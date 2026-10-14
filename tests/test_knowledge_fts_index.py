"""Disposable tests for the optional Knowledge FTS index candidate."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
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
        with self.assertRaisesRegex(INDEX.IndexUnavailable, "SHORT_QUERY"):
            INDEX.search(self.source, self.index, "лёд на воде")

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

    def test_failed_publication_preserves_previous_index(self) -> None:
        INDEX.build(self.source, self.index)
        before = self.index.read_bytes()
        with mock.patch.object(INDEX.os, "replace", side_effect=OSError("simulated publication failure")):
            with self.assertRaises(OSError):
                INDEX.build(self.source, self.index)
        self.assertEqual(self.index.read_bytes(), before)
        self.assertEqual([row["id"] for row in INDEX.search(self.source, self.index, "mars moons")], ["mars"])
        self.assertFalse(list(self.index.parent.glob("*.building")))


if __name__ == "__main__":
    unittest.main()
