import importlib.machinery
import importlib.util
import io
import contextlib
import json
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('cursor_reload', str(ROOT / 'bin/macshell-cursor-reload'))
spec = importlib.util.spec_from_loader(loader.name, loader)
reload = importlib.util.module_from_spec(spec)
loader.exec_module(reload)
COMMIT = 'a' * 40


class CursorReloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = Path(self.temp.name)
        self.directory = self.data / 'macshell/shake-to-find'
        self.directory.mkdir(parents=True)
        (self.directory / 'shake-to-find.so').touch()
        (self.directory / 'shake-to-find.so.commit').write_text(COMMIT)
        self.calls = []
        self.loaded = []
        self.failure = None
        self.rebuild = patch.object(reload, 'rebuild_for_session', side_effect=RuntimeError('Headers do not match')).start()
        self.addCleanup(patch.stopall)

    def hypr(self, *args, expect_ok=False):
        self.calls.append(args)
        if self.failure == args[0]:
            raise RuntimeError('IPC operation failed')
        if args == ('version',): return 'Hyprland 0.57.0 at commit ' + COMMIT
        if args == ('-j', 'plugin', 'list'): return json.dumps(self.loaded)
        return 'ok'

    def run_helper(self, *args):
        with patch.dict(reload.os.environ, XDG_DATA_HOME=str(self.data)), \
                patch.object(reload.sys, 'argv', ['cursor-reload', *args]), \
                patch.object(reload, 'hypr', side_effect=self.hypr), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return reload.main()

    def test_loads_only_the_cursor_plugin(self):
        self.assertEqual(self.run_helper(), 0)
        self.assertEqual([c[:2] for c in self.calls if c[0] == 'plugin'], [('plugin', 'load')])
        self.assertTrue(self.calls[-2][-1].endswith('/shake-to-find.so'))
        self.assertEqual(self.calls[-1], ('reload',))

    def test_mismatched_commit_changes_nothing(self):
        (self.directory / 'shake-to-find.so.commit').write_text('b' * 40)
        self.assertEqual(self.run_helper(), 1)
        self.assertEqual(self.calls, [('version',), ('-j', 'plugin', 'list')])
        self.rebuild.assert_called_once_with(self.directory, COMMIT)

    def test_missing_binary_changes_nothing(self):
        (self.directory / 'shake-to-find.so').unlink()
        self.assertEqual(self.run_helper(), 1)
        self.assertEqual(self.calls, [('version',), ('-j', 'plugin', 'list')])

    def test_unreachable_compositor_changes_nothing(self):
        self.failure = 'version'
        self.assertEqual(self.run_helper(), 1)
        self.assertEqual(self.calls, [('version',)])

    def test_ensure_preserves_current_plugin(self):
        self.loaded = [{'name': 'macshell-shake-to-find', 'version': '1.1'}]
        self.assertEqual(self.run_helper('--ensure'), 0)
        self.assertFalse(any(c[0] == 'plugin' for c in self.calls))

    def test_reloads_existing_plugin_only(self):
        self.loaded = [{'name': 'macshell-shake-to-find', 'version': '1.0'}, {'name': 'macshell-click-focus'}]
        self.assertEqual(self.run_helper(), 0)
        self.assertEqual([c[:2] for c in self.calls if c[0] == 'plugin'], [('plugin', 'unload'), ('plugin', 'load')])

    def test_conflicting_cursor_plugin_changes_nothing(self):
        self.loaded = [{'name': 'dynamic-cursors'}]
        self.assertEqual(self.run_helper(), 1)
        self.assertFalse(any(c[0] == 'plugin' for c in self.calls))

    def test_failed_unload_never_loads_another_copy(self):
        self.loaded = [{'name': 'macshell-shake-to-find'}]
        self.failure = 'plugin'
        self.assertEqual(self.run_helper(), 1)
        self.assertEqual(self.calls[-1][:2], ('plugin', 'unload'))

    def test_ensure_replaces_the_original_broken_version(self):
        self.loaded = [{'name': 'macshell-shake-to-find', 'version': '1.0'}]
        self.assertEqual(self.run_helper('--ensure'), 0)
        self.assertEqual([c[:2] for c in self.calls if c[0] == 'plugin'], [('plugin', 'unload'), ('plugin', 'load')])
        self.assertEqual(self.calls[-1], ('reload',))

    def test_failed_load_does_not_reload_config(self):
        self.failure = 'plugin'
        self.assertEqual(self.run_helper(), 1)
        self.assertEqual(self.calls[-1][:2], ('plugin', 'load'))
        self.assertNotIn(('reload',), self.calls)

    def test_reports_failed_config_reload_after_loading(self):
        self.failure = 'reload'
        self.assertEqual(self.run_helper(), 1)
        self.assertEqual(self.calls[-1], ('reload',))

    def test_upgrade_rebuilds_before_loading(self):
        (self.directory / 'shake-to-find.so.commit').write_text('b' * 40)
        def rebuild(directory, commit):
            self.assertFalse(any(c[0] == 'plugin' for c in self.calls))
            (directory / 'shake-to-find.so.commit').write_text(commit)
        self.rebuild.side_effect = rebuild
        self.assertEqual(self.run_helper(), 0)
        self.rebuild.assert_called_once_with(self.directory, COMMIT)
        self.assertEqual(self.calls[-2][0:2], ('plugin', 'load'))

    def test_failed_build_does_not_unload_plugin(self):
        (self.directory / 'shake-to-find.so.commit').write_text('b' * 40)
        self.loaded = [{'name': 'macshell-shake-to-find', 'version': '1.1'}]
        self.rebuild.side_effect = subprocess.CalledProcessError(1, ['sh', 'build.sh'])
        self.assertEqual(self.run_helper(), 1)
        self.assertFalse(any(c[0] == 'plugin' for c in self.calls))

    def test_incorrect_build_stamp_is_not_loaded(self):
        (self.directory / 'shake-to-find.so.commit').write_text('b' * 40)
        self.rebuild.side_effect = None
        self.assertEqual(self.run_helper(), 1)
        self.assertFalse(any(c[0] == 'plugin' for c in self.calls))

    def test_conflict_does_not_start_a_build(self):
        (self.directory / 'shake-to-find.so.commit').write_text('b' * 40)
        self.loaded = [{'name': 'dynamic-cursors'}]
        self.assertEqual(self.run_helper(), 1)
        self.rebuild.assert_not_called()


class BuildPreflightTests(unittest.TestCase):
    def test_different_headers_do_not_run_build(self):
        flags = subprocess.CompletedProcess([], 0, stdout='-I/usr/include/hyprland')
        macros = subprocess.CompletedProcess([], 0, stdout='#define GIT_COMMIT_HASH "' + 'b' * 40 + '"\n')
        with patch.object(reload.subprocess, 'run', side_effect=[flags, macros]) as run:
            with self.assertRaisesRegex(RuntimeError, 'Header Hyprland berbeda'):
                reload.rebuild_for_session(Path('/tmp/plugin'), COMMIT)
            self.assertEqual(run.call_count, 2)

    def test_matching_headers_run_build(self):
        flags = subprocess.CompletedProcess([], 0, stdout='-I"/tmp/path with spaces"')
        macros = subprocess.CompletedProcess([], 0, stdout='#define GIT_COMMIT_HASH "' + COMMIT + '"\n')
        with patch.object(reload.subprocess, 'run', side_effect=[flags, macros, subprocess.CompletedProcess([], 0)]) as run, \
                contextlib.redirect_stdout(io.StringIO()):
            reload.rebuild_for_session(Path('/tmp/plugin'), COMMIT)
            self.assertIn('-I/tmp/path with spaces', run.call_args_list[1].args[0])
            self.assertEqual(run.call_args_list[-1].args[0], ['sh', '/tmp/plugin/build.sh'])


if __name__ == '__main__':
    unittest.main()
