# Evolution Engine acceptance

This directory contains isolated tests for the feature branch. It does not alter release workflows.

## Static contracts

Run:

`python evolution_engine/tests/run_evolution_checks.py --static-only`

This runs all Python contract files in `evolution_engine/tests/`, including the acceptance-runner contract. It checks that Evolution:
- reuses the existing SelfImprover 3–10 tournament;
- reuses sandbox/master-stop/update-guard/runtime-extension authorities;
- does not call the single-candidate Core `run_candidate()`;
- keeps Memory/Knowledge reuse bounded;
- keeps release authority outside Evolution.

## Full Godot acceptance

With Godot 4.7.1 available:

`python evolution_engine/tests/run_evolution_checks.py --godot <path-to-godot>`

The runner executes the existing AuroraFox self-improvement and Core benchmark smokes before the new Evolution policy/evidence/controller smokes. It also runs `core_tournament_windows_smoke.gd` on every platform so the complete 3–10 candidate tournament, second verification, handoff, signed-update exclusion and lock lifecycle are always exercised.

The production adapter remains Windows-only because the existing Core source verification pipeline is Windows-only. On non-Windows hosts, that smoke uses a test-only subclass to cross the platform preflight without changing production behavior; its success marker reports `native_windows=false`. On Windows it uses the production adapter and reports `native_windows=true`.

A full acceptance claim requires the Godot smokes to be executed successfully; static contracts alone are not sufficient evidence for runtime readiness. Native Windows acceptance is still required before claiming the real Core source pipeline verified end to end.
