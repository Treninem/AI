from __future__ import annotations

import hashlib
import json
import sqlite3
import zipfile
from pathlib import Path

import pytest

from api.backup_service import BackupService, BackupTooLarge


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def test_backup_excludes_credential_files_and_manifest_is_verifiable(tmp_path: Path):
    root = tmp_path / "user"
    (root / "api" / "conversations").mkdir(parents=True)
    (root / "api" / "conversations" / "chat.json").write_text('{"message":"hello"}\n', encoding="utf-8")
    (root / "memory.json").write_text('{"facts":["safe"]}\n', encoding="utf-8")
    (root / "api" / "keys.json").write_text('{"token_hash":"secret"}\n', encoding="utf-8")
    (root / "api" / "bootstrap_key.txt").write_text("af_admin_secret\n", encoding="utf-8")
    (root / "models").mkdir()
    (root / "models" / "weights.json").write_text('{"large":"excluded"}\n', encoding="utf-8")

    database = root / "project_index.sqlite3"
    with sqlite3.connect(database) as connection:
        connection.execute("CREATE TABLE files(path TEXT PRIMARY KEY, digest TEXT NOT NULL)")
        connection.execute("INSERT INTO files VALUES (?, ?)", ("README.md", "abc123"))

    result = BackupService(root, tmp_path / "cache").create_archive()
    assert result.file_count == 3
    assert result.sha256 == hashlib.sha256(result.archive_path.read_bytes()).hexdigest()

    with zipfile.ZipFile(result.archive_path) as archive:
        names = set(archive.namelist())
        assert "manifest.json" in names
        assert "data/api/conversations/chat.json" in names
        assert "data/memory.json" in names
        assert "data/project_index.sqlite3" in names
        assert not any("key" in name.lower() for name in names)
        assert not any("models" in name.lower() for name in names)

        manifest = json.loads(archive.read("manifest.json"))
        assert manifest["schema"] == "aurorafox.backup.v1"
        assert manifest["credential_files_included"] is False
        assert manifest["file_count"] == 3
        for item in manifest["files"]:
            payload = archive.read(item["path"])
            assert len(payload) == item["bytes"]
            assert _sha256(payload) == item["sha256"]

        extracted = tmp_path / "restored.sqlite3"
        extracted.write_bytes(archive.read("data/project_index.sqlite3"))
        with sqlite3.connect(extracted) as connection:
            assert connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert connection.execute("SELECT path, digest FROM files").fetchone() == ("README.md", "abc123")


def test_backup_size_limit_fails_closed(tmp_path: Path):
    root = tmp_path / "user"
    root.mkdir()
    (root / "memory.json").write_text('{"payload":"too large"}\n', encoding="utf-8")
    with pytest.raises(BackupTooLarge):
        BackupService(root, tmp_path / "cache", max_source_bytes=4).create_archive()


def test_latest_export_is_atomic_and_has_detached_hash(tmp_path: Path):
    root = tmp_path / "user"
    root.mkdir()
    (root / "memory.json").write_text('{"facts":["safe"]}\n', encoding="utf-8")
    export = tmp_path / "sftp" / "exports"
    result = BackupService(root, tmp_path / "cache").publish_latest(export)
    assert result.archive_path == export / "latest.zip"
    assert result.archive_path.is_file()
    assert (export / "latest.sha256").read_text(encoding="ascii") == f"{result.sha256}  latest.zip\n"
    assert not list(export.glob("*.tmp"))
