from __future__ import annotations

import sys
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "file_intelligence"))

import file_service  # noqa: E402
from file_service import _analyze, _archive_listing  # noqa: E402


def test_text_file(tmp_path: Path) -> None:
    path = tmp_path / "hello.txt"
    path.write_text("Привет, AuroraFox!", encoding="utf-8")
    result = _analyze(path, "", False)
    assert result["kind"] == "text/code"
    assert "AuroraFox" in result["text"]
    assert result["metadata"]["encoding"].startswith("utf-8")


def test_partial_cache_identity_changes_with_owner_extraction_policy(tmp_path, monkeypatch):
    path = tmp_path / 'same-source.txt'
    path.write_text('actual canonical source', encoding='utf-8')
    baseline = file_service._cache_key(path, '', False, 160000)
    for field in ['MAX_PDF_RENDER_PIXELS', 'MAX_PDF_PAGES', 'VIDEO_MAX_FRAMES', 'VIDEO_FRAME_MAX_WIDTH']:
        with monkeypatch.context() as patch:
            patch.setattr(file_service, field, getattr(file_service, field) + 1)
            assert file_service._cache_key(path, '', False, 160000) != baseline
    import extended_formats
    with monkeypatch.context() as patch:
        patch.setattr(extended_formats, 'MAX_EPUB_CHAPTERS', extended_formats.MAX_EPUB_CHAPTERS + 1)
        assert file_service._cache_key(path, '', False, 160000) != baseline


def test_owner_cache_budget_prunes_actual_disk_files(tmp_path, monkeypatch):
    monkeypatch.setattr(file_service, 'CACHE_DIR', tmp_path)
    monkeypatch.setattr(file_service, 'CACHE_MAX_BYTES', 1)
    file_service._cache_put('small', {'content': 'actual cached text'})
    assert list(tmp_path.glob('*.json')) == []


def test_docx_xlsx_pptx(tmp_path: Path) -> None:
    from docx import Document
    from openpyxl import Workbook
    from pptx import Presentation

    docx_path = tmp_path / "sample.docx"
    doc = Document()
    doc.add_paragraph("Документ AuroraFox")
    table = doc.add_table(rows=1, cols=2)
    table.cell(0, 0).text = "ключ"
    table.cell(0, 1).text = "значение"
    doc.save(docx_path)
    doc_result = _analyze(docx_path, "", False)
    assert "Документ AuroraFox" in doc_result["text"]
    assert "ключ | значение" in doc_result["text"]

    xlsx_path = tmp_path / "sample.xlsx"
    wb = Workbook()
    ws = wb.active
    ws.title = "Данные"
    ws.append(["Имя", "Значение"])
    ws.append(["AuroraFox", 42])
    wb.save(xlsx_path)
    wb.close()
    xlsx_result = _analyze(xlsx_path, "", False)
    assert "AuroraFox" in xlsx_result["text"]
    assert "42" in xlsx_result["text"]

    pptx_path = tmp_path / "sample.pptx"
    prs = Presentation()
    slide = prs.slides.add_slide(prs.slide_layouts[1])
    slide.shapes.title.text = "AuroraFox"
    slide.placeholders[1].text = "Локальная презентация"
    prs.save(pptx_path)
    pptx_result = _analyze(pptx_path, "", False)
    assert "AuroraFox" in pptx_result["text"]
    assert "Локальная презентация" in pptx_result["text"]


def test_zip_path_traversal_is_detected(tmp_path: Path) -> None:
    archive = tmp_path / "unsafe.zip"
    with zipfile.ZipFile(archive, "w") as zf:
        zf.writestr("safe/readme.txt", "ok")
        zf.writestr("../escape.txt", "no")

    text, meta, warnings = _archive_listing(archive)
    assert meta["entries"] == 2
    assert meta["unsafe_entries"] == 1
    assert "[UNSAFE]" in text
    assert any("небезопас" in warning.lower() for warning in warnings)


def test_zip_extracts_bounded_text_content_for_knowledge(tmp_path: Path) -> None:
    archive = tmp_path / "files (2).zip"
    with zipfile.ZipFile(archive, "w") as zf:
        zf.writestr("facts/readme.txt", "AURORA_ARCHIVE_FACT=violet-cedar")
        zf.writestr("facts/data.jsonl", '{"topic":"archive","fact":"local knowledge"}\n')
        zf.writestr("bin/blob.dat", b"\x00\x01\x02")
        zf.writestr("../escape.txt", "MUST_NOT_BE_IMPORTED")

    text, meta, warnings = _archive_listing(archive, max_chars=20000)

    assert "AURORA_ARCHIVE_FACT=violet-cedar" in text
    assert '"fact":"local knowledge"' in text
    assert "MUST_NOT_BE_IMPORTED" not in text
    assert meta["text_entries_extracted"] == 2
    assert meta["text_bytes_extracted"] > 0
    assert meta["unsafe_entries"] == 1
    assert meta["untrusted_document"] is True
    assert meta["content_authority"] == "data_only"
    assert meta["external_ai_required"] is False
    assert any("небезопас" in warning.lower() for warning in warnings)

    clipped, _, _ = _archive_listing(archive, max_chars=80)
    assert len(clipped) <= 80


def test_zip_bomb_budget_blocks_content_read(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    archive = tmp_path / "oversized.zip"
    with zipfile.ZipFile(archive, "w") as zf:
        zf.writestr("facts.txt", "knowledge that must stay unread")

    monkeypatch.setattr(file_service, "MAX_ARCHIVE_EXPANDED", 4)
    text, meta, warnings = _archive_listing(archive, max_chars=20000)

    assert "knowledge that must stay unread" not in text
    assert meta["extraction_blocked"] is True
    assert meta["text_entries_extracted"] == 0
    assert any("лимит" in warning.lower() for warning in warnings)


def test_binary_does_not_crash(tmp_path: Path) -> None:
    path = tmp_path / "blob.dat"
    path.write_bytes(b"\x00\x01\x02\xff" * 100)
    result = _analyze(path, "", False)
    assert result["kind"] == "binary"
    assert result["text"]


class _FakeResponse:
    def __init__(self, status_code: int, payload: dict | None = None) -> None:
        self.status_code = status_code
        self._payload = payload or {}

    def json(self) -> dict:
        return self._payload


def test_health_does_not_claim_vision_without_model(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get(url: str, timeout: float):
        if url.endswith("/api/tags"):
            return _FakeResponse(200, {"models": [{"name": "qwen3:8b"}]})
        return _FakeResponse(200, {"ok": True})

    monkeypatch.setattr(file_service.requests, "get", fake_get)
    result = file_service.health()
    assert result["ok"] is True
    assert result["ollama_online"] is True
    assert result["vision_online"] is False
    assert result["vision_model"] == file_service.VISION_MODEL


def test_health_claims_vision_only_with_selected_model(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get(url: str, timeout: float):
        if url.endswith("/api/tags"):
            return _FakeResponse(200, {"models": [{"name": "qwen3:8b"}, {"name": file_service.VISION_MODEL}]})
        return _FakeResponse(200, {"ok": True})

    monkeypatch.setattr(file_service.requests, "get", fake_get)
    result = file_service.health()
    assert result["ollama_online"] is True
    assert result["vision_online"] is True
    assert file_service.VISION_MODEL in result["installed_models"]


def test_spreadsheet_budget_reaches_full_service_response_and_cache(tmp_path: Path, monkeypatch) -> None:
    from openpyxl import Workbook
    path = tmp_path / "owner_budget.xlsx"
    book = Workbook(); book.active.append(["one", "two", "three"]); book.active.append(["four", "five", "six"])
    book.save(path); book.close()
    monkeypatch.setattr(file_service, "CACHE_DIR", tmp_path / "cache")
    file_service.CACHE_DIR.mkdir()
    monkeypatch.setattr(file_service, "MAX_SPREADSHEET_CELLS", 5)
    request = file_service.AnalyzeRequest(path=str(path), visual=False)
    limited = file_service.analyze(request)
    assert limited["truncated"] is True
    assert limited["metadata"]["cells_read"] == 5
    assert limited["warnings"]
    assert "six" not in limited["content"]
    assert file_service.analyze(request)["cached"] is True
    monkeypatch.setattr(file_service, "MAX_SPREADSHEET_CELLS", 6)
    complete = file_service.analyze(request)
    assert complete["cached"] is False
    assert complete["truncated"] is False
    assert "six" in complete["content"]


def test_listing_owner_env_also_bounds_omitted_request_defaults(tmp_path: Path):
    import json
    import os
    import subprocess
    env = dict(os.environ, AURORAFOX_USER_DIR=str(tmp_path), AURORAFOX_FILE_TREE_MAX_ITEMS="2",
               AURORAFOX_FILE_SEARCH_MAX_RESULTS="3", AURORAFOX_FILE_SEARCH_EXCERPT_CHARS="10")
    code = "import json,file_service as f; print(json.dumps([f.TreeRequest(path='.').max_items,f.CacheSearchRequest(query='x').limit,f.MAX_CACHE_EXCERPT_CHARS]))"
    output = subprocess.check_output([sys.executable, "-c", code], cwd=ROOT / "file_intelligence", env=env, text=True)
    assert json.loads(output) == [2, 3, 10]


def test_zero_cache_budget_keeps_actual_cached_files(tmp_path, monkeypatch):
    monkeypatch.setattr(file_service, 'CACHE_DIR', tmp_path)
    monkeypatch.setattr(file_service, 'CACHE_MAX_BYTES', 0)
    file_service._cache_put('one', {'content': 'one'})
    file_service._cache_put('two', {'content': 'two'})
    assert len(list(tmp_path.glob('*.json'))) == 2
    size = sum(p.stat().st_size for p in tmp_path.glob('*.json'))
    file_service._trim_cache(size)
    assert len(list(tmp_path.glob('*.json'))) == 2
    file_service._trim_cache(size - 1)
    assert len(list(tmp_path.glob('*.json'))) == 1


@pytest.mark.parametrize('value', ['0', '1', '600'])
def test_file_operational_startup_budget_and_negative_rejection(monkeypatch, value):
    key = 'AURORAFOX_FILE_CACHE_MAX_BYTES'
    monkeypatch.setenv(key, value)
    assert file_service._operational_budget_from_env(key, 500) == int(value)
    monkeypatch.setenv(key, '-1')
    with pytest.raises(ValueError, match=key):
        file_service._operational_budget_from_env(key, 500)
    monkeypatch.setenv(key, 'invalid')
    with pytest.raises(ValueError, match=key):
        file_service._operational_budget_from_env(key, 500)


@pytest.mark.parametrize('deadline', [None, 1, 600])
def test_actual_file_provider_http_deadline(tmp_path, monkeypatch, deadline):
    import json
    import threading
    import requests
    from http.server import BaseHTTPRequestHandler, HTTPServer
    received = []
    timeouts = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_POST(self):
            received.append(json.loads(self.rfile.read(int(self.headers['Content-Length']))))
            self.send_response(200)
            self.end_headers()
            payload = {'ok': True, 'text': 'actual speech'} if self.path == '/stt_path' else {'message': {'content': 'actual vision'}}
            self.wfile.write(json.dumps(payload).encode())

    original_send = requests.sessions.Session.send
    def send(session, request, **kwargs):
        timeouts.append(kwargs['timeout'])
        return original_send(session, request, **kwargs)
    monkeypatch.setattr(requests.sessions.Session, 'send', send)
    server = HTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.01}, daemon=True)
    thread.start()
    try:
        url = f'http://127.0.0.1:{server.server_port}'
        monkeypatch.setattr(file_service, 'OLLAMA_URL', url)
        monkeypatch.setattr(file_service, 'VOICE_URL', url)
        monkeypatch.setattr(file_service, 'VISION_TIMEOUT_SECONDS', deadline)
        monkeypatch.setattr(file_service, 'STT_TIMEOUT_SECONDS', deadline)
        assert file_service._vision_bytes(b'actual image', 'inspect') == 'actual vision'
        path = tmp_path / 'sample.wav'
        path.write_bytes(b'actual audio')
        text, metadata, warnings = file_service._voice_transcribe(path)
        assert text == 'actual speech' and not warnings
        assert timeouts == [deadline, deadline]
        assert received[1]['path'] == str(path)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        assert not thread.is_alive()


def test_actual_video_ffmpeg_accepts_unlimited_owner_deadline(tmp_path, monkeypatch):
    import imageio_ffmpeg
    import subprocess
    executable = imageio_ffmpeg.get_ffmpeg_exe()
    video = tmp_path / 'actual.mp4'
    generated = subprocess.run([executable, '-y', '-f', 'lavfi', '-i', 'color=c=red:s=16x16:d=0.2',
                                '-f', 'lavfi', '-i', 'sine=frequency=440:duration=0.2', '-shortest',
                                '-c:v', 'mpeg4', '-c:a', 'aac', str(video)], capture_output=True, timeout=10)
    assert generated.returncode == 0, generated.stderr.decode(errors='replace')
    observed = []
    original_run = subprocess.run
    def run(*args, **kwargs):
        observed.append(kwargs['timeout'])
        return original_run(*args, **kwargs)
    monkeypatch.setattr(subprocess, 'run', run)
    monkeypatch.setattr(file_service, 'VIDEO_TIMEOUT_SECONDS', None)
    # Offline transcript availability is independent of extraction deadline.
    monkeypatch.setattr(file_service, '_voice_transcribe', lambda path: ('extracted audio', {}, []))
    text, _, warnings = file_service._video_analyze(video, '', False)
    assert text.endswith('extracted audio')
    assert observed == [None]
    assert not warnings


@pytest.mark.parametrize('value', [0, 2, 600])
def test_full_file_service_import_uses_four_owner_operational_budgets(monkeypatch, value):
    import importlib
    mapping = {'CACHE_MAX_BYTES': 'AURORAFOX_FILE_CACHE_MAX_BYTES',
               'VISION_TIMEOUT_SECONDS': 'AURORAFOX_FILE_VISION_TIMEOUT_SECONDS',
               'STT_TIMEOUT_SECONDS': 'AURORAFOX_FILE_STT_TIMEOUT_SECONDS',
               'VIDEO_TIMEOUT_SECONDS': 'AURORAFOX_FILE_VIDEO_TIMEOUT_SECONDS'}
    try:
        with monkeypatch.context() as patch:
            for key in mapping.values():
                patch.setenv(key, str(value))
            importlib.reload(file_service)
            assert file_service.CACHE_MAX_BYTES == value
            for field in ('VISION_TIMEOUT_SECONDS', 'STT_TIMEOUT_SECONDS', 'VIDEO_TIMEOUT_SECONDS'):
                assert getattr(file_service, field) == (value or None)
            patch.setenv(mapping['CACHE_MAX_BYTES'], '-1')
            with pytest.raises(ValueError, match='nonnegative integer'):
                importlib.reload(file_service)
    finally:
        importlib.reload(file_service)
