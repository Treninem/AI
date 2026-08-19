from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "file_intelligence"))

import project_index_service as indexer  # noqa: E402


def _set_db(tmp_path: Path) -> None:
    indexer.DB_PATH = tmp_path / "index.sqlite3"


def test_incremental_index_search_and_symbols(tmp_path: Path) -> None:
    _set_db(tmp_path)
    project = tmp_path / "project"
    project.mkdir()
    (project / "player.gd").write_text(
        "class_name PlayerController\n\nsignal health_changed\n\nfunc take_damage(amount):\n    health -= amount\n",
        encoding="utf-8",
    )
    (project / "utils.py").write_text(
        "class SaveManager:\n    pass\n\ndef load_world(path):\n    return path\n",
        encoding="utf-8",
    )
    ignored = project / "node_modules"
    ignored.mkdir()
    (ignored / "junk.js").write_text("function shouldNeverIndex() {}", encoding="utf-8")

    result = indexer.index_project(indexer.IndexRequest(root=str(project), max_files=100, force=False))
    assert result["ok"] is True
    assert result["total_files"] == 2
    assert result["updated_files"] == 2

    second = indexer.index_project(indexer.IndexRequest(root=str(project), max_files=100, force=False))
    assert second["updated_files"] == 0
    assert second["unchanged_files"] == 2

    search = indexer.search_project(indexer.SearchRequest(root=str(project), query="health damage", limit=10))
    assert search["ok"] is True
    assert any(item["path"] == "player.gd" for item in search["results"])

    symbols = indexer.search_symbols(indexer.SymbolRequest(root=str(project), query="take_damage", limit=20))
    assert any(item["name"] == "take_damage" and item["path"] == "player.gd" for item in symbols["results"])

    python_symbols = indexer.search_symbols(indexer.SymbolRequest(root=str(project), query="SaveManager", limit=20))
    assert any(item["name"] == "SaveManager" for item in python_symbols["results"])


def test_removed_file_disappears_from_index(tmp_path: Path) -> None:
    _set_db(tmp_path)
    project = tmp_path / "project"
    project.mkdir()
    path = project / "old.py"
    path.write_text("def obsolete_function():\n    return True\n", encoding="utf-8")
    indexer.index_project(indexer.IndexRequest(root=str(project), max_files=100, force=False))
    path.unlink()
    result = indexer.index_project(indexer.IndexRequest(root=str(project), max_files=100, force=False))
    assert result["removed_files"] == 1
    found = indexer.search_symbols(indexer.SymbolRequest(root=str(project), query="obsolete_function", limit=20))
    assert found["results"] == []
