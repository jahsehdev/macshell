import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("sync_icon_style", Path(__file__).parents[1] / "sync_icon_style.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class NativeFolders(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config = self.home / ".config"
        self.data = self.home / ".local/share"
        self.source = self.data / "icons/TestTheme/places/scalable"
        self.source.mkdir(parents=True)
        self.svg = '<svg xmlns="http://www.w3.org/2000/svg"><path fill="#67b1de"/><path fill="#ffffff"/><path fill="#ff0000"/></svg>'
        (self.source / "folder.svg").write_text(self.svg)
        (self.source / "folder-documents.svg").symlink_to("folder.svg")
        (self.source / "red-folder.svg").write_text(self.svg)
        sync.ini_set(self.config / "gtk-3.0/settings.ini", "Settings", "gtk-icon-theme-name", "TestTheme")
        sync.ini_set(self.config / "gtk-3.0/settings.ini", "Settings", "gtk-theme-name", "KeepWindowTheme")
        sync.ini_set(self.config / "kdeglobals", "General", "font", r"SF Pro Text,10,\x42")

    def apply(self, color="#bf5af2", style="default", dark=False):
        return sync.apply(self.home, self.config, self.data, color, style, dark, notify=False)

    def test_native_toolkits_use_same_theme_without_replacing_other_preferences(self):
        state = self.apply()
        for path, section, key in [("gtk-3.0/settings.ini", "Settings", "gtk-icon-theme-name"),
                                   ("gtk-4.0/settings.ini", "Settings", "gtk-icon-theme-name"),
                                   ("qt6ct/qt6ct.conf", "Appearance", "icon_theme"),
                                   ("kdeglobals", "Icons", "Theme")]:
            self.assertEqual(sync.ini_get(self.config / path, section, key), state["theme"])
        self.assertEqual(sync.ini_get(self.config / "gtk-3.0/settings.ini", "Settings", "gtk-theme-name"), "KeepWindowTheme")
        self.assertIn(r"font=SF Pro Text,10,\x42", (self.config / "kdeglobals").read_text())

    def test_original_artwork_and_explicit_color_overrides_are_preserved(self):
        state = self.apply()
        self.assertEqual((self.source / "folder.svg").read_text(), self.svg)
        self.assertNotIn("red-folder", state["icons"])
        generated = Path(state["icons"]["folder"]).read_text()
        self.assertNotIn("#67b1de", generated)
        self.assertIn("#ffffff", generated)
        self.assertIn("#ff0000", generated)
        self.assertTrue(Path(state["icons"]["folder-documents"]).is_file())
        self.assertEqual(Path(state["icons"]["inode-directory"]).read_text(), generated)
        self.assertIn("Inherits=TestTheme,hicolor", (self.data / "icons" / state["theme"] / "index.theme").read_text())

    def test_switching_style_keeps_original_inheritance_and_cache_is_stable(self):
        original = self.apply()
        clear = self.apply(style="clear")
        self.assertNotEqual(original["theme"], clear["theme"])
        self.assertEqual(clear["baseTheme"], "TestTheme")
        ET.fromstring(Path(clear["icons"]["folder"]).read_text())
        restored = self.apply()
        self.assertEqual(restored["theme"], original["theme"])
        state = json.loads((self.config / "macshell/folders/native-state.json").read_text())
        self.assertEqual(state["theme"], original["theme"])

    def test_invalid_color_does_not_write_native_configuration(self):
        before = (self.config / "gtk-3.0/settings.ini").read_text()
        with self.assertRaises(ValueError):
            self.apply(color="../../bad")
        self.assertEqual((self.config / "gtk-3.0/settings.ini").read_text(), before)


if __name__ == "__main__":
    unittest.main()
