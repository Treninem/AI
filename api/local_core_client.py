from __future__ import annotations

import json
import os
import re
import subprocess
import threading
import time
from pathlib import Path
from typing import Any

import requests


_TOKEN_RE = re.compile(r"[0-9A-Za-zА-Яа-яЁё_\-]{2,}", re.UNICODE)


class AuroraLocalCoreClient:
    """Use AuroraFox's own llama.cpp server without making Ollama a dependency.

    The desktop Godot runtime normally owns 127.0.0.1:8766. If the UI/bridge is
    down but the packaged Core Engine and a GGUF are present, the API may start
    that same local engine itself. Nothing here downloads a model or contacts an
    external inference provider.
    """

    def __init__(
        self,
        user_root: Path,
        base_url: str = "http://127.0.0.1:8766",
        timeout: float = 180.0,
    ) -> None:
        self.user_root = Path(user_root).resolve()
        self.base_url = base_url.rstrip("/")
        self.timeout = max(5.0, timeout)
        self._process: subprocess.Popen[Any] | None = None
        self._active_model = ""
        self._lock = threading.Lock()
        self._quarantine: dict[str, tuple[tuple[int, int], float, int]] = {}

    def status(self) -> dict[str, Any]:
        online = self._health()
        return {
            "ok": online,
            "runtime": "aurorafox-local-core",
            "endpoint": self.base_url,
            "engine": str(self._engine_path() or ""),
            "models": [str(p) for p in self._model_candidates()],
            "active_model": self._active_model,
            "owned_process": bool(self._process and self._process.poll() is None),
        }

    def chat(self, messages: list[dict[str, Any]], temperature: float = 0.2) -> dict[str, Any]:
        if not self._health():
            started = self._ensure_server()
            if not started.get("ok", False):
                raise RuntimeError(str(started.get("error", "AuroraFox local Core is not ready")))
        response = requests.post(
            f"{self.base_url}/v1/chat/completions",
            json={
                "model": "AuroraFox-Core",
                "messages": messages,
                "temperature": float(temperature),
                "stream": False,
            },
            timeout=self.timeout,
        )
        response.raise_for_status()
        payload = response.json()
        choices = payload.get("choices", []) if isinstance(payload, dict) else []
        if not choices or not isinstance(choices[0], dict):
            raise RuntimeError("AuroraFox local Core returned no choices")
        message = choices[0].get("message", {})
        if not isinstance(message, dict):
            raise RuntimeError("AuroraFox local Core returned an invalid message")
        content = str(message.get("content", ""))
        if not content.strip():
            raise RuntimeError("AuroraFox local Core returned an empty answer")
        return {
            "ok": True,
            "content": content,
            "model": str(payload.get("model", "AuroraFox-Core")),
            "runtime": "aurorafox-local-core",
            "raw": payload,
        }

    def _health(self) -> bool:
        try:
            response = requests.get(f"{self.base_url}/health", timeout=1.5)
            return 200 <= response.status_code < 300
        except Exception:
            return False

    def _ensure_server(self) -> dict[str, Any]:
        if os.name != "nt":
            return {"ok": False, "error": "AuroraFox desktop Core autostart is Windows-only"}
        with self._lock:
            if self._health():
                return {"ok": True, "reused": True}
            engine = self._engine_path()
            if engine is None:
                return {"ok": False, "error": "AuroraFox Core Engine is not installed"}
            candidates = self._model_candidates()
            if not candidates:
                return {"ok": False, "error": "No local AuroraFox GGUF is installed"}
            errors: list[str] = []
            for model in candidates:
                identity = self._identity(model)
                quarantine = self._quarantine.get(str(model))
                if quarantine and quarantine[0] == identity and time.time() < quarantine[1]:
                    continue
                try:
                    self._start(engine, model)
                    deadline = time.monotonic() + 120.0
                    while time.monotonic() < deadline:
                        if self._process is not None and self._process.poll() is not None:
                            break
                        if self._health():
                            self._active_model = str(model)
                            self._quarantine.pop(str(model), None)
                            return {"ok": True, "model": str(model), "engine": str(engine)}
                        time.sleep(0.25)
                    errors.append(f"{model.name}: engine did not become healthy")
                except Exception as exc:
                    errors.append(f"{model.name}: {exc}")
                self._stop_owned()
                previous = self._quarantine.get(str(model))
                failures = (previous[2] + 1) if previous and previous[0] == identity else 1
                backoff = min(900.0, 5.0 * (2 ** min(7, failures - 1)))
                self._quarantine[str(model)] = (identity, time.time() + backoff, failures)
            return {"ok": False, "error": "; ".join(errors[-4:]) or "No healthy local GGUF candidate"}

    def _start(self, engine: Path, model: Path) -> None:
        self._stop_owned()
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        self._process = subprocess.Popen(
            [
                str(engine), "-m", str(model), "--host", "127.0.0.1", "--port", "8766",
                "--ctx-size", "8192", "--alias", "AuroraFox-Core", "--jinja",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            creationflags=creationflags,
        )

    def _stop_owned(self) -> None:
        process = self._process
        self._process = None
        if process is None or process.poll() is not None:
            return
        try:
            process.terminate()
            process.wait(timeout=3)
        except Exception:
            try:
                process.kill()
            except Exception:
                pass

    def _engine_path(self) -> Path | None:
        explicit = os.getenv("AURORAFOX_CORE_ENGINE", "").strip()
        if explicit:
            path = Path(explicit).expanduser()
            if path.is_file():
                return path.resolve()
        project_root = Path(__file__).resolve().parents[1]
        roots = [project_root / "core_runtime" / "engine", project_root.parent / "core_runtime" / "engine"]
        for root in roots:
            if not root.is_dir():
                continue
            direct = root / "llama-server.exe"
            if direct.is_file():
                return direct.resolve()
            for candidate in root.rglob("llama-server.exe"):
                if candidate.is_file():
                    return candidate.resolve()
        return None

    def _model_candidates(self) -> list[Path]:
        roots: list[Path] = []
        explicit = os.getenv("AURORAFOX_MODEL_PATH", "").strip()
        if explicit:
            path = Path(explicit).expanduser()
            if path.is_file() and self._valid_gguf(path):
                return [path.resolve()]
            if path.is_dir():
                roots.append(path)
        roots.append(self.user_root / "models")
        appdata = os.getenv("APPDATA", "").strip()
        if appdata:
            roots.append(Path(appdata) / "Godot" / "app_userdata" / "AuroraFox" / "models")
        unique: dict[str, Path] = {}
        for root in roots:
            if not root.is_dir():
                continue
            for path in root.glob("*.gguf"):
                if self._valid_gguf(path):
                    unique[str(path.resolve()).lower()] = path.resolve()
        items = list(unique.values())
        items.sort(key=lambda p: (0 if p.name.lower() == "aurorafox-main.gguf" else 1, p.name.lower()))
        return items

    @staticmethod
    def _identity(path: Path) -> tuple[int, int]:
        stat = path.stat()
        return int(stat.st_size), int(stat.st_mtime_ns)

    @staticmethod
    def _valid_gguf(path: Path) -> bool:
        try:
            if path.stat().st_size < 1024 * 1024:
                return False
            with path.open("rb") as handle:
                return handle.read(4) == b"GGUF"
        except OSError:
            return False


class AuroraKnowledgeFallback:
    """Last-resort local answer path when no inference runtime is currently healthy."""

    def __init__(self, user_root: Path) -> None:
        self.user_root = Path(user_root).resolve()

    def reply(self, message: str, limit: int = 5) -> dict[str, Any]:
        terms = {m.group(0).lower() for m in _TOKEN_RE.finditer(message)}
        scored: list[tuple[int, str, str]] = []
        if terms:
            for path in self._knowledge_paths():
                if not path.is_file():
                    continue
                try:
                    with path.open("r", encoding="utf-8", errors="replace") as handle:
                        for line in handle:
                            line = line.strip()
                            if not line:
                                continue
                            try:
                                row = json.loads(line)
                            except Exception:
                                continue
                            if not isinstance(row, dict):
                                continue
                            text = str(row.get("text") or row.get("content") or "").strip()
                            if not text:
                                continue
                            haystack = text.lower()
                            score = sum(2 if term in haystack else 0 for term in terms)
                            source = str(row.get("source", "local knowledge"))
                            if score > 0:
                                scored.append((score, text[:1400], source))
                except OSError:
                    continue
        scored.sort(key=lambda item: item[0], reverse=True)
        selected: list[tuple[int, str, str]] = []
        seen: set[str] = set()
        for row in scored:
            key = row[1]
            if key in seen:
                continue
            seen.add(key)
            selected.append(row)
            if len(selected) >= max(1, limit):
                break
        if selected:
            pieces = ["По доступной локальной базе AuroraFox нашла следующее:"]
            for _, text, source in selected:
                pieces.append(f"- {text}\n  Источник: {source}")
            return {
                "ok": True,
                "content": "\n".join(pieces)[:7000],
                "model": "local-knowledge",
                "runtime": "aurorafox-local-knowledge",
                "degraded": True,
                "matches": len(selected),
            }
        return {
            "ok": True,
            "content": "AuroraFox приняла запрос и продолжает работать локально. Для этого запроса в доступной локальной базе пока нет подходящего материала.",
            "model": "local-deterministic",
            "runtime": "aurorafox-local-deterministic",
            "degraded": True,
            "matches": 0,
        }

    def _knowledge_paths(self) -> list[Path]:
        out: list[Path] = []
        explicit = os.getenv("AURORAFOX_KNOWLEDGE_PATH", "").strip()
        if explicit:
            out.append(Path(explicit).expanduser())
        out.append(self.user_root / "knowledge" / "knowledge.jsonl")
        appdata = os.getenv("APPDATA", "").strip()
        if appdata:
            out.append(Path(appdata) / "Godot" / "app_userdata" / "AuroraFox" / "knowledge" / "knowledge.jsonl")
        unique: list[Path] = []
        seen: set[str] = set()
        for path in out:
            key = str(path).lower()
            if key not in seen:
                seen.add(key)
                unique.append(path)
        return unique
