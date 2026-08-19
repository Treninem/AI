from __future__ import annotations

from typing import Any, Callable

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from api.learning_queue import LearningQueue
from api.runtime_bridge import AuroraRuntimeBridge


class FeedbackRequest(BaseModel):
    conversation_id: str = Field(min_length=1, max_length=256)
    source: str = Field(default="api", max_length=64)
    user_id: str = Field(default="", max_length=256)
    message: str = Field(default="", max_length=100000)
    answer: str = Field(default="", max_length=100000)
    score: float = Field(ge=-1.0, le=1.0)
    corrected_answer: str = Field(default="", max_length=100000)
    note: str = Field(default="", max_length=12000)
    metadata: dict[str, Any] = Field(default_factory=dict)


class LearningRequest(BaseModel):
    source: str = Field(default="api", max_length=64)
    kind: str = Field(default="external_knowledge", max_length=128)
    content: str = Field(min_length=1, max_length=200000)
    importance: float = Field(default=0.65, ge=0.0, le=1.0)
    confidence: float = Field(default=0.80, ge=0.0, le=1.0)
    metadata: dict[str, Any] = Field(default_factory=dict)


def build_learning_router(
    auth_dependency: Callable[..., dict[str, Any]],
    require_scope: Callable[[dict[str, Any], str], None],
    queue: LearningQueue,
    bridge: AuroraRuntimeBridge,
) -> APIRouter:
    router = APIRouter()

    def deliver_event(event: dict[str, Any]) -> dict[str, Any]:
        kind = str(event.get("kind", "learn"))
        payload = event.get("payload", {})
        if kind == "feedback":
            return bridge.feedback(payload)
        return bridge.learn(payload)

    def sync_one(event: dict[str, Any]) -> dict[str, Any]:
        try:
            result = deliver_event(event)
            if result.get("ok", False):
                queue.mark_synced(str(event["id"]))
            else:
                queue.mark_failed(str(event["id"]), str(result.get("error", "bridge rejected event")))
            return result
        except Exception as exc:
            queue.mark_failed(str(event["id"]), str(exc))
            return {"ok": False, "queued": True, "error": str(exc)}

    @router.post("/v1/feedback")
    def feedback(req: FeedbackRequest, record: dict[str, Any] = Depends(auth_dependency)) -> dict[str, Any]:
        require_scope(record, "feedback")
        payload = req.model_dump()
        payload["api_key_id"] = str(record.get("id", ""))
        event = queue.append("feedback", payload)
        result = sync_one(event)
        return {
            "ok": True,
            "queued": not result.get("ok", False),
            "event_id": event["id"],
            "bridge_result": result if result.get("ok", False) else None,
            "learning_queue": queue.stats(),
        }

    @router.post("/v1/learn")
    def learn(req: LearningRequest, record: dict[str, Any] = Depends(auth_dependency)) -> dict[str, Any]:
        require_scope(record, "memory.write")
        payload = req.model_dump()
        payload["api_key_id"] = str(record.get("id", ""))
        event = queue.append("learn", payload)
        result = sync_one(event)
        return {
            "ok": True,
            "queued": not result.get("ok", False),
            "event_id": event["id"],
            "bridge_result": result if result.get("ok", False) else None,
            "learning_queue": queue.stats(),
        }

    @router.post("/v1/learning/sync")
    def sync_learning(record: dict[str, Any] = Depends(auth_dependency)) -> dict[str, Any]:
        require_scope(record, "memory.write")
        return queue.flush(deliver_event, 250)

    @router.get("/v1/learning/status")
    def learning_status(record: dict[str, Any] = Depends(auth_dependency)) -> dict[str, Any]:
        require_scope(record, "memory.read")
        return {"ok": True, **queue.stats()}

    return router
