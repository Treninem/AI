"""Owner-PC HTTPS queue consumer; the AgentCore socket stays on loopback.

Uses an explicitly provisioned learning.sync credential. Does not implement
multi-device account enrollment or copy other users' records to this runtime.
Delivery is at least once: an interrupted bridge call may be redelivered.
"""
from __future__ import annotations

import argparse
import hashlib
import logging
import os
from pathlib import Path
import sqlite3
import time
from urllib.parse import urlsplit

import requests

from api.file_lock import file_lock
from api.runtime_bridge import AuroraRuntimeBridge

LOG = logging.getLogger(__name__)


class LearningPullClient:
    def __init__(self, url: str, token: str, root: Path, bridge=None):
        parsed = urlsplit(url)
        if (parsed.scheme != "https" or not parsed.hostname or parsed.username
                or parsed.password or parsed.query or parsed.fragment
                or parsed.path not in ("", "/")):
            raise ValueError("AURORAFOX_SYNC_URL must be an HTTPS origin without credentials")
        if not token or any(c.isspace() for c in token):
            raise ValueError("A valid sync credential is required")
        self.url = url.rstrip("/")
        self.token = token
        self.root = root
        root.mkdir(parents=True, exist_ok=True)
        self.bridge = bridge or AuroraRuntimeBridge(host="127.0.0.1", timeout=20)
        self.namespace = hashlib.sha256((self.url + "\0" + token).encode()).hexdigest()

    def _request(self, method: str, path: str, payload=None) -> dict:
        response = requests.request(method, self.url + path, json=payload,
                                    headers={"Authorization": "Bearer " + self.token},
                                    timeout=(8, 30), allow_redirects=False)
        if response.status_code != 200:
            raise RuntimeError("Sync HTTP status %d" % response.status_code)
        result = response.json()
        if not isinstance(result, dict) or result.get("ok") is not True:
            raise RuntimeError("Invalid sync response")
        return result

    def run_once(self) -> dict:
        # One process per local profile. Persist receipts before remote ACK, so
        # a lost ACK does not repeat an already-confirmed local bridge call.
        with file_lock(self.root / "learning_pull.lock"):
            with sqlite3.connect(self.root / "learning_receipts.sqlite3") as db:
                db.execute("CREATE TABLE IF NOT EXISTS receipts (namespace TEXT, id TEXT, PRIMARY KEY(namespace,id))")
                response = self._request("GET", "/v1/learning/pending?limit=25")
                events = response.get("events")
                if not isinstance(events, list) or len(events) > 25:
                    raise ValueError("Invalid learning batch")
                acknowledged = []
                failed = 0
                for event in events:
                    event_id = str(event["id"])
                    delivered = db.execute("SELECT 1 FROM receipts WHERE namespace=? AND id=?",
                                           (self.namespace, event_id)).fetchone()
                    if not delivered:
                        payload = event["payload"]
                        if not isinstance(payload, dict):
                            raise ValueError("Invalid learning payload")
                        method = self.bridge.feedback if event.get("kind") == "feedback" else self.bridge.learn
                        try:
                            result = method(payload)
                        except (OSError, RuntimeError):
                            failed += 1
                            break
                        if not result.get("ok"):
                            failed += 1
                            continue
                        db.execute("INSERT OR IGNORE INTO receipts VALUES (?, ?)", (self.namespace, event_id))
                        db.commit()
                    acknowledged.append(event_id)
                if acknowledged:
                    self._request("POST", "/v1/learning/ack", {"event_ids": acknowledged})
                return {"ok": failed == 0, "synced": len(acknowledged), "failed": failed}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--watch", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    # Secret lives in an owner-readable file, not CLI args or repository.
    token = Path(os.environ["AURORAFOX_SYNC_TOKEN_FILE"]).read_text().strip()
    client = LearningPullClient(os.environ["AURORAFOX_SYNC_URL"], token,
                                Path(os.getenv("AURORAFOX_USER_DIR", str(Path.home() / ".aurorafox"))) / "sync")
    while True:
        try:
            result = client.run_once()
            LOG.info("sync ok=%s synced=%s failed=%s", result["ok"], result["synced"], result["failed"])
        except Exception as exc:
            # Do not print credential, payload or server response bodies.
            LOG.error("sync failed: %s", type(exc).__name__)
            result = {"ok": False}
        if not args.watch:
            return 0 if result["ok"] else 1
        time.sleep(120)


if __name__ == "__main__":
    raise SystemExit(main())
