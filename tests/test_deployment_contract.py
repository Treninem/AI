from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_server_metadata_is_versioned_and_backup_is_not_exposed_over_http():
    server = read("api/server.py")
    version = json.loads(read("project/version.json"))
    assert 'version=_canonical_version()' in server
    assert version["numeric"] == ".".join(
        str(version[key]) for key in ("major", "minor", "patch", "build")
    )
    assert version["version"] == f'V{version["numeric"]}'
    assert '"build_sha": os.getenv("AURORAFOX_BUILD_SHA", "local")' in server
    assert '"deployment": os.getenv("AURORAFOX_DEPLOYMENT", "local")' in server
    assert '"ollama_required": False' in server
    assert '"chat_available": True' in server
    assert '"local_core": local_core' in server
    assert '"database": {"backend": "sqlite", "schema_version": SCHEMA_VERSION}' in server
    assert '/v1/backups/latest' not in server


def test_server_readiness_is_database_integrity_backed():
    server = read("api/server.py")
    database = read("api/database.py")
    assert '@app.get("/ready")' in server
    assert "database.integrity_check()" in server
    assert 'status.pop("path", None)' in server
    assert 'status["backend"] = "sqlite"' in server
    assert "HTTPException(status_code=503, detail=payload)" in server
    assert 'database_status.get("ok", False)' in server
    assert 'database_status.get("journal_mode")' not in server or '"journal_mode"' in database
    assert 'PRAGMA integrity_check' in database
    assert 'PRAGMA foreign_key_check' in database
    assert 'PRAGMA journal_mode=WAL' in database


def test_windows_backup_sync_is_key_pinned_sftp_and_periodic():
    sync = read("deploy/windows/sync_server_backup.ps1")
    installer = read("deploy/windows/install_server_backup.ps1")
    assert "sftp" in sync.lower()
    assert "BatchMode=yes" in sync
    assert "IdentitiesOnly=yes" in sync
    assert "StrictHostKeyChecking=yes" in sync
    assert "UserKnownHostsFile" in sync
    assert "Get-FileHash" in sync
    assert "manifest.json" in sync
    assert "aurorafox.backup.v1" in sync
    assert "AURORAFOX_BACKUP_OFFLINE retry=scheduled" in sync
    assert "ServerHostKey" in installer
    assert "ssh-keygen" in installer
    assert "Copy-Item" in installer
    assert "New-TimeSpan -Minutes 5" in installer
    assert "-User $currentUser," not in installer
    assert "AuroraFox Server Backup" in installer


def test_reg_ru_deployment_updates_only_from_github_main_and_rolls_back():
    updater = read("deploy/reg_ru/update.sh")
    install = read("deploy/reg_ru/install.sh")
    requirements = read("api/requirements.txt")
    assert b"\r" not in (ROOT / "deploy/reg_ru/install.sh").read_bytes()
    assert b"\r" not in (ROOT / "deploy/reg_ru/update.sh").read_bytes()
    assert "https://github.com/Treninem/AI.git" in install
    assert "AURORAFOX_GITHUB_REF='main'" in install
    assert 'public_ip="${2:-${AURORAFOX_PUBLIC_IP:-}}"' in install
    assert "gpg --batch --yes --dearmor" in install
    assert "caddy-stable-archive-keyring.gpg" in install
    assert "caddy-stable-archive-keyring.asc" in install
    assert "pydantic==2.13.4" in requirements
    assert "api.aurorafox.ru" in install
    assert "ws.aurorafox.ru" in install
    assert "files.aurorafox.ru" in install
    assert "update.aurorafox.ru" in install
    assert "cloud.aurorafox.ru" in install
    assert "--retry-connrefused" in install
    assert "systemctl restart aurorafox-api.service caddy.service" in install
    assert "git merge-base --is-ancestor" in updater
    assert "rollback" in updater.lower()
    assert "systemctl restart aurorafox-api.service" in updater
    gates = (
        "tests/test_api_gateway.py",
        "tests/test_api_database.py",
        "tests/test_api_privacy_contract.py",
        "tests/test_api_runtime_resilience.py",
        "tests/test_core_candidate_queue.py",
        "tests/test_backup_service.py",
        "tests/test_deployment_contract.py",
        "tests/test_network_json_contract.py",
    )
    for gate in gates:
        assert gate in updater
        assert gate in install
    assert 'PYTHONPATH="${repository}"' in updater
    assert "PYTHONPATH=/opt/aurorafox/repository" in install
    assert "compileall -q /opt/aurorafox/repository/api" in install
    assert "PasswordAuthentication no" in install
    assert "systemctl enable --now ssh.service" in install
    assert 'AURORAFOX_SSH_PORT:-22022' in install
    assert "Port ${ssh_port}" in install
    assert "MaxStartups 50:30:100" in install
    assert "PerSourceMaxStartups 5" in install
    assert "ufw allow \"${ssh_port}/tcp\"" in install
    assert "fail2ban" in install
    assert "rm -f /etc/ssh/sshd_config.d/00-temp.conf" in install
    assert "ufw --force enable" in install
    assert "ForceCommand internal-sftp" in install
    assert "chown root:aurorafox-backup /etc/ssh/authorized_keys/aurorafox-backup" in install
    assert "chmod 0640 /etc/ssh/authorized_keys/aurorafox-backup" in install

    # Production switching is data-aware: the current SQLite state must be
    # healthy, a verifiable snapshot must exist before checkout, and the new
    # process must pass readiness plus direct integrity before acceptance.
    assert "python -m api.database --path" in updater
    assert "python -m api.database --path" in install
    assert "systemctl start aurorafox-backup.service" in updater
    assert "latest.zip" in updater and "latest.sha256" in updater
    assert "sha256sum -c" in updater
    assert "preupdate_backup_sha=" in updater
    assert "http://127.0.0.1:8768/ready" in updater
    assert 'data["database"]["ok"] is True' in updater
    assert 'data["database"]["journal_mode"] == "wal"' in updater
    assert updater.index("systemctl start aurorafox-backup.service") < updater.index('git checkout --detach "${candidate}"')
    assert updater.rindex("python -m api.database --path") > updater.index("systemctl restart aurorafox-api.service")
    assert updater.index("http://127.0.0.1:8768/ready") > updater.index("systemctl restart aurorafox-api.service")
    assert "sha256sum -c latest.sha256" in install
    assert "db=sqlite-wal" in install


def test_api_provider_independence_is_packaged_and_deployed():
    build = read("build/build_windows.ps1")
    local_core = read("api/local_core_client.py")
    bridge = read("api/runtime_bridge.py")
    ollama = read("api/ollama_client.py")
    updater = read("deploy/reg_ru/update.sh")
    installer = read("deploy/reg_ru/install.sh")
    api_ci = read(".github/workflows/api-ci.yml")
    voice_ci = read(".github/workflows/voice-ci.yml")
    assert "Get-ChildItem -LiteralPath $apiSource -File" in build
    assert "class AuroraLocalCoreClient" in local_core
    assert "class AuroraKnowledgeFallback" in local_core
    assert "AuroraLocalCoreClient" in bridge
    assert "AuroraKnowledgeFallback" in bridge
    assert "AuroraLocalCoreClient" in ollama
    assert "AuroraKnowledgeFallback" in ollama
    assert "tests/test_api_runtime_resilience.py" in updater
    assert "tests/test_api_runtime_resilience.py" in installer
    assert "tests/test_api_runtime_resilience.py" in api_ci
    assert "tests/test_api_runtime_resilience.py" in voice_ci
    assert 'PYTHONPATH="$PWD"' in voice_ci
