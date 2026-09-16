# AuroraFox on REG.RU

Production uses the REG.RU Base Free Tier for an individual account: 1 vCPU,
1 GB RAM and 10 GB storage for up to six months. If the free offer is not
available, the approved fallback is the `Std C1-M1-D10` cloud server at no more
than 500 RUB/month. Do not add a paid control panel, provider backup product or
automatic tariff upgrade.

Use a supported Ubuntu LTS release and allow inbound TCP 22, 80 and 443 in the
REG.RU security group. Run `install.sh` as root. With no argument, the installer
derives a free `<public-ip>.sslip.io` HTTPS hostname. A real domain can be
supplied as the first argument.

The 1 GB server runs only the lightweight AuroraFox API, synchronization and
persistent data layer. Local model inference, voice and training stay on the
owner's PC. This prevents swapping a multi-gigabyte model on the small server.

The `aurorafox-update.timer` checks GitHub `main` every five minutes. Only a
fast-forward commit from `https://github.com/Treninem/AI.git` is accepted. The
candidate is compiled and tested before restart; a failed test or health check
restores the previous commit automatically.

Before server installation, generate a dedicated ed25519 key on the owner's PC.
Pass only its `.pub` value to the installer through
`AURORAFOX_BACKUP_PUBLIC_KEY`. Never copy the private key to REG.RU.

```sh
AURORAFOX_BACKUP_PUBLIC_KEY='ssh-ed25519 AAAA... AuroraFox owner PC backup' \
  bash deploy/reg_ru/install.sh
```

The server creates a new database snapshot every five minutes. A chrooted
`aurorafox-backup` account can only read `/exports/latest.zip` and its detached
hash through internal SFTP: it has no shell, port forwarding, API key or access
to the live database. Copy the server's trusted host-key line from the REG.RU
console, then run `deploy/windows/install_server_backup.ps1` on the PC. The task
pins that host key, retries every five minutes after connectivity returns,
validates the detached SHA-256 and embedded manifest, and saves the archive
atomically under `Documents/AuroraFox Backups` with 30-copy retention.

## Account email transport

The installer deliberately creates `/etc/aurorafox/account-mail.env` without
SMTP credentials. Before enabling public registration/password recovery, fill in
`AURORAFOX_SMTP_HOST`, `AURORAFOX_SMTP_USERNAME`, `AURORAFOX_SMTP_PASSWORD` and
`AURORAFOX_SMTP_SENDER`. Keep the file root-only (`0600`) and restart
`aurorafox-api.service`. `AURORAFOX_ACCOUNT_PUBLIC_URL` must be HTTPS; AuroraFox
fails closed rather than sending verification/reset bearer tokens over plain
HTTP.

Do not put SMTP credentials in the repository, command history, screenshots or
the owner-downloadable backup archive.

## Final production acceptance

After DNS/TLS, SMTP and the first backup are working, run the repository's
non-destructive verifier from the REG.RU console as root:

```sh
bash /opt/aurorafox/repository/deploy/reg_ru/verify.sh
```

A successful production gate ends with one line beginning with
`AURORAFOX_REG_RU_VERIFY_OK`. The verifier checks the API/Caddy/SSH services and
timers, deployed build SHA and updater, local and public `/health`/`/ready`,
SQLite integrity/foreign keys/WAL, secure account-mail configuration, the latest
backup SHA-256, HTTPS reachability and required security headers. It never prints
SMTP passwords or account tokens. Any missing production prerequisite fails the
command instead of being silently ignored.
