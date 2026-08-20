from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_server_metadata_is_versioned_and_backup_is_not_exposed_over_http():
    server = read("api/server.py")
    version = read("project/version.json")
    assert 'version=_canonical_version()' in server
    assert '"numeric": "1.2.0.0"' in version
    assert '"build_sha": os.getenv("AURORAFOX_BUILD_SHA", "local")' in server
    assert '"deployment": os.getenv("AURORAFOX_DEPLOYMENT", "local")' in server
    assert '/v1/backups/latest' not in server


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
    assert "https://github.com/Treninem/AI.git" in install
    assert "AURORAFOX_GITHUB_REF='main'" in install
    assert "gpg --batch --yes --dearmor" in install
    assert "caddy-stable-archive-keyring.gpg" in install
    assert "caddy-stable-archive-keyring.asc" in install
    assert "pydantic==2.13.4" in requirements
    assert "api.aurorafox.ru" in install
    assert "ws.aurorafox.ru" in install
    assert "files.aurorafox.ru" in install
    assert "update.aurorafox.ru" in install
    assert "--retry-connrefused" in install
    assert "systemctl restart aurorafox-api.service caddy.service" in install
    assert "git merge-base --is-ancestor" in updater
    assert "rollback" in updater.lower()
    assert "systemctl restart aurorafox-api.service" in updater
    assert "tests/test_backup_service.py" in updater
    assert "PasswordAuthentication no" in install
    assert "ufw --force enable" in install
    assert "ForceCommand internal-sftp" in install

