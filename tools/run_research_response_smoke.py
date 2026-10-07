"""Run the real Godot research request against an isolated loopback HTTP server."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import os
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = b"x" * (2 * 1024 * 1024 + 1)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/slow":
            time.sleep(1.25)
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(PAYLOAD)))
        self.end_headers()
        try:
            self.wfile.write(PAYLOAD)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Expected when Godot rejects the deliberately oversized body.

    def log_message(self, *_args):
        pass


def run(godot: str) -> int:
    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            env = dict(os.environ, AURORAFOX_RESEARCH_FIXTURE_URL=f"http://127.0.0.1:{server.server_port}/payload")
            result = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script", "tests/research_response_owner_smoke.gd"], env=env, timeout=30)
            return result.returncode
        finally:
            server.shutdown()
            thread.join(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot")
    raise SystemExit(run(parser.parse_args().godot))
