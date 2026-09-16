from __future__ import annotations

import base64
import hashlib
import os
import re
import time
from pathlib import Path
from typing import Any

import requests


DEFAULT_MAX_FILE_BYTES = 16 * 1024 * 1024
DEFAULT_UPLOAD_TTL_SECONDS = 24 * 60 * 60


class FileIntelligenceClient:
    def __init__(
        self,
        root: Path,
        base_url: str = "http://127.0.0.1:8767",
        *,
        max_file_bytes: int | None = None,
        upload_ttl_seconds: int | None = None,
    ):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.base_url = base_url.rstrip("/")
        configured_max = max_file_bytes
        if configured_max is None:
            configured_max = int(os.getenv("AURORAFOX_API_FILE_MAX_BYTES", str(DEFAULT_MAX_FILE_BYTES)))
        self.max_file_bytes = max(1, int(configured_max))
        self.max_encoded_chars = 4 * ((self.max_file_bytes + 2) // 3)
        configured_ttl = upload_ttl_seconds
        if configured_ttl is None:
            configured_ttl = int(os.getenv("AURORAFOX_API_UPLOAD_TTL_SECONDS", str(DEFAULT_UPLOAD_TTL_SECONDS)))
        self.upload_ttl_seconds = max(60, int(configured_ttl))
        self._prune_stale_uploads()

    @staticmethod
    def _safe_name(name: str) -> str:
        cleaned = re.sub(r"[^A-Za-z0-9._-]+", "_", Path(name).name).strip("._")
        return cleaned[:160] or "upload.bin"

    def _prune_stale_uploads(self) -> int:
        cutoff = time.time() - self.upload_ttl_seconds
        removed = 0
        for path in self.root.iterdir():
            try:
                if path.is_file() and not path.is_symlink() and path.stat().st_mtime < cutoff:
                    path.unlink()
                    removed += 1
            except OSError:
                continue
        return removed

    def save_base64(self, filename: str, content_base64: str) -> Path:
        if len(content_base64) > self.max_encoded_chars:
            raise ValueError(
                f"File payload exceeds AuroraFox API limit of {self.max_file_bytes} decoded bytes"
            )
        raw = base64.b64decode(content_base64, validate=True)
        if len(raw) > self.max_file_bytes:
            raise ValueError(
                f"Decoded file exceeds AuroraFox API limit of {self.max_file_bytes} bytes"
            )
        digest = hashlib.sha256(raw).hexdigest()[:16]
        safe = self._safe_name(filename)
        target = self.root / f"{digest}_{safe}"
        target.write_bytes(raw)
        return target

    def analyze_path(self, path: Path, question: str = "", visual: bool = True) -> dict[str, Any]:
        response = requests.post(
            f"{self.base_url}/analyze",
            json={"path": str(path.resolve()), "question": question, "visual": visual},
            timeout=180,
        )
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise RuntimeError("Invalid File Intelligence response")
        return payload

    def analyze_base64(self, filename: str, content_base64: str, question: str = "", visual: bool = True) -> dict[str, Any]:
        path = self.save_base64(filename, content_base64)
        try:
            return self.analyze_path(path, question, visual)
        finally:
            # API uploads are transient transport artifacts, not user storage.
            # Delete them after both successful and failed analyses so repeated
            # integrations cannot silently exhaust the server disk.
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass
