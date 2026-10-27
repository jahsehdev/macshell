#!/usr/bin/env python3
"""Workspace-backed Stage Manager and Show Desktop. JSON lines over stdin/stdout.

Only our own special workspaces are restored. Journal before parking a window,
validate PID on recovery, and preserve geometry and tiled/floating state.
"""
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time
import tempfile
import window_corners

STAGE = 'special:macshell-stage'
DESKTOP = 'special:macshell-desktop'
OWN = (STAGE, DESKTOP)
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'macshell'
CACHE = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'macshell/stages'


def address(value):
    value = str(value or '').removeprefix('0x')
    return value if re.fullmatch(r'[0-9a-fA-F]+', value) else ''


def lua(value):
    parts = ['"']
    for char in str(value):
        if char in ('"', '\\'):
            parts.append('\\' + char)
        elif ord(char) < 32 or ord(char) == 127:
            parts.append('\\%03d' % ord(char))
        else:
            parts.append(char)
    return ''.join(parts) + '"'


def atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                     prefix=path.name + '.', delete=False) as stream:
        temp = Path(stream.name)
        json.dump(value, stream)
    try:
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)


class Backend:
    def run(self, args):
        try:
            p = subprocess.run(args, capture_output=True, text=True, timeout=3)
            if p.returncode:
                raise RuntimeError(p.stderr.strip() or p.stdout.strip() or 'command failed')
            return p.stdout
        except (OSError, subprocess.TimeoutExpired) as e:
            raise RuntimeError(str(e)) from e

    def snapshot(self):
        return (json.loads(self.run(['hyprctl', '-j', 'clients'])),
                json.loads(self.run(['hyprctl', '-j', 'monitors'])))

    def dispatch(self, expression):
        self.run(['hyprctl', 'dispatch', expression])

    def move(self, a, workspace):
        self.dispatch('hl.dsp.window.move({window=' + lua('address:0x' + a)
                      + ',workspace=' + lua(workspace) + ',follow=false})')

    def tag(self, a, tag):
        a = address(a)
        if a:
            self.dispatch('hl.dsp.window.tag({window=' + lua('address:0x' + a) + ',tag=' + lua(tag) + '})')

    def focus(self, a):
        self.dispatch('hl.dsp.focus({window=' + lua('address:0x' + a) + '})')

    def geometry(self, a, r):
        sel = 'window=' + lua('address:0x' + a)
        if not r.get('floating', True):
            self.dispatch('hl.dsp.window.float({' + sel + ',action="disable"})')
            return
        self.dispatch('hl.dsp.window.float({' + sel + ',action="enable"})')
        self.dispatch('hl.dsp.window.resize({' + sel + ',x=%d,y=%d,exact=true})' % tuple(r['size']))
        self.dispatch('hl.dsp.window.move({' + sel + ',x=%d,y=%d,exact=true})' % tuple(r['at']))

    def capture(self, a, c):
        CACHE.mkdir(parents=True, exist_ok=True)
        x, y = c['at']; w, h = c['size']
        if w < 8 or h < 8:
            return ''
        path = CACHE / (a + '.png')
        try:
            self.run(['grim', '-g', '%d,%d %dx%d' % (x, y, w, h), '-t', 'png', str(path)])
            return str(path) + '?v=' + str(time.time_ns())
        except RuntimeError:
            return ''


class Controller:
    def __init__(self, backend=None, state_path=None):
        self.backend = backend or Backend()
        self.path = state_path or CONFIG / 'desktop-window-state.json'
        try:
            state = json.loads(self.path.read_text())
        except (OSError, ValueError):
            state = {}
        self.records = state.get('records', {})
        self.active = state.get('active', {})
        self.revealed = state.get('revealed', [])
        self.preferences = {}
        self.clients = []
        self.monitors = []
        self.error = ''
        self.serial = 0
        self.focus_request = ''
        self.last_foreground = ''
        self.last_saved = None

    def save(self):
        value = dict(records=self.records, active=self.active, revealed=self.revealed)
        encoded = json.dumps(value, sort_keys=True)
        if encoded != self.last_saved:
            atomic(self.path, value)
            self.last_saved = encoded

    @staticmethod
    def eligible(c):
        return (address(c.get('address')) and c.get('mapped', True) and c.get('pid', 0) > 0
                and not c.get('pinned') and c.get('class') and c.get('size', [0, 0])[0] > 1
                and c.get('class') not in ('qs-launchpad-backdrop', 'qs-launchpad', 'hyprlock'))

    def scope(self, c, r=None):
        ws = (r or {}).get('workspace') or c.get('workspace', {}).get('name', '1')
        return str(c.get('monitor', 0)) + ':' + str(ws)

    def record(self, c):
        a = address(c['address'])
        old = self.records.get(a, {})
        ws = c.get('workspace', {}).get('name', '1')
        if ws not in OWN and not ws.startswith('special:'):
            old.update(pid=c.get('pid'), workspace=ws, at=c['at'], size=c['size'],
                       floating=c.get('floating', True), monitor=c.get('monitor', 0),
                       app=c.get('class', ''), title=c.get('title', ''))
        old.setdefault('group', self.scope(c, old) + ':' + c.get('class', '').lower())
        self.records[a] = old
        return old

    def park(self, c, r, destination):
        if c.get('workspace', {}).get('name') == destination:
            return
        a = address(c['address'])
        # Capture only visible windows. Never take a screenshot of a parked stage.
        mon = next((m for m in self.monitors if m['id'] == c.get('monitor')), None)
        if (mon and c.get('workspace', {}).get('id') == mon.get('activeWorkspace', {}).get('id')
                and not c.get('hidden') and c.get('focusHistoryID') == 0):
            r['shot'] = self.backend.capture(a, c)
        self.save()
        self.backend.move(a, destination)
        c['workspace'] = {'name': destination, 'id': -1}

    def restore(self, c, r):
        if c.get('workspace', {}).get('name') not in OWN or not r.get('workspace'):
            return
        a = address(c['address'])
        self.backend.move(a, r['workspace'])
        self.backend.geometry(a, r)
        c['workspace'] = {'name': r['workspace'], 'id': int(r['workspace']) if r['workspace'].isdigit() else 0}

    def tick(self):
        self.clients, self.monitors = self.backend.snapshot()
        square_windows = window_corners.sync(self.backend, self.clients, self.monitors,
                                             window_corners.dock_settings())
        live = {address(c.get('address')): c for c in self.clients}
        previous_records = self.records
        self.records = {a: r for a, r in self.records.items()
                        if a in live and r.get('pid') == live[a].get('pid')}
        for a in previous_records.keys() - self.records.keys():
            shot = CACHE / (a + '.png')
            if address(a):
                shot.unlink(missing_ok=True)
        stage = self.preferences.get('stageManager', False)
        externally_focused = next((c for c in self.clients if c.get('focusHistoryID') == 0
            and c.get('workspace', {}).get('name') in OWN
            and address(c.get('address')) != self.last_foreground), None)
        if externally_focused and not self.focus_request:
            a = address(externally_focused['address'])
            if a in self.records:
                self.focus_request = a
                self.revealed = [m for m in self.revealed if m != str(externally_focused.get('monitor', 0))]
        foreground = next((c for c in self.clients if c.get('focusHistoryID') == 0
                           and c.get('workspace', {}).get('name') not in OWN
                           and not c.get('workspace', {}).get('name', '').startswith('special:')), None)
        if foreground and self.eligible(foreground) and not self.focus_request:
            if address(foreground['address']) != self.last_foreground:
                self.revealed = [m for m in self.revealed if m != str(foreground.get('monitor', 0))]
            r = self.record(foreground)
            scope = self.scope(foreground, r)
            self.active[scope] = r['group']
            if address(foreground['address']) != self.last_foreground:
                r['selected'] = time.time_ns()
            self.last_foreground = address(foreground['address'])
        groups = {}
        for c in self.clients:
            if not self.eligible(c):
                continue
            name = c.get('workspace', {}).get('name', '')
            if name.startswith('special:') and name not in OWN:
                continue  # minimized/other special workspaces belong to their owner
            r = self.record(c)
            if not r.get('workspace'):
                continue
            scope = self.scope(c, r)
            group = r['group']
            groups.setdefault(group, []).append((c, r))
            self.active.setdefault(scope, group)
        if self.focus_request in live:
            c = live[self.focus_request]; r = self.records.get(self.focus_request)
            if r:
                self.active[self.scope(c, r)] = r['group']
                r['selected'] = time.time_ns()
        for scope, group in list(self.active.items()):
            if group not in groups:
                replacement = next((g for g, members in groups.items() if self.scope(*members[0]) == scope), None)
                if replacement:
                    self.active[scope] = replacement
                else:
                    del self.active[scope]
        managed = {address(x['address']) for pairs in groups.values() for x, _ in pairs}
        selected = {}
        for group, members in groups.items():
            # One-at-a-time keeps one window PER APP in a multi-app group.
            for c, r in members:
                key = (group, r['app'])
                previous = selected.get(key)
                if previous is None or r.get('selected', 0) > previous[1].get('selected', 0):
                    selected[key] = (c, r)
        monitor_ws = {m['id']: str(m.get('activeWorkspace', {}).get('name', m.get('activeWorkspace', {}).get('id', '1')))
                      for m in self.monitors}
        for c in self.clients:
            a = address(c.get('address')); r = self.records.get(a)
            if not r or a not in managed:
                continue
            scope = self.scope(c, r)
            revealed = str(c.get('monitor', 0)) in self.revealed
            current = str(r['workspace']) == monitor_ws.get(c.get('monitor'))
            hide = stage and (self.active.get(scope) != r['group'] or
                (self.preferences.get('stageWindows') == 'one' and selected.get((r['group'], r['app']), (None,))[0] is not c))
            if revealed and current:
                self.park(c, r, DESKTOP)
            elif hide and current:
                self.park(c, r, STAGE)
            else:
                self.restore(c, r)
        if self.focus_request and self.focus_request in live:
            self.backend.focus(self.focus_request)
            self.last_foreground = self.focus_request
        self.focus_request = ''
        # Remove empty active groups after their last window closes.
        for scope, group in list(self.active.items()):
            if group not in groups:
                replacement = next((g for g, members in groups.items() if self.scope(*members[0]) == scope), None)
                if replacement:
                    self.active[scope] = replacement
                else:
                    del self.active[scope]
        self.save()
        stages = []
        if stage:
            for group, members in groups.items():
                c, r = members[0]
                if str(r['workspace']) != monitor_ws.get(c.get('monitor')):
                    continue
                mon = next((m for m in self.monitors if m['id'] == c.get('monitor')), {})
                stages.append(dict(id=group, monitor=mon.get('name', ''), active=self.active.get(self.scope(c, r)) == group,
                    title=' + '.join(dict.fromkeys(x['app'] for _, x in members)),
                    windows=[dict(addr=address(x['address']), app=y['app'], title=y['title'], shot=y.get('shot', '')) for x, y in members]))
        return dict(stages=stages, revealed=self.revealed, squareWindows=square_windows, error=self.error)

    def command(self, message):
        action = message.get('action')
        if action == 'preferences':
            self.preferences = message.get('settings', {})
        elif action == 'activate':
            a = address(message.get('addr'))
            r = self.records.get(a)
            if r:
                self.revealed = [m for m in self.revealed if m != str(r.get('monitor', 0))]
                self.focus_request = a
        elif action == 'resume':
            self.revealed = []
        elif action == 'desktop':
            if not message.get('force') and self.preferences.get('wallpaperClick', 'stage') == 'stage' and not self.preferences.get('stageManager'):
                return
            mon = str(message.get('monitor', 0))
            if mon in self.revealed:
                self.revealed.remove(mon)
                # Avoid immediately selecting a different group on desktop return.
                member = next((a for a, r in self.records.items() if str(r.get('monitor')) == mon
                               and self.active.get(str(r.get('monitor')) + ':' + str(r.get('workspace'))) == r['group']), '')
                self.focus_request = member
            else:
                self.revealed.append(mon)
        elif action in ('join', 'ungroup'):
            a = address(message.get('addr')); r = self.records.get(a)
            if r:
                scope = str(r.get('monitor')) + ':' + str(r['workspace'])
                target = message.get('group') or self.active.get(scope)
                if action == 'ungroup':
                    target = scope + ':window:' + a
                members = [v for v in self.records.values() if v['group'] == target]
                if action == 'ungroup' or any(str(v['monitor']) + ':' + str(v['workspace']) == scope for v in members):
                    r['group'] = target
                    self.active[scope] = target
                    self.focus_request = a
        self.save()

    def shutdown(self):
        clients, _ = self.backend.snapshot()
        for c in clients:
            a = address(c.get('address')); r = self.records.get(a)
            if r and r.get('pid') == c.get('pid'):
                self.restore(c, r)
        self.revealed = []
        self.save()


def main():
    controller = Controller()
    selector = selectors.DefaultSelector()
    selector.register(sys.stdin, selectors.EVENT_READ)
    running = True
    def stop(*_):
        nonlocal running
        running = False
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    previous = ''
    buffer = b''
    try:
        while running:
            for _, _ in selector.select(0.65):
                chunk = os.read(sys.stdin.fileno(), 65536)
                if not chunk:
                    running = False
                    break
                buffer += chunk
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    try:
                        controller.command(json.loads(line))
                    except (ValueError, KeyError, RuntimeError, OSError) as e:
                        controller.error = str(e)
            if not running:
                break
            try:
                result = controller.tick()
                controller.error = ''
                encoded = json.dumps(result)
                if encoded != previous:
                    print(encoded, flush=True)
                    previous = encoded
            except (ValueError, KeyError, RuntimeError, OSError) as e:
                print(json.dumps(dict(error=str(e))), flush=True)
    finally:
        try:
            controller.shutdown()
        except (ValueError, KeyError, RuntimeError, OSError):
            pass  # the journal is kept for the next shell start

if __name__ == '__main__':
    main()
