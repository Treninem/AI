import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "benchmarks" / "knowledge" / "production_pack_acceptance.gd"
RUNNER = ROOT / "benchmarks" / "knowledge" / "run_production_pack_acceptance.py"


def test_production_pack_probe_is_strict_offline_and_provenance_aware() -> None:
    source = PROBE.read_text(encoding="utf-8")
    assert 'REPORT_SCHEMA := "aurorafox.production-knowledge-acceptance.v1"' in source
    assert 'installer.inspect(pack_dir)' in source
    assert 'bool(manifest.get("production", false))' in source
    assert 'RELEASE_CONTRACT_PATH := "res://knowledge_pack/production_pack.json"' in source
    assert 'production release input provenance mismatch' in source
    assert 'installer.install(StoreScript.new(), pack_dir)' in source
    assert 'int(resumed.get("skipped_shards", -1))' in source
    assert 'metadata.get("pack_id", "")' in source
    assert '"offline": true' in source
    assert '"external_ai_required": false' in source
    assert "HTTPClient" not in source
    assert "HTTPRequest" not in source
    assert "OS.execute" not in source


def test_production_pack_runner_has_timeout_isolation_and_rss_evidence() -> None:
    source = RUNNER.read_text(encoding="utf-8")
    assert 'default=21600' in source
    assert 'TemporaryDirectory(prefix="aurorafox-production-pack-")' in source
    assert 'base.base_environment(user_data' in source
    assert '"AURORAFOX_OFFLINE": "1"' in source
    assert '"AURORAFOX_DISABLE_NETWORK": "1"' in source
    assert "base.process_rss_bytes(process.pid)" in source
    assert '"timed_out": timed_out' in source
    assert '"peak_rss_bytes": peak_rss' in source
    assert 'stdout_log.open("w"' in source
    spec = importlib.util.spec_from_file_location("production_pack_runner", RUNNER)
    assert spec is not None and spec.loader is not None
