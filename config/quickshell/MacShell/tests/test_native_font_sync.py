"""Ensure the live Dock starts native font synchronization at load and on style changes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SHELL = Path(__file__).resolve().parents[1]


class NativeFontSyncTests(unittest.TestCase):
    def test_startup_style_changes_and_fast_family_style_selection(self):
        source = (SHELL / "MacDock.qml").read_text()
        start = source.index('    onFontFamilyChanged:')
        end = source.index('    property bool magnificationEnabled:', start)
        integration = source[start:end]
        with tempfile.TemporaryDirectory(prefix="macshell-native-font-sync-") as directory:
            directory = Path(directory)
            config = directory / "config"
            helper = config / "quickshell/Common/sync_fonts.py"
            helper.parent.mkdir(parents=True)
            calls = directory / "calls.jsonl"
            helper.write_text('import json, sys\nwith open(' + repr(str(calls)) + ', "a") as output:\n'
                              '    output.write(json.dumps(sys.argv[1:]) + "\\n")\n')
            (directory / "runtime").mkdir(mode=0o700)
            qml = '''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
ShellRoot {
    Window {
        id: root
        visible: true; width: 100; height: 100
        property bool settingsReady: false
        property string fontFamily: "SF Pro Rounded"
        property string fontStyleName: "Semibold"
        INTEGRATION
        TestCase {
            name: "NativeFontSync"
            when: root.visible
            onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
            function test_selection() {
                compare(nativeFontDelay.running, false);
                root.settingsReady = true;
                tryCompare(nativeFontDelay, "running", false, 2000);
                wait(200);
                root.fontStyleName = "Medium";
                root.fontFamily = "SF Pro Text";
                root.fontStyleName = "Bold Italic";
                wait(600);
                compare(nativeFontDelay.running, false);
                compare(nativeFontSync.running, false);
                root.fontStyleName = "Regular";
                wait(600);
            }
        }
    }
}
'''.replace('INTEGRATION', integration)
            (directory / "shell.qml").write_text(qml)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_RUNTIME_DIR=str(directory / "runtime"), XDG_CONFIG_HOME=str(config))
            env.pop("WAYLAND_DISPLAY", None)
            result = subprocess.run(["qs", "-p", str(directory), "--no-color"], env=env,
                                    capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("TOTALS 2 passed, 0 failed", output)
            actual = [json.loads(line) for line in calls.read_text().splitlines()]
            self.assertEqual(actual, [["--family", "SF Pro Rounded", "--style", "Semibold"],
                                      ["--family", "SF Pro Text", "--style", "Bold Italic"],
                                      ["--family", "SF Pro Text", "--style", "Regular"]])


if __name__ == "__main__":
    unittest.main()
