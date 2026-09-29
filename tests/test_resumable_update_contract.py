from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_client_persists_verified_parts_and_has_no_total_deadline() -> None:
    source = (ROOT / "update/update_manager.gd").read_text(encoding="utf-8")
    chunked = source.split("func _download_chunked_asset", 1)[1].split("func _validate_part_plan", 1)[0]
    assert "_verified_file(final_path" in chunked
    assert "resumed += 1" in chunked
    assert "while true:" in chunked
    assert "PART_RETRY_MAX_SECONDS" in chunked
    assert "_assemble_verified_parts" in chunked
    assert "DirAccess.remove_absolute(final_path)" not in chunked.split("if _verified_file(final_path", 1)[1].split("continue", 1)[0]
    assert "There is no total" in source
    part_request = source.split("func _download_part_once", 1)[1].split("func _header_value", 1)[0]
    assert 'headers.append("Range: bytes=%d-" % offset)' in part_request
    assert 'code == 206' in part_request
    assert '"content-range"' in part_request
    assert "file.seek_end()" in part_request
    retry = chunked.split("while true:", 1)[1]
    assert "partial_size < 0 or partial_size >= expected_size" in retry


def test_client_rejects_unsafe_or_incomplete_signed_part_plans() -> None:
    source = (ROOT / "update/update_manager.gd").read_text(encoding="utf-8")
    validation = source.split("func _validate_part_plan", 1)[1].split("func _download_part_once", 1)[0]
    for required in (
        'name != name.get_file()',
        'name.contains("..")',
        "names.has(name)",
        'url.begins_with("https://")',
        "sha.length() != 64",
        "size > PART_MAX_BYTES",
        'total != int(asset.get("size", 0))',
    ):
        assert required in validation


def test_release_publishes_64_mib_parts_inside_signed_manifest() -> None:
    workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
    assert "split -b 64M -d -a 3 dist/AuroraFox-Windows.zip" in workflow
    assert "split -b 64M -d -a 3 dist/AuroraFox-Android.apk" in workflow
    assert "'schema_version': 2" in workflow
    assert "'chunk_size': 67108864" in workflow
    assert "'parts': windows_parts" in workflow
    assert "'parts': android_parts" in workflow
    assert "dist/AuroraFox-Windows.zip.chunk-*" in workflow
    assert "dist/AuroraFox-Android.apk.chunk-*" in workflow
    assert workflow.index("Path('dist/update.json').write_text") < workflow.index("openssl dgst -sha256 -sign")


def test_template_keeps_legacy_whole_asset_and_declares_chunk_contract() -> None:
    manifest = json.loads((ROOT / "update/manifest.template.json").read_text(encoding="utf-8"))
    for platform in ("windows", "android"):
        asset = manifest["assets"][platform]
        assert {"url", "sha256", "size", "format", "chunk_size", "parts"} <= asset.keys()
        assert asset["chunk_size"] == 64 * 1024 * 1024
        assert asset["parts"] == []


def test_chat_append_renders_before_deferred_atomic_persistence() -> None:
    store = (ROOT / "scripts/chat_store.gd").read_text(encoding="utf-8")
    add_message = store.split("func add_message", 1)[1].split("func _compact_attachments", 1)[0]
    assert "queue_save()" in add_message
    assert "save_all()" not in add_message
    assert 'call_deferred("_flush_queued_save")' in store
    save = store.split("func save_all", 1)[1].split("func queue_save", 1)[0]
    assert 'SAVE_PATH + ".tmp"' in save
    assert "DirAccess.rename_absolute" in save
