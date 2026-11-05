import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMMIT = 'a' * 40
FAKE_HYPRCTL = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['MACSHELL_TEST_LOG'], 'a') as out:
    out.write(json.dumps(args) + '\\n')
if os.environ.get('MACSHELL_TEST_FAIL') == 'ipc':
    print('Cannot connect to compositor', file=sys.stderr)
    sys.exit(1)
if args == ['version']:
    print('Hyprland 0.57.0 at commit ' + 'a' * 40)
elif args == ['-j', 'plugin', 'list']:
    versions = json.loads(os.environ.get('MACSHELL_TEST_VERSIONS', '{}'))
    print(json.dumps([{'name': name, 'version': versions.get(name, 'old')}
                      for name in os.environ.get('MACSHELL_TEST_LOADED', '').splitlines()]))
elif args[:2] == ['plugin', 'unload'] and os.environ.get('MACSHELL_TEST_FAIL') == 'unload':
    print('unload failed')
else:
    print('ok')
'''


class ReloadTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.base = Path(self.directory.name)
        self.log = self.base / 'commands.jsonl'
        fake = self.base / 'hyprctl'
        fake.write_text(FAKE_HYPRCTL)
        fake.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.base) + os.pathsep + os.environ['PATH'],
                        XDG_DATA_HOME=str(self.base / 'data'), MACSHELL_TEST_LOG=str(self.log))
        for name in ['click-focus', 'native-minimize', 'fullscreen-lock']:
            folder = self.base / 'data/macshell' / name
            folder.mkdir(parents=True)
            (folder / (name + '.so')).touch()
            (folder / (name + '.so.commit')).write_text(COMMIT)

    def run_reload(self, *args):
        result = subprocess.run([str(ROOT / 'bin/macshell-window-integration-reload'), *args],
                                env=self.env, text=True, capture_output=True)
        commands = [json.loads(line) for line in self.log.read_text().splitlines()]
        return result, commands

    def test_loads_integrations_that_are_not_loaded(self):
        result, commands = self.run_reload()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(commands[1], ['-j', 'plugin', 'list'])
        self.assertEqual([c[1] for c in commands if c[0] == 'plugin'], ['load', 'load', 'load'])

    def test_reloads_both_loaded_integrations(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-click-focus\nmacshell-native-minimize\nmacshell-fullscreen-lock'
        result, commands = self.run_reload()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c[1] for c in commands if c[0] == 'plugin'],
                         ['unload', 'load', 'unload', 'load', 'unload', 'load'])

    def test_ensure_keeps_current_integrations_attached(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-click-focus\nmacshell-native-minimize\nmacshell-fullscreen-lock'
        self.env['MACSHELL_TEST_VERSIONS'] = json.dumps({'macshell-click-focus': '1.2',
                                                       'macshell-native-minimize': '1.5', 'macshell-fullscreen-lock': '1.6'})
        result, commands = self.run_reload('--ensure')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(commands, [['version'], ['-j', 'plugin', 'list']])

    def test_ensure_replaces_only_outdated_integration(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-click-focus\nmacshell-native-minimize\nmacshell-fullscreen-lock'
        self.env['MACSHELL_TEST_VERSIONS'] = json.dumps({'macshell-click-focus': '1.2', 'macshell-fullscreen-lock': '1.6'})
        result, commands = self.run_reload('--ensure')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c[1] for c in commands if c[0] == 'plugin'], ['unload', 'load'])
        self.assertTrue(all('native-minimize' in c[-1] for c in commands if c[0] == 'plugin'))

    def test_version_mismatch_changes_neither_plugin(self):
        stamp = self.base / 'data/macshell/native-minimize/native-minimize.so.commit'
        stamp.write_text('b' * 40)
        result, commands = self.run_reload()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, [['version']])

    def test_unreachable_compositor_changes_neither_plugin(self):
        self.env['MACSHELL_TEST_FAIL'] = 'ipc'
        result, commands = self.run_reload()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, [['version']])

    def test_minimize_only_preserves_focus_plugin(self):
        result, commands = self.run_reload('--minimize-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(commands), 3)
        self.assertTrue(commands[-1][-1].endswith('native-minimize.so'))

    def test_fullscreen_only_preserves_other_integrations(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-click-focus\nmacshell-fullscreen-lock\nmacshell-spotify-drag'
        result, commands = self.run_reload('--fullscreen-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        operations=[c for c in commands if c[0]=='plugin']
        self.assertEqual([c[1] for c in operations],['unload','load'])
        self.assertTrue(all(c[-1].endswith('fullscreen-lock.so') for c in operations))

    def test_ensure_upgrades_the_old_never_hide_resize_exception(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-click-focus\nmacshell-native-minimize\nmacshell-fullscreen-lock'
        self.env['MACSHELL_TEST_VERSIONS'] = json.dumps({'macshell-click-focus':'1.2','macshell-native-minimize':'1.5',
                                                       'macshell-fullscreen-lock':'1.3'})
        result, commands = self.run_reload('--ensure')
        self.assertEqual(result.returncode,0,result.stderr)
        operations=[c for c in commands if c[0]=='plugin']
        self.assertEqual([c[1] for c in operations],['unload','load'])
        self.assertTrue(all(c[-1].endswith('fullscreen-lock.so') for c in operations))

    def test_ensure_upgrades_resize_lock_without_cursor_fix(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-fullscreen-lock'
        self.env['MACSHELL_TEST_VERSIONS'] = json.dumps({'macshell-fullscreen-lock':'1.4'})
        result, commands = self.run_reload('--fullscreen-only','--ensure')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual([c[1] for c in commands if c[0]=='plugin'],['unload','load'])

    def test_ensure_upgrades_cursor_fix_without_native_zoom_restore(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-fullscreen-lock'
        self.env['MACSHELL_TEST_VERSIONS'] = json.dumps({'macshell-fullscreen-lock':'1.5'})
        result, commands = self.run_reload('--fullscreen-only','--ensure')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual([c[1] for c in commands if c[0]=='plugin'],['unload','load'])

    def test_stops_if_unload_fails(self):
        self.env.update(MACSHELL_TEST_LOADED='macshell-click-focus', MACSHELL_TEST_FAIL='unload')
        result, commands = self.run_reload()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands[-1][:2], ['plugin', 'unload'])


if __name__ == '__main__':
    unittest.main()
