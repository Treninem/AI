from __future__ import annotations

import os

import uvicorn

import file_service
from extended_formats import extend_analyze

# Keep the proven File Intelligence service and extend only the formats that
# were previously missing/placeholder. All existing endpoints/cache/limits
# stay owned by file_service.py.
file_service._analyze = extend_analyze(file_service._analyze)


if __name__ == "__main__":
    uvicorn.run(
        file_service.app,
        host=os.getenv("AURORAFOX_FILE_HOST", file_service.HOST),
        port=int(os.getenv("AURORAFOX_FILE_PORT", str(file_service.PORT))),
        log_level="warning",
    )
