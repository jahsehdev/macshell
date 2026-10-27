#!/usr/bin/env bash
set -euo pipefail
launchpad_source=$(cd -- "$(dirname -- "$0")/.." && pwd)
launchpad_test_root=$(mktemp -d /tmp/launchpad-drag-tests.XXXXXX)
node "$launchpad_source/tests/state-test.cjs"
cp -a -- "$launchpad_source" "$launchpad_test_root/config"
mkdir -p -- "$launchpad_test_root/runtime" "$launchpad_test_root/state"
chmod 700 -- "$launchpad_test_root/runtime"
cat > "$launchpad_test_root/config/shell.qml" <<'QML'
import Quickshell
import "tests"
ShellRoot { FolderDragTests {} }
QML
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export XDG_RUNTIME_DIR="$launchpad_test_root/runtime"
export XDG_STATE_HOME="$launchpad_test_root/state"
unset WAYLAND_DISPLAY
printf 'Isolated test artifacts: %s\n' "$launchpad_test_root"
timeout 60s qs -p "$launchpad_test_root/config" --no-color 2>&1 | tee "$launchpad_test_root/tests.log"
if ! rg -q 'TOTALS [1-9][0-9]* passed, 0 failed' "$launchpad_test_root/tests.log"; then exit 1; fi
if rg -n '(WARN (qml|scene):|ERROR qml:|TypeError|ReferenceError)' "$launchpad_test_root/tests.log"; then exit 1; fi
cat > "$launchpad_test_root/config/shell.qml" <<'QML'
import Quickshell
import "tests"
ShellRoot { PersistenceRestartTest {} }
QML
timeout 15s qs -p "$launchpad_test_root/config" --no-color 2>&1 | tee "$launchpad_test_root/restart.log"
rg -q 'PASS restart round trip' "$launchpad_test_root/restart.log"
