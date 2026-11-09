"""Verify native font selection, toolkit decoding and Fontconfig matching."""
import configparser
import ctypes
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


HELPER = Path(__file__).resolve().parents[1] / "sync_fonts.py"
spec = importlib.util.spec_from_file_location("sync_fonts", HELPER)
fonts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fonts)


class NativeFontTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="macshell-native-fonts-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.config = self.root / "config"
        self.state = self.root / "state"
        self.font = fonts.resolve_font("SF Pro Rounded", "Semibold")

    def test_saved_selection_and_regular_legacy_settings(self):
        path = self.config / "macdock/settings.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"fontFamily": "SF Pro Rounded", "fontStyleName": "Semibold"}))
        self.assertEqual(fonts.selected_font(self.config), ("SF Pro Rounded", "Semibold"))
        path.write_text(json.dumps({"fontFamily": "SF Pro Display"}))
        self.assertEqual(fonts.selected_font(self.config), ("SF Pro Display", "Regular"))
        self.assertEqual(fonts.resolve_font("sans-serif", "Regular")["style"], "Regular")
        with self.assertRaises(ValueError):
            fonts.resolve_font("SF Missing", "Semibold")

    def test_ini_changes_keep_theme_icons_fixed_font_and_backup_original(self):
        gtk = self.config / "gtk-4.0/settings.ini"
        gtk.parent.mkdir(parents=True)
        original = "[Settings]\ngtk-theme-name=MacTahoe-Dark\ngtk-icon-theme-name=CustomFolders\ngtk-font-name=SF Pro Text 10\n"
        gtk.write_text(original)
        qt = self.config / "qt6ct/qt6ct.conf"
        qt.parent.mkdir(parents=True)
        qt.write_text('[Appearance]\nstyle=Kvantum\nicon_theme=CustomFolders\n[Fonts]\nfixed=custom-fixed\n')
        updated = fonts.sync_files(self.config, self.state, self.font)
        settings = configparser.ConfigParser()
        settings.read(gtk)
        self.assertEqual(settings["Settings"]["gtk-font-name"], "SF Pro Rounded Semibold 10")
        self.assertEqual(settings["Settings"]["gtk-theme-name"], "MacTahoe-Dark")
        self.assertEqual(settings["Settings"]["gtk-icon-theme-name"], "CustomFolders")
        settings.read(qt)
        self.assertEqual(settings["Appearance"]["style"], "Kvantum")
        self.assertEqual(settings["Fonts"]["fixed"], "custom-fixed")
        record = next(record for record in updated.records if record["path"] == str(gtk))
        self.assertEqual(Path(record["original"]).read_text(), original)
        self.assertFalse(fonts.sync_files(self.config, self.state, self.font).records)
        regular = fonts.resolve_font("SF Pro Rounded", "Regular")
        fonts.sync_files(self.config, self.state, regular)
        settings.read(gtk)
        self.assertEqual(settings["Settings"]["gtk-font-name"], "SF Pro Rounded Regular 10")

    def test_pango_decodes_family_weight_and_italic(self):
        pango = ctypes.CDLL("libpango-1.0.so.0")
        pango.pango_font_description_from_string.argtypes = [ctypes.c_char_p]
        pango.pango_font_description_from_string.restype = ctypes.c_void_p
        for name in ("family", "weight", "style"):
            function = getattr(pango, "pango_font_description_get_" + name)
            function.argtypes = [ctypes.c_void_p]
            function.restype = ctypes.c_char_p if name == "family" else ctypes.c_int
        pango.pango_font_description_free.argtypes = [ctypes.c_void_p]
        for family, style, weight, italic in [("SF Pro Rounded", "Semibold", 600, False),
                                               ("SF Pro Text", "Bold Italic", 700, True),
                                               ("SF Pro Text", "Regular", 400, False)]:
            font = fonts.resolve_font(family, style)
            description = pango.pango_font_description_from_string(fonts.pango_font(font, 10).encode())
            self.assertEqual(pango.pango_font_description_get_family(description).decode(), family)
            self.assertEqual(pango.pango_font_description_get_weight(description), weight)
            self.assertEqual(pango.pango_font_description_get_style(description) != 0, italic)
            pango.pango_font_description_free(description)

    def test_fontconfig_follows_selected_face_and_keeps_mono_and_emoji(self):
        fonts.sync_files(self.config, self.state, self.font)
        rules = self.config / "fontconfig/conf.d/99-sf-defaults.conf"
        config = self.root / "fonts.conf"
        config.write_text('<fontconfig><include>/etc/fonts/fonts.conf</include><include>' + str(rules) + '</include></fontconfig>')
        env = dict(os.environ, FONTCONFIG_FILE=str(config))
        def match(pattern):
            result = subprocess.run(["fc-match", "--format", "%{family[0]}\t%{style[0]}", pattern],
                                    capture_output=True, text=True, check=True, env=env)
            self.assertFalse(result.stderr)
            return result.stdout.split("\t")
        for pattern in ("sans-serif", "system-ui", "SF Pro Rounded:style=Regular", "SF Pro Rounded:weight=180"):
            self.assertEqual(match(pattern), ["SF Pro Rounded", "Semibold"])
        self.assertEqual(match("monospace")[0], "SF Mono")
        self.assertIn("Emoji", match("emoji")[0])
        fonts.sync_files(self.config, self.state, fonts.resolve_font("SF Pro Text", "Bold Italic"))
        self.assertEqual(match("sans-serif"), ["SF Pro Text", "Bold Italic"])
        fonts.sync_files(self.config, self.state, fonts.resolve_font("SF Pro Text", "Regular"))
        self.assertEqual(match("sans-serif"), ["SF Pro Text", "Regular"])

    def test_session_updates_include_style_and_report_failed_live_update(self):
        stored = {}
        def run(args):
            if args[1] == "list-schemas":
                stdout = "org.gnome.desktop.interface\norg.gnome.desktop.wm.preferences"
            elif args[1] == "list-keys":
                stdout = "font-name\ndocument-font-name\nmonospace-font-name\ntitlebar-font"
            elif args[1] == "get":
                stdout = repr(stored.get(tuple(args[2:4]), "Old Regular 10"))
            else:
                stored[tuple(args[2:4])] = args[4]
                stdout = ""
            return subprocess.CompletedProcess(args, 0, stdout, "")
        with patch.object(fonts, "run", side_effect=run):
            fonts.sync_session(self.state, self.font)
        self.assertEqual(stored[("org.gnome.desktop.interface", "font-name")], "SF Pro Rounded Semibold 10")
        self.assertEqual(stored[("org.gnome.desktop.interface", "monospace-font-name")], "SF Mono 11")
        self.assertTrue((self.state / "macshell/fonts/gsettings-before.json").is_file())
        with patch.object(fonts, "run", side_effect=lambda args: subprocess.CompletedProcess(args, 0,
                           run(args).stdout, "failed to commit changes" if args[1] == "set" else "")):
            stored.clear()
            with self.assertRaises(RuntimeError):
                fonts.sync_session(self.state, self.font)

    def test_qt6ct_font_decodes_in_real_qt_application(self):
        source = self.root / "probe.cpp"
        source.write_text('''#include <QApplication>
#include <QSettings>
#include <QFontInfo>
#include <iostream>
int main(int argc, char **argv) {
    QApplication app(argc, argv);
    QSettings settings(argv[1], QSettings::IniFormat);
    QFont saved = settings.value("Fonts/general").value<QFont>();
    QFont active = app.font();
    QFontInfo actual(active);
    std::cout << actual.family().toStdString() << " | " << actual.styleName().toStdString() << std::endl;
    return saved.family() == "SF Pro Rounded" && saved.styleName() == "Semibold" && saved.weight() == 600
        && active.family() == saved.family() && actual.styleName() == "Semibold" ? 0 : 1;
}''')
        flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "Qt6Widgets"], text=True).split()
        binary = self.root / "probe"
        subprocess.run(["c++", "-fPIC", str(source), "-o", str(binary), *flags], check=True, capture_output=True)
        fonts.sync_files(self.config, self.state, self.font)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="qt6ct", XDG_CONFIG_HOME=str(self.config))
        result = subprocess.run([str(binary), str(self.config / "qt6ct/qt6ct.conf")], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SF Pro Rounded | Semibold", result.stdout)


if __name__ == "__main__":
    unittest.main()
