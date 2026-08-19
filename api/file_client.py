from __future__ import annotations

import base64
import hashlib
import re
from pathlib import Path
from typing import Any

import requests


class FileIntelligenceClient:
    def __init__(self, root: Path, base_url: str = "http://127.0.0.1:8767"):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.base_url = base_url.rstrip("/")

    @staticmethod
    def _safe_name(name: str) -> str:
        cleaned = re.sub(r"[^A-Za-z0-9._-]+", "_", Path(name).name).strip("._")
        return cleaned[:160] or "upload.bin"

    def save_base64(self, filename: str, content_base64: str) -> Path:
        raw = base64.b64decode(content_base64, validate=True)
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
        return self.analyze_path(path, question, visual)
