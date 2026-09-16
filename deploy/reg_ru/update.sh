#!/usr/bin/env bash
set -Eeuo pipefail

readonly repository='/opt/aurorafox/repository'
readonly environment_file='/etc/aurorafox/aurorafox.env'
readonly build_environment='/etc/aurorafox/build.env'
readonly installed_updater='/usr/local/sbin/aurorafox-update'
readonly database_path='/var/lib/aurorafox/api/aurorafox.sqlite3'
readonly rollback_dir='/var/lib/aurorafox-rollback'
readonly rollback_database="${rollback_dir}/preupdate.sqlite3"
readonly backup_archive='/srv/aurorafox-backup/exports/latest.zip'
readonly backup_hash='/srv/aurorafox-backup/exports/latest.sha256'

if [[ "${EUID}" -ne 0 ]]; then
  echo 'AuroraFox updater must run as root.' >&2
  exit 2
fi

source "${environment_file}"
readonly expected_origin="${AURORAFOX_GITHUB_REPO:-https://github.com/Treninem/AI.git}"
readonly deploy_ref="${AURORAFOX_GITHUB_REF:-main}"
cd "${repository}"

actual_origin="$(git remote get-url origin)"
if [[ "${actual_origin}" != "${expected_origin}" ]]; then
  echo "Refusing update from unexpected Git origin: ${actual_origin}" >&2
  exit 3
fi

git fetch --no-tags --prune origin "refs/heads/${deploy_ref}:refs/remotes/origin/${deploy_ref}"
previous="$(git rev-parse HEAD)"
candidate="$(git rev-parse "origin/${deploy_ref}^{commit}")"
if [[ "${previous}" == "${candidate}" ]]; then
  echo "AURORAFOX_UPDATE_CURRENT sha=${candidate}"
  exit 0
fi
if ! git merge-base --is-ancestor "${previous}" "${candidate}"; then
  echo 'Refusing non-fast-forward production update.' >&2
  exit 4
fi

# Two different snapshots serve different trust boundaries:
# 1) root-only rollback_database is a complete operational snapshot, including
#    credential hashes, and never leaves this server;
# 2) the SFTP owner backup is exportable and therefore sanitized by BackupService.
install -d -o root -g root -m 0700 "${rollback_dir}"
rm -f "${rollback_database}"
database_existed='no'
if [[ -f "${database_path}" ]]; then
  database_existed='yes'
  PYTHONPATH="${repository}" /opt/aurorafox/venv/bin/python -m api.database \
    --path "${database_path}" --snapshot-to "${rollback_database}"
  chmod 0600 "${rollback_database}"
  test -s "${rollback_database}"
fi
readonly database_existed

systemctl start aurorafox-backup.service
systemctl is-failed --quiet aurorafox-backup.service && exit 5 || true
test -s "${backup_archive}"
test -s "${backup_hash}"
(
  cd "$(dirname "${backup_archive}")"
  sha256sum -c "$(basename "${backup_hash}")"
)
readonly preupdate_backup_sha="$(sha256sum "${backup_archive}" | awk '{print $1}')"

rollback() {
  status=$?
  trap - ERR
  echo "AuroraFox update failed; rollback code, updater and database to ${previous}." >&2
  systemctl stop aurorafox-api.service || true
  git checkout --detach "${previous}" || true
  if [[ -f deploy/reg_ru/update.sh ]]; then
    install -m 0755 deploy/reg_ru/update.sh "${installed_updater}" || true
  fi
  /opt/aurorafox/venv/bin/python -m pip install --disable-pip-version-check -r api/requirements.txt >/dev/null || true

  if [[ "${database_existed}" == 'yes' && -s "${rollback_database}" ]]; then
    install -o aurorafox -g aurorafox -m 0600 "${rollback_database}" "${database_path}" || true
    rm -f "${database_path}-wal" "${database_path}-shm"
  elif [[ "${database_existed}" == 'no' ]]; then
    rm -f "${database_path}" "${database_path}-wal" "${database_path}-shm"
  fi

  printf 'AURORAFOX_BUILD_SHA=%s\n' "${previous}" > "${build_environment}.tmp"
  mv "${build_environment}.tmp" "${build_environment}"
  systemctl restart aurorafox-api.service || true
  exit "${status}"
}
trap rollback ERR

git checkout --detach "${candidate}"
/opt/aurorafox/venv/bin/python -m pip install --disable-pip-version-check \
  -r api/requirements.txt pytest==8.4.1 httpx==0.28.1
/opt/aurorafox/venv/bin/python -m compileall -q api
PYTHONPATH="${repository}" /opt/aurorafox/venv/bin/python -m pytest -q \
  tests/test_api_gateway.py \
  tests/test_api_database.py \
  tests/test_api_accounts_sync.py \
  tests/test_api_account_network.py \
  tests/test_api_account_restore.py \
  tests/test_api_account_mailer.py \
  tests/test_api_server_hardening.py \
  tests/test_api_request_limits.py \
  tests/test_api_schema_migrations.py \
  tests/test_api_privacy_contract.py \
  tests/test_api_runtime_resilience.py \
  tests/test_core_candidate_queue.py \
  tests/test_backup_service.py \
  tests/test_deployment_contract.py \
  tests/test_network_json_contract.py

# The installed updater must evolve with the checked-out release. The current
# shell process can safely replace its on-disk file; rollback reinstalls the
# previous revision if anything after this point fails.
install -m 0755 deploy/reg_ru/update.sh "${installed_updater}"
printf 'AURORAFOX_BUILD_SHA=%s\n' "${candidate}" > "${build_environment}.tmp"
mv "${build_environment}.tmp" "${build_environment}"
systemctl restart aurorafox-api.service

ready=''
for _ in {1..30}; do
  if payload="$(curl --fail --silent --show-error --max-time 5 http://127.0.0.1:8768/ready 2>/dev/null)"; then
    if READINESS_PAYLOAD="${payload}" /opt/aurorafox/venv/bin/python -c \
      'import json, os; data=json.loads(os.environ["READINESS_PAYLOAD"]); assert data["ok"] is True; assert data["database"]["ok"] is True; assert data["database"]["journal_mode"] == "wal"'; then
      ready='yes'
      break
    fi
  fi
  sleep 2
done
test "${ready}" = 'yes'
# Defense in depth: deployment acceptance also validates the live file directly,
# independently of the HTTP process that reported /ready.
PYTHONPATH="${repository}" /opt/aurorafox/venv/bin/python -m api.database --path "${database_path}"
trap - ERR
echo "AURORAFOX_UPDATE_OK from=${previous} to=${candidate} source=github/${deploy_ref} preupdate_backup_sha=${preupdate_backup_sha} rollback_db=${rollback_database}"
