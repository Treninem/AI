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

adb install --no-incremental -r "$apk"
# This is a release APK: run-as is intentionally unavailable. Root belongs
# only to the disposable google_apis emulator, never to the shipped product.
adb root
adb wait-for-device
test "$(adb shell id -u | tr -d '\r')" = '0'

launcher=''
for _attempt in $(seq 1 30); do
  launcher="$(adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "$pkg" 2>/dev/null | tr -d '\r' | grep -E '^[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+' | tail -n1 || true)"
  if [ -n "$launcher" ]; then
    break
  fi
  sleep 2
done
if [ -z "$launcher" ]; then
  echo 'Android package manager did not resolve the AuroraFox launcher after adb root.' >&2
  adb shell dumpsys package "$pkg" >&2 || true
  exit 1
fi

app_files="/data/user/0/$pkg/files"
adb shell rm -f "$app_files/core-benchmark-android-e2e.json"
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
adb shell am start -W -n "$launcher"

report_path=''
completed=0
for _attempt in $(seq 1 240); do
  report_path="$(adb shell find "$app_files" -name core-benchmark-android-e2e.json -print 2>/dev/null | tr -d '\r' | head -n1 || true)"
  if [ -n "$report_path" ]; then
    # A running report is useful failure evidence, but not acceptance. Reads
    # may race with the writer; retry malformed/partial JSON until the bound.
    if adb exec-out cat "$report_path" > "$report.tmp"; then
      if python3 - "$report.tmp" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], encoding='utf-8') as file:
        data = json.load(file)
except (OSError, ValueError):
    raise SystemExit(1)
raise SystemExit(0 if isinstance(data, dict) else 1)
PY
      then
        mv "$report.tmp" "$report"
        if python3 - "$report" <<'PY'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as file:
    data = json.load(file)
raise SystemExit(0 if data.get('status') == 'completed' else 1)
PY
        then
          completed=1
          break
        fi
      fi
    fi
  fi
  if ! adb shell pidof "$pkg" >/dev/null 2>&1; then
    echo 'Android benchmark process exited before a completed report.' >&2
    break
  fi
  sleep 5
done

capture_logcat
if [ "$completed" != '1' ]; then
  echo 'Android AIClient E2E benchmark did not produce a completed report within 1200 seconds.' >&2
  cat "$report" >&2 2>/dev/null || true
  grep -E 'godot|Godot|aurorafox|AuroraFox|FATAL|AndroidRuntime|SCRIPT ERROR|Parse Error|Fatal signal' "$logcat_report" | tail -n 200 >&2 || true
  exit 1
fi

source_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 "$source_script_dir/report_identity.py" --report "$report"

python3 - <<'PY'
import json
from pathlib import Path

data = json.loads(Path('artifacts/core-benchmark-android-e2e.json').read_text(encoding='utf-8'))
required = {
    'offline_network_guard', 'bundled_core_identity', 'cold_start_first_response',
    'basic_reasoning', 'russian_dialog', 'multi_turn_context',
    'core_knowledge_retrieval', 'installed_knowledge_pack',
    'installed_voice_tts', 'installed_voice_stt',
    'installed_ocr_bilingual', 'compatibility_switch_isolation'
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
if not required.issubset(rows): failures.append('missing_scenarios')
if any(not bool(rows[name].get('passed', False)) for name in required if name in rows): failures.append('scenario_failure')
if any(str(rows[name].get('runtime', '')) not in ('', 'aurora_core_android') for name in required if name in rows): failures.append('unexpected_runtime')
pack = rows.get('installed_knowledge_pack', {})
if pack and (
    pack.get('status') != 'ready'
    or int(pack.get('imported_shards', 0)) != 1
    or int(pack.get('resumed_skipped_shards', 0)) != 1
    or pack.get('resumable') is not True
    or pack.get('offline') is not True
    or pack.get('external_ai_required') is not False
    or pack.get('query_match') is not True
): failures.append('knowledge_pack_contract')
perf = data.get('performance', {})
if float(perf.get('cold_first_response_ms', 0) or 0) <= 0: failures.append('cold_measurement')
if float(perf.get('warm_median_ms', 0) or 0) <= 0: failures.append('warm_measurement')
if float(perf.get('suite_wall_ms', 0) or 0) <= 0: failures.append('wall_measurement')
print(json.dumps(data, ensure_ascii=False, indent=2))
if failures:
    raise SystemExit('AURORAFOX_ANDROID_NORMAL_PATH_GATE_FAILED: ' + ','.join(failures))
print('AURORAFOX_ANDROID_INSTALLED_VOICE_OCR_KNOWLEDGE_OK')
print('AURORAFOX_ANDROID_NORMAL_PATH_GATE_OK')
PY
