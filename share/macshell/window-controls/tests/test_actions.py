import importlib.util
from pathlib import Path
from unittest import TestCase, main
from unittest.mock import patch
from types import SimpleNamespace
import json

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
    def test_minimize_uses_existing_dock_helper(self):
        with patch.object(A,'hypr',return_value=json.dumps(self.window)),patch.object(A.subprocess,'run',return_value=SimpleNamespace(returncode=0)) as run:
            self.assertTrue(A.perform('minimize','spotify',123))
            args=run.call_args.args[0]
            self.assertEqual(args[0],'/bin/sh')
            self.assertTrue(args[1].endswith('/hypr/minimize.sh'))
            self.assertEqual(args[2],'minimize')

class BridgeAuthorization(TestCase):
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

if __name__ == '__main__': main()
