#!/usr/bin/env python3
# macmin.py — backend helper for the MacShell macOS-style minimize system.
#
# Hyprland has no native minimize, so a window is "minimized" by moving it to the
# special:minimized workspace.  The visual part (screenshot flying to the Dock
# icon) is done in Quickshell; this script only talks to Hyprland / grim.
#
#   prep <addr>      geometry + a PNG screenshot of the window on stdout (JSON),
#                    the window is NOT moved — the shell moves it after it has
#                    placed the ghost image
#
# <addr> is a Hyprland window address, with or without the 0x prefix.

import sys
import os
import json
import subprocess
import re


def cache_dir():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    d = os.path.join(base, "macshell", "minimize")
    os.makedirs(d, exist_ok=True)
    return d


def run(args):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=5)
        return p.stdout
    except Exception:
        return ""


def clients():
    try:
        return json.loads(run(["hyprctl", "-j", "clients"]) or "[]")
    except Exception:
        return []


def monitors():
    try:
        return json.loads(run(["hyprctl", "-j", "monitors"]) or "[]")
    except Exception:
        return []


def norm(a):
    value = str(a or "").removeprefix("0x")
    return value if re.fullmatch(r"[a-fA-F0-9]+", value) else ""


def find(addr):
    a = norm(addr)
    for c in clients():
        if norm(c.get("address")) == a:
            return c
    return None


def clamp(v, lo, hi):
    if hi < lo:
        hi = lo
    return max(lo, min(hi, v))


def cmd_prep(addr):
    c = find(addr)
    if not c:
        print("{}")
        return

    at = c.get("at") or [0, 0]
    size = c.get("size") or [0, 0]
    ws = c.get("workspace") or {}

    x, y = int(at[0]), int(at[1])
    w, h = int(size[0]), int(size[1])

    # keep the capture region inside the monitor it lives on
    mon = None
    for m in monitors():
        if m.get("id") == c.get("monitor"):
            mon = m
            break
    if mon:
        mx, my = int(mon.get("x", 0)), int(mon.get("y", 0))
        mw, mh = int(mon.get("width", 0)), int(mon.get("height", 0))
        if mon.get("transform", 0) % 2:
            mw, mh = mh, mw
        scale = mon.get("scale", 1) or 1
        mw, mh = int(mw / scale), int(mh / scale)
        x = clamp(x, mx, mx + mw)
        y = clamp(y, my, my + mh)
        w = clamp(w, 1, mx + mw - x)
        h = clamp(h, 1, my + mh - y)

    shot = os.path.join(cache_dir(), norm(addr) + ".png")
    have = False
    if w >= 8 and h >= 8:
        try:
            if os.path.exists(shot):
                os.remove(shot)
        except OSError:
            pass
        run(["grim", "-g", "%d,%d %dx%d" % (x, y, w, h), "-t", "png", shot])
        have = os.path.exists(shot) and os.path.getsize(shot) > 0

    out = {
        "ok": True,
        "addr": norm(addr),
        "pid": c.get("pid"),
        "fullscreen": c.get("fullscreen", 0),
        "appId": c.get("class") or c.get("initialClass") or "",
        "title": c.get("title") or "",
        "ws": ws.get("id", 1),
        "wsName": ws.get("name", ""),
        "mon": c.get("monitor", 0),
        "floating": bool(c.get("floating", True)),
        "at": [int(at[0]), int(at[1])],
        "size": [int(size[0]), int(size[1])],
        "shot": shot if have else "",
    }
    print(json.dumps(out))


def main():
    if len(sys.argv) < 2:
        print("{}")
        return
    cmd = sys.argv[1]
    if cmd == "prep":
        cmd_prep(sys.argv[2] if len(sys.argv) > 2 else "")
    elif cmd == "cleanup":
        a = norm(sys.argv[2] if len(sys.argv) > 2 else "")
        if a:
            try:
                os.unlink(os.path.join(cache_dir(), a + ".png"))
            except FileNotFoundError:
                pass
    else:
        print("{}")


if __name__ == "__main__":
    main()
