import importlib.util
from pathlib import Path
from unittest import TestCase, main
from unittest.mock import patch
from types import SimpleNamespace
import json
import tempfile
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
A = load('actions', ROOT / 'window_action.py')
L = load('launcher', ROOT / 'launch.py')

class WindowActions(TestCase):
    window = {'class': 'Spotify', 'pid': 123, 'address': '0xab12', 'title': 'Spotify'}
    def test_other_application_cannot_be_closed(self):
        with patch.object(A, 'hypr', return_value=json.dumps({'class':'firefox','pid':123})), patch.object(A,'dispatch') as dispatch:
            self.assertFalse(A.perform('close','spotify',123))
            dispatch.assert_not_called()
    def test_other_process_cannot_be_closed(self):
        with patch.object(A,'hypr',return_value=json.dumps(self.window)),patch.object(A,'dispatch') as dispatch:
            self.assertFalse(A.perform('close','spotify',999))
            dispatch.assert_not_called()
    def test_ready_tags_only_matching_window(self):
        windows=[self.window,dict(self.window,pid=999),{'class':'firefox','pid':123,'address':'0x99'}]
        with patch.object(A,'hypr',return_value=json.dumps(windows)),patch.object(A,'dispatch') as dispatch:
            self.assertTrue(A.perform('ready','spotify',123))
            dispatch.assert_called_once_with('ready','0xab12')
    def test_maximize_uses_explicit_address(self):
        with patch.object(A,'hypr',return_value=json.dumps(self.window)),patch.object(A,'dispatch') as dispatch:
            self.assertTrue(A.perform('maximize','spotify',123))
            dispatch.assert_called_once_with('maximize','0xab12')
    def test_invalid_selector_is_rejected(self):
        with self.assertRaises(ValueError): A.dispatch('close','0x1");os.execute("false")')
    def test_minimize_addresses_spotify_and_confirms_it_was_hidden(self):
        parked=dict(self.window,workspace={'name':'special:minimized'})
        with patch.object(A,'hypr',side_effect=[json.dumps(self.window),json.dumps([parked])]),patch.object(A.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout='')) as run:
            self.assertTrue(A.perform('minimize','spotify',123))
            self.assertEqual(run.call_args.args[0],['qs','-c','MacShell','ipc','call','minimize','addr','0xab12'])
    def test_minimize_noop_is_not_reported_as_success(self):
        with patch.object(A,'hypr',return_value=json.dumps([self.window])),patch.object(A.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout='')),patch.object(A.time,'sleep'):
            self.assertFalse(A.minimize_spotify(self.window))
    def test_other_apps_retain_the_existing_minimize_helper(self):
        window=dict(self.window,**{'class':'kitty'})
        with patch.object(A,'hypr',return_value=json.dumps(window)),patch.object(A.subprocess,'run',return_value=SimpleNamespace(returncode=0)) as run:
            self.assertTrue(A.perform('minimize','kitty',123))
            self.assertEqual(run.call_args.args[0][0],'/bin/sh')
            self.assertTrue(run.call_args.args[0][1].endswith('/hypr/minimize.sh'))
    def test_move_checks_active_process_and_xwayland(self):
        for window,pid in [(dict(self.window,xwayland=True),999), (self.window,123),
                           (dict(self.window,**{'class':'firefox','xwayland':True}),123)]:
            with patch.object(A,'hypr',return_value=json.dumps(window)),patch.object(A,'begin_spotify_move') as move:
                self.assertFalse(A.perform('move','spotify',pid))
                move.assert_not_called()
    def test_native_move_receives_verified_pid(self):
        with patch.object(A,'hypr',return_value=json.dumps(dict(self.window,xwayland=True))),patch.object(A,'begin_spotify_move',return_value=True) as move:
            self.assertTrue(A.perform('move','spotify',123))
            move.assert_called_once_with(123)
    def test_dispatch_error_is_not_reported_as_success(self):
        with patch.object(A.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout='error: no window')):
            with self.assertRaises(RuntimeError): A.dispatch('close','0xab12')
    def test_move_asks_the_compositor_and_rejects_a_noop(self):
        with patch.object(A,'hypr',return_value='ok') as hypr:
            self.assertTrue(A.begin_spotify_move(123))
            self.assertEqual(hypr.call_args.args[0],'eval')
            self.assertIn('hl.plugin.macshell_spotify.move(123)',hypr.call_args.args[1])
        with patch.object(A,'hypr',return_value='Spotify drag was not started'):
            self.assertFalse(A.begin_spotify_move(123))

class BridgeAuthorization(TestCase):
    def setUp(self):
        diagnostic=patch.object(L,'spotify_diagnostic')
        diagnostic.start();self.addCleanup(diagnostic.stop)
    def handler(self,path='/secret/close',origin='https://xpui.app.spotify.com',host='127.0.0.1:43123'):
        h=object.__new__(L.WindowBridge)
        h.server=SimpleNamespace(token='secret',server_port=43123,spotify_pid=123)
        h.path=path
        h.headers={'Origin':origin,'Host':host,'Content-Length':'0'}
        self.status=None
        h.reply=lambda status,body=b'':setattr(self,'status',status)
        return h
    def test_authorized_page_is_accepted(self): self.assertTrue(self.handler().authorized())
    def test_unrelated_website_is_rejected(self): self.assertFalse(self.handler(origin='https://example.com').authorized())
    def test_wrong_token_is_rejected(self): self.assertFalse(self.handler(path='/wrong/close').authorized())
    def test_arbitrary_command_is_rejected(self): self.assertFalse(self.handler(path='/secret/exec').authorized())
    def test_dns_rebinding_is_rejected(self): self.assertFalse(self.handler(host='example.com:43123').authorized())
    def test_missing_origin_is_rejected(self): self.assertFalse(self.handler(origin=None).authorized())
    def test_post_rejects_payload_before_action(self):
        h=self.handler();h.headers['Content-Length']='100'
        with patch.object(L.actions,'perform') as perform:
            h.do_POST();self.assertEqual(self.status,403);perform.assert_not_called()
    def test_get_has_no_action_handler(self): self.assertFalse(hasattr(L.WindowBridge,'do_GET'))

class SpotifyOverlay(TestCase):
    def test_artwork_change_invalidates_cached_overlay(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root, upstream = home / 'launcher', home / 'upstream'
            for path in [root / 'launch.py', root / 'web/spotify.js',
                         root / 'web/antigravity-main.js', upstream / 'antigravity-ide',
                         upstream / 'resources/app/out/main.js',
                         upstream / 'resources/app/out/vs/workbench/workbench.desktop.main.css']:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'unchanged application')
            artwork = home / '.config/macshell/window-controls/dark/titlebutton-close-dark@2.png'
            artwork.parent.mkdir(parents=True)
            artwork.write_bytes(b'old artwork')
            with patch.dict(L.SOURCES, antigravity=upstream), patch.object(L, 'ROOT', root), \
                    patch.object(L.Path, 'home', return_value=home):
                before = L.fingerprint('antigravity')
                artwork.write_bytes(b'new glass traffic-light artwork')
                self.assertNotEqual(before, L.fingerprint('antigravity'))

    def test_drag_plugin_is_loaded_only_for_matching_compositor(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'spotify-drag.so.commit').write_text('a'*40)
            with patch.object(L,'ROOT',root),patch.object(L,'spotify_diagnostic'),patch.object(L.actions,'hypr',side_effect=['compositor '+'a'*40,'[]','ok']) as hypr:
                self.assertTrue(L.ensure_spotify_drag())
                self.assertEqual(hypr.call_args.args,('plugin','load',str(root/'spotify-drag.so')))
            with patch.object(L,'ROOT',root),patch.object(L,'spotify_diagnostic'),patch.object(L.actions,'hypr',return_value='compositor '+'b'*40) as hypr:
                self.assertFalse(L.ensure_spotify_drag())
                self.assertEqual(hypr.call_count,1,'mismatched binary must never be loaded')
    def test_loaded_drag_plugin_is_reused(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'spotify-drag.so.commit').write_text('a'*40)
            plugins=json.dumps([{'name':'macshell-spotify-drag','version':'1.0'}])
            with patch.object(L,'ROOT',root),patch.object(L.actions,'hypr',side_effect=['compositor '+'a'*40,plugins]) as hypr:
                self.assertTrue(L.ensure_spotify_drag())
                self.assertEqual(hypr.call_count,2)
    def test_relaunch_uses_different_asset_url_for_new_connection(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);upstream=root/'upstream';local=root/'local'
            (upstream/'Apps').mkdir(parents=True);(local/'Apps').mkdir(parents=True)
            with ZipFile(upstream/'Apps/xpui.spa','w') as archive:
                archive.writestr('index.html','<html><head></head><body></body></html>')
                archive.writestr('original.js','unchanged')
            pages=[]
            with patch.dict(L.SOURCES,spotify=upstream),patch.object(L,'controls_css',return_value='/*test*/'):
                for port in [43210,43211]:
                    L.patch_spotify(local,{'endpoint':f'http://127.0.0.1:{port}','token':'test'})
                    with ZipFile(local/'Apps/xpui.spa') as archive:
                        pages.append(archive.read('index.html'))
                        self.assertIn(f':{port}'.encode(),archive.read('macshell-controls.js'))
                        self.assertEqual(archive.read('original.js'),b'unchanged')
            self.assertNotEqual(pages[0],pages[1])
            self.assertIn(b'macshell-controls.js?v=',pages[0])
            self.assertIn(b'macshell-controls.css?v=',pages[0])
    def test_bridge_reuses_private_connection_across_launches(self):
        with tempfile.TemporaryDirectory() as folder:
            binds=[]
            def server(address,handler):
                binds.append(address)
                return SimpleNamespace(server_port=address[1] or 43210)
            with patch.object(L,'STATE',Path(folder)),patch.object(L,'ThreadingHTTPServer',side_effect=server):
                first=L.spotify_bridge();second=L.spotify_bridge()
            self.assertEqual(binds,[('127.0.0.1',0),('127.0.0.1',43210)])
            self.assertEqual(first.token,second.token)
            self.assertEqual((Path(folder)/'.spotify-bridge.json').stat().st_mode & 0o777,0o600)

if __name__ == '__main__': main()
