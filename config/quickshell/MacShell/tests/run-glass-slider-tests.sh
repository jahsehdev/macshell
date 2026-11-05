#!/usr/bin/env bash
set -euo pipefail
glass_source=$(cd -- "$(dirname -- "$0")/.." && pwd)
glass_test_root=$(mktemp -d /tmp/macshell-glass-slider.XXXXXX)
ln -s "$glass_source" "$glass_test_root/MacShell"
ln -s "$glass_source/../Common" "$glass_test_root/Common"
mkdir -p "$glass_test_root/runtime" "$glass_test_root/config/macshell"
chmod 700 "$glass_test_root/runtime"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export XDG_RUNTIME_DIR="$glass_test_root/runtime" XDG_CONFIG_HOME="$glass_test_root/config"
unset WAYLAND_DISPLAY
node --test --test-isolation=none "$glass_source/../Common/tests/test_glass_material.cjs"
cat > "$glass_test_root/shell.qml" <<'QML'
import Quickshell
import "MacShell/tests"
ShellRoot { GlassMaterialPreviewTests {} }
QML
timeout 15 qs -p "$glass_test_root" --no-color > "$glass_test_root/tests.log" 2>&1
cat "$glass_test_root/tests.log"
rg -q 'TOTALS [1-9][0-9]* passed, 0 failed' "$glass_test_root/tests.log"
if rg -n '(WARN (qml|scene):|ERROR qml:|TypeError|ReferenceError)' "$glass_test_root/tests.log"; then exit 1; fi
cat > "$glass_test_root/shell.qml" <<'QML'
import Quickshell
import QtQuick
import "MacShell/Common" as Common
ShellRoot {
    property real savedIntensity: Common.GlassMaterial.intensity
    Timer {
        interval: 350; running: true
        onTriggered: {
            console.log(savedIntensity === 0.37 ? "PASS intensity survives restart" : "FAIL restart intensity", savedIntensity);
            Qt.quit();
        }
    }
}
QML
timeout 5 qs -p "$glass_test_root" --no-color > "$glass_test_root/restart.log" 2>&1
cat "$glass_test_root/restart.log"
rg -q 'PASS intensity survives restart' "$glass_test_root/restart.log"
printf 'Test artifacts: %s\n' "$glass_test_root"
