#!/usr/bin/env python3
"""Apply the shared titlebar double-click preference to the focused window."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from desktop_controller import Backend, CONFIG, address, atomic, lua


def bounds(monitor):
    w, h = monitor['width'], monitor['height']
    if monitor.get('transform', 0) % 2:
        w, h = h, w
    scale = monitor.get('scale', 1) or 1
    l, t, r, b = monitor.get('reserved', [0, 0, 0, 0])
    return [int(monitor['x'] + l), int(monitor['y'] + t),
            max(1, int(w / scale - l - r)), max(1, int(h / scale - t - b))]


def perform(backend, action, window, monitors, path):
    a = address(window.get('address'))
    if not a or action == 'none':
        return
    if action == 'minimize':
        backend.run(['qs', '-c', 'MacShell', 'ipc', 'call', 'minimize', 'addr', a])
        return
    monitor = next((m for m in monitors if m['id'] == window.get('monitor')), None)
    if not monitor:
        return
    try:
        records = json.loads(path.read_text())
    except (OSError, ValueError):
        records = {}
    record = records.get(a)
    if record and record.get('pid') == window.get('pid') and record.get('action') == action:
        backend.dispatch('hl.dsp.window.fullscreen_state({window=' + lua('address:0x' + a) + ',internal=0,client=0})')
        backend.geometry(a, record)
        del records[a]
    else:
        original = record if record and record.get('pid') == window.get('pid') else dict(
            pid=window.get('pid'), at=window['at'], size=window['size'], floating=window.get('floating', True))
        original['action'] = action
        records[a] = original
        atomic(path, records)
        if action == 'zoom':
            # Native maximize lets the application participate in choosing its
            # preferred size through its normal Wayland configure handshake.
            backend.dispatch('hl.dsp.window.fullscreen({window=' + lua('address:0x' + a) + ',mode="maximized",action="toggle"})')
        else:
            x, y, w, h = bounds(monitor)
            backend.dispatch('hl.dsp.window.fullscreen_state({window=' + lua('address:0x' + a) + ',internal=0,client=0})')
            backend.geometry(a, dict(at=[x, y], size=[w, h], floating=True))
    atomic(path, records)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pid', type=int)
    args = parser.parse_args()
    try:
        preference = json.loads((CONFIG / 'desktop-dock.json').read_text())
    except (OSError, ValueError):
        preference = {}
    backend = Backend()
    try:
        window = json.loads(backend.run(['hyprctl', '-j', 'activewindow']))
        if args.pid and window.get('pid') != args.pid:
            return
        _, monitors = backend.snapshot()
        perform(backend, preference.get('titlebarAction', 'fill'), window, monitors, CONFIG / 'titlebar-state.json')
    except (RuntimeError, ValueError, KeyError, OSError, subprocess.TimeoutExpired):
        return

if __name__ == '__main__':
    main()
