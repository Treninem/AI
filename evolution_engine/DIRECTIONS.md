# AuroraFox Evolution Engine — directions

All chats work on the same branch:

`feature/aurorafox-evolution-engine`

No chat creates a new branch unless the coordinator explicitly authorizes an isolated experiment. Every chat reads `AGENTS.md` and the complete `docs/PROJECT_MASTER_LOG.md` first. The master log remains the only project journal.

## Shared rules for every direction

- Do not edit `main`, release/update/package/version files or `.github/workflows/**`.
- Do not rewrite existing AuroraFox foundations from zero.
- Reuse `SelfImprover`, `CoreImprovementPipeline`, `MemoryStore`, `KnowledgeStore`, `SandboxManager`, `RuntimeExtensionManager`, `AutonomySettingsManager`, `UpdateAutonomyGuard` and existing agent infrastructure.
- Before editing, compare fresh `main` and `feature/aurorafox-evolution-engine`, then check active claims in the master log.
- Multiple chats may audit one direction, but only one primary executor edits a claimed file set at a time.
- New chats continue the same direction and branch; they do not create replacement branches just because a chat changed.
- Until the coordinator opens runtime integration, production foundation files are read-only for Evolution work.
- Current owner instruction: continue code development/audit in large batches; do not disturb release tests.

## Direction 1 — Evolution Core

Primary ownership:
- `evolution_engine/core/**`
- `evolution_engine/integration/**`

Current foundation:
- `AuroraEvolutionEngine`
- `AuroraEvolutionExperimentRegistry`
- `AuroraEvolutionFoundationAdapter`

Tasks:
- maintain the complete Analysis → Experiment → Evaluation → Decision → Experience lifecycle;
- keep experiment IDs, phase history and bounded recent state;
- coordinate existing modules without becoming a second AgentCore/SelfImprover;
- expose deterministic status and recovery state.

Handoff prompt:
> You are Direction 1 — Evolution Core. Work only on the shared `feature/aurorafox-evolution-engine` branch. Read AGENTS.md and PROJECT_MASTER_LOG.md first. Reuse existing AuroraFox foundations. Do not touch release/main/workflows. Continue the Evolution lifecycle/controller/registry integration, check for duplicate architecture and coordinate file ownership through the master log.

## Direction 2 — Mutation Engine

Primary ownership:
- adapters/metadata under `evolution_engine/learning/**` and mutation-specific additions approved by coordinator.

Authoritative generator:
- `scripts/self_improver.gd` remains the hot-extension mutation implementation.
- Core mutations reuse `CoreImprovementPipeline` primitives through the Evolution Core tournament adapter.

Tasks:
- preserve 3–10 distinct candidates, default 5;
- keep mutation ID/tag, strategy, reason, SHA, verification outcome and failure reason;
- reject duplicate candidates;
- do not implement another mutation generator.

Handoff prompt:
> You are Direction 2 — Mutation Engine. Do not create a new generator. Audit and extend metadata/adapters around the existing SelfImprover and CoreImprovementPipeline tournaments. Preserve the 3–10 invariant, distinct SHA candidates and candidate ledger. Work only in the shared Evolution branch and avoid release files.

## Direction 3 — Learning System

Primary ownership:
- `evolution_engine/learning/**`

Authoritative storage/retrieval:
- `scripts/memory_store.gd`
- `scripts/knowledge_store.gd`

Tasks:
- record successful, rejected, blocked and rollback experience through MemoryStore;
- preserve candidate-level failed/rejected evidence;
- read existing Memory and Knowledge without duplicating the same source;
- never auto-import Evolution output into canonical Core Knowledge.

Handoff prompt:
> You are Direction 3 — Learning System. Reuse MemoryStore and KnowledgeStore; do not create a new database. Improve bounded Evolution experience/context/candidate learning, dedupe retrieval, provenance and useful rejected-experiment memory. Never bypass Knowledge curation.

## Direction 4 — Evaluation / Tournament

Primary ownership:
- `evolution_engine/evaluation/**`

Authoritative evaluation:
- `scripts/self_improver.gd`
- `scripts/core_candidate_benchmark.gd`
- existing comparative review in `CoreImprovementPipeline`

Tasks:
- preserve same-baseline comparison;
- require 3–10 distinct candidates and at least 3 verified finalists;
- keep stable Core as incumbent through baseline/candidate no-regression + comparative improvement;
- independently reverify the winner;
- keep Level 2 evaluation separate from Level 3 signed-promotion handoff;
- report unavailable speed/memory metrics as unavailable rather than inventing numbers.

Handoff prompt:
> You are Direction 4 — Evaluation/Tournament. Reuse existing benchmarks and reviews. Strengthen evidence integrity, metrics and winner verification without changing release authority. Never accept a single-candidate autonomous Core promotion.

## Direction 5 — Safety / Integration

Primary ownership:
- `evolution_engine/safety/**`
- Evolution integration contracts; tests only when owner reopens test phase.

Authoritative safety:
- `scripts/sandbox_manager.gd`
- `scripts/runtime_extension_manager.gd`
- `scripts/autonomy_settings_manager.gd`
- `scripts/update_autonomy_guard.gd`

Tasks:
- enforce levels 0–4;
- master stop/update guard fail closed;
- require Evolution managed mode before Levels 2–4 so the legacy AutonomousCoordinator cannot auto-activate hot winners in parallel;
- serialize with existing autonomous cycles and Core pipeline lock;
- preserve emergency rollback/recovery;
- ensure Evolution cannot sign, publish, auto-merge or grant itself release authority;
- keep Evolution unwired from runtime/release until coordinator explicitly opens integration.

Handoff prompt:
> You are Direction 5 — Safety/Integration. Audit permission gates, locks, rollback and release isolation. Do not weaken master stop, updater trust, sandbox or promotion authority. Work only in the Evolution branch and do not wire project.godot/workflows until the coordinator authorizes integration.

## Coordinator rule

The coordinator owns cross-direction architecture, conflicting file claims, final integration and any future decision to touch runtime wiring. Chats report real code/files/commits and blockers through `docs/PROJECT_MASTER_LOG.md`; this file is only the stable direction map, not a second progress journal.
