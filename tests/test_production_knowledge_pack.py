import importlib.util
import json
import tarfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "knowledge_pack" / "validate_pack.py"
SPEC = importlib.util.spec_from_file_location("validate_pack", MODULE_PATH)
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


def test_production_contract_pins_genuine_licensed_sharded_artifact() -> None:
    contract = json.loads((ROOT / "knowledge_pack" / "production_pack.json").read_text())
    assert contract["schema"] == "aurorafox.knowledge-pack-release.v1"
    assert contract["artifact"]["bytes"] == 429_588_529
    assert len(contract["artifact"]["sha256"]) == 64
    manifest = contract["manifest"]
    assert manifest["production"] is True
    assert manifest["content_bytes"] >= 1024**3
    assert manifest["shard_count"] == 60
    assert manifest["shard_limit_bytes"] <= 32 * 1024**2
    assert manifest["source"]["license"] == "CC BY-SA 4.0"
    assert manifest["source"]["attribution"] == "Russian Wikipedia contributors"
    assert len(manifest["input_archive"]["sha256"]) == 64


def _fixture(tmp_path: Path) -> tuple[Path, Path]:
    # Use a small tar fixture for structural fail-closed checks. The production
    # content floor is asserted separately and the validator must reject this.
    sample = {
        "schema": "aurorafox.knowledge-record.v1", "id": "mediawiki:ru:1:10",
        "title": "Аврора", "content": "Полярное сияние", "language": "ru",
        "source": "Russian Wikipedia",
        "source_url": "https://ru.wikipedia.org/?curid=1&oldid=10",
        "source_version": "20260901", "license": "CC BY-SA 4.0",
        "license_url": "https://creativecommons.org/licenses/by-sa/4.0/",
        "attribution": "Russian Wikipedia contributors", "verification_status": "source",
        "provenance": {"page_id": "1", "revision_id": "10"},
    }
    shard = (json.dumps(sample, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
    import hashlib
    manifest = {
        "schema": "aurorafox.knowledge-pack.v1", "pack_id": "test", "pack_version": "1",
        "record_schema": "aurorafox.knowledge-record.v1", "production": True,
        "content_bytes": len(sample["content"].encode()), "file_bytes": len(shard),
        "record_count": 1, "languages": ["ru"], "domains": ["encyclopedia"],
        "source": {"name": "Russian Wikipedia", "version": "20260901",
                   "license": "CC BY-SA 4.0", "license_url": "https://creativecommons.org/licenses/by-sa/4.0/",
                   "attribution": "Russian Wikipedia contributors"},
        "input_archives": [{"name": "source.bz2", "bytes": 1, "sha256": "0" * 64}],
        "shard_limit_bytes": 32 * 1024**2,
        "shards": [{"path": "knowledge-00000.jsonl", "sha256": hashlib.sha256(shard).hexdigest(),
                    "bytes": len(shard), "content_bytes": len(sample["content"].encode()), "records": 1}],
    }
    archive = tmp_path / "fixture.tar"
    manifest_path = tmp_path / "manifest.json"
    shard_path = tmp_path / "knowledge-00000.jsonl"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    shard_path.write_bytes(shard)
    with tarfile.open(archive, "w") as out:
        out.add(manifest_path, arcname="manifest.json")
        out.add(shard_path, arcname="knowledge-00000.jsonl")
    contract = {
        "schema": "aurorafox.knowledge-pack-release.v1",
        "artifact": {"name": archive.name, "bytes": archive.stat().st_size, "sha256": VALIDATOR.sha256_file(archive)},
        "manifest": {k: v for k, v in manifest.items() if k != "shards"},
    }
    contract["manifest"]["shard_count"] = 1
    contract["manifest"]["input_archive"] = contract["manifest"].pop("input_archives")[0]
    contract_path = tmp_path / "contract.json"
    contract_path.write_text(json.dumps(contract), encoding="utf-8")
    return archive, contract_path


def test_validator_rejects_pack_below_genuine_one_gib_floor(tmp_path: Path) -> None:
    archive, contract = _fixture(tmp_path)
    try:
        VALIDATOR.validate(archive, contract)
    except VALIDATOR.PackError as exc:
        assert "below 1 GiB" in str(exc)
    else:
        raise AssertionError("small fixture was accepted as a production pack")


def test_record_validator_rejects_duplicate_content_identity_basis() -> None:
    manifest = {
        "record_schema": "aurorafox.knowledge-record.v1", "languages": ["ru"],
        "source": {"name": "Russian Wikipedia", "version": "20260901", "license": "CC BY-SA 4.0",
                   "license_url": "https://creativecommons.org/licenses/by-sa/4.0/",
                   "attribution": "Russian Wikipedia contributors"},
    }
    record = {
        "schema": manifest["record_schema"], "id": "x", "title": "t", "content": "same",
        "language": "ru", "source": "Russian Wikipedia", "source_url": "https://example.invalid",
        "source_version": "20260901", "license": "CC BY-SA 4.0",
        "license_url": "https://creativecommons.org/licenses/by-sa/4.0/",
        "attribution": "Russian Wikipedia contributors", "verification_status": "source",
        "provenance": {"revision_id": "1"},
    }
    first = VALIDATOR.validate_record(record, manifest, "a")
    second = VALIDATOR.validate_record({**record, "id": "y"}, manifest, "b")
    assert first[1] == second[1]
