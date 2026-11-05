"""Recording completion and file actions without capturing the user's desktop."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HELPER = Path(__file__).resolve().parents[1] / "bin/notch_recording.py"
spec = importlib.util.spec_from_file_location("notch_recording", HELPER)
recording = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recording)


class RecordingResults(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="notch-recording-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.path = self.root / 'Demo "quoted" ; $file.mp4'
        self.path.write_bytes(b"video fixture")

    def test_rejects_remote_directory_empty_and_shortcut(self):
        empty = self.root / "empty.mp4"
        empty.touch()
        link = self.root / "shortcut.mp4"
        link.symlink_to(self.path)
        for value in ["https://example.com/test.mp4", "file://remote/test.mp4", "relative.mp4",
                      str(self.root), str(empty), str(link)]:
            with self.subTest(value=value), self.assertRaises((OSError, ValueError)):
                recording.local_file(value)
        self.assertEqual(recording.local_file(self.path.as_uri()), self.path)

    def test_real_video_metadata_and_thumbnail(self):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                        "color=c=blue:s=160x90:d=1:r=10", "-pix_fmt", "yuv420p", str(self.path)],
                       capture_output=True, check=True, timeout=20)
        with patch.dict(os.environ, XDG_CACHE_HOME=str(self.root / "cache")):
            result = recording.inspect_recording(str(self.path))
        self.assertTrue(result["ok"])
        self.assertAlmostEqual(result["duration"], 1, delta=.1)
        self.assertEqual(result["name"], self.path.name)
        self.assertEqual(result["directory"], str(self.root))
        thumbnail = recording.local_file(result["thumbnail"])
        self.assertEqual(thumbnail.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")

    def test_invalid_video_never_becomes_a_saved_result(self):
        with self.assertRaises(ValueError):
            recording.inspect_recording(str(self.path))

    def test_copy_uses_encoded_file_uri_without_shell(self):
        with patch.object(recording.subprocess, "run") as run:
            recording.perform("copy", str(self.path))
        self.assertEqual(run.call_args.args[0], ["wl-copy", "--type", "text/uri-list"])
        self.assertEqual(run.call_args.kwargs["input"], self.path.as_uri()+"\r\n")
        self.assertNotIn("shell", run.call_args.kwargs)

    def test_trash_is_recoverable_gio_action_and_failure_is_reported(self):
        with patch.object(recording.subprocess, "run") as run:
            recording.perform("trash", str(self.path))
        self.assertEqual(run.call_args.args[0], ["gio", "trash", "--", str(self.path)])
        self.assertTrue(self.path.exists())  # The test never removes user data.
        with patch.object(recording.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "gio")):
            with self.assertRaises(subprocess.CalledProcessError):
                recording.perform("trash", str(self.path))

    def test_watch_and_reveal_fallback_use_argument_arrays(self):
        with patch.object(recording.subprocess, "Popen") as launch:
            recording.perform("watch", str(self.path))
        self.assertEqual(launch.call_args.args[0], ["xdg-open", self.path.as_uri()])
        with patch.object(recording.subprocess, "run", side_effect=FileNotFoundError), \
             patch.object(recording.subprocess, "Popen") as launch:
            recording.perform("reveal", str(self.path))
        self.assertEqual(launch.call_args.args[0], ["xdg-open", self.root.as_uri()])

    def test_cli_returns_error_json_for_missing_recording(self):
        result = subprocess.run(["python3", str(HELPER), "inspect", str(self.root / "missing.mp4")],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertFalse(json.loads(result.stdout)["ok"])


if __name__ == "__main__":
    unittest.main()
