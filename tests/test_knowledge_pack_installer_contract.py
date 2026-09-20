from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_installer_is_bounded_verified_resumable_and_offline() -> None:
    source = (ROOT / "scripts/knowledge_pack_installer.gd").read_text(encoding="utf-8")
    assert 'PACK_SCHEMA := "aurorafox.knowledge-pack.v1"' in source
    assert "MIN_PRODUCTION_CONTENT_BYTES := 1024 * 1024 * 1024" in source
    assert "FileAccess.get_sha256(path)" in source
    assert "size > shard_limit" in source
    assert "KnowledgeImportTransaction.new()" in source
    assert "transaction.import_file" in source
    assert '"completed_shards"' in source
    assert '"resumable": true' in source
    assert '"offline": true' in source
    assert '"external_ai_required": false' in source
    assert "HTTPClient" not in source
    assert "HTTPRequest" not in source
    assert "OS.execute" not in source


def test_smoke_requires_verification_resume_and_production_floor() -> None:
    smoke = (ROOT / "tests/knowledge_pack_installer_smoke.gd").read_text(encoding="utf-8")
    assert "installer.inspect(ROOT)" in smoke
    assert "installer.install(StoreScript.new(), ROOT)" in smoke
    assert 'int(resumed.get("skipped_shards", 0)) != 1' in smoke
    assert 'manifest["production"] = true' in smoke
    assert 'contains("below 1 GiB")' in smoke
    assert "AURORA_KNOWLEDGE_PACK_INSTALLER_OK" in smoke
