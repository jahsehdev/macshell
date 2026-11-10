#!/usr/bin/env bash
set -euo pipefail
menu_source=$(cd -- "$(dirname -- "$0")/.." && pwd)
menu_test_root=$(mktemp -d /tmp/macshell-menu-theme.XXXXXX)
ln -s "$menu_source" "$menu_test_root/Common"
ln -s "$menu_source/../MacShell" "$menu_test_root/MacShell"
mkdir -p "$menu_test_root/runtime" "$menu_test_root/config/macshell" "$menu_test_root/previews"
chmod 700 "$menu_test_root/runtime"
export QT_QPA_PLATFORM="${MACSHELL_MENU_TEST_PLATFORM:-offscreen}" QT_QUICK_BACKEND="${MACSHELL_MENU_TEST_BACKEND:-software}"
export XDG_RUNTIME_DIR="$menu_test_root/runtime" XDG_CONFIG_HOME="$menu_test_root/config"
export MACSHELL_PREVIEW_DIR="$menu_test_root/previews"
unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
cat > "$menu_test_root/shell.qml" <<'QML'
import Quickshell
import "Common/tests"
ShellRoot { MenuThemeTests {} }
QML
set +e
timeout 20 qs -p "$menu_test_root" --no-color > "$menu_test_root/tests.log" 2>&1
menu_test_status=$?
set -e
cat "$menu_test_root/tests.log"
printf 'Test artifacts: %s\n' "$menu_test_root"
[[ $menu_test_status == 0 ]]
rg -q 'TOTALS [1-9][0-9]* passed, 0 failed' "$menu_test_root/tests.log"
if rg -n '(WARN (qml|scene):|Binding loop|ERROR qml:|TypeError|ReferenceError|FAIL!)' "$menu_test_root/tests.log"; then exit 1; fi
