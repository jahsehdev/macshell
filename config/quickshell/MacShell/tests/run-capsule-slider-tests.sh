#!/usr/bin/env bash
set -euo pipefail
capsule_source=$(cd -- "$(dirname -- "$0")/.." && pwd)
capsule_test_root=$(mktemp -d /tmp/macshell-capsule-sliders.XXXXXX)
ln -s "$capsule_source" "$capsule_test_root/MacShell"
ln -s "$capsule_source/../Common" "$capsule_test_root/Common"
mkdir -p "$capsule_test_root/runtime" "$capsule_test_root/config/macshell"
chmod 700 "$capsule_test_root/runtime"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export XDG_RUNTIME_DIR="$capsule_test_root/runtime" XDG_CONFIG_HOME="$capsule_test_root/config"
unset WAYLAND_DISPLAY
cat > "$capsule_test_root/shell.qml" <<'QML'
import Quickshell
import "MacShell/tests"
ShellRoot { GlassSliderTests {} }
QML
timeout 20 qs -p "$capsule_test_root" --no-color > "$capsule_test_root/tests.log" 2>&1
cat "$capsule_test_root/tests.log"
rg -q 'TOTALS [1-9][0-9]* passed, 0 failed' "$capsule_test_root/tests.log"
if rg -n '(WARN (qml|scene):|ERROR qml:|TypeError|ReferenceError)' "$capsule_test_root/tests.log"; then exit 1; fi
printf 'Test artifacts: %s\n' "$capsule_test_root"
