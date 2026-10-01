"""Owner-authorized, reproducible HTTP configuration checks. No exploit engine."""
from __future__ import annotations

import argparse
import hashlib
import http.client
import ipaddress
import json
import socket
import ssl
import time
from datetime import datetime, timezone
from http.cookies import SimpleCookie
from pathlib import Path
from urllib.parse import urlsplit


class ScopeError(ValueError):
    pass


def canonical_hash(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def validate_scope(scope: dict, *, authorized: bool) -> list[str]:
    if not authorized:
        raise ScopeError("Explicit owner authorization is required")
    if not str(scope.get("authorization_reference", "")).strip():
        raise ScopeError("Record the owner authorization reference")
    try:
        expires = datetime.fromisoformat(scope["expires_at"].replace("Z", "+00:00"))
    except (KeyError, ValueError, TypeError) as exc:
        raise ScopeError("Scope needs an ISO timestamp with timezone") from exc
    if expires.tzinfo is None or expires <= datetime.now(timezone.utc):
        raise ScopeError("Authorization expired or lacks timezone")
    urls = scope.get("urls", [])
    if not urls or not isinstance(urls, list):
        raise ScopeError("Scope must explicitly list exact target URLs")
    max_requests = int(scope.get("max_requests", len(urls)))
    timeout = float(scope.get("timeout_seconds", 10))
    max_bytes = int(scope.get("max_response_bytes", 1024 * 1024))
    if max_requests < len(urls) or timeout <= 0 or max_bytes <= 0:
        raise ScopeError("Owner operational budget does not cover this scope")
    allowed = set(scope.get("allowed_origins", []))
    for url in urls:
        parsed = urlsplit(url)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
            raise ScopeError("Only credential-free HTTP(S) targets are supported")
        if any(c in url for c in "\r\n\x00"):
            raise ScopeError("Invalid target URL")
        origin = f"{parsed.scheme}://{parsed.netloc}"
        if origin not in allowed:
            raise ScopeError(f"Out-of-scope origin: {origin}")
    return urls


class PinnedHTTPSConnection(http.client.HTTPSConnection):
    """Connect to validated IP; certificate/SNI still verifies original hostname."""
    def __init__(self, hostname: str, address: str, port: int, timeout: float):
        super().__init__(hostname, port, timeout=timeout, context=ssl.create_default_context())
        self.address = address

    def connect(self):
        raw = socket.create_connection((self.address, self.port), self.timeout)
        try:
            self.sock = self._context.wrap_socket(raw, server_hostname=self.host)
        except Exception:
            raw.close()
            raise


def resolved_address(host: str, port: int, scope: dict) -> str:
    addresses = sorted({x[4][0] for x in socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)})
    if not addresses:
        raise ScopeError("Target DNS returned no addresses")
    allow_lab = scope.get("allow_private_lab") is True
    for address in addresses:
        ip = ipaddress.ip_address(address)
        if not ip.is_global and not allow_lab:
            raise ScopeError("Private/local targets require explicit private-lab scope")
        if ip.is_unspecified or ip.is_multicast:
            raise ScopeError("Unspecified/multicast target is invalid")
    return addresses[0]


def finding(code: str, evidence: str, remediation: str) -> dict:
    return {"id": code, "evidence": evidence, "remediation": remediation,
            "assessment": "configuration finding; exploitability not established"}


def check_headers(url: str, headers: list[tuple[str, str]]) -> list[dict]:
    mapping = {name.lower(): value for name, value in headers}
    found = []
    checks = [
        ("content-security-policy", "missing_csp", "Define a CSP appropriate to the application and test it in report-only mode first."),
        ("x-content-type-options", "missing_nosniff", "Return X-Content-Type-Options: nosniff on relevant responses."),
    ]
    if urlsplit(url).scheme == "https":
        checks.append(("strict-transport-security", "missing_hsts", "Enable HTTPS-only access and a reviewed HSTS policy after validating all affected hosts."))
    for header, code, remediation in checks:
        if not mapping.get(header, "").strip():
            found.append(finding(code, f"Response lacks {header}", remediation))
    if not mapping.get("x-frame-options") and "frame-ancestors" not in mapping.get("content-security-policy", "").lower():
        found.append(finding("missing_frame_policy", "Neither frame-ancestors nor X-Frame-Options is present", "Define allowed frame ancestors or a compatible X-Frame-Options policy."))
    for name, value in headers:
        if name.lower() != "set-cookie":
            continue
        cookie = SimpleCookie()
        try:
            cookie.load(value)
        except Exception:
            continue
        for index, morsel in enumerate(cookie.values()):
            # Cookie names and values may contain sensitive data. Evidence is flags only.
            label = f"Response cookie {index + 1}"
            if not morsel["httponly"]:
                found.append(finding("cookie_without_httponly", label + " lacks HttpOnly", "Set HttpOnly on session/auth cookies unless browser script access is explicitly necessary."))
            if urlsplit(url).scheme == "https" and not morsel["secure"]:
                found.append(finding("cookie_without_secure", label + " lacks Secure", "Set Secure for session/auth cookies delivered over HTTPS."))
            if not morsel["samesite"]:
                found.append(finding("cookie_without_samesite", label + " lacks SameSite", "Choose SameSite according to the application's cross-site flows and retain CSRF defenses."))
    return found


def request_evidence(url: str, scope: dict) -> dict:
    parsed = urlsplit(url)
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    # Resolve and validate every address before creating the socket, then pin one.
    address = resolved_address(parsed.hostname, port, scope)
    timeout = float(scope.get("timeout_seconds", 10))
    connection = PinnedHTTPSConnection(parsed.hostname, address, port, timeout) if parsed.scheme == "https" else http.client.HTTPConnection(address, port, timeout=timeout)
    target = (parsed.path or "/") + ("?" + parsed.query if parsed.query else "")
    try:
        connection.request("GET", target, headers={"Host": parsed.netloc, "User-Agent": "AuroraFox-AuthorizedConfigurationCheck/1.0"})
        response = connection.getresponse()
        headers = response.getheaders()
        limit = int(scope.get("max_response_bytes", 1024 * 1024))
        deadline = time.monotonic() + timeout
        chunks = []
        received = 0
        while received <= limit:
            if time.monotonic() >= deadline:
                raise TimeoutError("Owner response time budget reached")
            chunk = response.read1(limit + 1 - received)
            if not chunk:
                break
            chunks.append(chunk)
            received += len(chunk)
        payload = b"".join(chunks)
        # Do not persist URL queries, response bodies, Set-Cookie, tokens or redirects.
        evidence = {"target_sha256": canonical_hash(url), "origin": f"{parsed.scheme}://{parsed.netloc}",
                    "status": response.status, "received_bytes": min(len(payload), limit),
                    "body_sha256": hashlib.sha256(payload[:limit]).hexdigest(),
                    "body_truncated": len(payload) > limit, "findings": []}
        if 300 <= response.status < 400:
            evidence["outcome"] = "redirect_not_followed"
        elif response.status in {401, 402, 403, 407, 451}:
            evidence["outcome"] = "access_control_boundary"
        elif not 200 <= response.status < 300:
            evidence["outcome"] = "http_failure"
        else:
            evidence["outcome"] = "checked"
            evidence["findings"] = check_headers(url, headers)
        return evidence
    finally:
        connection.close()


def run(scope: dict, *, authorized: bool = False, baseline: dict | None = None) -> dict:
    urls = validate_scope(scope, authorized=authorized)
    scope_hash = canonical_hash(scope)
    if baseline is not None and baseline.get("scope_sha256") != scope_hash:
        raise ScopeError("Retest scope differs from baseline; review and authorize a new baseline")
    # Preflight all DNS/private boundaries before the first request.
    for url in urls:
        p = urlsplit(url)
        resolved_address(p.hostname, p.port or (443 if p.scheme == "https" else 80), scope)
    report = {"schema": "aurorafox.security-evidence.v1", "scope_sha256": scope_hash,
              "authorized_at": datetime.now(timezone.utc).isoformat(),
              "method": "bounded GET; HTTP configuration checks only",
              "coverage": "No exploit, authenticated-flow, code, injection or full penetration assessment performed",
              "results": []}
    for url in urls:
        validate_scope(scope, authorized=authorized)
        try:
            item = request_evidence(url, scope)
        except (OSError, ssl.SSLError, http.client.HTTPException, ScopeError, ValueError) as exc:
            # Exception strings may include target query/credentials. Persist type only.
            item = {"target_sha256": canonical_hash(url), "outcome": "transport_failure",
                    "error_type": type(exc).__name__, "findings": []}
        report["results"].append(item)
    if baseline is not None:
        prior = {x["target_sha256"]: x for x in baseline.get("results", [])}
        comparisons = []
        for item in report["results"]:
            old = prior.get(item["target_sha256"], {})
            if old.get("outcome") != "checked" or item.get("outcome") != "checked":
                comparisons.append({"target_sha256": item["target_sha256"], "outcome": "retest_inconclusive"})
                continue
            before = {x["id"] for x in old.get("findings", [])}
            after = {x["id"] for x in item.get("findings", [])}
            comparisons.append({"target_sha256": item["target_sha256"], "outcome": "compared",
                                "resolved": sorted(before - after), "remaining": sorted(before & after),
                                "new": sorted(after - before)})
        report["retest"] = comparisons
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", required=True, type=Path)
    parser.add_argument("--authorize", action="store_true", help="Owner explicitly authorizes this exact scope")
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        report = run(json.loads(args.scope.read_text(encoding="utf-8")), authorized=args.authorize,
                     baseline=json.loads(args.baseline.read_text(encoding="utf-8")) if args.baseline else None)
    except (ScopeError, ValueError) as exc:
        parser.error(str(exc))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(args.output)
    return 0 if all(x["outcome"] == "checked" for x in report["results"]) else 2


if __name__ == "__main__":
    raise SystemExit(main())
