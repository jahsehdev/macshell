#!/bin/sh
set -eu
tests_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
drag_build=$(mktemp -d /tmp/macshell-drag-check.XXXXXX)
trap 'rm -rf -- "$drag_build"' EXIT HUP INT TERM
/usr/lib/qt6/moc $(pkg-config --cflags Qt6Widgets) "$tests_root/../qt/controls.cpp" -o "$drag_build/controls.moc"
c++ -std=c++17 -fPIC -Wall -Wextra -Werror "$tests_root/test_qt_drag.cpp" \
    -I"$drag_build" $(pkg-config --cflags --libs Qt6Widgets Qt6Test) -o "$drag_build/qt-drag"
cat > "$drag_build/python3" <<'HELPER'
#!/bin/sh
printf '%s\n' "$@" >> "$MACSHELL_GESTURE_LOG"
HELPER
chmod +x "$drag_build/python3"
PATH="$drag_build:$PATH" MACSHELL_GESTURE_LOG="$drag_build/gestures.log" QT_QPA_PLATFORM=offscreen "$drag_build/qt-drag"
XDG_RUNTIME_DIR="$drag_build" lua "$tests_root/test_zoom_drag.lua"
node "$tests_root/../../tabby/test_plugin.cjs"
