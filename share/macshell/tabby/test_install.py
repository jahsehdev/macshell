import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('installer', Path(__file__).with_name('install.py'))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class Migration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='tabby-migration-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.binary = self.root / 'fake-tabby'
        self.binary.write_text('#!/usr/bin/env python3\nimport json,sys,os\nprint(json.dumps({"argv":sys.argv[1:],"cwd":os.getcwd()}))\n')
        self.binary.chmod(0o755)
        self.fixture('.config/hypr/hyprland.lua', 'local terminal = "kitty"\n')
        self.fixture('.config/macbar/settings.json', '{"terminal":"kitty","unrelated":42}')
        self.fixture('.config/macdock/pinned.json', '["firefox","kitty","spotify"]')
        self.fixture('.config/kdeglobals', '[General]\nColorScheme=MacTahoeDark\n')
        self.fixture('.config/quickshell/MacShell/MacBar.qml', 'property string terminal: "kitty"\nif (any(["kitty", "alacritty"])) return "terminal";\n')
        self.fixture('.config/quickshell/MacShell/MacDock.qml', 'var term = root.bar ? root.bar.terminal : "kitty";\n["kitty", "com.mitchellh.ghostty"]\n')

    def fixture(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def test_missing_binary_does_not_switch_defaults(self):
        with self.assertRaises(RuntimeError):
            installer.prepare_files(self.root, self.root / 'missing')
        self.assertIn('kitty', (self.root / '.config/hypr/hyprland.lua').read_text())

    def test_all_default_routes_use_new_terminal(self):
        files = installer.prepare_files(self.root, self.binary)
        launcher = str(self.root / '.local/bin/macshell-terminal')
        self.assertIn(launcher, files['.config/hypr/hyprland.lua'])
        data = json.loads(files['.config/macbar/settings.json'])
        self.assertEqual(data['terminal'], launcher)
        self.assertEqual(data['unrelated'], 42)
        self.assertEqual(json.loads(files['.config/macdock/pinned.json']), ['firefox', 'tabby', 'spotify'])
        self.assertIn('ColorScheme=MacTahoeDark', files['.config/kdeglobals'])
        self.assertIn('TerminalService=tabby.desktop', files['.config/kdeglobals'])
        self.assertNotIn(': "kitty";', files['.config/quickshell/MacShell/MacDock.qml'])

    def test_routing_preserves_shell_arguments_without_executing_them(self):
        backup = installer.apply(self.root, installer.prepare_files(self.root, self.binary))
        self.assertTrue((backup / 'manifest.json').exists())
        payload = 'echo a $HOME; `do-not-run-this`'
        result = subprocess.check_output([str(self.root / '.local/bin/macshell-terminal'), '-e', '/bin/sh', '-c', payload],
                                         env={**os.environ, 'HOME': str(self.root)}, text=True)
        self.assertEqual(json.loads(result)['argv'], ['run', '--', '/bin/sh', '-c', payload])

    def test_working_directory_and_backups(self):
        installer.apply(self.root, installer.prepare_files(self.root, self.binary))
        directory = self.root / 'folder with spaces'; directory.mkdir()
        result = subprocess.check_output([str(self.root / '.local/bin/macshell-terminal'), '--dir', str(directory)],
                                         env={**os.environ, 'HOME': str(self.root)}, text=True)
        self.assertEqual(json.loads(result), {'argv': ['open', str(directory)], 'cwd': str(directory)})
        manifest = next((self.root / '.local/state/macshell/backups').glob('*/manifest.json'))
        saved = manifest.parent / '.config/macdock/pinned.json'
        self.assertEqual(json.loads(saved.read_text()), ['firefox', 'kitty', 'spotify'])
        self.assertEqual((self.root / '.config/tabby/config.yaml').stat().st_mode & 0o777, 0o600)


if __name__ == '__main__':
    unittest.main()
