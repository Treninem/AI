from __future__ import annotations

import base64
import hashlib
import hmac
import json
import multiprocessing as mp
import os
import re
import shutil
import signal
import subprocess
import threading
import time
import uuid
from collections import OrderedDict
from pathlib import Path, PurePath
from typing import Any

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

HOST = os.getenv("AURORAFOX_COMPUTER_HOST", "127.0.0.1")
PORT = int(os.getenv("AURORAFOX_COMPUTER_PORT", "8766"))
SERVICE_TOKEN = os.getenv("AURORAFOX_COMPUTER_TOKEN", "").strip()
PARENT_PID = int(os.getenv("AURORAFOX_PARENT_PID", "0") or "0")
SANDBOX_ROOT = Path(os.getenv("AURORAFOX_SANDBOX_ROOT", str(Path.cwd() / "sandbox"))).resolve()
MAX_OUTPUT = 120_000
MAX_WRITE_BYTES = 2_000_000
MAX_READ_BYTES = 5_000_000
MAX_TEXT_CHARS = 20_000
MAX_KEYS = 12
MAX_SNAPSHOT_ENTRIES = int(os.getenv("AURORAFOX_SNAPSHOT_MAX_ENTRIES", "5000"))
MAX_SNAPSHOT_BYTES = int(os.getenv("AURORAFOX_SNAPSHOT_MAX_BYTES", str(512 * 1024 * 1024)))
GUI_TIMEOUT_SECONDS = float(os.getenv("AURORAFOX_GUI_TIMEOUT_SECONDS", "8"))
ACTION_TIMEOUT_SECONDS = float(os.getenv("AURORAFOX_ACTION_TIMEOUT_SECONDS", "10"))
IS_WINDOWS = os.name == "nt"
ALLOW_DEGRADED_LOCAL_SANDBOX = os.getenv("AURORAFOX_ALLOW_DEGRADED_LOCAL_SANDBOX", "").strip() == "1"

SAFE_RETRY_ACTIONS = {"move", "wait", "done"}
UNSAFE_RETRY_ACTIONS = {"scroll", "click", "double_click", "right_click", "mouse_down", "mouse_up", "type", "press", "hotkey"}
VALID_ACTIONS = SAFE_RETRY_ACTIONS | UNSAFE_RETRY_ACTIONS
VALID_BUTTONS = {"left", "right", "middle"}
VALID_KEY = re.compile(r"^[A-Za-z0-9_+\-.,/\\\[\];'`]{1,32}$")
ACTION_CACHE_LIMIT = 512

SANDBOX_ROOT.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="AuroraFox Computer Primitive Service", version="1.1.0")
_action_cache: OrderedDict[str, dict[str, Any]] = OrderedDict()
_action_inflight: set[str] = set()
_action_cache_lock = threading.Lock()
_action_execution_lock = threading.Lock()


class Action(BaseModel):
    type: str = Field(min_length=1, max_length=32)
    action_id: str = Field(default="", max_length=160)
    x: int | None = None
    y: int | None = None
    button: str = "left"
    clicks: int = Field(default=1, ge=1, le=3)
    text: str = Field(default="", max_length=MAX_TEXT_CHARS)
    keys: list[str] = Field(default_factory=list, max_length=MAX_KEYS)
    amount: int = Field(default=0, ge=-100, le=100)
    seconds: float = Field(default=0.2, ge=0.0, le=5.0)
    verify: bool = False


class GoalRequest(BaseModel):
    goal: str = Field(min_length=1, max_length=8000)
    max_steps: int = Field(default=20, ge=1, le=100)
    auto_execute: bool = False


class SandboxExecRequest(BaseModel):
    command: list[str] = Field(min_length=1, max_length=64)
    cwd: str = Field(default=".", max_length=1024)
    timeout: int = Field(default=60, ge=1, le=300)
    allow_network: bool = False


class SandboxWriteRequest(BaseModel):
    path: str = Field(min_length=1, max_length=1024)
    content: str


class WorkspaceCreateRequest(BaseModel):
    id: str = Field(default="", max_length=96)
    task: str = Field(default="", max_length=4000)


class WorkspaceSnapshotRequest(BaseModel):
    workspace: str = Field(min_length=1, max_length=96)
    label: str = Field(default="checkpoint", max_length=64)


class WorkspaceRollbackRequest(BaseModel):
    workspace: str = Field(min_length=1, max_length=96)
    snapshot: str = Field(min_length=1, max_length=128)


def _auth(token: str | None) -> None:
    if not SERVICE_TOKEN:
        raise HTTPException(status_code=503, detail="Computer service authentication is not configured")
    if not hmac.compare_digest(token or "", SERVICE_TOKEN):
        raise HTTPException(status_code=401, detail="Computer service authentication failed")


def _autonomy_allowed(value: str | None) -> None:
    if value != "1":
        raise HTTPException(status_code=423, detail="Master stop or Computer permission is active")


def _authorize(token: str | None, autonomy: str | None, *, require_autonomy: bool = True) -> None:
    _auth(token)
    if require_autonomy:
        _autonomy_allowed(autonomy)


def _retryable(action_type: str) -> bool:
    return action_type in SAFE_RETRY_ACTIONS


def _error(kind: str, message: str, *, retryable: bool = False, **extra: Any) -> dict[str, Any]:
    result: dict[str, Any] = {"ok": False, "error": kind, "message": _redact(message), "retryable": retryable}
    result.update(extra)
    return result


def _redact(value: str) -> str:
    text = str(value)
    text = re.sub(
        r"(?i)(password|passwd|token|api[_-]?key|authorization|cookie|private[_-]?key)\s*[:=]\s*[^\s,;]+",
        r"\1=[REDACTED]",
        text,
    )
    text = re.sub(r"(?i)bearer\s+[A-Za-z0-9._~+/-]{8,}", "Bearer [REDACTED]", text)
    if SERVICE_TOKEN:
        text = text.replace(SERVICE_TOKEN, "[REDACTED]")
    return text[:MAX_OUTPUT]


def _safe_sandbox_path(relative: str, *, must_exist: bool = False) -> Path:
    raw = str(relative).strip()
    if not raw:
        raise HTTPException(status_code=400, detail="Empty sandbox path")
    candidate_path = Path(raw)
    if candidate_path.is_absolute() or PurePath(raw).anchor:
        raise HTTPException(status_code=400, detail="Absolute paths are not allowed in sandbox")
    if any(part == ".." for part in candidate_path.parts):
        raise HTTPException(status_code=400, detail="Path traversal is not allowed")
    target = (SANDBOX_ROOT / candidate_path).resolve(strict=False)
    if target != SANDBOX_ROOT and SANDBOX_ROOT not in target.parents:
        raise HTTPException(status_code=400, detail="Path escapes sandbox")
    if must_exist and not target.exists():
        raise HTTPException(status_code=404, detail="Sandbox path not found")
    return target


def _safe_workspace_id(value: str) -> str:
    cleaned = "".join(ch for ch in str(value) if ch.isalnum() or ch in "_-. ").strip().replace(" ", "_").strip(".")
    if not cleaned or len(cleaned) > 96 or cleaned in {".", ".."}:
        raise HTTPException(status_code=400, detail="Invalid workspace id")
    return cleaned


def _snapshot_tree_stats(root: Path) -> dict[str, int]:
    if not root.exists() or not root.is_dir():
        raise HTTPException(status_code=404, detail="Snapshot source directory not found")
    entries = 0
    total_bytes = 0
    stack = [root]
    while stack:
        current = stack.pop()
        try:
            with os.scandir(current) as iterator:
                children = list(iterator)
        except OSError as exc:
            raise HTTPException(status_code=500, detail=f"Cannot inspect snapshot tree: {type(exc).__name__}") from exc
        for entry in children:
            entries += 1
            if entries > MAX_SNAPSHOT_ENTRIES:
                raise HTTPException(status_code=413, detail="Snapshot contains too many filesystem entries")
            if entry.is_symlink():
                raise HTTPException(status_code=400, detail="Symlinks are not allowed in workspace snapshots")
            try:
                if entry.is_dir(follow_symlinks=False):
                    stack.append(Path(entry.path))
                elif entry.is_file(follow_symlinks=False):
                    total_bytes += int(entry.stat(follow_symlinks=False).st_size)
                    if total_bytes > MAX_SNAPSHOT_BYTES:
                        raise HTTPException(status_code=413, detail="Snapshot exceeds the configured byte limit")
                else:
                    raise HTTPException(status_code=400, detail="Special filesystem entries are not allowed in workspace snapshots")
            except HTTPException:
                raise
            except OSError as exc:
                raise HTTPException(status_code=500, detail=f"Cannot inspect snapshot entry: {type(exc).__name__}") from exc
    return {"entries": entries, "bytes": total_bytes}


def _copy_snapshot_tree(source: Path, target: Path) -> dict[str, int]:
    _snapshot_tree_stats(source)
    try:
        # Never follow a link introduced after preflight. The post-copy validation
        # below then rejects and removes any raced-in link rather than persisting it.
        shutil.copytree(source, target, symlinks=True)
        return _snapshot_tree_stats(target)
    except Exception:
        if target.exists():
            shutil.rmtree(target, ignore_errors=True)
        raise


def _desktop_bounds() -> dict[str, int]:
    if not IS_WINDOWS:
        return {"left": 0, "top": 0, "width": 0, "height": 0, "right": 0, "bottom": 0}
    try:
        import ctypes

        user32 = ctypes.windll.user32
        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(2)
        except Exception:
            try:
                user32.SetProcessDPIAware()
            except Exception:
                pass
        left = int(user32.GetSystemMetrics(76))
        top = int(user32.GetSystemMetrics(77))
        width = int(user32.GetSystemMetrics(78))
        height = int(user32.GetSystemMetrics(79))
        return {"left": left, "top": top, "width": width, "height": height, "right": left + width, "bottom": top + height}
    except Exception:
        return {"left": 0, "top": 0, "width": 0, "height": 0, "right": 0, "bottom": 0}


def _validate_coordinate(x: int | None, y: int | None) -> None:
    if x is None or y is None:
        raise HTTPException(status_code=400, detail="Action requires x and y coordinates")
    bounds = _desktop_bounds()
    if bounds["width"] <= 0 or bounds["height"] <= 0:
        raise HTTPException(status_code=503, detail="Desktop coordinate space is unavailable")
    if not (bounds["left"] <= x < bounds["right"] and bounds["top"] <= y < bounds["bottom"]):
        raise HTTPException(status_code=400, detail="Coordinates are outside the virtual desktop")


def _validate_action(req: Action) -> dict[str, Any]:
    action = req.model_dump()
    action_type = str(action["type"]).lower().strip()
    if action_type not in VALID_ACTIONS:
        raise HTTPException(status_code=400, detail=f"Unsupported action type: {action_type}")
    action["type"] = action_type
    button = str(action.get("button", "left")).lower().strip()
    if button not in VALID_BUTTONS:
        raise HTTPException(status_code=400, detail="Invalid mouse button")
    action["button"] = button
    if action_type in {"move", "click", "double_click", "right_click", "mouse_down", "mouse_up"}:
        _validate_coordinate(action.get("x"), action.get("y"))
    elif action_type == "scroll" and (action.get("x") is not None or action.get("y") is not None):
        _validate_coordinate(action.get("x"), action.get("y"))
    if action_type == "type" and not str(action.get("text", "")):
        raise HTTPException(status_code=400, detail="Type action requires text")
    if action_type in {"press", "hotkey"}:
        keys = [str(key).lower().strip() for key in action.get("keys", [])]
        if not keys or any(not VALID_KEY.match(key) for key in keys):
            raise HTTPException(status_code=400, detail="Invalid key sequence")
        action["keys"] = keys
    return action


def _worker_entry(kind: str, payload: dict[str, Any], queue: Any) -> None:
    try:
        if kind == "screen":
            from PIL import ImageGrab

            image = ImageGrab.grab(all_screens=True)
            import io

            buf = io.BytesIO()
            image.save(buf, format="PNG")
            data = buf.getvalue()
            queue.put({"ok": True, "png_base64": base64.b64encode(data).decode("ascii"), "sha256": hashlib.sha256(data).hexdigest()})
            return
        if kind == "windows":
            from pywinauto import Desktop

            limit = max(1, min(int(payload.get("limit", 250)), 500))
            items: list[dict[str, Any]] = []
            for window in Desktop(backend="uia").windows()[:30]:
                if len(items) >= limit:
                    break
                try:
                    rect = window.rectangle()
                    items.append({"kind": "window", "name": str(window.window_text())[:512], "control_type": str(getattr(window.element_info, "control_type", "Window"))[:64], "rect": [rect.left, rect.top, rect.right, rect.bottom]})
                    for control in window.descendants()[:40]:
                        if len(items) >= limit:
                            break
                        try:
                            cr = control.rectangle()
                            items.append({"kind": "control", "name": str(control.window_text() or getattr(control.element_info, "name", ""))[:512], "control_type": str(getattr(control.element_info, "control_type", ""))[:64], "automation_id": str(getattr(control.element_info, "automation_id", ""))[:256], "rect": [cr.left, cr.top, cr.right, cr.bottom]})
                        except Exception:
                            continue
                except Exception:
                    continue
            queue.put({"ok": True, "items": items})
            return
        if kind == "action":
            import pyautogui

            pyautogui.FAILSAFE = True
            pyautogui.PAUSE = 0.08
            action_type = str(payload["type"])
            x, y = payload.get("x"), payload.get("y")
            button = str(payload.get("button", "left"))
            if action_type == "move":
                pyautogui.moveTo(x, y, duration=float(payload.get("seconds", 0.2)))
            elif action_type == "click":
                pyautogui.click(x, y, clicks=int(payload.get("clicks", 1)), button=button)
            elif action_type == "double_click":
                pyautogui.doubleClick(x, y, button=button)
            elif action_type == "right_click":
                pyautogui.rightClick(x, y)
            elif action_type == "mouse_down":
                pyautogui.mouseDown(x, y, button=button)
            elif action_type == "mouse_up":
                pyautogui.mouseUp(x, y, button=button)
            elif action_type == "scroll":
                pyautogui.scroll(int(payload.get("amount", 0)), x=x, y=y)
            elif action_type == "type":
                pyautogui.write(str(payload.get("text", "")), interval=0.02)
            elif action_type == "press":
                for key in payload.get("keys", []):
                    pyautogui.press(key)
            elif action_type == "hotkey":
                pyautogui.hotkey(*payload.get("keys", []))
            elif action_type == "wait":
                time.sleep(float(payload.get("seconds", 0.2)))
            elif action_type == "done":
                queue.put({"ok": True, "done": True})
                return
            queue.put({"ok": True, "done": False})
            return
        raise RuntimeError(f"Unknown worker kind: {kind}")
    except Exception as exc:
        queue.put({"ok": False, "error": type(exc).__name__, "message": _redact(str(exc))})


def _run_worker(kind: str, payload: dict[str, Any] | None = None, timeout: float = GUI_TIMEOUT_SECONDS) -> dict[str, Any]:
    if not IS_WINDOWS:
        return _error("unsupported_platform", "Desktop Computer Agent primitives are supported on Windows only", retryable=False)
    context = mp.get_context("spawn")
    queue = context.Queue(maxsize=1)
    process = context.Process(target=_worker_entry, args=(kind, payload or {}, queue), daemon=True)
    process.start()
    process.join(timeout=max(0.1, timeout))
    if process.is_alive():
        process.terminate()
        process.join(1.0)
        if process.is_alive() and hasattr(process, "kill"):
            process.kill()
            process.join(1.0)
        return _error("timeout", f"{kind} operation timed out", retryable=kind in {"screen", "windows"})
    try:
        result = queue.get(timeout=0.5)
    except Exception:
        return _error("malformed_worker_response", f"{kind} worker returned no result", retryable=kind in {"screen", "windows"})
    if not isinstance(result, dict):
        return _error("malformed_worker_response", f"{kind} worker returned invalid data", retryable=False)
    return result


def _cached_action(action_id: str) -> dict[str, Any] | None:
    if not action_id:
        return None
    with _action_cache_lock:
        cached = _action_cache.get(action_id)
        if cached is None:
            return None
        _action_cache.move_to_end(action_id)
        result = dict(cached)
        result["deduplicated"] = True
        return result


def _store_action_result(action_id: str, result: dict[str, Any]) -> None:
    if not action_id:
        return
    with _action_cache_lock:
        _action_cache[action_id] = dict(result)
        _action_cache.move_to_end(action_id)
        while len(_action_cache) > ACTION_CACHE_LIMIT:
            _action_cache.popitem(last=False)


def _claim_action(action_id: str) -> tuple[str, dict[str, Any] | None]:
    if not action_id:
        return "owner", None
    with _action_cache_lock:
        cached = _action_cache.get(action_id)
        if cached is not None:
            _action_cache.move_to_end(action_id)
            result = dict(cached)
            result["deduplicated"] = True
            return "cached", result
        if action_id in _action_inflight:
            return "inflight", None
        _action_inflight.add(action_id)
    return "owner", None


def _release_action_claim(action_id: str) -> None:
    if not action_id:
        return
    with _action_cache_lock:
        _action_inflight.discard(action_id)


def _execute_action(req: Action) -> dict[str, Any]:
    action = _validate_action(req)
    action_id = str(action.get("action_id", "")).strip()
    action_type = str(action["type"])
    retry_safety = "safe" if _retryable(action_type) else "unsafe"
    if retry_safety == "unsafe" and not action_id:
        raise HTTPException(status_code=400, detail="Unsafe Computer actions require action_id for idempotency")

    claim, cached = _claim_action(action_id)
    if claim == "cached" and cached is not None:
        return cached
    if claim == "inflight":
        return _error("action_in_progress", "An action with this action_id is already executing; external state is not yet known", retryable=False, action_id=action_id, retry_safety=retry_safety, uncertain_external_state=True)

    if not _action_execution_lock.acquire(blocking=False):
        _release_action_claim(action_id)
        return _error("computer_busy", "Another Computer action is executing. This action was not started; retry after it finishes.", retryable=False, action_id=action_id, executed=False)

    try:
        before_hash = ""
        if bool(action.get("verify", False)):
            before = _run_worker("screen", {}, GUI_TIMEOUT_SECONDS)
            if before.get("ok"):
                before_hash = str(before.get("sha256", ""))
        result = _run_worker("action", action, ACTION_TIMEOUT_SECONDS)
        result["action_id"] = action_id
        result["retryable"] = _retryable(action_type)
        result["retry_safety"] = retry_safety
        if not result.get("ok") and retry_safety == "unsafe":
            result["uncertain_external_state"] = True
        if result.get("ok") and bool(action.get("verify", False)):
            after = _run_worker("screen", {}, GUI_TIMEOUT_SECONDS)
            if after.get("ok"):
                after_hash = str(after.get("sha256", ""))
                result["verified"] = bool(before_hash and after_hash and before_hash != after_hash)
                result["verification"] = "screen_changed" if result["verified"] else "screen_unchanged"
            else:
                result["verified"] = False
                result["verification"] = "verification_unavailable"
        _store_action_result(action_id, result)
        return result
    finally:
        _action_execution_lock.release()
        _release_action_claim(action_id)


def _container_engine() -> str | None:
    preferred = os.getenv("AURORAFOX_CONTAINER_ENGINE", "").strip()
    if preferred and shutil.which(preferred):
        return preferred
    for name in ("podman", "docker"):
        if shutil.which(name):
            return name
    return None


def _container_profile(command: list[str]) -> tuple[str, list[str]]:
    exe = Path(command[0]).name.lower()
    image_map = {
        "python": os.getenv("AURORAFOX_IMAGE_PYTHON", "python:3-slim"), "python3": os.getenv("AURORAFOX_IMAGE_PYTHON", "python:3-slim"), "pytest": os.getenv("AURORAFOX_IMAGE_PYTHON", "python:3-slim"),
        "node": os.getenv("AURORAFOX_IMAGE_NODE", "node:22-bookworm-slim"), "npm": os.getenv("AURORAFOX_IMAGE_NODE", "node:22-bookworm-slim"), "npx": os.getenv("AURORAFOX_IMAGE_NODE", "node:22-bookworm-slim"),
        "go": os.getenv("AURORAFOX_IMAGE_GO", "golang:1-bookworm"), "cargo": os.getenv("AURORAFOX_IMAGE_RUST", "rust:1-bookworm"), "rustc": os.getenv("AURORAFOX_IMAGE_RUST", "rust:1-bookworm"),
        "java": os.getenv("AURORAFOX_IMAGE_JAVA", "eclipse-temurin:21-jdk"), "javac": os.getenv("AURORAFOX_IMAGE_JAVA", "eclipse-temurin:21-jdk"), "gradle": os.getenv("AURORAFOX_IMAGE_GRADLE", "gradle:8-jdk21"),
        "dotnet": os.getenv("AURORAFOX_IMAGE_DOTNET", "mcr.microsoft.com/dotnet/sdk:9.0"), "gcc": os.getenv("AURORAFOX_IMAGE_CPP", "gcc:latest"), "g++": os.getenv("AURORAFOX_IMAGE_CPP", "gcc:latest"), "cmake": os.getenv("AURORAFOX_IMAGE_CPP", "gcc:latest"),
        "ruby": os.getenv("AURORAFOX_IMAGE_RUBY", "ruby:3-slim"), "php": os.getenv("AURORAFOX_IMAGE_PHP", "php:8-cli"),
    }
    image = image_map.get(exe)
    if not image:
        raise HTTPException(status_code=403, detail=f"No container profile for executable: {exe}")
    return image, command


def _tree(root: Path, max_items: int = 2000) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    if not root.exists():
        return items
    for path in root.rglob("*"):
        if len(items) >= max_items:
            break
        try:
            resolved = path.resolve(strict=False)
            if resolved != SANDBOX_ROOT and SANDBOX_ROOT not in resolved.parents:
                continue
            items.append({"path": path.relative_to(root).as_posix(), "dir": path.is_dir(), "size": path.stat().st_size if path.is_file() else 0})
        except OSError:
            continue
    return items


def _validate_command(command: list[str]) -> list[str]:
    if not command:
        raise HTTPException(status_code=400, detail="Empty command")
    clean = [str(part) for part in command]
    if any("\x00" in part or len(part) > 8192 for part in clean):
        raise HTTPException(status_code=400, detail="Malformed command argument")
    exe = Path(clean[0]).name.lower()
    allowed = {
        "python", "python.exe", "python3", "py", "pytest", "pytest.exe", "git", "git.exe", "godot", "godot.exe", "godot4", "godot4.exe",
        "node", "node.exe", "npm", "npm.cmd", "npx", "npx.cmd", "go", "go.exe", "cargo", "cargo.exe", "rustc", "rustc.exe", "dotnet", "dotnet.exe",
        "java", "java.exe", "javac", "javac.exe", "gradle", "gradle.bat", "gradlew", "gradlew.bat", "gcc", "gcc.exe", "g++", "g++.exe", "clang", "clang.exe",
        "cmake", "cmake.exe", "ninja", "ninja.exe", "ruby", "ruby.exe", "php", "php.exe", "lua", "lua.exe",
    }
    if exe not in allowed:
        raise HTTPException(status_code=403, detail=f"Executable not allowed in local sandbox: {exe}")
    for argument in clean[1:]:
        if argument.startswith("-"):
            continue
        path = Path(argument)
        if path.is_absolute() or ".." in path.parts:
            raise HTTPException(status_code=400, detail="Command path argument may not escape sandbox")
    return clean


def _sanitized_environment(cwd: Path, allow_network: bool) -> dict[str, str]:
    keep = {"PATH", "PATHEXT", "SYSTEMROOT", "WINDIR", "TEMP", "TMP", "LANG", "LC_ALL", "COMSPEC"}
    env = {key: value for key, value in os.environ.items() if key.upper() in keep}
    env["HOME"] = str(cwd)
    env["USERPROFILE"] = str(cwd)
    env["AURORAFOX_SANDBOX_ROOT"] = str(SANDBOX_ROOT)
    env["AURORAFOX_NETWORK_ALLOWED"] = "1" if allow_network else "0"
    return env


def _run_process(command: list[str], cwd: Path, timeout: int, *, allow_network: bool) -> dict[str, Any]:
    startup: dict[str, Any] = {}
    if os.name == "nt": startup["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else: startup["start_new_session"] = True
    try:
        process = subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, shell=False, env=_sanitized_environment(cwd, allow_network), **startup)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=f"Executable not installed: {Path(command[0]).name}") from exc
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        if os.name == "nt": subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True, check=False)
        else:
            try: os.killpg(process.pid, signal.SIGKILL)
            except OSError: process.kill()
        try: process.communicate(timeout=2)
        except Exception: pass
        return _error("timeout", "Sandbox process timed out and was terminated", retryable=True)
    output = _redact((stdout or "") + (stderr or ""))
    return {"ok": process.returncode == 0, "code": process.returncode, "output": output[:MAX_OUTPUT], "mode": "local", "retryable": process.returncode != 0}


def _parent_watchdog() -> None:
    if PARENT_PID <= 0: return
    while True:
        time.sleep(2.0)
        try:
            if os.name == "nt":
                result = subprocess.run(["tasklist", "/FI", f"PID eq {PARENT_PID}", "/NH"], capture_output=True, text=True, timeout=2)
                alive = str(PARENT_PID) in result.stdout
            else:
                os.kill(PARENT_PID, 0); alive = True
        except Exception: alive = False
        if not alive: os._exit(0)


@app.get("/health")
def health() -> dict[str, Any]:
    return {"ok": True, "service": "aurorafox_computer_primitives", "version": "1.1.0", "platform": "windows" if IS_WINDOWS else os.name, "computer_supported": IS_WINDOWS, "planning_owner": "aurorafox_core", "service_side_ai_planning": False, "external_ai_required": False, "network_required": False, "authenticated_channel_configured": bool(SERVICE_TOKEN), "virtual_desktop": _desktop_bounds(), "failsafe": True, "container_engine_available": bool(_container_engine()), "degraded_local_sandbox_enabled": ALLOW_DEGRADED_LOCAL_SANDBOX}


@app.get("/capabilities")
def capabilities(x_aurorafox_computer_token: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, "1", require_autonomy=False)
    return {"ok": True, "computer_supported": IS_WINDOWS, "platform": "windows" if IS_WINDOWS else os.name, "screen": IS_WINDOWS, "windows": IS_WINDOWS, "mouse": IS_WINDOWS, "keyboard": IS_WINDOWS, "clipboard": False, "service_side_planning": False, "local_core_planning_required": True, "sandbox": True, "degraded_local_sandbox_enabled": ALLOW_DEGRADED_LOCAL_SANDBOX, "snapshot_max_entries": MAX_SNAPSHOT_ENTRIES, "snapshot_max_bytes": MAX_SNAPSHOT_BYTES}


@app.get("/screen")
def screen(x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed)
    result = _run_worker("screen", {}, GUI_TIMEOUT_SECONDS)
    if result.get("ok"):
        windows_result = _run_worker("windows", {"limit": 250}, GUI_TIMEOUT_SECONDS)
        result["uia"] = windows_result.get("items", []) if windows_result.get("ok") else []
        result["virtual_desktop"] = _desktop_bounds(); result["retryable"] = True
    return result


@app.get("/windows")
def windows(x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed)
    result = _run_worker("windows", {"limit": 250}, GUI_TIMEOUT_SECONDS); result["retryable"] = True; return result


@app.post("/action")
def action(req: Action, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); return _execute_action(req)


@app.post("/plan")
def plan(req: GoalRequest, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed)
    return _error("local_core_planning_required", "Computer service does not plan goals. AuroraFox Core must plan and call primitive actions explicitly.", retryable=False, goal_received=bool(req.goal))


@app.post("/run")
def run(req: GoalRequest, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed)
    return _error("local_core_planning_required", "Service-side goal execution is disabled. Use AuroraFox Core -> verified Computer primitives.", retryable=False, goal_received=bool(req.goal), auto_execute_ignored=bool(req.auto_execute))


@app.post("/sandbox/workspace/create")
def workspace_create(req: WorkspaceCreateRequest, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed)
    workspace_id = _safe_workspace_id(req.id) if req.id else uuid.uuid4().hex[:16]
    root = _safe_sandbox_path(workspace_id)
    for name in ("input", "work", "output", "logs", "snapshots"): (root / name).mkdir(parents=True, exist_ok=True)
    manifest = {"id": workspace_id, "task": _redact(req.task), "created_at": int(time.time()), "root": workspace_id}
    temp = root / f"manifest.{uuid.uuid4().hex}.tmp"; temp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"); os.replace(temp, root / "manifest.json")
    return {"ok": True, "workspace": manifest}


@app.get("/sandbox/workspace/tree")
def workspace_tree(workspace: str, area: str = "work", x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); wid = _safe_workspace_id(workspace)
    if area not in {"input", "work", "output", "logs", "snapshots"}: raise HTTPException(status_code=400, detail="Invalid workspace area")
    return {"ok": True, "workspace": wid, "area": area, "items": _tree(_safe_sandbox_path(f"{wid}/{area}"))}


@app.post("/sandbox/workspace/snapshot")
def workspace_snapshot(req: WorkspaceSnapshotRequest, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); wid = _safe_workspace_id(req.workspace); work = _safe_sandbox_path(f"{wid}/work"); snapshots = _safe_sandbox_path(f"{wid}/snapshots"); snapshots.mkdir(parents=True, exist_ok=True)
    safe_label = "".join(ch if ch.isalnum() or ch in "_-" else "_" for ch in req.label)[:48] or "checkpoint"; snapshot_id = f"{int(time.time())}_{safe_label}_{uuid.uuid4().hex[:6]}"; target = snapshots / snapshot_id; stats = _copy_snapshot_tree(work, target)
    return {"ok": True, "workspace": wid, "snapshot": snapshot_id, "path": f"{wid}/snapshots/{snapshot_id}", "entries": stats["entries"], "bytes": stats["bytes"]}


@app.post("/sandbox/workspace/rollback")
def workspace_rollback(req: WorkspaceRollbackRequest, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); wid = _safe_workspace_id(req.workspace); sid = _safe_workspace_id(req.snapshot); work = _safe_sandbox_path(f"{wid}/work"); source = _safe_sandbox_path(f"{wid}/snapshots/{sid}", must_exist=True)
    if not source.is_dir(): raise HTTPException(status_code=404, detail="Snapshot not found")
    replacement = _safe_sandbox_path(f"{wid}/work.rollback.{uuid.uuid4().hex}"); stats = _copy_snapshot_tree(source, replacement)
    if work.exists():
        backup = _safe_sandbox_path(f"{wid}/work.pre_rollback.{uuid.uuid4().hex}"); os.replace(work, backup)
        try: os.replace(replacement, work)
        except Exception: os.replace(backup, work); raise
        shutil.rmtree(backup, ignore_errors=True)
    else: os.replace(replacement, work)
    return {"ok": True, "workspace": wid, "snapshot": sid, "entries": stats["entries"], "bytes": stats["bytes"]}


@app.get("/sandbox/list")
def sandbox_list(path: str = ".", x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); p = _safe_sandbox_path(path)
    if not p.exists(): return {"ok": True, "items": []}
    if not p.is_dir(): raise HTTPException(status_code=400, detail="Not a directory")
    items = []
    for child in p.iterdir():
        resolved = child.resolve(strict=False)
        if resolved != SANDBOX_ROOT and SANDBOX_ROOT not in resolved.parents: continue
        items.append({"name": child.name, "dir": child.is_dir(), "size": child.stat().st_size if child.is_file() else 0})
    return {"ok": True, "items": items}


@app.get("/sandbox/read")
def sandbox_read(path: str, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); p = _safe_sandbox_path(path, must_exist=True)
    if not p.is_file(): raise HTTPException(status_code=404, detail="File not found")
    data = p.read_bytes()
    if len(data) > MAX_READ_BYTES: raise HTTPException(status_code=413, detail="File too large")
    try: return {"ok": True, "text": data.decode("utf-8")}
    except UnicodeDecodeError: return {"ok": True, "base64": base64.b64encode(data).decode("ascii")}


@app.post("/sandbox/write")
def sandbox_write(req: SandboxWriteRequest, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); encoded = req.content.encode("utf-8")
    if len(encoded) > MAX_WRITE_BYTES: raise HTTPException(status_code=413, detail="Write payload too large")
    path = _safe_sandbox_path(req.path); path.parent.mkdir(parents=True, exist_ok=True); temp = path.parent / f".{path.name}.{uuid.uuid4().hex}.tmp"; temp.write_bytes(encoded); os.replace(temp, path)
    return {"ok": True, "path": path.relative_to(SANDBOX_ROOT).as_posix()}


@app.post("/sandbox/exec")
def sandbox_exec(req: SandboxExecRequest, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed)
    if not ALLOW_DEGRADED_LOCAL_SANDBOX:
        raise HTTPException(status_code=403, detail="Degraded local process sandbox is disabled by default; use container mode or explicit operator opt-in")
    command = _validate_command(req.command); cwd = _safe_sandbox_path(req.cwd); cwd.mkdir(parents=True, exist_ok=True); result = _run_process(command, cwd, req.timeout, allow_network=req.allow_network); result["network_requested"] = bool(req.allow_network); result["network_isolation_enforced"] = False; return result


@app.post("/sandbox/container_exec")
def sandbox_container_exec(req: SandboxExecRequest, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); command = _validate_command(req.command); engine = _container_engine()
    if not engine: raise HTTPException(status_code=404, detail="Docker/Podman not installed")
    cwd = _safe_sandbox_path(req.cwd); cwd.mkdir(parents=True, exist_ok=True); image, inner_command = _container_profile(command); network_args = [] if req.allow_network else ["--network", "none"]
    run_command = [engine, "run", "--rm", "--pull=never", *network_args, "--read-only", "--memory", os.getenv("AURORAFOX_CONTAINER_MEMORY", "2g"), "--cpus", os.getenv("AURORAFOX_CONTAINER_CPUS", "2"), "--pids-limit", os.getenv("AURORAFOX_CONTAINER_PIDS", "256"), "--security-opt", "no-new-privileges", "--tmpfs", "/tmp:rw,noexec,nosuid,size=256m", "-v", f"{cwd}:/workspace:rw", "-w", "/workspace", image, *inner_command]
    result = _run_process(run_command, cwd, req.timeout, allow_network=req.allow_network); result.update({"mode": "container", "engine": engine, "image": image, "network": "allowed" if req.allow_network else "none", "network_isolation_enforced": not req.allow_network, "image_pull_allowed": False}); return result


if __name__ == "__main__":
    import uvicorn

    if PARENT_PID > 0: threading.Thread(target=_parent_watchdog, name="aurorafox-parent-watchdog", daemon=True).start()
    uvicorn.run(app, host=HOST, port=PORT, access_log=False, log_level="warning")
