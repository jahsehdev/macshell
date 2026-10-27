import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'scripts/install.py'
spec = importlib.util.spec_from_file_location('macshell_installer', SOURCE)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.bundle = root / 'bundle'
        self.bundle.mkdir()
        self.home = root / 'new user'
        self.args = types.SimpleNamespace(home=str(self.home), reset_settings=False, skip_build=True)
        self.paths = installer.paths(self.args)
        self.file('VERSION', '1.0.0\n')
        self.file('scripts/install.py', '# installer fixture\n')
        self.file('scripts/dependencies.sh', '#!/bin/sh\n')
        self.file('config/hypr/hyprland.lua', 'local home = "@HOME@"\n')
        self.file('config/macdock/settings.json', '{"theme":"default"}\n')
        self.file('config/quickshell/Common/qmldir', '')
        (self.bundle / 'config/quickshell/MacShell').mkdir()
        (self.bundle / 'config/quickshell/MacShell/Common').symlink_to('../Common')
        self.patch = patch.object(installer, 'ROOT', self.bundle)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def file(self, name, text):
        path = self.bundle / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def install(self, plan=None):
        with contextlib.redirect_stdout(io.StringIO()):
            installer.install(plan or installer.plan_payload(self.paths, self.args), self.paths, self.args)

    def uninstall(self):
        with contextlib.redirect_stdout(io.StringIO()):
            installer.uninstall(self.paths)

    def test_installs_and_restores_original_config(self):
        destination = self.paths['CONFIG_HOME'] / 'hypr/hyprland.lua'
        destination.parent.mkdir(parents=True)
        destination.write_text('original configuration\n')
        self.install()
        self.assertIn(str(self.home), destination.read_text())
        link = self.paths['CONFIG_HOME'] / 'quickshell/MacShell/Common'
        self.assertEqual(link.readlink(), Path('../Common'))
        self.assertTrue(link.is_dir())
        self.uninstall()
        self.assertEqual(destination.read_text(), 'original configuration\n')
        self.assertFalse(link.is_symlink())

    def test_existing_settings_are_preserved(self):
        settings = self.paths['CONFIG_HOME'] / 'macdock/settings.json'
        settings.parent.mkdir(parents=True)
        settings.write_text('{"theme":"mine"}\n')
        self.install()
        self.assertEqual(settings.read_text(), '{"theme":"mine"}\n')
        self.uninstall()
        self.assertTrue(settings.exists())

    def test_updates_preserve_first_backup(self):
        destination = self.paths['CONFIG_HOME'] / 'hypr/hyprland.lua'
        destination.parent.mkdir(parents=True)
        destination.write_text('pre-existing desktop\n')
        self.install()
        self.file('config/hypr/hyprland.lua', 'updated code\n')
        self.install()
        self.assertEqual(destination.read_text(), 'updated code\n')
        self.uninstall()
        self.assertEqual(destination.read_text(), 'pre-existing desktop\n')

    def test_uninstall_keeps_user_edits(self):
        self.install()
        destination = self.paths['CONFIG_HOME'] / 'hypr/hyprland.lua'
        destination.write_text('user edit after install\n')
        self.uninstall()
        self.assertEqual(destination.read_text(), 'user edit after install\n')

    def test_failure_rolls_back_files_already_written(self):
        first = self.home / 'first'
        first.parent.mkdir(parents=True)
        first.write_text('before\n')
        directory = self.home / 'collision'
        directory.mkdir()
        source = self.file('config/changed', 'after\n')
        with self.assertRaisesRegex(RuntimeError, 'directory'):
            self.install([(source, first, False), (source, directory, False)])
        self.assertEqual(first.read_text(), 'before\n')
        self.assertTrue(directory.is_dir())

    def test_reset_settings_can_be_uninstalled(self):
        settings = self.paths['CONFIG_HOME'] / 'macdock/settings.json'
        settings.parent.mkdir(parents=True)
        settings.write_text('{"theme":"mine"}\n')
        self.args.reset_settings = True
        self.install()
        self.assertIn('default', settings.read_text())
        self.uninstall()
        self.assertIn('mine', settings.read_text())

    def test_shell_template_assignment_preserves_home_with_spaces(self):
        source = self.file('bin/example', '#!/bin/sh\nsource_dir=@HOME@/assets\n')
        rendered = installer.rendered(source, self.paths).decode()
        self.assertIn('source_dir="' + str(self.home) + '/assets"', rendered)


if __name__ == '__main__':
    unittest.main()
