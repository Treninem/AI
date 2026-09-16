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


def test_server_readiness_is_database_integrity_backed_and_privacy_safe():
    server = read("api/server.py")
    database = read("api/database.py")
    assert '@app.get("/ready")' in server
    assert "database.integrity_check()" in server
    assert "HTTPException(status_code=503, detail=payload)" in server
    assert 'database_status.get("ok", False)' in server
    assert 'PRAGMA integrity_check' in database
    assert 'PRAGMA foreign_key_check' in database
    assert 'PRAGMA journal_mode=WAL' in database

    database_projection = server.split("def _public_database_status()", 1)[1].split("@app.get", 1)[0]
    component_projection = server.split("def _public_component_status", 1)[1].split(
        "def _public_database_status", 1
    )[0]
    assert '"backend": "sqlite"' in database_projection
    assert '"schema_version"' in database_projection
    assert '"journal_mode"' in database_projection
    assert '"integrity"' in database_projection
    assert '"foreign_key_errors"' in database_projection
    assert '"path"' not in database_projection
    assert '"counts"' not in database_projection
    assert '"error"' not in component_projection
    assert '"value"' not in component_projection
    assert '"root"' not in component_projection


def test_server_rate_limit_is_thread_safe_and_covers_websocket_messages():
    server = read("api/server.py")
    limiter = server.split("class RateLimiter", 1)[1].split("rate_limiter =", 1)[0]
    websocket = server.split('@app.websocket("/v1/ws")', 1)[1]
    assert "import threading" in server
    assert "self._lock = threading.Lock()" in limiter
    assert "with self._lock:" in limiter
    assert "rate_limiter.check(key_id)" in websocket
    assert "code=4429" in websocket


def test_server_has_pre_parser_body_limit_and_secure_account_mail_boundary():
    server = read("api/server.py")
    limits = read("api/request_limits.py")
    mailer = read("api/account_mailer.py")
    assert "RequestBodyLimitMiddleware" in server
    assert 'AURORAFOX_API_MAX_BODY_BYTES' in server
    assert 'status": 413' in limits
    assert 'content-length' in limits
    assert 'received > self.max_bytes' in limits
    assert 'scope.get("type") != "http"' in limits
    assert "AccountMailConfig.from_env()" in server
    assert "AURORAFOX_SMTP_PASSWORD" in mailer
    assert 'self.config.security in {"starttls", "ssl"}' in mailer
    assert 'client.starttls(context=context)' in mailer
    assert '"plain"' not in mailer.split("def send_token", 1)[1]
    assert 'AURORAFOX_ACCOUNT_EXPOSE_DEV_TOKENS' in server


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
    assert "auth.aurorafox.ru" in install
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
        "tests/test_api_accounts_sync.py",
        "tests/test_api_account_network.py",
        "tests/test_api_account_restore.py",
        "tests/test_api_account_mailer.py",
        "tests/test_api_server_hardening.py",
        "tests/test_api_request_limits.py",
        "tests/test_api_schema_migrations.py",
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

    # HTTP/body and account-mail production settings are explicit. SMTP secrets
    # live in their own root-only file, are not overwritten on reinstall, and are
    # only read by the API service. The application stays healthy without SMTP,
    # while production account creation fails closed until the owner configures it.
    assert "AURORAFOX_API_MAX_BODY_BYTES=25165824" in install
    assert "if [[ ! -e /etc/aurorafox/account-mail.env ]]" in install
    assert "chmod 0600 /etc/aurorafox/account-mail.env" in install
    assert "AURORAFOX_SMTP_PASSWORD=" in install
    assert "AURORAFOX_SMTP_SECURITY=starttls" in install
    assert "EnvironmentFile=-/etc/aurorafox/account-mail.env" in install
    assert "account_public_host='auth.aurorafox.ru'" in install

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

    # Install and update must agree on the same restricted SFTP export root.
    canonical_backup_root = "/srv/aurorafox-backup/exports"
    assert canonical_backup_root in install
    assert f"{canonical_backup_root}/latest.zip" in updater
    assert f"{canonical_backup_root}/latest.sha256" in updater
    assert "/srv/aurorafox-sftp/" not in updater

    # The sanitized owner backup cannot be the exact production rollback source:
    # the full DB snapshot stays root-only, is made before candidate checkout,
    # and rollback restores it together with the previous updater/code revision.
    rollback_root = "/var/lib/aurorafox-rollback"
    assert f"readonly rollback_dir='{rollback_root}'" in updater
    assert 'readonly rollback_database="${rollback_dir}/preupdate.sqlite3"' in updater
    assert '--snapshot-to "${rollback_database}"' in updater
    assert 'install -d -o root -g root -m 0700 "${rollback_dir}"' in updater
    assert 'chmod 0600 "${rollback_database}"' in updater
    assert updater.index('--snapshot-to "${rollback_database}"') < updater.index('git checkout --detach "${candidate}"')
    assert "systemctl stop aurorafox-api.service" in updater
    assert 'install -o aurorafox -g aurorafox -m 0600 "${rollback_database}" "${database_path}"' in updater
    assert 'rm -f "${database_path}-wal" "${database_path}-shm"' in updater
    assert rollback_root not in canonical_backup_root

    # /usr/local/sbin is the timer/service entry point. Candidate updater fixes
    # must reach it on success, while rollback reinstalls the previous revision.
    assert "readonly installed_updater='/usr/local/sbin/aurorafox-update'" in updater
    updater_install = 'install -m 0755 deploy/reg_ru/update.sh "${installed_updater}"'
    assert updater.count(updater_install) >= 2
    assert updater.rindex(updater_install) > updater.index('git checkout --detach "${candidate}"')


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
