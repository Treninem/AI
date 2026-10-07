"""Actual service routes with isolated GUI-shaped workers; no desktop operation.

Only the test launcher imports this module. Production has no fixture switch.
"""
import hashlib
import os
from pathlib import Path
import time

from computer import computer_service as service


def gui_shaped_worker(kind, payload, _queue):
    identity = str(payload["__execution_id"])
    digest = hashlib.sha256(identity.encode()).hexdigest()
    root = Path(os.environ["AURORAFOX_SANDBOX_ROOT"])
    (root / ("gui-started-" + digest)).write_text(kind)
    while True:
        (root / ("gui-heartbeat-" + digest)).write_text(str(time.time_ns()))
        time.sleep(0.02)


# Exercise actual authorization, ownership, worker bootstrap and HTTP handlers.
# This explicitly does not provide physical Windows screenshot/input evidence.
service.IS_WINDOWS = True
service._worker_entry = gui_shaped_worker
app = service.app
