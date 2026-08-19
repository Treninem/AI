from __future__ import annotations

import asyncio
import json
import os
import time
import uuid
from collections import defaultdict, deque
from pathlib import Path
from typing import Any, Literal

from fastapi import Depends, FastAPI, Header, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from api.auth import DEFAULT_SCOPES, KeyStore, allows
from api.conversation_store import ConversationStore
from api.file_client import FileIntelligenceClient
from api.ollama_client import OllamaClient
from api.runtime_bridge import AuroraRuntimeBridge

HOST = os.getenv("AURORAFOX_API_HOST", "127.0.0.1")
PORT = int(os.getenv("AURORAFOX_API_PORT", "8768"))
USER_ROOT = Path(os.getenv("AURORAFOX_USER_DIR", str(Path.home() / ".aurorafox"))).resolve()
API_ROOT = USER_ROOT / "api"
API_ROOT.mkdir(parents=True, exist_ok=True)

keys = KeyStore(API_ROOT)
keys.ensure_bootstrap_key()
conversations = ConversationStore(API_ROOT / "conversations")
bridge = AuroraRuntimeBridge(
    host=os.getenv("AURORAFOX_BRIDGE_HOST", "127.0.0.1"),
    port=int(os.getenv("AURORAFOX_BRIDGE_PORT", "8770")),
)
ollama = OllamaClient(
    base_url=os.getenv("OLLAMA_URL", "http://127.0.0.1:11434"),
    preferred_model=os.getenv("AURORAFOX_CHAT_MODEL", "qwen3:8b"),
)
files = FileIntelligenceClient(API_ROOT / "uploads", os.getenv("AURORAFOX_FILES_URL", "http://127.0.0.1:8767"))

app = FastAPI(
    title="AuroraFox API",
    version="1.0.0",
    description="External gateway to AuroraFox AgentCore, memory, tools, files and local models.",
)

origins = [x.strip() for x in os.getenv("AURORAFOX_API_CORS", "").split(",") if x.strip()]
if origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=False,
        allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
    )


class RateLimiter:
    def __init__(self, limit: int = 60, window: float = 60.0):
        self.limit = max(1, limit)
        self.window = max(1.0, window)
        self.hits: dict[str, deque[float]] = defaultdict(deque)

    def check(self, key_id: str) -> None:
        now = time.monotonic()
        q = self.hits[key_id]
        while q and now - q[0] > self.window:
            q.popleft()
        if len(q) >= self.limit:
            raise HTTPException(429, "AuroraFox API rate limit exceeded")
        q.append(now)


rate_limiter = RateLimiter(int(os.getenv("AURORAFOX_API_RPM", "60")), 60.0)


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=100000)
    conversation_id: str | None = Field(default=None, max_length=256)
    mode: Literal["auto", "agent", "ollama"] = "auto"
    temperature: float = Field(default=0.2, ge=0.0, le=2.0)
    metadata: dict[str, Any] = Field(default_factory=dict)


class FileAnalyzeRequest(BaseModel):
    filename: str = Field(min_length=1, max_length=255)
    content_base64: str = Field(min_length=1)
    question: str = Field(default="", max_length=12000)
    visual: bool = True


class ToolRunRequest(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    args: dict[str, Any] = Field(default_factory=dict)


class KeyCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    scopes: list[str] = Field(default_factory=lambda: list(DEFAULT_SCOPES))


class OpenAIMessage(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str


class OpenAIChatRequest(BaseModel):
    model: str = "aurorafox-agent"
    messages: list[OpenAIMessage]
    temperature: float = Field(default=0.2, ge=0.0, le=2.0)
    stream: bool = False
    user: str | None = None


def _auth(authorization: str = Header(default="")) -> dict[str, Any]:
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "Missing AuroraFox API bearer key")
    record = keys.verify(authorization[7:].strip())
    if record is None:
        raise HTTPException(401, "Invalid or revoked AuroraFox API key")
    rate_limiter.check(str(record.get("id", "unknown")))
    return record


def _require(record: dict[str, Any], scope: str) -> None:
    if not allows(record, scope):
        raise HTTPException(403, f"API key does not have scope: {scope}")


def _execute_chat(message: str, context: list[dict[str, Any]], mode: str, temperature: float, conversation_id: str) -> dict[str, Any]:
    bridge_error = ""
    if mode in {"auto", "agent"}:
        try:
            result = bridge.chat(message, context, conversation_id)
            if result.get("ok", False):
                return {
                    "ok": True,
                    "content": str(result.get("content", "")),
                    "runtime": "aurorafox-agent",
                    "model": str(result.get("model", "agent")),
                    "details": result.get("details", {}),
                }
            bridge_error = str(result.get("error", "AgentCore bridge rejected request"))
        except Exception as exc:
            bridge_error = str(exc)
        if mode == "agent":
            raise HTTPException(503, f"AuroraFox AgentCore is unavailable: {bridge_error}")

    try:
        messages = list(context) + [{"role": "user", "content": message}]
        return ollama.chat(messages, temperature=temperature)
    except Exception as exc:
        detail = f"AgentCore unavailable: {bridge_error}; Ollama fallback failed: {exc}" if bridge_error else str(exc)
        raise HTTPException(503, detail) from exc


def _native_chat(req: ChatRequest, record: dict[str, Any]) -> dict[str, Any]:
    _require(record, "chat")
    owner = str(record.get("id", "unknown"))
    conversation_id = req.conversation_id or uuid.uuid4().hex
    context = conversations.context(owner, conversation_id, 24)
    result = _execute_chat(req.message, context, req.mode, req.temperature, conversation_id)
    conversations.append(owner, conversation_id, "user", req.message, req.metadata)
    conversations.append(owner, conversation_id, "assistant", str(result.get("content", "")), {
        "runtime": result.get("runtime", ""),
        "model": result.get("model", ""),
    })
    return {
        "ok": True,
        "conversation_id": conversation_id,
        "reply": str(result.get("content", "")),
        "runtime": result.get("runtime", ""),
        "model": result.get("model", ""),
    }


@app.get("/health")
def health() -> dict[str, Any]:
    agent_online = False
    agent_details: dict[str, Any] = {}
    try:
        status = bridge.status()
        agent_online = bool(status.get("ok", False))
        agent_details = status
    except Exception:
        pass
    ollama_models: list[str] = []
    try:
        ollama_models = ollama.models()
    except Exception:
        pass
    return {
        "ok": True,
        "service": "AuroraFox API",
        "agent_online": agent_online,
        "agent": agent_details,
        "ollama_online": bool(ollama_models),
        "ollama_models": ollama_models,
        "bridge": f"127.0.0.1:{bridge.port}",
    }


@app.get("/v1/capabilities")
def capabilities(record: dict[str, Any] = Depends(_auth)) -> dict[str, Any]:
    return {
        "object": "aurorafox.capabilities",
        "scopes": record.get("scopes", []),
        "features": [
            "agent-chat", "ollama-fallback", "conversation-memory", "openai-compatible-chat",
            "websocket", "file-intelligence", "tool-discovery", "scoped-api-keys",
        ],
    }


@app.post("/v1/chat")
def chat(req: ChatRequest, record: dict[str, Any] = Depends(_auth)) -> dict[str, Any]:
    return _native_chat(req, record)


@app.get("/v1/conversations/{conversation_id}")
def get_conversation(conversation_id: str, record: dict[str, Any] = Depends(_auth)) -> dict[str, Any]:
    _require(record, "conversations.read")
    return conversations.get(str(record.get("id", "unknown")), conversation_id)


@app.delete("/v1/conversations/{conversation_id}")
def delete_conversation(conversation_id: str, record: dict[str, Any] = Depends(_auth)) -> dict[str, Any]:
    _require(record, "chat")
    return {"ok": True, "removed": conversations.clear(str(record.get("id", "unknown")), conversation_id)}


@app.get("/v1/models")
def models(record: dict[str, Any] = Depends(_auth)) -> dict[str, Any]:
    _require(record, "models.read")
    items = [{"id": "aurorafox-agent", "object": "model", "owned_by": "aurorafox"}]
    try:
        for name in ollama.models():
            items.append({"id": name, "object": "model", "owned_by": "ollama"})
    except Exception:
        pass
    return {"object": "list", "data": items}


@app.get("/v1/tools")
def list_tools(record: dict[str, Any] = Depends(_auth)) -> dict[str, Any]:
    _require(record, "tools.read")
    try:
        result = bridge.tools()
        if not result.get("ok", False):
            raise RuntimeError(str(result.get("error", "bridge error")))
        return result
    except Exception as exc:
        raise HTTPException(503, f"AgentCore tools unavailable: {exc}") from exc


@app.post("/v1/tools/run")
def run_tool(req: ToolRunRequest, record: dict[str, Any] = Depends(_auth)) -> dict[str, Any]:
    _require(record, "tools.run")
    try:
        result = bridge.run_tool(req.name, req.args)
        if not result.get("ok", False):
            raise HTTPException(422, str(result.get("error", "Tool failed")))
        return result
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, f"AgentCore tool bridge unavailable: {exc}") from exc


@app.post("/v1/files/analyze")
def analyze_file(req: FileAnalyzeRequest, record: dict[str, Any] = Depends(_auth)) -> dict[str, Any]:
    _require(record, "files")
    try:
        return files.analyze_base64(req.filename, req.content_base64, req.question, req.visual)
    except Exception as exc:
        raise HTTPException(422, f"File analysis failed: {exc}") from exc


@app.post("/v1/chat/completions")
def openai_chat(req: OpenAIChatRequest, record: dict[str, Any] = Depends(_auth)):
    _require(record, "chat")
    messages = [m.model_dump() for m in req.messages]
    user_positions = [i for i, item in enumerate(messages) if item["role"] == "user"]
    if not user_positions:
        raise HTTPException(400, "messages must contain at least one user message")
    last = user_positions[-1]
    message = str(messages[last]["content"])
    context = messages[:last]
    conversation_id = req.user or uuid.uuid4().hex
    mode = "agent" if req.model == "aurorafox-agent" else "auto"
    result = _execute_chat(message, context, mode, req.temperature, conversation_id)
    created = int(time.time())
    completion_id = "chatcmpl-" + uuid.uuid4().hex
    model_name = str(result.get("model", req.model))
    content = str(result.get("content", ""))

    if req.stream:
        async def stream():
            first = {
                "id": completion_id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": model_name,
                "choices": [{"index": 0, "delta": {"role": "assistant", "content": content}, "finish_reason": None}],
            }
            done = {
                "id": completion_id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": model_name,
                "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
            }
            yield "data: " + json.dumps(first, ensure_ascii=False) + "\n\n"
            yield "data: " + json.dumps(done, ensure_ascii=False) + "\n\n"
            yield "data: [DONE]\n\n"
        return StreamingResponse(stream(), media_type="text/event-stream")

    return {
        "id": completion_id,
        "object": "chat.completion",
        "created": created,
        "model": model_name,
        "choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}],
        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
    }


@app.get("/v1/admin/keys")
def list_keys(record: dict[str, Any] = Depends(_auth)) -> dict[str, Any]:
    _require(record, "admin.keys")
    return {"ok": True, "keys": keys.list()}


@app.post("/v1/admin/keys")
def create_key(req: KeyCreateRequest, record: dict[str, Any] = Depends(_auth)) -> dict[str, Any]:
    _require(record, "admin.keys")
    token, created = keys.create(req.name, req.scopes)
    clean = dict(created)
    clean.pop("token_hash", None)
    return {"ok": True, "api_key": token, "key": clean}


@app.delete("/v1/admin/keys/{key_id}")
def revoke_key(key_id: str, record: dict[str, Any] = Depends(_auth)) -> dict[str, Any]:
    _require(record, "admin.keys")
    if str(record.get("id", "")) == key_id:
        raise HTTPException(409, "Cannot revoke the API key used for this request")
    return {"ok": True, "revoked": keys.revoke(key_id)}


@app.websocket("/v1/ws")
async def websocket_chat(websocket: WebSocket, api_key: str = Query(default="")) -> None:
    record = keys.verify(api_key)
    if record is None or not allows(record, "chat"):
        await websocket.close(code=4401)
        return
    await websocket.accept()
    try:
        while True:
            payload = await websocket.receive_json()
            req = ChatRequest.model_validate(payload)
            result = await asyncio.to_thread(_native_chat, req, record)
            await websocket.send_json(result)
    except WebSocketDisconnect:
        return
    except Exception as exc:
        await websocket.send_json({"ok": False, "error": str(exc)})
        await websocket.close(code=1011)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=HOST, port=PORT, log_level=os.getenv("AURORAFOX_API_LOG_LEVEL", "warning"))
