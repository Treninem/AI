# AuroraFox Evolution Engine

AuroraFox Evolution Engine is a thin orchestration layer over the self-improvement foundation that already exists in AuroraFox. It is **not** a second implementation of mutation, memory, knowledge, sandboxing, benchmarking, rollback or promotion.

## Existing foundation reused

- `agent/autonomous_coordinator.gd` — observation/synchronization, goals and existing autonomy state.
- `scripts/self_improver.gd` — authoritative hot-extension 3–10 mutation population, isolated verification, scoring, tournament and winner staging.
- `scripts/core_candidate_benchmark.gd` — source/public-contract and deterministic baseline/candidate benchmark comparison.
- `scripts/core_improvement_pipeline.gd` — existing Core proposal, validation, benchmark, comparative review and signed-update candidate storage.
- `scripts/sandbox_manager.gd` — isolated workspaces, snapshots and rollback.
- `scripts/runtime_extension_manager.gd` — verified staged-extension activation/deactivation.
- `scripts/autonomy_settings_manager.gd` — master stop and autonomy preferences.
- `scripts/update_autonomy_guard.gd` — pauses autonomy around update activity.
- `scripts/memory_store.gd` — existing local experience persistence.
- `scripts/knowledge_store.gd` — existing canonical local knowledge retrieval.
- Existing Core candidate queue / signed promotion path remains the only Core release authority.

## Evolution components

- `AuroraEvolutionEngine` — orchestration and full-cycle entry point.
- `AuroraEvolutionExperimentRegistry` — bounded in-memory experiment lifecycle/phase registry.
- `AuroraEvolutionCandidateLedger` — bounded 3–10 candidate metadata ledger; persisted only through existing MemoryStore experience.
- `AuroraEvolutionMetricsAdapter` — normalizes evidence that actually exists; unavailable metrics remain explicitly unavailable.
- `AuroraEvolutionDecisionRecord` — explicit Accept/Reject/Handoff/Rollback decision record.
- `AuroraEvolutionEvidenceGate` — scoreboard/winner/SHA/final-verification integrity.
- `AuroraEvolutionExecutionGuard` — serialization with existing autonomous work.
- `AuroraEvolutionManagedModeGuard` — disables the legacy automatic hot-winner activation path while Evolution Levels 2–4 are in control.
- `AuroraEvolutionCoreTournamentAdapter` — 3–10 Core candidates over one stable baseline using existing CoreImprovementPipeline primitives.
- `AuroraEvolutionExperienceBridge` / `ContextBridge` — reuse existing Memory/Knowledge without creating a parallel database.
- `AuroraEvolutionLearningSignal` — derives bounded strategy/failure metadata only from AuroraFox's own Evolution experience; canonical Knowledge contributes provenance references, not executable prompt instructions.
- `AuroraEvolutionProposalRecord` — records the improvement hypothesis/constraints without becoming a second candidate generator.

## Evolution lifecycle

`run_evolution_cycle()` coordinates:

Analysis
→ bounded learning signal + improvement proposal record
→ existing proposal/candidate generation
→ 3–10 mutation tournament
→ isolated verification
→ evaluation/no-regression
→ explicit decision
→ winner staging or rejection
→ bounded experience record in existing MemoryStore

Before any Level 2–4 operation, Evolution must enter managed mode. Managed mode disables only `AuroraAutonomousCoordinator.autonomous_hot_improvements`, preventing the legacy coordinator from auto-activating a winner behind Evolution permission gates; autonomous research remains available. Hot-extension activation remains a separate Level-4 action. Core promotion preparation remains a separate Level-3 handoff to the existing signed-update path.

## Permission levels

- Level 0 — analysis only.
- Level 1 — analysis + proposal preview.
- Level 2 — isolated mutation tournament; a hot winner may be staged but is not activated.
- Level 3 — Core promotion/handoff preparation only; no release authority.
- Level 4 — activation of an already verified staged hot extension through existing RuntimeExtensionManager.

`CoreImprovementPipeline.run_candidate()` remains unused because it is a single-candidate entrypoint. Evolution instead reuses its lower-level proposal/contract/benchmark/review/storage primitives across 3–10 distinct candidates from one stable baseline. If fewer than three candidates verify, the adapter may continue generating distinct candidates up to the hard maximum of ten before rejecting the tournament.

## Recovery and release authority

Evolution tracks managed-mode authority, its own exclusive guard and ownership of the Core pipeline lock. Recovery is explicit; normal status reads never silently unlock a long-running experiment. Emergency recovery can release only locks owned by Evolution. Rollback reuses existing RuntimeExtensionManager authority.

Evolution never signs, publishes, auto-merges, changes the canonical version, or grants itself release authority.

## Release isolation

Until explicit acceptance, `evolution_engine/**` is not wired into autoload/runtime and does not modify:
- `main`;
- release/update/package workflows;
- version files;
- existing production self-improvement modules.

This keeps current release testing independent while the Evolution layer is developed and verified.
