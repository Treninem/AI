# AuroraFox Evolution Engine

Development area for controlled self-improvement.

## Design rules

- Stable AuroraFox release remains unchanged.
- Evolution works from a stable baseline.
- No direct self-modification.
- Every improvement follows:

Analysis -> Proposal -> Experiment -> Mutation -> Evaluation -> Accept/Reject -> Experience

## Planned modules

- Evolution Core
- Mutation Engine
- Learning System
- Evaluation/Tournament
- Safety Integration

## Safety invariants

- Candidate changes are isolated.
- Stable baseline remains available.
- Promotion requires verification.
- Rollback is mandatory.
- External AI services are never required for AuroraFox intelligence.
