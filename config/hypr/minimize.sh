#!/bin/sh
# macOS-style minimize for Hyprland, driven by the yellow traffic light.
#
#   minimize            park the focused window on the special:minimized workspace
#                       (if it is already minimized, restore it instead)
#   restore             send the focused window back to the workspace it was
#                       minimized from
#
# Hyprland has no native minimize in this version, so a window is "minimized" by
# moving it onto the special workspace. To bring it back to the right screen we
# remember its workspace in $XDG_RUNTIME_DIR/hypr-minimized ("<addr> <workspace>"
# per line). Nothing else is touched: no window is closed or killed.

state="${XDG_RUNTIME_DIR:-/tmp}/hypr-minimized"
mkdir -p "$(dirname "$state")" 2>/dev/null
touch "$state" 2>/dev/null

# MacShell's animated minimize system (window flies to its Dock icon) takes over
# whenever it is running. `qs ipc call` prints nothing on success and a message
# ("Target not found.") on failure, so a non-empty answer means: fall back below.
try_ipc() {
    command -v qs >/dev/null 2>&1 || return 1
    out=$(qs -c MacShell ipc call "$1" "$2" 2>&1) || return 1
    [ -z "$out" ] || return 1
    return 0
}
case "${1:-}" in
minimize) try_ipc minimize focused && exit 0 ;;
restore)  try_ipc minimize restore && exit 0 ;;
esac

# "<address> <workspace id> <workspace name>" of the focused window
focused() {
    hyprctl activewindow -j 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ws = d.get("workspace", {})
print(d.get("address", "0x0"), ws.get("id", 0), ws.get("name", ""))'
}

set_ws() {   # set_ws <address> <workspace>
    grep -v "^$1 " "$state" >"$state.tmp" 2>/dev/null || : >"$state.tmp"
    [ -n "${2:-}" ] && printf '%s %s\n' "$1" "$2" >>"$state.tmp"
    mv -f "$state.tmp" "$state" 2>/dev/null || cp -f "$state.tmp" "$state" 2>/dev/null
}

get_ws() {   # get_ws <address>
    awk -v a="$1" '$1 == a { print $2; exit }' "$state" 2>/dev/null
}

case "${1:-}" in
minimize)
    set -- $(focused)
    [ $# -lt 2 ] && exit 0
    addr=$1; ws=$2
    if [ "$ws" -lt 0 ]; then
        # already minimized -> treat the click as "bring it back"
        back=$(get_ws "$addr")
        [ -z "$back" ] && back=1
        hyprctl dispatch "hl.dsp.window.move({ workspace = $back })" >/dev/null 2>&1
        set_ws "$addr" ""
    else
        set_ws "$addr" "$ws"
        hyprctl dispatch "hl.dsp.window.move({ workspace = 'special:minimized' })" >/dev/null 2>&1
    fi
    ;;
restore)
    set -- $(focused)
    [ $# -lt 2 ] && exit 0
    addr=$1; ws=$2
    [ "$ws" -ge 0 ] && exit 0        # not minimized -> never touch a normal window
    back=$(get_ws "$addr")
    if [ -n "$back" ]; then
        hyprctl dispatch "hl.dsp.window.move({ workspace = $back })" >/dev/null 2>&1
        set_ws "$addr" ""
    fi
    ;;
*)
    echo "usage: $0 minimize|restore" >&2
    exit 1
    ;;
esac
exit 0
