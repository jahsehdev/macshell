#!/usr/bin/env bash
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "$0")/../.." && pwd)
test_dir=$(mktemp -d /tmp/macshell-shared-material.XXXXXX)
mkdir -p "$test_dir/runtime" "$test_dir/config/macdock" "$test_dir/config/macshell"
chmod 700 "$test_dir/runtime"
ln -s "$source_dir/Common" "$test_dir/Common"
ln -s "$source_dir/MacLock" "$test_dir/MacLock"
ln -s "$source_dir/MacShell" "$test_dir/MacShell"
ln -s "$source_dir/launchpad" "$test_dir/launchpad"
cat > "$test_dir/shell.qml" <<'QML'
import Quickshell
import "Common/tests"
ShellRoot { GlassUniformsTests {} }
QML
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    XDG_RUNTIME_DIR="$test_dir/runtime" XDG_CONFIG_HOME="$test_dir/config" \
    timeout 45 qs -p "$test_dir" --no-color > "$test_dir/tests.log" 2>&1
cat "$test_dir/tests.log"
rg -q 'GLASS_TOTALS [1-9][0-9]* passed, 0 failed' "$test_dir/tests.log"
if rg -n '(WARN (qml|scene):|TypeError|ReferenceError|Failed to load configuration)' "$test_dir/tests.log"; then exit 1; fi
printf 'Test artifacts: %s\n' "$test_dir"
