import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


class Snapshot(unittest.TestCase):
    def test_snapshot_keeps_name_percentage_and_device_type(self):
        source=(Path(__file__).resolve().parents[1]/'UpstreamBar/MacBar.qml').read_text()
        block=source.split('id: btProc',1)[1].split('stdout: StdioCollector',1)[0]
        command=''.join(json.loads(s) for s in re.findall(r'"(?:\\.|[^"\\])*"',block)[2:])
        with tempfile.TemporaryDirectory() as temp:
            fake=Path(temp)/'bluetoothctl'
            fake.write_text('''#!/usr/bin/python3
import sys
if sys.argv[1]=='show':print('Powered: yes')
elif sys.argv[1]=='devices':print('Device AA:BB:01 G915 keyboard')
elif sys.argv[1]=='info':print('Paired: yes\\nConnected: yes\\nBattery Percentage: 0x00 (0)\\nIcon: input-keyboard')
else:raise SystemExit('Unexpected mutating Bluetooth command')
''')
            fake.chmod(0o755)
            result=subprocess.run(['sh','-c',command],env={**os.environ,'PATH':temp+':'+os.environ['PATH']},text=True,capture_output=True,timeout=4,check=True)
        self.assertIn('P:Powered: yes',result.stdout)
        self.assertIn('D:AA:BB:01\t1\t1\t0\tG915 keyboard\tinput-keyboard',result.stdout)


if __name__=='__main__':unittest.main()
