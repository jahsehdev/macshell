import copy
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

BIN = Path(__file__).resolve().parents[1] / 'bin'
sys.path.insert(0, str(BIN))
from desktop_controller import Controller, STAGE, DESKTOP, address, lua
from titlebar_action import perform, bounds


def client(a, app='Editor', ws='1', mon=0, pid=None, focus=4, floating=True):
    return dict(address='0x' + a, pid=pid or int(a, 16), **{'class': app}, title=app + a,
                at=[100 + mon * 1920, 100], size=[900, 600], floating=floating,
                workspace=dict(name=ws, id=int(ws) if ws.isdigit() else -1),
                monitor=mon, focusHistoryID=focus, mapped=True, hidden=False)


class Fake:
    def __init__(self, clients):
        self.clients = clients
        self.monitors = [dict(id=i, name='MON-' + str(i), x=i * 1920, y=0, width=1920,
            height=1080, scale=1, reserved=[0,30,0,70], activeWorkspace=dict(id=i+1, name=str(i+1))) for i in range(2)]
        self.calls = []
    def snapshot(self):
        return copy.deepcopy(self.clients), copy.deepcopy(self.monitors)
    def move(self, a, workspace):
        self.calls.append(('move', a, workspace))
        c = next(c for c in self.clients if c['address'] == '0x' + a)
        c['workspace'] = dict(name=workspace, id=int(workspace) if str(workspace).isdigit() else -1)
        if str(workspace).startswith('special:'):
            c['focusHistoryID'] = 10
    def focus(self, a):
        self.calls.append(('focus', a))
        for c in self.clients:
            c['focusHistoryID'] = 0 if c['address'] == '0x' + a else 10
    def geometry(self, a, record):
        self.calls.append(('geometry', a, copy.deepcopy(record)))
    def capture(self, a, c):
        return '/cache/' + a + '.png'
    def dispatch(self, expression):
        self.calls.append(('dispatch', expression))
    def run(self, args):
        self.calls.append(('run', args))
        return ''


class StageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'state.json'
        self.backend = Fake([client('aa', focus=0), client('bb', 'Browser')])
        self.c = Controller(self.backend, self.path)
        self.c.preferences = dict(stageManager=True, stageWindows='all', wallpaperClick='stage')
    def tearDown(self):
        self.temp.cleanup()
    def workspace(self, a):
        return next(c['workspace']['name'] for c in self.backend.clients if c['address'] == '0x' + a)
    def test_stage_switch_and_disable_restore(self):
        state = self.c.tick()
        self.assertEqual(len(state['stages']), 2)
        self.assertEqual(self.workspace('bb'), STAGE)
        self.c.command(dict(action='activate', addr='bb')); self.c.tick()
        self.assertEqual(self.workspace('aa'), STAGE)
        self.assertEqual(self.workspace('bb'), '1')
        self.c.preferences['stageManager'] = False; self.c.tick()
        self.assertEqual(self.workspace('aa'), '1')
        restored = [x for x in self.backend.calls if x[:2] == ('geometry', 'aa')][-1][2]
        self.assertEqual(restored['at'], [100,100])
    def test_tiled_state_preserved(self):
        self.backend.clients[1]['floating'] = False
        self.c.tick(); self.c.preferences['stageManager'] = False; self.c.tick()
        restored = [x for x in self.backend.calls if x[:2] == ('geometry','bb')][-1][2]
        self.assertFalse(restored['floating'])
    def test_minimized_and_other_special_workspaces_untouched(self):
        self.backend.clients += [client('cc','Music','special:minimized'), client('dd','Term','special:magic')]
        self.c.tick(); self.c.shutdown()
        self.assertFalse(any(x[0]=='move' and x[1] in ('cc','dd') for x in self.backend.calls))
    def test_workspace_and_monitor_isolation(self):
        self.backend.clients += [client('cc', 'Chat', '5'), client('dd', 'Video', '2', 1)]
        self.c.tick()
        self.assertEqual(self.workspace('cc'), '5'); self.assertEqual(self.workspace('dd'), '2')
        self.c.command(dict(action='desktop', monitor=0)); self.c.tick()
        self.assertEqual(self.workspace('aa'), DESKTOP); self.assertEqual(self.workspace('dd'), '2')
    def test_join_and_ungroup(self):
        self.c.tick(); self.c.command(dict(action='join', addr='bb')); self.c.tick()
        self.assertEqual(self.workspace('aa'), '1'); self.assertEqual(self.workspace('bb'), '1')
        self.assertEqual(self.c.records['aa']['group'], self.c.records['bb']['group'])
        self.c.command(dict(action='ungroup', addr='bb')); self.c.tick()
        self.assertEqual(self.workspace('aa'), STAGE)
    def test_one_window_at_a_time_per_app(self):
        self.backend.clients.append(client('cc'))
        self.c.preferences['stageWindows'] = 'one'; self.c.tick()
        self.assertEqual(self.workspace('aa'), '1'); self.assertEqual(self.workspace('cc'), STAGE)
        self.c.command(dict(action='activate', addr='cc')); self.c.tick()
        self.assertEqual(self.workspace('cc'), '1'); self.assertEqual(self.workspace('aa'), STAGE)
        self.c.command(dict(action='join',addr='bb')); self.c.tick()
        self.assertEqual(self.workspace('bb'), '1'); self.assertEqual(self.workspace('cc'), '1')
    def test_wallpaper_click_policy_and_toggle(self):
        self.c.preferences['stageManager'] = False
        self.c.command(dict(action='desktop',monitor=0)); self.c.tick()
        self.assertEqual(self.workspace('aa'),'1')
        self.c.preferences['wallpaperClick'] = 'always'
        self.c.command(dict(action='desktop',monitor=0)); self.c.tick()
        self.assertEqual(self.workspace('aa'),DESKTOP)
        self.c.command(dict(action='desktop',monitor=0)); self.c.tick()
        self.assertEqual(self.workspace('aa'),'1')
    def test_reload_recovery_and_pid_reuse(self):
        self.c.tick()
        recovered = Controller(self.backend,self.path)
        recovered.preferences = dict(stageManager=False)
        recovered.tick(); self.assertEqual(self.workspace('bb'),'1')
        self.c.tick()
        self.backend.clients[1]['pid'] = 9999
        recovered = Controller(self.backend,self.path)
        recovered.shutdown()
        self.assertEqual(self.workspace('bb'),STAGE)  # never apply old geometry to a new process
    def test_shutdown_restores_owned_workspaces(self):
        self.c.tick(); self.c.command(dict(action='desktop',monitor=0)); self.c.tick()
        self.c.shutdown()
        self.assertTrue(all(c['workspace']['name']=='1' for c in self.backend.clients))
    def test_closed_active_group_recovers(self):
        self.c.tick(); self.backend.clients = [self.backend.clients[1]]
        self.c.tick(); self.c.tick()
        self.assertEqual(self.workspace('bb'),'1')
    def test_new_app_leaves_show_desktop(self):
        self.c.tick(); self.c.command(dict(action='desktop',monitor=0)); self.c.tick()
        self.backend.clients.append(client('cc','New App',focus=0))
        self.c.tick()
        self.assertEqual(self.workspace('cc'),'1')
        self.assertEqual(self.c.revealed,[])
    def test_external_switcher_can_activate_a_parked_stage(self):
        self.c.tick(); self.backend.focus('bb'); self.c.tick()
        self.assertEqual(self.workspace('bb'),'1'); self.assertEqual(self.workspace('aa'),STAGE)
    def test_pinned_windows_stay_visible(self):
        self.backend.clients[1]['pinned']=True
        self.c.tick(); self.assertEqual(self.workspace('bb'),'1')
    def test_lua_quoting_preserves_unicode_and_literal_backslashes(self):
        self.assertEqual(lua('Kerja \"ü'), '"Kerja \\\"ü"')
        self.assertEqual(lua('\n'), '"\\010"')
    def test_address_validation(self):
        self.assertEqual(address('0xabcd'),'abcd')
        self.assertEqual(address('abc"; os.execute("x")'), '')


class TitlebarTests(unittest.TestCase):
    def test_fill_toggle_and_scaled_work_area(self):
        with tempfile.TemporaryDirectory() as temp:
            backend=Fake([client('aa', floating=False)])
            monitor=dict(id=0,width=3840,height=2160,x=100,y=50,scale=2,reserved=[10,30,20,70])
            self.assertEqual(bounds(monitor), [110,80,1890,980])
            path=Path(temp)/'titlebar.json'
            perform(backend,'fill',backend.clients[0],[monitor],path)
            geometry=backend.calls[-1][2]
            self.assertEqual(geometry['size'],[1890,980])
            perform(backend,'fill',backend.clients[0],[monitor],path)
            self.assertFalse(backend.calls[-1][2]['floating'])
    def test_zoom_minimize_and_none(self):
        with tempfile.TemporaryDirectory() as temp:
            backend=Fake([client('aa')]); path=Path(temp)/'state.json'
            perform(backend,'none',backend.clients[0],backend.monitors,path)
            self.assertEqual(backend.calls,[])
            perform(backend,'zoom',backend.clients[0],backend.monitors,path)
            self.assertIn('maximized',backend.calls[-1][1])
            perform(backend,'minimize',backend.clients[0],backend.monitors,path)
            self.assertEqual(backend.calls[-1][1][-2:],['addr','aa'])

if __name__ == '__main__':
    unittest.main()
