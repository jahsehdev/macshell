"""Exercise the actual Typography picker and shared Settings dropdown in Qt Quick."""
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_settings_switch import SHELL, component


def typography_picker():
    source = (SHELL / 'MacDock.qml').read_text()
    start = source.rindex('SPopUp {', 0, source.index('id: typographyFont'))
    end, depth = start + len('SPopUp {'), 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def root_function(source, name):
    start = source.index('    function ' + name + '(')
    end, depth = source.index('{', start) + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


class TypographyFontsTests(unittest.TestCase):
    def test_font_discovery_search_selection_and_regular_dropdown(self):
        qml = '''import QtQuick
import QtQuick.Controls
import QtQml.Models
import QtTest
import Quickshell
import Quickshell.Io
import "Common" as Corners
ShellRoot {
    Window {
        id: root
        visible: true; width: 620; height: 430
        color: darkMode ? "#252529" : "#ededf0"
        property bool darkMode: false
        property string fontFamily: "SF Pro Display"
        property string fontStyleName: ""
        LOOK_FUNCTION
        SAVE_FUNCTION
        APPLY_FUNCTION
        SETTINGS_PROPERTIES
        QtObject {
            id: settingsStore
            property string saved: ""
            function setText(text) { saved = text; }
        }
        QtObject {
            id: bar
            property string fontFamily: "SF Pro Display"
            property string fontStyleName: ""
        }
        Text {
            id: sample
            x: 30; y: 20; text: "Typography preview"; color: pal.text
            font.family: root.fontFamily; font.styleName: root.fontStyleName; font.pixelSize: 16
        }
        QtObject {
            id: pal
            property bool dark: root.darkMode
            property string fam: root.fontFamily
            property string fontStyleName: root.fontStyleName
            property color accent: "#0a84ff"
            property color text: dark ? "#f5f5f7" : "#1d1d1f"
            property color text2: dark ? "#a0a0a5" : "#77777c"
            property color text3: dark ? "#66666b" : "#c3c3c8"
            property color hover: dark ? "#333336" : "#dedee2"
            property color card: dark ? "#363639" : "white"
            property color cardBorder: "transparent"
            property color sep: dark ? "#454549" : "#dedee2"
        }
        CARD
        ROW
        SCard {
            x: 30; y: 70; width: 560; t: pal
            SRow {
                t: pal; title: "Font"; subtitle: "Used for labels and menus"
                PICKER
            }
        }
        SPopUp {
            id: plain; x: 350; y: 330; t: pal
            model: ["First", "Second", "Third"]
            current: 1
            onPicked: i => current = i
        }
        SignalSpy { id: changes; target: typographyFont; signalName: "picked" }
        TestCase {
            name: "TypographyFonts"
            when: root.visible
            readonly property var popup: findChild(typographyFont, "settingsPopupMenu")
            readonly property var field: findChild(typographyFont, "settingsPopupSearch")
            readonly property var list: findChild(typographyFont, "settingsPopupResults")
            onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
            function open() {
                typographyFont.openMenu();
                tryCompare(popup, "opened", true);
                tryCompare(field, "activeFocus", true);
            }
            function cleanup() {
                console.log("RESULT", qtest_results.functionName, qtest_results.failed ? "FAIL" : "PASS");
                popup.close();
                findChild(plain, "settingsPopupMenu").close();
                wait(220);
                root.fontFamily = "SF Pro Display";
                root.fontStyleName = ""; changes.clear();
            }
            function optionIndex(family, style) { return typographyFont.model.indexOf(family + " " + style); }
            function currentLabel() { return root.fontFamily + " " + (root.fontStyleName || "Regular"); }
            function test_01_lists_all_installed_sf_faces_and_retains_selection() {
                tryVerify(() => typographyFont.fontFiles.length > 0);
                const installed = Qt.fontFamilies().filter(f => /^SF(?:\\s|$)/i.test(f)).sort();
                verify(installed.length >= 4);
                compare(typographyFont.sfFamilies, installed);
                for (const family of ["SF Mono", "SF Pro Display", "SF Pro Rounded", "SF Pro Text"])
                    verify(optionIndex(family, "Regular") >= 0, family);
                compare(typographyFont.model[typographyFont.current], "SF Pro Display Regular");
                const pairs = typographyFont.fontOptions.map(option => option.family + " " + option.style).sort();
                compare(pairs, EXPECTED_FACES);
            }
            function test_02_search_is_case_insensitive_and_enter_saves_original_family() {
                open(); field.text = "  rOuNdEd MeDiUm  ";
                tryCompare(list, "count", 1);
                compare(typographyFont.filteredIndices[0], optionIndex("SF Pro Rounded", "Medium"));
                keyClick(Qt.Key_Return);
                compare(root.fontFamily, "SF Pro Rounded");
                compare(root.fontStyleName, "Medium");
                compare(bar.fontFamily, "SF Pro Rounded");
                compare(bar.fontStyleName, "Medium");
                compare(changes.count, 1);
                compare(changes.signalArguments[0][0], optionIndex("SF Pro Rounded", "Medium"));
            }
            function test_03_mouse_selection_maps_filtered_index() {
                open(); field.text = "mono bold italic";
                tryCompare(list, "count", 1); wait(20);
                mouseClick(list, list.width / 2, 16);
                compare(root.fontFamily, "SF Mono");
                compare(root.fontStyleName, "Bold Italic");
                compare(changes.count, 1);
            }
            function test_04_no_results_then_reopen_resets_query_and_escape_dismisses() {
                open(); field.text = "unavailable font";
                tryCompare(list, "count", 0);
                keyClick(Qt.Key_Return);
                compare(changes.count, 0); compare(popup.visible, true);
                keyClick(Qt.Key_Escape);
                tryCompare(popup, "visible", false);
                open(); compare(field.text, "");
                compare(list.count, typographyFont.model.length);
                compare(typographyFont.model[typographyFont.filteredIndices[list.currentIndex]], currentLabel());
            }
            function test_05_arrow_navigation_and_system_fallback() {
                open(); field.text = "pro";
                tryCompare(list, "count", typographyFont.fontOptions.filter(option => option.family.includes("Pro")).length);
                keyClick(Qt.Key_Down);
                compare(list.currentIndex, 1);
                keyClick(Qt.Key_Up); compare(list.currentIndex, 0);
                field.text = "system";
                tryCompare(list, "count", 1);
                keyClick(Qt.Key_Return);
                compare(root.fontFamily, "sans-serif");
                compare(root.fontStyleName, "");
                compare(typographyFont.model[typographyFont.current], "System");
            }
            function test_06_regular_dropdown_keeps_indices_without_search() {
                plain.openMenu();
                const menu = findChild(plain, "settingsPopupMenu");
                const search = findChild(plain, "settingsPopupSearch");
                tryCompare(menu, "opened", true);
                compare(search.visible, false);
                compare(menu.height, 3 * 26 + 2 * menu.padding);
                keyClick(Qt.Key_Down); keyClick(Qt.Key_Return);
                compare(plain.current, 2);
            }
            function test_07_both_themes_fit_and_render() {
                for (const dark of [false, true]) {
                    root.darkMode = dark; open(); wait(50);
                    verify(popup.width >= 248);
                    verify(popup.height <= root.height - 16);
                    const snapshot = grabImage(root.contentItem);
                    snapshot.save("ARTIFACT/" + (dark ? "dark" : "light") + ".png");
                    popup.close(); wait(220);
                }
            }
            function test_08_long_searchable_list_scrolls_and_picks_correct_index() {
                plain.searchable = true;
                plain.model = Array.from({ length: 60 }, (_, i) => "SF Family " + i);
                plain.current = 58;
                plain.openMenu();
                const menu = findChild(plain, "settingsPopupMenu");
                const list = findChild(plain, "settingsPopupResults");
                const field = findChild(plain, "settingsPopupSearch");
                tryCompare(menu, "opened", true);
                verify(list.contentHeight > list.height);
                compare(list.currentIndex, 58);
                keyClick(Qt.Key_Down);
                compare(list.currentIndex, 59);
                verify(list.contentY > 0);
                keyClick(Qt.Key_Return);
                compare(plain.current, 59);
                plain.searchable = false;
            }
            function test_09_fontconfig_fills_list_when_qt_cache_contains_no_sf_fonts() {
                compare(typographyFont.qtFamilies.length, 0);
                compare(typographyFont.sfFamilies, ["SF Mono", "SF Pro Display", "SF Pro Rounded", "SF Pro Text"]);
                open();
                compare(list.count, typographyFont.fontOptions.length + 1);
                compare(typographyFont.model[typographyFont.current], "SF Pro Display Regular");
                const registry = findChild(typographyFont, "sfFontRegistry");
                compare(registry.count, typographyFont.fontFiles.length);
                for (let i = 0; i < registry.count; i++)
                    tryCompare(registry.objectAt(i), "status", FontLoader.Ready);
                field.text = "rounded medium";
                tryCompare(list, "count", 1);
                keyClick(Qt.Key_Return);
                compare(root.fontFamily, "SF Pro Rounded");
            }
            function test_10_selected_face_saves_loads_and_resets_to_regular() {
                const regular = grabImage(sample);
                open(); field.text = "display bold italic";
                tryCompare(list, "count", 1);
                keyClick(Qt.Key_Return);
                compare(root.fontFamily, "SF Pro Display");
                compare(root.fontStyleName, "Bold Italic");
                compare(sample.font.styleName, "Bold Italic");
                tryCompare(sample.fontInfo, "styleName", "Bold Italic");
                compare(sample.fontInfo.family, "SF Pro Display");
                wait(20);
                const styled = grabImage(sample);
                let changed = regular.width !== styled.width || regular.height !== styled.height;
                if (!changed)
                    for (let y = 0; y < styled.height && !changed; y++)
                        for (let x = 0; x < styled.width; x++)
                            if (regular.pixel(x, y) !== styled.pixel(x, y)) { changed = true; break; }
                verify(changed, "Selecting Bold Italic must change the rendered glyphs");
                grabImage(root.contentItem).save("ARTIFACT/bold-italic.png");
                root.saveSettings();
                const saved = JSON.parse(settingsStore.saved);
                compare(saved.fontFamily, "SF Pro Display");
                compare(saved.fontStyleName, "Bold Italic");
                root.fontFamily = "SF Mono"; root.fontStyleName = "Medium";
                root.applySettings(saved);
                compare(root.fontFamily, "SF Pro Display");
                compare(root.fontStyleName, "Bold Italic");
                compare(typographyFont.model[typographyFont.current], "SF Pro Display Bold Italic");
                open(); field.text = "display regular";
                tryCompare(list, "count", 2);
                keyClick(Qt.Key_Return);
                compare(root.fontStyleName, "Regular");
            }
        }
    }
}
'''
        # Reproduce a long-running shell whose Qt font snapshot predates SF installation.
        # Keep the actual Fontconfig scan, file registration and selection code intact.
        picker = typography_picker()
        snapshot = 'readonly property var qtFamilies: Qt.fontFamilies().filter(family => /^SF(?:\\s|$)/i.test(family))'
        self.assertIn(snapshot, picker)
        picker = picker.replace(snapshot, 'readonly property var qtFamilies: []', 1)
        qml = qml.replace('PICKER', picker)
        source = (SHELL / 'MacDock.qml').read_text()
        qml = qml.replace('CARD', component(source, 'SCard')).replace('ROW', component(source, 'SRow'))
        save = root_function(source, 'saveSettings')
        properties = sorted(set(re.findall(r'\b(\w+):', save)) - {'fontFamily', 'fontStyleName', 'darkMode'})
        qml = qml.replace('SETTINGS_PROPERTIES', '\n'.join('property var ' + key + ': null' for key in properties))
        qml = qml.replace('LOOK_FUNCTION', root_function(source, 'setLook'))
        qml = qml.replace('SAVE_FUNCTION', save).replace('APPLY_FUNCTION', root_function(source, 'applySettings'))
        fontconfig = subprocess.check_output(['fc-list', '--format', '%{family[0]}\t%{style[0]}\n'], text=True)
        faces = sorted(set(line.replace('\t', ' ') for line in fontconfig.splitlines() if re.match(r'^SF(?:\s|$)', line)))
        qml = qml.replace('EXPECTED_FACES', json.dumps(faces))
        with tempfile.TemporaryDirectory(prefix='macshell-typography-fonts-') as directory:
            directory = Path(directory)
            for name, target in [('Common', SHELL.parent / 'Common'), ('SPopUp.qml', SHELL / 'SPopUp.qml')]:
                (directory / name).symlink_to(target, target_is_directory=target.is_dir())
            (directory / 'runtime').mkdir(mode=0o700)
            (directory / 'config/macshell').mkdir(parents=True)
            artifacts = Path(os.environ.get('MACSHELL_TEST_ARTIFACTS', directory))
            artifacts.mkdir(parents=True, exist_ok=True)
            (directory / 'shell.qml').write_text(qml.replace('ARTIFACT', str(artifacts)))
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       XDG_RUNTIME_DIR=str(directory / 'runtime'), XDG_CONFIG_HOME=str(directory / 'config'))
            env.pop('WAYLAND_DISPLAY', None)
            env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
            result = subprocess.run(['qs', '-p', str(directory), '--no-color'], env=env,
                                    capture_output=True, text=True, timeout=25)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('TOTALS 11 passed, 0 failed', output, output)
            for failure in ('FAIL!', 'TypeError', 'ReferenceError', 'WARN qml:', 'ERROR qml:'):
                self.assertNotIn(failure, output)


if __name__ == '__main__':
    unittest.main()
