# Authorized security workspace

This executable foundation checks HTTP response configuration on exact owner-authorized URLs. It sends bounded GET requests, verifies TLS certificates on HTTPS, pins the validated DNS destination, records redacted evidence and offers concrete remediation. It does not assign a security grade or claim exploit, authenticated-flow, injection or comprehensive pentest coverage. The Windows chat/tool registry can invoke this same runner only from an explicit owner-authorized private `user://` scope; broader controlled test modules remain pending.

Create a private scope JSON outside Git containing:

```json
{
  "authorization_reference": "owner approval for this exact system and test",
  "expires_at": "2026-10-02T00:00:00+00:00",
  "allowed_origins": ["https://example.invalid"],
  "urls": ["https://example.invalid/"],
  "allow_private_lab": false,
  "max_requests": 1,
  "timeout_seconds": 10,
  "max_response_bytes": 1048576
}
```

Replace the example with an authorized target and a current expiry. Operational budgets are owner-controlled; the URL list must fit the request budget. Private/local lab targets require explicit `allow_private_lab: true`. No live external target is authorized by this example or by importing a document.

From the repository root:

```bash
python -m security_workspace.runner --scope /private/scope.json --authorize --output /private/before.json
python -m security_workspace.runner --scope /private/scope.json --authorize --baseline /private/before.json --output /private/after.json
python -m unittest tests.test_security_workspace -v
```

The owner must authorize the exact scope at execution. Missing/expired authorization, invalid URLs and out-of-scope origins fail before a request. Redirects are recorded without following them; mandatory authentication/access restrictions are recorded without bypass. A failed/blocked retest is inconclusive, never resolved. Retests require the same scope hash. Renewing/changing scope requires a reviewed new baseline.

Evidence stores target hashes, origins, status, bounded body hash, checked configuration findings and remediation. It does not store URL queries, response bodies, cookie names/values or raw exception text. Keep scope and evidence private. A missing header is a configuration finding whose applicability needs review, not proof that exploitation succeeded.

The lab suite starts a real temporary loopback HTTP server. It measures missing defenses, applies actual header/cookie remediation and proves those findings disappear on retest. It also verifies authorization gates, redirect/access handling and redaction. It never contacts an external target.


## AuroraFox chat/tool bridge

The registered tool is `security_configuration_check`. It accepts only a private `user://` scope file, an optional `user://` baseline, a request flag `authorized=true`. This flag requests a local owner confirmation dialog; it cannot authorize a run itself. The dialog displays the full scope and baseline hash. Changed inputs invalidate consent. Each accepted run freezes reviewed bytes in a fresh private `user://security/runs/<random>/` directory and creates a new evidence file there; custom output paths are rejected and existing files are never deleted. Generic file tools cannot write into the reserved run directory. A scope document by itself never authorizes traffic. The installed Windows package ships the exact same `runner.py` beside the bundled File Intelligence Python runtime; the Godot client launches it as a child process and polls asynchronously so the UI thread is not blocked by a synchronous process call.

If the scope is rejected before evidence exists, the tool reports failure without inventing results. Redirects, authentication/access boundaries and transport failures remain non-success outcomes. The returned report is the runner's redacted evidence JSON; no response bodies, URL queries, cookie values or raw exception strings are returned.

The bridge rejects empty/malformed reports and checks the scope-file SHA-256 and result count. Work execution guards remain active while the child runs; cancellation/master stop kills the child and reports a stopped outcome. Windows physical dialog/package acceptance remains a separate device gate.
