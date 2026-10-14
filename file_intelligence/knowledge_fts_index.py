"""Optional Windows Knowledge JSONL index candidate.

This module never changes the source JSONL. Callers must fall back to the
canonical KnowledgeStore scan when the index is absent, stale, or unsupported.
"""

from __future__ import annotations

import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import tempfile


class IndexUnavailable(Exception):
    """The canonical scan must be used for this request."""


def _sample_digest(source: Path) -> str:
    """Cheap change detector; app-owned writes must also invalidate the index."""
    size = source.stat().st_size
    digest = hashlib.sha256()
    with source.open("rb") as handle:
        for position in (0, max(0, size // 2 - 2048), max(0, size - 4096)):
            handle.seek(position)
            digest.update(handle.read(4096))
    return digest.hexdigest()


def _source_state(source: Path) -> tuple[int, int, str, str, str]:
    before = source.stat()
    sample = _sample_digest(source)
    after = source.stat()
    if (before.st_size, before.st_mtime_ns, before.st_dev, before.st_ino) != (
        after.st_size, after.st_mtime_ns, after.st_dev, after.st_ino
    ):
        raise IndexUnavailable("SOURCE_CHANGED")
    return after.st_size, after.st_mtime_ns, sample, str(after.st_dev), str(after.st_ino)


def build(source: Path, index: Path) -> int:
    """Build in the target directory, then publish a complete SQLite file."""
    source = source.resolve(strict=True)
    index = index.resolve()
    if source == index:
        raise ValueError("source and index must differ")
    index.parent.mkdir(parents=True, exist_ok=True)
    expected = _source_state(source)
    descriptor, temporary = tempfile.mkstemp(prefix=index.name + ".", suffix=".building", dir=index.parent)
    os.close(descriptor)
    temporary_path = Path(temporary)
    try:
        with closing(sqlite3.connect(temporary_path)) as db:
            db.execute("CREATE VIRTUAL TABLE chunks USING fts5(text, tokenize='trigram', content='', detail=none)")
            db.execute("CREATE TABLE locations(rowid INTEGER PRIMARY KEY, byte_offset INTEGER NOT NULL, source_lower TEXT NOT NULL, kind_lower TEXT NOT NULL)")
            db.execute("CREATE TABLE source_state(path TEXT NOT NULL, size INTEGER NOT NULL, mtime_ns INTEGER NOT NULL, sample_sha256 TEXT NOT NULL, device TEXT NOT NULL, file_id TEXT NOT NULL)")
            count = 0
            with source.open("rb") as handle:
                while line := handle.readline():
                    offset = handle.tell() - len(line)
                    try:
                        item = json.loads(line)
                    except (UnicodeDecodeError, json.JSONDecodeError):
                        continue
                    if not isinstance(item, dict) or not isinstance(item.get("text"), str):
                        continue
                    count += 1
                    db.execute("INSERT INTO chunks(rowid,text) VALUES(?,?)", (count, item["text"]))
                    db.execute(
                        "INSERT INTO locations(rowid,byte_offset,source_lower,kind_lower) VALUES(?,?,?,?)",
                        (count, offset, str(item.get("source", "")).lower(), str(item.get("kind", "")).lower()),
                    )
            if _source_state(source) != expected:
                raise IndexUnavailable("SOURCE_CHANGED")
            db.execute(
                "INSERT INTO source_state(path,size,mtime_ns,sample_sha256,device,file_id) VALUES(?,?,?,?,?,?)",
                (str(source), *expected),
            )
            db.commit()
            if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                raise IndexUnavailable("INDEX_INTEGRITY")
        if _source_state(source) != expected:
            raise IndexUnavailable("SOURCE_CHANGED")
        os.replace(temporary_path, index)
        return count
    finally:
        temporary_path.unlink(missing_ok=True)


def _fts_term(term: str) -> str:
    trigrams = dict.fromkeys(term[pos:pos + 3] for pos in range(len(term) - 2))
    return "(" + " AND ".join('"' + trigram.replace('"', '""') + '"' for trigram in trigrams) + ")"


def search(source: Path, index: Path, query: str, limit: int = 2) -> list[dict]:
    source = source.resolve(strict=True)
    if limit < 1 or limit > 256:
        raise ValueError("limit outside supported range")
    normalized = query.lower().strip()
    terms = [term for term in normalized.split(" ") if len(term) >= 2]
    if not terms or any(len(term) < 3 for term in terms):
        raise IndexUnavailable("SHORT_QUERY")
    before = _source_state(source)
    try:
        with closing(sqlite3.connect(index.resolve().as_uri() + "?mode=ro", uri=True)) as db:
            state = db.execute("SELECT path,size,mtime_ns,sample_sha256,device,file_id FROM source_state").fetchone()
            if state != (str(source), *before):
                raise IndexUnavailable("STALE_INDEX")
            match = " OR ".join(_fts_term(term) for term in terms)
            candidates = dict(db.execute(
                "SELECT chunks.rowid,locations.byte_offset FROM chunks JOIN locations ON locations.rowid=chunks.rowid WHERE chunks MATCH ?",
                (match,),
            ).fetchall())
            for term in terms:
                candidates.update(db.execute(
                    "SELECT rowid,byte_offset FROM locations WHERE instr(source_lower,?)>0 OR instr(kind_lower,?)>0",
                    (term, term),
                ).fetchall())
    except sqlite3.Error as error:
        raise IndexUnavailable("INDEX_UNAVAILABLE") from error
    ranked: list[tuple[int, int, dict]] = []
    with source.open("rb") as handle:
        for rowid, offset in candidates.items():
            handle.seek(offset)
            try:
                item = json.loads(handle.readline())
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise IndexUnavailable("SOURCE_CHANGED") from error
            if not isinstance(item, dict):
                raise IndexUnavailable("SOURCE_CHANGED")
            text = str(item.get("text", "")).lower()
            source_name = str(item.get("source", "")).lower()
            kind = str(item.get("kind", "")).lower()
            score = (5 if normalized in text else 0) + sum(
                (2 if term in text else 0) + (1 if term in source_name else 0) + (1 if term in kind else 0)
                for term in terms
            )
            if score > 0:
                ranked.append((score, rowid, item))
    if _source_state(source) != before:
        raise IndexUnavailable("SOURCE_CHANGED")
    ranked.sort(key=lambda entry: (-entry[0], entry[1]))
    return [item for _, _, item in ranked[:limit]]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("build", "search"))
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--index", required=True, type=Path)
    parser.add_argument("--query", default="")
    parser.add_argument("--limit", type=int, default=2)
    args = parser.parse_args()
    try:
        if args.action == "build":
            print(json.dumps({"ok": True, "indexed_rows": build(args.source, args.index)}))
        else:
            print(json.dumps({"ok": True, "results": search(args.source, args.index, args.query, args.limit)}, ensure_ascii=False))
        return 0
    except (IndexUnavailable, OSError, ValueError, sqlite3.Error) as error:
        print(json.dumps({"ok": False, "error": str(error) if isinstance(error, IndexUnavailable) else "INDEX_UNAVAILABLE"}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
