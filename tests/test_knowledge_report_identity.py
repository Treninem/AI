import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    'knowledge_identity_runner', ROOT / 'benchmarks/knowledge/run_knowledge_benchmark.py'
)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class KnowledgeReportIdentityTests(unittest.TestCase):
    def make_checkout(self, repo):
        def git(*args):
            return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()
        git('init', '-q')
        git('config', 'user.name', 'Knowledge QA')
        git('config', 'user.email', 'qa@example.invalid')
        (repo / 'source').write_text('actual source')
        git('add', 'source')
        git('commit', '-qm', 'source')
        return git('rev-parse', 'HEAD')

    def test_real_checkout_not_pr_merge(self):
        with tempfile.TemporaryDirectory() as folder:
            repo = Path(folder)
            actual = self.make_checkout(repo)
            with patch.dict(os.environ, {'GITHUB_SHA': 'f' * 40, 'AURORAFOX_BENCHMARK_EXPECTED_SHA': actual}):
                self.assertEqual(runner.comparable_identity([], repo)['git_sha'], actual)

    def test_wrong_checkout_fails_before_godot_or_report(self):
        with tempfile.TemporaryDirectory() as folder:
            repo = Path(folder)
            self.make_checkout(repo)
            report = repo / 'existing-report.json'
            report.write_text('{"existing":"evidence"}')
            with patch.dict(os.environ, {'AURORAFOX_BENCHMARK_EXPECTED_SHA': '0' * 40}), \
                 patch.object(runner.Path, 'cwd', return_value=repo), \
                 patch('sys.argv', ['runner', '--godot', 'MUST_NOT_RUN', '--report', str(report)]):
                with self.assertRaisesRegex(ValueError, 'Benchmark source mismatch'):
                    runner.main()
            self.assertEqual(report.read_text(), '{"existing":"evidence"}')
            self.assertFalse((repo / 'logs').exists())

    def test_missing_checkout_does_not_use_ci_event(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch.dict(os.environ, {'GITHUB_SHA': 'f' * 40, 'AURORAFOX_BENCHMARK_EXPECTED_SHA': ''}):
                with self.assertRaisesRegex(ValueError, 'Unable to identify'):
                    runner.comparable_identity([], Path(folder))
