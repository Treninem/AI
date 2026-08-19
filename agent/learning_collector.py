from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
STATE_DIR = ROOT / ".aurora" / "learning"
DEFAULT_OUTPUT = STATE_DIR / "observations.jsonl"
USER_AGENT = "AuroraFox-Learning/1.0 (+local autonomous research)"
MAX_HTTP_BYTES = 2 * 1024 * 1024
TEXT_EXTENSIONS = {".txt", ".gd", ".py", ".md", ".log", ".jsonl", ".json"}
INDEX_EXTENSIONS = TEXT_EXTENSIONS | {".pdf", ".epub"}
ALLOWED_HOSTS = {
    "api.github.com",
    "api.stackexchange.com",
    "www.reddit.com",
    "export.arxiv.org",
    "habr.com",
    "medium.com",
    "docs.godotengine.org",
    "github.com",
    "docs.ollama.com",
    "github.com",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def safe_excerpt(text: str, limit: int = 1800) -> str:
    return " ".join((text or "").split())[:limit]


def http_get(url: str, timeout: int = 15) -> bytes:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in ALLOWED_HOSTS:
        raise ValueError(f"Learning source is not allowlisted: {url}")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json, application/atom+xml, application/rss+xml, text/xml, text/html;q=0.8"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        if int(getattr(response, "status", 200)) >= 400:
            raise RuntimeError(f"HTTP {response.status}: {url}")
        return response.read(MAX_HTTP_BYTES + 1)[:MAX_HTTP_BYTES]


def json_get(url: str) -> dict:
    return json.loads(http_get(url).decode("utf-8", errors="replace"))


def record(source: str, kind: str, title: str, summary: str = "", url: str = "", metadata: dict | None = None) -> dict:
    return {
        "observed_at": utc_now(),
        "source": source,
        "kind": kind,
        "title": safe_excerpt(title, 300),
        "summary": safe_excerpt(summary),
        "url": url,
        "metadata": metadata or {},
    }


def iter_local_candidates(limit: int) -> Iterable[Path]:
    roots = [ROOT / "logs", ROOT / "project", ROOT]
    documents = Path.home() / "Documents"
    if documents.exists():
        roots.insert(0, documents)

    explicit = [
        ROOT / "file_intelligence" / "index.json",
        ROOT / "dialogs.jsonl",
        ROOT / "evolution.log",
    ]
    seen: set[Path] = set()
    yielded = 0
    for path in explicit:
        if path.exists() and path.is_file():
            seen.add(path.resolve())
            yield path
            yielded += 1
            if yielded >= limit:
                return

    for base in roots:
        if not base.exists():
            continue
        patterns = ["*.txt", "*.pdf", "*.epub", "*.gd", "*.py", "*.md", "*.log", "*.jsonl"]
        for pattern in patterns:
            for path in base.rglob(pattern):
                try:
                    resolved = path.resolve()
                except OSError:
                    continue
                if resolved in seen or not path.is_file():
                    continue
                seen.add(resolved)
                yield path
                yielded += 1
                if yielded >= limit:
                    return


def collect_local(limit: int = 80) -> list[dict]:
    items: list[dict] = []
    for path in iter_local_candidates(limit):
        suffix = path.suffix.lower()
        summary = ""
        if suffix in TEXT_EXTENSIONS:
            try:
                summary = path.read_text(encoding="utf-8", errors="replace")[:12000]
            except OSError:
                summary = ""
        try:
            rel = str(path.relative_to(ROOT)).replace(os.sep, "/")
        except ValueError:
            rel = str(path)
        try:
            size = path.stat().st_size
            modified = int(path.stat().st_mtime)
        except OSError:
            size = 0
            modified = 0
        items.append(record("local", "file", rel, summary, metadata={"extension": suffix, "bytes": size, "mtime": modified, "needs_file_intelligence": suffix in {".pdf", ".epub"}}))

    try:
        result = subprocess.run(["git", "log", "-20", "--pretty=format:%H%x09%ad%x09%s", "--date=iso-strict"], cwd=ROOT, capture_output=True, text=True, timeout=8, check=False)
        for line in result.stdout.splitlines():
            parts = line.split("\t", 2)
            if len(parts) == 3:
                items.append(record("git", "commit", parts[2], metadata={"sha": parts[0], "date": parts[1]}))
    except (OSError, subprocess.SubprocessError):
        pass
    return items


def collect_github(query: str, limit: int) -> list[dict]:
    q = urllib.parse.quote(query)
    data = json_get(f"https://api.github.com/search/repositories?q={q}&sort=updated&order=desc&per_page={limit}")
    return [record("github", "repository", item.get("full_name", ""), item.get("description", ""), item.get("html_url", ""), {"stars": item.get("stargazers_count", 0), "language": item.get("language")}) for item in data.get("items", [])]


def collect_stackoverflow(query: str, limit: int) -> list[dict]:
    q = urllib.parse.quote(query)
    data = json_get(f"https://api.stackexchange.com/2.3/search/advanced?site=stackoverflow&order=desc&sort=activity&q={q}&pagesize={limit}&filter=default")
    return [record("stackoverflow", "question", item.get("title", ""), url=item.get("link", ""), metadata={"score": item.get("score", 0), "answers": item.get("answer_count", 0), "is_answered": item.get("is_answered", False)}) for item in data.get("items", [])]


def collect_reddit(subreddit: str, limit: int) -> list[dict]:
    data = json_get(f"https://www.reddit.com/r/{urllib.parse.quote(subreddit)}/hot.json?limit={limit}&raw_json=1")
    out: list[dict] = []
    for child in data.get("data", {}).get("children", []):
        item = child.get("data", {})
        out.append(record(f"reddit/r/{subreddit}", "post", item.get("title", ""), item.get("selftext", ""), "https://www.reddit.com" + item.get("permalink", ""), {"score": item.get("score", 0), "comments": item.get("num_comments", 0)}))
    return out


def collect_atom(url: str, source: str, limit: int) -> list[dict]:
    root = ET.fromstring(http_get(url))
    out: list[dict] = []
    ns = {"atom": "http://www.w3.org/2005/Atom"}
    for entry in root.findall("atom:entry", ns)[:limit]:
        title = entry.findtext("atom:title", default="", namespaces=ns)
        summary = entry.findtext("atom:summary", default="", namespaces=ns)
        link = ""
        for node in entry.findall("atom:link", ns):
            if node.attrib.get("rel", "alternate") == "alternate":
                link = node.attrib.get("href", "")
                break
        out.append(record(source, "paper", title, summary, link))
    return out


def collect_rss(url: str, source: str, limit: int) -> list[dict]:
    root = ET.fromstring(http_get(url))
    out: list[dict] = []
    for item in root.findall(".//item")[:limit]:
        out.append(record(source, "article", item.findtext("title", ""), item.findtext("description", ""), item.findtext("link", "")))
    if not out:
        # Some feeds are Atom rather than RSS.
        ns = {"atom": "http://www.w3.org/2005/Atom"}
        for entry in root.findall("atom:entry", ns)[:limit]:
            link_node = entry.find("atom:link", ns)
            out.append(record(source, "article", entry.findtext("atom:title", "", ns), entry.findtext("atom:summary", "", ns), link_node.attrib.get("href", "") if link_node is not None else ""))
    return out


def collect_docs() -> list[dict]:
    sources = [
        ("godot-docs", "https://docs.godotengine.org/en/latest/"),
        ("ollama-docs", "https://docs.ollama.com/"),
        ("llama.cpp", "https://github.com/ggml-org/llama.cpp"),
    ]
    out: list[dict] = []
    for name, url in sources:
        try:
            body = http_get(url).decode("utf-8", errors="replace")
            title = ""
            start = body.lower().find("<title")
            if start >= 0:
                start = body.find(">", start) + 1
                end = body.lower().find("</title>", start)
                title = body[start:end] if end > start else name
            out.append(record(name, "documentation", title or name, safe_excerpt(body, 1000), url))
        except Exception as exc:
            out.append(record(name, "source_error", name, str(exc), url))
    return out


def collect_internet(query: str, limit: int = 8) -> list[dict]:
    providers = [
        lambda: collect_github(query, limit),
        lambda: collect_stackoverflow(query, limit),
        lambda: collect_reddit("LocalLLaMA", limit),
        lambda: collect_reddit("MachineLearning", limit),
        lambda: collect_atom(f"https://export.arxiv.org/api/query?search_query=all:{urllib.parse.quote(query)}&start=0&max_results={limit}&sortBy=submittedDate&sortOrder=descending", "arxiv", limit),
        lambda: collect_rss("https://habr.com/ru/rss/hubs/artificial_intelligence/articles/all/?fl=ru", "habr", limit),
        lambda: collect_rss("https://medium.com/feed/tag/artificial-intelligence", "medium", limit),
        collect_docs,
    ]
    out: list[dict] = []
    for provider in providers:
        try:
            out.extend(provider())
        except Exception as exc:
            out.append(record("internet", "source_error", getattr(provider, "__name__", "provider"), str(exc)))
        time.sleep(0.15)
    return out


def dedupe(items: Iterable[dict]) -> list[dict]:
    seen: set[tuple[str, str, str]] = set()
    out: list[dict] = []
    for item in items:
        key = (str(item.get("source")), str(item.get("title")), str(item.get("url")))
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
    return out


def save(items: list[dict], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("a", encoding="utf-8", newline="\n") as handle:
        for item in items:
            handle.write(json.dumps(item, ensure_ascii=False) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="AuroraFox autonomous learning source collector")
    parser.add_argument("--query", default="local AI Godot LLM agent reasoning context optimization")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--local-limit", type=int, default=80)
    parser.add_argument("--source-limit", type=int, default=8)
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT.relative_to(ROOT)))
    parser.add_argument("--print", dest="print_json", action="store_true")
    args = parser.parse_args()

    items = collect_local(max(1, args.local_limit))
    if not args.offline:
        items.extend(collect_internet(args.query, max(1, min(args.source_limit, 20))))
    items = dedupe(items)
    output = (ROOT / args.output).resolve()
    if ROOT not in output.parents and output != ROOT:
        raise SystemExit("Output must stay inside the AuroraFox repository")
    save(items, output)
    if args.print_json:
        print(json.dumps({"ok": True, "count": len(items), "output": str(output), "items": items}, ensure_ascii=False, indent=2))
    else:
        print(json.dumps({"ok": True, "count": len(items), "output": str(output)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
