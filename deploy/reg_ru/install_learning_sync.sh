#!/usr/bin/env bash
set -Eeuo pipefail

# Installs the persistent learning queue flusher alongside the existing
# aurorafox-api.service. It does not replace or restart the API on install.

if [[ "${EUID}" -ne 0 ]]; then
  echo 'Run AuroraFox learning-sync installation as root.' >&2
  exit 2
fi

readonly APP_ROOT="${AURORAFOX_APP_ROOT:-/opt/aurorafox/repository}"
readonly ENV_FILE="${AURORAFOX_ENV_FILE:-/etc/aurorafox/aurorafox.env}"
readonly SERVICE="aurorafox-learning-sync.service"
readonly TIMER="aurorafox-learning-sync.timer"

if [[ ! -f "${APP_ROOT}/api/learning_daemon.py" ]]; then
  echo "Missing ${APP_ROOT}/api/learning_daemon.py; update the repository first." >&2
  exit 3
fi
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}; run deploy/reg_ru/install.sh first." >&2
  exit 4
fi

cat > "/etc/systemd/system/${SERVICE}" <<EOF
[Unit]
Description=AuroraFox persistent learning queue synchronization
After=network-online.target aurorafox-api.service
Wants=network-online.target

[Service]
Type=oneshot
User=aurorafox
Group=aurorafox
WorkingDirectory=${APP_ROOT}
EnvironmentFile=${ENV_FILE}
ExecStart=/opt/aurorafox/venv/bin/python -m api.learning_daemon
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/aurorafox
EOF

cat > "/etc/systemd/system/${TIMER}" <<EOF
[Unit]
Description=Retry AuroraFox learning synchronization every two minutes

[Timer]
OnBootSec=90s
OnUnitActiveSec=2min
Persistent=true
RandomizedDelaySec=20s

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "${TIMER}"
systemctl start "${SERVICE}"

echo "AURORAFOX_LEARNING_SYNC_OK timer=${TIMER}"
systemctl --no-pager --full status "${TIMER}" || true
