"""Real ZIP/tar extraction and cache identity; production AST, no API facade."""
import ast
import hashlib
import io
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


def runtime():
    tree = ast.parse((ROOT / 'file_intelligence/file_service.py').read_text())
    names = {'_archive_member_path', '_decode_archive_text', '_clip_archive_text', '_archive_listing', '_cache_key'}
    nodes = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in names]
    text_extensions = next(n for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'TEXT_EXT' for t in n.targets))
    namespace = dict(Path=Path, Any=Any, zipfile=zipfile, tarfile=tarfile, hashlib=hashlib,
                     MAX_TEXT_CHARS=160000, MAX_ARCHIVE_ENTRIES=5000, MAX_ARCHIVE_EXPANDED=512*1024*1024,
                     MAX_ARCHIVE_TEXT_MEMBER_BYTES=8*1024*1024, MAX_ARCHIVE_TEXT_TOTAL_BYTES=32*1024*1024,
                     MAX_ARCHIVE_LISTING_CHARS=40000, ARCHIVE_LISTING_PERCENT=25,
                     MAX_SPREADSHEET_CELLS=50000, MAX_XLS_ROWS=10000)
    # Keep the extraction policy identical to the real service, without copying defaults.
    import sys
    sys.path.insert(0, str(ROOT / 'file_intelligence'))
    import file_service
    for name in file_service._cache_key.__code__.co_names:
        if name.isupper() and hasattr(file_service, name):
            namespace[name] = getattr(file_service, name)
    exec(compile(ast.Module(body=[text_extensions]+nodes, type_ignores=[]), 'file_intelligence/file_service.py', 'exec'), namespace)
    return namespace


class ArchiveOwnerBudgets(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name); self.ns = runtime()

    def archive(self, suffix, members):
        path = self.root / ('real' + suffix)
        if suffix == '.zip':
            with zipfile.ZipFile(path, 'w') as z:
                for name, data in members: z.writestr(name, data)
        else:
            with tarfile.open(path, 'w') as t:
                for name, data in members:
                    item = tarfile.TarInfo(name); item.size = len(data)
                    t.addfile(item, io.BytesIO(data))
        return path

    def test_raised_cap_and_share_read_listing_above_old_ceiling(self):
        path = self.archive('.zip', [(str(i)+'x'*120+'.bin', b'x') for i in range(500)])
        text, meta, _ = self.ns['_archive_listing'](path, 400000)
        self.assertEqual(meta['listing_budget'], 40000); self.assertTrue(meta['listing_truncated'])
        self.ns.update(MAX_ARCHIVE_LISTING_CHARS=80000, ARCHIVE_LISTING_PERCENT=80)
        text, meta, _ = self.ns['_archive_listing'](path, 100000)
        self.assertGreater(len(text), 40000); self.assertFalse(meta['listing_truncated'])
        self.assertEqual(meta['listing_budget'], 80000)

    def test_disabled_listing_preserves_real_zip_and_tar_content(self):
        for suffix in ('.zip', '.tar'):
            with self.subTest(suffix=suffix):
                path = self.archive(suffix, [('lesson.txt', b'Genuine knowledge'), ('../escape.txt', b'Forbidden')])
                self.ns['MAX_ARCHIVE_LISTING_CHARS'] = 0
                text, meta, _ = self.ns['_archive_listing'](path, 1000)
                self.assertIn('Genuine knowledge', text); self.assertNotIn('Forbidden', text)
                self.assertNotIn('### Состав архива', text)
                self.assertEqual(meta['text_entries_extracted'], 1)

    def test_tiny_budgets_include_headers_and_never_claim_header_only_extraction(self):
        path = self.archive('.zip', [('lesson.txt', b'Actual content')])
        self.ns.update(ARCHIVE_LISTING_PERCENT=100)
        for budget in range(1, 65):
            text, meta, _ = self.ns['_archive_listing'](path, budget)
            self.assertLessEqual(len(text), budget)
        self.ns['MAX_ARCHIVE_LISTING_CHARS'] = 0
        text, meta, _ = self.ns['_archive_listing'](path, 10)
        self.assertEqual(meta['text_entries_extracted'], 0)
        self.assertTrue(meta['output_truncated'])

    def test_exact_content_fit_and_actual_content_omission(self):
        path = self.archive('.tar', [('a.txt', b'actual')]); self.ns['MAX_ARCHIVE_LISTING_CHARS'] = 0
        full, _, _ = self.ns['_archive_listing'](path, 1000)
        exact, meta, _ = self.ns['_archive_listing'](path, len(full))
        self.assertEqual(exact, full); self.assertFalse(meta['content_truncated'])
        clipped, meta, _ = self.ns['_archive_listing'](path, len(full)-1)
        self.assertEqual(len(clipped), len(full)-1)
        self.assertTrue(meta['content_truncated'])

    def test_each_archive_owner_budget_invalidates_cache(self):
        path = self.archive('.zip', [('a.txt', b'actual')]); key = self.ns['_cache_key'](path, '', False, 1000)
        for name in ('MAX_ARCHIVE_ENTRIES', 'MAX_ARCHIVE_EXPANDED', 'MAX_ARCHIVE_TEXT_MEMBER_BYTES',
                     'MAX_ARCHIVE_TEXT_TOTAL_BYTES', 'MAX_ARCHIVE_LISTING_CHARS', 'ARCHIVE_LISTING_PERCENT'):
            old = self.ns[name]; self.ns[name] = old + 1
            self.assertNotEqual(key, self.ns['_cache_key'](path, '', False, 1000), name)
            self.ns[name] = old


if __name__ == '__main__': unittest.main()
