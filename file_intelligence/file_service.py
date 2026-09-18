from __future__ import annotations

import base64
import hashlib
import io
import json
import logging
import os
import subprocess
import tarfile
import tempfile
import time
import zipfile
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET

import requests
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from extended_formats import analyze_epub, analyze_rar

from local_ocr import health as local_ocr_health
from local_ocr import recognize_image as local_ocr_image

HOST = os.getenv("AURORAFOX_FILES_HOST", "127.0.0.1")
PORT = int(os.getenv("AURORAFOX_FILES_PORT", "8767"))
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
VISION_MODEL = os.getenv("AURORAFOX_VISION_MODEL", "qwen3-vl:8b")
VOICE_URL = os.getenv("AURORAFOX_VOICE_URL", "http://127.0.0.1:8765").rstrip("/")
USER_ROOT = Path(os.getenv("AURORAFOX_USER_DIR", str(Path.home() / ".aurorafox"))).resolve()
CACHE_DIR = USER_ROOT / "file_cache"
LOG_DIR = USER_ROOT / "logs"
CACHE_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)

MAX_FILE_BYTES = int(os.getenv("AURORAFOX_FILE_MAX_BYTES", str(1024 * 1024 * 1024)))
MAX_TEXT_CHARS = int(os.getenv("AURORAFOX_FILE_MAX_TEXT", "160000"))
MAX_ARCHIVE_ENTRIES = int(os.getenv("AURORAFOX_ARCHIVE_MAX_ENTRIES", "5000"))
MAX_ARCHIVE_EXPANDED = int(os.getenv("AURORAFOX_ARCHIVE_MAX_EXPANDED", str(512 * 1024 * 1024)))
MAX_TREE_ITEMS = 5000
MAX_PDF_BYTES = int(os.getenv("AURORAFOX_OCR_MAX_PDF_BYTES", str(256 * 1024 * 1024)))
MAX_PDF_PAGES = int(os.getenv("AURORAFOX_OCR_MAX_PDF_PAGES", "1000"))
MAX_OCR_PAGES = int(os.getenv("AURORAFOX_OCR_MAX_PAGES", "500"))
MAX_PDF_RENDER_PIXELS = int(os.getenv("AURORAFOX_OCR_MAX_RENDER_PIXELS", str(8_000_000)))
MIN_PDF_RENDER_SCALE = 0.01

logging.basicConfig(filename=LOG_DIR / "aurora_files.log", level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", encoding="utf-8")
log = logging.getLogger("aurora_files")
app = FastAPI(title="AuroraFox File Intelligence", version="1.2.0")


class AnalyzeRequest(BaseModel):
    path: str = Field(min_length=1, max_length=8192)
    question: str = Field(default="", max_length=12000)
    visual: bool = True
    max_chars: int = Field(default=MAX_TEXT_CHARS, ge=2000, le=500000)


class TreeRequest(BaseModel):
    path: str = Field(min_length=1, max_length=8192)
    max_items: int = Field(default=2000, ge=1, le=MAX_TREE_ITEMS)


class CacheSearchRequest(BaseModel):
    query: str = Field(min_length=1, max_length=1000)
    limit: int = Field(default=20, ge=1, le=100)


TEXT_EXT = {
    ".txt", ".md", ".json", ".csv", ".tsv", ".gd", ".py", ".js", ".ts", ".tsx", ".jsx", ".html", ".css",
    ".scss", ".xml", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".log", ".shader", ".glsl", ".cpp", ".c",
    ".h", ".hpp", ".cs", ".java", ".kt", ".rs", ".go", ".php", ".rb", ".lua", ".swift", ".dart", ".sql",
    ".sh", ".ps1", ".r", ".jl", ".ex", ".exs",
}
IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".tif", ".tiff"}
AUDIO_EXT = {".wav", ".mp3", ".ogg", ".flac", ".m4a", ".aac", ".opus"}
VIDEO_EXT = {".mp4", ".mkv", ".webm", ".mov", ".avi", ".m4v"}
ARCHIVE_EXT = {".zip", ".7z", ".tar", ".gz", ".tgz", ".bz2", ".tbz2", ".xz", ".txz"}


def _safe_file(path: str) -> Path:
    try:
        p = Path(path).expanduser().resolve(strict=True)
    except Exception as exc:
        raise HTTPException(404, f"File not found: {path}") from exc
    if not p.is_file():
        raise HTTPException(400, "Path is not a file")
    size = p.stat().st_size
    if size > MAX_FILE_BYTES:
        raise HTTPException(413, f"File is too large: {size} bytes")
    return p


def _safe_dir(path: str) -> Path:
    try:
        p = Path(path).expanduser().resolve(strict=True)
    except Exception as exc:
        raise HTTPException(404, f"Directory not found: {path}") from exc
    if not p.is_dir():
        raise HTTPException(400, "Path is not a directory")
    return p


def _cache_key(path: Path, question: str, visual: bool, max_chars: int) -> str:
    st = path.stat()
    raw = f"{path}|{st.st_size}|{st.st_mtime_ns}|{question}|{visual}|{max_chars}|v3-local-ocr-bounded"
    return hashlib.sha256(raw.encode("utf-8", errors="replace")).hexdigest()


def _cache_get(key: str) -> dict[str, Any] | None:
    p = CACHE_DIR / f"{key}.json"
    if not p.is_file(): return None
    try:
        data = json.loads(p.read_text(encoding="utf-8")); p.touch()
        return data if isinstance(data, dict) else None
    except Exception: return None


def _cache_put(key: str, payload: dict[str, Any]) -> None:
    target = CACHE_DIR / f"{key}.json"
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    _trim_cache(512 * 1024 * 1024)


def _trim_cache(limit: int) -> None:
    files = sorted(CACHE_DIR.glob("*.json"), key=lambda p: p.stat().st_mtime)
    total = sum(p.stat().st_size for p in files)
    while files and total > limit:
        p = files.pop(0); total -= p.stat().st_size; p.unlink(missing_ok=True)


def _truncate(text: str, limit: int) -> tuple[str, bool]:
    if len(text) <= limit: return text, False
    return text[:limit] + "\n\n[Обрезано AuroraFox: достигнут лимит контекста]", True


def _read_text(path: Path) -> tuple[str, str]:
    raw = path.read_bytes()
    for enc in ("utf-8-sig", "utf-8", "cp1251", "utf-16", "latin-1"):
        try: return raw.decode(enc), enc
        except UnicodeDecodeError: continue
    return raw.decode("utf-8", errors="replace"), "utf-8-replace"


def _text_from_docx(path: Path) -> tuple[str, dict[str, Any]]:
    from docx import Document
    doc = Document(str(path)); parts: list[str] = [p.text for p in doc.paragraphs if p.text.strip()]; tables = 0
    for table in doc.tables:
        tables += 1
        for row in table.rows: parts.append(" | ".join(cell.text.strip() for cell in row.cells))
    return "\n".join(parts), {"paragraphs": len(doc.paragraphs), "tables": tables}


def _text_from_xlsx(path: Path) -> tuple[str, dict[str, Any]]:
    from openpyxl import load_workbook
    wb = load_workbook(filename=str(path), read_only=True, data_only=True); parts: list[str] = []; sheets = []; cells = 0
    try:
        for ws in wb.worksheets:
            parts.append(f"\n### Лист: {ws.title}"); rows = 0
            for row in ws.iter_rows(values_only=True):
                values = ["" if v is None else str(v) for v in row]
                if any(values): parts.append("\t".join(values)); rows += 1; cells += len(values)
                if cells >= 50000: parts.append("[Таблица обрезана: лимит 50000 ячеек]"); break
            sheets.append({"name": ws.title, "rows_read": rows})
            if cells >= 50000: break
    finally: wb.close()
    return "\n".join(parts), {"sheets": sheets, "cells_read": cells}


def _text_from_xls(path: Path) -> tuple[str, dict[str, Any]]:
    import xlrd
    book = xlrd.open_workbook(str(path), on_demand=True); parts = []; sheets = []; cells = 0
    try:
        for sheet in book.sheets():
            parts.append(f"\n### Лист: {sheet.name}")
            for r in range(min(sheet.nrows, 10000)):
                values = [str(sheet.cell_value(r, c)) for c in range(sheet.ncols)]
                if any(values): parts.append("\t".join(values)); cells += len(values)
                if cells >= 50000: parts.append("[Таблица обрезана: лимит 50000 ячеек]"); break
            sheets.append({"name": sheet.name, "rows": sheet.nrows, "cols": sheet.ncols})
            if cells >= 50000: break
    finally: book.release_resources()
    return "\n".join(parts), {"sheets": sheets, "cells_read": cells}


def _text_from_pptx(path: Path) -> tuple[str, dict[str, Any]]:
    from pptx import Presentation
    prs = Presentation(str(path)); parts: list[str] = []
    for idx, slide in enumerate(prs.slides, start=1):
        slide_parts = []
        for shape in slide.shapes:
            if getattr(shape, "has_text_frame", False) and shape.text.strip(): slide_parts.append(shape.text.strip())
            if getattr(shape, "has_table", False):
                for row in shape.table.rows: slide_parts.append(" | ".join(cell.text.strip() for cell in row.cells))
        if slide_parts: parts.append(f"\n### Слайд {idx}\n" + "\n".join(slide_parts))
    return "\n".join(parts), {"slides": len(prs.slides)}


def _text_from_open_document(path: Path) -> tuple[str, dict[str, Any]]:
    if not zipfile.is_zipfile(path): raise ValueError("Invalid OpenDocument container")
    with zipfile.ZipFile(path) as zf: raw = zf.read("content.xml")
    root = ET.fromstring(raw); chunks = [elem.text.strip() for elem in root.iter() if elem.text and elem.text.strip()]
    return "\n".join(chunks), {"xml_nodes": sum(1 for _ in root.iter())}


def _usable_pdf_text(text: str) -> bool:
    compact = "".join(ch for ch in text if not ch.isspace())
    return len(compact) >= 12 and sum(1 for ch in compact if ch.isalnum()) >= 4


def _render_pdf_page(pdf: Any, index: int):
    page = pdf[index]
    try:
        width, height = page.get_size()
        width = float(width); height = float(height)
        if not (width > 0.0 and height > 0.0):
            raise ValueError("PDF page has invalid dimensions for local OCR")
        default_scale = 2.0
        projected = width * height * default_scale * default_scale
        scale = default_scale
        if projected > MAX_PDF_RENDER_PIXELS:
            scale *= (MAX_PDF_RENDER_PIXELS / projected) ** 0.5
        if not (scale >= MIN_PDF_RENDER_SCALE):
            raise ValueError("PDF page dimensions exceed safe local OCR render limit")
        bounded_pixels = width * height * scale * scale
        if not (bounded_pixels <= MAX_PDF_RENDER_PIXELS * 1.01):
            raise ValueError("PDF page render budget could not be bounded safely")
        bitmap = page.render(scale=scale)
        try: return bitmap.to_pil().copy()
        finally: bitmap.close()
    finally: page.close()


def _append_pdf_page(out: io.StringIO, page_no: int, text: str, limit: int) -> bool:
    prefix = "\n\n" if out.tell() else ""
    block = f"{prefix}### Страница {page_no}\n{text}"
    remaining = max(0, limit - out.tell())
    if remaining <= 0:
        return False
    if len(block) <= remaining:
        out.write(block)
        return True
    out.write(block[:remaining])
    return False


def _pdf_extract(path: Path, visual: bool, question: str, max_chars: int = MAX_TEXT_CHARS) -> tuple[str, dict[str, Any], list[str]]:
    del visual, question
    from pypdf import PdfReader
    if path.stat().st_size > MAX_PDF_BYTES: raise ValueError(f"PDF exceeds local OCR limit of {MAX_PDF_BYTES} bytes")
    reader = PdfReader(str(path), strict=False); page_count = len(reader.pages)
    if page_count > MAX_PDF_PAGES: raise ValueError(f"PDF has {page_count} pages; limit is {MAX_PDF_PAGES}")
    output_limit = max(1, int(max_chars))
    warnings: list[str] = []; out = io.StringIO(); page_sources: list[dict[str, Any]] = []
    ocr_status = local_ocr_health(); pdfium_doc = None; ocr_pages = text_pages = empty_pages = failed_ocr_pages = 0
    pages_processed = 0; output_truncated = False; ocr_limit_reached = False
    try:
        for idx, page in enumerate(reader.pages):
            if out.tell() >= output_limit:
                output_truncated = True
                break
            page_no = idx + 1; pages_processed = page_no
            try: layer_text = (page.extract_text() or "").strip()
            except Exception as exc: layer_text = ""; warnings.append(f"Страница {page_no}: ошибка text layer: {exc}")
            if _usable_pdf_text(layer_text):
                text_pages += 1
                complete = _append_pdf_page(out, page_no, layer_text, output_limit)
                page_sources.append({"page": page_no, "source": "text_layer", "chars": len(layer_text), "stored_chars": min(len(layer_text), max(0, output_limit - out.tell() + min(len(layer_text), output_limit)))})
                if not complete:
                    output_truncated = True
                    break
                continue
            if ocr_pages >= MAX_OCR_PAGES:
                ocr_limit_reached = True
                empty_pages += int(not bool(layer_text)); page_sources.append({"page": page_no, "source": "ocr_limit", "chars": len(layer_text)})
                if layer_text and not _append_pdf_page(out, page_no, layer_text, output_limit):
                    output_truncated = True
                    break
                continue
            if not bool(ocr_status.get("available", False)):
                failed_ocr_pages += 1; empty_pages += int(not bool(layer_text)); page_sources.append({"page": page_no, "source": "ocr_unavailable", "chars": len(layer_text)})
                if layer_text and not _append_pdf_page(out, page_no, layer_text, output_limit):
                    output_truncated = True
                    break
                continue
            ocr_pages += 1
            try:
                if pdfium_doc is None:
                    import pypdfium2 as pdfium
                    pdfium_doc = pdfium.PdfDocument(str(path))
                image = _render_pdf_page(pdfium_doc, idx)
                try: result = local_ocr_image(image, page_number=page_no)
                finally: image.close()
                ocr_text = str(result.get("text", "")).strip() if result.get("ok") else ""
                if ocr_text:
                    complete = _append_pdf_page(out, page_no, ocr_text, output_limit)
                    page_sources.append({"page": page_no, "source": "ocr", "chars": len(ocr_text)})
                    if not complete:
                        output_truncated = True
                        break
                elif layer_text:
                    complete = _append_pdf_page(out, page_no, layer_text, output_limit)
                    page_sources.append({"page": page_no, "source": "text_layer_sparse", "chars": len(layer_text)})
                    if not complete:
                        output_truncated = True
                        break
                else:
                    empty_pages += 1
                    if result.get("ok"): page_sources.append({"page": page_no, "source": "empty", "chars": 0})
                    else: failed_ocr_pages += 1; page_sources.append({"page": page_no, "source": "ocr_error", "chars": 0, "error": str(result.get("error", ""))[:500]})
            except Exception as exc:
                failed_ocr_pages += 1; empty_pages += int(not bool(layer_text)); page_sources.append({"page": page_no, "source": "ocr_error", "chars": len(layer_text), "error": str(exc)[:500]})
                if layer_text and not _append_pdf_page(out, page_no, layer_text, output_limit):
                    output_truncated = True
                    break
                warnings.append(f"Страница {page_no}: локальный OCR недоступен: {exc}")
    finally:
        if pdfium_doc is not None: pdfium_doc.close()
    if failed_ocr_pages and not bool(ocr_status.get("available", False)): warnings.append("Локальный OCR-компонент отсутствует: text-layer страницы импортированы, сканированные страницы пропущены без падения приложения.")
    if ocr_limit_reached: warnings.append(f"OCR ограничен первыми {MAX_OCR_PAGES} страницами без usable text layer.")
    if output_truncated: warnings.append(f"Извлечение остановлено на лимите {output_limit} символов; необработанные страницы не рендерились и не отправлялись в OCR.")
    return out.getvalue(), {
        "pages": page_count, "pages_processed": pages_processed, "text_layer_pages": text_pages, "ocr_pages": ocr_pages,
        "empty_pages": empty_pages, "ocr_failed_pages": failed_ocr_pages, "page_sources": page_sources, "ocr": ocr_status,
        "engine": "pypdf+pypdfium2+tesseract-local", "offline": True, "streaming_pages": True,
        "output_limit_chars": output_limit, "output_truncated": output_truncated,
        "untrusted_document": True, "content_authority": "data_only", "external_ai_required": False,
    }, warnings


def _vision_bytes(data: bytes, prompt: str) -> str:
    payload = {"model": VISION_MODEL, "stream": False, "messages": [{"role": "user", "content": prompt, "images": [base64.b64encode(data).decode("ascii")]}], "options": {"temperature": 0.1}}
    r = requests.post(f"{OLLAMA_URL}/api/chat", json=payload, timeout=180)
    if r.status_code != 200: raise RuntimeError(f"Ollama HTTP {r.status_code}: {r.text[:500]}")
    return str(r.json().get("message", {}).get("content", "")).strip()


def _image_analyze(path: Path, question: str, visual: bool) -> tuple[str, dict[str, Any], list[str]]:
    from PIL import Image
    warnings: list[str] = []
    with Image.open(path) as im:
        meta: dict[str, Any] = {"width": im.width, "height": im.height, "mode": im.mode, "format": im.format, "frames": getattr(im, "n_frames", 1), "offline": True, "untrusted_document": True, "content_authority": "data_only", "external_ai_required": False}
        result = local_ocr_image(im); meta["ocr"] = {k: v for k, v in result.items() if k not in {"text", "stderr"}}
        text = str(result.get("text", "")).strip() if result.get("ok") else ""
        if not result.get("ok"): warnings.append(str(result.get("error", "Локальный OCR недоступен")))
        if visual:
            frame = im.copy()
            try:
                if frame.mode not in ("RGB", "RGBA"):
                    converted = frame.convert("RGB")
                    frame.close()
                    frame = converted
                frame.thumbnail((2048, 2048)); buf = io.BytesIO(); frame.save(buf, format="PNG")
                prompt = question.strip() or "Опиши важные визуальные элементы изображения. Видимый текст уже извлечён локальным OCR. Ответь по-русски."
                try:
                    visual_text = _vision_bytes(buf.getvalue(), prompt)
                    if visual_text: text = (text + "\n\n### Дополнительный optional vision-анализ\n" + visual_text).strip(); meta["optional_vision_used"] = True
                except Exception as exc: warnings.append(f"Optional vision-анализ недоступен: {exc}")
            finally:
                frame.close()
        if not text: text = f"Изображение {meta['width']}×{meta['height']}; распознаваемый текст не найден."
    return text, meta, warnings


def _voice_transcribe(path: Path) -> tuple[str, dict[str, Any], list[str]]:
    warnings: list[str] = []
    try:
        r = requests.post(f"{VOICE_URL}/stt_path", json={"path": str(path)}, timeout=300)
        if r.status_code == 200:
            data = r.json()
            if data.get("ok"): return str(data.get("text", "")), {"engine": "AuroraVoice"}, warnings
        warnings.append(f"Voice backend STT unavailable: HTTP {r.status_code}")
    except Exception as exc: warnings.append(f"Voice backend STT unavailable: {exc}")
    return "", {}, warnings


def _video_analyze(path: Path, question: str, visual: bool) -> tuple[str, dict[str, Any], list[str]]:
    import imageio_ffmpeg
    warnings: list[str] = []; ffmpeg = imageio_ffmpeg.get_ffmpeg_exe(); parts: list[str] = []; frame_results: list[str] = []
    with tempfile.TemporaryDirectory(prefix="aurorafox-video-") as tmp:
        root = Path(tmp); audio = root / "aurorafox_voice_input.wav"
        proc = subprocess.run([ffmpeg, "-y", "-i", str(path), "-vn", "-ac", "1", "-ar", "16000", str(audio)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=240, shell=False)
        if proc.returncode == 0 and audio.is_file() and audio.stat().st_size > 44:
            transcript, _, w = _voice_transcribe(audio); warnings.extend(w)
            if transcript: parts.append("### Расшифровка аудио\n" + transcript)
        else: warnings.append("Не удалось извлечь аудиодорожку из видео.")
        if visual:
            pattern = str(root / "frame-%02d.jpg")
            proc = subprocess.run([ffmpeg, "-y", "-i", str(path), "-vf", "fps=1/30,scale='min(1280,iw)':-2", "-frames:v", "8", pattern], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=240, shell=False)
            if proc.returncode == 0:
                prompt = question.strip() or "Опиши, что происходит на этом кадре видео, и прочитай важный видимый текст. Ответь по-русски."
                for frame in sorted(root.glob("frame-*.jpg"))[:8]:
                    try:
                        result = _vision_bytes(frame.read_bytes(), prompt)
                        if result: frame_results.append(f"{frame.stem}: {result}")
                    except Exception as exc: warnings.append(f"Vision-анализ кадра недоступен: {exc}"); break
    if frame_results: parts.append("### Выбранные кадры\n" + "\n".join(frame_results))
    return "\n\n".join(parts), {"frames_analyzed": len(frame_results)}, warnings


def _archive_listing(path: Path) -> tuple[str, dict[str, Any], list[str]]:
    warnings: list[str] = []; entries: list[dict[str, Any]] = []; total = 0
    def add(name: str, size: int, is_dir: bool = False) -> None:
        nonlocal total
        normalized = name.replace("\\", "/"); p = Path(normalized); unsafe = p.is_absolute() or ".." in p.parts
        entries.append({"path": normalized, "size": int(size), "dir": is_dir, "unsafe": unsafe})
        if not is_dir: total += max(0, int(size))
    suffix = path.suffix.lower()
    if suffix == ".zip":
        with zipfile.ZipFile(path) as zf:
            for info in zf.infolist()[:MAX_ARCHIVE_ENTRIES + 1]: add(info.filename, info.file_size, info.is_dir())
    elif suffix == ".7z":
        import py7zr
        with py7zr.SevenZipFile(path, mode="r") as zf:
            for info in zf.list()[:MAX_ARCHIVE_ENTRIES + 1]: add(str(info.filename), int(getattr(info, "uncompressed", 0) or 0), bool(getattr(info, "is_directory", False)))
    elif tarfile.is_tarfile(path):
        with tarfile.open(path, mode="r:*") as tf:
            for info in tf.getmembers()[:MAX_ARCHIVE_ENTRIES + 1]: add(info.name, info.size, info.isdir())
    else: raise ValueError("Формат архива не поддерживается безопасным локальным обработчиком")
    if len(entries) > MAX_ARCHIVE_ENTRIES: warnings.append(f"Архив содержит больше {MAX_ARCHIVE_ENTRIES} записей; список обрезан."); entries = entries[:MAX_ARCHIVE_ENTRIES]
    unsafe_count = sum(1 for e in entries if e["unsafe"])
    if unsafe_count: warnings.append(f"Обнаружено потенциально небезопасных путей: {unsafe_count}; распаковка таких путей запрещена.")
    if total > MAX_ARCHIVE_EXPANDED: warnings.append(f"Заявленный распакованный размер превышает лимит {MAX_ARCHIVE_EXPANDED} байт; автоматическая распаковка запрещена.")
    text_lines = [f"{('[DIR] ' if e['dir'] else '')}{e['path']} ({e['size']} B){' [UNSAFE]' if e['unsafe'] else ''}" for e in entries]
    return "\n".join(text_lines), {"entries": len(entries), "expanded_bytes": total, "unsafe_entries": unsafe_count}, warnings


def _analyze(path: Path, question: str, visual: bool, max_chars: int = MAX_TEXT_CHARS) -> dict[str, Any]:
    ext = path.suffix.lower(); warnings: list[str] = []; metadata: dict[str, Any] = {"name": path.name, "extension": ext, "size": path.stat().st_size}; text = ""; kind = "binary"
    if ext in TEXT_EXT: kind = "text/code"; text, encoding = _read_text(path); metadata["encoding"] = encoding
    elif ext == ".epub": kind = "ebook"; text, extra, warnings = analyze_epub(path, max_chars=max_chars); metadata.update(extra)
    elif ext == ".rar": kind = "archive"; text, extra, warnings = analyze_rar(path, max_chars=max_chars); metadata.update(extra)
    elif ext == ".pdf": kind = "pdf"; text, extra, warnings = _pdf_extract(path, visual, question, max_chars=max_chars); metadata.update(extra)
    elif ext == ".docx": kind = "document"; text, extra = _text_from_docx(path); metadata.update(extra)
    elif ext == ".xlsx": kind = "spreadsheet"; text, extra = _text_from_xlsx(path); metadata.update(extra)
    elif ext == ".xls": kind = "spreadsheet"; text, extra = _text_from_xls(path); metadata.update(extra)
    elif ext == ".pptx": kind = "presentation"; text, extra = _text_from_pptx(path); metadata.update(extra)
    elif ext in {".odt", ".ods"}: kind = "document" if ext == ".odt" else "spreadsheet"; text, extra = _text_from_open_document(path); metadata.update(extra)
    elif ext in IMAGE_EXT: kind = "image"; text, extra, warnings = _image_analyze(path, question, visual); metadata.update(extra)
    elif ext in AUDIO_EXT: kind = "audio"; text, extra, warnings = _voice_transcribe(path); metadata.update(extra)
    elif ext in VIDEO_EXT: kind = "video"; text, extra, warnings = _video_analyze(path, question, visual); metadata.update(extra)
    elif ext in ARCHIVE_EXT or zipfile.is_zipfile(path) or tarfile.is_tarfile(path): kind = "archive"; text, extra, warnings = _archive_listing(path); metadata.update(extra)
    else:
        try:
            text, encoding = _read_text(path)
            if "\x00" not in text[:4096]: kind = "text"; metadata["encoding"] = encoding
            else: text = "Бинарный файл: содержимое не преобразовано в текст."
        except Exception: text = "Бинарный файл: содержимое не преобразовано в текст."
    return {"kind": kind, "text": text, "metadata": metadata, "warnings": warnings}


def _ollama_models() -> tuple[bool, list[str]]:
    try:
        r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=1.5)
        if r.status_code != 200: return False, []
        models = []
        for item in r.json().get("models", []):
            if isinstance(item, dict):
                name = str(item.get("name") or item.get("model") or "").strip()
                if name: models.append(name)
        return True, models
    except Exception: return False, []


def _model_installed(model: str, models: list[str]) -> bool:
    wanted = model.strip()
    if wanted in models: return True
    if ":" not in wanted: return any(name == wanted or name.startswith(wanted + ":") for name in models)
    return False


@app.get("/health")
def health() -> dict[str, Any]:
    ollama_online, installed_models = _ollama_models(); vision = ollama_online and _model_installed(VISION_MODEL, installed_models); voice = False
    try: voice = requests.get(f"{VOICE_URL}/health", timeout=1.5).status_code == 200
    except Exception: pass
    ocr = local_ocr_health()
    return {"ok": True, "backend": "AuroraFileIntelligence", "local_ocr": ocr, "ocr_available": bool(ocr.get("available", False)), "ocr_languages": ocr.get("languages", []), "ollama_online": ollama_online, "vision_online": vision, "vision_model": VISION_MODEL, "installed_models": installed_models, "voice_online": voice, "cache_dir": str(CACHE_DIR), "limits": {"max_file_bytes": MAX_FILE_BYTES, "max_text_chars": MAX_TEXT_CHARS, "max_pdf_bytes": MAX_PDF_BYTES, "max_pdf_pages": MAX_PDF_PAGES, "max_ocr_pages": MAX_OCR_PAGES, "max_pdf_render_pixels": MAX_PDF_RENDER_PIXELS}}


@app.post("/analyze")
def analyze(req: AnalyzeRequest) -> dict[str, Any]:
    path = _safe_file(req.path); key = _cache_key(path, req.question, req.visual, req.max_chars); cached = _cache_get(key)
    if cached is not None: cached["cached"] = True; return cached
    started = time.time()
    try:
        result = _analyze(path, req.question, req.visual, req.max_chars); text, outer_truncated = _truncate(str(result.get("text", "")), req.max_chars)
        metadata = result.get("metadata", {}) if isinstance(result.get("metadata", {}), dict) else {}
        truncated = bool(outer_truncated or metadata.get("output_truncated", False))
        payload = {"ok": True, "path": str(path), "name": path.name, "kind": result.get("kind", "unknown"), "content": text, "metadata": metadata, "warnings": result.get("warnings", []), "truncated": truncated, "cached": False, "elapsed_ms": int((time.time() - started) * 1000)}
        _cache_put(key, payload); log.info("analyzed name=%s kind=%s size=%d ms=%d", path.name, payload["kind"], path.stat().st_size, payload["elapsed_ms"]); return payload
    except HTTPException: raise
    except Exception as exc: log.exception("analysis failed path=%s", path); raise HTTPException(422, f"File analysis failed: {exc}") from exc


@app.post("/tree")
def tree(req: TreeRequest) -> dict[str, Any]:
    root = _safe_dir(req.path); items: list[dict[str, Any]] = []
    for p in root.rglob("*"):
        if len(items) >= req.max_items: break
        try: items.append({"path": p.relative_to(root).as_posix(), "dir": p.is_dir(), "size": p.stat().st_size if p.is_file() else 0})
        except OSError: continue
    return {"ok": True, "root": str(root), "items": items, "truncated": len(items) >= req.max_items}


@app.post("/cache/search")
def cache_search(req: CacheSearchRequest) -> dict[str, Any]:
    q = req.query.casefold(); results: list[dict[str, Any]] = []
    for p in sorted(CACHE_DIR.glob("*.json"), key=lambda x: x.stat().st_mtime, reverse=True):
        try: data = json.loads(p.read_text(encoding="utf-8"))
        except Exception: continue
        hay = (str(data.get("name", "")) + "\n" + str(data.get("content", ""))).casefold()
        if q in hay: results.append({"name": data.get("name", ""), "path": data.get("path", ""), "kind": data.get("kind", ""), "excerpt": str(data.get("content", ""))[:1200]})
        if len(results) >= req.limit: break
    return {"ok": True, "results": results}


@app.post("/cache/clear")
def clear_cache() -> dict[str, Any]:
    removed = 0
    for p in CACHE_DIR.glob("*.json"): p.unlink(missing_ok=True); removed += 1
    return {"ok": True, "removed": removed}


@app.post("/shutdown")
def shutdown() -> dict[str, Any]:
    import threading
    def die() -> None: time.sleep(0.15); os._exit(0)
    threading.Thread(target=die, daemon=True).start(); return {"ok": True}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT, log_level="warning")
