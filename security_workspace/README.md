# Authorized security workspace

This executable foundation checks HTTP response configuration on exact owner-authorized URLs. It sends bounded GET requests, verifies TLS certificates on HTTPS, pins the validated DNS destination, records redacted evidence and offers concrete remediation. It does not assign a security grade or claim exploit, authenticated-flow, injection or comprehensive pentest coverage. Chat/tool integration and broader controlled tests remain pending.

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
