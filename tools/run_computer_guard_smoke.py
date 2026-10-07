"""Run real Godot guard against the actual authenticated Computer sidecar."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
TOKEN = "computer-guard-isolated-fixture-token"
IDS = ("guard-master", "guard-transport", "guard-uncertain", "guard-shutdown")


def run(godot):
    with tempfile.TemporaryDirectory(prefix="aurora-computer-guard-") as directory:
        sandbox = Path(directory)
        (sandbox / "owned.py").write_text("from pathlib import Path\nimport time,sys\nPath('started-'+sys.argv[1]).write_text('yes')\nwhile True:\n Path('heartbeat').write_text(str(time.time_ns()))\n time.sleep(0.02)\n")
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        url = f"http://127.0.0.1:{port}"
        env = dict(os.environ, AURORAFOX_COMPUTER_TOKEN=TOKEN, AURORAFOX_SANDBOX_ROOT=directory, AURORAFOX_ALLOW_DEGRADED_LOCAL_SANDBOX="1")
        with tempfile.TemporaryFile() as logs:
            backend = subprocess.Popen([sys.executable, "-m", "uvicorn", "computer.computer_service:app", "--host", "127.0.0.1", "--port", str(port), "--log-level", "warning"], cwd=ROOT, env=env, stdout=logs, stderr=logs)
            try:
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if backend.poll() is not None: raise RuntimeError("Computer fixture backend exited")
                    try:
                        with urlopen(url + "/health", timeout=0.2) as response:
                            if response.status == 200: break
                    except OSError: time.sleep(0.02)
                else: raise RuntimeError("Computer fixture health deadline exceeded")
                godot_env = dict(os.environ, AURORAFOX_GUARD_URL=url, AURORAFOX_GUARD_TOKEN=TOKEN, AURORAFOX_GUARD_PYTHON=sys.executable, AURORAFOX_GUARD_ROOT=directory)
                result = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script", "tests/computer_request_guard_smoke.gd"], env=godot_env, timeout=30)
                return result.returncode
            finally:
                for execution_id in IDS:
                    request = Request(url + "/sandbox/cancel", data=json.dumps({"execution_id": execution_id}).encode(), headers={"Content-Type": "application/json", "X-AuroraFox-Computer-Token": TOKEN}, method="POST")
                    try:
                        with urlopen(request, timeout=10) as response: response.read()
                    except OSError: pass
                backend.terminate()
                try: backend.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    backend.kill()
                    backend.wait(timeout=5)
                if backend.returncode not in (0, -15):
                    logs.seek(0)
                    print(logs.read().decode(errors="replace"), file=sys.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot")
    raise SystemExit(run(parser.parse_args().godot))
