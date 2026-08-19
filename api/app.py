from __future__ import annotations

from api.learning_routes import build_learning_router
from api.learning_sync import LearningSynchronizer
from api.server import API_ROOT, HOST, PORT, _auth, _require, app, bridge

learning = LearningSynchronizer(API_ROOT, bridge)
app.include_router(build_learning_router(_auth, _require, learning))


if __name__ == "__main__":
    import os
    import uvicorn

    uvicorn.run(
        app,
        host=HOST,
        port=PORT,
        log_level=os.getenv("AURORAFOX_API_LOG_LEVEL", "warning"),
    )
