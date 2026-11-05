"""Check Settings switches against the actual Launchpad reference and their settings API."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SHELL = Path(__file__).resolve().parents[1]


def component(source, name):
    start = source.index('    component ' + name + ':')
    opening = source.index('{', start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


class SettingsSwitchTests(unittest.TestCase):
    def test_launchpad_appearance_and_settings_interaction(self):
        actual = component((SHELL / 'MacDock.qml').read_text(), 'SSwitch')
        reference = component((SHELL.parent / 'launchpad/components/SettingsPanel.qml').read_text(), 'ToggleRow')
        reference = reference.replace('component ToggleRow:', 'component ReferenceToggleRow:')
        reference = reference.replace('Theme.fontFamily', 'root.fontFamily').replace('Theme.animationsEnabled', 'false')
        qml = '''import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import Quickshell
import "Common" as Corners
ShellRoot {
    Window {
        id: root
        visible: true; width: 340; height: 180
        property bool dark: true
        property bool reduceMotion: true
        property bool option: false
        property string fontFamily: "SF Pro Text"
        property color accent: "#0a84ff"
        property color ink: dark ? "white" : "black"
        ACTUAL
        REFERENCE
        QtObject { id: palette; property bool dark: root.dark; property color accent: root.accent }
        SSwitch {
            id: settings
            x: 20; y: 20; t: palette; checked: root.option
            onToggled: value => root.option = value
        }
        ReferenceToggleRow {
            id: launchpad
            x: 20; y: 90; width: 300; height: 27; label: "Launchpad"; checked: root.option
        }
        SignalSpy { id: changes; target: settings; signalName: "toggled" }
        TestCase {
            name: "SettingsSwitch"
            when: root.visible
            onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
            function cleanup() {
                console.log("RESULT", qtest_results.functionName, qtest_results.failed ? "FAIL" : "PASS");
                settings.enabled = true; root.option = false; changes.clear();
            }
            function test_01_matches_launchpad_pixels_in_both_themes_and_states() {
                for (const dark of [false, true]) {
                    root.dark = dark;
                    for (const checked of [false, true]) {
                        root.option = checked;
                        wait(30);
                        const reference = findChild(launchpad, "switch");
                        const actual = grabImage(settings);
                        const original = grabImage(launchpad);
                        compare(actual.width, reference.width);
                        compare(actual.height, reference.height);
                        for (let y = 0; y < actual.height; y++)
                            for (let x = 0; x < actual.width; x++)
                                compare(actual.pixel(x, y), original.pixel(x + reference.x, y + reference.y));
                    }
                }
            }
            function test_02_click_emits_boolean_and_keeps_external_state_binding() {
                mouseClick(settings, settings.width / 2, settings.height / 2);
                compare(root.option, true);
                compare(changes.count, 1);
                compare(changes.signalArguments[0][0], true);
                root.option = false;
                compare(findChild(settings, "settingsSwitchButton").checked, false);
                root.option = true;
                compare(findChild(settings, "settingsSwitchButton").checked, true);
                mouseClick(settings, settings.width / 2, settings.height / 2);
                compare(root.option, false);
                compare(changes.signalArguments[1][0], false);
            }
            function test_03_space_toggles_focused_switch() {
                findChild(settings, "settingsSwitchButton").forceActiveFocus();
                keyClick(Qt.Key_Space);
                compare(root.option, true);
                compare(changes.count, 1);
            }
            function test_04_disabled_switch_does_not_change_setting() {
                settings.enabled = false;
                mouseClick(settings, settings.width / 2, settings.height / 2);
                compare(root.option, false);
                compare(changes.count, 0);
            }
        }
    }
}
'''.replace('ACTUAL', actual).replace('REFERENCE', reference)
        with tempfile.TemporaryDirectory(prefix='macshell-settings-switch-') as directory:
            directory = Path(directory)
            (directory / 'Common').symlink_to(SHELL.parent / 'Common', target_is_directory=True)
            (directory / 'runtime').mkdir(mode=0o700)
            (directory / 'config/macshell').mkdir(parents=True)
            (directory / 'shell.qml').write_text(qml)
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       XDG_RUNTIME_DIR=str(directory / 'runtime'), XDG_CONFIG_HOME=str(directory / 'config'))
            env.pop('WAYLAND_DISPLAY', None)
            env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
            result = subprocess.run(['qs', '-p', str(directory), '--no-color'], env=env,
                                    capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('TOTALS 5 passed, 0 failed', output)
            for failure in ('FAIL!', 'TypeError', 'ReferenceError', 'WARN qml:', 'ERROR qml:'):
                self.assertNotIn(failure, output)


if __name__ == '__main__':
    unittest.main()
