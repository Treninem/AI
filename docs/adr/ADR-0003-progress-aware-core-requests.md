# ADR-0003 — Progress-aware local Core requests

- Date: 2026-10-06
- Status: ACCEPTED (owner delegated best waiting-policy choice)
- Scope: V1.5 current desktop Core request reliability; no new cognition/media scope

## Evidence

Core run37431321173/job112162690911 at8efc513: long_context fails after90040ms with transport13/http0. Engine task1105 is still evaluating prompt at88.68s/progress0.94, then receives client cancellation. The client90s wall deadline conflicts with the existing120s scenario watchdog. Earlier diagnostic-less failures remain historically unproven identical.

Observed engine build11429/commitd81235049 exposes OpenAI streaming chunks with return_progress/prompt_progress (processed/total/cache) and content/reasoning deltas. Source: ggml-org/llama.cpp tools/server/server-context.cpp, server-task.cpp and README.md at deployed d81235049 (also checked at7fe450e19). Reference: https://github.com/ggml-org/llama.cpp/blob/d81235049/tools/server/README.md

## Decision

Use asynchronous local HTTPClient streaming and a bounded SSE decoder. Renew a request's progress clock only when processed prompt tokens increase above zero or real generation deltas arrive. Connection activity, role-only frames, duplicate progress, changing timing/total and SSE pings are not proof of work.

Capture immutable limits when the request starts: no-progress90s default, total deadline0 (disabled) default, response bytes4MiB default. All are owner-adjustable and zero disables each operational bound; integer representation remains a technical boundary. Persist in private user config, expose in Windows Settings, and report save failure honestly. Changes affect new requests.

Explicit request cancellation closes active sockets without relaunching or stopping a healthy engine; existing forced teardown/Master Stop still closes requests and terminates owned processes. Reject malformed JSON/protocol, oversized response, HTTP/backend errors and EOF without complete finish+DONE; never return partial content as completed work. No automatic fallback/retry of a deadline, protocol or budget failure.

Keep health checks separate and short. Imported content remains data, not authority. Normal private chat does not enable file logging. Retained content/reasoning is response data under the same byte budget; diagnostic records contain counts, not private prompt/raw dictionaries.

## Alternatives

A larger fixed wall deadline is simpler but still discards healthy longer work and conflates slow progress with a stall. Heartbeat-only extension can keep a stuck request alive indefinitely. Neither is selected. Total deadlines remain available to the owner alongside confirmed-progress waiting.

## Acceptance / consequences

The existing120s benchmark watchdog and performance/quality scenario gates are unchanged. Progress waiting improves correctness of cancellation, not inference speed; exceeding a declared benchmark/SLO remains a failure. Genuine fragmented UTF8/SSE, loopback HTTP progress/stall/duplicate/total/response-budget/cancellation/EOF/error fixtures are required along with actual bundled Core21/21 and new-SHA package/integration gates. Missing local Godot is UNVERIFIED, never PASS. Android native request policy is unchanged and remains a separately verified platform scope.
