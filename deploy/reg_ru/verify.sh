#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY='/opt/aurorafox/repository'
readonly VENV='/opt/aurorafox/venv'
readonly API_ENV='/etc/aurorafox/aurorafox.env'
readonly MAIL_ENV='/etc/aurorafox/account-mail.env'
readonly BUILD_ENV='/etc/aurorafox/build.env'
readonly API_DATABASE='/var/lib/aurorafox/api/aurorafox.sqlite3'
readonly BACKUP_ROOT='/srv/aurorafox-backup/exports'

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
for path in "${API_ENV}" "${BUILD_ENV}" "${API_DATABASE}" "${REPOSITORY}/api/server.py"; do
  require_file "${path}"
done
[[ -x "${VENV}/bin/python" ]] || fail "missing_python=${VENV}/bin/python"

# Export the same runtime configuration systemd consumes. Secrets are never
# printed; this is used only to validate that production mail/link configuration
# is complete and safe.
set -a
# shellcheck disable=SC1090
source "${API_ENV}"
if [[ -f "${MAIL_ENV}" ]]; then
  # shellcheck disable=SC1090
  source "${MAIL_ENV}"
fi
# shellcheck disable=SC1090
source "${BUILD_ENV}"
set +a

for unit in aurorafox-api.service caddy.service ssh.service fail2ban.service; do
  systemctl is-active --quiet "${unit}" || fail "inactive_unit=${unit}"
done
for timer in aurorafox-update.timer aurorafox-backup.timer; do
  systemctl is-enabled --quiet "${timer}" || fail "disabled_timer=${timer}"
  systemctl is-active --quiet "${timer}" || fail "inactive_timer=${timer}"
done
sshd -t || fail 'sshd_config_invalid'

actual_origin="$(git -C "${REPOSITORY}" remote get-url origin)"
[[ "${actual_origin}" == "${AURORAFOX_GITHUB_REPO:-}" ]] || fail "origin_mismatch=${actual_origin}"
actual_sha="$(git -C "${REPOSITORY}" rev-parse HEAD)"
[[ -n "${AURORAFOX_BUILD_SHA:-}" ]] || fail 'build_sha_missing'
[[ "${actual_sha}" == "${AURORAFOX_BUILD_SHA}" ]] || fail "build_sha_mismatch=${actual_sha}"

[[ -x /usr/local/sbin/aurorafox-update ]] || fail 'installed_updater_missing'
cmp -s "${REPOSITORY}/deploy/reg_ru/update.sh" /usr/local/sbin/aurorafox-update || \
  fail 'installed_updater_not_current'

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

curl --fail --silent --show-error --max-time 10 \
  http://127.0.0.1:8768/health -o "${work}/health.json"
curl --fail --silent --show-error --max-time 10 \
  http://127.0.0.1:8768/ready -o "${work}/ready.json"

"${VENV}/bin/python" - "${work}/health.json" "${work}/ready.json" "${AURORAFOX_BUILD_SHA}" <<'PY'
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

# Registration/password recovery is production-ready only when the SMTP
# transport and public one-time-token URL pass the same secure config contract as
# the API process. No password/token/credential value is emitted here.
PYTHONPATH="${REPOSITORY}" "${VENV}/bin/python" - <<'PY'
from api.account_mailer import AccountMailConfig
config = AccountMailConfig.from_env()
assert config.configured, "account mail transport is not production-configured"
assert config.public_url_is_secure, "account action URL is not secure"
PY

require_file "${BACKUP_ROOT}/latest.zip"
require_file "${BACKUP_ROOT}/latest.sha256"
(
  cd "${BACKUP_ROOT}"
  sha256sum -c latest.sha256 >/dev/null
) || fail 'backup_checksum_invalid'

public_url="${AURORAFOX_PUBLIC_URL:-}"
[[ "${public_url}" == https://* ]] || fail 'public_url_must_be_https'
public_url="${public_url%/}"
curl --fail --silent --show-error --max-time 15 \
  "${public_url}/ready" -o "${work}/public-ready.json"
curl --fail --silent --show-error --max-time 15 -D "${work}/headers.txt" \
  "${public_url}/health" -o "${work}/public-health.json"

"${VENV}/bin/python" - "${work}/public-ready.json" "${work}/public-health.json" "${AURORAFOX_BUILD_SHA}" <<'PY'
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
