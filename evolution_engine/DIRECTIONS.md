# AuroraFox Evolution Engine Directions

## Main coordinator
Owns architecture, integration decisions and conflict control.

## Direction 1 — Evolution Core
Owner goal:
Create the controlled improvement lifecycle.

Tasks:
- improvement cycle state;
- experiment registry;
- proposal lifecycle;
- integration contracts.

Do not modify production Core directly.

## Direction 2 — Mutation Engine
Owner goal:
Create safe candidate generation.

Tasks:
- mutation record;
- candidate identity;
- isolated candidate metadata;
- mutation history.

Rules:
- 3-10 candidates per tournament;
- no direct promotion.

## Direction 3 — Learning System
Owner goal:
Store improvement experience.

Tasks:
- accepted/rejected experience records;
- links to Memory/Knowledge interfaces;
- reusable improvement knowledge.

## Direction 4 — Evaluation / Tournament
Owner goal:
Compare candidates against baseline.

Tasks:
- metrics contract;
- benchmark result storage;
- winner selection rules.

## Direction 5 — Safety / Integration
Owner goal:
Protect AuroraFox.

Tasks:
- permission levels;
- rollback contract;
- audit events;
- sandbox boundaries.

Parallel workers must read the master log before changes and avoid editing the same files.
