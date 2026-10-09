# AuroraFox — Canonical Roadmap and Release Scope

Status: **ACTIVE / CANONICAL**
Owner decision date: 2026-10-06
Applies to: all Chat / Work / Codex / Agent development sessions

This file is the canonical release roadmap for AuroraFox. It converts the end-state specification, accepted ADRs and owner decisions into a bounded execution order.

It is intentionally shorter than the historical master journal. The journal records what happened; this file defines what future release scope means.

---

## 1. Authority and contradiction rules

When two statements appear to conflict, use this precedence:

1. **Current repository/runtime/CI/device evidence** — facts override prose.
2. **Hard invariants in `AGENTS.md`** — self-primary Core, privacy, safety, version-last, signing, rollback, journal protocol.
3. **This file: `docs/AURORAFOX_CANONICAL_ROADMAP.md`** — authoritative release scope and sequencing.
4. **Accepted ADRs in `docs/adr/`** — authoritative architecture decisions inside their scope.
5. **Canonical owner target/UI sections in `docs/PROJECT_MASTER_LOG.md`** — detailed end-state requirements and acceptance contracts.
6. **Current ACTIVE claim in the master log** — execution ownership only; a claim may not silently expand or contradict items 1–5.
7. **Older master-log roadmap/proposal entries** — historical context only when superseded by this file or an accepted ADR.

Historical journal entries are never deleted merely because plans evolved. They preserve evidence and rationale, but they do not regain authority over a later explicit canonical decision.

If a new owner decision changes this roadmap materially:
- create/update an ADR when the decision is architectural;
- update this canonical roadmap;
- append the reconciliation to the master log;
- never rely on a chat-only instruction as the sole durable source.

---

## 2. Scope classes

Every planned capability is one of three classes for a release.

### CRITICAL
The release cannot be accepted without it.

### PARALLEL_NON_BLOCKING
May be implemented and merged when its own gates are green, but failure/incompletion does **not** delay the release unless the owner explicitly promotes it to CRITICAL.

### DEFERRED
Must not be implemented as current release work without a new owner decision/claim.

An ACTIVE claim must state the scope class.

---

## 3. Permanent product direction

AuroraFox is one self-primary AI system.

The long-term shared loop is:

`Perception -> Context -> World/Self Model -> Memory/Knowledge/Experience -> Reasoning -> Goals -> Decision -> Action -> Outcome -> Learning`

All capabilities — Chat, Voice, Vision, Files, Web, Code, Work, Computer, Security, media creation, sync and Evolution — plug into that one identity and lifecycle.

External AI/models may be optional providers/tools. They are never the required cognitive authority.

---

# RELEASE TRAIN

## 4. V1.5.0.0 — Stable production foundation

### Objective

Finish and verify the product that already exists. V1.5.0.0 is **not** the Cognitive Core rewrite.

### CRITICAL scope

#### Core / Chat
- bundled self-primary local Core;
- normal chat without required external AI/Ollama/Internet;
- stable direct-chat path;
- bounded recovery from Core crash/OOM;
- Lite fallback where required by supported hardware;
- offline capability benchmark and current release quality gates.

#### Memory / Knowledge
- current Memory/Knowledge baseline made reliable;
- genuine Knowledge profiles and import integrity;
- Seed/Standard/Full behavior according to canonical target spec;
- source provenance and honest truncation;
- no destructive migration into future Experience schema.

#### File Intelligence
- supported document/archive/spreadsheet parsing;
- local OCR baseline;
- image/audio/video analysis currently in scope;
- bounded memory/resource limits;
- owner-adjustable operational limits where allowed;
- truthful unsupported/partial-processing states.

#### Public Web
- public HTTP/HTTPS reading;
- provenance;
- private Knowledge retention under owner read=remember rule;
- CAPTCHA/login/paywall/access-control/SSRF boundaries.

#### Code / project work
- CodeSpecialist baseline;
- Project Index on supported platform;
- Git/status/diff;
- real test/build evidence when toolchain exists;
- UNVERIFIED status when it does not.

#### Work / Computer baseline
- production-safe lifecycle/recovery baseline;
- bounded task state;
- screenshot/UIA/mouse/keyboard primitives on supported Windows;
- idempotency/uncertain-external-state protection;
- permissions, sandbox, cancellation and Master Stop;
- no claim of completed action without observable verification.

#### Voice
- local STT/TTS/VAD/wake/barge-in baseline;
- text chat remains usable if Voice fails.

#### UI / performance / accessibility
- adaptive Windows/Android UI;
- separate Windows Settings window;
- loading/streaming/long-response/empty/error/offline/resource states;
- NVDA/TalkBack baseline;
- canonical performance/RAM SLO gates;
- no minute-scale interaction latency accepted in affected scope.

#### Updater / release
- signed manifest/package;
- resumable chunked download;
- network/restart recovery;
- hash/integrity checks;
- atomic apply, health check and rollback;
- A.B.C.D version-last;
- exact-SHA package/release acceptance.

#### Security/privacy
- protected boundaries already in current product scope;
- owner-controlled limits;
- no secrets in Git/logs;
- current scoped Security Workspace acceptance where implemented.

### PARALLEL_NON_BLOCKING

- hidden account/guest/role backend hardening while public multi-user stays disabled;
- future Cognitive/media schema preparation only when it does not expand V1.5 runtime scope;
- documentation/benchmarks that do not block current product acceptance unless already defined as V1.5 gates.

### DEFERRED from V1.5

- mature Cognitive Event brain;
- mature World/Self Model;
- formal Experience/Learning engine;
- distributed cognition;
- public multi-user activation;
- production image generation;
- production video generation;
- advanced autonomous Evolution;
- Smart Home.

### Exit gate

V1.5.0.0 is accepted only after its release-scope exact-SHA CI/package/device/update gates are satisfied. Canonical version is changed last.

After release, only necessary V1.5.0.x stabilization fixes remain on this line.

---

## 5. V1.6.0.0 — Cognitive Foundation / substrate

### Objective

Introduce the minimum common cognition substrate **without attempting the finished cognitive brain**.

### CRITICAL scope

- canonical Cognitive Event envelope and versioning;
- provenance primitives;
- uncertainty/confidence representation primitives;
- bounded Context Manager kernel;
- adapters over existing Memory and Knowledge — no destructive all-at-once rewrite;
- projection-first/read-oriented World Model skeleton;
- projection-first Self Model skeleton;
- semantic intent routing contracts;
- model/capability routing contracts;
- common artifact/capability/media contracts from ADR-0001:
  - MediaIntent;
  - ArtifactSpec;
  - CapabilityDescriptor;
  - MediaJob;
  - MediaOutcome compatibility with Cognitive Events;
- migration/version identifiers;
- observability/diagnostics for new cognition substrate;
- deterministic mock-provider tests;
- independent migration/rollback/exact-SHA acceptance.

### Explicitly NOT a V1.6.0.0 blocker

- mature world graph;
- automatic conversion of all historic Memory into Experience;
- collective-learning promotion;
- distributed sync cognition;
- public accounts;
- autonomous Core mutation;
- production diffusion/image provider;
- production video provider.

### PARALLEL_NON_BLOCKING

After the media contracts are accepted:
- concrete signed image-generation provider;
- image-edit/inpaint/upscale provider;
- optional local Vision provider;
- provider benchmarking.

These may ship when independently green. They do not delay V1.6.0.0.

### Exit gate

The substrate must coexist safely with V1.5 data paths, be observable, reversible/migratable and not regress current product behavior.

---

## 6. V1.6.1.0 — Experience & Learning

### Objective

Turn verified outcomes into reusable private experience without confusing facts, preferences and strategies.

### CRITICAL scope

#### Memory / Experience boundary
Memory owns:
- facts;
- events;
- preferences;
- relationships;
- user/project/device state;
- remembered decisions/sources.

Experience owns:
- goal/conditions;
- strategy/actions/tools;
- expected outcome;
- observed outcome;
- verification evidence;
- success/failure class;
- applicability;
- confidence;
- counterexamples.

A Memory/event becomes an Experience candidate only when:
1. goal exists;
2. strategy/action exists;
3. observable outcome exists;
4. evaluation signal/evidence exists.

#### Learning
- objective evaluator;
- hybrid evaluator;
- subjective evaluator;
- private preference learning;
- confidence/calibration;
- Experience/Skill retrieval;
- migration of eligible legacy skills/failures;
- NEVER_LEARN admission veto;
- LEARN_PRIVATE / LEARN_SHARED_CANDIDATE classification;
- learning audit/provenance.

#### Media learning hooks
- MediaOutcome evaluation;
- provider/model/workflow performance history;
- user-specific visual/media preferences;
- visual evaluation result as evidence, not unquestioned truth.

### PARALLEL_NON_BLOCKING

- production image.generate provider;
- image.edit/image-to-image/inpaint/outpaint/upscale;
- better Vision provider;
- media candidate generation/evaluation workflows.

Concrete providers may appear as soon as their own acceptance passes. They do not hold the core Experience release hostage.

### Exit gate

Learning must improve future strategy selection without leaking private data, learning secrets/untrusted instructions or overriding objective failure with subjective feedback.

---

## 7. V1.6.2.0 — Shared / Distributed Cognition

### Objective

Make cognitive state causally consistent across devices and allow privacy-safe shared lessons.

### CRITICAL scope

#### Principal-aware cognition
- private cognitive events scoped to verified principal;
- account/guest/owner capability semantics available internally even if public multi-user UI remains disabled.

#### Distributed event history
- append-only operations;
- unique event id;
- device id + monotonic device sequence;
- HLC;
- dotted/version-vector causal context;
- checkpoints/snapshots;
- tombstones;
- offline queues;
- versioned protocol.

#### Conflict handling
- type-specific merge;
- explicit unresolved conflict preservation;
- no universal blind Last-Write-Wins;
- conflict UI for non-mergeable state.

#### Collective learning
- private_principal -> shared_candidate -> shared_core;
- privacy scrub;
- source eligibility;
- evidence gates;
- applicability scope;
- contradiction/counterexample retention;
- durable curator/system veto;
- subjective taste never promoted as universal truth.

### PARALLEL_NON_BLOCKING

- cross-device media artifact metadata;
- privacy-safe provider/model reliability lessons;
- reusable media workflow lessons;
- account UX preparation.

### Still DEFERRED unless owner explicitly activates

- mandatory login;
- public registration;
- guest quota UI;
- public multi-user launch.

### Exit gate

A generalized lesson may improve another task/user without any cross-principal raw private read or data leakage.

---

# 8. V1.7.0.0 — Autonomy Foundation

### Objective

Create a durable, inspectable and stoppable autonomous execution substrate. This is **not yet maximum autonomy**.

### CRITICAL scope

- durable long-running task state machine;
- pre-execution plan for MEDIUM/HIGH side-effect work;
- Change Ledger;
- checkpoints;
- rollback handlers where technically honest;
- trust evaluator using:
  - impact;
  - reversibility;
  - scope;
  - evidence confidence;
  - history trust;
  - explicit capability;
- permission revalidation;
- pause/resume/cancel;
- Master Stop;
- observe -> act -> verify loop for supported Work/Computer actions;
- user-visible task audit/progress;
- crash/restart recovery of supported tasks.

### Default trust policy

LOW + reversible + granted capability:
- auto-run only with evidence confidence >=0.80 and history trust >=0.70, or deterministic independently verifiable equivalent.

MEDIUM:
- checkpoint/sandbox/dry-run;
- evidence confidence >=0.85;
- rollback available.

HIGH:
- explicit confirmation.

CRITICAL:
- fresh exact authorization; learned trust alone can never make it autonomous.

### Explicitly NOT a V1.7.0.0 blocker

- maximum autonomy over every tool;
- full automatic Evolution promotion;
- full video generation/editing;
- Smart Home;
- public multi-user.

### PARALLEL_NON_BLOCKING

- autonomous selection of installed media providers;
- provider benchmarking;
- image/video workflows already independently accepted.

---

## 9. V1.7.1.0 — Advanced Work / Computer

### Objective

Make autonomous execution resilient to unexpected intermediate states.

### CRITICAL scope

- bounded replanning;
- expected-vs-actual UI/tool-state verification;
- richer Computer Session evidence;
- selective rollback for isolated reversible changes;
- partial-failure recovery;
- dynamic-trust adaptation within hard risk floors;
- stronger task decomposition/checkpoint strategy.

### Exit gate

Fox must detect when reality differs from its plan and repair/replan instead of blindly continuing.

---

## 10. V1.7.2.0 — Experience-driven Evolution

### Objective

Connect verified recurring weaknesses to controlled self-improvement.

### CRITICAL scope

- recurring-weakness detection from verified Experience;
- improvement proposal generation;
- 3–10 same-baseline isolated candidates;
- hard binary safety/privacy/regression gates;
- versioned numerical benchmark manifest;
- stable incumbent comparison;
- independent verification;
- rollback readiness;
- controlled promotion under owner/release authority.

### Promotion rule

Existing canonical Evolution thresholds remain authoritative:
- all hard gates PASS;
- improvement must exceed the accepted metric/tolerance threshold;
- noisy results require repeated evidence;
- inconclusive/tied result keeps Stable.

Evolution cannot bypass signing, release authority, Master Stop, privacy or protected boundaries.

---

# 11. Parallel Multimodal Capability Lane

Multimodal creation is important but is **not placed in front of cognition/autonomy on the critical path**.

The stable capability interface is defined by ADR-0001.

## Earliest allowed progression

After V1.6.0 media contracts are accepted, independently versioned signed providers may be added for:

1. `vision.analyze`;
2. `image.generate`;
3. `image.edit`;
4. `image.image_to_image`;
5. `image.inpaint`;
6. `image.outpaint`;
7. `image.upscale`;
8. `image.background_remove`;
9. `video.generate`;
10. `video.image_to_video`;
11. `video.edit`;
12. `video.compose`;
13. `video.render`.

A provider is an implementation of a capability, not the capability itself.

## Non-delay invariant

A missing/failed provider means:
- that capability is unavailable/degraded;
- normal Core remains healthy;
- V1.6/V1.7 proceeds unless the owner explicitly made that exact provider/capability CRITICAL for that release.

Fox learns how to use available providers; Fox is not expected to invent a diffusion/video engine from nothing.

---

# 12. Vision integration rule

Vision is a Perception source, not an isolated File Intelligence feature.

Visual observation records carry:
- source artifact/frame/screenshot;
- provider/model;
- timestamp;
- confidence;
- OCR text separately from inferred visual meaning;
- detected entities/regions when available;
- provenance;
- privacy class.

Low-confidence visual inference is not promoted to confirmed fact.

Computer:
`screenshot/UIA -> Perception -> Context -> expected state -> action -> observation -> verification`

Media:
`generated artifact -> Vision evaluation -> MediaOutcome -> Experience`

---

# 13. Future public multi-user activation

Account, guest, role and privacy foundations may continue to mature internally.

Public activation stays **DEFERRED** until an explicit owner decision.

Before activation, required acceptance includes:
- official email verification;
- guest quota;
- account switching;
- export/delete;
- device/session revoke;
- role/capability enforcement;
- cross-principal negative tests;
- Cognitive Core isolation;
- sync/privacy acceptance.

Current owner use remains frictionless single-user.

---

# 14. Smart Home / physical-world lane

Status: **DEFERRED ARCHITECTURAL RESERVE**.

Do not implement Home UI/device runtime merely because it is described conceptually.

Activation requires:
- explicit owner decision;
- new ADR;
- capability/device protocol;
- electrical/physical safety boundaries;
- privacy model;
- release scope.

The Cognitive Core should remain extensible to physical Perception/Action without redesign.

---

# 15. Cross-cutting acceptance contracts

Every release/capability in scope inherits the canonical contracts already recorded in the master log and ADRs.

These include:

- self-primary/offline Core;
- performance/RAM SLOs;
- Android battery/thermal policy;
- Seed/Standard/Full Knowledge profiles;
- local Core quality suite;
- accessibility;
- data deletion/export;
- migrations/embedding versioning;
- local execution threat model;
- UI loading/streaming/empty/error/offline states;
- observability;
- exact-SHA acceptance;
- updater signing/rollback;
- A.B.C.D version-last;
- physical/device acceptance where required.

No roadmap item is "done" merely because source code exists.

---

# 16. CI cadence

For each coherent block:

`implement largest safe coherent block -> cheap local/static checks -> one full relevant CI batch -> collect all reds -> batch repair -> targeted local/direct checks -> one final full exact-SHA CI`

Do not poll CI repeatedly.

Do not launch full CI after each tiny change.

Do not stack a large dependent layer on an unverified foundation.

---

# 17. Journal execution protocol

The master log remains the only coordination journal.

Every new ACTIVE claim must include:

```text
ROADMAP_RELEASE: V1.x.x.x
SCOPE_CLASS: CRITICAL | PARALLEL_NON_BLOCKING | DEFERRED-EXCEPTION
ROADMAP_SECTION: <section number/name>
ADR_REFS: <ADR ids or none>
STARTING_HEAD: <sha>
INTENDED_BUMP: A | B | C | D | NONE
OWNED_PATHS: <paths>
DEPENDENCIES: <accepted prerequisites>
NON_BLOCKERS: <parallel work explicitly not required>
ACCEPTANCE_GATES:
- ...
```

A claim is invalid if it silently expands the release's CRITICAL scope.

If a new requirement appears during development:
1. classify it as current defect, parallel capability or future requirement;
2. do not automatically make it a release blocker;
3. if architecture changes, create/reconcile ADR;
4. if release scope changes, update this canonical roadmap with owner authority;
5. then update the claim.

---

# 18. Progress reporting

Progress percentages belong to the active release/lane acceptance criteria, not the long-term end-state vision.

Therefore:
- V1.5 readiness is not reduced because V1.7 features are not implemented;
- V1.6.0 readiness is not reduced because V1.6.2 distributed cognition is not implemented;
- V1.7.0 readiness is not reduced because V1.7.2 Experience-driven Evolution is not implemented;
- a PARALLEL_NON_BLOCKING media provider cannot hold another release at 99%.

Required journal/report fields remain:

`PROGRESS_COMPLETE: XX%`
`PROGRESS_REMAINING: YY%`
`DONE:`
`REMAINING:`
`BLOCKERS:`
`NEXT:`

A blocker must name the exact acceptance gate it blocks.

---

# 19. Definition of a release blocker

A problem is a release blocker only when at least one is true:

1. it breaks a CRITICAL capability in this roadmap;
2. it violates a hard invariant/security/privacy/signing boundary;
3. it fails a declared acceptance gate for that release;
4. it is a known P0/P1 defect that makes an in-scope capability unusable/unsafe;
5. the owner explicitly promotes it into current release scope.

Interesting future work, incomplete optional providers and later-version capabilities are **not** blockers by default.

---

# 20. Definition of Done

For an in-scope block:

`implementation -> relevant tests -> integration -> real behavior verification -> regression check -> journal evidence -> accepted`

For a release:

- all CRITICAL scope accepted;
- no unresolved in-scope P0/P1;
- exact-SHA final relevant CI green;
- package/update/release gates green;
- device/physical gates complete where required or explicitly waived with correct WAIVED status;
- version bumped last;
- post-bump gates green;
- artifacts belong to the accepted SHA.

---

# 21. Current execution point

**V1.5.0.0 was published on 2026-10-09** from tag commit `ac222f545b6a69727b4b5ba38fffb458a67e3680`, after the release-scope exact-SHA package, signed Windows/Android, updater-repair and publication gates passed. The master log records the run IDs, public assets and explicit Android full-production-Knowledge-payload waiver.

Only necessary V1.5.0.x stabilization fixes remain on this line. Any V1.6 implementation needs its own roadmap claim and gates. The retained owner-audit inventory is tracked in the master log; its unresolved entries are not silently treated as verified fixes.

---

# 22. Accepted architecture references

- `docs/adr/ADR-0001-nonblocking-multimodal-capabilities.md`
  - media capability/provider abstraction;
  - media must not delay V1.6/V1.7.

- `docs/adr/ADR-0002-staged-cognition-learning-and-autonomy.md`
  - staged V1.6/V1.7;
  - Memory/Experience boundary;
  - learning veto;
  - Dynamic Trust;
  - Change Ledger;
  - Vision as Perception;
  - resource/toolchain recovery;
  - capability matrix.

- `docs/adr/ADR-0003-progress-aware-core-requests.md`
  - V1.5 desktop Core progress-aware request/stall/total/cancellation policy; existing quality/performance gates unchanged.

- `docs/PRODUCT_CAPABILITY_SCENARIOS.md`
  - user-facing before/after scenarios; explanatory, not a replacement for acceptance evidence.

---

CANONICAL_ROADMAP_STATUS: ACTIVE / OWNER-APPROVED / SUPERSEDES CONFLICTING EARLIER ROADMAP WORDING.
