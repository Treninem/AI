# AuroraFox production Knowledge Pack

The production payload is a separate release artifact and is never committed to
Git. `production_pack.json` pins its filename, byte size, SHA-256, source dump,
license, attribution, genuine-content total and bounded-shard contract.

Validate the downloaded artifact before import:

```bash
python tools/knowledge_pack/validate_pack.py \
  AuroraFox-Knowledge-RU-2026.09.01-v1.tar.zst \
  --report knowledge-pack-validation.json
```

Validation is streaming and fail-closed. It verifies the outer artifact,
manifest, exact member set, every shard hash/size/record count, every record's
schema and provenance, aggregate totals, the 1 GiB genuine-content floor, and
duplicate IDs/content. `.tar.zst` validation requires the local `zstd` command;
normal AuroraFox runtime intelligence remains offline and independent of it.

The source is the pinned Russian Wikipedia `20260901` dump segment recorded in
the contract. Redistribution must retain the CC BY-SA 4.0 license link and
`Russian Wikipedia contributors` attribution stored in every record.
