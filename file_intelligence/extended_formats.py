from __future__ import annotations

import html
import os
import shutil
import zipfile
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
from typing import Any, Callable
from urllib.parse import unquote
from xml.etree import ElementTree as ET

MAX_ARCHIVE_ENTRIES = int(os.getenv("AURORAFOX_ARCHIVE_MAX_ENTRIES", "5000"))
MAX_ARCHIVE_EXPANDED = int(os.getenv("AURORAFOX_ARCHIVE_MAX_EXPANDED", str(512 * 1024 * 1024)))
MAX_EPUB_CHAPTERS = int(os.getenv("AURORAFOX_EPUB_MAX_CHAPTERS", "2000"))
MAX_EMBEDDED_TEXT_BYTES = int(os.getenv("AURORAFOX_ARCHIVE_TEXT_ENTRY_MAX", str(4 * 1024 * 1024)))
MAX_ARCHIVE_TEXT_ENTRIES = int(os.getenv("AURORAFOX_ARCHIVE_TEXT_ENTRIES", "24"))

TEXT_INSIDE_ARCHIVE = {
    ".txt", ".md", ".json", ".csv", ".tsv", ".xml", ".html", ".htm", ".xhtml",
    ".py", ".gd", ".js", ".ts", ".css", ".yml", ".yaml", ".toml", ".ini", ".cfg", ".log",
}


class _TextHTMLParser(HTMLParser):
    _BLOCKS = {
        "p", "div", "section", "article", "main", "aside", "header", "footer", "nav",
        "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "pre", "br", "tr",
    }

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._skip = 0
        self._parts: list[str] = []
        self.links: list[tuple[str, str]] = []
        self._link_href = ""
        self._link_text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        if tag in {"script", "style", "svg", "template"}:
            self._skip += 1
            return
        if self._skip:
            return
        if tag in self._BLOCKS:
            self._parts.append("\n")
        if tag == "a":
            attrs_dict = {k.lower(): (v or "") for k, v in attrs}
            self._link_href = attrs_dict.get("href", "")
            self._link_text = []

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag in {"script", "style", "svg", "template"} and self._skip:
            self._skip -= 1
            return
        if self._skip:
            return
        if tag == "a" and self._link_href:
            label = " ".join("".join(self._link_text).split()).strip()
            if label:
                self.links.append((self._link_href, label))
            self._link_href = ""
            self._link_text = []
        if tag in self._BLOCKS:
            self._parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self._skip:
            return
        if self._link_href:
            self._link_text.append(data)
        self._parts.append(data)

    def text(self) -> str:
        lines = []
        for line in "".join(self._parts).replace("\r", "\n").split("\n"):
            clean = " ".join(html.unescape(line).split()).strip()
            if clean:
                lines.append(clean)
        return "\n".join(lines)


def _safe_member(name: str) -> str:
    normalized = unquote(str(name)).replace("\\", "/").lstrip("./")
    pure = PurePosixPath(normalized)
    if not normalized or pure.is_absolute() or ".." in pure.parts:
        raise ValueError(f"Unsafe archive path: {name}")
    if ":" in pure.parts[0]:
        raise ValueError(f"Unsafe archive path: {name}")
    return pure.as_posix()


def _decode_text(data: bytes) -> tuple[str, str]:
    for enc in ("utf-8-sig", "utf-8", "utf-16", "cp1251", "latin-1"):
        try:
            return data.decode(enc), enc
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace"), "utf-8-replace"


def _zip_limits(zf: zipfile.ZipFile) -> tuple[int, int]:
    infos = zf.infolist()
    if len(infos) > MAX_ARCHIVE_ENTRIES:
        raise ValueError(f"Container has more than {MAX_ARCHIVE_ENTRIES} entries")
    expanded = 0
    for info in infos:
        _safe_member(info.filename)
        if info.is_dir():
            continue
        expanded += max(0, int(info.file_size))
        if expanded > MAX_ARCHIVE_EXPANDED:
            raise ValueError(f"Expanded container exceeds {MAX_ARCHIVE_EXPANDED} bytes")
    return len(infos), expanded


def _find_first_local(root: ET.Element, local_name: str) -> ET.Element | None:
    for elem in root.iter():
        if elem.tag.rsplit("}", 1)[-1].lower() == local_name.lower():
            return elem
    return None


def _find_all_local(root: ET.Element, local_name: str) -> list[ET.Element]:
    return [elem for elem in root.iter() if elem.tag.rsplit("}", 1)[-1].lower() == local_name.lower()]


def _epub_nav(zf: zipfile.ZipFile, opf_dir: PurePosixPath, manifest: dict[str, dict[str, str]]) -> list[dict[str, str]]:
    nav_item = next((row for row in manifest.values() if "nav" in row.get("properties", "").split()), None)
    if nav_item:
        nav_path = _safe_member((opf_dir / nav_item["href"]).as_posix())
        try:
            raw = zf.read(nav_path)
            text, _ = _decode_text(raw)
            parser = _TextHTMLParser()
            parser.feed(text)
            return [{"title": label, "href": href} for href, label in parser.links[:1000]]
        except Exception:
            pass

    ncx_item = next((row for row in manifest.values() if row.get("media_type") == "application/x-dtbncx+xml"), None)
    if not ncx_item:
        return []
    ncx_path = _safe_member((opf_dir / ncx_item["href"]).as_posix())
    try:
        root = ET.fromstring(zf.read(ncx_path))
    except Exception:
        return []
    out: list[dict[str, str]] = []
    for nav_point in _find_all_local(root, "navPoint")[:1000]:
        label_node = _find_first_local(nav_point, "text")
        content_node = _find_first_local(nav_point, "content")
        label = " ".join("".join(label_node.itertext()).split()) if label_node is not None else ""
        href = content_node.attrib.get("src", "") if content_node is not None else ""
        if label:
            out.append({"title": label, "href": href})
    return out


def analyze_epub(path: Path) -> tuple[str, dict[str, Any], list[str]]:
    warnings: list[str] = []
    if not zipfile.is_zipfile(path):
        raise ValueError("EPUB is not a valid ZIP container")
    with zipfile.ZipFile(path) as zf:
        entries, expanded = _zip_limits(zf)
        try:
            container = ET.fromstring(zf.read("META-INF/container.xml"))
        except KeyError as exc:
            raise ValueError("EPUB META-INF/container.xml is missing") from exc
        rootfile = _find_first_local(container, "rootfile")
        if rootfile is None:
            raise ValueError("EPUB rootfile is missing")
        opf_path = _safe_member(rootfile.attrib.get("full-path", ""))
        if not opf_path:
            raise ValueError("EPUB OPF path is empty")
        try:
            opf = ET.fromstring(zf.read(opf_path))
        except KeyError as exc:
            raise ValueError(f"EPUB OPF file is missing: {opf_path}") from exc

        opf_dir = PurePosixPath(opf_path).parent
        metadata_node = _find_first_local(opf, "metadata")
        title = ""
        authors: list[str] = []
        language = ""
        if metadata_node is not None:
            title_node = _find_first_local(metadata_node, "title")
            language_node = _find_first_local(metadata_node, "language")
            title = " ".join("".join(title_node.itertext()).split()) if title_node is not None else ""
            language = " ".join("".join(language_node.itertext()).split()) if language_node is not None else ""
            for creator in _find_all_local(metadata_node, "creator"):
                value = " ".join("".join(creator.itertext()).split())
                if value:
                    authors.append(value)

        manifest: dict[str, dict[str, str]] = {}
        manifest_node = _find_first_local(opf, "manifest")
        if manifest_node is None:
            raise ValueError("EPUB manifest is missing")
        for item in _find_all_local(manifest_node, "item"):
            item_id = item.attrib.get("id", "").strip()
            href = item.attrib.get("href", "").strip()
            if not item_id or not href:
                continue
            manifest[item_id] = {
                "href": href,
                "media_type": item.attrib.get("media-type", ""),
                "properties": item.attrib.get("properties", ""),
            }

        spine_node = _find_first_local(opf, "spine")
        if spine_node is None:
            raise ValueError("EPUB spine is missing")
        spine_ids = [row.attrib.get("idref", "").strip() for row in _find_all_local(spine_node, "itemref")]
        spine_ids = [item_id for item_id in spine_ids if item_id]
        if len(spine_ids) > MAX_EPUB_CHAPTERS:
            warnings.append(f"EPUB spine contains more than {MAX_EPUB_CHAPTERS} items; reading was truncated.")
            spine_ids = spine_ids[:MAX_EPUB_CHAPTERS]

        parts: list[str] = []
        chapters: list[dict[str, Any]] = []
        for order, item_id in enumerate(spine_ids, start=1):
            item = manifest.get(item_id)
            if not item:
                warnings.append(f"EPUB spine references unknown item: {item_id}")
                continue
            chapter_path = _safe_member((opf_dir / item["href"]).as_posix())
            try:
                raw = zf.read(chapter_path)
            except KeyError:
                warnings.append(f"EPUB chapter is missing: {chapter_path}")
                continue
            if len(raw) > MAX_EMBEDDED_TEXT_BYTES:
                warnings.append(f"EPUB chapter is too large and was skipped: {chapter_path}")
                continue
            chapter_html, encoding = _decode_text(raw)
            parser = _TextHTMLParser()
            try:
                parser.feed(chapter_html)
                chapter_text = parser.text()
            except Exception as exc:
                warnings.append(f"EPUB chapter parse error {chapter_path}: {exc}")
                continue
            if chapter_text:
                parts.append(f"\n### Глава {order}: {chapter_path}\n{chapter_text}")
            chapters.append({
                "order": order,
                "id": item_id,
                "path": chapter_path,
                "encoding": encoding,
                "chars": len(chapter_text),
            })

        toc = _epub_nav(zf, opf_dir, manifest)
        image_count = sum(1 for row in manifest.values() if row.get("media_type", "").startswith("image/"))
        metadata = {
            "title": title,
            "authors": authors,
            "language": language,
            "opf_path": opf_path,
            "chapters": chapters,
            "chapter_count": len(chapters),
            "toc": toc,
            "toc_count": len(toc),
            "images": image_count,
            "container_entries": entries,
            "expanded_bytes": expanded,
        }
        if not parts:
            warnings.append("EPUB spine was parsed, but no readable chapter text was found.")
        return "\n".join(parts).strip(), metadata, warnings


def _configure_rar_backend(rarfile_module: Any) -> str:
    candidates = [
        ("unrar", "UNRAR_TOOL"),
        ("7zz", "SEVENZIP2_TOOL"),
        ("7z", "SEVENZIP_TOOL"),
        ("bsdtar", "BSDTAR_TOOL"),
        ("tar", "BSDTAR_TOOL"),
    ]
    for executable, attr in candidates:
        resolved = shutil.which(executable)
        if resolved:
            setattr(rarfile_module, attr, resolved)
            return f"{executable}:{resolved}"
    return "none"


def analyze_rar(path: Path) -> tuple[str, dict[str, Any], list[str]]:
    import rarfile

    warnings: list[str] = []
    backend = _configure_rar_backend(rarfile)
    entries: list[dict[str, Any]] = []
    expanded = 0
    text_parts: list[str] = []
    extracted_text_entries = 0

    if not rarfile.is_rarfile(str(path)):
        raise ValueError("Invalid RAR3/RAR5 archive")

    with rarfile.RarFile(str(path)) as rf:
        infos = rf.infolist()
        if len(infos) > MAX_ARCHIVE_ENTRIES:
            warnings.append(f"RAR contains more than {MAX_ARCHIVE_ENTRIES} entries; listing was truncated.")
            infos = infos[:MAX_ARCHIVE_ENTRIES]
        for info in infos:
            name = _safe_member(info.filename)
            is_dir = bool(info.is_dir())
            size = max(0, int(getattr(info, "file_size", 0) or 0))
            compressed = max(0, int(getattr(info, "compress_size", 0) or 0))
            encrypted = bool(info.needs_password())
            entries.append({
                "path": name,
                "size": size,
                "compressed_size": compressed,
                "dir": is_dir,
                "encrypted": encrypted,
            })
            if not is_dir:
                expanded += size
            if expanded > MAX_ARCHIVE_EXPANDED:
                raise ValueError(f"RAR expanded size exceeds {MAX_ARCHIVE_EXPANDED} bytes")

        for info in infos:
            if extracted_text_entries >= MAX_ARCHIVE_TEXT_ENTRIES:
                break
            if info.is_dir() or info.needs_password():
                continue
            name = _safe_member(info.filename)
            if Path(name).suffix.lower() not in TEXT_INSIDE_ARCHIVE:
                continue
            size = max(0, int(getattr(info, "file_size", 0) or 0))
            if size <= 0 or size > MAX_EMBEDDED_TEXT_BYTES:
                continue
            try:
                data = rf.read(info)
            except Exception as exc:
                warnings.append(f"RAR text extraction unavailable for {name}: {exc}")
                continue
            decoded, encoding = _decode_text(data)
            text_parts.append(f"\n### {name} [{encoding}]\n{decoded}")
            extracted_text_entries += 1

    if backend == "none":
        warnings.append("RAR structure was parsed in Python; compressed-entry extraction backend was not found in PATH.")
    listing = [f"{('[DIR] ' if row['dir'] else '')}{row['path']} ({row['size']} B){' [ENCRYPTED]' if row['encrypted'] else ''}" for row in entries]
    content = "### Содержимое RAR\n" + "\n".join(listing)
    if text_parts:
        content += "\n\n### Извлечённые текстовые файлы\n" + "\n".join(text_parts)
    metadata = {
        "entries": len(entries),
        "expanded_bytes": expanded,
        "encrypted_entries": sum(1 for row in entries if row["encrypted"]),
        "text_entries_extracted": extracted_text_entries,
        "rar_backend": backend,
        "format": "RAR",
    }
    return content, metadata, warnings


def extend_analyze(original: Callable[[Path, str, bool], dict[str, Any]]) -> Callable[[Path, str, bool], dict[str, Any]]:
    def analyze(path: Path, question: str, visual: bool) -> dict[str, Any]:
        ext = path.suffix.lower()
        if ext == ".epub":
            text, metadata, warnings = analyze_epub(path)
            base = {"name": path.name, "extension": ext, "size": path.stat().st_size}
            base.update(metadata)
            return {"kind": "ebook", "text": text, "metadata": base, "warnings": warnings}
        if ext == ".rar":
            text, metadata, warnings = analyze_rar(path)
            base = {"name": path.name, "extension": ext, "size": path.stat().st_size}
            base.update(metadata)
            return {"kind": "archive", "text": text, "metadata": base, "warnings": warnings}
        return original(path, question, visual)

    return analyze
