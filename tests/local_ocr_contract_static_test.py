from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_windows_ocr_is_local_bundled_and_bilingual():
    ocr = read("file_intelligence/local_ocr.py")
    prep = read("file_intelligence/prepare_windows_ocr.ps1")
    build = read("build/build_windows.ps1")
    assert '"rus+eng"' in ocr
    assert 'network_required": False' in ocr
    assert 'external_ai_required": False' in ocr
    assert "prepare_windows_ocr.ps1" in build
    assert "rus.traineddata" in prep and "eng.traineddata" in prep
    assert "tesseract.exe" in prep


def test_pdf_uses_text_layer_before_page_ocr_and_keeps_provenance():
    service = read("file_intelligence/file_service.py")
    assert "_usable_pdf_text(layer_text)" in service
    assert '"source": "text_layer"' in service
    assert '"source": "ocr"' in service
    assert '"page_sources"' in service
    assert "MAX_PDF_PAGES" in service and "MAX_OCR_PAGES" in service
    assert "MAX_PDF_RENDER_PIXELS" in service


def test_knowledge_boundary_remains_data_only_and_offline():
    service = read("file_intelligence/file_service.py")
    smoke = read("tests/local_ocr_knowledge_smoke.gd")
    assert '"untrusted_document": True' in service
    assert '"content_authority": "data_only"' in service
    assert '"external_ai_required": False' in service
    assert '"untrusted_document": true' in smoke
    assert '"content_authority": "data_only"' in smoke
    assert "duplicate" in smoke and "restart" in smoke


def test_android_bridge_and_packaging_are_offline_ocr_capable():
    runtime = read("android_plugin/plugin/src/main/java/com/aurorafox/runtime/AndroidOcrRuntime.kt")
    bridge = read("android_plugin/plugin/src/main/java/com/aurorafox/runtime/GodotAndroidPlugin.kt")
    export = read("addons/AuroraFoxRuntime/export_plugin.gd")
    assert "rus" in runtime and "eng" in runtime
    assert "external_ai_required" in runtime and "network_required" in runtime
    assert "extractDocumentText" in bridge
    assert "cancelDocumentExtraction" in bridge
    assert "getDocumentExtractionProgress" in bridge
    assert "tess-two" in export or "tesseract" in export.lower()


def test_missing_ocr_runtime_has_explicit_degradation_contract():
    ocr = read("file_intelligence/local_ocr.py")
    service = read("file_intelligence/file_service.py")
    assert "Local OCR runtime is unavailable" in ocr
    assert "ocr_unavailable" in service
    assert "failed_ocr_pages" in service
