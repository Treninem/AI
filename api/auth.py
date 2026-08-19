from __future__ import annotations

import hashlib
import hmac
import json
import secrets
import time
from pathlib import Path
from typing import Any


DEFAULT_SCOPES = ["chat", "feedback", "models.read", "conversations.read", "files", "tools.read"]
ADMIN_SCOPES = ["*"]


class KeyStore:
    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.path = self.root / "keys.json"
        self.bootstrap_path = self.root / "bootstrap_key.txt"

    @staticmethod
    def _hash(token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

    def _load(self) -> dict[str, Any]:
        if not self.path.is_file():
            return {"keys": []}
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            if isinstance(data, dict) and isinstance(data.get("keys"), list):
                return data
        except Exception:
            pass
        return {"keys": []}

    def _save(self, data: dict[str, Any]) -> None:
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        tmp.replace(self.path)

    def ensure_bootstrap_key(self) -> str | None:
        data = self._load()
        active = [x for x in data["keys"] if isinstance(x, dict) and not x.get("revoked", False)]
        if active:
            return None
        token, record = self._new_record("AuroraFox local admin", ADMIN_SCOPES, prefix="af_admin")
        data["keys"].append(record)
        self._save(data)
        self.bootstrap_path.write_text(token + "\n", encoding="utf-8")
        return token

    def _new_record(self, name: str, scopes: list[str], prefix: str = "af_live") -> tuple[str, dict[str, Any]]:
        token = f"{prefix}_{secrets.token_urlsafe(32)}"
        record = {
            "id": secrets.token_hex(8),
            "name": name.strip() or "AuroraFox integration",
            "token_hash": self._hash(token),
            "scopes": sorted(set(scopes or DEFAULT_SCOPES)),
            "created_at": int(time.time()),
            "revoked": False,
        }
        return token, record

    def create(self, name: str, scopes: list[str] | None = None) -> tuple[str, dict[str, Any]]:
        data = self._load()
        token, record = self._new_record(name, scopes or DEFAULT_SCOPES)
        data["keys"].append(record)
        self._save(data)
        return token, record

    def list(self) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for item in self._load()["keys"]:
            if not isinstance(item, dict):
                continue
            clean = dict(item)
            clean.pop("token_hash", None)
            out.append(clean)
        return out

    def revoke(self, key_id: str) -> bool:
        data = self._load()
        changed = False
        for item in data["keys"]:
            if isinstance(item, dict) and str(item.get("id", "")) == key_id:
                item["revoked"] = True
                changed = True
        if changed:
            self._save(data)
        return changed

    def verify(self, token: str) -> dict[str, Any] | None:
        if not token:
            return None
        digest = self._hash(token)
        for item in self._load()["keys"]:
            if not isinstance(item, dict) or item.get("revoked", False):
                continue
            stored = str(item.get("token_hash", ""))
            if stored and hmac.compare_digest(digest, stored):
                return dict(item)
        return None


def allows(record: dict[str, Any], required: str) -> bool:
    scopes = {str(x) for x in record.get("scopes", [])}
    if "*" in scopes or required in scopes:
        return True
    namespace = required.split(".", 1)[0] + ".*"
    return namespace in scopes
