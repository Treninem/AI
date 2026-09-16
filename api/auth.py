from __future__ import annotations

import hashlib
import hmac
import json
import secrets
import time
from pathlib import Path
from typing import Any

from api.database import AuroraDatabase, atomic_write_text


DEFAULT_SCOPES = [
    "chat",
    "feedback",
    "memory.read",
    "memory.write",
    "models.read",
    "conversations.read",
    "files",
    "tools.read",
]
ADMIN_SCOPES = ["*"]


class KeyStore:
    LEGACY_MIGRATION_KEY = "migration.api_keys.keys_json.v1"

    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.path = self.root / "keys.json"
        self.bootstrap_path = self.root / "bootstrap_key.txt"
        self.database = AuroraDatabase(self.root / "aurorafox.sqlite3")
        self._migrate_legacy_once()

    @staticmethod
    def _hash(token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

    @staticmethod
    def _normalize_scopes(scopes: list[str] | None) -> list[str]:
        values = [str(value).strip() for value in (scopes or DEFAULT_SCOPES)]
        return sorted({value for value in values if value}) or list(DEFAULT_SCOPES)

    @staticmethod
    def _row_record(row: Any) -> dict[str, Any]:
        try:
            scopes = json.loads(str(row["scopes_json"]))
        except Exception:
            scopes = []
        if not isinstance(scopes, list):
            scopes = []
        return {
            "id": str(row["id"]),
            "name": str(row["name"]),
            "token_hash": str(row["token_hash"]),
            "scopes": [str(value) for value in scopes],
            "created_at": int(row["created_at"]),
            "revoked": bool(row["revoked"]),
        }

    def _read_legacy(self) -> list[dict[str, Any]]:
        if not self.path.is_file():
            return []
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except Exception:
            return []
        rows = data.get("keys", []) if isinstance(data, dict) else []
        return [dict(item) for item in rows if isinstance(item, dict)]

    def _migrate_legacy_once(self) -> None:
        if self.database.get_meta(self.LEGACY_MIGRATION_KEY) is not None:
            return
        legacy = self._read_legacy()
        imported = 0
        with self.database.connection(write=True) as connection:
            for item in legacy:
                key_id = str(item.get("id", "")).strip()
                token_hash = str(item.get("token_hash", "")).strip().lower()
                if not key_id or len(token_hash) != 64:
                    continue
                scopes = self._normalize_scopes(item.get("scopes", DEFAULT_SCOPES))
                before = connection.total_changes
                connection.execute(
                    "INSERT OR IGNORE INTO api_keys(id, name, token_hash, scopes_json, created_at, revoked) "
                    "VALUES(?, ?, ?, ?, ?, ?)",
                    (
                        key_id,
                        str(item.get("name", "AuroraFox integration")).strip() or "AuroraFox integration",
                        token_hash,
                        json.dumps(scopes, ensure_ascii=False, separators=(",", ":")),
                        int(item.get("created_at", int(time.time()))),
                        1 if bool(item.get("revoked", False)) else 0,
                    ),
                )
                if connection.total_changes > before:
                    imported += 1
            connection.execute(
                "INSERT INTO metadata(key, value, updated_at) VALUES(?, ?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
                (self.LEGACY_MIGRATION_KEY, json.dumps({"imported": imported}), int(time.time())),
            )
        # Preserve a rollback-readable mirror. It contains only token hashes,
        # exactly like the legacy format; raw bearer secrets never enter SQLite.
        self._write_legacy_mirror()

    def _all_records(self) -> list[dict[str, Any]]:
        with self.database.connection() as connection:
            rows = connection.execute(
                "SELECT id, name, token_hash, scopes_json, created_at, revoked "
                "FROM api_keys ORDER BY created_at, id"
            ).fetchall()
        return [self._row_record(row) for row in rows]

    def _write_legacy_mirror(self) -> None:
        payload = {"keys": self._all_records()}
        atomic_write_text(self.path, json.dumps(payload, ensure_ascii=False, indent=2) + "\n", mode=0o600)

    def ensure_bootstrap_key(self) -> str | None:
        with self.database.connection() as connection:
            active = int(connection.execute("SELECT COUNT(*) FROM api_keys WHERE revoked=0").fetchone()[0])
        if active:
            return None
        token, record = self._new_record("AuroraFox local admin", ADMIN_SCOPES, prefix="af_admin")
        self._insert_record(record)
        self._write_legacy_mirror()
        atomic_write_text(self.bootstrap_path, token + "\n", mode=0o600)
        return token

    def _new_record(self, name: str, scopes: list[str], prefix: str = "af_live") -> tuple[str, dict[str, Any]]:
        token = f"{prefix}_{secrets.token_urlsafe(32)}"
        record = {
            "id": secrets.token_hex(8),
            "name": name.strip() or "AuroraFox integration",
            "token_hash": self._hash(token),
            "scopes": self._normalize_scopes(scopes),
            "created_at": int(time.time()),
            "revoked": False,
        }
        return token, record

    def _insert_record(self, record: dict[str, Any]) -> None:
        with self.database.connection(write=True) as connection:
            connection.execute(
                "INSERT INTO api_keys(id, name, token_hash, scopes_json, created_at, revoked) "
                "VALUES(?, ?, ?, ?, ?, ?)",
                (
                    str(record["id"]),
                    str(record["name"]),
                    str(record["token_hash"]),
                    json.dumps(record["scopes"], ensure_ascii=False, separators=(",", ":")),
                    int(record["created_at"]),
                    1 if bool(record.get("revoked", False)) else 0,
                ),
            )

    def create(self, name: str, scopes: list[str] | None = None) -> tuple[str, dict[str, Any]]:
        token, record = self._new_record(name, scopes or DEFAULT_SCOPES)
        self._insert_record(record)
        self._write_legacy_mirror()
        return token, record

    def list(self) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for item in self._all_records():
            clean = dict(item)
            clean.pop("token_hash", None)
            out.append(clean)
        return out

    def revoke(self, key_id: str) -> bool:
        with self.database.connection(write=True) as connection:
            cursor = connection.execute("UPDATE api_keys SET revoked=1 WHERE id=? AND revoked=0", (key_id,))
            changed = cursor.rowcount > 0
        if changed:
            self._write_legacy_mirror()
        return changed

    def verify(self, token: str) -> dict[str, Any] | None:
        if not token:
            return None
        digest = self._hash(token)
        # Keep constant-time digest comparison even though SQLite already narrows
        # the sensitive state to hashes rather than raw bearer tokens.
        with self.database.connection() as connection:
            rows = connection.execute(
                "SELECT id, name, token_hash, scopes_json, created_at, revoked "
                "FROM api_keys WHERE revoked=0"
            ).fetchall()
        for row in rows:
            stored = str(row["token_hash"])
            if stored and hmac.compare_digest(digest, stored):
                return self._row_record(row)
        return None


def allows(record: dict[str, Any], required: str) -> bool:
    scopes = {str(x) for x in record.get("scopes", [])}
    if "*" in scopes or required in scopes:
        return True
    namespace = required.split(".", 1)[0] + ".*"
    return namespace in scopes
