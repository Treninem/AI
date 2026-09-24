#!/usr/bin/env python3
"""Fail-closed streaming validator for AuroraFox production Knowledge Packs."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path
from typing import BinaryIO, Iterator


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONTRACT = ROOT / "knowledge_pack" / "production_pack.json"
REQUIRED_RECORD_FIELDS = {
    "schema", "id", "title", "content", "language", "source", "source_url",
    "source_version", "license", "license_url", "attribution",
    "verification_status", "provenance",
}


class PackError(RuntimeError):
    pass


class HashingReader:
    def __init__(self, source: BinaryIO) -> None:
        self.source = source
        self.digest = hashlib.sha256()
        self.bytes_read = 0

    def read(self, size: int = -1) -> bytes:
        chunk = self.source.read(size)
        self.digest.update(chunk)
        self.bytes_read += len(chunk)
        return chunk

    def readline(self, size: int = -1) -> bytes:
        chunk = self.source.readline(size)
        self.digest.update(chunk)
        self.bytes_read += len(chunk)
        return chunk


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def open_tar(path: Path) -> tuple[tarfile.TarFile, subprocess.Popen[bytes] | None]:
    if path.name.endswith((".tar.zst", ".tzst")):
        executable = shutil.which("zstd") or shutil.which("unzstd")
        if not executable:
            raise PackError("zstd/unzstd is required to validate .tar.zst")
        process = subprocess.Popen(
            [executable, "-dc", "--", str(path)], stdout=subprocess.PIPE
        )
        if process.stdout is None:
            process.kill()
            raise PackError("cannot open zstd output")
        return tarfile.open(fileobj=process.stdout, mode="r|"), process
    return tarfile.open(path, mode="r|*"), None


def iter_jsonl(stream: BinaryIO, member_name: str) -> Iterator[tuple[int, dict, bytes]]:
    line_number = 0
    while True:
        raw = stream.readline()
        if not raw:
            break
        line_number += 1
        if not raw.endswith(b"\n"):
            raise PackError(f"{member_name}:{line_number}: missing final newline")
        try:
            value = json.loads(raw)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise PackError(f"{member_name}:{line_number}: invalid UTF-8 JSON: {exc}") from exc
        if not isinstance(value, dict):
            raise PackError(f"{member_name}:{line_number}: record is not an object")
        yield line_number, value, raw


def validate_record(record: dict, manifest: dict, location: str) -> tuple[str, bytes, int]:
    missing = REQUIRED_RECORD_FIELDS.difference(record)
    if missing:
        raise PackError(f"{location}: missing fields: {sorted(missing)}")
    if record["schema"] != manifest["record_schema"]:
        raise PackError(f"{location}: record schema mismatch")
    source = manifest["source"]
    expected = {
        "language": manifest["languages"][0],
        "source": source["name"],
        "source_version": source["version"],
        "license": source["license"],
        "license_url": source["license_url"],
        "attribution": source["attribution"],
        "verification_status": "source",
    }
    for key, expected_value in expected.items():
        if record.get(key) != expected_value:
            raise PackError(f"{location}: {key} does not match manifest provenance")
    record_id = record["id"]
    content = record["content"]
    if not isinstance(record_id, str) or not record_id.strip():
        raise PackError(f"{location}: empty id")
    if not isinstance(content, str) or not content.strip():
        raise PackError(f"{location}: empty content")
    if not isinstance(record["provenance"], dict) or not record["provenance"]:
        raise PackError(f"{location}: empty provenance")
    encoded = content.encode("utf-8")
    return record_id, hashlib.sha256(encoded).digest(), len(encoded)


def _require_equal(actual: object, expected: object, label: str) -> None:
    if actual != expected:
        raise PackError(f"{label}: expected {expected!r}, got {actual!r}")


def validate(archive: Path, contract_path: Path, skip_archive_hash: bool = False) -> dict:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    artifact_contract = contract["artifact"]
    expected_manifest = contract["manifest"]
    _require_equal(archive.name, artifact_contract["name"], "artifact name")
    _require_equal(archive.stat().st_size, artifact_contract["bytes"], "artifact bytes")
    archive_sha = ""
    if not skip_archive_hash:
        archive_sha = sha256_file(archive)
        _require_equal(archive_sha, artifact_contract["sha256"], "artifact sha256")

    tar, process = open_tar(archive)
    manifest: dict | None = None
    expected_shards: dict[str, dict] = {}
    seen_members: set[str] = set()
    seen_ids: set[str] = set()
    seen_content: set[bytes] = set()
    totals = {"file_bytes": 0, "content_bytes": 0, "record_count": 0}
    validated_shards = 0
    try:
        for member in tar:
            name = member.name
            if name in seen_members:
                raise PackError(f"duplicate archive member: {name}")
            seen_members.add(name)
            if not member.isfile() or name.startswith("/") or ".." in Path(name).parts:
                raise PackError(f"unsafe or non-file archive member: {name}")
            extracted = tar.extractfile(member)
            if extracted is None:
                raise PackError(f"cannot read archive member: {name}")
            if name == "manifest.json":
                if manifest is not None or validated_shards:
                    raise PackError("manifest.json must be the first archive member")
                manifest = json.load(extracted)
                if not isinstance(manifest, dict):
                    raise PackError("manifest.json is not an object")
                for key, value in expected_manifest.items():
                    if key == "shard_count":
                        continue
                    if key == "input_archive":
                        inputs = manifest.get("input_archives", [])
                        _require_equal(len(inputs), 1, "manifest input archive count")
                        _require_equal(inputs[0], value, "manifest input archive")
                    else:
                        _require_equal(manifest.get(key), value, f"manifest {key}")
                shards = manifest.get("shards")
                if not isinstance(shards, list):
                    raise PackError("manifest shards is not a list")
                _require_equal(len(shards), expected_manifest["shard_count"], "manifest shard count")
                expected_shards = {row["path"]: row for row in shards}
                if len(expected_shards) != len(shards):
                    raise PackError("duplicate shard paths in manifest")
                continue
            if manifest is None:
                raise PackError("manifest.json must be the first archive member")
            shard = expected_shards.get(name)
            if shard is None:
                raise PackError(f"undeclared archive member: {name}")
            reader = HashingReader(extracted)
            shard_records = 0
            shard_content_bytes = 0
            for line_number, record, _raw in iter_jsonl(reader, name):
                record_id, content_hash, content_bytes = validate_record(
                    record, manifest, f"{name}:{line_number}"
                )
                if record_id in seen_ids:
                    raise PackError(f"{name}:{line_number}: duplicate record id {record_id}")
                if content_hash in seen_content:
                    raise PackError(f"{name}:{line_number}: duplicate content")
                seen_ids.add(record_id)
                seen_content.add(content_hash)
                shard_records += 1
                shard_content_bytes += content_bytes
            _require_equal(reader.bytes_read, member.size, f"{name} tar/member bytes")
            _require_equal(reader.bytes_read, shard["bytes"], f"{name} manifest bytes")
            _require_equal(reader.digest.hexdigest(), shard["sha256"], f"{name} sha256")
            _require_equal(shard_records, shard["records"], f"{name} records")
            _require_equal(shard_content_bytes, shard["content_bytes"], f"{name} content bytes")
            if reader.bytes_read > manifest["shard_limit_bytes"]:
                raise PackError(f"{name}: shard exceeds limit")
            totals["file_bytes"] += reader.bytes_read
            totals["content_bytes"] += shard_content_bytes
            totals["record_count"] += shard_records
            validated_shards += 1
    finally:
        tar.close()
        if process is not None:
            if process.stdout is not None:
                process.stdout.close()
            return_code = process.wait()
            if return_code != 0 and sys.exc_info()[0] is None:
                raise PackError(f"zstd decompressor exited with {return_code}")

    if manifest is None:
        raise PackError("manifest.json is missing")
    _require_equal(validated_shards, len(expected_shards), "validated shard count")
    _require_equal(seen_members, {"manifest.json", *expected_shards}, "archive member set")
    for key, value in totals.items():
        _require_equal(value, manifest[key], f"computed {key}")
    if totals["content_bytes"] < 1024 ** 3:
        raise PackError("genuine content is below 1 GiB")
    return {
        "ok": True,
        "artifact": archive.name,
        "artifact_bytes": archive.stat().st_size,
        "artifact_sha256": archive_sha or artifact_contract["sha256"],
        "pack_id": manifest["pack_id"],
        "pack_version": manifest["pack_version"],
        "shards": validated_shards,
        **totals,
        "duplicate_ids": 0,
        "duplicate_content": 0,
        "source": manifest["source"],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("--contract", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--skip-archive-hash", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        report = validate(args.archive, args.contract, args.skip_archive_hash)
    except (OSError, KeyError, TypeError, ValueError, PackError, tarfile.TarError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(encoded, encoding="utf-8")
    print(encoded, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
