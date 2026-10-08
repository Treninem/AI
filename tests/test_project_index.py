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


def test_owner_file_budget_reports_partial_and_preserves_unvisited(tmp_path: Path) -> None:
    _set_db(tmp_path)
    project = tmp_path / "project"
    project.mkdir()
    for name in ("a.py", "b.py", "c.py"):
        (project / name).write_text("def retained(): pass", encoding="utf-8")
    complete = indexer.index_project(indexer.IndexRequest(root=str(project), max_files=0))
    assert complete["total_files"] == 3 and not complete["partial"]
    limited = indexer.index_project(indexer.IndexRequest(root=str(project), max_files=1))
    assert limited["partial"] and limited["limit_reached"]
    assert limited["total_files"] == 3 and limited["removed_files"] == 0
    exact = indexer.index_project(indexer.IndexRequest(root=str(project), max_files=3))
    assert not exact["partial"] and not exact["limit_reached"]
    assert indexer.IndexRequest(root=str(project), max_files=100001).max_files == 100001
    import pytest
    from pydantic import ValidationError
    with pytest.raises(ValidationError):
        indexer.IndexRequest(root=str(project), max_files=-1)


def test_owner_source_bytes_preserve_records_and_can_raise_or_disable(tmp_path: Path) -> None:
    _set_db(tmp_path)
    project = tmp_path / "project"
    project.mkdir()
    large = project / "large.py"
    large.write_text("#" * (4 * 1024 * 1024 + 1) + "\ndef beyond_old_cap(): pass\n")
    first = indexer.index_project(indexer.IndexRequest(root=str(project), max_source_bytes=0))
    assert first["updated_files"] == 1 and not first["partial"]
    limited = indexer.index_project(indexer.IndexRequest(root=str(project)))
    assert limited["partial"] and limited["oversized_files"] == 1
    assert limited["total_files"] == 1 and limited["removed_files"] == 0
    raised = indexer.index_project(indexer.IndexRequest(root=str(project), max_source_bytes=large.stat().st_size))
    assert not raised["partial"] and raised["oversized_files"] == 0
    found = indexer.search_symbols(indexer.SymbolRequest(root=str(project), query="beyond_old_cap", limit=0))
    assert len(found["results"]) == 1


def test_symbol_policy_rebuilds_each_file_and_partial_runs_do_not_mark_unvisited_current(tmp_path: Path) -> None:
    _set_db(tmp_path)
    project = tmp_path / "project"
    project.mkdir()
    source = "\n".join(f"def generated_{i}(): pass" for i in range(601))
    for name in ("a.py", "b.py"):
        (project / name).write_text(source)
    capped = indexer.index_project(indexer.IndexRequest(root=str(project)))
    assert capped["partial"] and capped["symbol_partial_files"] == 2
    partial = indexer.index_project(indexer.IndexRequest(root=str(project), max_files=1, max_symbols=0))
    assert partial["limit_reached"]
    complete = indexer.index_project(indexer.IndexRequest(root=str(project), max_symbols=0))
    assert complete["updated_files"] == 1 and complete["unchanged_files"] == 1
    assert not complete["partial"]
    results = indexer.search_symbols(indexer.SymbolRequest(root=str(project), query="generated_600", limit=0))
    assert len(results["results"]) == 2


def test_real_source_growth_is_bounded_and_old_record_is_retained(tmp_path: Path, monkeypatch) -> None:
    _set_db(tmp_path)
    project = tmp_path / "project"
    project.mkdir()
    path = project / "growing.py"
    path.write_text("old")
    indexer.index_project(indexer.IndexRequest(root=str(project), max_source_bytes=0))
    old_stat = path.stat()
    path.write_text("new and much larger content")
    def growth(_root, _count, _coverage):
        yield path, "Python", old_stat
    monkeypatch.setattr(indexer, "_iter_sources", growth)
    result = indexer.index_project(indexer.IndexRequest(root=str(project), max_source_bytes=6, force=True))
    assert result["partial"] and result["failed_files"] == 1
    with indexer._conn() as db:
        assert db.execute("SELECT content FROM files").fetchone()[0] == "old"


def test_source_symlink_does_not_import_outside_root_and_purges_old_row(tmp_path: Path) -> None:
    _set_db(tmp_path)
    project = tmp_path / "project"
    project.mkdir()
    path = project / "linked.py"
    path.write_text("def previously_safe(): pass")
    indexer.index_project(indexer.IndexRequest(root=str(project)))
    outside = tmp_path / "private.py"
    outside.write_text("PRIVATE_OUTSIDE_ROOT")
    path.unlink()
    path.symlink_to(outside)
    result = indexer.index_project(indexer.IndexRequest(root=str(project)))
    assert result["partial"] and result["unsafe_paths_skipped"] == 1 and result["removed_files"] == 1
    with indexer._conn() as db:
        assert db.execute("SELECT COUNT(*) FROM files").fetchone()[0] == 0


def test_search_limit_extra_match_and_zero_unlimited_are_honest(tmp_path: Path) -> None:
    _set_db(tmp_path)
    project = tmp_path / "project"
    project.mkdir()
    for i in range(130):
        (project / f"source_{i}.py").write_text("def common_match(): pass")
    indexer.index_project(indexer.IndexRequest(root=str(project)))
    exact = indexer.search_project(indexer.SearchRequest(root=str(project), query="common_match", limit=130))
    assert len(exact["results"]) == 130 and not exact["limit_reached"]
    partial = indexer.search_project(indexer.SearchRequest(root=str(project), query="common_match", limit=1))
    assert len(partial["results"]) == 1 and partial["limit_reached"]
    all_results = indexer.search_project(indexer.SearchRequest(root=str(project), query="common_match", limit=0))
    assert len(all_results["results"]) == 130 and not all_results["limit_reached"]
    symbols = indexer.search_symbols(indexer.SymbolRequest(root=str(project), query="common_match", limit=0))
    assert len(symbols["results"]) == 130 and not symbols["limit_reached"]


def test_symbols_match_after_more_than_1000_metadata_false_positives(tmp_path: Path) -> None:
    _set_db(tmp_path)
    with indexer._conn() as db:
        import json
        for i in range(1001):
            symbols = [{"kind": "func", "name": f"dummy_{i}", "line": 1}]
            db.execute("INSERT INTO files(root,path,language,size,mtime_ns,content,symbols,indexed_at) VALUES(?,?,?,?,?,?,?,?)",
                       (str(tmp_path), str(i), "Python", 0, 0, "", json.dumps(symbols), 0))
        db.execute("INSERT INTO files(root,path,language,size,mtime_ns,content,symbols,indexed_at) VALUES(?,?,?,?,?,?,?,?)",
                   (str(tmp_path), "late", "Python", 0, 0, "", json.dumps([{"kind": "func", "name": "func_actual", "line": 1}]), 0))
    found = indexer.search_symbols(indexer.SymbolRequest(root=str(tmp_path), query="func", limit=1))
    assert [row["name"] for row in found["results"]] == ["func_actual"]
    assert not found["limit_reached"]


def test_owner_excerpt_and_result_symbols_report_actual_clipping(tmp_path: Path) -> None:
    _set_db(tmp_path)
    project = tmp_path / "project"
    project.mkdir()
    content = "\n".join(f"def marker_{i}(): pass" for i in range(100))
    (project / "many.py").write_text(content)
    indexer.index_project(indexer.IndexRequest(root=str(project), max_symbols=0))
    clipped = indexer.search_project(indexer.SearchRequest(root=str(project), query="marker", excerpt_chars=20, result_symbols=2))
    assert len(clipped["results"][0]["excerpt"]) <= 20
    assert clipped["results"][0]["symbols_truncated"] and clipped["results"][0]["excerpt_truncated"]
    full = indexer.search_project(indexer.SearchRequest(root=str(project), query="marker", excerpt_chars=0, result_symbols=0))
    assert len(full["results"][0]["symbols"]) == 100
    assert full["results"][0]["excerpt"] == content
    assert not full["results"][0]["symbols_truncated"] and not full["results"][0]["excerpt_truncated"]


def test_excerpt_markers_stay_inside_tiny_and_exact_owner_budgets():
    for budget in [1, 2, 3, 20, 100]:
        assert len(indexer._excerpt("before " * 20 + "needle" + " after" * 20, "needle", budget)) <= budget
    assert indexer._excerpt("exact", "exact", 5) == "exact"

def test_query_terms_after_twenty_remain_searchable(tmp_path: Path):
    _set_db(tmp_path)
    project = tmp_path / "project"
    project.mkdir()
    (project / "late.py").write_text("def late_unique_marker(): pass")
    indexer.index_project(indexer.IndexRequest(root=str(project)))
    query = " ".join([f"absent_{i}" for i in range(21)] + ["late_unique_marker"])
    found = indexer.search_project(indexer.SearchRequest(root=str(project), query=query, max_query_chars=0))
    assert [row["path"] for row in found["results"]] == ["late.py"]


def test_symbol_unicode_casefold_and_clipped_index_coverage(tmp_path: Path):
    _set_db(tmp_path)
    import json
    with indexer._conn() as db:
        db.execute("INSERT INTO files(root,path,language,size,mtime_ns,content,symbols,indexed_at,symbols_truncated) VALUES(?,?,?,?,?,?,?,?,?)",
                   (str(tmp_path), "unicode", "Python", 0, 0, "", json.dumps([{"kind": "func", "name": "ПРОВЕРКА", "line": 1}], ensure_ascii=False), 0, 1))
    found = indexer.search_symbols(indexer.SymbolRequest(root=str(tmp_path), query="проверка"))
    assert found["results"][0]["name"] == "ПРОВЕРКА"
    assert found["index_partial"]
    missing = indexer.search_symbols(indexer.SymbolRequest(root=str(tmp_path), query="not_in_stored_symbols"))
    assert not missing["results"] and missing["index_partial"]

def test_owner_query_budget_rejects_overflow_without_silent_clipping(tmp_path: Path):
    _set_db(tmp_path)
    from fastapi import HTTPException
    import pytest
    with pytest.raises(HTTPException) as error:
        indexer.search_project(indexer.SearchRequest(query="long", max_query_chars=3))
    assert error.value.status_code == 413
    assert indexer.search_project(indexer.SearchRequest(query="long", max_query_chars=4))["ok"]
    assert indexer.search_symbols(indexer.SymbolRequest(query="long" * 200, max_query_chars=0))["ok"]

def test_legacy_derived_index_additive_migration_preserves_rows(tmp_path: Path):
    _set_db(tmp_path)
    import sqlite3
    with sqlite3.connect(indexer.DB_PATH) as db:
        db.execute("CREATE TABLE files(root TEXT,path TEXT,language TEXT,size INTEGER,mtime_ns INTEGER,content TEXT,symbols TEXT,indexed_at INTEGER,PRIMARY KEY(root,path))")
        db.execute("INSERT INTO files VALUES(?,?,?,?,?,?,?,?)", ("root", "retained.py", "Python", 1, 1, "saved", "[]", 1))
    with indexer._conn() as db:
        row = db.execute("SELECT * FROM files").fetchone()
        assert row["content"] == "saved" and row["policy"] == "" and row["symbols_truncated"] == 0
