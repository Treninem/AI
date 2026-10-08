from __future__ import annotations

import json
import os
import re
import sqlite3
import time
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

HOST = os.getenv("AURORAFOX_INDEX_HOST", "127.0.0.1")
PORT = int(os.getenv("AURORAFOX_INDEX_PORT", "8768"))
USER_ROOT = Path(os.getenv("AURORAFOX_USER_DIR", str(Path.home() / ".aurorafox"))).resolve()
USER_ROOT.mkdir(parents=True, exist_ok=True)
DB_PATH = USER_ROOT / "project_index.sqlite3"
MAX_SOURCE_BYTES = 4 * 1024 * 1024
DEFAULT_MAX_FILES = 30_000

app = FastAPI(title="AuroraFox Project Index", version="1.0.0")

CODE_EXTENSIONS = {
    ".gd": "GDScript", ".py": "Python", ".js": "JavaScript", ".jsx": "JavaScript",
    ".ts": "TypeScript", ".tsx": "TypeScript", ".c": "C", ".h": "C/C++",
    ".cpp": "C++", ".cc": "C++", ".cxx": "C++", ".hpp": "C++", ".hxx": "C++",
    ".cs": "C#", ".java": "Java", ".kt": "Kotlin", ".kts": "Kotlin", ".rs": "Rust",
    ".go": "Go", ".php": "PHP", ".rb": "Ruby", ".lua": "Lua", ".swift": "Swift",
    ".dart": "Dart", ".sql": "SQL", ".sh": "Shell", ".bash": "Shell", ".ps1": "PowerShell",
    ".r": "R", ".jl": "Julia", ".ex": "Elixir", ".exs": "Elixir", ".erl": "Erlang",
    ".hrl": "Erlang", ".hs": "Haskell", ".ml": "OCaml", ".mli": "OCaml", ".zig": "Zig",
    ".nim": "Nim", ".fs": "F#", ".fsx": "F#", ".vb": "VB.NET", ".pas": "Pascal",
    ".f90": "Fortran", ".f95": "Fortran", ".asm": "Assembly", ".s": "Assembly",
    ".sol": "Solidity", ".scala": "Scala", ".clj": "Clojure", ".pl": "Perl",
    ".html": "HTML", ".css": "CSS", ".scss": "SCSS", ".xml": "XML", ".json": "JSON",
    ".yaml": "YAML", ".yml": "YAML", ".toml": "TOML", ".ini": "INI", ".cfg": "Config",
    ".md": "Markdown", ".txt": "Text",
}

IGNORED_DIRS = {
    ".git", ".hg", ".svn", ".godot", ".idea", ".vscode", "node_modules", "vendor",
    "dist", "build", "target", "bin", "obj", "__pycache__", ".venv", "venv", ".gradle",
    ".android", ".ci", "coverage", ".pytest_cache", ".mypy_cache", ".ruff_cache",
}

SYMBOL_PATTERNS: dict[str, list[tuple[str, re.Pattern[str]]]] = {
    "GDScript": [
        ("class", re.compile(r"^\s*class_name\s+([A-Za-z_][\w]*)", re.M)),
        ("func", re.compile(r"^\s*func\s+([A-Za-z_][\w]*)\s*\(", re.M)),
        ("signal", re.compile(r"^\s*signal\s+([A-Za-z_][\w]*)", re.M)),
    ],
    "Python": [
        ("class", re.compile(r"^\s*class\s+([A-Za-z_][\w]*)", re.M)),
        ("func", re.compile(r"^\s*(?:async\s+)?def\s+([A-Za-z_][\w]*)\s*\(", re.M)),
    ],
    "JavaScript": [
        ("class", re.compile(r"\bclass\s+([A-Za-z_$][\w$]*)")),
        ("func", re.compile(r"\bfunction\s+([A-Za-z_$][\w$]*)\s*\(")),
    ],
    "TypeScript": [
        ("class", re.compile(r"\b(?:class|interface|type|enum)\s+([A-Za-z_$][\w$]*)")),
        ("func", re.compile(r"\bfunction\s+([A-Za-z_$][\w$]*)\s*\(")),
    ],
    "C#": [
        ("type", re.compile(r"\b(?:class|struct|interface|enum|record)\s+([A-Za-z_][\w]*)")),
        ("method", re.compile(r"\b(?:public|private|protected|internal|static|async|virtual|override|sealed|partial|\s)+\s*[\w<>,\[\]?]+\s+([A-Za-z_][\w]*)\s*\(")),
    ],
    "Java": [
        ("type", re.compile(r"\b(?:class|interface|enum|record)\s+([A-Za-z_][\w]*)")),
    ],
    "Kotlin": [
        ("type", re.compile(r"\b(?:class|interface|object|enum\s+class|data\s+class)\s+([A-Za-z_][\w]*)")),
        ("func", re.compile(r"\bfun\s+([A-Za-z_][\w]*)\s*\(")),
    ],
    "Rust": [
        ("type", re.compile(r"\b(?:struct|enum|trait)\s+([A-Za-z_][\w]*)")),
        ("func", re.compile(r"\bfn\s+([A-Za-z_][\w]*)\s*\(")),
    ],
    "Go": [
        ("type", re.compile(r"\btype\s+([A-Za-z_][\w]*)\s+(?:struct|interface)\b")),
        ("func", re.compile(r"\bfunc\s+(?:\([^)]*\)\s*)?([A-Za-z_][\w]*)\s*\(")),
    ],
}


class IndexRequest(BaseModel):
    root: str = Field(min_length=1, max_length=8192)
    max_files: int = Field(default=DEFAULT_MAX_FILES, ge=0)
    max_source_bytes: int = Field(default=MAX_SOURCE_BYTES, ge=0)
    max_symbols: int = Field(default=500, ge=0)
    force: bool = False


class SearchRequest(BaseModel):
    root: str = Field(default="", max_length=8192)
    query: str = Field(min_length=1)
    max_query_chars: int = Field(default=2000, ge=0)
    excerpt_chars: int = Field(default=1800, ge=0)
    result_symbols: int = Field(default=80, ge=0)
    limit: int = Field(default=20, ge=0, le=9223372036854775806)
    language: str = Field(default="", max_length=100)


class SymbolRequest(BaseModel):
    root: str = Field(default="", max_length=8192)
    query: str = Field(min_length=1)
    max_query_chars: int = Field(default=500, ge=0)
    limit: int = Field(default=50, ge=0)


def _conn() -> sqlite3.Connection:
    db = sqlite3.connect(DB_PATH, timeout=30)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    db.execute(
        "CREATE TABLE IF NOT EXISTS files ("
        "root TEXT NOT NULL, path TEXT NOT NULL, language TEXT NOT NULL, size INTEGER NOT NULL, "
        "mtime_ns INTEGER NOT NULL, content TEXT NOT NULL, symbols TEXT NOT NULL, indexed_at INTEGER NOT NULL, "
        "PRIMARY KEY(root, path))"
    )
    db.execute("CREATE INDEX IF NOT EXISTS idx_files_root ON files(root)")
    db.execute("CREATE INDEX IF NOT EXISTS idx_files_language ON files(language)")
    try:
        db.execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5("
            "root UNINDEXED, path, language, content, symbols, tokenize='unicode61')"
        )
    except sqlite3.OperationalError:
        pass
    columns = {row[1] for row in db.execute("PRAGMA table_info(files)")}
    if not {"policy", "symbols_truncated"}.issubset(columns):
        # Recheck under SQLite's writer lock so concurrent first requests cannot
        # race an additive migration, including across separate processes.
        db.execute("BEGIN IMMEDIATE")
        columns = {row[1] for row in db.execute("PRAGMA table_info(files)")}
        if "policy" not in columns:
            db.execute("ALTER TABLE files ADD COLUMN policy TEXT NOT NULL DEFAULT ''")
        if "symbols_truncated" not in columns:
            db.execute("ALTER TABLE files ADD COLUMN symbols_truncated INTEGER NOT NULL DEFAULT 0")
        db.commit()
    return db


def _root(value: str) -> Path:
    try:
        root = Path(value).expanduser().resolve(strict=True)
    except Exception as exc:
        raise HTTPException(404, "Project root not found") from exc
    if not root.is_dir():
        raise HTTPException(400, "Project root is not a directory")
    return root


def _decode(path: Path, max_bytes: int = 0, root: Path | None = None) -> str:
    if path.is_symlink() or (root is not None and not path.resolve(strict=True).is_relative_to(root)):
        raise ValueError("Source path leaves approved project root")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(path, flags), "rb") as source:
        raw = source.read(max_bytes + 1) if max_bytes > 0 else source.read()
    if max_bytes > 0 and len(raw) > max_bytes:
        raise ValueError("Source grew beyond owner byte budget")
    for enc in ("utf-8-sig", "utf-8", "cp1251", "utf-16", "latin-1"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def _symbols(language: str, content: str, max_symbols: int = 500) -> list[dict[str, Any]]:
    patterns = SYMBOL_PATTERNS.get(language, [])
    result: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()
    for kind, pattern in patterns:
        for match in pattern.finditer(content):
            name = match.group(1)
            key = (kind, name)
            if key in seen:
                continue
            seen.add(key)
            line = content.count("\n", 0, match.start()) + 1
            result.append({"kind": kind, "name": name, "line": line})
            if max_symbols > 0 and len(result) >= max_symbols:
                return result
    return result


def _iter_sources(root: Path, max_files: int, coverage: dict | None = None):
    coverage = coverage if coverage is not None else {"failed": 0, "unsafe": set()}
    count = 0
    def failed(_error):
        coverage["failed"] += 1
    for current, dirs, files in os.walk(root, onerror=failed, followlinks=False):
        base = Path(current)
        retained = []
        for name in dirs:
            path = base / name
            if name in IGNORED_DIRS or name.startswith(".__"):
                continue
            if path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction()):
                coverage["unsafe"].add(path.relative_to(root).as_posix()+"/")
                continue
            retained.append(name)
        dirs[:] = retained
        for name in files:
            language = CODE_EXTENSIONS.get(Path(name).suffix.lower())
            if not language:
                continue
            path = base / name
            try:
                if path.is_symlink() or not path.resolve(strict=True).is_relative_to(root):
                    coverage["unsafe"].add(path.relative_to(root).as_posix())
                    continue
                st = path.stat()
                if not path.is_file():
                    continue
            except OSError:
                coverage["failed"] += 1
                continue
            yield path, language, st
            count += 1
            if max_files > 0 and count >= max_files:
                return


def _fts_available(db: sqlite3.Connection) -> bool:
    try:
        db.execute("SELECT rowid FROM files_fts LIMIT 1").fetchall()
        return True
    except sqlite3.OperationalError:
        return False


def _sync_fts(db: sqlite3.Connection, root: str) -> None:
    if not _fts_available(db):
        return
    db.execute("DELETE FROM files_fts WHERE root = ?", (root,))
    db.execute(
        "INSERT INTO files_fts(root,path,language,content,symbols) "
        "SELECT root,path,language,content,symbols FROM files WHERE root = ?",
        (root,),
    )


def _search_terms(query: str) -> str:
    tokens = re.findall(r"[\w.$:+/#-]+", query, flags=re.UNICODE)
    safe = [t.replace('"', '""') for t in tokens if t.strip()]
    return " OR ".join(f'"{t}"' for t in safe)


def _excerpt(content: str, query: str, size: int = 1800) -> str:
    if size == 0:
        return content
    if len(content) <= size:
        return content
    lower = content.casefold()
    positions = [lower.find(token.casefold()) for token in re.findall(r"[\w.$:+/#-]+", query) if token]
    positions = [p for p in positions if p >= 0]
    pos = min(positions) if positions else 0
    start = max(0, pos - size // 3)
    end = min(len(content), start + size)
    prefix = "…" if start > 0 else ""
    suffix = "…" if end < len(content) else ""
    # Ellipsis markers share the owner's output budget. Tiny budgets remain valid.
    available = max(0, size - len(prefix) - len(suffix))
    return (prefix + content[start:start + available] + suffix)[:size]


@app.get("/health")
def health():
    with _conn() as db:
        total = int(db.execute("SELECT COUNT(*) FROM files").fetchone()[0])
        roots = int(db.execute("SELECT COUNT(DISTINCT root) FROM files").fetchone()[0])
        fts = _fts_available(db)
    return {"ok": True, "backend": "AuroraProjectIndex", "db": str(DB_PATH), "files": total, "roots": roots, "fts5": fts}


@app.post("/index")
def index_project(req: IndexRequest):
    root = _root(req.root)
    root_str = str(root)
    started = time.time()
    seen: set[str] = set()
    indexed = 0
    unchanged = 0
    failed = 0
    languages: dict[str, int] = {}
    limit_reached = False
    oversized = 0
    symbol_partial_files = 0
    coverage = {"failed": 0, "unsafe": set()}
    policy = f"v2-owner-index:{req.max_source_bytes}:{req.max_symbols}"
    with _conn() as db:
        existing = {
            row["path"]: (int(row["size"]), int(row["mtime_ns"]), row["policy"], bool(row["symbols_truncated"]))
            for row in db.execute("SELECT path,size,mtime_ns,policy,symbols_truncated FROM files WHERE root = ?", (root_str,))
        }
        for path, language, st in _iter_sources(root, 0, coverage):
            if req.max_files > 0 and len(seen) >= req.max_files:
                limit_reached = True
                break
            rel = path.relative_to(root).as_posix()
            seen.add(rel)
            if req.max_source_bytes > 0 and st.st_size > req.max_source_bytes:
                oversized += 1
                continue
            languages[language] = languages.get(language, 0) + 1
            old = existing.get(rel)
            if not req.force and old is not None and old[:3] == (st.st_size, st.st_mtime_ns, policy):
                unchanged += 1
                symbol_partial_files += int(old[3])
                continue
            try:
                content = _decode(path, req.max_source_bytes, root)
                symbols = _symbols(language, content, req.max_symbols+1 if req.max_symbols else 0)
                symbols_truncated = req.max_symbols > 0 and len(symbols) > req.max_symbols
                if symbols_truncated:
                    symbols = symbols[:req.max_symbols]
                    symbol_partial_files += 1
                db.execute(
                    "INSERT INTO files(root,path,language,size,mtime_ns,content,symbols,indexed_at,policy,symbols_truncated) VALUES(?,?,?,?,?,?,?,?,?,?) "
                    "ON CONFLICT(root,path) DO UPDATE SET language=excluded.language,size=excluded.size,"
                    "mtime_ns=excluded.mtime_ns,content=excluded.content,symbols=excluded.symbols,indexed_at=excluded.indexed_at,policy=excluded.policy,symbols_truncated=excluded.symbols_truncated",
                    (root_str, rel, language, st.st_size, st.st_mtime_ns, content, json.dumps(symbols, ensure_ascii=False), int(time.time()), policy, int(symbols_truncated)),
                )
                indexed += 1
            except Exception:
                failed += 1
        failed += coverage["failed"]
        # Never delete unseen rows when traversal/byte coverage was incomplete.
        # Explicitly unsafe paths are separately purged, not retained as trusted.
        incomplete = limit_reached or oversized > 0 or failed > 0
        unsafe = {path for path in existing if any(path == value or (value.endswith("/") and path.startswith(value)) for value in coverage["unsafe"])}
        stale = sorted(unsafe | (set() if incomplete else {path for path in existing if path not in seen}))
        if stale:
            db.executemany("DELETE FROM files WHERE root = ? AND path = ?", [(root_str, path) for path in stale])
        _sync_fts(db, root_str)
        db.commit()
        total = int(db.execute("SELECT COUNT(*) FROM files WHERE root = ?", (root_str,)).fetchone()[0])
    return {
        "ok": True, "root": root_str, "total_files": total, "updated_files": indexed,
        "unchanged_files": unchanged, "removed_files": len(stale), "failed_files": failed,
        "languages": languages, "limit_reached": limit_reached, "partial": limit_reached or oversized > 0 or failed > 0 or symbol_partial_files > 0 or bool(coverage["unsafe"]),
        "oversized_files": oversized, "unsafe_paths_skipped": len(coverage["unsafe"]),
        "symbol_partial_files": symbol_partial_files, "max_source_bytes": req.max_source_bytes, "max_symbols": req.max_symbols,
        "elapsed_ms": int((time.time() - started) * 1000),
    }


def _check_query(query: str, limit: int) -> None:
    if limit > 0 and len(query) > limit:
        raise HTTPException(413, "Query exceeds owner character budget")


@app.post("/search")
def search_project(req: SearchRequest):
    _check_query(req.query, req.max_query_chars)
    root = str(Path(req.root).expanduser().resolve()) if req.root else ""
    fetch_limit = req.limit+1 if req.limit > 0 else -1
    with _conn() as db:
        terms = _search_terms(req.query)
        rows = []
        if terms and _fts_available(db):
            sql = "SELECT files_fts.root,files_fts.path,files_fts.language,files_fts.content,files_fts.symbols,files.symbols_truncated,bm25(files_fts) AS score FROM files_fts JOIN files ON files.root=files_fts.root AND files.path=files_fts.path WHERE files_fts MATCH ?"
            params: list[Any] = [terms]
            if root:
                sql += " AND files_fts.root = ?"; params.append(root)
            if req.language:
                sql += " AND files_fts.language = ?"; params.append(req.language)
            sql += " ORDER BY score LIMIT ?"; params.append(fetch_limit)
            try:
                rows = db.execute(sql, params).fetchall()
            except sqlite3.OperationalError:
                rows = []
        if not rows:
            like = f"%{req.query}%"
            sql = "SELECT root,path,language,content,symbols,symbols_truncated,0.0 AS score FROM files WHERE (content LIKE ? OR path LIKE ? OR symbols LIKE ?)"
            params = [like, like, like]
            if root:
                sql += " AND root = ?"; params.append(root)
            if req.language:
                sql += " AND language = ?"; params.append(req.language)
            sql += " LIMIT ?"; params.append(fetch_limit)
            rows = db.execute(sql, params).fetchall()
    more = req.limit > 0 and len(rows) > req.limit
    if more:
        rows = rows[:req.limit]
    results = []
    for row in rows:
        try:
            symbols = json.loads(row["symbols"])
        except Exception:
            symbols = []
        clipped_symbols = req.result_symbols > 0 and len(symbols) > req.result_symbols
        excerpt = _excerpt(row["content"], req.query, req.excerpt_chars)
        results.append({
            "root": row["root"], "path": row["path"], "language": row["language"],
            "score": float(row["score"] or 0.0), "symbols": symbols[:req.result_symbols] if req.result_symbols else symbols,
            "symbols_truncated": bool(row["symbols_truncated"]) or clipped_symbols,
            "excerpt": excerpt, "excerpt_truncated": excerpt != row["content"],
        })
    return {"ok": True, "query": req.query, "results": results, "limit_reached": more, "more_results": more}


@app.post("/symbols")
def search_symbols(req: SymbolRequest):
    _check_query(req.query, req.max_query_chars)
    root = str(Path(req.root).expanduser().resolve()) if req.root else ""
    q = req.query.casefold()
    results = []
    index_partial = False
    with _conn() as db:
        # SQLite LIKE only folds ASCII. Filter names in Python so Unicode
        # identifiers and clipped-index coverage cannot disappear from candidates.
        sql = "SELECT root,path,language,symbols,symbols_truncated FROM files"
        params: list[Any] = []
        if root:
            sql += " WHERE root = ?"; params.append(root)
        # Stream all candidate rows: a cap on candidates can hide the first
        # actual matching symbol after many JSON metadata false positives.
        for row in db.execute(sql, params):
            index_partial = index_partial or bool(row["symbols_truncated"])
            try:
                symbols = json.loads(row["symbols"])
            except Exception:
                continue
            for symbol in symbols:
                if q in str(symbol.get("name", "")).casefold():
                    if req.limit > 0 and len(results) >= req.limit:
                        return {"ok": True, "query": req.query, "results": results, "limit_reached": True, "index_partial": index_partial}
                    results.append({"root": row["root"], "path": row["path"], "language": row["language"], **symbol})
    return {"ok": True, "query": req.query, "results": results, "limit_reached": False, "index_partial": index_partial}


@app.get("/status")
def status(root: str = ""):
    root_value = str(Path(root).expanduser().resolve()) if root else ""
    with _conn() as db:
        if root_value:
            total = int(db.execute("SELECT COUNT(*) FROM files WHERE root = ?", (root_value,)).fetchone()[0])
            languages = {row[0]: int(row[1]) for row in db.execute("SELECT language,COUNT(*) FROM files WHERE root = ? GROUP BY language", (root_value,))}
        else:
            total = int(db.execute("SELECT COUNT(*) FROM files").fetchone()[0])
            languages = {row[0]: int(row[1]) for row in db.execute("SELECT language,COUNT(*) FROM files GROUP BY language")}
    return {"ok": True, "root": root_value, "files": total, "languages": languages}


@app.post("/clear")
def clear(root: str = ""):
    root_value = str(Path(root).expanduser().resolve()) if root else ""
    with _conn() as db:
        if root_value:
            db.execute("DELETE FROM files WHERE root = ?", (root_value,))
            if _fts_available(db): db.execute("DELETE FROM files_fts WHERE root = ?", (root_value,))
        else:
            db.execute("DELETE FROM files")
            if _fts_available(db): db.execute("DELETE FROM files_fts")
        db.commit()
    return {"ok": True}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT, log_level="warning")
