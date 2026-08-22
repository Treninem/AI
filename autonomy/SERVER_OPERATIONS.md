# AuroraFox server operations

## Production hosts

- Main site: `aurorafox.ru`
- API: `api.aurorafox.ru`
- Production IPv4 is deployment-time configuration and must not be guessed or committed as a secret.

## Server role

The REG.RU host is the persistent coordination/data/API layer. The large local model, voice runtime and autonomous Godot coordinator remain on the owner's PC because the documented server profile is lightweight.

## Local services

- API: `127.0.0.1:8768`
- AgentCore bridge: `127.0.0.1:8770` on the owner runtime only
- File service: `127.0.0.1:8767` where deployed
- Ollama: `127.0.0.1:11434` where locally installed

The public reverse proxy terminates HTTPS and forwards to the API. The AgentCore TCP bridge is intentionally not a public internet endpoint.

## Health contract

`GET /health` is public and must return JSON with `ok=true`. It also reports:

- API build SHA
- deployment type
- AgentCore availability
- Ollama availability and models
- learning queue status
- configured bridge port

A healthy API with `agent_online=false` means the persistent server is alive but the owner runtime is not currently connected; it is not an API crash.

## Learning flow

1. Public research runs in the existing autonomous PC coordinator.
2. Curated observations enter the existing MemoryStore/learning collector.
3. API learning events may be persisted in the server's `LearningStore`.
4. The learning-sync timer retries queued events against the configured runtime bridge.
5. The server never needs to load the large local model merely to persist learning state.

## Deployment gate

`deploy/reg_ru/update.sh` must:

1. fast-forward only from the configured GitHub ref;
2. install Python dependencies;
3. compile the API;
4. run the existing API/privacy/backup/deployment tests;
5. install the additive learning-sync timer;
6. restart the API;
7. poll `http://127.0.0.1:8768/health` until `ok=true`;
8. leave the previous Git revision available for rollback if any gate fails.

## Operator verification

On the REG.RU machine, after deployment:

```text
systemctl status aurorafox-api.service
systemctl status aurorafox-learning-sync.timer
curl --fail http://127.0.0.1:8768/health
systemctl list-timers 'aurorafox-*'
```

For the public endpoint, verify `https://api.aurorafox.ru/health` after DNS and TLS are active.

## Do not expose

Do not expose `127.0.0.1:8770` directly to the internet. The bridge is an owner-runtime control interface, not a public API. If remote synchronization is added, it must use the authenticated HTTPS API or another authenticated, explicitly configured transport.
