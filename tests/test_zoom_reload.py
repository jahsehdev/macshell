import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FAKE = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args=sys.argv[1:]
base=Path(os.environ['MACSHELL_ZOOM_TEST'])
with (base/'commands').open('a') as output: output.write(json.dumps(args)+'\\n')
if args==['version']: print('Hyprland 0.57.0 at commit '+'a'*40)
elif args==['-j','plugin','list']:
    version=(base/'native-version').read_text().strip()
    print(json.dumps([{'name':'macshell-fullscreen-lock','version':version}]))
elif args[:2]==['plugin','load']:
    (base/'native-version').write_text('1.6'); print('ok')
elif args==['reload']:
    (Path(os.environ['XDG_RUNTIME_DIR'])/'macshell-zoom.status').write_text('restore-v6\\n')
    print('ok')
else: print('ok')
'''


class ZoomReloadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.home = self.base / 'home'
        config = self.home / '.config/hypr'
        config.mkdir(parents=True)
        (config / 'macshell_zoom.lua').write_text("status:write('restore-v6\\n')\n")
        self.native = self.base / 'data/macshell/fullscreen-lock'
        self.native.mkdir(parents=True)
        (self.native / 'fullscreen-lock.so').touch()
        (self.native / 'fullscreen-lock.so.commit').write_text('a' * 40)
        self.runtime = self.base / 'runtime'
        self.runtime.mkdir()
        fake = self.base / 'hyprctl'
        fake.write_text(FAKE)
        fake.chmod(0o755)
        (self.base / 'native-version').write_text('1.5')
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.base)+':'+os.environ['PATH'],
                        XDG_RUNTIME_DIR=str(self.runtime), XDG_DATA_HOME=str(self.base/'data'),
                        MACSHELL_ZOOM_TEST=str(self.base))

    def run_reload(self):
        result = subprocess.run(['python3', str(ROOT/'bin/macshell-zoom-reload')],
                                env=self.env, capture_output=True, text=True, timeout=10)
        log = self.base / 'commands'
        return result, [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def test_upgrades_native_before_loading_lua(self):
        result, commands = self.run_reload()
        self.assertEqual(result.returncode, 0, result.stderr)
        operations = [command for command in commands if command[0] == 'plugin']
        self.assertEqual([command[1] for command in operations], ['unload', 'load'])
        self.assertTrue(all(command[-1].endswith('/fullscreen-lock.so') for command in operations))
        self.assertLess(commands.index(operations[-1]), commands.index(['reload']))
        self.assertEqual((self.runtime/'macshell-zoom.status').read_text().strip(), 'restore-v6')
        self.assertIn('1.6 aktif', result.stdout)

    def test_keeps_current_native_plugin(self):
        (self.base/'native-version').write_text('1.6')
        result, commands = self.run_reload()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(command[0] == 'plugin' for command in commands))
        self.assertIn(['reload'], commands)

    def test_rejects_binary_mismatch_before_config_reload(self):
        (self.native/'fullscreen-lock.so.commit').write_text('b' * 40)
        result, commands = self.run_reload()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(commands, [['version']])


if __name__ == '__main__':
    unittest.main()
