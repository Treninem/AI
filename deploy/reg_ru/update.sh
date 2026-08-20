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

rollback() {
  status=$?
  trap - ERR
  echo "AuroraFox update failed; rollback to ${previous}." >&2
  git checkout --detach "${previous}" || true
  /opt/aurorafox/venv/bin/python -m pip install --disable-pip-version-check -r api/requirements.txt >/dev/null || true
  printf 'AURORAFOX_BUILD_SHA=%s\n' "${previous}" > "${build_environment}.tmp"
  mv "${build_environment}.tmp" "${build_environment}"
  systemctl restart aurorafox-api.service || true
  exit "${status}"
}
trap rollback ERR

git checkout --detach "${candidate}"
/opt/aurorafox/venv/bin/python -m pip install --disable-pip-version-check -r api/requirements.txt pytest==8.4.1
/opt/aurorafox/venv/bin/python -m compileall -q api
PYTHONPATH="${repository}" /opt/aurorafox/venv/bin/python -m pytest -q \
  tests/test_api_gateway.py \
  tests/test_api_privacy_contract.py \
  tests/test_backup_service.py \
  tests/test_deployment_contract.py

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
trap - ERR
echo "AURORAFOX_UPDATE_OK from=${previous} to=${candidate} source=github/${deploy_ref}"

