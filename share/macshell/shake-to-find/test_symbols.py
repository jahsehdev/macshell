"""Exercise cursor lookups using the same raw-symbol matching as Hyprland."""
from pathlib import Path
import re
import subprocess
import unittest


class CursorSymbolTests(unittest.TestCase):
    def test_runtime_queries_find_the_exact_cursor_abi(self):
        source = Path(__file__).with_name('shake-to-find.cpp').read_text()
        expected = dict(re.findall(r'const std::string (\w+Symbol) = "([^"]+)"', source))
        lookups = re.findall(
            r'findFunctionsByName\(handle, "([^"]+)"\)\)\s*if \(match.signature == (\w+)\)', source)
        self.assertEqual(len(lookups), 2, 'Both cursor entry points must retain an exact ABI guard')
        symbols = subprocess.check_output(
            ['nm', '-D', '-j', '--defined-only', '/usr/bin/Hyprland'], text=True).splitlines()
        for query, guard in lookups:
            with self.subTest(query=query):
                # PluginAPI.cpp filters mangled names BEFORE creating SFunctionMatch.
                matches = [symbol for symbol in symbols if query in symbol]
                self.assertIn(expected[guard], matches,
                              f'Runtime lookup {query!r} cannot resolve {guard}')


if __name__ == '__main__':
    unittest.main()
