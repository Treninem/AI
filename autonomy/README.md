# AuroraFox Autonomy Foundation

This directory defines the first non-destructive foundation for autonomous learning and self-improvement.

## Principles

- Existing runtime, model, memory, API, Android and Windows paths remain untouched.
- Autonomous experiments run outside production.
- Every candidate gets tests before activation.
- The production version is versioned and rollback-capable.
- Internet research is limited to publicly accessible sources that the configured researcher is permitted to access.
- The emergency stop and rollback controls are external to the autonomous agent and are never delegated to it.
- Ollama is treated as a replaceable provider, not a permanent architectural dependency.

## Target loop

`research -> curate -> remember -> self-evaluate -> create task -> experiment -> mutate candidate -> test -> compare -> approve -> version -> observe -> repeat`

## Planned components

- `researcher`: discovers and reads permitted public sources.
- `curator`: extracts claims, source metadata and training examples.
- `self_evaluation`: identifies knowledge and capability gaps.
- `task_queue`: turns gaps into measurable improvement tasks.
- `arena`: runs isolated candidate variants and scores them.
- `validator`: executes regression, integration and capability tests.
- `version_manager`: promotes candidates and retains rollback points.
- `provider`: abstracts Ollama and future local model providers.
- `reflection`: records lessons, failed hypotheses and next questions.

This file is intentionally specification-only. Existing application behavior is not replaced by this foundation.