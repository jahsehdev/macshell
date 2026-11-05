"""Exercise the Dock's production capture bounds and tooltip readiness bindings in Qt."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

SHELL = Path(__file__).resolve().parents[1]


def function(source, name):
    start = source.index("function " + name + "(")
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


class DockTooltipBackdropTests(unittest.TestCase):
    def test_capture_bounds_and_window_readiness(self):
        source = (SHELL / "MacDock.qml").read_text()
        ready = function(source, "readyFor")
        surface = function(source, "surfaceRectFor")
        shell = (SHELL / "shell.qml").read_text()
        fingerprint = re.search(r'gk.push\((.+)\);', shell)[1]
        capture_ready = re.search(r"readonly property bool captureReady: (.*?)\n\s*//", source, re.S)[1].strip()
        near = re.search(r"readonly property bool nearNow: (.*?)\n\s*//", source, re.S)[1].strip()
        with tempfile.TemporaryDirectory(prefix="dock-tooltip-backdrop-") as directory:
            path = Path(directory)
            (path / "runtime").mkdir(mode=0o700)
            (path / "MacShell").symlink_to(SHELL)
            qml = r'''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "MacShell"
ShellRoot {
    Window {
        id: host; width: 400; height: 160; visible: true; color: "yellow"
        QtObject { id: root; property bool glassRT: false }
        Item { id: ui; height: 400; property bool tucked: false }
        Item {
            id: bd; width: 1000; height: 1000
            readonly property real captureMargin: 82
            ListModel { id: windows }
            Repeater {
                id: windowCaptures; model: windows
                delegate: Item {
                    required property bool gone
                    required property real wx
                    required property real wy
                    required property real wz
                    z: wz
                    x: wx; y: wy; width: 100; height: 250
                    QtObject { id: windowLoader; property var item: null }
                    property alias exportState: windowLoader.item
                    readonly property bool captureReady: CAPTURE_READY
                    readonly property bool nearNow: NEAR
                }
            }
            READY_FUNCTION
            SURFACE_FUNCTION
        }
        DockTooltip {
            id: tip; x: 10; y: 10; text: "Spotify"; liquid: true
            // Avoid starting a GPU shader in a software-only test. The actual
            // material choice and capture rectangle still use production QML.
            visible: !useLiquid
            backdrop: bd; backdropOrigin: Qt.point(100, 780)
            backdropReady: bd.readyFor(captureRect)
            surfaceOpacity: 0
        }
        TestCase {
            name: "DockTooltipBackdrop"; when: host.visible
            onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
            function init() { windows.clear(); ui.tucked = false; root.glassRT = false; }
            function addWindow() {
                windows.append({gone: false, wx: 100, wy: 600, wz: 100});
                return windowCaptures.itemAt(0);
            }
            function test_labelOnlyFloatingWindowStaysCapturedInNonRealtimeMode() {
                const capture = addWindow();
                verify(capture.nearNow);
                // This window ends 93 px above the slab, outside the old 48 px zone.
                capture.y = 430; verify(capture.nearNow); // ends at 680, within the panel
                capture.y = 260; verify(!capture.nearNow); // ends at 510, outside optical margin
                root.glassRT = true; verify(capture.nearNow);
                root.glassRT = false; capture.y = 600;
                ui.tucked = true; verify(!capture.nearNow);
            }
            function test_pendingFailedAndRecoveredExportsChooseCorrectMaterial() {
                verify(tip.useLiquid); // wallpaper is valid with no overlapping windows
                const capture = addWindow();
                verify(!tip.useLiquid); // no export yet
                capture.exportState = {captureStopped: false, hasContent: false};
                verify(!tip.useLiquid);
                capture.exportState = {captureStopped: false, hasContent: true};
                verify(tip.useLiquid);
                capture.exportState = {captureStopped: true, hasContent: true};
                verify(!tip.useLiquid); // a retained texture is not a healthy export
                capture.exportState = {captureStopped: false, hasContent: true};
                verify(tip.useLiquid);
                capture.exportState = null;
                verify(!tip.useLiquid);
                capture.gone = true;
                verify(tip.useLiquid); // minimized/closed windows cannot block recovery
            }
            function test_onlyOverlappingExportsBlockGlass() {
                const capture = addWindow();
                verify(!tip.useLiquid);
                capture.x = 800; verify(tip.useLiquid);
                capture.x = 100; verify(!tip.useLiquid);
                capture.y = 100; verify(tip.useLiquid);
            }
            function test_surfaceBoundsFollowTopFloatingWindow() {
                const capture = addWindow();
                compare(bd.surfaceRectFor(Qt.point(100,780),60,32,Qt.rect(0,0,1000,1000)), Qt.rect(101,601,98,248));
                windows.append({gone:false,wx:110,wy:610,wz:99});
                compare(bd.surfaceRectFor(Qt.point(110,780),60,32,Qt.rect(0,0,1000,1000)).x,101);
                windowCaptures.itemAt(1).z=101;
                compare(bd.surfaceRectFor(Qt.point(110,780),60,32,Qt.rect(0,0,1000,1000)).x,111);
                windowCaptures.itemAt(1).gone=true;
                compare(bd.surfaceRectFor(Qt.point(110,780),60,32,Qt.rect(0,0,1000,1000)).x,101);
                capture.gone=true;
                compare(bd.surfaceRectFor(Qt.point(110,780),60,32,Qt.rect(0,0,1000,1000)),Qt.rect(0,0,1000,1000));
            }
            function test_focusingWindowInvalidatesSharedBackdropGeometry() {
                const c={address:"0x123",focusHistoryID:0};
                const before=JSON.stringify(FINGERPRINT);
                c.focusHistoryID=1;
                verify(JSON.stringify(FINGERPRINT)!==before);
            }
            function test_windowBoundaryClipsBeforeBlur() {
                tip.backdropBounds=Qt.rect(0,0,1000,815);
                compare(tip.captureRect.y+tip.captureRect.height,815);
                verify(tip.captureRect.y+tip.captureRect.height<tip.requestedCaptureRect.y+tip.requestedCaptureRect.height);
                tip.backdropBounds=Qt.binding(function(){return tip.requestedCaptureRect;});
            }
            function test_captureRectIncludesFullOpticalMargin() {
                compare(tip.captureRect.x, tip.backdropOrigin.x - 82);
                compare(tip.captureRect.y, tip.backdropOrigin.y - 82);
                compare(tip.captureRect.width, tip.width + 164);
                compare(tip.captureRect.height, tip.height + 164);
            }
            function test_zeroTintFallbackStillCoversWallpaper() {
                addWindow(); verify(!tip.useLiquid);
                wait(40);
                const pixel = grabImage(host.contentItem).pixel(30, 25);
                // A nonzero body tint is required by macdock's ignore_alpha=0.2.
                verify(pixel.r < 0.9 && pixel.g < 0.9, pixel.toString());
            }
        }
    }
}'''.replace("CAPTURE_READY", capture_ready).replace("NEAR", near).replace("READY_FUNCTION", ready).replace("SURFACE_FUNCTION", surface).replace("FINGERPRINT", fingerprint)
            (path / "shell.qml").write_text(qml)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_RUNTIME_DIR=str(path / "runtime"), XDG_CONFIG_HOME=str(path / "config"),
                       XDG_STATE_HOME=str(path / "state"))
            env.pop("WAYLAND_DISPLAY", None)
            result = subprocess.run(["qs", "-p", str(path), "--no-color"], env=env,
                                    capture_output=True, text=True, timeout=25)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertRegex(output, r"TOTALS [1-9][0-9]* passed, 0 failed", output)
            self.assertNotRegex(output, r"ERROR qml:|TypeError|ReferenceError", output)


if __name__ == "__main__":
    unittest.main()
