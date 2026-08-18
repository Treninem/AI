from pathlib import Path
import runpy

# Backwards-compatible entry point used by older AuroraFox installs.
# The real implementation lives in voice/python/aurora_voice_server.py.
SERVER = Path(__file__).resolve().parent / "python" / "aurora_voice_server.py"
runpy.run_path(str(SERVER), run_name="__main__")
