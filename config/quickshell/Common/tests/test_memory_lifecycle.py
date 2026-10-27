"""Exercise resource release and the actual Launchpad scene in isolated Qt windows."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from PIL import Image

COMMON = Path(__file__).resolve().parents[1]

QML = r'''
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "config/quickshell/Common" as Common
import "config/quickshell/launchpad" as Launchpad
import "config/quickshell/launchpad/components" as Components

ShellRoot {
    Window {
        id: host
        width: 1280; height: 800; visible: true
        property var modelData: ({ name: "TEST-1", width: 1280, height: 800 })
        property bool focusedHere: true
        property bool optionsOpen: false
        property real wheelX: 0
        property real wheelY: 0
        property real lastPageScroll: 0
        property real dotsCenterY: height - 16
        property real gridX: (width - Launchpad.Theme.gridWidth) / 2
        property real gridY: 130
        property bool revealGrid: scene.item !== null && scene.item.revealGrid
        property int released: 0
        Common.ActivityLoader {
            id: retained
            releaseDelay: 200
            sourceComponent: Item { Component.onDestruction: host.released++ }
        }
        Loader {
            id: scene
            anchors.fill: parent
            focus: true
            active: Launchpad.LaunchpadState.windowVisible
            Component.onCompleted: setSource(Qt.resolvedUrl("config/quickshell/launchpad/components/LaunchpadContent.qml"), {win: host})
        }
        Common.LaunchpadBackground {
            id: background
            visible: false
            width: 1280; height: 800
            imageSource: WALLPAPER
            backgroundBlur: 0.35
        }
        TestCase {
            name: "MemoryLifecycle"
            when: host.visible
            onCompletedChanged: if (completed)
                console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")

            function initTestCase() {
                wait(350);
                Launchpad.Theme.backgroundType = "custom";
                Launchpad.Theme.customImage = WALLPAPER;
                Launchpad.Theme.autoLayout = false;
                Launchpad.Theme.columns = 8;
                Launchpad.Theme.rows = 5;
                Launchpad.Theme.animationsEnabled = true;
                Launchpad.LaunchpadState.mockMode = true;
                Launchpad.LaunchpadState.pages = Launchpad.LaunchpadState.buildMockPages();
                Launchpad.LaunchpadState.refreshView();
            }
            function test_delayedReleaseAndRapidReopen() {
                compare(retained.item, null);
                retained.requested = true;
                verify(retained.item !== null);
                const original = retained.item;
                retained.requested = false;
                wait(60);
                compare(retained.item, original, "keep resources through a close animation");
                retained.requested = true;
                wait(220);
                compare(retained.item, original, "rapid reopen cancels release");
                retained.requested = false;
                tryCompare(retained, "item", null, 1000);
                compare(host.released, 1);
                retained.requested = true;
                verify(retained.item !== null, "scene must work again after release");
                retained.requested = false;
                tryCompare(retained, "item", null, 1000);
            }
            function test_launchpadSceneReopensWithoutLosingLayoutOrKeyboard() {
                const state = Launchpad.LaunchpadState;
                const layout = JSON.stringify(state.pages.map(p => p.map(state.serializeItem)));
                compare(scene.item, null, "no hidden icon/effect objects at startup");
                for (let i = 0; i < 3; ++i) {
                    state.open();
                    tryVerify(() => scene.item !== null && state.shown, 2000);
                    wait(80);
                    keyClick(Qt.Key_M);
                    tryCompare(state, "query", "m", 1000);
                    const current = scene.item;
                    state.close();
                    compare(scene.item, current, "keep UI until close animation finishes");
                    tryCompare(state, "windowVisible", false, 2000);
                    compare(scene.item, null, "release hidden visual subtree");
                    compare(JSON.stringify(state.pages.map(p => p.map(state.serializeItem))), layout);
                }
            }
            function test_wallpaperDecodeBoundAndFallbackRelease() {
                tryVerify(() => background.cachedSource.toString() !== "", 5000);
                tryVerify(() => background.ready, 3000);
                const images = Array.from(background.children).filter(c => c.sourceSize !== undefined && c.source !== undefined);
                compare(images.length, 2);
                tryVerify(() => images.filter(i => i.source.toString() !== "" && i.status === Image.Ready).length === 1, 3000);
                compare(images[0].source.toString(), "", "do not retain original plus prepared blur");
                for (const image of images) {
                    verify(image.sourceSize.width <= 1280 * background.renderScale);
                    verify(image.sourceSize.height <= 800 * background.renderScale);
                }
                background.backgroundBlur = 0;
                tryCompare(images[0], "status", Image.Ready, 3000);
                compare(images[1].source.toString(), "");
                verify(images[0].implicitWidth < 3840, "decode scaled pixels, not original 4K image");
                background.backgroundBlur = 0.35;
                tryVerify(() => images[1].status === Image.Ready && images[0].source.toString() === "", 5000);
            }
        }
    }
}
'''


class MemoryLifecycleTests(unittest.TestCase):
    def test_resource_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix="macshell-memory-test-") as temporary:
            root = Path(temporary)
            config = root / "config/quickshell"
            config.mkdir(parents=True)
            ignore = shutil.ignore_patterns("tests", "__pycache__", "*.bak*", "Common")
            shutil.copytree(COMMON, config / "Common", ignore=ignore)
            shutil.copytree(COMMON.parent / "launchpad", config / "launchpad", ignore=ignore)
            (config / "launchpad/Common").symlink_to("../Common")
            runtime = root / "runtime"
            runtime.mkdir(mode=0o700)
            wallpaper = root / "wallpaper.jpg"
            Image.new("RGB", (3840, 2160), "#aabbee").save(wallpaper)
            (root / "shell.qml").write_text(QML.replace("WALLPAPER", '"' + wallpaper.as_uri() + '"'))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(root / "config"),
                       XDG_STATE_HOME=str(root / "state"), XDG_CACHE_HOME=str(root / "cache"))
            env.pop("WAYLAND_DISPLAY", None)
            result = subprocess.run(["qs", "-p", str(root), "--no-color"], env=env,
                                    capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertRegex(output, r"TOTALS [1-9][0-9]* passed, 0 failed", output)
            self.assertNotRegex(output, r"(TypeError|ReferenceError|ERROR qml:|WARN qml:)", output)
            print(output)


if __name__ == "__main__":
    unittest.main()
