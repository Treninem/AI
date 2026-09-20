# AuroraFox Evolution Engine — directions

All chats work on the same branch:

`feature/aurorafox-evolution-engine`

No chat creates a new branch unless the coordinator explicitly authorizes an isolated experiment. Every chat reads `AGENTS.md` and `docs/PROJECT_MASTER_LOG.md` first.

## Direction 1 — Evolution Core

Primary files:
- `evolution_engine/core/**`
- `evolution_engine/integration/**`

Goal:
- coordinate the existing AuroraFox self-improvement foundation;
- maintain the Evolution lifecycle;
- expose state/status without changing production Core.

Do not reimplement SelfImprover, AgentCore or CoreImprovementPipeline.

## Direction 2 — Mutation Engine

Primary files:
- adapters/contracts under `evolution_engine/mutation/**` when needed.

Foundation owner:
- `scripts/self_improver.gd` remains the mutation implementation.

Goal:
- reuse the existing 3–10 mutation tournament;
- add only missing orchestration/metadata contracts.

Do not create a second mutation generator.

## Direction 3 — Learning System

Primary files:
- `evolution_engine/learning/**`

Foundation owners:
- `scripts/memory_store.gd`
- `scripts/knowledge_store.gd`

Goal:
- write bounded Evolution experience through existing MemoryStore;
- read existing Knowledge for context;
- never bypass research/knowledge curation by automatically writing Evolution output into Core Knowledge.

## Direction 4 — Evaluation / Tournament

Primary files:
- `evolution_engine/evaluation/**`

Foundation owners:
- `scripts/self_improver.gd`
- `scripts/core_candidate_benchmark.gd`

Goal:
- adapt existing tournament and benchmark evidence;
- preserve stable-baseline/no-regression rules;
- maintain the isolated 3–10 Core candidate tournament adapter over the existing CoreImprovementPipeline primitives;\n- keep Level 2 tournament evaluation separate from Level 3 signed-promotion handoff.

## Direction 5 — Safety / Integration

Primary files:
- `evolution_engine/safety/**`
- `evolution_engine/tests/**`

Foundation owners:
- `scripts/sandbox_manager.gd`
- `scripts/runtime_extension_manager.gd`
- `scripts/autonomy_settings_manager.gd`
- `scripts/update_autonomy_guard.gd`

Goal:
- enforce permission levels and master stop;
- keep staged candidates separate from activation;
- preserve snapshot/rollback and signed-release authority;
- prove Evolution is isolated from release paths.

## Shared rule

Until the coordinator explicitly opens integration, these production files are read-only for Evolution work:
`scripts/self_improver.gd`, `scripts/core_improvement_pipeline.gd`, `scripts/core_candidate_benchmark.gd`, `scripts/sandbox_manager.gd`, `scripts/memory_store.gd`, `scripts/knowledge_store.gd`, release/update/workflow/version files.
