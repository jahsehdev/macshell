"""Wiring tests for personal-context results in Search or Ask (A3/GG-04).

The Luma search menu queries bin/context.py while the user types and shows
local matches (notes, calendar events, fixture-folder files) with the
provenance recorded at index time. These tests pin the QML wiring and the
CLI result shape the panel renders.
"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
MENU = SHELL / "LumaSearchMenu.qml"
VIEW = SHELL / "LumaSearchView.qml"
PANEL = SHELL / "LumaSearchPanel.qml"
CTX = SHELL / "bin" / "context.py"


class ContextSearchWiringTests(unittest.TestCase):
    def test_menu_queries_the_context_bridge(self):
        menu = MENU.read_text()
        self.assertIn('Quickshell.shellPath("bin/context.py")', menu)
        self.assertIn('"search"', menu)
        self.assertIn('"--query"', menu)
        self.assertIn('"--limit", "5"', menu)
        # typing is debounced, not a process per keystroke
        self.assertIn("id: debounce", menu)
        self.assertIn("interval: 250", menu)

    def test_menu_discards_stale_results(self):
        menu = MENU.read_text()
        # a late answer for an older draft must not be shown
        self.assertIn("parsed.query !== root.controller.draft.trim()", menu)
        # a search issued while the bridge process is busy is rerun, not dropped
        self.assertIn("pendingRun", menu)

    def test_menu_activates_results(self):
        menu = MENU.read_text()
        self.assertIn('contextResults: contextSearch.results', menu)
        self.assertIn('contextSearching: contextSearch.searching', menu)
        self.assertIn('onContextResultActivated', menu)
        self.assertIn('"notes", "open"', menu)
        self.assertIn('"calendar", "open"', menu)
        self.assertIn('"mail", "open"', menu)
        self.assertIn('"xdg-open"', menu)

    def test_view_forwards_context_to_panel(self):
        view = VIEW.read_text()
        self.assertIn("property var contextResults", view)
        self.assertIn("property bool contextSearching", view)
        self.assertIn("signal contextResultActivated", view)
        self.assertIn("localResults: root.contextResults", view)
        self.assertIn("localSearching: root.contextSearching", view)
        self.assertIn("onLocalResultActivated", view)

    def test_panel_renders_rows_with_provenance(self):
        panel = PANEL.read_text()
        self.assertIn("readonly property bool showLocal", panel)
        self.assertIn("Repeater", panel)
        # kind chip, highlighted snippet, provenance line
        self.assertIn("kindLabel", panel)
        self.assertIn("MarkdownText", panel)
        self.assertIn("sourceLabel", panel)
        # activation and keyboard selection
        self.assertIn("localResultActivated", panel)
        self.assertIn("Keys.onDownPressed", panel)
        self.assertIn("Keys.onUpPressed", panel)
        self.assertIn("localSelected >= 0", panel)

    def test_search_results_show_even_without_a_model(self):
        # submit() opens a selected local result before any readiness check,
        # so results work while no Luma model is installed.
        panel = PANEL.read_text()
        submit = panel[panel.index("function submit()"):]
        self.assertLess(submit.index("localResultActivated"), submit.index("controller.ready"))


class ContextSearchCliShapeTests(unittest.TestCase):
    """The panel consumes {kind, ref, title, modified, provenance, snippet}."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        cls.fixture = cls.tmp / "fixture"
        cls.fixture.mkdir()
        (cls.fixture / "catatan.txt").write_text("nasi goreng resep luma\n")
        cls.db = cls.tmp / "context.db"

        def cli(*args):
            return subprocess.run([sys.executable, "-B", str(CTX), "--db", str(cls.db)] + list(args),
                                  capture_output=True, text=True, timeout=30)

        cli("enable", "--kind", "files")
        cli("configure", "--kind", "files", "--folders", str(cls.fixture))
        cli("index")
        cls.result = json.loads(cli("search", "--query", "goreng", "--limit", "5").stdout)

    def test_search_returns_the_shape_the_panel_renders(self):
        results = self.result["results"]
        self.assertEqual(len(results), 1)
        row = results[0]
        for key in ("kind", "ref", "title", "modified", "provenance", "snippet"):
            self.assertIn(key, row)
        for key in ("kind", "ref", "origin", "modified", "indexed_at", "indexer"):
            self.assertIn(key, row["provenance"])
        self.assertEqual(row["kind"], "files")
        self.assertEqual(row["provenance"]["ref"], row["ref"])

    def test_search_respects_limit(self):
        self.assertEqual(self.result["kinds"], ["files"])
        self.assertLessEqual(len(self.result["results"]), 5)


if __name__ == "__main__":
    unittest.main()
