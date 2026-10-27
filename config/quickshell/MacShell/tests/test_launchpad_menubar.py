"""Render the actual menubar strip in an isolated Quickshell/Qt test window."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from PIL import Image


SHELL = Path(__file__).resolve().parents[1]
SOURCE = SHELL / "UpstreamBar/MacBar.qml"


def qml_block(source, identifier):
    marker = source.index("id: " + identifier + "\n")
    start = source.rfind("\n", 0, source.rfind("{", 0, marker)) + 1
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


class LaunchpadMenubarTests(unittest.TestCase):
    def test_render_and_lifecycle(self):
        source = SOURCE.read_text()
        strip = qml_block(source, "launchpadBarBackground")
        palette = qml_block(source, "bpal")
        layer = re.search(r"WlrLayershell.layer: ([^\n]+)",
                          source[source.index('WlrLayershell.namespace: "macbar"'):])[1]
        coverage = re.search(r"readonly property bool launchpadCovered: ([^\n]+)", source)[1]
        host_visible = re.search(r"visible: ([^\n]+)", qml_block(source, "barBgWin"))[1]
        normal_visible = re.search(r"visible: ([^\n]+)", qml_block(source, "normalBarTint"))[1]
        with tempfile.TemporaryDirectory(prefix="launchpad-menubar-test-") as temporary:
            task_root = Path(temporary)
            runtime = task_root / "runtime"
            runtime.mkdir(mode=0o700)
            common = task_root / "Common"
            common.mkdir()
            for name in ("LaunchpadBackground.qml", "LaunchpadGlassState.qml"):
                shutil.copy2(SHELL.parent / "Common" / name, common / name)
            (common / "qmldir").write_text(
                "singleton LaunchpadGlassState 1.0 LaunchpadGlassState.qml\n"
                "LaunchpadBackground 1.0 LaunchpadBackground.qml\n")
            wallpaper = task_root / "wallpaper.png"
            image = Image.new("RGB", (320, 200), "#b9c8dd")
            for x in range(0, 320, 20):
                image.paste("#193b24", (x, 0, x + 10, 200))
            image.save(wallpaper)
            qml = r'''
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Wayland
import "COMMON" as GlassCommon
ShellRoot {
    // Exercise the production visibility binding on a real window. A normal
    // Qt window works offscreen; the Wayland host must retain this mapping.
    Window {
        id: normalBackgroundHost
        width: 320; height: 28
        visible: HOST_VISIBLE
    }
    Window {
        id: root
        visible: true
        width: 640; height: 200
        color: "#00ff00"
        property bool barEnabled: true
        property real barBgOpacity: 0
        property bool darkMode: false
        property string fontFamily: "sans-serif"
        property color accent: "#007aff"
        Item {
            id: perScreen
            property var modelData: ({name: "TEST-1", width: 320, height: 200})
            readonly property bool launchpadCovered: COVERAGE
            PALETTE
            Item {
                id: ui
                property bool anyVisible: false
                readonly property int hostLayer: LAYER
                readonly property bool normalBackgroundVisible: NORMAL_VISIBLE
                Item {
                    id: barBg
                    width: 320; height: 28
                    visible: root.barEnabled
                    STRIP
                }
            }
        }
        GlassCommon.LaunchpadBackground {
            id: reference
            x: 320; width: 320; height: 200
            screenName: "TEST-1"
        }
        TestCase {
            id: tests
            name: "LaunchpadMenubar"
            when: root.visible
            onCompletedChanged: if (completed)
                console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
            SignalSpy {
                id: backgroundMapping
                target: normalBackgroundHost
                signalName: "visibleChanged"
            }
            function preferences(dimming) {
                GlassCommon.LaunchpadGlassState.preferences = {
                    backgroundType: "custom", customImage: WALLPAPER,
                    backgroundBlur: 0.5, backgroundOpacity: dimming
                };
            }
            function activity(active, screen) {
                GlassCommon.LaunchpadGlassState.activity = {
                    active: active, screen: screen || "TEST-1", updated: Date.now()
                };
                GlassCommon.LaunchpadGlassState.now = Date.now();
            }
            function initTestCase() {
                wait(200);
                preferences(0.55);
                tryVerify(() => launchpadBarScene.cachedSource.toString() !== "", 5000);
                tryVerify(() => reference.cachedSource.toString() !== "", 5000);
                wait(100);
            }
            function init() {
                root.barEnabled = true;
                root.barBgOpacity = 0;
                root.darkMode = false;
                ui.anyVisible = false;
                preferences(0.55);
                activity(false);
                wait(1);
            }
            function test_backgroundMatchesLaunchpadAndStaysClipped() {
                activity(true);
                wait(30);
                const rendered = grabImage(root.contentItem);
                for (let x = 0; x < 320; x += 17)
                    for (let y = 0; y < 28; y += 5)
                        compare(rendered.pixel(x, y), rendered.pixel(x + 320, y));
                compare(rendered.pixel(10, 29), Qt.color("#00ff00"));
                compare(rendered.pixel(10, 190), Qt.color("#00ff00"));
            }
            function test_repeatedOpenCloseKeepsPreparedBlurAndLayer() {
                const prepared = launchpadBarScene;
                const cached = prepared.cachedSource;
                for (let i = 0; i < 20; ++i) {
                    activity(true);
                    compare(launchpadBarBackground.visible, true);
                    compare(ui.hostLayer, WlrLayer.Top);
                    compare(launchpadBarScene, prepared);
                    compare(launchpadBarScene.cachedSource, cached);
                    wait(10);
                    const rendered = grabImage(root.contentItem);
                    compare(rendered.pixel(10, 10), rendered.pixel(330, 10));
                    activity(false);
                    compare(launchpadBarBackground.visible, false);
                    compare(ui.hostLayer, WlrLayer.Top);
                    wait(10);
                }
            }
            function test_zeroOpacityStillHasLaunchpadBackground() {
                activity(true);
                compare(launchpadBarBackground.visible, true);
                compare(ui.normalBackgroundVisible, false);
                wait(30);
                const rendered = grabImage(root.contentItem);
                verify(rendered.pixel(10, 10) !== Qt.color("#00ff00"));
            }
            function test_normalBackgroundStaysBelowLaunchpad() {
                root.barBgOpacity = 0.1;
                compare(ui.normalBackgroundVisible, true);
                activity(true);
                compare(ui.normalBackgroundVisible, true);
                activity(false);
                compare(ui.normalBackgroundVisible, true);
            }
            function test_backgroundMappingSurvivesOpenClose() {
                root.barBgOpacity = 0.1;
                wait(10);
                backgroundMapping.clear();
                for (let i = 0; i < 20; ++i) {
                    activity(true);
                    wait(10);
                    compare(normalBackgroundHost.visible, true,
                        "Keep the backdrop mapped below the text while Launchpad is open");
                    activity(false);
                    wait(10);
                    compare(normalBackgroundHost.visible, true);
                }
                compare(backgroundMapping.count, 0,
                    "Remapping the Top-layer backdrop after close can cover and blur the text");
            }
            function test_backgroundMappingSurvivesAppearanceChanges() {
                backgroundMapping.clear();
                root.barBgOpacity = 0.1;
                root.barEnabled = false;
                wait(10);
                root.barEnabled = true;
                root.barBgOpacity = 0;
                wait(10);
                root.barBgOpacity = 0.1;
                wait(10);
                compare(normalBackgroundHost.visible, true);
                compare(backgroundMapping.count, 0);
            }
            function test_textAndLogoPaletteFollowsDimmedMonitor() {
                activity(true);
                compare(bpal.dark, true);
                compare(bpal.fg, Qt.color("#ffffff"));
                activity(true, "TEST-2");
                compare(bpal.dark, false);
                compare(launchpadBarBackground.visible, false);
                activity(true);
                preferences(0.04);
                compare(bpal.dark, false);
                activity(false);
                root.darkMode = true;
                compare(bpal.dark, true);
            }
            function test_disabledBarAndPopovers() {
                activity(true);
                root.barEnabled = false;
                compare(launchpadBarBackground.visible, false);
                ui.anyVisible = true;
                compare(ui.hostLayer, WlrLayer.Overlay);
                activity(false);
                compare(ui.hostLayer, WlrLayer.Overlay);
            }
        }
    }
}
'''
            for key, value in (("COMMON", "Common"),
                               ("COVERAGE", coverage), ("PALETTE", palette),
                               ("LAYER", layer), ("HOST_VISIBLE", host_visible),
                               ("NORMAL_VISIBLE", normal_visible),
                               ("STRIP", strip), ("WALLPAPER", json.dumps(wallpaper.as_uri()))):
                qml = qml.replace(key, value)
            (task_root / "shell.qml").write_text(qml)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(task_root / "state"),
                       XDG_CACHE_HOME=str(task_root / "cache"))
            env.pop("WAYLAND_DISPLAY", None)
            result = subprocess.run(["qs", "-p", str(task_root), "--no-color"], env=env,
                                    capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertRegex(output, r"TOTALS [1-9][0-9]* passed, 0 failed", output)
            self.assertNotRegex(output, r"(TypeError|ReferenceError|ERROR qml:|WARN qml:)")
            print(output)


if __name__ == "__main__":
    unittest.main()
