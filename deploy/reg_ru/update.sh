#!/usr/bin/env bash
set -Eeuo pipefail

readonly repository='/opt/aurorafox/repository'
readonly environment_file='/etc/aurorafox/aurorafox.env'
readonly build_environment='/etc/aurorafox/build.env'

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

readonly sync_service='aurorafox-learning-sync.service'
readonly sync_timer='aurorafox-learning-sync.timer'
readonly unit_directory='/etc/systemd/system'
readonly snapshot="$(mktemp -d /etc/aurorafox/update-rollback.XXXXXX)"
timer_enabled='no'
timer_active='no'
systemctl is-enabled --quiet "${sync_timer}" && timer_enabled='yes'
systemctl is-active --quiet "${sync_timer}" && timer_active='yes'
for unit in "${sync_service}" "${sync_timer}"; do
  if [[ -f "${unit_directory}/${unit}" ]]; then
    cp -p "${unit_directory}/${unit}" "${snapshot}/${unit}"
  fi
done
cp -p /usr/local/sbin/aurorafox-update "${snapshot}/aurorafox-update"

rollback() {
  status=$?
  trap - ERR
  echo "AuroraFox update failed; rollback to ${previous}." >&2
  systemctl stop "${sync_timer}" "${sync_service}" || true
  systemctl disable "${sync_timer}" || true
  for unit in "${sync_service}" "${sync_timer}"; do
    if [[ -f "${snapshot}/${unit}" ]]; then
      cp -p "${snapshot}/${unit}" "${unit_directory}/${unit}"
    else
      # These exact additive units did not exist before this deployment.
      rm -f "${unit_directory}/${unit}"
    fi
  done
  cp -p "${snapshot}/aurorafox-update" /usr/local/sbin/aurorafox-update
  systemctl daemon-reload || true
  git checkout --detach "${previous}" || true
  /opt/aurorafox/venv/bin/python -m pip install --disable-pip-version-check -r api/requirements.txt >/dev/null || true
  printf 'AURORAFOX_BUILD_SHA=%s\n' "${previous}" > "${build_environment}.tmp"
  mv "${build_environment}.tmp" "${build_environment}"
  systemctl restart aurorafox-api.service || true
  if [[ "${timer_enabled}" == 'yes' ]]; then systemctl enable "${sync_timer}" || true; fi
  if [[ "${timer_active}" == 'yes' ]]; then systemctl start "${sync_timer}" || true; fi
  echo "Rollback snapshot retained at ${snapshot}" >&2
  exit "${status}"
}
trap rollback ERR

# Quiesce old writers before replacing queue code in place.
systemctl stop "${sync_timer}" "${sync_service}" || true
systemctl stop aurorafox-api.service
git checkout --detach "${candidate}"
/opt/aurorafox/venv/bin/python -m pip install --disable-pip-version-check -r api/requirements.txt pytest==8.4.1
/opt/aurorafox/venv/bin/python -m compileall -q api
PYTHONPATH="${repository}" /opt/aurorafox/venv/bin/python -m pytest -q \
  tests/test_api_gateway.py \
  tests/test_api_privacy_contract.py \
  tests/test_backup_service.py \
  tests/test_deployment_contract.py \
  tests/test_learning_sync.py

printf 'AURORAFOX_BUILD_SHA=%s\n' "${candidate}" > "${build_environment}.tmp"
mv "${build_environment}.tmp" "${build_environment}"
systemctl restart aurorafox-api.service

healthy=''
for _ in {1..30}; do
  if payload="$(curl --fail --silent --show-error --max-time 3 http://127.0.0.1:8768/health 2>/dev/null)"; then
    if HEALTH_PAYLOAD="${payload}" /opt/aurorafox/venv/bin/python -c \
      'import json, os; data=json.loads(os.environ["HEALTH_PAYLOAD"]); assert data["ok"] is True'; then
      healthy='yes'
      break
    fi
  fi
  sleep 2
done
test "${healthy}" = 'yes'
# Installation is independent of the executable bit and follows the health gate.
bash deploy/reg_ru/install_learning_sync.sh
# Refresh the installed updater too; changing the repository alone is insufficient.
install -m 0755 deploy/reg_ru/update.sh /usr/local/sbin/aurorafox-update
trap - ERR
echo "Rollback snapshot retained at ${snapshot}"
echo "AURORAFOX_UPDATE_OK from=${previous} to=${candidate} source=github/${deploy_ref}"
