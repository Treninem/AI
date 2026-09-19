#!/usr/bin/env bash
set -euo pipefail

apk="${1:?usage: run_android_apk_smoke.sh <apk-path> <numeric-version>}"
version="${2:?numeric version required}"
pkg='com.aurorafox.ai'
mkdir -p build/android
test -s "$apk"

capture_logcat() {
  # ADB collection itself returned 255 in run 35253859322 after a successful
  # install/launch. Retry the transport, while preserving stderr and requiring
  # a successful collection before the smoke can pass.
  for _attempt in 1 2 3; do
    if timeout 30s adb logcat -d -v brief > build/android/emulator-logcat.tmp 2>> build/android/emulator-logcat-errors.txt; then
      mv build/android/emulator-logcat.tmp build/android/emulator-logcat.txt
      return 0
    fi
    adb wait-for-device
  done
  cat build/android/emulator-logcat-errors.txt >&2
  return 1
}
trap 'capture_logcat || true' EXIT

adb install -r "$apk"
adb shell pm path "$pkg" > build/android/emulator-package.txt
grep -q '^package:' build/android/emulator-package.txt
adb logcat -c
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1
sleep 8
capture_logcat
adb shell pidof "$pkg" | tr -d '\r' > build/android/emulator-pid.txt
test -s build/android/emulator-pid.txt
adb shell dumpsys package "$pkg" | grep -F "versionName=$version"
if grep -A10 -B4 'FATAL EXCEPTION' build/android/emulator-logcat.txt | grep -q "$pkg"; then
  echo 'AuroraFox crashed during Android launch smoke.' >&2
  grep -A20 -B6 'FATAL EXCEPTION' build/android/emulator-logcat.txt | tail -n 120 >&2
  exit 1
fi
echo "AURORA_ANDROID_EMULATOR_OK pid=$(cat build/android/emulator-pid.txt)"
