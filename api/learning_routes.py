from __future__ import annotations

from typing import Any, Callable

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from api.learning_sync import LearningSynchronizer


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
    learning: LearningSynchronizer,
) -> APIRouter:
    router = APIRouter()

    @router.post("/v1/feedback")
    def feedback(req: FeedbackRequest, record: dict[str, Any] = Depends(auth_dependency)) -> dict[str, Any]:
        require_scope(record, "feedback")
        payload = req.model_dump()
        payload["api_key_id"] = str(record.get("id", ""))
        result = learning.feedback(payload, True)
        return {
            "ok": True,
            "queued": not bool(result.get("synced", False)),
            **result,
            "learning": learning.status(),
        }

    @router.post("/v1/learn")
    def learn(req: LearningRequest, record: dict[str, Any] = Depends(auth_dependency)) -> dict[str, Any]:
        require_scope(record, "memory.write")
        payload = req.model_dump()
        payload["api_key_id"] = str(record.get("id", ""))
        result = learning.record(req.kind, payload, True)
        return {
            "ok": True,
            "queued": not bool(result.get("synced", False)),
            **result,
            "learning": learning.status(),
        }

    @router.post("/v1/learning/sync")
    def sync_learning(record: dict[str, Any] = Depends(auth_dependency)) -> dict[str, Any]:
        require_scope(record, "memory.write")
        return learning.flush(250)

    @router.get("/v1/learning/status")
    def learning_status(record: dict[str, Any] = Depends(auth_dependency)) -> dict[str, Any]:
        require_scope(record, "memory.read")
        return learning.status()

    return router
