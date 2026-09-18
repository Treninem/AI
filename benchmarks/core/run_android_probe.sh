#!/usr/bin/env bash
set -euo pipefail

core_model="${1:?usage: run_android_probe.sh <core-model-path>}"
pkg='com.aurorafox.corebenchmark'
apk='benchmarks/core/android_probe/app/build/outputs/apk/benchmark/app-benchmark.apk'
report='artifacts/core-benchmark-android.json'
logcat_report='artifacts/core-benchmark-android-logcat.txt'

mkdir -p artifacts
test -s "$apk"
test -s "$core_model"

capture_logcat() {
  adb logcat -d -v brief > "$logcat_report" 2>/dev/null || true
}
trap capture_logcat EXIT

adb install -r "$apk"
if adb shell dumpsys package "$pkg" | grep -q 'android.permission.INTERNET'; then
  echo 'Benchmark app unexpectedly requests INTERNET permission.' >&2
  exit 1
fi

adb push "$core_model" /data/local/tmp/aurorafox-core.gguf
adb shell run-as "$pkg" mkdir -p files
adb shell run-as "$pkg" cp /data/local/tmp/aurorafox-core.gguf files/aurorafox-core.gguf
adb shell rm -f /data/local/tmp/aurorafox-core.gguf
adb shell run-as "$pkg" ls -l files/aurorafox-core.gguf

adb logcat -c
adb shell am force-stop "$pkg"
adb shell am start -W -n "$pkg/.MainActivity"

for _attempt in $(seq 1 180); do
  if adb shell run-as "$pkg" test -s files/core-benchmark-android.json; then
    break
  fi
  sleep 5
done

if ! adb shell run-as "$pkg" test -s files/core-benchmark-android.json; then
  echo 'Android Core benchmark timed out after 900 seconds.' >&2
  capture_logcat
  tail -n 400 "$logcat_report" >&2 || true
  exit 1
fi

adb shell run-as "$pkg" cat files/core-benchmark-android.json > "$report"
capture_logcat

python3 - <<'PY'
import json
from pathlib import Path

path = Path('artifacts/core-benchmark-android.json')
data = json.loads(path.read_text(encoding='utf-8'))
failures = []
if data.get('status') != 'completed': failures.append('status')
if data.get('passed') is not True: failures.append('overall')
env = data.get('environment', {})
if env.get('internet_permission_granted') is not False: failures.append('internet_permission')
if env.get('network_forbidden_by_manifest') is not True: failures.append('network_guard')
core = data.get('core', {})
if core.get('runtime') != 'llama.cpp': failures.append('runtime')
if core.get('runtime_build_type') != 'release' or core.get('runtime_debug') is not False: failures.append('production_release_runtime')
if core.get('native_library_loaded') is not True or core.get('llama_cpp') is not True: failures.append('native_llama')
if core.get('prepared_sha256') != 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5': failures.append('model_sha')
perf = data.get('performance', {})
for key in ('cold_first_response_ms', 'warm_median_ms', 'process_pss_mb'):
    if float(perf.get(key, 0) or 0) <= 0: failures.append(key)
scenarios = data.get('scenarios', [])
if len(scenarios) != 3 or any(row.get('passed') is not True for row in scenarios): failures.append('scenarios')
print(json.dumps(data, ensure_ascii=False, indent=2))
if failures:
    raise SystemExit('AURORAFOX_ANDROID_CORE_GATE_FAILED: ' + ','.join(failures))
print('AURORAFOX_ANDROID_REAL_CORE_GATE_OK')
PY
