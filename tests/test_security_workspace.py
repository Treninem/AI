"""Real loopback lab: configuration findings, remediation and retest."""
import json
import hashlib
import subprocess
import sys
import tempfile
from pathlib import Path
import threading
import unittest
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

from security_workspace.runner import ScopeError, run


class Handler(BaseHTTPRequestHandler):
    fixed = False
    requests_seen = 0
    def do_GET(self):
        type(self).requests_seen += 1
        if self.path.startswith('/redirect'):
            self.send_response(302)
            self.send_header('Location', 'http://out-of-scope.invalid/SECRET')
        elif self.path.startswith('/protected'):
            self.send_response(401)
        else:
            self.send_response(200)
            if self.fixed:
                self.send_header('Content-Security-Policy', "default-src 'self'; frame-ancestors 'none'")
                self.send_header('X-Content-Type-Options', 'nosniff')
                self.send_header('Set-Cookie', 'session=TOP_SECRET_COOKIE; HttpOnly; SameSite=Lax')
            else:
                self.send_header('Set-Cookie', 'session=TOP_SECRET_COOKIE')
        self.end_headers()
        self.wfile.write(b'PRIVATE_RESPONSE_BODY')
    def log_message(self, *_args):
        pass


class SecurityWorkspaceTests(unittest.TestCase):
    def test_cli_binds_evidence_to_exact_reviewed_file_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            scope_path = Path(directory) / "scope.json"
            output = Path(directory) / "evidence.json"
            scope_bytes = (json.dumps(self.scope, ensure_ascii=False, indent=2) + "\n").encode()
            scope_path.write_bytes(scope_bytes)
            command = [sys.executable, "-m", "security_workspace.runner", "--scope", str(scope_path),
                       "--authorize", "--output", str(output)]
            completed = subprocess.run(command, capture_output=True, timeout=15)
            self.assertEqual(completed.returncode, 0, completed.stderr.decode())
            evidence = json.loads(output.read_text())
            self.assertEqual(evidence["scope_file_sha256"], hashlib.sha256(scope_bytes).hexdigest())
            self.assertEqual(len(evidence["results"]), len(self.scope["urls"]))
            self.assertGreater(Handler.requests_seen, 0)

    def setUp(self):
        Handler.fixed = False
        Handler.requests_seen = 0
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.origin = 'http://127.0.0.1:' + str(self.server.server_port)
        self.scope = {'authorization_reference': 'self-owned ephemeral test lab',
                      'expires_at': (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat(),
                      'allowed_origins': [self.origin], 'urls': [self.origin + '/?token=QUERY_SECRET'],
                      'allow_private_lab': True, 'max_requests': 1,
                      'max_response_bytes': 8, 'timeout_seconds': 2}
    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def test_actual_findings_remediation_retest_and_redaction(self):
        before = run(self.scope, authorized=True)
        ids = {x['id'] for x in before['results'][0]['findings']}
        self.assertTrue({'missing_csp', 'missing_nosniff', 'missing_frame_policy', 'cookie_without_httponly', 'cookie_without_samesite'} <= ids)
        self.assertTrue(before['results'][0]['body_truncated'])
        encoded = json.dumps(before)
        for secret in ['TOP_SECRET_COOKIE', 'QUERY_SECRET', 'PRIVATE_RESPONSE_BODY']:
            self.assertNotIn(secret, encoded)
        Handler.fixed = True
        after = run(self.scope, authorized=True, baseline=before)
        self.assertEqual(after['results'][0]['findings'], [])
        self.assertEqual(set(after['retest'][0]['resolved']), ids)
        self.assertEqual(Handler.requests_seen, 2)

    def test_denied_expired_and_out_of_scope_issue_no_requests(self):
        with self.assertRaises(ScopeError): run(self.scope)
        expired = dict(self.scope, expires_at='2000-01-01T00:00:00Z')
        with self.assertRaises(ScopeError): run(expired, authorized=True)
        outside = dict(self.scope, allowed_origins=[])
        with self.assertRaises(ScopeError): run(outside, authorized=True)
        with self.assertRaises(ScopeError): run(dict(self.scope, allow_private_lab=False), authorized=True)
        self.assertEqual(Handler.requests_seen, 0)

    def test_redirect_and_access_control_are_not_followed_or_graded(self):
        for path, outcome in [('/redirect', 'redirect_not_followed'), ('/protected', 'access_control_boundary')]:
            scoped = dict(self.scope, urls=[self.origin + path])
            report = run(scoped, authorized=True)
            self.assertEqual(report['results'][0]['outcome'], outcome)
            self.assertEqual(report['results'][0]['findings'], [])
        self.assertEqual(Handler.requests_seen, 2)

    def test_changed_scope_and_failed_retest_cannot_claim_remediation(self):
        before = run(self.scope, authorized=True)
        with self.assertRaises(ScopeError): run(dict(self.scope, max_response_bytes=9), authorized=True, baseline=before)
        with patch('security_workspace.runner.request_evidence', side_effect=OSError('QUERY_SECRET')):
            report = run(self.scope, authorized=True, baseline=before)
        self.assertEqual(report['retest'][0]['outcome'], 'retest_inconclusive')
        self.assertNotIn('QUERY_SECRET', json.dumps(report))


if __name__ == '__main__':
    unittest.main()
