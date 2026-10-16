from __future__ import annotations

import os
import socket
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "file_intelligence" / "file_service.py"


def test_file_service_binds_without_standard_streams(tmp_path: Path) -> None:
    with socket.socket() as reserve:
        reserve.bind(("127.0.0.1", 0))
        port = reserve.getsockname()[1]

    profile = tmp_path / "private-profile"
    profile.mkdir()
    trace = tmp_path / "startup-trace.txt"
    env = os.environ.copy()
    env.update({
        "AURORAFOX_USER_DIR": str(profile),
        "AURORAFOX_LOCAL_SERVICES_PORT": str(port),
        "AURORAFOX_FILES_PORT": str(port),
    })
    env["PYTHONPATH"] = os.pathsep.join(filter(None, [str(SERVICE.parent), env.get("PYTHONPATH", "")]))
    script = """
import runpy
import sys
import traceback
from pathlib import Path

source, trace = map(Path, sys.argv[1:3])
sys.stdout = None
sys.stderr = None
try:
    runpy.run_path(str(source), run_name="__main__")
except BaseException:
    with trace.open("w", encoding="utf-8") as output:
        traceback.print_exc(file=output)
"""
    proc = subprocess.Popen(
        [sys.executable, "-c", script, str(SERVICE), str(trace)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env,
        cwd=ROOT,
    )
    try:
        deadline = time.monotonic() + 15
        ready = False
        while time.monotonic() < deadline and proc.poll() is None:
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                    ready = True
                    break
            except OSError:
                time.sleep(0.1)
        diagnostic = trace.read_text(encoding="utf-8") if trace.exists() else ""
        assert ready, f"File service exited={proc.poll()} before binding without standard streams: {diagnostic}"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
