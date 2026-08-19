from __future__ import annotations

import argparse
import json
import time
from datetime import datetime, timezone
from pathlib import Path

from self_audit import ROOT, audit

STATE_PATH = ROOT / "agent" / "state" / "progress.json"


def version_display() -> str:
    path = ROOT / "project" / "version.json"
    if not path.exists():
        return "V0.0.0.0"
    try:
        return str(json.loads(path.read_text(encoding="utf-8")).get("version", "V0.0.0.0"))
    except Exception:
        return "V0.0.0.0"


def mmss(seconds: float) -> str:
    value = max(0, int(seconds))
    return f"{value // 60:02d}:{value % 60:02d}"


def summarize(report: dict) -> tuple[str, str, str]:
    passed = [item["title"] for item in report.get("checks", []) if item.get("ok")]
    pending = [item["title"] for item in report.get("checks", []) if not item.get("ok")]
    percent = int(report.get("progress_percent", 0))
    if percent >= 100:
        state = "Релизная архитектура собрана"
    elif percent >= 85:
        state = "Финальная синхронизация и тесты"
    elif percent >= 60:
        state = "Основные автономные подсистемы соединены"
    elif percent >= 35:
        state = "Автономный контур достраивается"
    else:
        state = "Базовые узлы автономного развития подключаются"
    done = "; ".join(passed[-3:]) if passed else "аудит начат"
    left = "; ".join(pending[:3]) if pending else "финальный релизный прогон"
    return state, done, left


def snapshot(started: float) -> dict:
    report = audit()
    state, done, left = summarize(report)
    return {
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "elapsed": mmss(time.monotonic() - started),
        "version": version_display(),
        "percent": int(report.get("progress_percent", 0)),
        "ready": bool(report.get("ready", False)),
        "state": state,
        "done": done,
        "left": left,
        "audit": report,
    }


def render(item: dict) -> str:
    return (
        f"🦊 [{item['elapsed']}] AuroraFox {item['version']}: {item['percent']}% до релиза. "
        f"{item['state']}. Сделано: {item['done']}. Осталось: {item['left']}."
    )


def persist(item: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(item, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="AuroraFox real-time release progress reporter")
    parser.add_argument("--watch", action="store_true", help="Keep reporting at the requested interval")
    parser.add_argument("--interval", type=int, default=60, help="Seconds between reports; default 60")
    parser.add_argument("--count", type=int, default=0, help="Stop after N reports; 0 means unlimited in watch mode")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--no-state", action="store_true")
    args = parser.parse_args()

    interval = max(60, args.interval) if args.watch else max(1, args.interval)
    started = time.monotonic()
    emitted = 0
    while True:
        item = snapshot(started)
        if not args.no_state:
            persist(item)
        print(json.dumps(item, ensure_ascii=False) if args.json else render(item), flush=True)
        emitted += 1
        if not args.watch or (args.count > 0 and emitted >= args.count):
            return 0 if item["ready"] else 2
        time.sleep(interval)


if __name__ == "__main__":
    raise SystemExit(main())
