from __future__ import annotations

import base64
import io
import json
import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any

import pyautogui
import requests
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from pywinauto import Desktop

HOST = os.getenv("AURORAFOX_COMPUTER_HOST", "127.0.0.1")
PORT = int(os.getenv("AURORAFOX_COMPUTER_PORT", "8766"))
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
VISION_MODEL = os.getenv("AURORAFOX_VISION_MODEL", "qwen3-vl:8b")
SANDBOX_ROOT = Path(os.getenv("AURORAFOX_SANDBOX_ROOT", str(Path.cwd() / "sandbox"))).resolve()
MAX_OUTPUT = 120_000

SANDBOX_ROOT.mkdir(parents=True, exist_ok=True)
pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.12

app = FastAPI(title="AuroraFox Computer Agent", version="0.3.0")


class Action(BaseModel):
    type: str
    x: int | None = None
    y: int | None = None
    button: str = "left"
    clicks: int = 1
    text: str = ""
    keys: list[str] = Field(default_factory=list)
    amount: int = 0
    seconds: float = 0.2


class GoalRequest(BaseModel):
    goal: str = Field(min_length=1, max_length=8000)
    max_steps: int = Field(default=20, ge=1, le=100)
    auto_execute: bool = False


class SandboxExecRequest(BaseModel):
    command: list[str]
    cwd: str = "."
    timeout: int = Field(default=60, ge=1, le=600)


class SandboxWriteRequest(BaseModel):
    path: str
    content: str


def _safe_sandbox_path(relative: str) -> Path:
    target = (SANDBOX_ROOT / relative).resolve()
    if SANDBOX_ROOT != target and SANDBOX_ROOT not in target.parents:
        raise HTTPException(status_code=400, detail="Path escapes sandbox")
    return target


def _screen_png() -> bytes:
    image = pyautogui.screenshot()
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    return buf.getvalue()


def _screen_b64() -> str:
    return base64.b64encode(_screen_png()).decode("ascii")


def _uia_snapshot(limit: int = 250) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    try:
        windows = Desktop(backend="uia").windows()
        for w in windows[:30]:
            try:
                rect = w.rectangle()
                items.append({
                    "kind": "window",
                    "name": w.window_text(),
                    "control_type": getattr(w.element_info, "control_type", "Window"),
                    "rect": [rect.left, rect.top, rect.right, rect.bottom],
                })
                for c in w.descendants()[:40]:
                    if len(items) >= limit:
                        return items
                    try:
                        cr = c.rectangle()
                        name = c.window_text() or getattr(c.element_info, "name", "")
                        if not name and getattr(c.element_info, "control_type", "") not in {"Button", "Edit", "Text", "CheckBox", "MenuItem"}:
                            continue
                        items.append({
                            "kind": "control",
                            "name": name,
                            "control_type": getattr(c.element_info, "control_type", ""),
                            "automation_id": getattr(c.element_info, "automation_id", ""),
                            "rect": [cr.left, cr.top, cr.right, cr.bottom],
                        })
                    except Exception:
                        pass
            except Exception:
                pass
    except Exception:
        pass
    return items


def _execute(action: Action) -> dict[str, Any]:
    t = action.type.lower().strip()
    try:
        if t == "move":
            pyautogui.moveTo(action.x, action.y, duration=max(0.0, action.seconds))
        elif t == "click":
            pyautogui.click(action.x, action.y, clicks=max(1, action.clicks), button=action.button)
        elif t == "double_click":
            pyautogui.doubleClick(action.x, action.y, button=action.button)
        elif t == "right_click":
            pyautogui.rightClick(action.x, action.y)
        elif t == "drag":
            pyautogui.moveTo(action.x, action.y, duration=0.1)
            raise ValueError("drag requires dedicated start/end action; use move + mouse_down/move/mouse_up")
        elif t == "mouse_down":
            pyautogui.mouseDown(action.x, action.y, button=action.button)
        elif t == "mouse_up":
            pyautogui.mouseUp(action.x, action.y, button=action.button)
        elif t == "scroll":
            pyautogui.scroll(action.amount, x=action.x, y=action.y)
        elif t == "type":
            pyautogui.write(action.text, interval=0.02)
        elif t == "press":
            for key in action.keys:
                pyautogui.press(key)
        elif t == "hotkey":
            pyautogui.hotkey(*action.keys)
        elif t == "wait":
            time.sleep(max(0.0, min(action.seconds, 30.0)))
        elif t == "done":
            return {"ok": True, "done": True}
        else:
            raise ValueError(f"Unsupported action type: {action.type}")
        return {"ok": True, "done": False}
    except pyautogui.FailSafeException:
        raise HTTPException(status_code=409, detail="Emergency stop: mouse moved to top-left corner")
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def _vision_plan(goal: str, history: list[dict[str, Any]]) -> dict[str, Any]:
    image = _screen_b64()
    uia = _uia_snapshot()
    system = (
        "You are AuroraFox Computer Agent on a Windows desktop. Analyze the current screenshot and UI Automation tree. "
        "Choose exactly ONE next low-risk UI action that advances the user's stated goal. "
        "Return ONLY strict JSON with keys: reasoning_short, action. "
        "action must be one of: click, double_click, right_click, move, scroll, type, press, hotkey, wait, done. "
        "For click actions provide x,y. For type provide text. For hotkey/press provide keys. "
        "Do not attempt destructive actions, account/security bypass, credential extraction, purchases, or irreversible changes. "
        "If the task is complete, choose done."
    )
    user_text = json.dumps({"goal": goal, "recent_history": history[-8:], "uia": uia[:250]}, ensure_ascii=False)
    payload = {
        "model": VISION_MODEL,
        "stream": False,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user_text, "images": [image]},
        ],
        "options": {"temperature": 0.1},
    }
    r = requests.post(f"{OLLAMA_URL}/api/chat", json=payload, timeout=180)
    if r.status_code != 200:
        raise HTTPException(status_code=502, detail=f"Ollama error {r.status_code}: {r.text[:1000]}")
    content = str(r.json().get("message", {}).get("content", "")).strip()
    if content.startswith("```"):
        content = content.strip("`")
        if content.startswith("json"):
            content = content[4:].strip()
    try:
        data = json.loads(content)
        if not isinstance(data, dict) or "action" not in data:
            raise ValueError("missing action")
        return data
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Vision model returned invalid JSON: {content[:1500]}") from exc


def _container_engine() -> str | None:
    preferred = os.getenv("AURORAFOX_CONTAINER_ENGINE", "").strip()
    if preferred and shutil.which(preferred):
        return preferred
    for name in ("docker", "podman"):
        if shutil.which(name):
            return name
    return None


def _container_profile(command: list[str]) -> tuple[str, list[str]]:
    exe = Path(command[0]).name.lower()
    image_map = {
        "python": os.getenv("AURORAFOX_IMAGE_PYTHON", "python:3-slim"),
        "python3": os.getenv("AURORAFOX_IMAGE_PYTHON", "python:3-slim"),
        "pytest": os.getenv("AURORAFOX_IMAGE_PYTHON", "python:3-slim"),
        "node": os.getenv("AURORAFOX_IMAGE_NODE", "node:22-bookworm-slim"),
        "npm": os.getenv("AURORAFOX_IMAGE_NODE", "node:22-bookworm-slim"),
        "npx": os.getenv("AURORAFOX_IMAGE_NODE", "node:22-bookworm-slim"),
        "go": os.getenv("AURORAFOX_IMAGE_GO", "golang:1-bookworm"),
        "cargo": os.getenv("AURORAFOX_IMAGE_RUST", "rust:1-bookworm"),
        "rustc": os.getenv("AURORAFOX_IMAGE_RUST", "rust:1-bookworm"),
        "java": os.getenv("AURORAFOX_IMAGE_JAVA", "eclipse-temurin:21-jdk"),
        "javac": os.getenv("AURORAFOX_IMAGE_JAVA", "eclipse-temurin:21-jdk"),
        "gradle": os.getenv("AURORAFOX_IMAGE_GRADLE", "gradle:8-jdk21"),
        "dotnet": os.getenv("AURORAFOX_IMAGE_DOTNET", "mcr.microsoft.com/dotnet/sdk:9.0"),
        "gcc": os.getenv("AURORAFOX_IMAGE_CPP", "gcc:latest"),
        "g++": os.getenv("AURORAFOX_IMAGE_CPP", "gcc:latest"),
        "cmake": os.getenv("AURORAFOX_IMAGE_CPP", "gcc:latest"),
        "ruby": os.getenv("AURORAFOX_IMAGE_RUBY", "ruby:3-slim"),
        "php": os.getenv("AURORAFOX_IMAGE_PHP", "php:8-cli"),
    }
    image = image_map.get(exe)
    if not image:
        raise HTTPException(status_code=403, detail=f"No container profile for executable: {exe}")
    return image, command


@app.get("/health")
def health():
    return {
        "ok": True,
        "vision_model": VISION_MODEL,
        "ollama_url": OLLAMA_URL,
        "screen": list(pyautogui.size()),
        "sandbox_root": str(SANDBOX_ROOT),
        "failsafe": True,
        "container_engine": _container_engine(),
    }


@app.get("/screen")
def screen():
    return {"ok": True, "png_base64": _screen_b64(), "uia": _uia_snapshot()}


@app.get("/windows")
def windows():
    return {"ok": True, "items": _uia_snapshot()}


@app.post("/action")
def action(req: Action):
    return _execute(req)


@app.post("/plan")
def plan(req: GoalRequest):
    return {"ok": True, "step": _vision_plan(req.goal, [])}


@app.post("/run")
def run(req: GoalRequest):
    history: list[dict[str, Any]] = []
    for index in range(req.max_steps):
        step = _vision_plan(req.goal, history)
        action_data = step.get("action", {})
        if not isinstance(action_data, dict):
            raise HTTPException(status_code=502, detail="Invalid action")
        history.append({"index": index + 1, "step": step})
        if not req.auto_execute:
            return {"ok": True, "needs_confirmation": True, "history": history, "next_action": action_data}
        result = _execute(Action(**action_data))
        history[-1]["result"] = result
        if result.get("done"):
            return {"ok": True, "done": True, "history": history}
        time.sleep(0.25)
    return {"ok": True, "done": False, "history": history, "reason": "max_steps reached"}


@app.get("/sandbox/list")
def sandbox_list(path: str = "."):
    p = _safe_sandbox_path(path)
    if not p.exists():
        return {"ok": True, "items": []}
    if not p.is_dir():
        raise HTTPException(status_code=400, detail="Not a directory")
    items = []
    for c in p.iterdir():
        items.append({"name": c.name, "dir": c.is_dir(), "size": c.stat().st_size if c.is_file() else 0})
    return {"ok": True, "items": items}


@app.get("/sandbox/read")
def sandbox_read(path: str):
    p = _safe_sandbox_path(path)
    if not p.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    data = p.read_bytes()
    if len(data) > 5_000_000:
        raise HTTPException(status_code=413, detail="File too large")
    try:
        return {"ok": True, "text": data.decode("utf-8")}
    except UnicodeDecodeError:
        return {"ok": True, "base64": base64.b64encode(data).decode("ascii")}


@app.post("/sandbox/write")
def sandbox_write(req: SandboxWriteRequest):
    p = _safe_sandbox_path(req.path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(req.content, encoding="utf-8")
    return {"ok": True, "path": str(p.relative_to(SANDBOX_ROOT))}


@app.post("/sandbox/exec")
def sandbox_exec(req: SandboxExecRequest):
    if not req.command:
        raise HTTPException(status_code=400, detail="Empty command")
    cwd = _safe_sandbox_path(req.cwd)
    cwd.mkdir(parents=True, exist_ok=True)
    exe = Path(req.command[0]).name.lower()
    allowed = {
        "python", "python.exe", "python3", "py", "pytest", "pytest.exe",
        "git", "git.exe", "godot", "godot.exe", "godot4", "godot4.exe",
        "node", "node.exe", "npm", "npm.cmd", "npx", "npx.cmd",
        "go", "go.exe", "cargo", "cargo.exe", "rustc", "rustc.exe",
        "dotnet", "dotnet.exe", "java", "java.exe", "javac", "javac.exe",
        "gradle", "gradle.bat", "gradlew", "gradlew.bat",
        "gcc", "gcc.exe", "g++", "g++.exe", "clang", "clang.exe", "cmake", "cmake.exe", "ninja", "ninja.exe",
        "ruby", "ruby.exe", "php", "php.exe", "lua", "lua.exe",
    }
    if exe not in allowed:
        raise HTTPException(status_code=403, detail=f"Executable not allowed in local sandbox: {exe}")
    try:
        cp = subprocess.run(req.command, cwd=cwd, capture_output=True, text=True, timeout=req.timeout, shell=False)
        out = (cp.stdout or "") + (cp.stderr or "")
        return {"ok": cp.returncode == 0, "code": cp.returncode, "output": out[:MAX_OUTPUT], "mode": "local"}
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=f"Executable not installed: {exe}") from exc
    except subprocess.TimeoutExpired as exc:
        raise HTTPException(status_code=408, detail="Sandbox command timed out") from exc


@app.post("/sandbox/container_exec")
def sandbox_container_exec(req: SandboxExecRequest):
    if not req.command:
        raise HTTPException(status_code=400, detail="Empty command")
    engine = _container_engine()
    if not engine:
        raise HTTPException(status_code=404, detail="Docker/Podman not installed")
    cwd = _safe_sandbox_path(req.cwd)
    cwd.mkdir(parents=True, exist_ok=True)
    image, inner_command = _container_profile(req.command)
    # Only the current task directory is writable. Network is disabled by default.
    run_command = [
        engine, "run", "--rm", "--network", "none", "--read-only",
        "--memory", os.getenv("AURORAFOX_CONTAINER_MEMORY", "2g"),
        "--cpus", os.getenv("AURORAFOX_CONTAINER_CPUS", "2"),
        "--pids-limit", os.getenv("AURORAFOX_CONTAINER_PIDS", "256"),
        "--security-opt", "no-new-privileges",
        "--tmpfs", "/tmp:rw,noexec,nosuid,size=256m",
        "-v", f"{cwd}:/workspace:rw",
        "-w", "/workspace",
        image,
        *inner_command,
    ]
    try:
        cp = subprocess.run(run_command, capture_output=True, text=True, timeout=req.timeout, shell=False)
        out = (cp.stdout or "") + (cp.stderr or "")
        return {
            "ok": cp.returncode == 0,
            "code": cp.returncode,
            "output": out[:MAX_OUTPUT],
            "mode": "container",
            "engine": engine,
            "image": image,
            "network": "none",
        }
    except subprocess.TimeoutExpired as exc:
        raise HTTPException(status_code=408, detail="Container command timed out") from exc


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT)
