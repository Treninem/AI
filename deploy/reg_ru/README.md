# AuroraFox on REG.RU

Production uses the REG.RU Base Free Tier for an individual account: 1 vCPU,
1 GB RAM and 10 GB storage for up to six months. If the free offer is not
available, the approved fallback is the `Std C1-M1-D10` cloud server at no more
than 500 RUB/month. Do not add a paid control panel, provider backup product or
automatic tariff upgrade.

Use Ubuntu 24.04 LTS and allow inbound TCP 22, 80 and 443 in the REG.RU security
group. Run `install.sh` as root. With no argument, the installer derives a free
`<public-ip>.sslip.io` HTTPS hostname. A real domain can be supplied as the first
argument.

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
