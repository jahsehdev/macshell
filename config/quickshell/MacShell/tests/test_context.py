"""Exercise the personal-context bridge (bin/context.py) against temporary data.

Covers: source controls (enable/disable/configure), the fixture-folder file index
(incremental, cleanup, skip rules), the Notes and Calendar source contracts
(through the sibling CLIs with temp databases), search with provenance and
disabled-source exclusion, and the contract document itself.
"""
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
CTX_PY = HERE.parent / "bin/context.py"
NOTES_PY = HERE.parent / "bin/notes.py"
CAL_PY = HERE.parent / "bin/calendar.py"
SHELL = HERE.parent / "shell.qml"
LUMA_SETTINGS = HERE.parent / "LumaSettings.qml"


class ContextCliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.db = self.tmp / "context.db"
        self.fixture = self.tmp / "fixture"
        self.fixture.mkdir()
        self.run_cli("disable", "--kind", "files")  # ensure a clean default state

    def run_cli(self, *args, expect_ok=True):
        result = subprocess.run(
            [sys.executable, "-B", str(CTX_PY), "--db", str(self.db)] + list(args),
            capture_output=True, text=True, env=dict(os.environ, XDG_DATA_HOME=str(self.tmp / "data")))
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError:
            self.fail("non-JSON output: " + result.stdout + result.stderr)
        if expect_ok:
            self.assertEqual(result.returncode, 0, payload)
            self.assertNotIn("error", payload)
        return payload

    # ── controls ──
    def test_sources_start_disabled(self):
        sources = self.run_cli("sources")["sources"]
        self.assertEqual([s["kind"] for s in sources],
                         ["calendar", "files", "mail", "notes"])
        self.assertTrue(all(not s["enabled"] for s in sources))

    def test_enable_disable_roundtrip(self):
        self.run_cli("enable", "--kind", "notes")
        row = [s for s in self.run_cli("sources")["sources"] if s["kind"] == "notes"][0]
        self.assertTrue(row["enabled"])
        self.run_cli("disable", "--kind", "notes")
        row = [s for s in self.run_cli("sources")["sources"] if s["kind"] == "notes"][0]
        self.assertFalse(row["enabled"])

    def test_unknown_kind_rejected(self):
        self.run_cli("enable", "--kind", "browser", expect_ok=False)
        self.run_cli("configure", "--kind", "browser", "--folders", "/tmp", expect_ok=False)

    def test_files_needs_folders(self):
        self.run_cli("enable", "--kind", "files")
        row = [s for s in self.run_cli("sources")["sources"] if s["kind"] == "files"][0]
        self.assertEqual(row["status"], "needs-folders")

    # ── fixture-folder file index ──
    def test_files_index_search_and_provenance(self):
        (self.fixture / "catatan.txt").write_text("hello luma context\n")
        (self.fixture / "plan.md").write_text("rahasia proyek alpha\n")
        (self.fixture / "node_modules" / "x.js").parent.mkdir()
        (self.fixture / "node_modules" / "x.js").write_text("var hidden = 1\n")
        (self.fixture / ".hidden.txt").write_text("tersembunyi\n")
        (self.fixture / "binary.png").write_bytes(b"\x00\x01\x02not text")
        self.run_cli("enable", "--kind", "files")
        self.run_cli("configure", "--kind", "files", "--folders", str(self.fixture))
        report = self.run_cli("index")["report"]["files"]
        self.assertEqual(report["indexed"], 2)  # node_modules, hidden and binary skipped

        result = self.run_cli("search", "--query", "luma")["results"]
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["ref"], str(self.fixture / "catatan.txt"))
        self.assertEqual(result[0]["provenance"]["kind"], "files")
        self.assertEqual(result[0]["provenance"]["indexer"], "macshell-context/1")
        self.assertIn("luma", result[0]["snippet"])

        # unchanged files are not re-read; an edited file is picked up again
        report = self.run_cli("index")["report"]["files"]
        self.assertEqual(report["indexed"], 0)
        (self.fixture / "plan.md").write_text("alpha diedit sekarang\n")
        os.utime(self.fixture / "plan.md", (time.time(), time.time() + 5))
        report = self.run_cli("index")["report"]["files"]
        self.assertEqual(report["indexed"], 1)
        result = self.run_cli("search", "--query", "diedit")["results"]
        self.assertEqual(len(result), 1)

        # deleting a file removes it from the index
        (self.fixture / "plan.md").unlink()
        report = self.run_cli("index")["report"]["files"]
        self.assertEqual(report["removed"], 1)
        result = self.run_cli("search", "--query", "diedit")["results"]
        self.assertEqual(result, [])

    def test_disabled_files_are_not_indexed(self):
        (self.fixture / "catatan.txt").write_text("hello luma\n")
        self.run_cli("configure", "--kind", "files", "--folders", str(self.fixture))
        report = self.run_cli("index")["report"]["files"]
        self.assertEqual(report["indexed"], 0)
        self.assertEqual(report["skipped-source"], "disabled")
        result = self.run_cli("search", "--query", "luma")["results"]
        self.assertEqual(result, [])

    # ── Notes source contract ──
    def test_notes_contract(self):
        notes_db = self.tmp / "notes.db"
        note = subprocess.run([sys.executable, "-B", str(NOTES_PY), "--db", str(notes_db), "new"],
                              capture_output=True, text=True)
        note_id = json.loads(note.stdout)["note"]["id"]
        subprocess.run([sys.executable, "-B", str(NOTES_PY), "--db", str(notes_db), "save", "--json",
                        json.dumps({"id": note_id, "title": "Ide resep", "body": "nasi goreng"})],
                       capture_output=True, text=True)
        self.run_cli("enable", "--kind", "notes")
        self.run_cli("configure", "--kind", "notes", "--path", str(notes_db))
        # the adapter reads the notes db through its config; commit matters here
        conn = sqlite3.connect(str(self.db))
        conn.execute("UPDATE sources SET config = ? WHERE kind = 'notes'", (json.dumps({"path": str(notes_db)}),))
        conn.commit()
        conn.close()
        report = self.run_cli("index")["report"]["notes"]
        self.assertEqual(report["indexed"], 1)
        result = self.run_cli("search", "--query", "goreng")["results"]
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["kind"], "notes")
        self.assertEqual(result[0]["title"], "Ide resep")
        self.assertEqual(result[0]["provenance"]["ref"], note_id)
        self.assertEqual(result[0]["provenance"]["kind"], "notes")

        # deleting the note removes it from the context index on the next run
        subprocess.run([sys.executable, "-B", str(NOTES_PY), "--db", str(notes_db),
                        "delete", "--id", note_id], capture_output=True, text=True)
        report = self.run_cli("index")["report"]["notes"]
        self.assertEqual(report["removed"], 1)
        self.assertEqual(self.run_cli("search", "--query", "goreng")["results"], [])

    # ── Calendar source contract ──
    def test_calendar_contract(self):
        cal_db = self.tmp / "calendar.db"
        ev = subprocess.run([sys.executable, "-B", str(CAL_PY), "--db", str(cal_db), "new",
                             "--json", json.dumps({"title": "Rapat kunci", "location": "Ruang 4",
                                                   "start": "2026-11-02T10:00:00+07:00",
                                                   "end": "2026-11-02T11:00:00+07:00"})],
                            capture_output=True, text=True)
        event_id = json.loads(ev.stdout)["event"]["id"]
        self.run_cli("enable", "--kind", "calendar")
        conn = sqlite3.connect(str(self.db))
        conn.execute("UPDATE sources SET config = ? WHERE kind = 'calendar'",
                     (json.dumps({"path": str(cal_db)}),))
        conn.commit()
        conn.close()
        report = self.run_cli("index")["report"]["calendar"]
        self.assertEqual(report["indexed"], 1)
        result = self.run_cli("search", "--query", "rapat kunci")["results"]
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["kind"], "calendar")
        self.assertEqual(result[0]["title"], "Rapat kunci")
        self.assertEqual(result[0]["provenance"]["ref"], event_id)
        self.assertEqual(result[0]["provenance"]["kind"], "calendar")
        # the location lands in the indexed body; match it (snippet wraps matches in ⟦⟧)
        place = self.run_cli("search", "--query", "ruang")["results"]
        self.assertEqual(len(place), 1)
        self.assertIn("Ruang 4", place[0]["snippet"].replace("⟦", "").replace("⟧", ""))

    # ── Mail: contract only ──
    def test_mail_source_available(self):
        self.run_cli("enable", "--kind", "mail")
        row = [s for s in self.run_cli("sources")["sources"] if s["kind"] == "mail"][0]
        self.assertEqual(row["status"], "enabled")
        report = self.run_cli("index")["report"]["mail"]
        self.assertEqual(report["indexed"], 0)
        self.assertNotIn("skipped-source", report)

    # ── search behaviour ──
    def test_search_disabled_kind_excluded(self):
        (self.fixture / "a.txt").write_text("kata sandi biru\n")
        self.run_cli("enable", "--kind", "files")
        self.run_cli("configure", "--kind", "files", "--folders", str(self.fixture))
        self.run_cli("index")
        # enabled kind matches
        self.assertEqual(len(self.run_cli("search", "--query", "sandi")["results"]), 1)
        # searching a disabled kind returns nothing
        self.assertEqual(self.run_cli("search", "--query", "sandi", "--kind", "notes")["results"], [])

    def test_search_empty_query_fails(self):
        self.run_cli("search", "--query", "  ", expect_ok=False)

    def test_forget_clears_kind(self):
        (self.fixture / "a.txt").write_text("satu dua tiga\n")
        self.run_cli("enable", "--kind", "files")
        self.run_cli("configure", "--kind", "files", "--folders", str(self.fixture))
        self.run_cli("index")
        self.assertEqual(len(self.run_cli("search", "--query", "tiga")["results"]), 1)
        self.run_cli("forget", "--kind", "files")
        self.assertEqual(self.run_cli("search", "--query", "tiga")["results"], [])

    # ── contract document ──
    def test_contract_document(self):
        contract = self.run_cli("contract")["contract"]
        self.assertEqual(contract["version"], 1)
        self.assertIn("kind", contract["provenance"]["fields"])
        self.assertIn("indexer", contract["provenance"]["fields"])
        self.assertFalse(contract["controls"]["defaults"]["files"])
        for kind in ("files", "notes", "calendar", "mail"):
            self.assertIn(kind, contract["sources"])
        self.assertEqual(contract["sources"]["mail"]["status"], "available")
        self.assertIn("disabled sources are not indexed",
                      " ".join(contract["controls"]["rule"].split()).lower()
                      if isinstance(contract["controls"]["rule"], str) else "")

    # ── integration: settings UI wiring ──
    def test_luma_settings_wires_the_bridge(self):
        text = LUMA_SETTINGS.read_text()
        self.assertIn('shellPath("bin/context.py")', text)
        self.assertIn('"index"', text)
        self.assertIn('"enable"', text)
        self.assertIn('"disable"', text)
        self.assertIn('"configure"', text)
        self.assertIn('"sources"', text)
        shell = SHELL.read_text()
        # the shell must not need a new IPC target for A3 (settings pane owns it)
        self.assertNotIn('target: "context"', shell)


if __name__ == "__main__":
    unittest.main()
