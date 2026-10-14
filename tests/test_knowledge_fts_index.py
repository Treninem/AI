"""Disposable tests for the optional Knowledge FTS index candidate."""

from __future__ import annotations

import importlib.util
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "file_intelligence" / "knowledge_fts_index.py"
SPEC = importlib.util.spec_from_file_location("knowledge_fts_index", MODULE_PATH)
assert SPEC and SPEC.loader
INDEX = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INDEX)


class KnowledgeFtsIndexTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="aurorafox-knowledge-fts-")
        root = Path(self.directory.name)
        self.source = root / "knowledge.jsonl"
        self.index = root / "knowledge.sqlite3"
        rows = [
            {"id": "weak", "text": "Лёд формируется в воде.", "source": "synthetic://ice", "kind": "fact"},
            {"id": "strong", "text": "Лёд плавает в воде благодаря меньшей плотности.", "source": "synthetic://ice", "kind": "fact"},
            {"id": "mars", "text": "Mars has two moons named Phobos and Deimos.", "source": "synthetic://mars", "kind": "fact"},
        ]
        self.source.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")

    def tearDown(self) -> None:
        self.directory.cleanup()

    def test_ranked_search_and_short_query_fallback(self) -> None:
        self.assertEqual(INDEX.build(self.source, self.index), 3)
        self.assertEqual([row["id"] for row in INDEX.search(self.source, self.index, "лёд плавает воде")], ["strong", "weak"])
        self.assertEqual([row["id"] for row in INDEX.search(self.source, self.index, "mars moons")], ["mars"])
        self.assertEqual([row["id"] for row in INDEX.search(self.source, self.index, "synthetic://ice")], ["weak", "strong"])
        self.assertEqual([row["id"] for row in INDEX.search(self.source, self.index, "fact", limit=3)], ["weak", "strong", "mars"])
        with self.assertRaisesRegex(INDEX.IndexUnavailable, "SHORT_QUERY"):
            INDEX.search(self.source, self.index, "лёд на воде")

    def test_metadata_candidates_use_fts_and_rowid_lookup(self) -> None:
        INDEX.build(self.source, self.index)
        with closing(sqlite3.connect(self.index)) as db:
            plan = " ".join(row[3] for row in db.execute(
                "EXPLAIN QUERY PLAN SELECT metadata_terms.rowid,locations.byte_offset "
                "FROM metadata_terms JOIN locations ON locations.rowid=metadata_terms.rowid "
                "WHERE metadata_terms MATCH ?", (INDEX._fts_term("synthetic"),)
            ))
        self.assertIn("metadata_terms VIRTUAL TABLE", plan)
        self.assertIn("locations USING INTEGER PRIMARY KEY", plan)
        self.assertNotIn("SCAN locations", plan)

    def test_append_and_same_size_same_mtime_edge_edit_are_rejected(self) -> None:
        INDEX.build(self.source, self.index)
        original = self.source.read_bytes()
        stat = self.source.stat()
        self.source.write_bytes(original.replace(b"Phobos", b"Xhobos"))
        os.utime(self.source, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        with self.assertRaisesRegex(INDEX.IndexUnavailable, "STALE_INDEX"):
            INDEX.search(self.source, self.index, "mars moons")
        self.source.write_bytes(original + b"{}\n")
        with self.assertRaisesRegex(INDEX.IndexUnavailable, "STALE_INDEX"):
            INDEX.search(self.source, self.index, "mars moons")

    def test_same_bytes_and_timestamp_replacement_is_rejected(self) -> None:
        INDEX.build(self.source, self.index)
        stat = self.source.stat()
        replacement = self.source.with_suffix(".replacement")
        replacement.write_bytes(self.source.read_bytes())
        os.utime(replacement, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        os.replace(replacement, self.source)
        with self.assertRaisesRegex(INDEX.IndexUnavailable, "STALE_INDEX"):
            INDEX.search(self.source, self.index, "mars moons")

    def test_failed_publication_preserves_previous_index(self) -> None:
        INDEX.build(self.source, self.index)
        before = self.index.read_bytes()
        with mock.patch.object(INDEX.os, "replace", side_effect=OSError("simulated publication failure")):
            with self.assertRaises(OSError):
                INDEX.build(self.source, self.index)
        self.assertEqual(self.index.read_bytes(), before)
        self.assertEqual([row["id"] for row in INDEX.search(self.source, self.index, "mars moons")], ["mars"])
        self.assertFalse(list(self.index.parent.glob("*.building")))

    def test_insufficient_disk_space_preserves_previous_index(self) -> None:
        INDEX.build(self.source, self.index)
        before = self.index.read_bytes()
        with mock.patch.object(INDEX.shutil, "disk_usage", return_value=mock.Mock(free=0)):
            with self.assertRaisesRegex(INDEX.IndexUnavailable, "INSUFFICIENT_DISK_SPACE"):
                INDEX.build(self.source, self.index)
        self.assertEqual(self.index.read_bytes(), before)
        self.assertFalse(list(self.index.parent.glob("*.building")))

    def test_cancelled_rebuild_preserves_previous_index(self) -> None:
        INDEX.build(self.source, self.index)
        before = self.index.read_bytes()
        cancel_file = self.index.with_suffix(".cancel")
        cancel_file.touch()
        with self.assertRaisesRegex(INDEX.IndexUnavailable, "BUILD_CANCELLED"):
            INDEX.build(self.source, self.index, cancel_file)
        self.assertEqual(self.index.read_bytes(), before)
        self.assertFalse(list(self.index.parent.glob("*.building")))

    def test_mid_build_cancellation_cleans_temporary_index(self) -> None:
        INDEX.build(self.source, self.index)
        before = self.index.read_bytes()
        cancel_file = self.index.with_suffix(".cancel")
        original_check = INDEX._check_cancel
        checks = 0

        def cancel_after_build_starts(path: Path | None) -> None:
            nonlocal checks
            checks += 1
            if checks == 2:
                cancel_file.touch()
            original_check(path)

        with mock.patch.object(INDEX, "_check_cancel", side_effect=cancel_after_build_starts):
            with self.assertRaisesRegex(INDEX.IndexUnavailable, "BUILD_CANCELLED"):
                INDEX.build(self.source, self.index, cancel_file)
        self.assertEqual(self.index.read_bytes(), before)
        self.assertFalse(list(self.index.parent.glob("*.building")))

    def test_cancel_file_cli_returns_bounded_error(self) -> None:
        cancel_file = self.index.with_suffix(".cancel")
        cancel_file.touch()
        result = subprocess.run(
            [sys.executable, str(MODULE_PATH), "build", "--source", str(self.source),
             "--index", str(self.index), "--cancel-file", str(cancel_file)],
            capture_output=True, check=False,
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(json.loads(result.stdout)["error"], "BUILD_CANCELLED")
        self.assertFalse(self.index.exists())

    def test_search_cli_survives_legacy_windows_output_encoding(self) -> None:
        INDEX.build(self.source, self.index)
        env = os.environ.copy()
        env["PYTHONIOENCODING"] = "cp1252:strict"
        result = subprocess.run(
            [sys.executable, str(MODULE_PATH), "search", "--source", str(self.source),
             "--index", str(self.index), "--query", "лёд плавает воде"],
            env=env, capture_output=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.isascii())
        self.assertEqual(json.loads(result.stdout)["results"][0]["id"], "strong")


if __name__ == "__main__":
    unittest.main()
