import importlib.util
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


HELPER = Path(__file__).resolve().parents[1] / "desktop_files.py"
SPEC = importlib.util.spec_from_file_location("desktop_files", HELPER)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DesktopFilesTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.source = self.base / "source"
        self.source.mkdir()
        self.desktop = self.base / "Desktop"
        self.state = self.base / "config" / "layout.json"
        self.files = MODULE.DesktopFiles(self.desktop, self.state)

    def test_drop_copies_file_and_preserves_source(self):
        source = self.source / 'catatan 日本 $(literal) "name".txt'
        source.write_text("unchanged original")
        result = self.files.command({"action": "copy", "urls": [source.as_uri()]})
        self.assertFalse(result["error"])
        self.assertEqual(source.read_text(), "unchanged original")
        self.assertEqual((self.desktop / source.name).read_text(), source.read_text())

    def test_duplicate_names_never_overwrite(self):
        source = self.source / "report.txt"
        source.write_text("new content")
        (self.desktop / source.name).write_text("existing content")
        self.assertEqual(self.files.copy_one(source.as_uri()), "report copy.txt")
        self.assertEqual(self.files.copy_one(source.as_uri()), "report copy 2.txt")
        self.assertEqual((self.desktop / source.name).read_text(), "existing content")

    def test_directory_copy_includes_nested_files_and_symlinks(self):
        folder = self.source / "Project"
        (folder / "nested").mkdir(parents=True)
        (folder / "nested" / "file.txt").write_text("inside")
        (folder / "link").symlink_to("nested/file.txt")
        self.files.copy_one(folder.as_uri())
        self.files.copy_one(folder.as_uri())
        self.assertEqual((self.desktop / "Project/nested/file.txt").read_text(), "inside")
        self.assertTrue((self.desktop / "Project/link").is_symlink())
        self.assertEqual((self.desktop / "Project copy/link").read_text(), "inside")
        self.assertTrue(folder.exists())

    def test_rejects_recursive_copy_and_nonlocal_urls(self):
        with self.assertRaises(ValueError):
            self.files.copy_one(self.base.as_uri())
        with self.assertRaises(ValueError):
            self.files.copy_one(self.desktop.as_uri())
        with self.assertRaises(ValueError):
            self.files.copy_one("sftp://host/private.txt")
        with self.assertRaises(ValueError):
            self.files.copy_one("file://remote-host/private.txt")

    def test_partial_batch_reports_errors_and_keeps_successful_files(self):
        source = self.source / "ok.txt"
        source.write_text("ok")
        result = self.files.command({"action": "copy", "urls": [source.as_uri(), (self.source / "gone").as_uri()]})
        self.assertEqual(result["names"], ["ok.txt"])
        self.assertTrue(result["error"])
        self.assertTrue(source.exists())

    def test_rename_retains_position_and_rejects_collision_or_traversal(self):
        (self.desktop / "old.txt").write_text("original")
        (self.desktop / "occupied.txt").write_text("keep")
        self.files.command({"action": "positions", "positions": {"old.txt": {"x": 100, "y": 52}}})
        with self.assertRaises(FileExistsError):
            self.files.command({"action": "rename", "name": "old.txt", "newName": "occupied.txt"})
        for name in ("../outside", "", ".", "..", "bad/name"):
            with self.assertRaises(ValueError):
                self.files.command({"action": "rename", "name": "old.txt", "newName": name})
        self.files.command({"action": "rename", "name": "old.txt", "newName": "new.txt"})
        reloaded = MODULE.DesktopFiles(self.desktop, self.state)
        self.assertEqual(reloaded.positions["new.txt"], {"x": 100, "y": 52})
        self.assertEqual((self.desktop / "occupied.txt").read_text(), "keep")

    def test_new_folders_and_external_listing(self):
        one = self.files.command({"action": "mkdir"})["names"][0]
        two = self.files.command({"action": "mkdir"})["names"][0]
        self.assertNotEqual(one, two)
        (self.desktop / ".hidden").write_text("hidden")
        self.assertEqual(len(self.files.listing()["items"]), 2)

    def test_trash_preserves_a_recoverable_copy(self):
        path = self.desktop / "trash me.txt"
        path.write_text("recover me")
        data_home = self.base / "data"
        data_home.mkdir()
        with patch.dict(os.environ, {"XDG_DATA_HOME": str(data_home)}):
            self.files.command({"action": "trash", "names": [path.name]})
        self.assertFalse(path.exists())
        trashed = list((data_home / "Trash/files").iterdir())
        self.assertEqual(len(trashed), 1)
        self.assertEqual(trashed[0].read_text(), "recover me")
        self.assertTrue(list((data_home / "Trash/info").glob("*.trashinfo")))

    def test_configured_desktop_directory_is_respected(self):
        config = self.base / "xdg-config"
        config.mkdir()
        custom = self.base / "Custom Desktop"
        (config / "user-dirs.dirs").write_text('XDG_DESKTOP_DIR="' + str(custom) + '"\n')
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(config)}):
            self.assertEqual(MODULE.desktop_directory(), custom)

    def test_daemon_detects_external_file_and_handles_copy_requests(self):
        process = subprocess.Popen([sys.executable, "-u", str(HELPER), "--desktop", str(self.desktop), "--state", str(self.state)],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: process.poll() is None and process.kill())
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        self.addCleanup(selector.close)
        def receive(predicate):
            until = time.monotonic() + 4
            while time.monotonic() < until:
                if selector.select(0.2):
                    event = json.loads(process.stdout.readline())
                    if predicate(event):
                        return event
            self.fail("desktop daemon did not produce the expected event")
        receive(lambda event: event.get("event") == "files")
        (self.desktop / "from Dolphin.txt").write_text("external")
        event = receive(lambda event: event.get("event") == "files" and bool(event["items"]))
        self.assertEqual(event["items"][0]["name"], "from Dolphin.txt")
        source = self.source / "drop.txt"
        source.write_text("drop")
        process.stdin.write((json.dumps({"action": "copy", "urls": [source.as_uri()]}) + "\n").encode())
        process.stdin.flush()
        receive(lambda event: event.get("event") == "result" and event.get("names") == ["drop.txt"])
        self.assertTrue(source.exists())
        process.stdin.close()
        process.wait(timeout=3)
        self.assertEqual(process.returncode, 0, process.stderr.read().decode())
        process.stdout.close()
        process.stderr.close()


if __name__ == "__main__":
    unittest.main()
