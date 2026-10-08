"""Exercise production Godot HTTPClient with genuine fragmented local SSE responses."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def event(data: dict) -> bytes:
    return ("data: " + json.dumps(data, ensure_ascii=False) + "\r\n\r\n").encode()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        kind = data['fixture']
        self.fixture_started = time.monotonic()
        self.fixture_events = []
        terminal_error = ""
        self.send_response(503 if kind == 'http_error' else 200)
        self.send_header('Content-Type', 'text/event-stream; charset=utf-8')
        self.send_header('Transfer-Encoding', 'chunked')
        self.end_headers()
        print('AURORA_CORE_HTTP_SERVER_START ' + json.dumps({'fixture': kind, 'elapsed_seconds': round(time.monotonic() - self.fixture_started, 6)}), flush=True)
        try:
            if kind == 'malformed':
                self.send(b'data: {broken}\n\n')
            elif kind == 'truncated':
                self.send(event({'choices': [{'delta': {'content': 'partial'}, 'finish_reason': None}]}))
            else:
                for i in range(1, 9):
                    if kind == 'heartbeat':
                        self.send(b': ping\n\n')
                    else:
                        self.send(event({'prompt_progress': {'processed': 1 if kind == 'duplicate' else i, 'total': 8}, 'choices': []}))
                    time.sleep(0.06)
                # Split UTF8 within a codepoint; HTTP chunk framing must not corrupt text.
                message = event({'choices': [{'index': 0, 'delta': {'content': 'Привет 🌍'}, 'finish_reason': None}]})
                split = message.index('Привет'.encode()) + 1
                self.send(message[:split]); self.send(message[split:])
                self.send(event({'choices': [{'delta': {}, 'finish_reason': 'stop'}]}))
                self.send(b'data: [DONE]\n\n')
            self.wfile.write(b'0\r\n\r\n'); self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError) as exc:
            terminal_error = type(exc).__name__  # Real client deadline/cancel closes the connection.
        finally:
            print('AURORA_CORE_HTTP_SERVER_TRACE ' + json.dumps({
                'fixture': kind, 'events': self.fixture_events,
                'elapsed_seconds': round(time.monotonic() - self.fixture_started, 6),
                'terminal_error': terminal_error,
            }), flush=True)

    def send(self, value: bytes):
        self.wfile.write(f'{len(value):x}\r\n'.encode() + value + b'\r\n')
        self.wfile.flush()
        self.fixture_events.append({'elapsed_seconds': round(time.monotonic() - self.fixture_started, 6), 'bytes': len(value)})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    smoke = subprocess.run([args.godot, '--headless', '--path', str(root), '--script', 'tests/core_progress_stream_smoke.gd'], timeout=15)
    if smoke.returncode:
        raise SystemExit(smoke.returncode)
    owner_smoke = subprocess.run([args.godot, '--headless', '--path', str(root), '--script', 'tests/owner_resource_limits_smoke.gd'], timeout=30)
    if owner_smoke.returncode:
        raise SystemExit(owner_smoke.returncode)
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        env = dict(os.environ, AURORAFOX_TEST_CORE_PORT=str(server.server_port))
        result = subprocess.run([args.godot, '--headless', '--path', str(root), '--script', 'tests/core_progress_http_smoke.gd'], env=env, timeout=30)
        if result.returncode:
            raise SystemExit(result.returncode)
    finally:
        server.shutdown(); server.server_close(); thread.join()


if __name__ == '__main__':
    main()
