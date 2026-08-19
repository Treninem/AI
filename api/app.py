from __future__ import annotations

from api.learning_queue import LearningQueue
from api.learning_routes import build_learning_router
from api.server import API_ROOT, HOST, PORT, _auth, _require, app, bridge

learning_queue = LearningQueue(API_ROOT / "learning_queue.json")
app.include_router(build_learning_router(_auth, _require, learning_queue, bridge))


if __name__ == "__main__":
    import os
    import uvicorn

    uvicorn.run(
        app,
        host=HOST,
        port=PORT,
        log_level=os.getenv("AURORAFOX_API_LOG_LEVEL", "warning"),
    )
