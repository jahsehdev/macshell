import configparser
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("appearance", Path(__file__).parents[1] / "sync_appearance.py")
appearance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appearance)


class AppearanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="appearance-test-")
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name) / "user with spaces"
        self.config = self.home / ".config"
        self.data = self.home / ".local/share"
        for variant in ("Light", "Dark"):
            path = self.data / f"macshell/nautilus/themes/MacTahoe-{variant}/gtk-4.0/gtk.css"
            path.parent.mkdir(parents=True)
            path.write_text("/* fixture */")

    def test_mode_and_auto_resolution(self):
        self.assertEqual(appearance.resolved_mode({"appearanceMode": "light", "darkMode": True}), "light")
        self.assertEqual(appearance.resolved_mode({"appearanceMode": "dark", "darkMode": False}), "dark")
        self.assertEqual(appearance.resolved_mode({"appearanceMode": "auto", "darkMode": False}, 22), "light")
        self.assertEqual(appearance.resolved_mode({"appearanceMode": "auto", "darkMode": True}, 10), "dark")
        for hour, expected in ((6, "dark"), (7, "light"), (18, "light"), (19, "dark")):
            self.assertEqual(appearance.resolved_mode({}, hour), expected)

    def test_switching_preserves_user_settings_and_loads_both_variants(self):
        path = self.config / "gtk-4.0/settings.ini"
        path.parent.mkdir(parents=True)
        path.write_text("[Settings]\ngtk-icon-theme-name=MyIcons\ngtk-font-name=SF Pro Text 10\ngtk-decoration-layout=close,minimize,maximize:\n")
        for mode, theme, scheme in (("light", "MacTahoe-Light", "3"), ("dark", "MacTahoe-Dark", "2"), ("light", "MacTahoe-Light", "3")):
            appearance.sync_files(self.home, self.config, self.data, mode)
            parser = configparser.ConfigParser()
            parser.read(path)
            self.assertEqual(parser["Settings"]["gtk-theme-name"], theme)
            self.assertEqual(parser["Settings"]["gtk-interface-color-scheme"], scheme)
            self.assertEqual(parser["Settings"]["gtk-icon-theme-name"], "MyIcons")
            self.assertEqual(parser["Settings"]["gtk-font-name"], "SF Pro Text 10")
            self.assertEqual(parser["Settings"]["gtk-decoration-layout"], "close,minimize,maximize:")
        dynamic = (self.config / "macshell/appearance/theme.css").read_text()
        self.assertIn("prefers-color-scheme: light", dynamic)
        self.assertIn("prefers-color-scheme: dark", dynamic)
        self.assertIn("%20", dynamic)
        self.assertIn("--window-bg-color: @window_bg_color", dynamic)
        imports = self.config / "macshell/nautilus"
        self.assertEqual((imports / "theme-import.css").read_text(), (imports / "dark-import.css").read_text())
        before = (self.config / "macshell/appearance/theme.css").stat().st_mtime_ns
        appearance.sync_files(self.home, self.config, self.data, "light")
        self.assertEqual((self.config / "macshell/appearance/theme.css").stat().st_mtime_ns, before)

    def test_missing_variant_stops_before_writing(self):
        (self.data / "macshell/nautilus/themes/MacTahoe-Dark/gtk-4.0/gtk.css").unlink()
        with self.assertRaises(RuntimeError):
            appearance.sync_files(self.home, self.config, self.data, "light")
        self.assertFalse(self.config.exists())

    def test_gnome_preferences_follow_mode_and_original_values_are_saved(self):
        values = {
            ("org.gnome.desktop.interface", "gtk-theme"): "'MacTahoe-Dark'",
            ("org.gnome.desktop.interface", "color-scheme"): "'prefer-dark'",
            ("org.gnome.Console", "theme"): "'night'",
            ("org.gnome.TextEditor", "style-variant"): "'dark'",
        }
        original = values.copy()
        calls = []
        def gsettings(command, **kwargs):
            calls.append(command)
            if command[1] == "list-schemas":
                return "\n".join(set(schema for schema, _ in values))
            key = tuple(command[2:4])
            if command[1] == "set":
                values[key] = command[4]
                return ""
            return values[key]
        with patch.object(subprocess, "check_output", side_effect=gsettings):
            appearance.sync_gsettings(self.config, "light")
            self.assertEqual(values[("org.gnome.desktop.interface", "color-scheme")], "'prefer-light'")
            self.assertEqual(values[("org.gnome.Console", "theme")], "'auto'")
            self.assertEqual(values[("org.gnome.TextEditor", "style-variant")], "'follow'")
            count = sum(command[1] == "set" for command in calls)
            appearance.sync_gsettings(self.config, "light")
            self.assertEqual(sum(command[1] == "set" for command in calls), count)
            appearance.sync_gsettings(self.config, "dark")
            self.assertEqual(values[("org.gnome.desktop.interface", "color-scheme")], "'prefer-dark'")
        snapshot = json.loads((self.config / "macshell/appearance/previous-gsettings.json").read_text())
        self.assertEqual(snapshot, {" ".join(key): value for key, value in original.items()})

    def test_backend_that_does_not_retain_changes_is_reported(self):
        def gsettings(command, **kwargs):
            return "org.gnome.desktop.interface" if command[1] == "list-schemas" else "'MacTahoe-Dark'"
        with patch.object(subprocess, "check_output", side_effect=gsettings):
            with self.assertRaises(RuntimeError):
                appearance.sync_gsettings(self.config, "light")


if __name__ == "__main__":
    unittest.main()
