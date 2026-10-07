from __future__ import annotations

import json
import socket
import socketserver
import threading
from contextlib import contextmanager

import pytest

from api.runtime_bridge import AuroraRuntimeBridge
from api.ollama_client import OllamaClient


@contextmanager
def bridge_peer(*, mismatch=False, payload='é' * 40):
    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            request = json.loads(self.rfile.readline())
            response = {'request_id': 'x' * 32 if mismatch else request['request_id'], 'value': payload}
            frame = (json.dumps(response, ensure_ascii=False) + '\n').encode()
            try:
                self.request.sendall(frame)
            except OSError:
                pass

    server = socketserver.TCPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.01}, daemon=True)
    thread.start()
    try:
        yield server.server_address[1]
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        assert not thread.is_alive()


@pytest.mark.parametrize('offset', [-1, 0, 10, None])
def test_real_bridge_frame_cap_and_zero_before_json_parse(tmp_path, monkeypatch, offset):
    monkeypatch.setenv('AURORAFOX_USER_DIR', str(tmp_path))
    frame_bytes = len((json.dumps({'request_id': '0' * 32, 'value': 'é' * 40}, ensure_ascii=False) + '\n').encode())
    budget = 0 if offset is None else frame_bytes + offset
    received = []
    original = socket.create_connection

    class TrackedSocket:
        def __init__(self, sock):
            self.sock = sock
        def __enter__(self):
            return self
        def __exit__(self, *args):
            self.sock.close()
        def settimeout(self, timeout):
            self.sock.settimeout(timeout)
        def sendall(self, raw):
            self.sock.sendall(raw)
        def recv(self, count):
            raw = self.sock.recv(count)
            received.append(len(raw))
            return raw

    monkeypatch.setattr(socket, 'create_connection', lambda *a, **kw: TrackedSocket(original(*a, **kw)))
    with bridge_peer() as port:
        client = AuroraRuntimeBridge(port=port, timeout=2, max_response_bytes=budget)
        if offset == -1:
            with pytest.raises(RuntimeError, match='exceeds owner byte budget'):
                client.request('status')
        else:
            assert client.request('status')['value'] == 'é' * 40
    assert sum(received) <= budget + 1 if budget else sum(received) == frame_bytes


def test_real_bridge_zero_timeouts_and_identity_guard(tmp_path, monkeypatch):
    monkeypatch.setenv('AURORAFOX_USER_DIR', str(tmp_path))
    observed = []
    original = socket.create_connection
    def connect(*args, **kwargs):
        observed.append(kwargs['timeout'])
        return original(*args, **kwargs)
    monkeypatch.setattr(socket, 'create_connection', connect)
    with bridge_peer(mismatch=True) as port:
        client = AuroraRuntimeBridge(port=port, timeout=0, connect_timeout=0, max_response_bytes=0)
        with pytest.raises(RuntimeError, match='request id mismatch'):
            client.request('status')
    assert observed == [None]


@pytest.mark.parametrize('value', [-1, float('nan'), float('inf'), True, 'invalid'])
def test_provider_invalid_time_policy_fails_visibly(tmp_path, monkeypatch, value):
    monkeypatch.setenv('AURORAFOX_USER_DIR', str(tmp_path))
    for factory, keyword in [(AuroraRuntimeBridge, 'timeout'), (AuroraRuntimeBridge, 'connect_timeout'),
                             (OllamaClient, 'discovery_timeout'), (OllamaClient, 'chat_timeout')]:
        with pytest.raises(ValueError, match='finite and nonnegative'):
            factory(**{keyword: value})


def test_provider_environment_defaults_zero_and_explicit_override(tmp_path, monkeypatch):
    monkeypatch.setenv('AURORAFOX_USER_DIR', str(tmp_path))
    bridge = AuroraRuntimeBridge()
    assert (bridge.timeout, bridge.connect_timeout, bridge.max_response_bytes) == (180, 8, 8 * 1024 * 1024)
    client = OllamaClient()
    assert client.discovery_timeout is None and client.chat_timeout == 180
    for key in ('AURORAFOX_API_BRIDGE_READ_SECONDS', 'AURORAFOX_API_BRIDGE_CONNECT_SECONDS',
                'AURORAFOX_API_BRIDGE_RESPONSE_BYTES', 'AURORAFOX_API_OLLAMA_DISCOVERY_SECONDS',
                'AURORAFOX_API_OLLAMA_CHAT_SECONDS'):
        monkeypatch.setenv(key, '0')
    bridge = AuroraRuntimeBridge()
    assert (bridge.timeout, bridge.connect_timeout, bridge.max_response_bytes) == (0, 0, 0)
    client = OllamaClient()
    assert (client.discovery_timeout, client.chat_timeout) == (0, 0)
    explicit = AuroraRuntimeBridge(timeout=600, connect_timeout=30, max_response_bytes=100)
    assert (explicit.timeout, explicit.connect_timeout, explicit.max_response_bytes) == (600, 30, 100)


@pytest.mark.parametrize('discovery,chat', [(0, 0), (0.5, 0.5), (10, 600)])
def test_real_ollama_owner_deadlines_override_legacy_discovery_call(tmp_path, monkeypatch, discovery, chat):
    from http.server import BaseHTTPRequestHandler, HTTPServer
    import requests
    monkeypatch.setenv('AURORAFOX_USER_DIR', str(tmp_path))
    observed = []
    timeouts = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_GET(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"models":[{"name":"qwen3:8b"}]}')
        def do_POST(self):
            observed.append(json.loads(self.rfile.read(int(self.headers['Content-Length']))))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"message":{"content":"actual provider reply"}}')

    original = requests.sessions.Session.send
    def send(session, request, **kwargs):
        timeouts.append(kwargs['timeout'])
        return original(session, request, **kwargs)
    monkeypatch.setattr(requests.sessions.Session, 'send', send)
    server = HTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.01}, daemon=True)
    thread.start()
    try:
        client = OllamaClient(f'http://127.0.0.1:{server.server_port}', discovery_timeout=discovery, chat_timeout=chat)
        assert client.models(timeout=0.75) == ['qwen3:8b']
        result = client.chat([{'role': 'user', 'content': 'hello'}])
        assert result['runtime'] == 'ollama'
        assert result['content'] == 'actual provider reply'
        assert timeouts == [discovery or None, discovery or None, chat or None]
        assert observed[0]['messages'] == [{'role': 'user', 'content': 'hello'}]
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        assert not thread.is_alive()
