import importlib.util
import json
from pathlib import Path
import sqlite3
import subprocess
import selectors
import os
import time
from contextlib import closing
import tempfile
import unittest
import zipfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("downloads", Path(__file__).parents[1] / "bin/notch_downloads.py")
downloads = importlib.util.module_from_spec(spec)
spec.loader.exec_module(downloads)


class DownloadsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="notch downloads ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_existing_files_do_not_replay_and_unknown_total_stays_unknown(self):
        (self.root / "old.zip").write_bytes(b"old")
        watcher = downloads.FolderDownloads([self.root], now=100)
        self.assertEqual(watcher.update(101), [])
        file = self.root / "new.zip.part"
        file.write_bytes(b"a" * 100)
        job = watcher.update(102)[0]
        self.assertEqual(job["state"], "active")
        self.assertEqual(job["name"], "new.zip")
        self.assertEqual((job["total"], job["progress"], job["eta"]), (-1, -1, -1))
        file.write_bytes(b"a" * 300)
        job = watcher.update(104)[0]
        self.assertEqual(job["received"], 300)
        self.assertGreater(job["speed"], 0)
        self.assertEqual(watcher.update(120)[0]["state"], "waiting")

    def test_partial_rename_is_complete_with_stable_identity_and_expires(self):
        watcher = downloads.FolderDownloads([self.root], now=100)
        part = self.root / "Launch 'demo'.zip.crdownload"
        part.write_bytes(b"zip content")
        first = watcher.update(101)[0]
        part.rename(self.root / "Launch 'demo'.zip")
        result = watcher.update(102)[0]
        self.assertEqual(result["id"], first["id"])
        self.assertEqual((result["state"], result["progress"]), ("complete", 1))
        self.assertEqual(result["total"], len(b"zip content"))
        self.assertEqual(watcher.update(106)[0]["state"], "complete")
        self.assertEqual(watcher.update(133), [])

    def test_direct_writes_and_extracted_files_are_not_downloads(self):
        watcher = downloads.FolderDownloads([self.root], now=100)
        target = self.root / "application.bin"
        target.write_bytes(b"a" * 40)
        watcher.update(101)
        self.assertEqual(watcher.update(105), [])
        target.write_bytes(b"b" * 80)
        self.assertEqual(watcher.update(107), [])

    def test_extraction_temp_files_and_nested_partial_names_are_ignored(self):
        watcher = downloads.FolderDownloads([self.root], now=100)
        (self.root / "archive.tmp").write_bytes(b"extraction scratch data")
        extracted = self.root / "extracted"
        extracted.mkdir()
        for name in ("readme.txt", "example.part", "sample.crdownload"):
            (extracted / name).write_bytes(b"archive member")
        self.assertEqual(watcher.update(101), [])

    def test_extracting_an_archive_in_downloads_produces_no_activity(self):
        archive = self.root / "downloaded.zip"
        with zipfile.ZipFile(archive, "w") as bundle:
            for name in ("README.txt", "temporary.tmp", "project/main.py", "project/example.part"):
                bundle.writestr(name, "extracted content")
        watcher = downloads.FolderDownloads([self.root], now=100)
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(self.root)
        self.assertEqual(watcher.update(101), [])
        self.assertEqual(watcher.update(105), [])

    def test_partial_can_finalize_by_copy_with_a_new_inode(self):
        watcher = downloads.FolderDownloads([self.root], now=100)
        part = self.root / "file.zip.part"
        part.write_bytes(b"download bytes")
        first = watcher.update(101)[0]
        target = self.root / "file.zip"
        target.write_bytes(part.read_bytes())
        part.unlink()
        result = watcher.update(104)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["id"], first["id"])
        self.assertEqual(result[0]["state"], "complete")
        self.assertEqual(watcher.update(108)[0]["state"], "complete")

    def test_editing_a_completed_download_does_not_restart_the_activity(self):
        watcher = downloads.FolderDownloads([self.root], now=100)
        part = self.root / "file.zip.part"
        part.write_bytes(b"download")
        watcher.update(101)
        target = self.root / "file.zip"
        part.rename(target)
        watcher.update(102)
        target.write_bytes(b"modified locally")
        self.assertEqual(watcher.update(105)[0]["state"], "complete")

    def test_delayed_final_rename_gets_grace_from_disappearance(self):
        watcher = downloads.FolderDownloads([self.root], now=100)
        part = self.root / "file.zip.part"
        part.write_bytes(b"download bytes")
        watcher.update(101)
        watcher.update(120)
        part.unlink()
        self.assertNotEqual(watcher.update(121)[0]["state"], "interrupted")
        (self.root / "file.zip").write_bytes(b"download bytes")
        self.assertEqual(watcher.update(122)[0]["state"], "complete")

    def test_deleted_partial_is_interrupted_not_completed(self):
        watcher = downloads.FolderDownloads([self.root], now=100)
        part = self.root / "file.part"
        part.write_bytes(b"partial")
        watcher.update(101)
        part.unlink()
        watcher.update(102)
        self.assertEqual(watcher.update(105)[0]["state"], "interrupted")

    def test_cancelled_replacement_does_not_complete_an_old_destination(self):
        (self.root / "file.zip").write_bytes(b"old download")
        watcher = downloads.FolderDownloads([self.root], now=100)
        part = self.root / "file.zip.part"
        part.write_bytes(b"new partial")
        watcher.update(101)
        part.unlink()
        watcher.update(102)
        self.assertEqual(watcher.update(105)[0]["state"], "interrupted")

    def test_symlinks_and_aria2_metadata_are_ignored(self):
        watcher = downloads.FolderDownloads([self.root], now=100)
        (self.root / "sidecar.aria2").write_bytes(b"metadata")
        (self.root / "link.part").symlink_to("/etc/hosts")
        self.assertEqual(watcher.update(101), [])

    def test_aria2_sidecar_keeps_destination_pending_until_removed(self):
        watcher = downloads.FolderDownloads([self.root], now=100)
        target = self.root / "archive.zip"
        sidecar = self.root / "archive.zip.aria2"
        target.write_bytes(b"a" * 20)
        sidecar.write_bytes(b"metadata")
        watcher.update(101)
        self.assertEqual(watcher.update(105)[0]["state"], "active")
        sidecar.unlink()
        self.assertEqual(watcher.update(106)[0]["state"], "complete")

    def test_watch_cli_streams_real_file_updates_and_completion(self):
        destination = self.root / "Downloads"
        destination.mkdir()
        config = self.root / "config"
        config.mkdir()
        (config / "user-dirs.dirs").write_text('XDG_DOWNLOAD_DIR="' + str(destination) + '"\n')
        process = subprocess.Popen(["python3", "-B", str(spec.origin), "watch"], env=dict(os.environ, XDG_CONFIG_HOME=str(config)), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(process.stderr.close)
        self.addCleanup(process.stdout.close)
        def stop():
            process.terminate()
            process.wait(timeout=3)
        self.addCleanup(stop)
        selector = selectors.DefaultSelector()
        self.addCleanup(selector.close)
        selector.register(process.stdout, selectors.EVENT_READ)
        def packet():
            self.assertTrue(selector.select(4), "Watcher did not stream a packet")
            return json.loads(process.stdout.readline())
        self.assertEqual(packet()["items"], [])
        # Real watcher output stays silent for ordinary Nautilus-style writes.
        (destination / "copied.txt").write_bytes(b"local file")
        (destination / "extract.tmp").write_bytes(b"extraction scratch")
        extracted = destination / "extracted"
        extracted.mkdir()
        (extracted / "sample.part").write_bytes(b"archive member")
        self.assertFalse(selector.select(1.6), "Extraction incorrectly emitted download activity")
        part = destination / "cli test.zip.part"
        part.write_bytes(b"a" * 256)
        first = packet()["items"][0]
        self.assertEqual(first["received"], 256)
        part.rename(destination / "cli test.zip")
        final = packet()["items"][0]
        self.assertEqual(final["id"], first["id"])
        self.assertEqual(final["state"], "complete")

    def browser(self):
        database = self.root / "History"
        with closing(sqlite3.connect(database)) as db, db:
            # Real Chromium History schemas need not contain a paused column.
            db.execute("CREATE TABLE downloads(id INTEGER,current_path TEXT,target_path TEXT,received_bytes INTEGER,total_bytes INTEGER,state INTEGER,end_time INTEGER,start_time INTEGER)")
            db.execute("INSERT INTO downloads VALUES(1,?,?,?,?,0,0,1)",
                       (str(self.root / "browser.zip.crdownload"), str(self.root / "browser.zip"), 100, 1000))
            db.execute("INSERT INTO downloads VALUES(2,'',?,100,100,1,1,1)", (str(self.root / "old.zip"),))
        return database, downloads.BrowserDownloads([database], now=100)

    def test_browser_real_totals_eta_completion_and_no_historic_events(self):
        database, watcher = self.browser()
        first = watcher.update(101)
        self.assertEqual(len(first), 1)
        self.assertEqual(first[0]["progress"], .1)
        self.assertEqual(first[0]["eta"], -1)
        with closing(sqlite3.connect(database)) as db, db:
            db.execute("UPDATE downloads SET received_bytes=300 WHERE id=1")
        active = watcher.update(103)[0]
        self.assertAlmostEqual(active["progress"], .3)
        self.assertGreater(active["eta"], 0)
        (self.root / "browser.zip").write_bytes(b"a" * 1000)
        with closing(sqlite3.connect(database)) as db, db:
            db.execute("UPDATE downloads SET received_bytes=1000,state=1,end_time=? WHERE id=1", ((105+downloads.CHROME_EPOCH)*1e6,))
        self.assertEqual(watcher.update(106)[0]["state"], "complete")
        self.assertEqual(watcher.update(140), [])

    def test_browser_metadata_overrides_folder_duplicate(self):
        _, watcher = self.browser()
        browser = watcher.update(101)
        folder = [dict(browser[0], id="folder", total=-1, source="folder")]
        merged = downloads.merge_jobs(folder, browser)
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0]["source"], "browser")

    def test_browser_success_does_not_depend_on_final_file_visibility(self):
        database, watcher = self.browser()
        watcher.update(101)
        with closing(sqlite3.connect(database)) as db, db:
            db.execute("UPDATE downloads SET received_bytes=1000,state=1,end_time=? WHERE id=1",
                       ((105+downloads.CHROME_EPOCH)*1e6,))
        job = watcher.update(106)[0]
        self.assertEqual(job["state"], "complete")
        self.assertEqual((job["progress"], job["eta"], job["speed"], job["error"]), (1, 0, 0, ""))
        self.assertEqual(watcher.update(107)[0]["state"], "complete")

    def test_completed_empty_browser_download_is_successful(self):
        database, watcher = self.browser()
        (self.root / "browser.zip").touch()
        with closing(sqlite3.connect(database)) as db, db:
            db.execute("UPDATE downloads SET received_bytes=0,total_bytes=0,state=1,end_time=? WHERE id=1",
                       ((105+downloads.CHROME_EPOCH)*1e6,))
        self.assertEqual(watcher.update(106)[0]["state"], "complete")

    def test_browser_completion_covers_earlier_unconfirmed_partial(self):
        database, watcher = self.browser()
        partial = self.root / "Unconfirmed 123.crdownload"
        with closing(sqlite3.connect(database)) as db, db:
            db.execute("UPDATE downloads SET current_path=? WHERE id=1", (str(partial),))
        browser = watcher.update(101)
        folder = [dict(browser[0], id="folder", source="folder", path=str(downloads.final_path(partial)), state="interrupted")]
        with closing(sqlite3.connect(database)) as db, db:
            db.execute("UPDATE downloads SET current_path=target_path,state=1,end_time=? WHERE id=1",
                       ((105+downloads.CHROME_EPOCH)*1e6,))
        merged = downloads.merge_jobs(folder, watcher.update(106))
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0]["state"], "complete")

    def test_new_browser_retry_takes_precedence_over_old_failure_at_same_path(self):
        path = str(self.root / "browser.zip")
        jobs = [{"path": path, "state": "complete", "changed": 105},
                {"path": path, "state": "interrupted", "changed": 104}]
        self.assertEqual(downloads.merge_jobs([], jobs)[0]["state"], "complete")

    def test_newest_attempt_wins_across_browser_profiles(self):
        path = str(self.root / "browser.zip")
        jobs = [{"path": path, "state": "interrupted", "changed": 106, "_started": 100},
                {"path": path, "state": "complete", "changed": 105, "_started": 104}]
        merged = downloads.merge_jobs([], jobs)
        self.assertEqual(merged[0]["state"], "complete")
        self.assertNotIn("_started", merged[0])

    def test_browser_takes_over_fallback_without_ghost_failure_after_expiry(self):
        folders = downloads.FolderDownloads([self.root], now=100)
        part = self.root / "Unconfirmed 123.crdownload"
        part.write_bytes(b"a" * 100)
        folders.update(101)
        database, watcher = self.browser()
        with closing(sqlite3.connect(database)) as db, db:
            db.execute("UPDATE downloads SET current_path=? WHERE id=1", (str(part),))
        browser = watcher.update(102)
        self.assertEqual(folders.update(102, downloads.browser_paths(browser)), [])
        (self.root / "browser.zip").write_bytes(b"a" * 1000)
        part.unlink()
        with closing(sqlite3.connect(database)) as db, db:
            db.execute("UPDATE downloads SET current_path=target_path,received_bytes=1000,state=1,end_time=? WHERE id=1",
                       ((105+downloads.CHROME_EPOCH)*1e6,))
        browser = watcher.update(106)
        folder = folders.update(106, downloads.browser_paths(browser))
        self.assertEqual([j["state"] for j in downloads.merge_jobs(folder, browser)], ["complete"])
        browser = watcher.update(136)
        folder = folders.update(136, downloads.browser_paths(browser))
        self.assertEqual(downloads.merge_jobs(folder, browser), [])

    def test_real_browser_interruption_still_reports_failure(self):
        database, watcher = self.browser()
        with closing(sqlite3.connect(database)) as db, db:
            db.execute("UPDATE downloads SET state=3,end_time=? WHERE id=1",
                       ((105+downloads.CHROME_EPOCH)*1e6,))
        job = watcher.update(106)[0]
        self.assertEqual(job["state"], "interrupted")
        self.assertTrue(job["error"])

    def test_file_actions_pass_literal_paths_and_reject_missing_or_symlink(self):
        target = self.root / "file 'quote' $(command).zip"
        target.write_bytes(b"content")
        with patch.object(downloads.subprocess, "Popen") as launch:
            self.assertTrue(downloads.file_action("open", str(target))["ok"])
            self.assertEqual(launch.call_args.args[0], ["xdg-open", target.as_uri()])
        (self.root / "link.zip").symlink_to(target)
        for invalid in ("relative.zip", str(self.root / "missing"), str(self.root / "link.zip")):
            with self.assertRaises(ValueError):
                downloads.file_action("open", invalid)


if __name__ == "__main__":
    unittest.main()
