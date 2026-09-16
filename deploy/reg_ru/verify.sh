#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY='/opt/aurorafox/repository'
readonly VENV='/opt/aurorafox/venv'
readonly API_ENV='/etc/aurorafox/aurorafox.env'
readonly MAIL_ENV='/etc/aurorafox/account-mail.env'
readonly BUILD_ENV='/etc/aurorafox/build.env'
readonly API_DATABASE='/var/lib/aurorafox/api/aurorafox.sqlite3'
readonly BACKUP_ROOT='/srv/aurorafox-backup/exports'
readonly EXPECTED_ORIGIN='https://github.com/Treninem/AI.git'

fail() {
  printf 'AURORAFOX_VERIFY_FAIL %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing_file=$1"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing_command=$1"
}

if [[ "${EUID}" -ne 0 ]]; then
  fail 'run_as_root_required'
fi

for command in curl git python3 sha256sum sshd systemctl; do
  require_cmd "${command}"
done
for path in \
  "${API_ENV}" \
  "${MAIL_ENV}" \
  "${BUILD_ENV}" \
  "${API_DATABASE}" \
  "${REPOSITORY}/api/server.py"; do
  require_file "${path}"
done
[[ -x "${VENV}/bin/python" ]] || fail "missing_python=${VENV}/bin/python"

for unit in aurorafox-api.service caddy.service ssh.service fail2ban.service; do
  systemctl is-active --quiet "${unit}" || fail "inactive_unit=${unit}"
done
for timer in aurorafox-update.timer aurorafox-backup.timer; do
  systemctl is-enabled --quiet "${timer}" || fail "disabled_timer=${timer}"
  systemctl is-active --quiet "${timer}" || fail "inactive_timer=${timer}"
done
sshd -t || fail 'sshd_config_invalid'

actual_origin="$(git -C "${REPOSITORY}" remote get-url origin)"
[[ "${actual_origin}" == "${EXPECTED_ORIGIN}" ]] || fail "origin_mismatch=${actual_origin}"
actual_sha="$(git -C "${REPOSITORY}" rev-parse HEAD)"
[[ -n "${actual_sha}" ]] || fail 'repository_head_missing'

[[ -x /usr/local/sbin/aurorafox-update ]] || fail 'installed_updater_missing'
cmp -s "${REPOSITORY}/deploy/reg_ru/update.sh" /usr/local/sbin/aurorafox-update || \
  fail 'installed_updater_not_current'

# Validate the exact environment of the running systemd service instead of
# shell-sourcing EnvironmentFile values. Shell sourcing can reinterpret special
# characters in SMTP passwords; /proc/<pid>/environ gives the already parsed
# runtime values and they never leave this Python process except for the public
# non-secret URL printed on stdout.
api_pid="$(systemctl show --property=MainPID --value aurorafox-api.service)"
[[ "${api_pid}" =~ ^[1-9][0-9]*$ ]] || fail 'api_main_pid_invalid'
[[ -r "/proc/${api_pid}/environ" ]] || fail 'api_runtime_environment_unreadable'
public_url="$(PYTHONPATH="${REPOSITORY}" "${VENV}/bin/python" - "${api_pid}" "${actual_sha}" "${EXPECTED_ORIGIN}" <<'PY'
import os
import sys
from pathlib import Path
from urllib.parse import urlsplit

from api.account_mailer import AccountMailConfig

pid, expected_sha, expected_origin = sys.argv[1:4]
raw = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
runtime: dict[str, str] = {}
for item in raw:
    if not item or b"=" not in item:
        continue
    key, value = item.split(b"=", 1)
    name = key.decode("utf-8", "surrogateescape")
    if name.startswith("AURORAFOX_"):
        runtime[name] = value.decode("utf-8", "surrogateescape")
for name, value in runtime.items():
    os.environ[name] = value

assert runtime.get("AURORAFOX_BUILD_SHA") == expected_sha, "running build SHA does not match repository HEAD"
assert runtime.get("AURORAFOX_GITHUB_REPO") == expected_origin, "runtime GitHub origin is not canonical"
assert runtime.get("AURORAFOX_GITHUB_REF") == "main", "runtime GitHub ref is not main"
assert runtime.get("AURORAFOX_DEPLOYMENT") == "reg-ru", "runtime deployment marker is not reg-ru"
config = AccountMailConfig.from_env()
assert config.configured, "account mail transport is not production-configured"
assert config.public_url_is_secure, "account action URL is not secure"
public_url = runtime.get("AURORAFOX_PUBLIC_URL", "").rstrip("/")
assert public_url.startswith("https://"), "public API URL must be HTTPS"

# A valid TLS URL is not sufficient for one-time account credentials: an owner
# typo must never redirect verification/reset links to an unrelated HTTPS host.
# Default sslip.io deployments use the same public origin for API + account
# actions. The canonical aurorafox.ru deployment intentionally separates them
# into api.aurorafox.ru and auth.aurorafox.ru.
api_url = urlsplit(public_url)
action_url = urlsplit(config.public_url.rstrip("/"))
assert api_url.scheme == "https" and api_url.hostname, "public API URL is invalid"
assert api_url.path in {"", "/"} and not api_url.query and not api_url.fragment, "public API URL must be an origin"
expected_action_host = "auth.aurorafox.ru" if api_url.hostname == "api.aurorafox.ru" else api_url.hostname
assert action_url.scheme == "https", "account action URL must use HTTPS"
assert action_url.hostname == expected_action_host, "account action URL host is not trusted for this deployment"
assert action_url.port in {None, 443}, "account action URL must use the default HTTPS port"
assert action_url.path in {"", "/"} and not action_url.query and not action_url.fragment, "account action URL must be an origin"
print(public_url)
PY
)" || fail 'runtime_environment_validation_failed'
[[ "${public_url}" == https://* ]] || fail 'public_url_must_be_https'

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

curl --fail --silent --show-error --max-time 10 \
  http://127.0.0.1:8768/health -o "${work}/health.json"
curl --fail --silent --show-error --max-time 10 \
  http://127.0.0.1:8768/ready -o "${work}/ready.json"

"${VENV}/bin/python" - "${work}/health.json" "${work}/ready.json" "${actual_sha}" <<'PY'
import json
import sys
from pathlib import Path

health = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
ready = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
expected_sha = sys.argv[3]
assert health.get("ok") is True, health
assert health.get("ollama_required") is False, health
assert ready.get("ok") is True, ready
assert ready.get("build_sha") == expected_sha, ready
status = ready.get("database") or {}
assert status.get("ok") is True, status
assert status.get("backend") == "sqlite", status
assert str(status.get("journal_mode", "")).lower() == "wal", status
assert status.get("integrity") == "ok", status
assert int(status.get("foreign_key_errors", -1)) == 0, status
PY

# Direct read-only SQLite verification is independent of the HTTP process. It
# catches a case where the service answers but the durable database itself is not
# structurally healthy.
"${VENV}/bin/python" - "${API_DATABASE}" <<'PY'
import sqlite3
import sys
from pathlib import Path

db = Path(sys.argv[1]).resolve()
uri = db.as_uri() + "?mode=ro"
connection = sqlite3.connect(uri, uri=True, timeout=30)
try:
    integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
    foreign = connection.execute("PRAGMA foreign_key_check").fetchall()
    journal = connection.execute("PRAGMA journal_mode").fetchone()[0]
    version = int(connection.execute("PRAGMA user_version").fetchone()[0])
finally:
    connection.close()
assert integrity == "ok", integrity
assert foreign == [], foreign
assert str(journal).lower() == "wal", journal
assert version > 0, version
PY

require_file "${BACKUP_ROOT}/latest.zip"
require_file "${BACKUP_ROOT}/latest.sha256"
(
  cd "${BACKUP_ROOT}"
  sha256sum -c latest.sha256 >/dev/null
) || fail 'backup_checksum_invalid'

curl --fail --silent --show-error --max-time 15 \
  "${public_url}/ready" -o "${work}/public-ready.json"
curl --fail --silent --show-error --max-time 15 -D "${work}/headers.txt" \
  "${public_url}/health" -o "${work}/public-health.json"

"${VENV}/bin/python" - "${work}/public-ready.json" "${work}/public-health.json" "${actual_sha}" <<'PY'
import json
import sys
from pathlib import Path

ready = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
health = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
expected_sha = sys.argv[3]
assert ready.get("ok") is True, ready
assert ready.get("build_sha") == expected_sha, ready
assert health.get("ok") is True, health
assert health.get("build_sha") == expected_sha, health
assert health.get("ollama_required") is False, health
PY

grep -qi '^strict-transport-security:' "${work}/headers.txt" || fail 'hsts_header_missing'
grep -qi '^x-content-type-options:[[:space:]]*nosniff' "${work}/headers.txt" || fail 'nosniff_header_missing'
grep -qi '^x-frame-options:[[:space:]]*DENY' "${work}/headers.txt" || fail 'frame_deny_header_missing'
grep -qi '^cache-control:[[:space:]]*no-store' "${work}/headers.txt" || fail 'no_store_header_missing'

printf 'AURORAFOX_REG_RU_VERIFY_OK sha=%s public_url=%s db=sqlite-wal backup=verified mail=secure\n' \
  "${actual_sha}" "${public_url}"
