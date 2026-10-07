from __future__ import annotations

import base64
from contextlib import asynccontextmanager, contextmanager
import hashlib
import hmac
import json
import multiprocessing as mp
import math
import os
import re
import shutil
import signal
import stat
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
MAX_CAPTURE_BYTES = 8 * 1024 * 1024
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

@asynccontextmanager
async def _lifespan(_app):
    try:
        yield
    finally:
        _cancel_all_processes()


app = FastAPI(title="AuroraFox Computer Primitive Service", version="1.1.0", lifespan=_lifespan)
_action_cache: OrderedDict[str, dict[str, Any]] = OrderedDict()
_action_inflight: set[str] = set()
_action_consumed: set[str] = set()
_action_cache_lock = threading.Lock()
_action_execution_lock = threading.Lock()
_execution_lock = threading.Lock()
_execution_records: dict[str, dict[str, Any]] = {}
_execution_stopping = False
_gui_workers: set[Any] = set()
_gui_worker_lifecycle_lock = threading.RLock()


class GuiResourceLimits(BaseModel):
    action_results: int = Field(default=ACTION_CACHE_LIMIT, ge=0)
    action_identities: int = Field(default=0, ge=0)
    action_text_chars: int = Field(default=MAX_TEXT_CHARS, ge=0)
    action_keys: int = Field(default=MAX_KEYS, ge=0)
    action_clicks: int = Field(default=3, ge=0)
    action_scroll: int = Field(default=100, ge=0)
    action_seconds: int = Field(default=5, ge=0)
    action_worker_seconds: int = Field(default=10, ge=0, le=9223372036854775807)
    uia_items: int = Field(default=250, ge=0)
    uia_windows: int = Field(default=30, ge=0)
    uia_controls: int = Field(default=40, ge=0)
    uia_name_chars: int = Field(default=512, ge=0)
    uia_type_chars: int = Field(default=64, ge=0)
    uia_id_chars: int = Field(default=256, ge=0)
    worker_seconds: int = Field(default=8, ge=0, le=9223372036854775807)


def _gui_limits(header):
    if not header: return GuiResourceLimits().model_dump()
    try:
        data = json.loads(header)
        if not isinstance(data, dict): raise ValueError("object required")
        return GuiResourceLimits.model_validate(data).model_dump()
    except (ValueError, TypeError):
        raise HTTPException(422, "Invalid GUI resource policy")


class Action(BaseModel):
    type: str = Field(min_length=1, max_length=32)
    action_id: str = Field(default="", max_length=160)
    x: int | None = None
    y: int | None = None
    button: str = "left"
    clicks: int = Field(default=1, ge=1)
    text: str = ""
    keys: list[str] = Field(default_factory=list)
    amount: int = 0
    seconds: float = Field(default=0.2, ge=0.0, allow_inf_nan=False)
    verify: bool = False


class GoalRequest(BaseModel):
    goal: str = Field(min_length=1, max_length=8000)
    max_steps: int = Field(default=20, ge=1, le=100)
    auto_execute: bool = False


class SandboxExecRequest(BaseModel):
    execution_id: str = Field(default="", max_length=160, pattern=r"^[A-Za-z0-9_:.-]*$")
    command: list[str] = Field(min_length=1, max_length=64)
    cwd: str = Field(default=".", max_length=1024)
    timeout: int = Field(default=60, ge=0, le=9223372036854775807)
    allow_network: bool = False
    output_chars: int = Field(default=MAX_OUTPUT, ge=0)
    capture_bytes: int = Field(default=MAX_CAPTURE_BYTES, ge=0)


class SandboxCancelRequest(BaseModel):
    execution_id: str = Field(min_length=1, max_length=160, pattern=r"^[A-Za-z0-9_:.-]+$")


class SandboxWriteRequest(BaseModel):
    max_bytes: int = Field(default=MAX_WRITE_BYTES, ge=0)
    path: str = Field(min_length=1, max_length=1024)
    content: str


class WorkspaceCreateRequest(BaseModel):
    id: str = Field(default="", max_length=96)
    task: str = Field(default="", max_length=4000)


class WorkspaceSnapshotRequest(BaseModel):
    max_entries: int = Field(default_factory=lambda: MAX_SNAPSHOT_ENTRIES, ge=0)
    max_bytes: int = Field(default_factory=lambda: MAX_SNAPSHOT_BYTES, ge=0)
    workspace: str = Field(min_length=1, max_length=96)
    label: str = Field(default="checkpoint", max_length=64)


class WorkspaceRollbackRequest(BaseModel):
    max_entries: int = Field(default_factory=lambda: MAX_SNAPSHOT_ENTRIES, ge=0)
    max_bytes: int = Field(default_factory=lambda: MAX_SNAPSHOT_BYTES, ge=0)
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
        if _execution_stopping:
            raise HTTPException(status_code=503, detail="Computer sidecar is stopping")


def _retryable(action_type: str) -> bool:
    return action_type in SAFE_RETRY_ACTIONS


def _error(kind: str, message: str, *, retryable: bool = False, **extra: Any) -> dict[str, Any]:
    result: dict[str, Any] = {"ok": False, "error": kind, "message": _redact(message), "retryable": retryable}
    result.update(extra)
    return result


def _redact(value: str, max_chars: int = MAX_OUTPUT) -> str:
    text = str(value)
    text = re.sub(
        '(?i)\\b(password|passwd|secret|token|api[_ -]?key|authorization|cookie|private[_ -]?key)["\']?\\s*(?:[:=]\\s*|\\s+)(?:Bearer\\s+)?(?:"[^"\\r\\n]*"|\'[^\'\\r\\n]*\'|[^\\s,;"\']+)',
        r"\1=[REDACTED]",
        text,
    )
    text = re.sub(r"(?i)\bbearer\s+[^\s,;]+", "Bearer [REDACTED]", text)
    if SERVICE_TOKEN:
        text = text.replace(SERVICE_TOKEN, "[REDACTED]")
    return text if max_chars == 0 else text[:max_chars]


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


def _walk_directory_entries(root: Path, failed):
    """Depth-first streaming enumeration; at most one open iterator per depth."""
    frames = []
    try:
        try: frames.append(os.scandir(root))
        except OSError as exc:
            failed(exc)
            return
        while frames:
            try:
                entry = next(frames[-1])
            except StopIteration:
                frames.pop().close()
                continue
            except OSError as exc:
                frames.pop().close()
                failed(exc)
                continue
            yield entry
            try:
                if entry.is_dir(follow_symlinks=False) and not entry.is_symlink():
                    attrs = getattr(entry.stat(follow_symlinks=False), "st_file_attributes", 0)
                    if not attrs & stat.FILE_ATTRIBUTE_REPARSE_POINT:
                        frames.append(os.scandir(entry.path))
            except OSError as exc:
                failed(exc)
    finally:
        for iterator in reversed(frames): iterator.close()


def _snapshot_tree_stats(root: Path, max_entries: int = MAX_SNAPSHOT_ENTRIES, max_bytes: int = MAX_SNAPSHOT_BYTES) -> dict[str, int]:
    if not root.exists() or not root.is_dir():
        raise HTTPException(status_code=404, detail="Snapshot source directory not found")
    entries = 0
    total_bytes = 0
    def failed(exc):
        raise HTTPException(status_code=500, detail=f"Cannot inspect snapshot tree: {type(exc).__name__}") from exc
    iterator = _walk_directory_entries(root, failed)
    try:
        for entry in iterator:
            entries += 1
            if max_entries > 0 and entries > max_entries:
                raise HTTPException(status_code=413, detail="Snapshot contains too many filesystem entries")
            try:
                info = entry.stat(follow_symlinks=False)
                if entry.is_symlink() or bool(getattr(info, "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT):
                    raise HTTPException(status_code=400, detail="Symlinks and reparse entries are not allowed in workspace snapshots")
                if entry.is_file(follow_symlinks=False):
                    total_bytes += int(info.st_size)
                    if max_bytes > 0 and total_bytes > max_bytes:
                        raise HTTPException(status_code=413, detail="Snapshot exceeds the configured byte limit")
                elif not entry.is_dir(follow_symlinks=False):
                    raise HTTPException(status_code=400, detail="Special filesystem entries are not allowed in workspace snapshots")
            except OSError as exc: failed(exc)
    finally: iterator.close()
    return {"entries": entries, "bytes": total_bytes}


def _copy_snapshot_tree(source: Path, target: Path, max_entries: int = MAX_SNAPSHOT_ENTRIES, max_bytes: int = MAX_SNAPSHOT_BYTES) -> dict[str, int]:
    _snapshot_tree_stats(source, max_entries, max_bytes)
    source_root = source.resolve(strict=True)
    created = False
    iterator = None
    directory_metadata = []
    entries = 0
    total_bytes = 0

    def failed(exc):
        raise HTTPException(status_code=500, detail=f"Cannot copy snapshot tree: {type(exc).__name__}") from exc

    try:
        try:
            target.mkdir(mode=0o700, parents=False, exist_ok=False)
        except FileExistsError as exc:
            raise HTTPException(status_code=409, detail="Snapshot destination already exists") from exc
        created = True
        directory_metadata.append((target, source_root.stat()))
        iterator = _walk_directory_entries(source_root, failed)
        for entry in iterator:
            entries += 1
            if max_entries > 0 and entries > max_entries:
                raise HTTPException(status_code=413, detail="Snapshot contains too many filesystem entries during copy")
            path = Path(entry.path)
            info = path.stat(follow_symlinks=False)
            if stat.S_ISLNK(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT):
                raise HTTPException(status_code=400, detail="Symlinks and reparse entries are not allowed in workspace snapshots")
            try:
                path.resolve(strict=True).relative_to(source_root)
            except ValueError as exc:
                raise HTTPException(status_code=400, detail="Snapshot source escapes its original root") from exc
            destination = target / path.relative_to(source_root)
            if stat.S_ISDIR(info.st_mode):
                destination.mkdir(mode=0o700, exist_ok=False)
                directory_metadata.append((destination, info))
                continue
            if not stat.S_ISREG(info.st_mode):
                raise HTTPException(status_code=400, detail="Special filesystem entries are not allowed in workspace snapshots")
            flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_BINARY", 0) | getattr(os, "O_NONBLOCK", 0)
            with os.fdopen(os.open(path, flags), "rb") as reader:
                opened = os.fstat(reader.fileno())
                if not stat.S_ISREG(opened.st_mode) or not os.path.samestat(info, opened):
                    raise HTTPException(status_code=400, detail="Snapshot source identity changed before copy")
                if max_bytes > 0 and total_bytes + opened.st_size > max_bytes:
                    raise HTTPException(status_code=413, detail="Snapshot exceeds the configured byte limit during copy")
                with destination.open("xb") as writer:
                    while True:
                        read_bytes = 65536 if max_bytes == 0 else min(65536, max_bytes - total_bytes + 1)
                        chunk = reader.read(read_bytes)
                        if not chunk:
                            break
                        if max_bytes > 0 and total_bytes + len(chunk) > max_bytes:
                            raise HTTPException(status_code=413, detail="Snapshot exceeds the configured byte limit during copy")
                        writer.write(chunk)
                        total_bytes += len(chunk)
            os.chmod(destination, stat.S_IMODE(opened.st_mode))
            os.utime(destination, ns=(opened.st_atime_ns, opened.st_mtime_ns), follow_symlinks=False)
        stats = _snapshot_tree_stats(target, max_entries, max_bytes)
        for directory, info in reversed(directory_metadata):
            os.chmod(directory, stat.S_IMODE(info.st_mode))
            os.utime(directory, ns=(info.st_atime_ns, info.st_mtime_ns), follow_symlinks=False)
        return stats
    except Exception:
        if created and target.exists():
            try:
                # Restored read-only metadata must not strand an owned partial
                # snapshot. Never repair a link/reparse target during cleanup.
                for directory, _ in directory_metadata:
                    info = directory.stat(follow_symlinks=False)
                    if stat.S_ISLNK(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT):
                        raise OSError("Snapshot cleanup directory identity is unsafe")
                    os.chmod(directory, 0o700)

                def remove_readonly(function, path, exc_info):
                    info = os.stat(path, follow_symlinks=False)
                    if stat.S_ISLNK(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT):
                        raise exc_info[1]
                    os.chmod(path, 0o700)
                    function(path)

                shutil.rmtree(target, onerror=remove_readonly)
            except OSError as cleanup_error:
                raise HTTPException(status_code=500, detail="Snapshot copy failed and partial destination cleanup failed") from cleanup_error
        raise
    finally:
        if iterator is not None:
            iterator.close()


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


def _validate_action(req: Action, limits=None) -> dict[str, Any]:
    limits = limits if limits is not None else GuiResourceLimits().model_dump()
    action = req.model_dump()
    measurements = {"action_text_chars": len(action["text"]), "action_keys": len(action["keys"]),
                    "action_clicks": action["clicks"], "action_scroll": abs(action["amount"]), "action_seconds": action["seconds"]}
    for key, size in measurements.items():
        if limits[key] and size > limits[key]:
            raise HTTPException(413, detail={"error": "action_resource_budget", "budget": key, "limit": limits[key], "requested": size, "executed": False})
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


def _collect_uia(desktop, limits):
    items = []
    reasons = set()
    failed = 0

    def bounded(values, key):
        cap = limits[key]
        for index, value in enumerate(values):
            if cap and index >= cap:
                reasons.add(key)
                break
            yield value

    def append(element, kind):
        if limits["uia_items"] and len(items) >= limits["uia_items"]:
            reasons.add("uia_items")
            return False
        rect = element.rectangle()
        info = element.element_info
        record = {"kind": kind, "rect": [rect.left, rect.top, rect.right, rect.bottom]}
        fields = [("name", element.window_text() or getattr(info, "name", ""), "uia_name_chars"),
                  ("control_type", getattr(info, "control_type", "Window" if kind == "window" else ""), "uia_type_chars")]
        if kind == "control": fields.append(("automation_id", getattr(info, "automation_id", ""), "uia_id_chars"))
        for key, value, budget in fields:
            text = _redact(str(value), 0)
            cap = limits[budget]
            if cap and len(text) > cap:
                reasons.add(budget)
                record.setdefault("truncated_fields", []).append(key)
                text = text[:cap]
            record[key] = text
        items.append(record)
        return True

    for window in bounded(desktop.windows(), "uia_windows"):
        try:
            if not append(window, "window"): break
            for control in bounded(window.descendants(), "uia_controls"):
                try:
                    if not append(control, "control"): break
                except Exception: failed += 1
        except Exception: failed += 1
        if "uia_items" in reasons: break
    return {"ok": True, "items": items, "partial": bool(reasons or failed),
            "limit_reached": bool(reasons), "limit_reasons": sorted(reasons), "failed_elements": failed}


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

            queue.put(_collect_uia(Desktop(backend="uia"), payload.get("__gui_limits", GuiResourceLimits().model_dump())))
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


@contextmanager
def _gui_execution_scope(execution_id="", unsafe_gui=False):
    execution_id = execution_id or uuid.uuid4().hex
    record = None
    error = None
    with _execution_lock:
        previous = _execution_records.get(execution_id)
        if _execution_stopping:
            error = _error("service_stopping", "Computer service is stopping; GUI execution was not started", execution_id=execution_id)
        elif previous is not None:
            error = _error("cancelled" if previous["cancelled"] else "execution_id_reused", "GUI execution identity is terminal or in use", execution_id=execution_id, retryable=False)
        else:
            record = {"process": None, "worker": None, "finished": False, "cancelled": False,
                      "termination_confirmed": False, "unsafe_gui": unsafe_gui}
            _execution_records[execution_id] = record
    try:
        yield execution_id, error
    finally:
        if record is not None:
            with _execution_lock:
                record["finished"] = record.get("worker") is None and record.get("job") is None and (not record["cancelled"] or record["termination_confirmed"])


def _stop_gui_worker(worker, seconds=2.0):
    with _gui_worker_lifecycle_lock:
        try:
            if worker.is_alive(): worker.terminate()
            worker.join(timeout=seconds)
            if worker.is_alive():
                worker.kill()
                worker.join(timeout=seconds)
            return not worker.is_alive()
        except Exception:
            return False


def _worker_alive(process: Any) -> bool:
    # multiprocessing.Process wait/status methods share internal state and must
    # not race the request thread against shutdown's join/terminate thread.
    with _gui_worker_lifecycle_lock:
        return process.is_alive()


def _run_worker(kind: str, payload: dict[str, Any] | None = None, timeout: float = GUI_TIMEOUT_SECONDS) -> dict[str, Any]:
    if not IS_WINDOWS:
        return _error("unsupported_platform", "Desktop Computer Agent primitives are supported on Windows only", retryable=False)
    if not math.isfinite(timeout) or timeout < 0:
        return _error("invalid_worker_timeout", "Worker deadline must be finite and nonnegative", retryable=False)
    payload = dict(payload or {})
    execution_id = str(payload.get("__execution_id", ""))
    if not execution_id:
        with _gui_execution_scope() as (owned_id, error):
            if error is not None: return error
            return _run_worker(kind, {**payload, "__execution_id": owned_id}, timeout)
    context = mp.get_context("spawn")
    queue = context.Queue(maxsize=1)
    launch_gate = context.Event()
    try:
        from owned_gui_worker import run_owned_worker
    except ModuleNotFoundError as exc:
        if exc.name != "owned_gui_worker": raise
        from computer.owned_gui_worker import run_owned_worker
    process = context.Process(target=run_owned_worker, args=(_worker_entry, kind, payload, queue, launch_gate), daemon=True)
    with _execution_lock:
        if _execution_stopping:
            return _error("service_stopping", "Computer worker was not started")
        record = _execution_records.get(execution_id)
        if record is None or record["cancelled"] or record["finished"]:
            return _error("cancelled", "GUI execution was cancelled before worker launch", execution_id=execution_id, retryable=False)
        if record.get("job") is not None:
            return _error("ownership_uncertain", "Previous GUI phase still has unconfirmed ownership", retryable=False, uncertain_external_state=True)
        if os.name == "nt": record["job"] = _new_windows_job()
        try:
            process.start()
        except Exception:
            _close_record_job(record)
            raise
        record["worker"] = process
        record["worker_queue"] = queue
        _gui_workers.add(process)
        try:
            if record.get("job") is not None: record["job"].assign(process.pid)
            launch_gate.set()
        except Exception:
            confirmed = _stop_gui_worker(process)
            if record.get("job") is not None:
                try: confirmed = record["job"].terminate() and confirmed
                except OSError: confirmed = False
            record["cancelled"] = True
            record["termination_confirmed"] = confirmed
            if confirmed:
                record["worker"] = None
                record["worker_queue"] = None
                _gui_workers.discard(process)
                _close_record_job(record)
                if callable(getattr(queue, "close", None)): queue.close()
            return _error("process_ownership_failed", "GUI worker ownership could not be installed; launch gate remained closed",
                          execution_id=execution_id, termination_confirmed=confirmed, uncertain_external_state=not confirmed, retryable=False)
    try:
        deadline = None if timeout == 0 else time.monotonic() + timeout
        result = None
        # Drain before join: the child's Queue feeder cannot flush a large
        # screenshot/UIA payload while the parent waits for child exit.
        while True:
            if record["cancelled"]:
                confirmed = _stop_gui_worker(process)
                return _error("cancelled", "GUI execution was cancelled", retryable=False,
                              execution_id=execution_id, termination_confirmed=confirmed,
                              uncertain_external_state=not confirmed or bool(record.get("unsafe_gui")))
            remaining = 0.1 if deadline is None else deadline - time.monotonic()
            try:
                result = queue.get(timeout=max(0.0, min(0.1, remaining)))
                break
            except Exception:
                if record["cancelled"]: continue
                if not _worker_alive(process):
                    try:
                        result = queue.get(timeout=0.5)
                        break
                    except Exception:
                        return _error("malformed_worker_response", f"{kind} worker returned no result", retryable=kind in {"screen", "windows"})
                if deadline is not None and remaining <= 0:
                    break
        # Never hold lifecycle ownership while waiting indefinitely: cancellation
        # must be able to terminate/join the same worker between bounded polls.
        while True:
            with _gui_worker_lifecycle_lock:
                process.join(timeout=0.1 if deadline is None else max(0.0, min(0.1, deadline - time.monotonic())))
                alive = _worker_alive(process)
            if not alive or record["cancelled"] or (deadline is not None and time.monotonic() >= deadline): break
        with _gui_worker_lifecycle_lock:
            if _worker_alive(process):
                process.terminate()
                process.join(1.0)
                if _worker_alive(process) and hasattr(process, "kill"):
                    process.kill()
                    process.join(1.0)
                confirmed = not _worker_alive(process)
                if record["cancelled"]:
                    return _error("cancelled", "GUI execution was cancelled while waiting for worker completion", retryable=False,
                                  execution_id=execution_id, termination_confirmed=bool(record["termination_confirmed"]),
                                  uncertain_external_state=not bool(record["termination_confirmed"]) or bool(record.get("unsafe_gui")))
                return _error("timeout", f"{kind} operation timed out", retryable=confirmed and kind in {"screen", "windows"},
                              termination_confirmed=confirmed, uncertain_external_state=not confirmed)
        if record["cancelled"]:
            return _error("cancelled", "GUI execution was cancelled", execution_id=execution_id, retryable=False,
                          termination_confirmed=True, uncertain_external_state=bool(record.get("unsafe_gui")))
        if record.get("job") is not None:
            try: ownership_empty = record["job"].active_count() == 0
            except OSError: ownership_empty = False
            if not ownership_empty:
                terminated = bool(_cancel_execution(execution_id)["termination_confirmed"])
                return _error("background_descendants", "GUI worker left unconfirmed descendants", retryable=False,
                              execution_id=execution_id, termination_confirmed=terminated, uncertain_external_state=not terminated or bool(record.get("unsafe_gui")))
        if not isinstance(result, dict):
            return _error("malformed_worker_response", f"{kind} worker returned invalid data", retryable=False)
        return result
    finally:
        stopped = not _worker_alive(process)
        with _execution_lock:
            if stopped:
                _gui_workers.discard(process)
                if record.get("worker") is process:
                    record["worker"] = None
                    record["worker_queue"] = None
                try:
                    if record.get("job") is not None and record["job"].active_count() == 0:
                        _close_record_job(record)
                except OSError:
                    pass # Preserve the Job handle for confirmed cleanup/retry.
                if record["cancelled"] and record.get("job") is None: record["termination_confirmed"] = True
        if stopped and callable(getattr(queue, "close", None)):
            queue.close()


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


def _store_action_result(action_id: str, result: dict[str, Any], max_results: int = ACTION_CACHE_LIMIT) -> None:
    if not action_id:
        return
    with _action_cache_lock:
        _action_consumed.add(action_id)
        _action_cache[action_id] = dict(result)
        _action_cache.move_to_end(action_id)
        while max_results > 0 and len(_action_cache) > max_results:
            _action_cache.popitem(last=False)


def _claim_action(action_id: str, max_identities: int = 0) -> tuple[str, dict[str, Any] | None]:
    if not action_id:
        return "owner", None
    with _action_cache_lock:
        cached = _action_cache.get(action_id)
        if cached is not None:
            _action_cache.move_to_end(action_id)
            result = dict(cached)
            result["deduplicated"] = True
            return "cached", result
        if action_id in _action_consumed:
            return "terminal", _error("action_result_evicted", "This action identity was consumed; its detailed result is unavailable", retryable=False,
                                     action_id=action_id, executed=False, deduplicated=True, uncertain_external_state=True)
        if action_id in _action_inflight:
            return "inflight", None
        if max_identities > 0 and len(_action_consumed | _action_inflight) >= max_identities:
            return "terminal", _error("action_identity_capacity", "Action identity storage reached the owner's capacity; no action was started", retryable=False,
                                     action_id=action_id, executed=False, uncertain_external_state=False, limit_reached=True)
        _action_inflight.add(action_id)
    return "owner", None


def _release_action_claim(action_id: str) -> None:
    if not action_id:
        return
    with _action_cache_lock:
        _action_inflight.discard(action_id)


def _execute_action(req: Action, execution_id: str = "", limits=None) -> dict[str, Any]:
    with _gui_execution_scope(execution_id, unsafe_gui=not _retryable(req.type.strip().lower())) as (owned_id, error):
        if error is not None: return error
        return _execute_action_owned(req, owned_id, limits)


def _execute_action_owned(req: Action, execution_id: str, limits=None) -> dict[str, Any]:
    limits = limits if limits is not None else GuiResourceLimits().model_dump()
    action = _validate_action(req, limits)
    action["__gui_limits"] = limits
    action["__execution_id"] = execution_id
    action_id = str(action.get("action_id", "")).strip()
    action_type = str(action["type"])
    retry_safety = "safe" if _retryable(action_type) else "unsafe"
    if retry_safety == "unsafe" and not action_id:
        raise HTTPException(status_code=400, detail="Unsafe Computer actions require action_id for idempotency")

    claim, cached = _claim_action(action_id, limits["action_identities"])
    if claim in {"cached", "terminal"} and cached is not None:
        return cached
    if claim == "inflight":
        return _error("action_in_progress", "An action with this action_id is already executing; external state is not yet known", retryable=False, action_id=action_id, retry_safety=retry_safety, uncertain_external_state=True)

    if not _action_execution_lock.acquire(blocking=False):
        _release_action_claim(action_id)
        return _error("computer_busy", "Another Computer action is executing. This action was not started; retry after it finishes.", retryable=False, action_id=action_id, executed=False)

    try:
        before_hash = ""
        if bool(action.get("verify", False)):
            before = _run_worker("screen", {"__execution_id": execution_id, "__gui_limits": limits}, limits["worker_seconds"])
            if before.get("ok"):
                before_hash = str(before.get("sha256", ""))
        result = _run_worker("action", action, limits["action_worker_seconds"])
        result["action_id"] = action_id
        result["retryable"] = _retryable(action_type) and result.get("error") not in {"cancelled", "execution_id_reused", "service_stopping"} and not result.get("uncertain_external_state", False)
        result["retry_safety"] = retry_safety
        if not result.get("ok") and retry_safety == "unsafe":
            result["uncertain_external_state"] = True
        if result.get("ok") and bool(action.get("verify", False)):
            after = _run_worker("screen", {"__execution_id": execution_id, "__gui_limits": limits}, limits["worker_seconds"])
            if after.get("ok"):
                after_hash = str(after.get("sha256", ""))
                result["verified"] = bool(before_hash and after_hash and before_hash != after_hash)
                result["verification"] = "screen_changed" if result["verified"] else "screen_unchanged"
            else:
                result["verified"] = False
                result["verification"] = "verification_unavailable"
        record = _execution_records[execution_id]
        if record["cancelled"]:
            result = _error("cancelled", "GUI request was cancelled; prior effects are not reversed", retryable=False,
                            action_id=action_id, retry_safety=retry_safety, execution_id=execution_id,
                            termination_confirmed=bool(record["termination_confirmed"]),
                            uncertain_external_state=retry_safety == "unsafe" or not bool(record["termination_confirmed"]))
        _store_action_result(action_id, result, limits["action_results"])
        return result
    finally:
        if action_id:
            # Unexpected exceptions cannot authorize replay of attempted input.
            with _action_cache_lock: _action_consumed.add(action_id)
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


def _tree(root: Path, max_items: int = 2000, coverage: dict | None = None) -> list[dict[str, Any]]:
    if max_items < 0:
        raise HTTPException(400, "Tree budget must be nonnegative")
    items: list[dict[str, Any]] = []
    coverage = coverage if coverage is not None else {}
    coverage.update(truncated=False, failed_paths=0, unsafe_paths_skipped=0)
    if not root.exists(): return items
    def failed(_error): coverage["failed_paths"] += 1
    iterator = _walk_directory_entries(root, failed)
    try:
        for entry in iterator:
            path = Path(entry.path)
            try:
                info = entry.stat(follow_symlinks=False)
                if entry.is_symlink() or bool(getattr(info, "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT) or not path.resolve(strict=True).is_relative_to(root):
                    coverage["unsafe_paths_skipped"] += 1
                    continue
                if max_items > 0 and len(items) >= max_items:
                    coverage["truncated"] = True
                    break
                items.append({"path": path.relative_to(root).as_posix(), "dir": entry.is_dir(follow_symlinks=False), "size": info.st_size if entry.is_file(follow_symlinks=False) else 0})
            except OSError: coverage["failed_paths"] += 1
    finally: iterator.close()
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


def _terminate_process_tree(process: subprocess.Popen) -> bool:
    if os.name == "nt" and process.poll() is not None:
        return True
    if os.name == "nt":
        try:
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True, check=False, timeout=3)
        except (OSError, subprocess.TimeoutExpired):
            return False # Never report confirmed tree termination after taskkill failure.
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        except OSError:
            return False
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        return False
    return process.poll() is not None


def _cancel_execution(execution_id: str) -> dict[str, Any]:
    with _execution_lock:
        # A cancellation can arrive before the execution HTTP handler. Keep the
        # terminal identity for this service session so a late request cannot run.
        record = _execution_records.setdefault(execution_id, {"process": None, "cancelled": False, "finished": False})
        record["cancelled"] = True
        process = record["process"]
        finished = record["finished"]
    worker = record.get("worker")
    worker_stopped = True if worker is None else _stop_gui_worker(worker)
    job = record.get("job")
    if job is not None:
        try:
            terminated = job.terminate()
            if process is not None: process.wait(timeout=2)
        except (OSError, subprocess.TimeoutExpired):
            terminated = False
    else:
        terminated = True if process is None else _terminate_process_tree(process)
    terminated = terminated and worker_stopped
    for reader in record.get("capture_threads", []): reader.join(timeout=0.2)
    if any(reader.is_alive() for reader in record.get("capture_threads", [])): terminated = False
    container = record.get("container")
    if container and not finished:
        try:
            removed = subprocess.run([container[0], "rm", "--force", container[1]], capture_output=True, check=False, timeout=3)
            terminated = terminated and removed.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            terminated = False
    with _execution_lock:
        record["termination_confirmed"] = terminated
        if terminated and (process is None or process.poll() is not None):
            record["finished"] = True
            record["process"] = None
            record["worker"] = None
            if worker is not None: _gui_workers.discard(worker)
            owned_queue = record.get("worker_queue")
            record["worker_queue"] = None
            if owned_queue is not None and callable(getattr(owned_queue, "close", None)): owned_queue.close()
            if record.get("job"):
                _close_record_job(record)
    return {"ok": terminated, "cancelled": True, "execution_id": execution_id,
            "termination_confirmed": terminated, "already_finished": finished,
            "uncertain_external_state": not terminated or bool(record.get("unsafe_gui")), "retryable": False}


def _cancel_all_processes() -> dict[str, Any]:
    global _execution_stopping
    with _execution_lock:
        _execution_stopping = True
        execution_ids = [key for key, record in _execution_records.items()
                         if not record["finished"] and (record["process"] is not None or record.get("container") or record.get("job") or record.get("worker"))]
        workers = list(_gui_workers)
    workers_stopped = all([_stop_gui_worker(worker) for worker in workers])
    stopped_workers = [worker for worker in workers if not _worker_alive(worker)]
    with _execution_lock:
        for worker in stopped_workers: _gui_workers.discard(worker)
    results = [_cancel_execution(execution_id) for execution_id in execution_ids]
    confirmed = workers_stopped and all(result["termination_confirmed"] for result in results)
    return {"ok": confirmed, "termination_confirmed": confirmed,
            "uncertain_external_state": not confirmed, "executions_stopped": len(results)}


def _new_windows_job():
    try:
        from windows_job import WindowsJob
    except ModuleNotFoundError as exc:
        if exc.name != "windows_job": raise
        from computer.windows_job import WindowsJob
    return WindowsJob()


def _close_record_job(record):
    job = record.get("job")
    if job is not None:
        job.close()
        record["job"] = None  # Keep ownership if CloseHandle raises.


def _read_capture_chunk(stream) -> bytes:
    return os.read(stream.fileno(), 65536)


def _run_process(command: list[str], cwd: Path, timeout: int, *, allow_network: bool, execution_id: str = "", container: tuple[str, str] | None = None, output_chars: int = MAX_OUTPUT, capture_bytes: int = MAX_CAPTURE_BYTES) -> dict[str, Any]:
    execution_id = execution_id or uuid.uuid4().hex
    startup: dict[str, Any] = {}
    if os.name == "nt": startup["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP | 0x4 # CREATE_SUSPENDED
    else: startup["start_new_session"] = True
    # Serialize registration and launch against cancellation. A pre-cancelled or
    # previously used identity is never allowed to launch an action again.
    with _execution_lock:
        if _execution_stopping:
            return _error("service_stopping", "Computer sidecar is stopping; execution was not started", execution_id=execution_id)
        previous = _execution_records.get(execution_id)
        if previous is not None:
            kind = "cancelled" if previous["cancelled"] else "execution_id_reused"
            return _error(kind, "Execution identity is already terminal or in use", execution_id=execution_id)
        record: dict[str, Any] = {"process": None, "cancelled": False, "finished": False, "container": container, "termination_confirmed": False}
        _execution_records[execution_id] = record
        try:
            if os.name == "nt": record["job"] = _new_windows_job()
            process = subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=False, env=_sanitized_environment(cwd, allow_network), **startup)
        except FileNotFoundError as exc:
            record["finished"] = True
            if record.get("job"): _close_record_job(record)
            raise HTTPException(status_code=404, detail=f"Executable not installed: {Path(command[0]).name}") from exc
        except Exception:
            record["finished"] = True
            if record.get("job"): _close_record_job(record)
            raise
        record["process"] = process
        if record.get("job"):
            try:
                record["job"].assign_and_resume(process.pid)
            except Exception:
                # Never resume an unowned process. Cleanup is performed directly
                # here because registration still holds the execution lock.
                confirmed = False
                try:
                    record["job"].terminate()
                    if process.poll() is None: process.terminate()
                    process.wait(timeout=2)
                    confirmed = process.poll() is not None and record["job"].active_count() == 0
                except Exception:
                    pass
                record["cancelled"] = True
                record["termination_confirmed"] = confirmed
                record["finished"] = confirmed
                if confirmed:
                    _close_record_job(record)
                    record["process"] = None
                    process.stdout.close()
                    process.stderr.close()
                return _error("process_ownership_failed", "Windows process ownership could not be installed; command was not authorized to start",
                              execution_id=execution_id, termination_confirmed=confirmed,
                              uncertain_external_state=not confirmed, retryable=False)
    buffers = [bytearray(), bytearray()]
    capture_lock = threading.Lock()
    captured_bytes = 0
    overflow = threading.Event()
    capture_failed = threading.Event()

    def drain(stream, index):
        nonlocal captured_bytes
        try:
            while True:
                chunk = _read_capture_chunk(stream)
                if not chunk: break
                with capture_lock:
                    room = len(chunk) if capture_bytes == 0 else max(0, capture_bytes - captured_bytes)
                    retained = chunk[:room]
                    buffers[index].extend(retained)
                    captured_bytes += len(retained)
                    if len(retained) < len(chunk): overflow.set()
        except (OSError, ValueError):
            capture_failed.set()

    readers = [threading.Thread(target=drain, args=(stream, index), daemon=True)
               for index, stream in enumerate((process.stdout, process.stderr))]
    with _execution_lock:
        record["capture_threads"] = readers
        for reader in readers: reader.start()
    try:
        deadline = None if timeout == 0 else time.monotonic() + float(timeout)
        while True:
            if capture_failed.is_set():
                terminated = bool(_cancel_execution(execution_id)["termination_confirmed"])
                return _error("output_capture_failed", "Owned output capture failed", retryable=False,
                              execution_id=execution_id, termination_confirmed=terminated,
                              uncertain_external_state=not terminated)
            if overflow.is_set():
                terminated = bool(_cancel_execution(execution_id)["termination_confirmed"])
                return _error("output_budget", "Sandbox raw output exceeded owner byte budget", retryable=False,
                              limit_reached=True, partial=True, output="", capture_budget_bytes=capture_bytes,
                              captured_bytes=captured_bytes, execution_id=execution_id,
                              termination_confirmed=terminated, uncertain_external_state=not terminated)
            if process.poll() is not None and all(not reader.is_alive() for reader in readers):
                break
            if deadline is not None and time.monotonic() >= deadline:
                terminated = bool(_cancel_execution(execution_id)["termination_confirmed"])
                return _error("timeout", "Sandbox process timed out", retryable=False,
                              execution_id=execution_id, termination_confirmed=terminated,
                              uncertain_external_state=not terminated)
            if process.poll() is not None:
                # A descendant may still hold inherited pipes. Never wait forever
                # or claim complete capture/termination when ownership is uncertain.
                for reader in readers: reader.join(timeout=0.2)
                if any(reader.is_alive() for reader in readers):
                    terminated = bool(_cancel_execution(execution_id)["termination_confirmed"])
                    return _error("output_capture_incomplete", "Owned output pipe did not close", retryable=False,
                                  execution_id=execution_id, termination_confirmed=terminated,
                                  uncertain_external_state=not terminated)
            else:
                time.sleep(0.02)
        if capture_failed.is_set():
            terminated = bool(_cancel_execution(execution_id)["termination_confirmed"])
            return _error("output_capture_failed", "Owned output capture failed", retryable=False,
                          execution_id=execution_id, termination_confirmed=terminated,
                          uncertain_external_state=not terminated)
        # Recheck after EOF: a reader can set overflow between the loop's first
        # event check and the final process/reader completion observation.
        if overflow.is_set():
            terminated = bool(_cancel_execution(execution_id)["termination_confirmed"])
            return _error("output_budget", "Sandbox raw output exceeded owner byte budget", retryable=False,
                          limit_reached=True, partial=True, output="", capture_budget_bytes=capture_bytes,
                          captured_bytes=captured_bytes, execution_id=execution_id,
                          termination_confirmed=terminated, uncertain_external_state=not terminated)
        job = record.get("job")
        if job is not None:
            try:
                background = job.active_count() > 0
            except OSError:
                background = True
            if background:
                terminated = bool(_cancel_execution(execution_id)["termination_confirmed"])
                return _error("background_descendants", "Owned descendants outlived the command", retryable=False,
                              execution_id=execution_id, termination_confirmed=terminated,
                              uncertain_external_state=not terminated)
        decoding_replaced = False
        try:
            stdout, stderr = (buffer.decode("utf-8") for buffer in buffers)
        except UnicodeDecodeError:
            decoding_replaced = True
            stdout, stderr = (buffer.decode("utf-8", errors="replace") for buffer in buffers)
        if record["cancelled"]:
            return _error("cancelled", "Sandbox execution was cancelled", execution_id=execution_id,
                          termination_confirmed=bool(record.get("termination_confirmed", False)),
                          uncertain_external_state=not bool(record.get("termination_confirmed", False)), retryable=False)
        output = _redact((stdout or "") + (stderr or ""), max_chars=0)
        truncated = output_chars > 0 and len(output) > output_chars
        return {"ok": process.returncode == 0, "code": process.returncode,
                "output": output[:output_chars] if output_chars > 0 else output,
                "output_chars_total": len(output), "output_budget_chars": output_chars,
                "captured_bytes": captured_bytes, "capture_budget_bytes": capture_bytes,
                "output_encoding": "utf-8", "output_decoding_replaced": decoding_replaced,
                "partial": truncated, "truncated": truncated, "limit_reached": truncated,
                "mode": "local", "retryable": False, "execution_id": execution_id}
    finally:
        if process.poll() is None or any(reader.is_alive() for reader in readers):
            _cancel_execution(execution_id)
        exited = process.poll() is not None and all(not reader.is_alive() for reader in readers)
        job = record.get("job")
        try:
            ownership_empty = job is None or job.active_count() == 0
        except OSError:
            ownership_empty = False
        with _execution_lock:
            record["finished"] = exited and ownership_empty and (not record["cancelled"] or bool(record["termination_confirmed"]))
            if exited and ownership_empty:
                record["process"] = None
                if record.get("job"): _close_record_job(record)
        # Keep failed-stop ownership for shutdown/retry instead of losing a PID.
        if exited:
            for stream in (process.stdout, process.stderr):
                if stream is not None: stream.close()


def _run_owned_process(req: SandboxExecRequest, command: list[str], cwd: Path, container: tuple[str, str] | None = None) -> dict[str, Any]:
    if req.execution_id or container or req.output_chars != MAX_OUTPUT or req.capture_bytes != MAX_CAPTURE_BYTES:
        return _run_process(command, cwd, req.timeout, allow_network=req.allow_network, execution_id=req.execution_id, container=container, output_chars=req.output_chars, capture_bytes=req.capture_bytes)
    return _run_process(command, cwd, req.timeout, allow_network=req.allow_network)


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
        if not alive:
            _cancel_all_processes()
            os._exit(0)


@app.get("/health")
def health() -> dict[str, Any]:
    return {"ok": True, "service": "aurorafox_computer_primitives", "version": "1.1.0", "platform": "windows" if IS_WINDOWS else os.name, "computer_supported": IS_WINDOWS, "planning_owner": "aurorafox_core", "service_side_ai_planning": False, "external_ai_required": False, "network_required": False, "authenticated_channel_configured": bool(SERVICE_TOKEN), "virtual_desktop": _desktop_bounds(), "failsafe": True, "container_engine_available": bool(_container_engine()), "degraded_local_sandbox_enabled": ALLOW_DEGRADED_LOCAL_SANDBOX}


@app.get("/capabilities")
def capabilities(x_aurorafox_computer_token: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, "1", require_autonomy=False)
    return {"ok": True, "computer_supported": IS_WINDOWS, "platform": "windows" if IS_WINDOWS else os.name, "screen": IS_WINDOWS, "windows": IS_WINDOWS, "mouse": IS_WINDOWS, "keyboard": IS_WINDOWS, "clipboard": False, "service_side_planning": False, "local_core_planning_required": True, "sandbox": True, "degraded_local_sandbox_enabled": ALLOW_DEGRADED_LOCAL_SANDBOX, "snapshot_max_entries": MAX_SNAPSHOT_ENTRIES, "snapshot_max_bytes": MAX_SNAPSHOT_BYTES}


@app.get("/screen")
def screen(x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None),
           x_aurorafox_execution_id: str = Header(default="", max_length=160, pattern=r"^[A-Za-z0-9_:.-]*$"),
            x_aurorafox_gui_limits: str = Header(default="")) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed)
    limits = _gui_limits(x_aurorafox_gui_limits)
    with _gui_execution_scope(x_aurorafox_execution_id) as (execution_id, error):
        if error is not None: return error
        result = _run_worker("screen", {"__execution_id": execution_id, "__gui_limits": limits}, limits["worker_seconds"])
        if result.get("ok"):
            windows_result = _run_worker("windows", {"__execution_id": execution_id, "__gui_limits": limits}, limits["worker_seconds"])
            if _execution_records[execution_id]["cancelled"]:
                return _error("cancelled", "Screen request was cancelled", retryable=False, execution_id=execution_id,
                              termination_confirmed=bool(_execution_records[execution_id]["termination_confirmed"]))
            result["uia"] = windows_result.get("items", []) if windows_result.get("ok") else []
            result["uia_ok"] = bool(windows_result.get("ok"))
            result["uia_partial"] = not result["uia_ok"] or bool(windows_result.get("partial"))
            result["uia_limit_reasons"] = windows_result.get("limit_reasons", [])
            result["uia_failed_elements"] = windows_result.get("failed_elements", 0)
            if not result["uia_ok"]: result["uia_error"] = windows_result.get("error", "uia_unverified")
            result["partial"] = bool(result.get("partial")) or result["uia_partial"]
            result["virtual_desktop"] = _desktop_bounds(); result["retryable"] = True
        return result


@app.get("/windows")
def windows(x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None),
            x_aurorafox_execution_id: str = Header(default="", max_length=160, pattern=r"^[A-Za-z0-9_:.-]*$"),
            x_aurorafox_gui_limits: str = Header(default="")) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed)
    limits = _gui_limits(x_aurorafox_gui_limits)
    with _gui_execution_scope(x_aurorafox_execution_id) as (execution_id, error):
        if error is not None: return error
        result = _run_worker("windows", {"__execution_id": execution_id, "__gui_limits": limits}, limits["worker_seconds"])
        result["retryable"] = result.get("error") not in {"cancelled", "execution_id_reused", "service_stopping"} and not result.get("uncertain_external_state", False)
        return result


@app.post("/action")
def action(req: Action, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None),
           x_aurorafox_execution_id: str = Header(default="", max_length=160, pattern=r"^[A-Za-z0-9_:.-]*$"),
           x_aurorafox_gui_limits: str = Header(default="")) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed)
    return _execute_action(req, x_aurorafox_execution_id, _gui_limits(x_aurorafox_gui_limits))


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
def workspace_tree(workspace: str, area: str = "work", x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None), max_items: int = 2000) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); wid = _safe_workspace_id(workspace)
    if area not in {"input", "work", "output", "logs", "snapshots"}: raise HTTPException(status_code=400, detail="Invalid workspace area")
    coverage = {}
    items = _tree(_safe_sandbox_path(f"{wid}/{area}"), max_items, coverage)
    return {"ok": True, "workspace": wid, "area": area, "items": items, **coverage, "partial": any(coverage.values())}


@app.post("/sandbox/workspace/snapshot")
def workspace_snapshot(req: WorkspaceSnapshotRequest, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); wid = _safe_workspace_id(req.workspace); work = _safe_sandbox_path(f"{wid}/work"); snapshots = _safe_sandbox_path(f"{wid}/snapshots"); snapshots.mkdir(parents=True, exist_ok=True)
    safe_label = "".join(ch if ch.isalnum() or ch in "_-" else "_" for ch in req.label)[:48] or "checkpoint"; snapshot_id = f"{int(time.time())}_{safe_label}_{uuid.uuid4().hex[:6]}"; target = snapshots / snapshot_id; stats = _copy_snapshot_tree(work, target, req.max_entries, req.max_bytes)
    return {"ok": True, "workspace": wid, "snapshot": snapshot_id, "path": f"{wid}/snapshots/{snapshot_id}", "entries": stats["entries"], "bytes": stats["bytes"]}


@app.post("/sandbox/workspace/rollback")
def workspace_rollback(req: WorkspaceRollbackRequest, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); wid = _safe_workspace_id(req.workspace); sid = _safe_workspace_id(req.snapshot); work = _safe_sandbox_path(f"{wid}/work"); source = _safe_sandbox_path(f"{wid}/snapshots/{sid}", must_exist=True)
    if not source.is_dir(): raise HTTPException(status_code=404, detail="Snapshot not found")
    replacement = _safe_sandbox_path(f"{wid}/work.rollback.{uuid.uuid4().hex}"); stats = _copy_snapshot_tree(source, replacement, req.max_entries, req.max_bytes)
    if work.exists():
        backup = _safe_sandbox_path(f"{wid}/work.pre_rollback.{uuid.uuid4().hex}"); os.replace(work, backup)
        try: os.replace(replacement, work)
        except Exception: os.replace(backup, work); raise
        shutil.rmtree(backup, ignore_errors=True)
    else: os.replace(replacement, work)
    return {"ok": True, "workspace": wid, "snapshot": sid, "entries": stats["entries"], "bytes": stats["bytes"]}


@app.get("/sandbox/list")
def sandbox_list(path: str = ".", x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None),
                 max_items: int = 0, x_aurorafox_sandbox_items: int | None = Header(default=None, ge=0)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed)
    budget = max_items if x_aurorafox_sandbox_items is None else x_aurorafox_sandbox_items
    if budget < 0: raise HTTPException(400, "List item budget must be nonnegative")
    p = _safe_sandbox_path(path)
    items = []
    result = {"ok": True, "items": items, "partial": False, "truncated": False, "limit_reached": False, "failed_paths": 0, "unsafe_paths_skipped": 0}
    if not p.exists(): return result
    if not p.is_dir(): raise HTTPException(status_code=400, detail="Not a directory")
    with os.scandir(p) as iterator:
        for entry in iterator:
            try:
                child = Path(entry.path)
                resolved = child.resolve(strict=True)
                if resolved != SANDBOX_ROOT and SANDBOX_ROOT not in resolved.parents:
                    result["unsafe_paths_skipped"] += 1
                    continue
                if budget > 0 and len(items) >= budget:
                    result["truncated"] = result["limit_reached"] = True
                    break
                info = entry.stat()
                items.append({"name": entry.name, "dir": entry.is_dir(), "size": info.st_size if entry.is_file() else 0})
            except OSError: result["failed_paths"] += 1
    result["partial"] = bool(result["truncated"] or result["failed_paths"] or result["unsafe_paths_skipped"])
    return result


@app.get("/sandbox/read")
def sandbox_read(path: str, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None), max_bytes: int = MAX_READ_BYTES) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); p = _safe_sandbox_path(path, must_exist=True)
    if not p.is_file(): raise HTTPException(status_code=404, detail="File not found")
    if max_bytes < 0: raise HTTPException(400, "Read byte budget must be nonnegative")
    if max_bytes > 0 and p.stat().st_size > max_bytes:
        raise HTTPException(413, "File exceeds owner byte budget")
    with os.fdopen(os.open(p, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)), "rb") as source:
        data = source.read(max_bytes + 1) if max_bytes > 0 else source.read()
    if max_bytes > 0 and len(data) > max_bytes: raise HTTPException(413, "File grew beyond owner byte budget")
    try: return {"ok": True, "text": data.decode("utf-8")}
    except UnicodeDecodeError: return {"ok": True, "base64": base64.b64encode(data).decode("ascii")}


@app.post("/sandbox/write")
def sandbox_write(req: SandboxWriteRequest, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); encoded = req.content.encode("utf-8")
    if req.max_bytes > 0 and len(encoded) > req.max_bytes: raise HTTPException(status_code=413, detail="Write payload too large")
    path = _safe_sandbox_path(req.path); path.parent.mkdir(parents=True, exist_ok=True); temp = path.parent / f".{path.name}.{uuid.uuid4().hex}.tmp"; temp.write_bytes(encoded); os.replace(temp, path)
    return {"ok": True, "path": path.relative_to(SANDBOX_ROOT).as_posix()}


@app.post("/sandbox/cancel_all")
def sandbox_cancel_all(x_aurorafox_computer_token: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, None, require_autonomy=False)
    return _cancel_all_processes()


@app.post("/sandbox/cancel")
def sandbox_cancel(req: SandboxCancelRequest, x_aurorafox_computer_token: str | None = Header(default=None)) -> dict[str, Any]:
    # Stopping an already-owned execution must remain possible after Master Stop.
    _authorize(x_aurorafox_computer_token, None, require_autonomy=False)
    return _cancel_execution(req.execution_id)


@app.post("/sandbox/exec")
def sandbox_exec(req: SandboxExecRequest, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed)
    if not ALLOW_DEGRADED_LOCAL_SANDBOX:
        raise HTTPException(status_code=403, detail="Degraded local process sandbox is disabled by default; use container mode or explicit operator opt-in")
    command = _validate_command(req.command); cwd = _safe_sandbox_path(req.cwd); cwd.mkdir(parents=True, exist_ok=True); result = _run_owned_process(req, command, cwd); result["network_requested"] = bool(req.allow_network); result["network_isolation_enforced"] = False; return result


@app.post("/sandbox/container_exec")
def sandbox_container_exec(req: SandboxExecRequest, x_aurorafox_computer_token: str | None = Header(default=None), x_aurorafox_autonomy_allowed: str | None = Header(default=None)) -> dict[str, Any]:
    _authorize(x_aurorafox_computer_token, x_aurorafox_autonomy_allowed); command = _validate_command(req.command); engine = _container_engine()
    if not engine: raise HTTPException(status_code=404, detail="Docker/Podman not installed")
    cwd = _safe_sandbox_path(req.cwd); cwd.mkdir(parents=True, exist_ok=True); image, inner_command = _container_profile(command); network_args = [] if req.allow_network else ["--network", "none"]
    container_name = "aurorafox-" + uuid.uuid4().hex
    run_command = [engine, "run", "--rm", "--name", container_name, "--pull=never", *network_args, "--read-only", "--memory", os.getenv("AURORAFOX_CONTAINER_MEMORY", "2g"), "--cpus", os.getenv("AURORAFOX_CONTAINER_CPUS", "2"), "--pids-limit", os.getenv("AURORAFOX_CONTAINER_PIDS", "256"), "--security-opt", "no-new-privileges", "--tmpfs", "/tmp:rw,noexec,nosuid,size=256m", "-v", f"{cwd}:/workspace:rw", "-w", "/workspace", image, *inner_command]
    result = _run_owned_process(req, run_command, cwd, (engine, container_name)); result.update({"mode": "container", "engine": engine, "image": image, "network": "allowed" if req.allow_network else "none", "network_isolation_enforced": not req.allow_network, "image_pull_allowed": False}); return result


if __name__ == "__main__":
    import uvicorn

    if PARENT_PID > 0: threading.Thread(target=_parent_watchdog, name="aurorafox-parent-watchdog", daemon=True).start()
    uvicorn.run(app, host=HOST, port=PORT, access_log=False, log_level="warning")
