#!/usr/bin/env bash
set -euo pipefail
source_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d /tmp/opencode/spotlight-gooey.XXXXXX)
ln -s "$source_root" "$test_root/MacShell"
cat > "$test_root/shell.qml" <<'QML'
import Quickshell
import "MacShell/tests"
ShellRoot { SpotlightGooeyTests {} }
QML
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    timeout 12 qs -p "$test_root" --no-color > "$test_root/tests.log" 2>&1
cat "$test_root/tests.log"
grep -Eq 'TOTALS [1-9][0-9]* passed, 0 failed' "$test_root/tests.log"
if grep -Eq '(ERROR|TypeError|ReferenceError)' "$test_root/tests.log"; then exit 1; fi
