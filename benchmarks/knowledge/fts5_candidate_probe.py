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


def build_index(source: Path, target: Path, offsets: Path, tokenizer: str, contentless: bool, detail_none: bool, offsets_sql: bool, text_field: str) -> tuple[int, float]:
    start = time.perf_counter()
    source_before = source.stat()
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
        if offsets_sql:
            db.execute("CREATE TABLE offsets(rowid INTEGER PRIMARY KEY, byte_offset INTEGER NOT NULL)")
            db.execute("CREATE TABLE source_state(size INTEGER NOT NULL, mtime_ns INTEGER NOT NULL)")
        batch: list[tuple[str, str, str]] = []
        batch_offsets: list[tuple[int, int]] = []
        count = 0
        with source.open("rb") as handle, offsets.open("wb") as offset_handle:
            while line := handle.readline():
                position = handle.tell() - len(line)
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(row, dict) or not isinstance(row.get(text_field), str):
                    continue
                if offsets_sql:
                    batch_offsets.append((count + len(batch) + 1, position))
                else:
                    offset_handle.write(struct.pack("<Q", position))
                batch.append((str(row.get("source", "")), str(row.get("kind", "")), row[text_field]))
                if len(batch) >= 1000:
                    db.executemany("INSERT INTO knowledge(source,kind,text) VALUES(?,?,?)", batch)
                    if offsets_sql:
                        db.executemany("INSERT INTO offsets(rowid,byte_offset) VALUES(?,?)", batch_offsets)
                    count += len(batch)
                    batch.clear()
                    batch_offsets.clear()
        if batch:
            db.executemany("INSERT INTO knowledge(source,kind,text) VALUES(?,?,?)", batch)
            if offsets_sql:
                db.executemany("INSERT INTO offsets(rowid,byte_offset) VALUES(?,?)", batch_offsets)
            count += len(batch)
        source_after = source.stat()
        if (source_before.st_size, source_before.st_mtime_ns) != (source_after.st_size, source_after.st_mtime_ns):
            raise RuntimeError("source changed during index build")
        if offsets_sql:
            db.execute("INSERT INTO source_state(size,mtime_ns) VALUES(?,?)", (source_after.st_size, source_after.st_mtime_ns))
        db.commit()
        return count, time.perf_counter() - start
    finally:
        db.close()


def search_index(source: Path, target: Path, offsets: Path, term: str, detail_none: bool, offsets_sql: bool, text_field: str) -> tuple[int, int, float]:
    start = time.perf_counter()
    query = " AND ".join(f'"{term[i:i + 3]}"' for i in range(len(term) - 2)) if detail_none else f'"{term}"'
    with sqlite3.connect(target) as db:
        if offsets_sql:
            expected = db.execute("SELECT size,mtime_ns FROM source_state").fetchone()
            current = source.stat()
            if expected != (current.st_size, current.st_mtime_ns):
                raise RuntimeError("stale Knowledge index")
            rows = db.execute(
                "SELECT knowledge.rowid,offsets.byte_offset FROM knowledge JOIN offsets ON offsets.rowid=knowledge.rowid "
                "WHERE knowledge MATCH ?", (query,)
            ).fetchall()
        else:
            rows = db.execute("SELECT rowid FROM knowledge WHERE knowledge MATCH ?", (query,)).fetchall()
    verified = 0
    with source.open("rb") as data, offsets.open("rb") as pointers:
        for row in rows:
            if offsets_sql:
                pointer = row[1]
            else:
                pointers.seek((row[0] - 1) * 8)
                pointer = struct.unpack("<Q", pointers.read(8))[0]
            data.seek(pointer)
            row = json.loads(data.readline())
            if term in row[text_field].casefold():
                verified += 1
    if offsets_sql:
        current = source.stat()
        if expected != (current.st_size, current.st_mtime_ns):
            raise RuntimeError("source changed during index query")
    return verified, len(rows), time.perf_counter() - start


def search_scan(source: Path, term: str, text_field: str) -> tuple[int, float]:
    start = time.perf_counter()
    found = 0
    with source.open(encoding="utf-8") as handle:
        for line in handle:
            row = json.loads(line)
            if term in row[text_field].casefold():
                found += 1
    return found, time.perf_counter() - start


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rows", type=int, default=100_000)
    parser.add_argument("--tokenizer", choices=("unicode61", "trigram"), default="unicode61")
    parser.add_argument("--contentless", action="store_true")
    parser.add_argument("--detail-none", action="store_true")
    parser.add_argument("--offsets-sql", action="store_true")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--text-field", choices=("text", "content"), default="text")
    parser.add_argument("--term", action="append", default=[])
    args = parser.parse_args()
    if args.rows < 1:
        parser.error("--rows must be positive")
    with tempfile.TemporaryDirectory(prefix="aurorafox-fts5-") as directory:
        root = Path(directory)
        source, target, offsets = args.source or root / "synthetic.jsonl", root / "synthetic.sqlite3", root / "offsets.bin"
        if args.source is None:
            with source.open("w", encoding="utf-8") as handle:
                for number in range(args.rows):
                    text = f"Synthetic note {number}: local offline knowledge and reproducible evidence."
                    if number == args.rows // 2:
                        text += " uniqueauroratoken"
                    if number == args.rows // 3:
                        text += " aur uro ror ora rat ato tok oke ken"
                    handle.write(json.dumps({"source": "synthetic", "kind": "fact", "text": text}) + "\n")
        elif not source.is_file() or not args.term or any(len(term) < 3 or len(term) > 200 for term in args.term):
            parser.error("external source requires an existing file and 3-200 character --term values")
        count, build_seconds = build_index(source, target, offsets, args.tokenizer, args.contentless, args.detail_none, args.offsets_sql, args.text_field)
        terms = [term.casefold() for term in args.term] if args.source else ["auroratoken" if args.tokenizer == "trigram" else "uniqueauroratoken"]
        queries = []
        for term in terms:
            indexed_hits, candidates, indexed_seconds = search_index(source, target, offsets, term, args.detail_none, args.offsets_sql, args.text_field)
            scanned_hits, scanned_seconds = search_scan(source, term, args.text_field)
            assert indexed_hits == scanned_hits and (args.source is not None or (count == args.rows and indexed_hits == 1))
            queries.append({
                "term": term,
                "indexed_query_ms": round(indexed_seconds * 1000, 3),
                "full_scan_ms": round(scanned_seconds * 1000, 3),
                "hits": indexed_hits,
                "candidates": candidates,
            })
        print(json.dumps({
            "rows": count,
            "external_source": args.source is not None,
            "tokenizer": args.tokenizer,
            "contentless": args.contentless,
            "detail_none": args.detail_none,
            "offsets_sql": args.offsets_sql,
            "jsonl_bytes": source.stat().st_size,
            "index_bytes": target.stat().st_size,
            "offset_bytes": offsets.stat().st_size,
            "build_seconds": round(build_seconds, 3),
            "queries": queries,
            "synthetic_only": args.source is None,
        }))
        if args.offsets_sql and args.source is None:
            with source.open("a", encoding="utf-8") as handle:
                handle.write('{"source":"synthetic","kind":"fact","text":"mutation"}\n')
            try:
                search_index(source, target, offsets, terms[0], args.detail_none, True, args.text_field)
            except RuntimeError as error:
                assert str(error) == "stale Knowledge index"
                print("STALE_INDEX_REJECTED")
            else:
                raise AssertionError("stale Knowledge index was accepted")


if __name__ == "__main__":
    main()
