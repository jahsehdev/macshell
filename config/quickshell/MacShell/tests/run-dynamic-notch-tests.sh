#!/usr/bin/env bash
set -euo pipefail
notch_source=$(cd -- "$(dirname -- "$0")/.." && pwd)
notch_test_root=$(mktemp -d /tmp/macshell-dynamic-notch.XXXXXX)
ln -s "$notch_source" "$notch_test_root/MacShell"
mkdir -p "$notch_test_root/runtime" "$notch_test_root/config"
chmod 700 "$notch_test_root/runtime"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export XDG_RUNTIME_DIR="$notch_test_root/runtime" XDG_CONFIG_HOME="$notch_test_root/config"
unset WAYLAND_DISPLAY
node --test --test-isolation=none "$notch_source/tests/test_dynamic_notch.cjs" "$notch_source/tests/test_notch_tools.cjs" "$notch_source/tests/test_notch_geometry.cjs" "$notch_source/tests/test_notch_devices.cjs" "$notch_source/tests/test_notch_calendar.cjs" "$notch_source/tests/test_notch_stats.cjs"
python3 "$notch_source/tests/test_notch_bluetooth_snapshot.py"
python3 "$notch_source/tests/test_notch_shelf.py"
python3 "$notch_source/tests/test_notch_spectrum.py"
python3 "$notch_source/tests/test_notch_recording.py"
python3 "$notch_source/tests/test_notch_downloads.py"
python3 "$notch_source/tests/test_notch_stats.py"
python3 "$notch_source/tests/test_notch_weather_service.py"
export MACSHELL_SPECTRUM_TEST_HELPER="$notch_test_root/spectrum helper.py"
cat > "$MACSHELL_SPECTRUM_TEST_HELPER" <<'PYTHON'
import json
from pathlib import Path
import sys
import time
marker=Path(__file__).with_suffix('.attempts')
attempt=int(marker.read_text())+1 if marker.exists() else 1
marker.write_text(str(attempt))
if attempt==1:
    sys.exit(1)
for frame in range(120):
    print(json.dumps({'bands':[0.1 if frame%2 else 0.8]*24}),flush=True)
    time.sleep(0.05)
PYTHON
cat > "$notch_test_root/shell.qml" <<'QML'
import Quickshell
import "MacShell/tests"
ShellRoot { DynamicNotchTests {} }
QML
timeout 90 qs -p "$notch_test_root" --no-color > "$notch_test_root/tests.log" 2>&1
cat "$notch_test_root/tests.log"
rg -q 'TOTALS [1-9][0-9]* passed, 0 failed' "$notch_test_root/tests.log"
if rg -n '(WARN (qml|scene):|ERROR qml:|TypeError|ReferenceError)' "$notch_test_root/tests.log"; then exit 1; fi
printf 'Test artifacts: %s\n' "$notch_test_root"
