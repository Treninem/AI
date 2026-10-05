"""Real filesystem/cache unit evidence for exact production function bodies.

AST isolation excludes only API imports/decorators, not filesystem/search logic.
Full service/Pydantic acceptance belongs to the separate CI integration suite.
"""
import ast
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


def production_functions(cache):
    tree = ast.parse((ROOT / 'file_intelligence/file_service.py').read_text())
    nodes = []
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name in {'_safe_dir', 'tree', 'cache_search'}:
            node.decorator_list = []
            nodes.append(node)
    future = ast.ImportFrom(module='__future__', names=[ast.alias(name='annotations')], level=0)
    namespace = {'Path': Path, 'Any': Any, 'json': json, 'CACHE_DIR': cache, 'MAX_CACHE_EXCERPT_CHARS': 1200}
    exec(compile(ast.fix_missing_locations(ast.Module(body=[future] + nodes, type_ignores=[])), 'file_intelligence/file_service.py', 'exec'), namespace)
    return namespace


class ListingOwnerBudgets(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.cache = self.folder / 'cache'; self.cache.mkdir()
        self.runtime = production_functions(self.cache)

    def test_tree_exact_fit_is_complete_and_actual_overflow_is_partial(self):
        folder = self.folder / 'tree'; folder.mkdir()
        for number in range(3): (folder / str(number)).write_text('actual content')
        exact = self.runtime['tree'](SimpleNamespace(path=str(folder), max_items=3))
        self.assertEqual(len(exact['items']), 3); self.assertFalse(exact['truncated'])
        limited = self.runtime['tree'](SimpleNamespace(path=str(folder), max_items=2))
        self.assertEqual(len(limited['items']), 2); self.assertTrue(limited['truncated'])

    def test_tree_accepts_request_above_old_ceiling_without_function_clamp(self):
        folder = self.folder / 'many'; folder.mkdir()
        for number in range(5001): (folder / str(number)).touch()
        result = self.runtime['tree'](SimpleNamespace(path=str(folder), max_items=5001))
        self.assertEqual(len(result['items']), 5001); self.assertFalse(result['truncated'])

    def test_search_raised_budget_and_actual_excerpt_omission(self):
        for number in range(101):
            (self.cache / f'{number}.json').write_text(json.dumps({'name':f'match{number}', 'content':'match-' + 'x'*1300}))
        request = SimpleNamespace(query='match', limit=101)
        limited_excerpt = self.runtime['cache_search'](request)
        self.assertEqual(len(limited_excerpt['results']), 101)
        self.assertTrue(limited_excerpt['limit_reached'])
        self.assertEqual(limited_excerpt['more_results'], 'unknown')
        self.assertTrue(limited_excerpt['results'][0]['excerpt_truncated'])
        self.runtime['MAX_CACHE_EXCERPT_CHARS'] = 1400
        full_excerpt = self.runtime['cache_search'](SimpleNamespace(query='match', limit=102))
        self.assertFalse(full_excerpt['limit_reached'])
        self.assertEqual(full_excerpt['more_results'], 'none')
        self.assertFalse(full_excerpt['results'][0]['excerpt_truncated'])
        self.assertGreater(len(full_excerpt['results'][0]['excerpt']), 1200)

    def test_search_skips_corrupt_and_nonobject_cache_entries(self):
        (self.cache/'bad.json').write_text('{bad')
        (self.cache/'array.json').write_text('[]')
        (self.cache/'good.json').write_text('{"name":"match","content":"match"}')
        result = self.runtime['cache_search'](SimpleNamespace(query='match', limit=20))
        self.assertEqual(len(result['results']), 1)
        self.assertFalse(result['limit_reached'])


if __name__ == '__main__': unittest.main()
