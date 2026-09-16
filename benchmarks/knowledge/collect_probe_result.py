#!/usr/bin/env python3
"""Extract one AuroraFox benchmark probe payload from a text log."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--require-true", action="append", default=[])
    args = parser.parse_args()

    text = args.log.read_text(encoding="utf-8", errors="replace")
    payload = None
    for line in reversed(text.splitlines()):
        if line.startswith(args.prefix):
            payload = json.loads(line[len(args.prefix) :])
            break
    if not isinstance(payload, dict):
        raise SystemExit(f"probe result marker missing: {args.prefix}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    failed = [key for key in args.require_true if payload.get(key) is not True]
    if failed:
        print(json.dumps({"failed_required_true": failed, "payload": payload}, sort_keys=True))
        return 2
    print(json.dumps({"probe": args.output.name, "required_true": args.require_true, "ok": True}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
