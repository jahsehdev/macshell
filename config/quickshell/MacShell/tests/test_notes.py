"""Exercise the Notes storage CLI (bin/notes.py) against a temporary database."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

NOTES_PY = Path(__file__).resolve().parents[1] / "bin/notes.py"
APP = Path(__file__).resolve().parents[1] / "NotesApp.qml"
SHELL = Path(__file__).resolve().parents[1] / "shell.qml"

STROKE = {"tool": "pen", "color": "#ff0000", "width": 0.01,
          "points": [0.1, 0.1, 0.2, 0.3, 0.4, 0.2]}
RECT = {"tool": "rect", "color": "#007AFF", "width": 0.003, "points": [0.5, 0.1, 0.9, 0.5]}


class NotesCliTests(unittest.TestCase):
    def setUp(self):
        self.db = Path(tempfile.mkdtemp()) / "notes.db"

    def run_cli(self, *args, expect_ok=True):
        result = subprocess.run(
            [sys.executable, "-B", str(NOTES_PY), "--db", str(self.db)] + list(args),
            capture_output=True, text=True)
        payload = json.loads(result.stdout)
        if expect_ok:
            self.assertEqual(result.returncode, 0, payload)
            self.assertNotIn("error", payload)
        return payload, result.returncode

    def test_crud_roundtrip(self):
        note = self.run_cli("new")[0]["note"]
        self.assertEqual(note["strokes"], [])
        payload = {"id": note["id"], "title": "Ide resep", "body": "Nasi goreng\n- telur",
                   "strokes": [STROKE, RECT]}
        saved = self.run_cli("save", "--json", json.dumps(payload))[0]
        self.assertTrue(saved["ok"])
        loaded = self.run_cli("get", "--id", note["id"])[0]["note"]
        self.assertEqual(loaded["title"], "Ide resep")
        self.assertEqual(loaded["body"], "Nasi goreng\n- telur")
        self.assertEqual([s["tool"] for s in loaded["strokes"]], ["pen", "rect"])
        self.assertEqual(loaded["strokes"][0]["color"], "#ff0000")
        listing = self.run_cli("list")[0]["notes"]
        self.assertEqual(len(listing), 1)
        self.assertTrue(listing[0]["has_drawing"])
        self.assertEqual(listing[0]["title"], "Ide resep")
        self.run_cli("delete", "--id", note["id"])
        self.assertEqual(self.run_cli("list")[0]["notes"], [])
        self.run_cli("get", "--id", note["id"], expect_ok=False)

    def test_stroke_validation(self):
        note = self.run_cli("new")[0]["note"]
        bad = [
            {"tool": "spray", "color": "#ff0000", "width": 0.01, "points": [0, 0, 1, 1]},
            {"tool": "pen", "color": "red", "width": 0.01, "points": [0, 0, 1, 1]},
            {"tool": "pen", "color": "#ff0000", "width": 5, "points": [0, 0, 1, 1]},
            {"tool": "pen", "color": "#ff0000", "width": 0.01, "points": [2, 0, 3, 1]},
            {"tool": "pen", "color": "#ff0000", "width": 0.01, "points": [0.1, 0.1]},
            {"tool": "pen", "color": "#ff0000", "width": 0.01, "points": [0.1, 0.1, 0.2]},
            "not a dict",
        ]
        self.run_cli("save", "--json", json.dumps(
            {"id": note["id"], "title": "", "body": "", "strokes": bad + [STROKE]}))
        loaded = self.run_cli("get", "--id", note["id"])[0]["note"]
        self.assertEqual(loaded["strokes"], [STROKE])

    def test_search_filters(self):
        a = self.run_cli("new")[0]["note"]
        b = self.run_cli("new")[0]["note"]
        self.run_cli("save", "--json", json.dumps({"id": a["id"], "title": "Belajar QML", "body": "latihan"}))
        self.run_cli("save", "--json", json.dumps({"id": b["id"], "title": "Ide resep", "body": "nasi goreng"}))
        hits = self.run_cli("list", "--query", "resep")[0]["notes"]
        self.assertEqual([n["id"] for n in hits], [b["id"]])
        empty = self.run_cli("list", "--query", "zzz")[0]["notes"]
        self.assertEqual(empty, [])

    def test_exports(self):
        note = self.run_cli("new")[0]["note"]
        self.run_cli("save", "--json", json.dumps(
            {"id": note["id"], "title": "Rencana", "body": "baris satu", "strokes": [STROKE]}))
        directory = Path(tempfile.mkdtemp())
        # md
        out = directory / "rencana.md"
        self.run_cli("export", "--id", note["id"], "--out", str(out), "--format", "md")
        text = out.read_text()
        self.assertTrue(text.startswith("# Rencana\n"))
        self.assertIn("baris satu", text)
        self.assertIn("strokes", text)
        # txt
        out = directory / "rencana.txt"
        self.run_cli("export", "--id", note["id"], "--out", str(out), "--format", "txt")
        self.assertEqual(out.read_text(), "Rencana\n\nbaris satu\n")
        # svg (dependency-free renderer)
        out = directory / "rencana.svg"
        self.run_cli("export", "--id", note["id"], "--out", str(out), "--format", "svg")
        svg = out.read_text()
        self.assertIn("<svg", svg)
        self.assertIn('stroke="#ff0000"', svg)
        # png (needs Pillow; skipped with a message when unavailable)
        out = directory / "rencana.png"
        payload, _ = self.run_cli("export", "--id", note["id"], "--out", str(out), "--format", "png")
        try:
            import PIL  # noqa: F401
            have_pillow = True
        except ImportError:
            have_pillow = False
        if have_pillow:
            self.assertTrue(out.exists())
        else:
            self.assertIn("error", payload)
        # suffix mismatch is corrected
        out = directory / "rencana-wrong-ext.md"
        self.run_cli("export", "--id", note["id"], "--out", str(out), "--format", "txt")
        self.assertTrue(out.with_suffix(".txt").exists())
        # export into a missing directory creates it
        deep = directory / "sub" / "dir" / "note.md"
        self.run_cli("export", "--id", note["id"], "--out", str(deep), "--format", "md")
        self.assertTrue(deep.exists())

    def test_id_validation(self):
        self.run_cli("get", "--id", "../escape", expect_ok=False)
        self.run_cli("delete", "--id", "", expect_ok=False)
        self.run_cli("save", "--json", json.dumps({"id": "bad id!", "title": "x"}), expect_ok=False)

    def test_empty_body_falls_back_to_derived_title(self):
        note = self.run_cli("new")[0]["note"]
        self.run_cli("save", "--json", json.dumps({"id": note["id"], "title": "", "body": "pertama sekali"}))
        listing = self.run_cli("list")[0]["notes"]
        self.assertEqual(listing[0]["title"], "pertama sekali")


class NotesIntegrationTests(unittest.TestCase):
    """The QML side must stay wired to the CLI contract."""
    def test_app_uses_the_cli_and_db_path(self):
        source = APP.read_text()
        self.assertIn('Quickshell.shellPath("bin/notes.py")', source)
        self.assertIn("/.local/share/macshell/notes/notes.db", source)
        for cmd in ("list", "get", "new", "save", "delete", "export"):
            self.assertIn(f'"{cmd}"', source)
        self.assertNotIn('target: "notestest"', source)   # temp hook must stay removed

    def test_shell_registers_notes(self):
        source = SHELL.read_text()
        self.assertIn("NotesApp { id: notesApp", source)
        self.assertIn('target: "notes"', source)
        self.assertIn("notesApp.open()", source)
        self.assertIn("notesApp.newNote()", source)

    def test_launcher_and_desktop_entry(self):
        root = Path(__file__).resolve().parents[4]
        launcher = root / "bin/macshell-notes"
        self.assertTrue(launcher.exists())
        self.assertIn("ipc call notes open", launcher.read_text())
        desktop = root / "share/applications/macshell-notes.desktop"
        self.assertTrue(desktop.exists())
        self.assertIn("Exec=macshell-notes", desktop.read_text())
        self.assertTrue((root / "share/macshell/icons/notes.png").exists())
        self.assertTrue((root / "config/quickshell/MacShell/assets/notes.png").exists())


if __name__ == "__main__":
    unittest.main()
