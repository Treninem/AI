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
    max_files: int = Field(default=DEFAULT_MAX_FILES, ge=1, le=100_000)
    force: bool = False


class SearchRequest(BaseModel):
    root: str = Field(default="", max_length=8192)
    query: str = Field(min_length=1, max_length=2000)
    limit: int = Field(default=20, ge=1, le=100)
    language: str = Field(default="", max_length=100)


class SymbolRequest(BaseModel):
    root: str = Field(default="", max_length=8192)
    query: str = Field(min_length=1, max_length=500)
    limit: int = Field(default=50, ge=1, le=200)


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
    return db


def _root(value: str) -> Path:
    try:
        root = Path(value).expanduser().resolve(strict=True)
    except Exception as exc:
        raise HTTPException(404, "Project root not found") from exc
    if not root.is_dir():
        raise HTTPException(400, "Project root is not a directory")
    return root


def _decode(path: Path) -> str:
    raw = path.read_bytes()
    for enc in ("utf-8-sig", "utf-8", "cp1251", "utf-16", "latin-1"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def _symbols(language: str, content: str) -> list[dict[str, Any]]:
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
            if len(result) >= 500:
                return result
    return result


def _iter_sources(root: Path, max_files: int):
    count = 0
    for current, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in IGNORED_DIRS and not d.startswith(".__")]
        base = Path(current)
        for name in files:
            ext = Path(name).suffix.lower()
            language = CODE_EXTENSIONS.get(ext)
            if not language:
                continue
            path = base / name
            try:
                st = path.stat()
            except OSError:
                continue
            if st.st_size > MAX_SOURCE_BYTES:
                continue
            yield path, language, st
            count += 1
            if count >= max_files:
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
    return " OR ".join(f'"{t}"' for t in safe[:20])


def _excerpt(content: str, query: str, size: int = 1800) -> str:
    lower = content.casefold()
    positions = [lower.find(token.casefold()) for token in re.findall(r"[\w.$:+/#-]+", query) if token]
    positions = [p for p in positions if p >= 0]
    pos = min(positions) if positions else 0
    start = max(0, pos - size // 3)
    end = min(len(content), start + size)
    prefix = "…" if start > 0 else ""
    suffix = "…" if end < len(content) else ""
    return prefix + content[start:end] + suffix


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
    with _conn() as db:
        existing = {
            row["path"]: (int(row["size"]), int(row["mtime_ns"]))
            for row in db.execute("SELECT path,size,mtime_ns FROM files WHERE root = ?", (root_str,))
        }
        for path, language, st in _iter_sources(root, req.max_files):
            rel = path.relative_to(root).as_posix()
            seen.add(rel)
            languages[language] = languages.get(language, 0) + 1
            old = existing.get(rel)
            if not req.force and old == (st.st_size, st.st_mtime_ns):
                unchanged += 1
                continue
            try:
                content = _decode(path)
                symbols = _symbols(language, content)
                db.execute(
                    "INSERT INTO files(root,path,language,size,mtime_ns,content,symbols,indexed_at) VALUES(?,?,?,?,?,?,?,?) "
                    "ON CONFLICT(root,path) DO UPDATE SET language=excluded.language,size=excluded.size,"
                    "mtime_ns=excluded.mtime_ns,content=excluded.content,symbols=excluded.symbols,indexed_at=excluded.indexed_at",
                    (root_str, rel, language, st.st_size, st.st_mtime_ns, content, json.dumps(symbols, ensure_ascii=False), int(time.time())),
                )
                indexed += 1
            except Exception:
                failed += 1
        stale = [path for path in existing if path not in seen]
        if stale:
            db.executemany("DELETE FROM files WHERE root = ? AND path = ?", [(root_str, path) for path in stale])
        _sync_fts(db, root_str)
        db.commit()
        total = int(db.execute("SELECT COUNT(*) FROM files WHERE root = ?", (root_str,)).fetchone()[0])
    return {
        "ok": True, "root": root_str, "total_files": total, "updated_files": indexed,
        "unchanged_files": unchanged, "removed_files": len(stale), "failed_files": failed,
        "languages": languages, "elapsed_ms": int((time.time() - started) * 1000),
    }


@app.post("/search")
def search_project(req: SearchRequest):
    root = str(Path(req.root).expanduser().resolve()) if req.root else ""
    with _conn() as db:
        rows: list[sqlite3.Row]
        terms = _search_terms(req.query)
        if terms and _fts_available(db):
            sql = "SELECT root,path,language,content,symbols,bm25(files_fts) AS score FROM files_fts WHERE files_fts MATCH ?"
            params: list[Any] = [terms]
            if root:
                sql += " AND root = ?"
                params.append(root)
            if req.language:
                sql += " AND language = ?"
                params.append(req.language)
            sql += " ORDER BY score LIMIT ?"
            params.append(req.limit)
            try:
                rows = db.execute(sql, params).fetchall()
            except sqlite3.OperationalError:
                rows = []
        else:
            rows = []
        if not rows:
            like = f"%{req.query}%"
            sql = "SELECT root,path,language,content,symbols,0.0 AS score FROM files WHERE (content LIKE ? OR path LIKE ? OR symbols LIKE ?)"
            params = [like, like, like]
            if root:
                sql += " AND root = ?"
                params.append(root)
            if req.language:
                sql += " AND language = ?"
                params.append(req.language)
            sql += " LIMIT ?"
            params.append(req.limit)
            rows = db.execute(sql, params).fetchall()
    results = []
    for row in rows:
        try:
            symbols = json.loads(row["symbols"])
        except Exception:
            symbols = []
        results.append({
            "root": row["root"], "path": row["path"], "language": row["language"],
            "score": float(row["score"] or 0.0), "symbols": symbols[:80],
            "excerpt": _excerpt(row["content"], req.query),
        })
    return {"ok": True, "query": req.query, "results": results}


@app.post("/symbols")
def search_symbols(req: SymbolRequest):
    root = str(Path(req.root).expanduser().resolve()) if req.root else ""
    q = req.query.casefold()
    with _conn() as db:
        sql = "SELECT root,path,language,symbols FROM files WHERE symbols LIKE ?"
        params: list[Any] = [f"%{req.query}%"]
        if root:
            sql += " AND root = ?"
            params.append(root)
        sql += " LIMIT 1000"
        rows = db.execute(sql, params).fetchall()
    results = []
    for row in rows:
        try:
            symbols = json.loads(row["symbols"])
        except Exception:
            continue
        for symbol in symbols:
            name = str(symbol.get("name", ""))
            if q in name.casefold():
                results.append({"root": row["root"], "path": row["path"], "language": row["language"], **symbol})
                if len(results) >= req.limit:
                    return {"ok": True, "query": req.query, "results": results}
    return {"ok": True, "query": req.query, "results": results}


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
