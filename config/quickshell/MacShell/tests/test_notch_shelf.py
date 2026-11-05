import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('notch_shelf', Path(__file__).parents[1] / 'bin/notch_shelf.py')
shelf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shelf)


class ShelfTests(unittest.TestCase):
    def test_local_references_keep_files_untouched_and_deduplicate_encoded_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            file = Path(tmp) / 'hello # $(test).txt'
            file.write_text('original')
            folder = Path(tmp) / 'Project files'
            folder.mkdir()
            result = shelf.inspect([file.as_uri(), file.as_uri(), folder.as_uri()])
            self.assertEqual(len(result['items']), 2)
            self.assertFalse(result['errors'])
            self.assertEqual(result['items'][0]['name'], file.name)
            self.assertTrue(result['items'][1]['folder'])
            self.assertEqual(file.read_text(), 'original')

    def test_remote_missing_and_special_files_are_rejected(self):
        result = shelf.inspect(['https://example.com/file', 'file://remote/tmp/file', 'file:///no-such-notch-file', 'file:///dev/null'])
        self.assertFalse(result['items'])
        self.assertEqual(len(result['errors']), 4)

    def test_open_uses_an_argument_array_and_rechecks_missing_references(self):
        with tempfile.TemporaryDirectory() as tmp:
            file = Path(tmp) / 'a file.txt'
            file.touch()
            with patch.object(shelf.sys, 'argv', ['notch_shelf', 'open', file.as_uri()]), patch.object(shelf.subprocess, 'Popen') as launch, patch('builtins.print'):
                shelf.main()
                self.assertEqual(launch.call_args.args[0], ['xdg-open', file.as_uri()])
            file.unlink()
            with patch.object(shelf.sys, 'argv', ['notch_shelf', 'open', file.as_uri()]), patch.object(shelf.subprocess, 'Popen') as launch, patch('builtins.print'):
                shelf.main()
                launch.assert_not_called()


if __name__ == '__main__':
    unittest.main()
