"""Exercise release-report collection and rejection using a simulated adb."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / 'benchmarks/core/run_android_godot_e2e.sh'
REQUIRED = [
    'offline_network_guard', 'bundled_core_identity', 'cold_start_first_response',
    'basic_reasoning', 'russian_dialog', 'multi_turn_context',
    'core_knowledge_retrieval', 'compatibility_switch_isolation',
]
ADB = '''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
state = pathlib.Path(os.environ['FAKE_STATE'])
with open(state / 'calls', 'a') as file:
    file.write(json.dumps(args) + '\\n')
if args == ['shell', 'id', '-u']:
    print(os.environ.get('FAKE_UID', '0'))
elif args[:2] == ['shell', 'ping']:
    sys.exit(1)
elif args[:4] == ['shell', 'cmd', 'package', 'resolve-activity']:
    if os.environ.get('FAKE_NO_LAUNCHER') != '1':
        print('com.aurorafox.ai/com.godot.game.GodotApp')
elif args[:3] == ['shell', 'am', 'start']:
    print('Status: ok')
elif args[:3] == ['shell', 'settings', 'get']:
    print('1')
elif args[:2] == ['shell', 'find']:
    print('/data/user/0/com.aurorafox.ai/files/app_userdata/AuroraFox/core-benchmark-android-e2e.json')
elif args[:2] == ['exec-out', 'cat']:
    counter = state / 'counter'
    n = int(counter.read_text()) if counter.exists() else 0
    reports = json.loads((state / 'reports').read_text())
    print(json.dumps(reports[min(n, len(reports)-1)]))
    counter.write_text(str(n + 1))
elif args[:2] == ['shell', 'pidof']:
    if os.environ.get('FAKE_CRASH') == '1': sys.exit(1)
    print('1234')
elif args[:3] == ['shell', 'pm', 'path']:
    print('package:/data/app/base.apk')
elif args[:3] == ['shell', 'dumpsys', 'package']:
    print('versionName=1.3.0.0')
elif args[:2] == ['logcat', '-d']:
    count = state / 'logcat_count'
    n = int(count.read_text()) if count.exists() else 0
    count.write_text(str(n + 1))
    if os.environ.get('FAKE_LOGCAT') == 'always_fail' or (os.environ.get('FAKE_LOGCAT') == 'fail_once' and n == 0):
        print('simulated adb transport error', file=sys.stderr)
        sys.exit(255)
    if os.environ.get('FAKE_FATAL') == '1':
        print('E/AndroidRuntime: FATAL EXCEPTION\\nE/AndroidRuntime: Process: com.aurorafox.ai')
    print('E/godot: simulated diagnostic')
'''


def completed_report():
    return {
        'status': 'completed', 'passed': True, 'platform': 'Android',
        'environment': {'external_network_probe_blocked': True},
        'core': {
            'prepared_sha256': 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5',
            'runtime_after': {'last_runtime': 'aurora_core_android', 'ollama_failures': 0},
        },
        'scenarios': [{'id': name, 'passed': True, 'runtime': 'aurora_core_android'} for name in REQUIRED],
        'performance': {'cold_first_response_ms': 10, 'warm_median_ms': 5, 'suite_wall_ms': 30},
    }


class AndroidE2ERunnerTests(unittest.TestCase):
    def run_runner(self, reports, runner=RUNNER, **overrides):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            (work / 'adb').write_text(ADB)
            (work / 'adb').chmod(0o755)
            (work / 'sleep').write_text('#!/bin/sh\nexit 0\n')
            (work / 'sleep').chmod(0o755)
            (work / 'reports').write_text(json.dumps(reports))
            apk = work / 'release.apk'
            apk.write_bytes(b'fixture')
            env = dict(os.environ, PATH=str(work) + os.pathsep + os.environ['PATH'], FAKE_STATE=str(work), **overrides)
            result = subprocess.run(['bash', str(runner), str(apk), '1.3.0.0'], cwd=work, env=env, text=True, capture_output=True, timeout=30)
            report_path = work / 'artifacts/core-benchmark-android-e2e.json'
            saved = json.loads(report_path.read_text()) if report_path.exists() else None
            calls = [json.loads(line) for line in (work / 'calls').read_text().splitlines()]
            return result, saved, calls

    def test_waits_for_completed_release_report(self):
        result, saved, calls = self.run_runner([{'status': 'running'}, completed_report()])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(saved['status'], 'completed')
        self.assertEqual(sum(call[:2] == ['exec-out', 'cat'] for call in calls), 2)
        self.assertIn(['root'], calls)
        self.assertFalse(any('run-as' in call for call in calls))

    def test_missing_required_scenario_with_extra_row_is_rejected(self):
        report = completed_report()
        report['scenarios'][0]['id'] = 'unexpected_extra'
        result, _, _ = self.run_runner([report])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing_scenarios', result.stderr)

    def test_failed_quality_is_rejected(self):
        report = completed_report()
        report['passed'] = False
        report['scenarios'][0]['passed'] = False
        result, _, _ = self.run_runner([report])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('scenario_failure', result.stderr)

    def test_process_exit_preserves_partial_report_and_app_diagnostics(self):
        result, saved, _ = self.run_runner([{'status': 'running'}], FAKE_CRASH='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(saved['status'], 'running')
        self.assertIn('process exited', result.stderr)
        self.assertIn('simulated diagnostic', result.stderr)

    def test_non_root_emulator_is_rejected_before_launch(self):
        result, _, calls = self.run_runner([completed_report()], FAKE_UID='2000')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any('monkey' in call for call in calls))

    def test_missing_launcher_after_adb_root_is_rejected(self):
        result, _, calls = self.run_runner([completed_report()], FAKE_NO_LAUNCHER='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('did not resolve', result.stderr)
        self.assertFalse(any(call[:3] == ['shell', 'am', 'start'] for call in calls))

    def test_apk_smoke_retries_transient_logcat_failure(self):
        result, _, calls = self.run_runner([], runner=ROOT / 'benchmarks/core/run_android_apk_smoke.sh', FAKE_LOGCAT='fail_once')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('AURORA_ANDROID_EMULATOR_OK', result.stdout)
        self.assertGreaterEqual(sum(call[:2] == ['logcat', '-d'] for call in calls), 2)

    def test_apk_smoke_rejects_persistent_collection_failure(self):
        result, _, _ = self.run_runner([], runner=ROOT / 'benchmarks/core/run_android_apk_smoke.sh', FAKE_LOGCAT='always_fail')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('simulated adb transport error', result.stderr)
        self.assertNotIn('AURORA_ANDROID_EMULATOR_OK', result.stdout)

    def test_apk_smoke_rejects_real_app_crash(self):
        result, _, _ = self.run_runner([], runner=ROOT / 'benchmarks/core/run_android_apk_smoke.sh', FAKE_FATAL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('crashed during Android launch', result.stderr)


if __name__ == '__main__':
    unittest.main()
