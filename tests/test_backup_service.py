from __future__ import annotations

import hashlib
import json
import sqlite3
import zipfile
from pathlib import Path

import pytest

from api.account_store import AccountStore
from api.auth import KeyStore
from api.backup_service import BackupService, BackupStoragePressure, BackupTooLarge


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def test_backup_excludes_credential_files_and_manifest_is_verifiable(tmp_path: Path):
    root = tmp_path / "user"
    (root / "api" / "conversations").mkdir(parents=True)
    (root / "api" / "conversations" / "chat.json").write_text('{"message":"hello"}\n', encoding="utf-8")
    (root / "memory.json").write_text('{"facts":["safe"]}\n', encoding="utf-8")
    (root / "models").mkdir()
    (root / "models" / "weights.json").write_text('{"large":"excluded"}\n', encoding="utf-8")

    project_database = root / "project_index.sqlite3"
    with sqlite3.connect(project_database) as connection:
        connection.execute("CREATE TABLE files(path TEXT PRIMARY KEY, digest TEXT NOT NULL)")
        connection.execute("INSERT INTO files VALUES (?, ?)", ("README.md", "abc123"))

    api_root = root / "api"
    key_store = KeyStore(api_root)
    api_token, api_record = key_store.create("backup secret", ["chat"])
    accounts = AccountStore(api_root)
    registration = accounts.register("backup@example.com", "backup account password", "Backup")
    accounts.verify_email(registration["verification_token"])
    login = accounts.login("backup@example.com", "backup account password", "PC", "test")
    guest = accounts.create_guest("Guest", "test")
    with sqlite3.connect(api_root / "aurorafox.sqlite3") as connection:
        connection.execute("CREATE TABLE durable_data(value TEXT NOT NULL)")
        connection.execute("INSERT INTO durable_data VALUES (?)", ("keep-me",))
        password_hash = connection.execute(
            "SELECT password_hash FROM accounts WHERE id=?", (registration["account"]["id"],)
        ).fetchone()[0]

    secret_hashes = {
        hashlib.sha256(api_token.encode("utf-8")).hexdigest(),
        hashlib.sha256(login["access_token"].encode("utf-8")).hexdigest(),
        hashlib.sha256(login["refresh_token"].encode("utf-8")).hexdigest(),
        hashlib.sha256(guest["guest_token"].encode("utf-8")).hexdigest(),
        str(password_hash),
    }
    assert api_record["token_hash"] in secret_hashes

    result = BackupService(root, tmp_path / "cache").create_archive()
    assert result.file_count == 4
    assert result.sha256 == hashlib.sha256(result.archive_path.read_bytes()).hexdigest()

    with zipfile.ZipFile(result.archive_path) as archive:
        names = set(archive.namelist())
        assert "manifest.json" in names
        assert "data/api/conversations/chat.json" in names
        assert "data/api/aurorafox.sqlite3" in names
        assert "data/memory.json" in names
        assert "data/project_index.sqlite3" in names
        assert not any(name.endswith("keys.json") or name.endswith("bootstrap_key.txt") for name in names)
        assert not any("models" in name.lower() for name in names)

        manifest = json.loads(archive.read("manifest.json"))
        assert manifest["schema"] == "aurorafox.backup.v1"
        assert manifest["credential_files_included"] is False
        assert manifest["database_credentials_sanitized"] is True
        assert manifest["storage_maintenance"] is not None
        assert manifest["storage_maintenance"]["hard_pressure"] is False
        assert manifest["file_count"] == 4
        api_item = next(item for item in manifest["files"] if item["path"] == "data/api/aurorafox.sqlite3")
        assert api_item["credentials_sanitized"] is True
        for item in manifest["files"]:
            payload = archive.read(item["path"])
            assert len(payload) == item["bytes"]
            assert _sha256(payload) == item["sha256"]

        extracted = tmp_path / "restored.sqlite3"
        extracted.write_bytes(archive.read("data/project_index.sqlite3"))
        with sqlite3.connect(extracted) as connection:
            assert connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert connection.execute("SELECT path, digest FROM files").fetchone() == ("README.md", "abc123")

        api_extracted = tmp_path / "restored-api.sqlite3"
        api_payload = archive.read("data/api/aurorafox.sqlite3")
        for secret_hash in secret_hashes:
            assert secret_hash.encode("ascii") not in api_payload
        api_extracted.write_bytes(api_payload)
        with sqlite3.connect(api_extracted) as connection:
            assert connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert connection.execute("SELECT COUNT(*) FROM api_keys").fetchone()[0] == 0
            assert connection.execute("SELECT COUNT(*) FROM auth_sessions").fetchone()[0] == 0
            assert connection.execute("SELECT COUNT(*) FROM refresh_tokens").fetchone()[0] == 0
            assert connection.execute("SELECT COUNT(*) FROM account_tokens").fetchone()[0] == 0
            assert connection.execute("SELECT password_hash FROM accounts").fetchone()[0] == ""
            assert connection.execute("SELECT token_hash FROM guests").fetchone()[0].startswith("redacted:")
            assert connection.execute("SELECT value FROM durable_data").fetchone()[0] == "keep-me"
            assert connection.execute(
                "SELECT COUNT(*) FROM metadata WHERE key LIKE 'migration.api_keys.%'"
            ).fetchone()[0] == 0


def test_backup_size_limit_fails_closed(tmp_path: Path):
    root = tmp_path / "user"
    root.mkdir()
    (root / "memory.json").write_text('{"payload":"too large"}\n', encoding="utf-8")
    with pytest.raises(BackupTooLarge):
        BackupService(root, tmp_path / "cache", max_source_bytes=4).create_archive()


def test_backup_rechecks_materialized_size_after_transform(tmp_path: Path, monkeypatch):
    root = tmp_path / "user"
    root.mkdir()
    (root / "memory.json").write_text("{}", encoding="utf-8")
    cache = tmp_path / "cache"
    service = BackupService(root, cache, max_source_bytes=8)

    def inflate_copy(_source: Path, destination: Path) -> bool:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(b"x" * 16)
        return False

    monkeypatch.setattr(service, "_copy_source", inflate_copy)
    with pytest.raises(BackupTooLarge, match="materialized backup data"):
        service.create_archive()
    assert not list(cache.glob("AuroraFox-Server-Backup-*.zip"))
    assert not list(cache.glob("*.tmp"))


def test_backup_fails_before_snapshot_when_disk_pressure_is_critical(tmp_path: Path, monkeypatch):
    root = tmp_path / "user"
    api_root = root / "api"
    AccountStore(api_root)
    monkeypatch.setenv("AURORAFOX_STORAGE_MIN_FREE_BYTES", str(10**18))
    with pytest.raises(BackupStoragePressure, match="critically low free space"):
        BackupService(root, tmp_path / "cache").create_archive()
    assert not list((tmp_path / "cache").glob("AuroraFox-Server-Backup-*.zip"))


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
