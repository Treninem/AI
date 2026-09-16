from __future__ import annotations

import shutil
from pathlib import Path

from api.account_store import AccountStore
from api.database import AuroraDatabase
from api.sync_store import SyncStore


def test_operational_snapshot_restores_account_session_and_personal_sync(tmp_path: Path):
    root = tmp_path / "api"
    accounts = AccountStore(root)
    registration = accounts.register("restore@example.com", "restore account password", "Restore")
    accounts.verify_email(registration["verification_token"])
    login = accounts.login("restore@example.com", "restore account password", "PC", "pytest")
    principal = accounts.verify_access(login["access_token"])
    assert principal is not None

    sync = SyncStore(root)
    sync.push(
        principal,
        [{"entity_type": "memory", "entity_id": "durable", "base_revision": 0, "payload": {"value": "before-update"}}],
    )
    live_path = root / "aurorafox.sqlite3"
    snapshot_path = tmp_path / "rollback" / "preupdate.sqlite3"
    snapshot = AuroraDatabase(live_path).create_snapshot(snapshot_path)
    assert snapshot["ok"] is True

    # Simulate a candidate release mutating durable auth/sync state before it
    # fails acceptance and the deployment script restores the root-only snapshot.
    assert accounts.revoke_device(str(principal["principal_id"]), str(principal["device_id"])) is True
    assert accounts.verify_access(login["access_token"]) is None

    live_path.unlink(missing_ok=True)
    Path(str(live_path) + "-wal").unlink(missing_ok=True)
    Path(str(live_path) + "-shm").unlink(missing_ok=True)
    shutil.copyfile(snapshot_path, live_path)

    restored_accounts = AccountStore(root)
    restored_principal = restored_accounts.verify_access(login["access_token"])
    assert restored_principal is not None
    restored_sync = SyncStore(root)
    changes = restored_sync.pull(restored_principal)["changes"]
    assert any(item["entity_id"] == "durable" and item["payload"] == {"value": "before-update"} for item in changes)
    assert AuroraDatabase(live_path).integrity_check()["ok"] is True
