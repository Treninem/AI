from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from api.auth import DEFAULT_SCOPES, KeyStore


def root() -> Path:
    user_root = Path(os.getenv("AURORAFOX_USER_DIR", str(Path.home() / ".aurorafox"))).resolve()
    return user_root / "api"


def main() -> int:
    parser = argparse.ArgumentParser(prog="aurorafox-api-key")
    sub = parser.add_subparsers(dest="command", required=True)

    create = sub.add_parser("create")
    create.add_argument("name")
    create.add_argument("--scopes", default=",".join(DEFAULT_SCOPES))

    sub.add_parser("list")

    revoke = sub.add_parser("revoke")
    revoke.add_argument("key_id")

    args = parser.parse_args()
    store = KeyStore(root())

    if args.command == "create":
        scopes = [x.strip() for x in args.scopes.split(",") if x.strip()]
        token, record = store.create(args.name, scopes)
        clean = dict(record)
        clean.pop("token_hash", None)
        print(json.dumps({"api_key": token, "key": clean}, ensure_ascii=False, indent=2))
        return 0

    if args.command == "list":
        print(json.dumps({"keys": store.list()}, ensure_ascii=False, indent=2))
        return 0

    if args.command == "revoke":
        ok = store.revoke(args.key_id)
        print(json.dumps({"revoked": ok, "key_id": args.key_id}, ensure_ascii=False))
        return 0 if ok else 2

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
