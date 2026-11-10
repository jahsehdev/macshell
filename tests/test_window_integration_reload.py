import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMMIT = 'a' * 40
FAKE_HYPRCTL = '''#!/usr/bin/env python3
import json, os, subprocess, sys
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
elif args[0] == 'dispatch':
    # Bare legacy dispatcher names are not Lua expressions in Hyprland 0.57.
    print('error: legacy dispatcher is not available')
elif args[0] == 'eval':
    if os.environ.get('MACSHELL_TEST_FAIL') == 'normalize':
        print('error: normalization callback unavailable')
    else:
        # Execute the exact payload with real Lua. A permissive fake returning
        # "ok" for any dispatch cannot catch the user-reported syntax failure.
        marker = str(Path(os.environ['MACSHELL_TEST_LOG']).with_suffix('.normalized'))
        prelude = 'hl = {plugin = {macshell_window_policy = {normalize = function() local f = assert(io.open(' + json.dumps(marker) + ', "w")); f:write("normalized"); f:close() end}}}\\n'
        result = subprocess.run(['lua', '-'], input=prelude + args[1], text=True, capture_output=True)
        print('ok' if result.returncode == 0 else 'error: ' + result.stderr.strip())
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
        for name in ['click-focus', 'native-minimize', 'fullscreen-lock', 'window-policy']:
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
        self.assertEqual([c[1] for c in commands if c[0] == 'plugin'], ['load', 'load', 'load', 'load'])

    def test_reloads_both_loaded_integrations(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-click-focus\nmacshell-native-minimize\nmacshell-fullscreen-lock\nmacshell-window-policy'
        result, commands = self.run_reload()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c[1] for c in commands if c[0] == 'plugin'],
                         ['unload', 'load', 'unload', 'load', 'unload', 'load', 'unload', 'load'])

    def test_ensure_keeps_current_integrations_attached(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-click-focus\nmacshell-native-minimize\nmacshell-fullscreen-lock\nmacshell-window-policy'
        self.env['MACSHELL_TEST_VERSIONS'] = json.dumps({'macshell-click-focus': '1.2',
                                                       'macshell-native-minimize': '1.5', 'macshell-fullscreen-lock': '1.6', 'macshell-window-policy': '1.3'})
        result, commands = self.run_reload('--ensure')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(commands, [['version'], ['-j', 'plugin', 'list']])

    def test_ensure_replaces_only_outdated_integration(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-click-focus\nmacshell-native-minimize\nmacshell-fullscreen-lock\nmacshell-window-policy'
        self.env['MACSHELL_TEST_VERSIONS'] = json.dumps({'macshell-click-focus': '1.2', 'macshell-fullscreen-lock': '1.6', 'macshell-window-policy': '1.3'})
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

    def test_focus_only_preserves_other_integrations_even_when_their_builds_differ(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-click-focus\nmacshell-native-minimize\nmacshell-fullscreen-lock'
        (self.base / 'data/macshell/fullscreen-lock/fullscreen-lock.so.commit').write_text('b' * 40)
        result, commands = self.run_reload('--focus-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        operations = [command for command in commands if command[0] == 'plugin']
        self.assertEqual([command[1] for command in operations], ['unload', 'load'])
        self.assertTrue(all(command[-1].endswith('click-focus.so') for command in operations))

    def test_focus_only_does_not_load_a_mismatched_focus_build(self):
        (self.base / 'data/macshell/click-focus/click-focus.so.commit').write_text('b' * 40)
        result, commands = self.run_reload('--focus-only')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, [['version']])

    def test_focus_only_rejects_window_normalization(self):
        result = subprocess.run([str(ROOT / 'bin/macshell-window-integration-reload'), '--focus-only', '--normalize'],
                                env=self.env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_fullscreen_only_preserves_other_integrations(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-click-focus\nmacshell-fullscreen-lock\nmacshell-spotify-drag'
        result, commands = self.run_reload('--fullscreen-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        operations=[c for c in commands if c[0]=='plugin']
        self.assertEqual([c[1] for c in operations],['unload','load'])
        self.assertTrue(all(c[-1].endswith('fullscreen-lock.so') for c in operations))

    def test_policy_only_preserves_other_integrations(self):
        result, commands = self.run_reload('--policy-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(commands), 3)
        self.assertTrue(commands[-1][-1].endswith('window-policy.so'))

    def test_ensure_upgrades_policy_that_skipped_all_app_windows(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-window-policy'
        self.env['MACSHELL_TEST_VERSIONS'] = json.dumps({'macshell-window-policy': '1.1'})
        result, commands = self.run_reload('--policy-only', '--ensure')
        self.assertEqual(result.returncode, 0, result.stderr)
        operations = [command for command in commands if command[0] == 'plugin']
        self.assertEqual([command[1] for command in operations], ['unload', 'load'])
        self.assertTrue(all(command[-1].endswith('window-policy.so') for command in operations))

    def test_ensure_upgrades_policy_with_duplicate_settings_header(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-window-policy'
        self.env['MACSHELL_TEST_VERSIONS'] = json.dumps({'macshell-window-policy': '1.2'})
        result, commands = self.run_reload('--policy-only', '--ensure')
        self.assertEqual(result.returncode, 0, result.stderr)
        operations = [command for command in commands if command[0] == 'plugin']
        self.assertEqual([command[1] for command in operations], ['unload', 'load'])
        self.assertTrue(all(command[-1].endswith('window-policy.so') for command in operations))

    def test_normalize_runs_only_after_policy_is_loaded(self):
        result, commands = self.run_reload('--policy-only', '--normalize')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(commands[-1], ['eval', 'hl.plugin.macshell_window_policy.normalize()'])
        self.assertEqual(commands[-2][:2], ['plugin', 'load'])
        self.assertEqual(self.log.with_suffix('.normalized').read_text(), 'normalized')

    def test_normalize_failure_reports_that_plugin_loading_succeeded(self):
        self.env['MACSHELL_TEST_FAIL'] = 'normalize'
        result, commands = self.run_reload('--policy-only', '--normalize')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Integrasi sudah dimuat, tetapi normalisasi gagal:', result.stderr)
        self.assertIn('normalization callback unavailable', result.stderr)
        self.assertEqual(commands[-2][:2], ['plugin', 'load'])

    def test_policy_mismatch_never_resizes_existing_windows(self):
        (self.base / 'data/macshell/window-policy/window-policy.so.commit').write_text('b' * 40)
        result, commands = self.run_reload('--policy-only', '--normalize')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, [['version']])

    def test_ensure_upgrades_the_old_never_hide_resize_exception(self):
        self.env['MACSHELL_TEST_LOADED'] = 'macshell-click-focus\nmacshell-native-minimize\nmacshell-fullscreen-lock\nmacshell-window-policy'
        self.env['MACSHELL_TEST_VERSIONS'] = json.dumps({'macshell-click-focus':'1.2','macshell-native-minimize':'1.5',
                                                       'macshell-fullscreen-lock':'1.3','macshell-window-policy':'1.3'})
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
