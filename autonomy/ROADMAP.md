# AuroraFox autonomy roadmap

## Preserve first

The existing Android APK pipeline, Windows package pipeline, API, memory, model bootstrap, voice, work mode and current runtime are treated as existing functionality. The autonomy work must integrate around them rather than replace them.

## Phase 1 — inventory and observability

- Map current API, runtime, memory, model and Ollama integration.
- Identify existing unfinished autonomy/self-improvement code before adding duplicates.
- Add health/status information for autonomous cycles.
- Record every experiment, candidate, score and promotion decision.

## Phase 2 — autonomous research

- Public-web research worker.
- Source metadata and provenance.
- Deduplication and quality scoring.
- Memory ingestion.
- Research queue generated from self-evaluation gaps.

## Phase 3 — self-evaluation

- Capability benchmarks.
- Failure clustering.
- Knowledge-gap generation.
- Self-question queue.
- Reflection history.

## Phase 4 — sandbox evolution

- 3–10 isolated candidates.
- Controlled mutations of prompts/configuration/code/model adapters.
- Automated tests and regression suite.
- Arena scoring.
- Candidate promotion only after validation.

## Phase 5 — repository-aware engineering

- Autonomous work happens on isolated branches/worktrees.
- Build and test before proposing promotion.
- Production remains protected from direct experimental edits.
- Version manager retains rollback points.

## Phase 6 — provider independence

- Keep Ollama behind a provider interface.
- Measure provider dependence.
- Add local model backends as they become available.
- Permit migration only when a replacement passes the same benchmarks.

## Phase 7 — visual improvement

- Screenshot/UI inspection.
- UI candidate generation.
- Automated visual regression checks.
- Promote only validated UI changes.

## Completion criterion

The system reaches the intended autonomous loop when it can independently discover a measurable gap, research it, update memory/skills, create an isolated candidate, test and compare candidates, promote a validated version, record the result, and schedule the next improvement cycle without requiring a manual prompt for each cycle.