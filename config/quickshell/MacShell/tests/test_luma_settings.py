"""Render Luma Settings and exercise source controls through the real context CLI."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SHELL = Path(__file__).resolve().parents[1]

QML = r'''
import QtQuick
import QtTest
import Quickshell
ShellRoot {
    Window {
        id: window
        width: 640; height: 800; visible: true
        color: palette.dark ? "#252628" : "#ececee"
        QtObject {
            id: palette
            property bool dark: true
            property string fam: "SF Pro Text"
            property string fontStyleName: "Regular"
            property color accent: "#0a84ff"
            property color card: dark ? "#38393b" : "#ffffff"
            property color text: dark ? "#f5f5f7" : "#1d1d1f"
            property color text2: dark ? "#b6b7bb" : "#626267"
            property color sep: dark ? "#505153" : "#e3e3e6"
            property color track: dark ? "#555558" : "#dddddf"
            property color button: dark ? "#56575a" : "#ffffff"
            property color buttonPressed: dark ? "#66676a" : "#e4e4e7"
            property color buttonBorder: dark ? "#626367" : "#cccccf"
            property color danger: "#ff453a"
        }
        QtObject {
            id: controller
            property bool ready: false
            property bool loaded: false
            property bool runtimeReady: true
            property string busy: ""
            property string error: ""
            property string stage: "Installing model…"
            property real progress: 0.42
            property string selectedModel: "gemma-3-1b"
            property var catalog: [
                {id:"gemma-3-1b",name:"Gemma 3 1B",family:"Gemma 3",params:"1B",size:"815 MB",ram:"2 GB",installed:true,verified:true},
                {id:"gemma-3-4b",name:"Gemma 3 4B",family:"Gemma 3",params:"4B",size:"3.3 GB",ram:"6 GB",installed:false,verified:false}
            ]
            function refresh() {}
            function open(value) {}
            function send(value) {}
            function install(value) {}
            function importModel(model, path) {}
        }
        Flickable {
            anchors.fill: parent
            contentHeight: pane.height + 32
            clip: true
            Rectangle {
                id: canvas
                width: pane.width + 32; height: pane.height + 32
                color: window.color
                LumaSettings { id: pane; x: 16; y: 16; width: 576; t: palette; controller: controller; reduceMotion: true }
            }
        }
        TestCase {
            name: "LumaSettings"
            when: window.visible
            onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
            function cleanup() { console.log("RESULT", qtest_results.functionName, qtest_results.failed ? "FAIL" : "PASS"); }
            function row(kind) { return findChild(pane, "lumaSourceRow_" + kind); }
            function toggle(kind) { return findChild(pane, "lumaSourceSwitch_" + kind); }
            function checkLayout() {
                let previousBottom = 0;
                for (const kind of ["calendar", "files", "mail", "notes"]) {
                    const item=row(kind);
                    verify(item !== null);
                    verify(item.height >= 64);
                    verify(item.y >= previousBottom, kind + " overlaps previous row");
                    previousBottom=item.y+item.height;
                    const control=toggle(kind);
                    compare(control.width,58); compare(control.height,27);
                    verify(control.x+control.width<=item.width);
                    verify(control.y>=0 && control.y+control.height<=item.height);
                }
            }
            function test_01_rows_and_themes() {
                tryVerify(() => row("files") !== null, 3000);
                for (const dark of [true, false]) {
                    palette.dark=dark;
                    for (const width of [576, 400, 760]) {
                        pane.width=width; wait(40); checkLayout();
                    }
                }
                pane.width=576; palette.dark=true;
            }
            function test_02_toggle_refreshes_from_real_context_bridge() {
                const sw=toggle("files");
                compare(sw.checked,false);
                // Dispatch directly to the real control, independent of the viewport scroll.
                const button=findChild(sw,"settingsSwitchButton");
                button.forceActiveFocus(); keyClick(Qt.Key_Space);
                tryVerify(() => toggle("files").checked,3000);
                const input=findChild(pane,"lumaFoldersInput");
                tryCompare(input.parent,"visible",true,1000);
                verify(input.width>0 && input.height>=24);
                checkLayout();
                const currentButton=findChild(toggle("files"),"settingsSwitchButton");
                currentButton.forceActiveFocus(); keyClick(Qt.Key_Space);
                tryVerify(() => !toggle("files").checked,3000);
                tryCompare(input.parent,"visible",false,1000);
                compare(toggle("mail").enabled,false);
            }
            function test_03_render_representative_states() {
                // Show the folder field, confirmation actions and long status together.
                const button=findChild(toggle("files"),"settingsSwitchButton");
                button.forceActiveFocus(); keyClick(Qt.Key_Space);
                tryVerify(() => toggle("files").checked,3000);
                pane.removePending="gemma-3-1b"; pane.clearPending=true;
                controller.busy="install";
                for (const dark of [true,false]) {
                    palette.dark=dark;
                    for (const width of [576,400]) {
                        pane.width=width; window.width=width+32; wait(80);
                        checkLayout();
                        let saved=false;
                        canvas.grabToImage(result => { result.saveToFile("RENDER_DIR/luma-settings-"+(dark ? "dark" : "light")+"-"+width+".png"); saved=true; });
                        tryVerify(() => saved, 3000);
                    }
                }
            }
        }
    }
}
'''


class LumaSettingsTests(unittest.TestCase):
    def test_layout_and_source_controls(self):
        with tempfile.TemporaryDirectory(prefix="macshell-luma-settings-") as directory:
            directory = Path(directory)
            for name, target in {
                "Common": SHELL.parent / "Common",
                "LumaSettings.qml": SHELL / "LumaSettings.qml",
                "LumaSettingsText.qml": SHELL / "LumaSettingsText.qml",
                "LumaButton.qml": SHELL / "LumaButton.qml",
                "assets": SHELL / "assets",
                "bin": SHELL / "bin",
            }.items():
                (directory / name).symlink_to(target, target_is_directory=target.is_dir())
            (directory / "runtime").mkdir(mode=0o700)
            render_dir = Path(os.environ.get("MACSHELL_QA_RENDER_DIR", str(directory)))
            render_dir.mkdir(parents=True, exist_ok=True)
            (directory / "shell.qml").write_text(QML.replace("RENDER_DIR", render_dir.as_posix()))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_RUNTIME_DIR=str(directory / "runtime"),
                       XDG_CONFIG_HOME=str(directory / "config"), XDG_DATA_HOME=str(directory / "data"))
            env.pop("WAYLAND_DISPLAY", None)
            env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
            result = subprocess.run(["qs", "-p", str(directory), "--no-color"], env=env,
                                    capture_output=True, text=True, timeout=25)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("TOTALS 4 passed, 0 failed", output)
            for failure in ("FAIL!", "TypeError", "ReferenceError", "WARN scene:", "WARN qml:", "ERROR qml:"):
                self.assertNotIn(failure, output)


if __name__ == "__main__":
    unittest.main()
