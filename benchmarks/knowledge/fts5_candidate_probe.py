"""Offline, disposable FTS5 feasibility probe for AuroraFox JSONL Knowledge.

This is deliberately separate from KnowledgeStore and never opens user:// data.
Run with --rows to generate synthetic records, build a disposable index, and
compare repeated indexed queries with a full JSONL scan.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import struct
import tempfile
import time
from pathlib import Path


def build_index(source: Path, target: Path, offsets: Path, tokenizer: str, contentless: bool, detail_none: bool) -> tuple[int, float]:
    start = time.perf_counter()
    db = sqlite3.connect(target)
    try:
        if tokenizer not in {"unicode61", "trigram"}:
            raise ValueError("unsupported tokenizer")
        extra = ", content=''" if contentless else ""
        if detail_none:
            extra += ", detail=none"
        db.execute(
            "CREATE VIRTUAL TABLE knowledge USING fts5("
            f"source UNINDEXED, kind UNINDEXED, text, tokenize='{tokenizer}'{extra})"
        )
        batch: list[tuple[str, str, str]] = []
        count = 0
        with source.open("rb") as handle, offsets.open("wb") as offset_handle:
            while line := handle.readline():
                position = handle.tell() - len(line)
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(row, dict) or not isinstance(row.get("text"), str):
                    continue
                offset_handle.write(struct.pack("<Q", position))
                batch.append((str(row.get("source", "")), str(row.get("kind", "")), row["text"]))
                if len(batch) >= 1000:
                    db.executemany("INSERT INTO knowledge(source,kind,text) VALUES(?,?,?)", batch)
                    count += len(batch)
                    batch.clear()
        if batch:
            db.executemany("INSERT INTO knowledge(source,kind,text) VALUES(?,?,?)", batch)
            count += len(batch)
        db.commit()
        return count, time.perf_counter() - start
    finally:
        db.close()


def search_index(source: Path, target: Path, offsets: Path, term: str, detail_none: bool) -> tuple[int, int, float]:
    start = time.perf_counter()
    query = " AND ".join(f'"{term[i:i + 3]}"' for i in range(len(term) - 2)) if detail_none else f'"{term}"'
    with sqlite3.connect(target) as db:
        rows = db.execute("SELECT rowid FROM knowledge WHERE knowledge MATCH ?", (query,)).fetchall()
    verified = 0
    with source.open("rb") as data, offsets.open("rb") as pointers:
        for (rowid,) in rows:
            pointers.seek((rowid - 1) * 8)
            pointer = struct.unpack("<Q", pointers.read(8))[0]
            data.seek(pointer)
            row = json.loads(data.readline())
            if term in row["text"].casefold():
                verified += 1
    return verified, len(rows), time.perf_counter() - start


def search_scan(source: Path, term: str) -> tuple[int, float]:
    start = time.perf_counter()
    found = 0
    with source.open(encoding="utf-8") as handle:
        for line in handle:
            row = json.loads(line)
            if term in row["text"].casefold():
                found += 1
    return found, time.perf_counter() - start


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rows", type=int, default=100_000)
    parser.add_argument("--tokenizer", choices=("unicode61", "trigram"), default="unicode61")
    parser.add_argument("--contentless", action="store_true")
    parser.add_argument("--detail-none", action="store_true")
    args = parser.parse_args()
    if args.rows < 1:
        parser.error("--rows must be positive")
    with tempfile.TemporaryDirectory(prefix="aurorafox-fts5-") as directory:
        root = Path(directory)
        source, target, offsets = root / "synthetic.jsonl", root / "synthetic.sqlite3", root / "offsets.bin"
        with source.open("w", encoding="utf-8") as handle:
            for number in range(args.rows):
                text = f"Synthetic note {number}: local offline knowledge and reproducible evidence."
                if number == args.rows // 2:
                    text += " uniqueauroratoken"
                if number == args.rows // 3:
                    text += " aur uro ror ora rat ato tok oke ken"
                handle.write(json.dumps({"source": "synthetic", "kind": "fact", "text": text}) + "\n")
        count, build_seconds = build_index(source, target, offsets, args.tokenizer, args.contentless, args.detail_none)
        term = "auroratoken" if args.tokenizer == "trigram" else "uniqueauroratoken"
        indexed_hits, candidates, indexed_seconds = search_index(source, target, offsets, term, args.detail_none)
        scanned_hits, scanned_seconds = search_scan(source, term)
        assert count == args.rows and indexed_hits == scanned_hits == 1
        print(json.dumps({
            "rows": count,
            "tokenizer": args.tokenizer,
            "contentless": args.contentless,
            "detail_none": args.detail_none,
            "term": term,
            "jsonl_bytes": source.stat().st_size,
            "index_bytes": target.stat().st_size,
            "offset_bytes": offsets.stat().st_size,
            "build_seconds": round(build_seconds, 3),
            "indexed_query_ms": round(indexed_seconds * 1000, 3),
            "full_scan_ms": round(scanned_seconds * 1000, 3),
            "hits": indexed_hits,
            "candidates": candidates,
            "synthetic_only": True,
        }))


if __name__ == "__main__":
    main()
