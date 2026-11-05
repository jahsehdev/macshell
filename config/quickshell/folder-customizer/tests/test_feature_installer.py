"""Protect existing config files when the targeted feature update fails."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('folder_feature_installer', Path(__file__).resolve().parents[4] / 'scripts/install-folder-customizer.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class FeatureInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        native = self.source / 'share/macshell/folder-customizer/native'
        native.mkdir(parents=True)
        (native / 'folder-menu.so').touch()
        self.home = self.root / 'home'
        self.home.mkdir()
        self.file = self.home / 'existing.qml'
        self.file.write_text('user configuration')
        self.new = self.source / 'new.qml'
        self.new.write_text('updated configuration')
        self.patch = patch.object(installer, 'ROOT', self.source)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_failed_update_restores_earlier_files(self):
        directory = self.home / 'directory'
        directory.mkdir()
        with patch.object(installer, 'payload', return_value=[(self.new, self.file), (self.new, directory)]):
            with self.assertRaises(RuntimeError):
                installer.install(self.home, skip_build=True)
        self.assertEqual(self.file.read_text(), 'user configuration')
        self.assertTrue(directory.is_dir())

    def test_successful_update_retains_original_backup_and_symlink(self):
        link = self.source / 'link'
        link.symlink_to('new.qml')
        target_link = self.home / 'link'
        with patch.object(installer, 'payload', return_value=[(self.new, self.file), (link, target_link)]):
            installer.install(self.home, skip_build=True)
        self.assertEqual(self.file.read_text(), 'updated configuration')
        backup = next((self.home / '.local/state/macshell/backups').glob('folder-customizer-*'))
        self.assertEqual((backup / '0').read_text(), 'user configuration')
        self.assertTrue(target_link.is_symlink())
        self.assertEqual(target_link.readlink(), Path('new.qml'))


if __name__ == '__main__':
    unittest.main()
