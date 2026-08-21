from __future__ import annotations

import logging
import os
from pathlib import Path

from api.learning_sync import LearningSynchronizer
from api.runtime_bridge import AuroraRuntimeBridge

LOG = logging.getLogger("aurorafox.learning_daemon")


def main() -> int:
    logging.basicConfig(
        level=os.getenv("AURORAFOX_LEARNING_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    root = Path(os.getenv("AURORAFOX_USER_DIR", "/var/lib/aurorafox")).resolve() / "api"
    bridge = AuroraRuntimeBridge(
        host=os.getenv("AURORAFOX_BRIDGE_HOST", "127.0.0.1"),
        port=int(os.getenv("AURORAFOX_BRIDGE_PORT", "8770")),
        timeout=float(os.getenv("AURORAFOX_BRIDGE_TIMEOUT", "20")),
    )
    sync = LearningSynchronizer(root, bridge)
    batch_size = max(1, min(1000, int(os.getenv("AURORAFOX_LEARNING_BATCH", "250"))))
    result = sync.flush(batch_size)
    LOG.info(
        "learning sync: ok=%s attempted=%s synced=%s failed=%s pending=%s",
        result.get("ok"), result.get("attempted", 0), result.get("synced", 0),
        result.get("failed", 0), result.get("pending", 0),
    )
    # A disconnected PC/runtime is a normal state for the persistent queue.
    # Keep the timer green so the next run retries automatically.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
