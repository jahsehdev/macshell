import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / 'MacShell/bin/desktop_files.py'
spec = importlib.util.spec_from_file_location('desktop_customization_test', SOURCE)
desktop = importlib.util.module_from_spec(spec)
spec.loader.exec_module(desktop)


class Metadata:
    def get(self, path):
        return ''
    def set(self, path, value):
        pass


class DesktopCustomizationTests(unittest.TestCase):
    def test_customized_folder_rename_preserves_artwork(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / 'Desktop/Recipes $(echo harmless)'
            path.mkdir(parents=True)
            with patch.dict(os.environ, XDG_DATA_HOME=str(root / 'data')):
                desktop.Folder(path, Metadata()).apply(dict(color='#ffd43b', symbol='cutlery'))
                files = desktop.DesktopFiles(path.parent, root / 'layout.json')
                original_icon = files.listing()['items'][0]['customIcon']
                result = files.command(dict(action='rename', name=path.name, newName='Family recipes'))
                self.assertEqual(result['names'], ['Family recipes'])
                self.assertFalse(path.exists())
                self.assertEqual(files.listing()['items'][0]['customIcon'], original_icon)

    def test_customized_folder_collision_does_not_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, occupied = root / 'Source', root / 'Occupied'
            source.mkdir()
            occupied.mkdir()
            marker = occupied / 'keep.txt'
            marker.write_text('keep')
            with patch.dict(os.environ, XDG_DATA_HOME=str(root / 'data')):
                desktop.Folder(source, Metadata()).apply(dict(color='#ffd43b'))
                files = desktop.DesktopFiles(root, root / 'layout.json')
                with self.assertRaises(FileExistsError):
                    files.command(dict(action='rename', name='Source', newName='Occupied'))
                self.assertEqual(marker.read_text(), 'keep')
                self.assertTrue(source.is_dir())


if __name__ == '__main__':
    unittest.main()
