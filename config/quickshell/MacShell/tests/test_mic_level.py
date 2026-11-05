"""Validate PCM metering and recorder cleanup without opening a real microphone."""
from array import array
import importlib.util
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import tempfile
import unittest

SHELL = Path(__file__).resolve().parents[1]
SCRIPT = SHELL / "bin/mic_level.py"
spec = importlib.util.spec_from_file_location("mic_level", SCRIPT)
meter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(meter)


class MicrophoneTests(unittest.TestCase):
    def test_silence_attack_release_and_normalization(self):
        envelope = meter.Envelope()
        silence = array("h", [0] * 533).tobytes()
        loud = array("h", [30000] * 533).tobytes()
        self.assertEqual(envelope.update(silence, 16000), 0)
        first = envelope.update(loud, 16000)
        self.assertGreater(first, 0.5)
        self.assertLess(first, 1)
        for _ in range(20):
            self.assertTrue(0 <= envelope.update(loud, 16000) <= 1)
        self.assertGreater(envelope.volume, 0.99)
        release = envelope.update(silence, 16000)
        self.assertGreater(release, 0.8)
        for _ in range(60):
            envelope.update(silence, 16000)
        self.assertLess(envelope.volume, 0.001)

    def test_pcm_stream_outputs_flushed_json_lines(self):
        pcm = array("h", [0] * 533 + [15000] * (533 * 5) + [0] * (533 * 10)).tobytes()
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--stdin"], input=pcm,
                                capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        levels = [json.loads(line)["volume"] for line in result.stdout.splitlines()]
        self.assertEqual(len(levels), 16)
        self.assertEqual(levels[0], 0)
        self.assertGreater(levels[5], 0.9)
        self.assertLess(levels[-1], levels[5])
        self.assertTrue(all(0 <= level <= 1 for level in levels))

    def test_sigterm_releases_recorder(self):
        with tempfile.TemporaryDirectory(prefix="luma-mic-test-") as directory:
            base = Path(directory)
            pid_file = base / "recorder.pid"
            fake = base / "pw-cat"
            fake.write_text(f'''#!{sys.executable}
from array import array
from pathlib import Path
import os, sys, time
Path(os.environ["TEST_MIC_PID"]).write_text(str(os.getpid()))
while True:
    sys.stdout.buffer.write(array("h",[3000]*533).tobytes())
    sys.stdout.buffer.flush()
    time.sleep(0.03)
''')
            fake.chmod(0o755)
            env = dict(os.environ, PATH=str(base) + os.pathsep + os.environ.get("PATH", ""), TEST_MIC_PID=str(pid_file))
            worker = subprocess.Popen([sys.executable, "-B", "-u", str(SCRIPT), "--backend=pipewire"],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(worker.stdout, selectors.EVENT_READ)
                    self.assertTrue(selector.select(timeout=5), "meter must stream promptly")
                # The status line precedes the first PCM block.
                worker.stdout.readline()
                self.assertEqual(json.loads(worker.stdout.readline())["event"], "level")
                recorder_pid = int(pid_file.read_text())
                worker.send_signal(signal.SIGTERM)
                worker.communicate(timeout=3)
                self.assertEqual(worker.returncode, 0)
                with self.assertRaises(ProcessLookupError):
                    os.kill(recorder_pid, 0)
            finally:
                if worker.poll() is None:
                    worker.terminate()
                    worker.communicate(timeout=3)


if __name__ == "__main__":
    unittest.main()
