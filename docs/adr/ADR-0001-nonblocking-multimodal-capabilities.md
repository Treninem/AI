# ADR-0001 — Non-blocking multimodal capabilities

- Date: 2026-10-06
- Status: ACCEPTED
- Decision authority: Owner
- Scope: AuroraFox Cognitive Core roadmap, image/video generation, model/runtime integration
- Supersedes: none

## Context

AuroraFox needs image generation, image editing, image-to-image, inpainting, video generation and video editing soon enough to become part of the same learning system, but these capabilities must not turn V1.6.0.0 or V1.7.0.0 into open-ended releases.

The cognitive roadmap already has hard milestones:
- V1.6.0.0 Cognitive Foundation;
- V1.6.1.0 Experience & Learning;
- V1.6.2.0 Shared/Distributed Cognition;
- V1.7.0.0 Autonomous Fox / integrated Evolution.

Heavy image/video runtimes, model downloads and hardware-specific optimization have substantially different delivery risk from the cognitive foundation. Making a specific diffusion/video model a hard dependency of the Core would couple release readiness to GPU/runtime/model churn and would repeat the architectural mistake of making a tool equal to a Fox capability.

## Constraints / invariants

- One AuroraFox identity and one cognitive loop.
- No separate "Image Fox" or "Video Fox".
- Model/provider is an implementation of a capability, not the capability itself.
- V1.6.0.0 and V1.7.0.0 must keep bounded, independently testable release scopes.
- V1.5.0.0 is not delayed by heavy generation runtimes.
- External/cloud media providers may be optional but can never become the required intelligence engine.
- Capability/model assets must be signed/versioned and owner-controlled.
- Media generation must participate in Context, Memory/Experience, provenance, Outcome and Learning.
- Private user media/prompts are not automatically promoted to shared learning.

## Alternatives considered

### A. Put full image + video generation into V1.6.0.0

Pros:
- immediate complete multimodal release.

Cons:
- high risk of delaying the Cognitive Foundation;
- forces hardware/model/runtime decisions before the common cognition interfaces stabilize;
- makes V1.6 testing much broader;
- risks coupling Core architecture to current-generation diffusion/video models.

Rejected.

### B. Defer all media creation until after V1.7

Pros:
- simplest V1.6/V1.7 critical path.

Cons:
- media learning is not represented while Experience/Cognitive foundations are designed;
- later integration may require reworking events, artifacts, outcomes, model routing and capability discovery;
- delays an important owner-requested capability unnecessarily.

Rejected.

### C. Add a small common Media/Artifact/Capability foundation in V1.6.0.0, keep concrete generators as non-blocking signed capability providers

Pros:
- media becomes a first-class faculty of the same Fox immediately;
- Cognitive/Experience schemas are designed once;
- image/video models can arrive independently without delaying Core milestones;
- provider/model replacement does not change Fox identity or brain architecture;
- Fox can later benchmark and learn which provider/model/workflow works best.

Cons:
- requires disciplined capability/provider abstraction;
- initial V1.6.0.0 has media contracts even if no generation provider is installed.

Accepted.

## Decision

AuroraFox will use a **capability/provider architecture**.

Cognitive Core reasons in stable capability names such as:

- `vision.analyze`
- `image.generate`
- `image.edit`
- `image.image_to_image`
- `image.inpaint`
- `image.outpaint`
- `image.upscale`
- `image.background_remove`
- `video.generate`
- `video.image_to_video`
- `video.edit`
- `video.compose`
- `video.render`
- `audio.analyze`
- `audio.edit`

Concrete models/runtimes implement these capabilities through providers.

Examples of future providers may include local diffusion/video runtimes, owner-controlled workers, or optional external services. The provider name/model family is never part of the user's cognitive contract.

## Stable media objects

V1.6.0.0 introduces only the common contracts required by cognition:

### MediaIntent
Represents what the user is trying to create/change.

Fields include:
- goal;
- media type;
- required dimensions/duration;
- content constraints;
- style/preferences;
- forbidden elements;
- target platform/use;
- privacy/provenance requirements.

### ArtifactSpec
Represents the required finished artifact.

Fields include:
- type;
- format;
- dimensions/resolution;
- duration/frame-rate where relevant;
- quality requirements;
- output destination;
- validation criteria.

### CapabilityDescriptor
Describes what an installed provider can actually do.

Fields include:
- capability id;
- provider id/version;
- model id/hash;
- supported modes;
- hardware requirements;
- resource profile;
- limits;
- local/remote classification;
- privacy classification.

### MediaJob
A resumable bounded execution record.

States:
- PLANNED;
- RUNNING;
- PAUSED;
- FAILED;
- CANCELLED;
- COMPLETED.

### MediaOutcome
Records:
- generated artifact hashes;
- provider/model/settings;
- measured resource cost;
- automatic evaluation;
- user feedback;
- accepted/rejected state;
- learned lesson references.

These objects plug into the same Cognitive Event / Experience substrate as code, Work and Computer.

## Release sequencing

### V1.5.0.0 — unchanged critical path
No image/video generation requirement is added to the V1.5 release gate.

Only existing image/video analysis capabilities are stabilized.

### V1.6.0.0 — Cognitive Foundation + media contracts only
Required media scope is intentionally small:
- MediaIntent schema;
- ArtifactSpec;
- Capability Registry extension;
- MediaJob/Outcome event compatibility;
- provider discovery contract;
- resource/hardware declaration;
- deterministic mock-provider tests.

No production image/video generator is required for V1.6.0.0 acceptance.

This prevents media from delaying Cognitive Foundation.

### V1.6.1.0 — Experience & Learning
Add learning hooks that allow Fox to evaluate creation workflows:
- task outcome;
- user preference feedback;
- quality evaluation;
- provider/model performance history;
- workflow/strategy success statistics.

A concrete image-generation provider may ship when ready, but **its readiness is not allowed to block the Experience & Learning core release**. If it is not ready, the capability remains unavailable and the core release proceeds.

### V1.6.2.0 — Shared/Distributed Cognition
Add safe shared-media lessons:
- provider/model reliability;
- general workflow corrections;
- reusable non-private strategy lessons;
- cross-device MediaJob/Artifact metadata where appropriate.

Raw private generated assets/prompts are not shared automatically.

Concrete media providers remain independent from this release gate.

### V1.7.0.0 — Autonomous Fox
V1.7 depends on the accepted cognitive/experience contracts, not on completion of every possible image/video generator.

V1.7 adds:
- autonomous selection of installed media capabilities;
- dynamic trust for media actions;
- benchmark/evaluation orchestration;
- self-improving media workflows;
- safe adoption of newly installed provider versions;
- rollback/fallback to known-good providers/workflows.

Full video generation is explicitly **not a V1.7.0.0 release blocker**.

## Capability delivery after the common foundation

Concrete image/video capability providers are delivered as signed, owner-controlled capability assets/packages with their own manifest/model hashes and compatibility requirements.

They are not separate AuroraFox products and do not create a second AI identity.

This allows, for example:
1. an image provider to become available as soon as it passes its own capability acceptance;
2. an image-edit provider to follow later;
3. a video provider to follow after that;
without reopening or delaying the Cognitive Core release.

The main application exposes the capability automatically when the provider is installed and verified.

## Self-learning behavior

Fox is not expected to invent diffusion/video generation mathematics from nothing.

Fox is expected to learn **how to use available capabilities better**:

- select the best provider/model for the goal;
- select parameters/resource profile;
- choose direct generation vs image-to-image/inpainting;
- generate multiple candidates when justified;
- visually evaluate results;
- repair artifacts;
- learn user preferences;
- learn which workflows succeed/fail;
- benchmark newly installed provider/model versions;
- maintain capability performance profiles.

New provider onboarding flow:

`discover -> verify signature/compatibility -> sandbox benchmark -> capability profile -> limited use -> outcome learning -> trusted routing`.

## Acceptance / non-delay rule

A media feature may block a release only if that exact capability is explicitly listed as a release-scope requirement for that version.

Otherwise:
- missing provider = capability unavailable, not Core failure;
- provider failure = degrade to another installed provider or honest unavailable state;
- image/video model download/build failure does not fail V1.6.0.0 or V1.7.0.0 unless explicitly promoted into that release gate;
- no unfinished media code may weaken the stable Core path.

## Consequences

AuroraFox receives the correct learning and architectural foundation early, while expensive media runtimes can mature independently.

This keeps development smooth:
`V1.5 stable product -> V1.6 cognition -> V1.7 autonomy`
without a large media detour, while still allowing image/video creation to appear as soon as its concrete capability provider is genuinely ready.
