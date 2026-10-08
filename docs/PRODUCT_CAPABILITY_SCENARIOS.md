# AuroraFox — Product Capability Scenarios

This document is the user-facing companion to the technical capability catalog. It explains what a capability gives the user, what AuroraFox visibly does, how the result is verified, and what happens when a prerequisite is missing.

## Scenario 1 — Ordinary offline question

**Before:** Internet is unavailable. The user needs an explanation based on the local Core, Memory and installed Knowledge.

**User:** "Explain why polypropylene shrinks after molding and remember the useful conclusion."

**AuroraFox visibly does:**
1. keeps Local Core status READY;
2. retrieves relevant installed Knowledge;
3. checks private Memory for related material;
4. answers with provenance labels;
5. stores the user-relevant conclusion in private Memory/Knowledge according to policy.

**Verification:** no external AI/network inference is required; the response records which local sources were used.

**Result:** the user gets a useful answer offline.

**Fallback:** if the installed Seed pack lacks sufficient material, Fox says that local knowledge is insufficient instead of inventing a sourced answer.

---

## Scenario 2 — Read a public URL and remember it

**Before:** The user has a public technical article.

**User:** "Read this link and remember the useful information."

**AuroraFox visibly does:**
1. validates the URL and redirects;
2. blocks private-network/SSRF destinations;
3. downloads the public content;
4. extracts readable text or passes the downloaded document through File Intelligence;
5. stores source URL/title/hash/time/provenance;
6. adds usable content to private Knowledge;
7. answers the user's question from the imported source.

**Verification:** the Knowledge source is visible and searchable after import.

**Result:** the user can ask follow-up questions later without re-sending the URL.

**Fallback:** CAPTCHA, mandatory login, paywall or unavailable network produces a clear reason and does not trigger bypass behavior.

---

## Scenario 3 — Fix a code regression

**Before:** A trusted project fails when a second request arrives while Core is still starting.

**User:** "Find why the second request breaks startup, fix it and prove the fix."

**AuroraFox visibly does:**
1. indexes/searches the trusted project;
2. finds startup/retry code and related tests;
3. asks Code Architect/Tester logic to identify likely contracts and verification;
4. prepares a patch in the trusted workspace;
5. runs the relevant test/build toolchain when available;
6. checks the resulting diff;
7. reports actual test evidence.

**Verification:** build/test exit status and diff evidence, not a generated claim.

**Result:** a concrete code change with proof.

**Fallback:** if the required compiler/toolchain is missing, Fox offers an installed sandbox/container or owner-approved installation path and labels the result UNVERIFIED until a real test can run.

---

## Scenario 4 — Long Work task

**Before:** A project has several known problems and the user does not want to guide every step.

**User:** "Audit this project, fix the release-blocking defects, run the relevant checks and prepare a report."

**AuroraFox visibly does:**
1. shows a concise task plan and affected scope;
2. creates a checkpoint/change ledger;
3. executes bounded steps;
4. records progress in the Task Center;
5. replans when an observed result differs from expectation;
6. runs verification;
7. produces the report/artifacts.

**Verification:** each completed step has outcome/evidence; failed or unverified steps remain marked.

**Result:** a finished work product rather than a long chat explanation.

**Fallback:** pause/cancel preserves checkpoints; a non-reversible external side effect requires fresh confirmation.

---

## Scenario 5 — Computer Agent edits a desktop application

**Before:** A value must be changed in a Windows application.

**User:** "Open the production spreadsheet and change the plan value in the specified cell."

**AuroraFox visibly does:**
1. requests task-scoped Computer permission if needed;
2. shows the Computer Session preview and intended plan;
3. inspects Windows UI Automation/screenshot state;
4. performs bounded mouse/keyboard actions;
5. re-reads the UI;
6. verifies that the expected value/state changed;
7. records the action in the audit timeline.

**Verification:** expected-vs-actual UI state, not "I clicked it".

**Result:** the requested application state is confirmed.

**Fallback:** if the user moves the mouse/types, automation pauses and control returns to the user. If the external state is uncertain after an unsafe action, Fox does not blindly retry.

---

## Scenario 6 — Analyze a scanned PDF

**Before:** A PDF has no usable text layer.

**User:** "Read this manual and find the setup limits."

**AuroraFox visibly does:**
1. detects missing/insufficient text layer;
2. renders pages within resource limits;
3. runs local OCR;
4. indexes extracted text with page provenance;
5. retrieves the relevant sections;
6. answers with page/source references.

**Verification:** processed page count/OCR warnings are visible.

**Result:** the user receives the requested limits from the scanned document.

**Fallback:** if OCR is unavailable or limits are hit, Fox says exactly which pages were not processed instead of claiming the whole PDF was read.

---

## Scenario 7 — Voice conversation

**Before:** The user wants hands-free interaction.

**User:** presses the microphone or uses the configured wake mode.

**AuroraFox visibly does:**
1. shows LISTENING with an input-level indicator;
2. transcribes speech;
3. passes text through the same Core/Memory/Knowledge pipeline as typed chat;
4. speaks the answer through local TTS when enabled;
5. supports barge-in: user speech stops TTS and returns to listening.

**Verification:** the temporary transcript is visible before/while it is committed according to the selected voice mode.

**Result:** the same Fox works through voice rather than a separate voice assistant.

**Fallback:** denied microphone permission, busy microphone or STT failure produces an actionable state while text chat remains usable.

---

## Scenario 8 — Low-resource Android device

**Before:** Android device has 4 GiB RAM and low battery.

**User:** asks a normal question while a heavy background task is pending.

**AuroraFox visibly does:**
1. uses Lite Core;
2. uses Seed Knowledge;
3. reduces context/parallelism;
4. pauses or serializes heavy Work/OCR tasks;
5. shows resource mode without blocking basic chat.

**Verification:** Diagnostics/Capability Matrix reports active Lite profile and unavailable/deferred heavy capabilities.

**Result:** basic useful operation continues without repeated OOM crashes.

**Fallback:** operations that cannot safely fit are queued/refused with a clear reason and preserved intermediate state.

---

## Scenario 9 — Future image generation capability

**Status:** capability provider may ship after the common V1.6 media contracts are accepted; it is not a V1.6.0 blocker.

**User:** "Create a 3000×3000 music cover with no people, brighter composition and Treninem branding."

**AuroraFox visibly does:**
1. turns the request into MediaIntent + ArtifactSpec;
2. recalls private style preferences;
3. selects an installed `image.generate` provider based on capability/resource profile;
4. creates candidates;
5. evaluates them with Vision;
6. repairs/edits the best candidate when supported;
7. validates dimensions/constraints;
8. records MediaOutcome and user feedback.

**Verification:** artifact dimensions/hash and visual constraint checks.

**Result:** a finished image artifact.

**Fallback:** no installed provider = capability unavailable, without affecting normal Core/chat.

---

## Scenario 10 — Future video creation capability

**Status:** video provider is parallel/non-blocking and is not a V1.7.0 release requirement unless the owner explicitly promotes it into scope.

**User:** "Make a vertical TikTok video for this track."

**AuroraFox visibly does:**
1. analyzes audio structure/beat/energy;
2. builds a creative plan/storyboard;
3. uses available image/video generation/edit capabilities;
4. assembles shots and transitions;
5. verifies timing and visual constraints;
6. reviews the rendered result through Vision/audio analysis;
7. revises weak sections;
8. returns final MP4 and a concise production summary.

**Learning:** user rejection/acceptance updates private media workflow preferences; reusable provider reliability lessons may become privacy-safe shared candidates.

---

## Scenario 11 — Sync conflict

**Before:** Windows and Android changed the same non-mergeable private record while offline.

**AuroraFox visibly does:**
1. detects causal concurrency using the sync protocol;
2. preserves both versions;
3. shows "Нужно выбрать версию";
4. offers local/other/common-ancestor comparison;
5. lets the user keep mine / keep other / merge / keep both where supported.

**Verification:** resolution creates a new causal event and no version is silently lost.

**Result:** the user controls the ambiguous merge.

---

## Scenario 12 — Evolution from a recurring verified weakness

**Before:** Fox repeatedly fails the same class of deterministic task despite ordinary learning.

**AuroraFox does:**
1. Experience identifies the recurring verified weakness;
2. creates an improvement proposal;
3. generates 3-10 isolated candidates from the same Stable baseline;
4. runs hard safety/privacy/regression gates;
5. runs the versioned quality benchmark;
6. keeps Stable if no candidate proves improvement;
7. independently re-verifies a winner before controlled promotion.

**Verification:** exact candidate hashes, benchmark manifest and independent verification evidence.

**Result:** self-improvement is evidence-driven, not "Fox decided to rewrite itself".
