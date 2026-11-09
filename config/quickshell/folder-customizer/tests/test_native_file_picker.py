"""Run the actual QML chooser process and worker with a controlled GTK chooser."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]


class NativeFilePickerTests(unittest.TestCase):
    def test_native_selection_cancel_error_and_export(self):
        with tempfile.TemporaryDirectory(prefix='macshell-gtk-picker-') as directory:
            directory = Path(directory)
            (directory / 'Customizer').symlink_to(ROOT, target_is_directory=True)
            (directory / 'runtime').mkdir(mode=0o700)
            (directory / 'config').mkdir()
            (directory / 'bin').mkdir()
            folder = directory / 'Folder'
            folder.mkdir()
            exports = directory / 'Exports'
            exports.mkdir()
            # Preserve spaces, Unicode, newlines and shell metacharacters verbatim.
            mask = directory / 'mask 家族 $(literal)\n .png'
            image = Image.new('RGBA', (48, 48))
            ImageDraw.Draw(image).ellipse((8, 8, 40, 40), fill='black')
            image.save(mask)
            log = directory / 'picker-arguments.jsonl'
            chooser = directory / 'bin/zenity'
            chooser.write_text('''#!/usr/bin/python3
import json, os, sys, time
with open(os.environ['MACSHELL_PICKER_LOG'], 'a') as output:
    output.write(json.dumps(sys.argv[1:]) + '\\n')
response = json.loads(os.environ['MACSHELL_PICKER_RESULT'])
time.sleep(0.15)
if response.get('path'):
    sys.stdout.write(response['path'] + '\\n')
if response.get('error'):
    print(response['error'], file=sys.stderr)
sys.exit(response.get('code', 0))
''')
            chooser.chmod(0o755)
            metadata = directory / 'bin/gio'
            metadata.write_text('''#!/usr/bin/python3
import json, os, pathlib, sys
file = pathlib.Path(os.environ['XDG_DATA_HOME']) / 'test-gio.json'
value = json.loads(file.read_text()) if file.exists() else ''
if sys.argv[1] == 'info':
    if value: print('  metadata::custom-icon: ' + value)
else:
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(json.dumps('' if 'unset' in sys.argv else sys.argv[-1]))
''')
            metadata.chmod(0o755)
            qml = '''import QtQuick
import QtTest
import Quickshell
import "Customizer" as Custom
ShellRoot {
    Window {
        id: window
        visible: true; width: 460; height: 700
        Custom.FolderCustomizer {
            id: panel
            x: 20; y: 20
            folderPath: Quickshell.env("MACSHELL_CUSTOMIZE_FOLDER")
        }
        TestCase {
            id: tests
            name: "NativeFilePicker"
            when: window.visible
            readonly property var picker: findChild(panel, "nativeFolderFilePicker")
            onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
            function cleanup() { console.log("RESULT", qtest_results.functionName, qtest_results.failed ? "FAIL" : "PASS"); }
            function choose(result, mode) {
                picker.environment = { MACSHELL_PICKER_RESULT: JSON.stringify(result) };
                mouseClick(findChild(panel, mode === "directory" ? "exportFolderIconButton" : "importFolderMaskButton"));
                tryCompare(panel, "pickerBusy", true);
                verify(!findChild(panel, "importFolderMaskButton").enabled);
                verify(!findChild(panel, "engravedStyleButton").enabled);
                verify(!findChild(panel, "exportFolderIconButton").enabled);
                tryCompare(panel, "pickerBusy", false);
                tryCompare(panel, "busy", false, 10000);
            }
            function test_01_cancel_keeps_settings_and_preview() {
                tryCompare(panel, "ready", true, 5000);
                const settings = JSON.stringify(panel.settings());
                const icon = panel.iconUrl;
                choose({ code: 1 }, "mask");
                compare(JSON.stringify(panel.settings()), settings);
                compare(panel.iconUrl, icon);
                compare(panel.customized, false);
                compare(panel.error, "");
            }
            function test_02_selected_png_reaches_worker_without_path_changes() {
                choose({ path: Quickshell.env("MACSHELL_PICKER_MASK") }, "mask");
                compare(panel.maskValue.length, 64);
                compare(panel.artworkStyle, "engraved");
                compare(panel.customized, true);
                compare(panel.error, "");
                verify(panel.iconUrl.toString().includes("folder-icons"));
            }
            function test_03_picker_error_is_visible_and_keeps_custom_icon() {
                const icon = panel.iconUrl;
                const mask = panel.maskValue;
                choose({ code: 255, error: "GTK chooser unavailable" }, "mask");
                compare(panel.error, "GTK chooser unavailable");
                compare(panel.iconUrl, icon);
                compare(panel.maskValue, mask);
            }
            function test_04_export_uses_directory_mode() {
                const icon = panel.iconUrl;
                choose({ path: Quickshell.env("MACSHELL_PICKER_EXPORT") }, "directory");
                tryVerify(() => panel.exportNotice.includes(".iconset"), 10000);
                compare(panel.iconUrl, icon);
                compare(panel.error, "");
            }
        }
    }
}
'''
            (directory / 'shell.qml').write_text(qml)
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       XDG_RUNTIME_DIR=str(directory / 'runtime'), XDG_CONFIG_HOME=str(directory / 'config'),
                       XDG_DATA_HOME=str(directory / 'data'), PATH=str(directory / 'bin') + ':' + os.environ['PATH'],
                       MACSHELL_CUSTOMIZE_FOLDER=str(folder), MACSHELL_PICKER_MASK=str(mask),
                       MACSHELL_PICKER_EXPORT=str(exports), MACSHELL_PICKER_LOG=str(log))
            env.pop('WAYLAND_DISPLAY', None)
            env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
            result = subprocess.run(['qs', '-p', str(directory), '--no-color'], env=env,
                                    capture_output=True, text=True, timeout=35)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('TOTALS 5 passed, 0 failed', output, output)
            for failure in ('TypeError', 'ReferenceError', 'WARN qml:', 'ERROR qml:', 'FAIL!'):
                self.assertNotIn(failure, output)
            arguments = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(len(arguments), 4)
            for call in arguments[:3]:
                self.assertIn('--file-selection', call)
                self.assertIn('--file-filter=PNG masks | *.png *.PNG', call)
                self.assertNotIn('--directory', call)
            self.assertIn('--directory', arguments[-1])
            self.assertFalse(any(value.startswith('--file-filter') for value in arguments[-1]))
            iconsets = list(exports.glob('*.iconset'))
            self.assertEqual(len(iconsets), 1)
            self.assertEqual(len(list(iconsets[0].glob('*.png'))), 10)
            self.assertEqual(list(folder.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
