#!/usr/bin/env bash
set -Eeuo pipefail

readonly AURORAFOX_GITHUB_REPO='https://github.com/Treninem/AI.git'
readonly AURORAFOX_GITHUB_REF='main'
public_host="${1:-${AURORAFOX_PUBLIC_HOST:-}}"
backup_public_key="${AURORAFOX_BACKUP_PUBLIC_KEY:-}"

if [[ "${EUID}" -ne 0 ]]; then
  echo 'Run AuroraFox REG.RU installation as root.' >&2
  exit 2
fi
if [[ -z "${public_host}" ]]; then
  public_ip="$(ip -4 route get 1.1.1.1 | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}')"
  test -n "${public_ip}"
  public_host="${public_ip}.sslip.io"
fi
if [[ ! "${public_host}" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo 'Invalid AuroraFox public host.' >&2
  exit 3
fi
if [[ ! "${backup_public_key}" =~ ^ssh-ed25519[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]]; then
  echo 'AURORAFOX_BACKUP_PUBLIC_KEY must contain the owner PC ed25519 public key.' >&2
  exit 4
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git openssh-server python3 python3-pip python3-venv ufw unattended-upgrades
if ! command -v caddy >/dev/null 2>&1; then
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https gpg
  curl --fail --silent --show-error --location \
    'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    -o /usr/share/keyrings/caddy-stable-archive-keyring.asc
  curl --fail --silent --show-error --location \
    'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    -o /etc/apt/sources.list.d/caddy-stable.list
  chmod 0644 /usr/share/keyrings/caddy-stable-archive-keyring.asc /etc/apt/sources.list.d/caddy-stable.list
  apt-get update
  apt-get install -y caddy
fi

if ! id aurorafox >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/aurorafox --create-home --shell /usr/sbin/nologin aurorafox
fi
if ! id aurorafox-backup >/dev/null 2>&1; then
  useradd --system --home-dir /exports --shell /usr/sbin/nologin aurorafox-backup
fi
usermod -a -G aurorafox-backup aurorafox
install -d -m 0755 /opt/aurorafox /etc/aurorafox
install -d -o aurorafox -g aurorafox -m 0750 /var/lib/aurorafox
install -d -o root -g root -m 0755 /srv/aurorafox-backup
install -d -o aurorafox -g aurorafox-backup -m 2750 /srv/aurorafox-backup/exports
install -d -o root -g root -m 0755 /etc/ssh/authorized_keys
printf '%s\n' "${backup_public_key}" > /etc/ssh/authorized_keys/aurorafox-backup
chmod 0600 /etc/ssh/authorized_keys/aurorafox-backup
cat > /etc/ssh/sshd_config.d/10-aurorafox-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PermitRootLogin prohibit-password
X11Forwarding no
EOF
cat > /etc/ssh/sshd_config.d/90-aurorafox-backup.conf <<'EOF'
Match User aurorafox-backup
  ChrootDirectory /srv/aurorafox-backup
  ForceCommand internal-sftp
  AuthorizedKeysFile /etc/ssh/authorized_keys/%u
  AuthenticationMethods publickey
  PasswordAuthentication no
  AllowAgentForwarding no
  AllowTcpForwarding no
  PermitTTY no
  X11Forwarding no
EOF
sshd -t
systemctl restart ssh.service

ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
systemctl enable --now unattended-upgrades.service

if [[ ! -d /opt/aurorafox/repository/.git ]]; then
  git clone --branch "${AURORAFOX_GITHUB_REF}" --single-branch \
    "${AURORAFOX_GITHUB_REPO}" /opt/aurorafox/repository
fi
actual_origin="$(git -C /opt/aurorafox/repository remote get-url origin)"
test "${actual_origin}" = "${AURORAFOX_GITHUB_REPO}"
git -C /opt/aurorafox/repository fetch --no-tags origin "${AURORAFOX_GITHUB_REF}"
git -C /opt/aurorafox/repository checkout --detach "origin/${AURORAFOX_GITHUB_REF}"
chown -R root:root /opt/aurorafox/repository

python3 -m venv /opt/aurorafox/venv
/opt/aurorafox/venv/bin/python -m pip install --disable-pip-version-check --upgrade pip
/opt/aurorafox/venv/bin/python -m pip install --disable-pip-version-check \
  -r /opt/aurorafox/repository/api/requirements.txt pytest==8.4.1

cat > /etc/aurorafox/aurorafox.env <<EOF
AURORAFOX_USER_DIR=/var/lib/aurorafox
AURORAFOX_API_HOST=127.0.0.1
AURORAFOX_API_PORT=8768
AURORAFOX_API_RPM=60
AURORAFOX_API_LOG_LEVEL=warning
AURORAFOX_DEPLOYMENT=reg-ru
AURORAFOX_BACKUP_MAX_BYTES=268435456
AURORAFOX_GITHUB_REPO=${AURORAFOX_GITHUB_REPO}
AURORAFOX_GITHUB_REF=${AURORAFOX_GITHUB_REF}
AURORAFOX_PUBLIC_URL=https://${public_host}
EOF
chmod 0600 /etc/aurorafox/aurorafox.env
current_sha="$(git -C /opt/aurorafox/repository rev-parse HEAD)"
printf 'AURORAFOX_BUILD_SHA=%s\n' "${current_sha}" > /etc/aurorafox/build.env

cat > /etc/systemd/system/aurorafox-api.service <<'EOF'
[Unit]
Description=AuroraFox lightweight REG.RU API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=aurorafox
Group=aurorafox
WorkingDirectory=/opt/aurorafox/repository
EnvironmentFile=/etc/aurorafox/aurorafox.env
EnvironmentFile=/etc/aurorafox/build.env
ExecStart=/opt/aurorafox/venv/bin/uvicorn api.server:app --host 127.0.0.1 --port 8768
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/aurorafox

[Install]
WantedBy=multi-user.target
EOF

install -m 0755 /opt/aurorafox/repository/deploy/reg_ru/update.sh /usr/local/sbin/aurorafox-update
cat > /etc/systemd/system/aurorafox-update.service <<'EOF'
[Unit]
Description=Update AuroraFox from GitHub main with tests and rollback
After=network-online.target aurorafox-api.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/aurorafox-update
EOF
cat > /etc/systemd/system/aurorafox-update.timer <<'EOF'
[Unit]
Description=Check GitHub for AuroraFox updates every five minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Persistent=true
RandomizedDelaySec=30s

[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/aurorafox-backup.service <<'EOF'
[Unit]
Description=Create restricted AuroraFox data snapshot for owner PC SFTP
After=aurorafox-api.service

[Service]
Type=oneshot
User=aurorafox
Group=aurorafox-backup
WorkingDirectory=/opt/aurorafox/repository
EnvironmentFile=/etc/aurorafox/aurorafox.env
ExecStart=/opt/aurorafox/venv/bin/python -m api.backup_service --user-root /var/lib/aurorafox --export-root /srv/aurorafox-backup/exports --max-source-bytes 268435456
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/aurorafox /srv/aurorafox-backup/exports
EOF
cat > /etc/systemd/system/aurorafox-backup.timer <<'EOF'
[Unit]
Description=Refresh AuroraFox owner-PC snapshot every five minutes

[Timer]
OnBootSec=3min
OnUnitActiveSec=5min
Persistent=true
RandomizedDelaySec=20s

[Install]
WantedBy=timers.target
EOF

cat > /etc/caddy/Caddyfile <<EOF
${public_host} {
  encode zstd gzip
  reverse_proxy 127.0.0.1:8768
  header {
    Cache-Control "no-store"
    Strict-Transport-Security "max-age=31536000; includeSubDomains"
    X-Content-Type-Options "nosniff"
    X-Frame-Options "DENY"
    Referrer-Policy "no-referrer"
  }
}
EOF
caddy validate --config /etc/caddy/Caddyfile

if ! swapon --show=NAME --noheadings | grep -q . && [[ "$(df --output=avail -B1 / | tail -n1)" -gt 2147483648 ]]; then
  fallocate -l 1G /swapfile
  chmod 0600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

systemctl daemon-reload
systemctl enable --now aurorafox-api.service aurorafox-update.timer aurorafox-backup.timer caddy.service
curl --fail --silent --show-error --retry 30 --retry-delay 2 http://127.0.0.1:8768/health >/dev/null
systemctl start aurorafox-backup.service
test -s /srv/aurorafox-backup/exports/latest.zip
test -s /srv/aurorafox-backup/exports/latest.sha256

echo "AURORAFOX_REG_RU_OK url=https://${public_host} sha=${current_sha} updates=github/main"
echo 'Bootstrap admin key (read it once, then remove the file): /var/lib/aurorafox/api/bootstrap_key.txt'
echo 'Owner PC backup transport: key-pinned, chrooted internal SFTP user aurorafox-backup.'
