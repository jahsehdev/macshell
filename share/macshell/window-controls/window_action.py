#!/usr/bin/env python3
"""Small, bounded Hyprland actions for application-owned window controls."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

CLASSES = {
    "tabby": {"tabby", "org.tabby"},
    "dolphin": {"org.kde.dolphin", "dolphin"},
    "kitty": {"kitty"},
    "spotify": {"spotify"},
    "antigravity": {"antigravity-ide"},
    "qt6ct": {"qt6ct"},
    "kvantummanager": {"kvantummanager", "kvantum manager"},
    "cmake-gui": {"cmake-gui", "cmakesetup"},
    "qv4l2": {"qv4l2"},
    "qvidcap": {"qvidcap"},
    "nm-connection-editor": {"nm-connection-editor", "nm-connection-list"},
}


def hypr(*args):
    result = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=3)
    if result.returncode:
        raise RuntimeError("Hyprland is unavailable")
    return result.stdout


def belongs(window, app, pid=None, title=None):
    if window.get("class", "").lower() not in CLASSES[app]:
        return False
    if pid is not None and window.get("pid") != pid:
        return False
    actual = window.get("title", "")
    return not title or actual == title or actual.startswith(title + " — ") or actual.startswith(title + " – ")


def dispatch(action, address):
    if not re.fullmatch(r"0x[0-9a-fA-F]+", address):
        raise ValueError("Invalid window address")
    selector = json.dumps("address:" + address)
    if action == "ready":
        expression = f'hl.dsp.window.tag({{window={selector},tag="+macshell-native-controls"}})'
    elif action == "close":
        expression = f"hl.dsp.window.close({{window={selector}}})"
    elif action == "maximize":
        expression = f'hl.dsp.window.fullscreen({{window={selector},mode="maximized",action="toggle"}})'
    else:
        raise ValueError("Unsupported action")
    return hypr("dispatch", expression)


def perform(action, app, pid=None, title=None):
    if action == "ready":
        # Only remove an external header after the native UI reports readiness.
        for attempt in range(20):
            windows = json.loads(hypr("-j", "clients"))
            matches = [w for w in windows if belongs(w, app, pid, title)]
            if matches:
                for window in matches:
                    dispatch("ready", window["address"])
                return True
            time.sleep(0.05)
        return False
    window = json.loads(hypr("-j", "activewindow"))
    if not belongs(window, app, pid, title):
        return False
    if action == "minimize":
        helper = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "hypr/minimize.sh"
        return subprocess.run(["/bin/sh", str(helper), "minimize"], timeout=8).returncode == 0
    dispatch(action, window["address"])
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("ready", "close", "minimize", "maximize"))
    parser.add_argument("app", choices=CLASSES)
    parser.add_argument("--pid", type=int)
    parser.add_argument("--title")
    args = parser.parse_args()
    try:
        return 0 if perform(args.action, args.app, args.pid, args.title) else 1
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired):
        return 1


if __name__ == "__main__":
    sys.exit(main())
