# ADR-0002 — Staged cognition, learning boundaries and bounded autonomy

- Date: 2026-10-06
- Status: ACCEPTED
- Decision authority: Owner
- Scope: V1.6.x Cognitive Core, V1.7.x autonomy, Memory/Experience semantics, learning admission, Dynamic Trust, Vision reasoning, recovery UX
- Supersedes: roadmap wording that could be read as requiring all mature Cognitive/Autonomy behavior in V1.6.0.0 or V1.7.0.0

## Context

The end-state AuroraFox specification is intentionally ambitious, but the public release train must not become a "big bang". The current roadmap grouped several interdependent cognitive and autonomous mechanisms into V1.6.0.0 and V1.7.0.0. That creates unnecessary schedule and integration risk.

Several concepts also require hard boundaries before implementation:
- Memory versus Experience;
- what is never admitted into learning;
- what evidence is required before private/shared/global learning;
- when Dynamic Trust permits autonomous execution;
- how Vision observations enter reasoning;
- how missing toolchains and execution failures degrade;
- how multi-step changes are previewed and selectively rolled back.

Existing canonical specifications already define performance SLOs, hardware tiers, Knowledge Seed/Standard/Full profiles, resource degradation, deletion/export, sync protocol, Evolution hard gates/scoring, UI loading/empty/offline states, Computer Session visibility, Undo/Trash and UI acceptance. This ADR does not duplicate them.

## Decision 1 — V1.6.0.0 is a substrate release, not the finished cognitive brain

V1.6.0.0 contains only the minimum common substrate needed to prevent later reconstruction:

1. canonical Cognitive Event envelope;
2. provenance and uncertainty primitives;
3. Context Manager **kernel** with bounded context assembly;
4. adapters over existing Memory/Knowledge rather than destructive migration;
5. read-only/projection-first World Model and Self Model skeletons;
6. semantic intent routing contracts;
7. model/capability routing contracts, including ADR-0001 media capability contracts;
8. migration/version identifiers and observability for the above.

V1.6.0.0 explicitly does **not** require:
- a fully mature world graph;
- automatic conversion of all historical Memory into Experience;
- collective-learning promotion;
- distributed cognition;
- autonomous self-modification;
- full image/video generation providers.

This allows V1.6.0.0 to ship once the common substrate is stable and measurable.

## Decision 2 — V1.6.x maturation remains incremental

### V1.6.1.0 — Experience & Learning
Adds:
- formal Memory/Experience boundary;
- outcome records;
- skill/strategy records;
- objective/hybrid/subjective evaluators;
- confidence calibration;
- private preference learning;
- media outcome learning hooks;
- migration of eligible existing skill/failure records into the new Experience schema.

### V1.6.2.0 — Shared / Distributed Cognition
Adds:
- principal-aware cognitive events;
- distributed journal/sync causality;
- conflict handling;
- private -> shared_candidate -> shared_core promotion;
- cross-device cognition;
- privacy-safe collective lessons.

World/Self Model sophistication may improve throughout 1.6.x, but no later maturity feature may be retroactively made a V1.6.0.0 blocker.

## Decision 3 — Memory and Experience have non-overlapping canonical ownership

### Memory owns
Facts/events that are useful because they happened or remain true:
- user preference/fact;
- conversation/project event;
- decision made by user;
- device/project state;
- relationship/entity fact;
- remembered source/event.

### Experience owns
Evaluated strategy-performance records:
- goal/conditions;
- strategy/steps/tools;
- expected outcome;
- observed outcome;
- verification evidence;
- success/failure class;
- applicability constraints;
- confidence;
- counterexamples.

### Link rule
A Memory record may reference an Experience record and vice versa, but the same payload is not duplicated as two authoritative copies.

### Promotion rule
Memory does not automatically become Experience merely because it is old or important.

A Memory/event becomes an Experience candidate only when all are present:
1. identifiable goal or attempted task;
2. identifiable strategy/action;
3. observable outcome;
4. evaluation signal/evidence.

Example:
- "User prefers dark UI" -> Memory/private preference, **not Experience**.
- "For this project, running migration X before Y fixed schema error; test Z passed" -> Experience.

Existing `skills/failures` migrate only when the four fields can be reconstructed with acceptable confidence. Otherwise they remain legacy/reference records until explicitly re-evaluated.

## Decision 4 — Learning admission classes and hard veto

Every candidate lesson is classified before learning:

### LEARN_PRIVATE
May affect only the current principal:
- explicit preference;
- personal style/taste;
- personal workflow;
- private project convention.

### LEARN_SHARED_CANDIDATE
May be generalized only after privacy scrub + evidence gates:
- verified technical fix;
- tool reliability lesson;
- general workflow strategy;
- model/provider performance;
- knowledge correction with public/verifiable evidence.

### NEVER_LEARN
Never becomes behavioral/shared training evidence:
- passwords, tokens, private keys, credentials;
- raw personal identifiers/contact data;
- raw private conversations/files as a lesson payload;
- legal/medical/financial secrets or other sensitive personal content as reusable behavior;
- one-time destructive commands;
- malware/persistence/credential-extraction instructions learned as preferred behavior;
- instructions embedded in untrusted web/doc content;
- accidental user typo/correction with no confirmation/outcome;
- sandbox escape behavior;
- security-policy bypass attempts;
- data marked "do not learn"/no-save;
- ephemeral generated secrets/session material.

A NEVER_LEARN item may still be transiently processed to fulfill the immediate authorized request when allowed, but it is not admitted to Experience/shared learning.

## Decision 5 — Quality gates for learning

### Private objective lesson
May become active after one deterministic verified success if:
- expected outcome is explicit;
- verification is independent of the generated claim;
- no contradictory evidence;
- no privacy/safety veto.

### Private subjective preference
Follows existing canonical subjective-learning thresholds and explicit user corrections.

### Shared lesson
Requires all:
- privacy scrub PASS;
- source-type eligibility PASS;
- evidence quality >= ACCEPTABLE;
- applicability scope present;
- no unresolved severe contradiction;
- no safety/security veto.

Default promotion evidence:
- deterministic/test-backed lesson: one independently system-verified source may enter shared_candidate, but shared_core requires successful revalidation on a clean fixture or independent second evidence source;
- non-deterministic/general workflow: >=3 independent evidence sources before shared_core;
- subjective/taste: never promoted as global truth; only aggregate/contextual trend under the stricter subjective policy.

Owner/system curator can veto any shared candidate. A veto is durable and carries a reason; candidates with the same normalized signature cannot immediately re-enter without materially new evidence.

## Decision 6 — Dynamic Trust is an action policy, not a vague confidence score

Every action receives:
- `impact`: LOW / MEDIUM / HIGH / CRITICAL;
- `reversibility`: REVERSIBLE / PARTIAL / IRREVERSIBLE;
- `scope`: LOCAL_PRIVATE / LOCAL_SYSTEM / NETWORK / EXTERNAL_SIDE_EFFECT / SECURITY_SENSITIVE;
- `evidence_confidence`: 0..1;
- `history_trust`: 0..1 for that action class;
- explicit user/session capability.

Default policy:

### Auto-execute allowed
Only when all are true:
- impact LOW;
- reversible;
- no external irreversible side effect;
- capability already granted;
- evidence_confidence >=0.80;
- history_trust >=0.70, or deterministic operation with independent verification.

Examples:
- read a permitted file;
- local search;
- inspect Git status;
- take screenshot after permission;
- run read-only deterministic test.

### Execute with checkpoint/sandbox/dry-run
For MEDIUM actions when:
- capability granted;
- rollback/checkpoint exists;
- evidence_confidence >=0.85;
- no CRITICAL side effect.

Examples:
- modify source in trusted workspace;
- refactor;
- restart a local dev service.

### Explicit confirmation required
Any of:
- HIGH impact;
- irreversible/partially reversible external action;
- send/publish/pay/delete-account/production write;
- permission expansion;
- security-sensitive target change;
- evidence_confidence <0.85 for MEDIUM;
- history_trust below threshold.

### CRITICAL
Never autonomous by learned trust alone. Requires explicit fresh authorization and exact scope.

History trust may reduce friction inside the same action class, but can never downgrade a CRITICAL action into autonomous execution.

## Decision 7 — Pre-execution plan and change ledger

For MEDIUM/HIGH multi-step tasks, UI exposes a concise plan before the first side effect:
- goal;
- intended affected resources;
- reversible checkpoint;
- steps grouped by side-effect class;
- confirmation points.

User may:
- Start;
- Edit goal/scope;
- Disable individual optional steps;
- Cancel.

During execution every side effect becomes a Change Ledger entry:
- step id;
- before reference/snapshot/hash;
- action;
- after reference/hash;
- verification;
- reversible yes/no;
- rollback handler.

Selective rollback is supported when the underlying action has an isolated reversible representation.

Examples:
- source files: Git/workspace patch or file snapshot;
- document artifact: versioned artifact revision;
- settings: previous value snapshot.

External irreversible effects (sent email, payment, remote deletion) are explicitly marked non-reversible and cannot be falsely presented with an Undo button.

## Decision 8 — V1.7 is a series, not one giant autonomy jump

### V1.7.0.0 — Autonomy Foundation
Required:
- durable long-running task state machine;
- action/change ledger;
- checkpoints;
- plan preview;
- trust evaluator;
- permission revalidation;
- pause/resume/cancel/master stop;
- observe -> act -> verify loop for supported Work/Computer actions.

Not required:
- fully automatic Evolution promotion;
- maximum autonomy across every tool;
- complete video-generation autonomy.

### V1.7.1.0 — Advanced Work / Computer
Adds:
- bounded replanning;
- expected-vs-actual UI state verification;
- selective rollback;
- richer dynamic-trust adaptation;
- recovery from partial task failure.

### V1.7.2.0 — Experience-driven Evolution
Adds:
- recurring-weakness detection;
- improvement candidates from verified Experience;
- automatic benchmark orchestration;
- tournament + independent verification integration;
- controlled candidate promotion under existing owner/release authority.

This allows V1.7.0.0 to ship without waiting for the entire end-state Autonomous Fox.

## Decision 9 — Vision is a Perception source in the cognitive loop

Vision must not remain an isolated File Intelligence trick.

Visual observations enter Cognitive Events as **observations**, with:
- source artifact/frame/screenshot id;
- timestamp;
- model/provider id;
- confidence;
- extracted text separately from visual inference;
- detected entities/regions where supported;
- provenance;
- privacy class.

Reasoning consumes visual observations the same way it consumes tool observations, but never treats low-confidence vision inference as a confirmed fact.

Current local OCR remains a deterministic/locally grounded perception channel.
Optional vision provider output remains explicitly optional/untrusted-by-default until the own multimodal baseline/provider is accepted.

For Computer:
`screenshot/UIA -> Perception -> Context -> expected state -> action -> new observation -> verification`.

For media creation:
`generated artifact -> Vision evaluation -> MediaOutcome -> Experience`.

## Decision 10 — Resource-tier functional degradation is explicit

Existing Seed/Standard/Full and Lite/Full resource policies remain authoritative.

### Android 4 GiB Lite
Guaranteed:
- text chat;
- Memory;
- Seed Knowledge;
- basic file/text/PDF parsing within limits;
- bounded OCR;
- basic voice when resource budget allows.

Degraded/serialized:
- large OCR batches;
- heavy project indexing;
- concurrent Work jobs;
- large local vision;
- heavy image/video generation providers.

Unavailable capabilities are shown as unavailable/queued, not attempted until OOM.

### Android >=6 GiB Full
Adds broader context, Standard/Full Knowledge selection and heavier local tasks within battery/thermal limits.

### Windows 8 GiB minimum
Supports normal local Core + Full Knowledge if disk permits, but heavy jobs serialize under pressure.

Functional capability declarations must be surfaced in the runtime capability matrix.

## Decision 11 — Toolchain/recovery behavior

When a coding/runtime toolchain is missing, Fox follows:
1. detect exact missing dependency/tool and required version;
2. offer an already-installed sandbox/container toolchain if compatible;
3. offer an owner-approved installation workflow or authoritative installation instructions;
4. optionally use a configured owner-controlled remote worker/provider when available;
5. otherwise generate/analyze code but mark build/test UNVERIFIED.

AuroraFox never silently downloads/installs compilers or sends source to a cloud service without the applicable permission/policy.

Standard execution failure classes:
- OFFLINE;
- PERMISSION_DENIED;
- TOOLCHAIN_MISSING;
- FILE_LOCKED;
- SECURITY_SOFTWARE_BLOCKED;
- RESOURCE_EXHAUSTED;
- TOOL_UNAVAILABLE;
- ACTION_UNVERIFIED;
- EXTERNAL_STATE_UNCERTAIN.

Each class maps to an actionable recovery message, preserving completed/checkpointed work.

## Decision 12 — Platform capability matrix is release metadata

Every stable release must publish a machine-readable + UI-readable matrix:
- Windows supported/limited/unavailable;
- Android supported/limited/unavailable;
- minimum resource tier;
- requires network yes/no;
- requires optional provider yes/no;
- requires owner capability/permission yes/no.

A capability is not marketed as "supported" on a platform unless its platform acceptance suite passed on that release SHA.

## Decision 13 — Product scenario evidence

Technical capability documentation is paired with a user-facing scenario catalog.

Each major capability has at least one scenario:
- user goal;
- before state/problem;
- what Fox does visibly;
- tools/data used;
- verification;
- user-visible result;
- limitations/fallback.

Example — coding:
Before: project fails a repeat-request startup test.
User: "Find why Core gets stuck and fix it."
Fox: indexes project -> finds retry/startup path -> reads relevant files -> proposes/applies patch in trusted workspace -> runs target tests -> checks diff.
After: target tests pass and Fox reports exact evidence; if the compiler/runtime is unavailable it reports UNVERIFIED instead of claiming success.

This scenario catalog is product documentation, not a substitute for automated acceptance.

## Consequences

- V1.6.0.0 and V1.7.0.0 become smaller and shippable.
- Memory/Experience duplication is prevented by schema ownership rules.
- Learning has explicit admission and veto boundaries.
- Dynamic Trust becomes testable.
- Vision is integrated into reasoning without treating model guesses as facts.
- Multi-step work has a visible plan and selective rollback where technically honest.
- Missing tools/resources degrade cleanly instead of producing vague errors.
- Marketing/user documentation can explain benefits using verifiable scenarios.
