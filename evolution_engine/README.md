# AuroraFox Evolution Engine

AuroraFox Evolution Engine is a thin orchestration layer over the self-improvement foundation that already exists in AuroraFox. It is **not** a second implementation of mutation, memory, knowledge, sandboxing, benchmarking, rollback or promotion.

## Existing foundation reused

- `agent/autonomous_coordinator.gd` — observation/synchronization, goals and existing autonomy state.
- `scripts/self_improver.gd` — authoritative 3–10 mutation population, isolated verification, scoring, tournament and winner staging.
- `scripts/core_candidate_benchmark.gd` — source/public-contract and deterministic baseline/candidate benchmark comparison.
- `scripts/core_improvement_pipeline.gd` — existing Core candidate validation/storage/promotion handoff.
- `scripts/sandbox_manager.gd` — isolated workspaces, snapshots and rollback.
- `scripts/runtime_extension_manager.gd` — verified staged-extension activation.
- `scripts/autonomy_settings_manager.gd` — master stop and autonomy preferences.
- `scripts/update_autonomy_guard.gd` — pauses autonomy around update activity.
- `scripts/memory_store.gd` — existing local experience persistence.
- `scripts/knowledge_store.gd` — existing local knowledge retrieval.
- Existing Core candidate queue / signed promotion path remains the only Core release authority.

## Evolution lifecycle

Analysis
→ proposal/candidate generation in the existing SelfImprover
→ 3–10 mutation tournament
→ isolated verification
→ evaluation against the stable baseline
→ winner staging
→ explicit activation/integration gate
→ experience record in existing MemoryStore

No direct rewrite of production Core is performed by this package.

## Permission levels

- Level 0 — analysis only.
- Level 1 — analysis + proposal preview.
- Level 2 — isolated mutation tournament; winner may be staged but is not activated by Evolution Engine.
- Level 3 — promotion/handoff preparation only; no release authority.
- Level 4 — activation of an already verified staged hot extension through the existing RuntimeExtensionManager.

Core-file rewriting is intentionally not exposed here yet. The current `CoreImprovementPipeline.run_candidate()` is a single-candidate path, while the hard Evolution invariant requires 3–10 competing candidates before autonomous Core promotion. A later adapter must create that tournament around the existing Core benchmark/proposal primitives before this engine may invoke Core promotion.

## Release isolation

Until explicit acceptance, `evolution_engine/**` is not wired into autoload/runtime and does not modify:
- `main`;
- release/update/package workflows;
- version files;
- existing production self-improvement modules.

This keeps release testing independent while the Evolution layer is developed and verified.
