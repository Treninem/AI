#!/usr/bin/env bash
set -euo pipefail

apk="${1:?usage: run_android_godot_e2e.sh <apk-path>}"
pkg='com.aurorafox.ai'
report='artifacts/core-benchmark-android-e2e.json'
logcat_report='artifacts/core-benchmark-android-e2e-logcat.txt'
network_report='artifacts/core-benchmark-android-e2e-network.txt'

mkdir -p artifacts
test -s "$apk"

capture_logcat() {
  adb logcat -d -v brief > "$logcat_report" 2>/dev/null || true
}
trap capture_logcat EXIT

adb install -r "$apk"
adb shell cmd connectivity airplane-mode enable || true
adb shell settings put global airplane_mode_on 1 || true
adb shell svc wifi disable || true
adb shell svc data disable || true
sleep 2

state="$(adb shell settings get global airplane_mode_on 2>/dev/null | tr -d '\r' || true)"
ping_blocked=1
if adb shell ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
  ping_blocked=0
fi
printf 'airplane_mode=%s\nexternal_ping_blocked=%s\n' "$state" "$ping_blocked" | tee "$network_report"
if [ "$ping_blocked" != '1' ]; then
  echo 'Android emulator still has external network connectivity after offline setup.' >&2
  exit 1
fi

adb logcat -c
adb shell am force-stop "$pkg"
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1

report_path=''
for _attempt in $(seq 1 240); do
  report_path="$(adb shell run-as "$pkg" find files -name core-benchmark-android-e2e.json -print 2>/dev/null | tr -d '\r' | head -n1 || true)"
  if [ -n "$report_path" ]; then
    break
  fi
  sleep 5
done

capture_logcat
if [ -z "$report_path" ]; then
  echo 'Android AIClient E2E benchmark timed out after 1200 seconds.' >&2
  tail -n 500 "$logcat_report" >&2 || true
  exit 1
fi

adb exec-out run-as "$pkg" cat "$report_path" > "$report"

python3 - <<'PY'
import json
from pathlib import Path

data = json.loads(Path('artifacts/core-benchmark-android-e2e.json').read_text(encoding='utf-8'))
required = {
    'offline_network_guard', 'bundled_core_identity', 'cold_start_first_response',
    'basic_reasoning', 'russian_dialog', 'multi_turn_context',
    'core_knowledge_retrieval', 'compatibility_switch_isolation'
}
rows = {row.get('id'): row for row in data.get('scenarios', []) if isinstance(row, dict)}
failures = []
if data.get('status') != 'completed' or data.get('passed') is not True: failures.append('overall')
if data.get('platform') != 'Android': failures.append('platform')
if data.get('environment', {}).get('external_network_probe_blocked') is not True: failures.append('network_probe')
core = data.get('core', {})
if core.get('prepared_sha256') != 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5': failures.append('model_sha')
runtime_after = core.get('runtime_after', {})
if runtime_after.get('last_runtime') != 'aurora_core_android': failures.append('runtime_after')
if int(runtime_after.get('ollama_failures', -1)) != 0: failures.append('ollama_failures')
if set(rows) < required: failures.append('missing_scenarios')
if any(not bool(rows[name].get('passed', False)) for name in required if name in rows): failures.append('scenario_failure')
if any(str(rows[name].get('runtime', '')) not in ('', 'aurora_core_android') for name in required if name in rows): failures.append('unexpected_runtime')
perf = data.get('performance', {})
if float(perf.get('cold_first_response_ms', 0) or 0) <= 0: failures.append('cold_measurement')
if float(perf.get('warm_median_ms', 0) or 0) <= 0: failures.append('warm_measurement')
if float(perf.get('suite_wall_ms', 0) or 0) <= 0: failures.append('wall_measurement')
print(json.dumps(data, ensure_ascii=False, indent=2))
if failures:
    raise SystemExit('AURORAFOX_ANDROID_NORMAL_PATH_GATE_FAILED: ' + ','.join(failures))
print('AURORAFOX_ANDROID_NORMAL_PATH_GATE_OK')
PY
