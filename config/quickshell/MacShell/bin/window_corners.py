"""Expanded window corners: preserve rounding beside a permanently visible Dock."""
import json
import os
from pathlib import Path

SQUARE_TAG = 'macshell-square-window'
DOCK_ROUNDED_TAG = 'macshell-dock-rounded-window'


def dock_settings():
    path = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'macdock/settings.json'
    try:
        settings = json.loads(path.read_text())
        return settings if isinstance(settings, dict) else {}
    except (OSError, ValueError):
        return {}


def expanded(client, monitor):
    if not client.get('mapped', True) or client.get('hidden') or client.get('pinned'):
        return False
    # F11/HTML fullscreen can leave a client-only flag on an ordinary-sized
    # floating window. Only the rectangle actually covering the work area counts.
    if not monitor or not client.get('at') or not client.get('size'):
        return False
    width, height = monitor['width'], monitor['height']
    if monitor.get('transform', 0) % 2:
        width, height = height, width
    scale = monitor.get('scale', 1) or 1
    left, top, right, bottom = monitor.get('reserved') or [0, 0, 0, 0]
    x, y = monitor['x'] + left, monitor['y'] + top
    width, height = width / scale - left - right, height / scale - top - bottom
    cx, cy = client['at']; cw, ch = client['size']
    return (width > 0 and height > 0 and cx <= x + 8 and cy <= y + 8
            and cx + cw >= x + width - 8 and cy + ch >= y + height - 8)


def dock_rounded(client, monitor, settings):
    if not expanded(client, monitor):
        return False
    if settings.get('hideMode') != 'never' or not settings.get('dockEnabled', True):
        return False
    if settings.get('monitor') and settings['monitor'] != monitor.get('name'):
        return False
    # The exclusive zone is authoritative: it also handles side Docks, display
    # selection and a disabled/unmapped Dock without guessing its pixel height.
    left, top, right, bottom = monitor.get('reserved') or [0, 0, 0, 0]
    if max(left, right, bottom) <= 0:
        return False
    width, height = monitor['width'], monitor['height']
    if monitor.get('transform', 0) % 2:
        width, height = height, width
    scale = monitor.get('scale', 1) or 1
    x, y = monitor['x'] + left, monitor['y'] + top
    end_x = monitor['x'] + width / scale - right
    end_y = monitor['y'] + height / scale - bottom
    cx, cy = client['at']; cw, ch = client['size']
    # A real desktop-covering rectangle still needs square corners, even when
    # the Dock preference is Never. Only windows inside the work area round.
    return cx >= x - 8 and cy >= y - 8 and cx + cw <= end_x + 8 and cy + ch <= end_y + 8


def sync(backend, clients, monitors, settings=None):
    by_id = {monitor['id']: monitor for monitor in monitors}
    result = []
    for client in clients:
        monitor = by_id.get(client.get('monitor'))
        rounded = dock_rounded(client, monitor, settings or {})
        square = expanded(client, monitor) and not rounded
        for tag, enabled in ((SQUARE_TAG, square), (DOCK_ROUNDED_TAG, rounded)):
            if enabled != (tag in client.get('tags', [])):
                try:
                    backend.tag(client['address'], ('+' if enabled else '-') + tag)
                except RuntimeError:
                    # Windows may close between the snapshot and dispatcher.
                    pass
        if square:
            result.append(dict(pid=client.get('pid'), title=client.get('title', ''), address=client['address']))
    return result
