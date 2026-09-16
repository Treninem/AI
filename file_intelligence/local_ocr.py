from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image

OCR_LANGUAGES = os.getenv("AURORAFOX_OCR_LANGUAGES", "rus+eng")
OCR_TIMEOUT_SECONDS = int(os.getenv("AURORAFOX_OCR_TIMEOUT_SECONDS", "90"))
OCR_MAX_PIXELS = int(os.getenv("AURORAFOX_OCR_MAX_PIXELS", str(16_000_000)))
OCR_MAX_OUTPUT_CHARS = int(os.getenv("AURORAFOX_OCR_MAX_OUTPUT_CHARS", "200000"))
OCR_PSM = int(os.getenv("AURORAFOX_OCR_PSM", "6"))


@dataclass(frozen=True)
class OcrRuntime:
    executable: Path | None
    tessdata_dir: Path | None
    languages: tuple[str, ...]

    @property
    def available(self) -> bool:
        return self.executable is not None and self.tessdata_dir is not None and bool(self.languages)


def _module_root() -> Path:
    return Path(__file__).resolve().parent


def _candidate_executables() -> list[Path]:
    configured = os.getenv("AURORAFOX_OCR_TESSERACT", "").strip()
    roots = [
        _module_root() / "ocr_runtime" / "tesseract.exe",
        _module_root() / "ocr_runtime" / "bin" / "tesseract.exe",
        _module_root() / "ocr_runtime" / "tesseract",
    ]
    if configured:
        roots.insert(0, Path(configured).expanduser())
    path_hit = shutil.which("tesseract")
    if path_hit:
        roots.append(Path(path_hit))
    unique: list[Path] = []
    seen: set[str] = set()
    for item in roots:
        try:
            key = str(item.resolve())
        except OSError:
            key = str(item)
        if key not in seen:
            seen.add(key)
            unique.append(item)
    return unique


def _candidate_tessdata(executable: Path | None) -> list[Path]:
    configured = os.getenv("AURORAFOX_OCR_TESSDATA", "").strip()
    roots: list[Path] = []
    if configured:
        roots.append(Path(configured).expanduser())
    roots.append(_module_root() / "ocr_runtime" / "tessdata")
    if executable is not None:
        roots += [executable.parent / "tessdata", executable.parent.parent / "share" / "tessdata"]
    # Linux distributions commonly keep traineddata under a versioned
    # /usr/share/tesseract-ocr/<version>/tessdata directory instead of next to
    # /usr/bin/tesseract. Discover those local directories without invoking the
    # engine or requiring network access. Homebrew paths are included for
    # developer/test hosts; production Windows uses the bundled runtime above.
    distro_root = Path("/usr/share/tesseract-ocr")
    if distro_root.is_dir():
        roots.extend(sorted(distro_root.glob("*/tessdata"), reverse=True))
    roots += [
        Path("/usr/share/tessdata"),
        Path("/usr/local/share/tessdata"),
        Path("/opt/homebrew/share/tessdata"),
    ]
    prefix = os.getenv("TESSDATA_PREFIX", "").strip()
    if prefix:
        p = Path(prefix).expanduser()
        roots += [p, p / "tessdata"]
    unique: list[Path] = []
    seen: set[str] = set()
    for item in roots:
        try:
            key = str(item.resolve())
        except OSError:
            key = str(item)
        if key not in seen:
            seen.add(key)
            unique.append(item)
    return unique


def runtime() -> OcrRuntime:
    executable = next((p for p in _candidate_executables() if p.is_file()), None)
    wanted = tuple(part for part in OCR_LANGUAGES.split("+") if part)
    tessdata_dir: Path | None = None
    present: tuple[str, ...] = ()
    for candidate in _candidate_tessdata(executable):
        if not candidate.is_dir():
            continue
        found = tuple(lang for lang in wanted if (candidate / f"{lang}.traineddata").is_file())
        if found:
            tessdata_dir = candidate
            present = found
            if len(found) == len(wanted):
                break
    return OcrRuntime(executable=executable, tessdata_dir=tessdata_dir, languages=present)


def health() -> dict[str, Any]:
    rt = runtime()
    return {
        "available": rt.available and set(rt.languages) >= set(OCR_LANGUAGES.split("+")),
        "engine": "tesseract-local",
        "executable": str(rt.executable) if rt.executable else "",
        "tessdata_dir": str(rt.tessdata_dir) if rt.tessdata_dir else "",
        "languages": list(rt.languages),
        "requested_languages": OCR_LANGUAGES.split("+"),
        "network_required": False,
        "external_ai_required": False,
        "max_pixels": OCR_MAX_PIXELS,
        "timeout_seconds": OCR_TIMEOUT_SECONDS,
    }


def _prepare_image(image: Image.Image) -> Image.Image:
    # Always own an independent frame so callers can close/reuse their source.
    frame = image.copy()
    if getattr(frame, "n_frames", 1) > 1:
        try:
            frame.seek(0)
        except Exception:
            pass
    if frame.mode not in ("L", "RGB"):
        if "A" in frame.getbands():
            previous = frame
            background = Image.new("RGB", frame.size, "white")
            alpha = frame.getchannel("A")
            try:
                background.paste(frame.convert("RGB"), mask=alpha)
            finally:
                alpha.close()
            frame = background
            previous.close()
        else:
            previous = frame
            frame = previous.convert("RGB")
            previous.close()
    pixels = max(1, frame.width * frame.height)
    if pixels > OCR_MAX_PIXELS:
        ratio = (OCR_MAX_PIXELS / float(pixels)) ** 0.5
        width = max(1, int(frame.width * ratio))
        height = max(1, int(frame.height * ratio))
        previous = frame
        frame = previous.resize((width, height), Image.Resampling.LANCZOS)
        previous.close()
    return frame


def recognize_image(image: Image.Image, *, page_number: int | None = None) -> dict[str, Any]:
    rt = runtime()
    requested = tuple(part for part in OCR_LANGUAGES.split("+") if part)
    missing = [lang for lang in requested if lang not in rt.languages]
    if rt.executable is None or rt.tessdata_dir is None or missing:
        return {
            "ok": False,
            "available": False,
            "text": "",
            "error": "Local OCR runtime is unavailable" if not missing else f"Local OCR language data missing: {','.join(missing)}",
            "page": page_number,
            "engine": "tesseract-local",
            "languages": list(rt.languages),
            "network_required": False,
            "external_ai_required": False,
        }

    frame = _prepare_image(image)
    try:
        env = os.environ.copy()
        env["TESSDATA_PREFIX"] = str(rt.tessdata_dir)
        env.setdefault("OMP_THREAD_LIMIT", "2")
        with tempfile.TemporaryDirectory(prefix="aurorafox-ocr-") as tmp:
            input_path = Path(tmp) / "page.png"
            frame.save(input_path, format="PNG", optimize=False)
            command = [
                str(rt.executable), str(input_path), "stdout", "--tessdata-dir", str(rt.tessdata_dir),
                "-l", OCR_LANGUAGES, "--psm", str(OCR_PSM),
            ]
            try:
                proc = subprocess.run(
                    command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    timeout=OCR_TIMEOUT_SECONDS, check=False, shell=False, env=env,
                )
            except subprocess.TimeoutExpired:
                return {"ok": False, "available": True, "text": "", "error": f"Local OCR timed out after {OCR_TIMEOUT_SECONDS}s", "page": page_number, "engine": "tesseract-local", "languages": list(rt.languages), "network_required": False, "external_ai_required": False}
            except OSError as exc:
                return {"ok": False, "available": False, "text": "", "error": f"Local OCR could not start: {exc}", "page": page_number, "engine": "tesseract-local", "languages": list(rt.languages), "network_required": False, "external_ai_required": False}

        stderr = proc.stderr.decode("utf-8", errors="replace").strip()[:2000]
        if proc.returncode != 0:
            return {"ok": False, "available": True, "text": "", "error": f"Local OCR exited with code {proc.returncode}: {stderr}", "page": page_number, "engine": "tesseract-local", "languages": list(rt.languages), "network_required": False, "external_ai_required": False}

        text = proc.stdout.decode("utf-8", errors="replace").replace("\x0c", "").strip()
        truncated = len(text) > OCR_MAX_OUTPUT_CHARS
        if truncated:
            text = text[:OCR_MAX_OUTPUT_CHARS]
        return {
            "ok": True, "available": True, "text": text, "page": page_number,
            "engine": "tesseract-local", "languages": list(rt.languages),
            "width": frame.width, "height": frame.height, "truncated": truncated,
            "network_required": False, "external_ai_required": False, "stderr": stderr,
        }
    finally:
        frame.close()


def recognize_path(path: Path, *, page_number: int | None = None) -> dict[str, Any]:
    with Image.open(path) as image:
        return recognize_image(image, page_number=page_number)
