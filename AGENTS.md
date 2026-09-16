# AuroraFox agent instructions

These instructions apply to **every** coding agent, ChatGPT chat, ChatGPT Work session, Codex session, automation, or other development process that changes this repository.

## Mandatory first action

Before editing any file:

1. Fetch the latest `main` HEAD.
2. Read **all of `docs/PROJECT_MASTER_LOG.md`**.
3. Read its `Активные работы и занятые файлы` section.
4. Add an ACTIVE claim to that same master log before touching implementation files.
5. Do not edit files/subsystems claimed by another active lane unless you first integrate the latest `main` and explicitly take over/reconcile the claim in the master log.

## One journal only

`docs/PROJECT_MASTER_LOG.md` is the **only development/coordination journal** for AuroraFox.

Do not create separate Chat, Work, Codex, lane, progress, development, or coordination journals. Technical subsystem documentation is allowed, but project status, engineering decisions, claims, completed work, CI evidence, and the continuation plan must be recorded in the master log.

## During and after work

Work in coherent batches. After each completed batch, update `docs/PROJECT_MASTER_LOG.md` with:

- starting HEAD and produced commit(s);
- what changed;
- concise engineering rationale (problem/decision/reason, not private chain-of-thought);
- tests and GitHub Actions run IDs/results;
- artifacts/hashes when relevant;
- remaining limitations/risks;
- exact next step;
- files/subsystem released from the claim.

When stopping, mark the claim DONE or clearly state what remains so the next Chat/Work/Codex session can continue directly from the repository without repeating completed work.

## Product invariants

AuroraFox is local-first and must remain operational without Ollama or another third-party AI client. Normal Windows/Android users must not have to install an inference engine, choose/download a GGUF, or use a model setup wizard; the product ships AuroraFox Core and its required weights.

Do not weaken the user master stop, rollback/snapshots, Core candidate allowlists, independent candidate verification, updater signature/trust boundaries, Android signing continuity, privacy boundaries, sandbox permissions, or the rule that imported documents/code are untrusted data rather than executable authority.

Repository state and CI results override stale prose. If the master log conflicts with current code/CI, investigate, correct the code or the log as appropriate, and record the correction in the master log rather than silently proceeding.
