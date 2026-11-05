"""Exercise production ghost handoff against real Qt image loading and animations.

The software scene graph cannot draw custom shaders or request compositor window
exports. GPU nodes are substituted, including the texture completion signal;
PNG loading, state transitions and animations use the production delegate.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from PIL import Image
from test_launchpad_menubar import qml_block

SHELL = Path(__file__).resolve().parents[1]


class MinimizeHandoffTests(unittest.TestCase):
    def test_render_handoff(self):
        source = (SHELL / "MacMinimize.qml").read_text()
        ghost = qml_block(source, "gh").replace("delegate: Item {", "Item {", 1)
        ghost = ghost.replace("ShaderEffect {", "TestShader {")
        ghost = ghost.replace("ScreencopyView {", "TestCapture {")
        ghost = ghost.replace("ShaderEffectSource {", "TestTexture {")
        for identifier in ("srcImg", "fx", "anim", "srcTex", "capture", "snapshotSoon"):
            ghost = ghost.replace(f"id: {identifier}\n",
                                  f'id: {identifier}\nobjectName: "{identifier}"\n')
        start = source.index("    function onPrepared(o) {")
        opening = source.index("{", start)
        depth, end = 1, opening + 1
        while depth:
            depth += (source[end] == "{") - (source[end] == "}")
            end += 1
        prepared = source[start:end]
        start = source.index("    function nativeCaptureFailed(a) {")
        native_failure = source[start:source.index("\n    Process {", start)]
        prepared = prepared.replace("Corners.DesktopPreferences.settings.minimizeEffect", '\"genie\"')
        prepared = prepared.replace("Corners.DesktopPreferences.settings.position", '\"bottom\"')
        ghost = ghost.replace('frozenSource.grabToImage(function(image) {',
                              'if (root.stallSnapshot) return; frozenSource.grabToImage(function(image) {')
        start = source.index("    function prepareDirect(a) {")
        direct = source[start:source.index("\n    function focusedAddr", start)]
        direct = direct.replace("Hyprland.", "fakeHyprland.")
        start = source.index("    function minimize(a) {")
        minimize = source[start:source.index("\n    Process {", start)]
        qml = r'''
import QtQuick
import QtTest
Item {
    id: root
    width: 640; height: 480
    property int durMin: 100
    property int durRes: 100
    property int hides: 0
    property int restores: 0
    property int removals: 0
    property bool textureAtHide: false
    property int snapshots: 0
    property bool stallSnapshot: false
    property bool exportAvailable: true
    property bool completeTexture: true
    property var fakeToplevel: ({address: "abc123"})
    property var fakeHyprland: ({toplevels: {values: []}})
    property var preparing: ({})
    property var canceledPreparations: ({})
    property bool nativeCaptureAvailable: true
    property var screenshotQueue: []
    property var onSpecial: ({})
    property var prepareQueue: []
    property int fallbackCalls: 0
    property int screenshotFallbacks: 0
    function trace(stage,detail) {}
    function prepareNext() { fallbackCalls++; }
    function queueScreenshot(rec) { screenshotFallbacks++; }
    function cancelGhosts(addr) { removals++; }
    NATIVE_FAILURE
    DIRECT
    MINIMIZE
    property var records: ({})
    property int ghostPlans: 0
    property bool hasTarget: true
    function toplevelFor(addr) { return fakeToplevel; }
    function saveSnapshot(addr, image) { image.saveToFile("SNAPSHOT"); snapshots++; }
    function norm(addr) { return String(addr); }
    function saveState() {}
    function dockKey(appId) { return appId; }
    function dockTarget() { return hasTarget ? {x: 320, y: 420, size: 48, screen: "TEST-1"} : null; }
    function screenForMon() { return {name: "TEST-1", x: 0, y: 0}; }
    function screenForPoint() { return screenForMon(); }
    function addGhost(g) { ghostPlans++; }
    PREPARED
    property var ghost: null
    property var modelData: ({name: "TEST-1"})
    // The production delegate references its PanelWindow by this id.
    Item { id: animWin; property var modelData: root.modelData }
    function hideWindow(addr) { hides++; textureAtHide = ghost ? ghost.textureReady : false; }
    function finishRestore(addr) { restores++; }
    function removeGhost(gid) { removals++; }
    component TestCapture: Rectangle {
        color: "#27bd6e"
        property var captureSource
        property bool live: false
        property bool paintCursor: false
        property bool hasContent: captureSource !== null && root.exportAvailable
        signal stopped()
    }
    component TestShader: Item {
        property url fragmentShader
        property int status: ShaderEffect.Compiled
        property string log: ""
    }
    component TestTexture: Item {
        property Item sourceItem
        property bool hideSource
        property bool live
        property bool recursive
        signal scheduledUpdateCompleted()
        function scheduleUpdate() {
            if (root.completeTexture) Qt.callLater(function() { scheduledUpdateCompleted(); });
        }
    }
    Component {
        id: ghostComponent
        GHOST
    }
    TestCase {
        name: "MinimizeHandoff"
        when: windowShown
        function makeGhost(mode, effect, screen, source) {
            root.ghost = ghostComponent.createObject(root, {
                gid: 1, gmode: mode, gaddr: "abc123", gsrc: source, gcapture: source === "",
                gscreen: screen, wx: 20, wy: 20, ww: 320, wh: 240,
                icx: 320, icy: 420, icsz: 48, geffect: effect, gdirection: "bottom"
            });
            verify(root.ghost !== null);
            return root.ghost;
        }
        function init() {
            root.hides = 0; root.restores = 0; root.removals = 0;
            root.textureAtHide = false; root.ghostPlans = 0; root.hasTarget = true;
            root.snapshots = 0; root.exportAvailable = true;
            root.completeTexture = true;
            root.records = ({}); root.preparing = ({}); root.onSpecial = ({});
            root.canceledPreparations = ({}); root.stallSnapshot = false;
            root.nativeCaptureAvailable = true; root.screenshotQueue = []; root.screenshotFallbacks = 0;
            root.prepareQueue = []; root.fallbackCalls = 0;
        }
        function cleanup() {
            if (root.ghost) root.ghost.destroy();
            root.ghost = null;
            wait(0);
        }
        function test_preparation_data() {
            return [
                {tag: "animated", target: true, shot: "SHOT", plans: 1, hides: 0},
                {tag: "no-capture", target: true, shot: "", plans: 0, hides: 1},
                {tag: "direct-frame", target: true, shot: "", capture: true, plans: 1, hides: 0},
                {tag: "no-dock", target: false, shot: "SHOT", plans: 0, hides: 1}
            ];
        }
        function test_preparation(data) {
            root.hasTarget = data.target;
            root.onPrepared({addr: "abc123", appId: "test", title: "test", ws: 1,
                wsName: "1", mon: 0, pid: 123, fullscreen: 0, at: [20,20],
                size: [320,240], floating: true, shot: data.shot, capture: data.capture === true});
            compare(root.ghostPlans, data.plans);
            compare(root.hides, data.hides, "Animated preparation must leave the real window visible");
            verify(root.records.abc123 !== undefined);
        }
        function test_transition_data() {
            return [
                {tag: "genie-minimize", mode: "minimize", effect: "genie"},
                {tag: "genie-restore", mode: "restore", effect: "genie"},
                {tag: "scale-minimize", mode: "minimize", effect: "scale"},
                {tag: "scale-restore", mode: "restore", effect: "scale"}
            ];
        }
        function test_transition(data) {
            const ghost = makeGhost(data.mode, data.effect, "TEST-1", "SHOT");
            const fx = findChild(ghost, "fx");
            const image = findChild(ghost, "srcImg");
            const anim = findChild(ghost, "anim");
            compare(ghost.started, false);
            compare(anim.running, false);
            compare(root.hides, 0, "Creation must not hide the real window");
            compare(fx.progress, 1, "Preparation stays transparent without disabling the shader");
            tryCompare(ghost, "started", true);
            compare(image.status, Image.Ready);
            compare(findChild(ghost, "srcTex").visible, true,
                    "The production texture producer must participate in rendering");
            compare(root.hides, data.mode === "minimize" ? 1 : 0);
            if (data.mode === "minimize") {
                verify(ghost.frozenSource !== null);
                verify(root.textureAtHide, "The real window must remain visible until its texture is ready");
            }
            tryCompare(root, "removals", 1);
            compare(root.restores, data.mode === "restore" ? 1 : 0);
            compare(fx.progress, data.mode === "minimize" ? 1 : 0);
            wait(80);
            compare(root.removals, 1, "Later frames cannot restart the animation");
        }
        function test_cachedMetadataAvoidsProcessQueue() {
            root.fakeHyprland = {toplevels: {values: [{address: "abc123", wayland: root.fakeToplevel,
                lastIpcObject: {class: "test", title: "test", workspace: {id: 1, name: "1"},
                    monitor: 0, pid: 123, at: [20,20], size: [320,240], floating: true}}]}};
            root.minimize("abc123");
            compare(root.ghostPlans, 1);
            compare(root.hides, 0);
            compare(root.fallbackCalls, 0);
            compare(root.prepareQueue.length, 0);
            compare(root.preparing.abc123, undefined);
            root.minimize("abc123");
            compare(root.ghostPlans, 1, "Repeated native requests cannot duplicate the transition");
        }
        function test_textureCompletionStartsWithoutWindowSwap() {
            root.completeTexture = false;
            const ghost = makeGhost("minimize", "genie", "TEST-1", "SHOT");
            tryCompare(findChild(ghost, "srcImg"), "status", Image.Ready);
            wait(25);
            compare(ghost.started, false); compare(root.hides, 0);
            findChild(ghost, "srcTex").scheduledUpdateCompleted();
            wait(0);
            compare(ghost.started, true, "Texture completion must start Genie without a window frame signal");
            verify(findChild(ghost, "anim").running);
            verify(root.textureAtHide);
        }
        function test_failedNativeExportUsesSnapshotInsteadOfRemovingEffect() {
            root.fakeHyprland = {toplevels: {values: [{address: "abc123", wayland: root.fakeToplevel,
                lastIpcObject: {class: "test", title: "test", workspace: {id: 1, name: "1"},
                    monitor: 0, pid: 123, at: [20,20], size: [320,240], floating: true}}]}};
            root.minimize("abc123");
            root.nativeCaptureFailed("abc123");
            compare(root.hides, 0, "Keep the original window visible for the fallback snapshot");
            compare(root.screenshotFallbacks, 1);
            compare(root.nativeCaptureAvailable, false);
            // Complete the snapshot: it must still create the requested animation.
            root.onPrepared(Object.assign({}, root.records.abc123, {shot: "SHOT", capture: false}));
            compare(root.ghostPlans, 2);
            compare(root.hides, 0);
        }
        function test_failedNativeCaptureIsNotRetriedOnNextClick() {
            root.nativeCaptureAvailable = false;
            root.fakeHyprland = {toplevels: {values: [{address: "abc123", wayland: root.fakeToplevel,
                lastIpcObject: {class: "test", title: "test", workspace: {id: 1, name: "1"},
                    monitor: 0, pid: 123, at: [20,20], size: [320,240], floating: true}}]}};
            root.minimize("abc123");
            compare(root.screenshotFallbacks, 1);
            compare(root.ghostPlans, 0);
            compare(root.hides, 0);
        }
        function test_missingMetadataFallsBackImmediately() {
            root.fakeHyprland = {toplevels: {values: []}};
            root.minimize("abc123");
            compare(root.fallbackCalls, 1);
            compare(root.prepareQueue[0], "abc123");
            compare(root.hides, 0);
            root.minimize("abc123");
            compare(root.fallbackCalls, 1);
        }
        function test_directFrameStartsWithoutImageOrTimer() {
            const ghost = makeGhost("minimize", "genie", "TEST-1", "");
            // Hold only the optional save to verify it is not a startup gate.
            findChild(ghost, "snapshotSoon").interval = 1000;
            compare(findChild(ghost, "srcImg").status, Image.Null);
            compare(root.hides, 0);
            tryCompare(ghost, "started", true);
            verify(ghost.frozenSource !== null);
            compare(root.snapshots, 0, "PNG saving must not block starting the animation");
            findChild(ghost, "snapshotSoon").stop();
            verify(findChild(ghost, "anim").running);
            // Preview saving is optional and cannot block the running animation.
            wait(30);
            verify(findChild(ghost, "fx").progress > 0.1, "Visible movement begins immediately");
            ghost.savePreview();
            tryCompare(root, "removals", 1);
            compare(root.snapshots, 1);
            compare(root.hides, 1);
        }
        function test_stalledSnapshotCannotLeaveFrozenDuplicate() {
            root.stallSnapshot = true;
            const ghost = makeGhost("minimize", "genie", "TEST-1", "");
            compare(findChild(ghost, "fx").opacity, 1,
                "Keep the shader renderable while preparing at the transparent endpoint");
            compare(findChild(ghost, "fx").progress, 1);
            tryCompare(ghost, "started", true);
            tryCompare(root, "removals", 1);
            compare(ghost.finished, true);
            compare(findChild(ghost, "fx").opacity, 0);
            compare(root.hides, 1); compare(root.snapshots, 0);
        }
        function test_uncompiledStatusDoesNotSkipAnimation() {
            const ghost = makeGhost("minimize", "genie", "TEST-1", "SHOT");
            findChild(ghost, "fx").status = ShaderEffect.Uncompiled;
            tryCompare(ghost, "textureReady", true);
            tryCompare(findChild(ghost, "anim"), "running", true);
            verify(root.textureAtHide);
            tryCompare(root, "removals", 1);
            compare(root.hides, 1);
            compare(findChild(ghost, "fx").progress, 1);
        }
        function test_unavailableExportFallsBackOnce() {
            root.exportAvailable = false;
            root.records = {abc123: {addr: "abc123", at: [20,20], size: [320,240]}};
            const ghost = makeGhost("minimize", "genie", "TEST-1", "");
            compare(root.hides, 0);
            tryCompare(root, "removals", 1);
            compare(root.hides, 0); compare(root.snapshots, 0);
            compare(root.screenshotFallbacks, 1, "Keep Genie/Scale by requesting a screen snapshot on export failure");
            compare(root.nativeCaptureAvailable, false);
            verify(!findChild(ghost, "anim").running);
        }
        function test_cachedShaderStartsWhenTextureCompletes_data() {
            return [
                {tag: "genie-minimize", mode: "minimize", effect: "genie"},
                {tag: "genie-restore", mode: "restore", effect: "genie"},
                {tag: "scale-minimize", mode: "minimize", effect: "scale"},
                {tag: "scale-restore", mode: "restore", effect: "scale"}
            ];
        }
        function test_cachedShaderStartsWhenTextureCompletes(data) {
            root.completeTexture = false;
            const ghost = makeGhost(data.mode, data.effect, "TEST-1", "SHOT");
            const fx = findChild(ghost, "fx");
            fx.status = ShaderEffect.Uncompiled;
            tryCompare(findChild(ghost, "srcImg"), "status", Image.Ready);
            compare(ghost.started, false); compare(root.hides, 0);
            // Match the real desktop trace: ready PNG + ready texture, but
            // Qt's metadata cache leaves the new shader's status Uncompiled.
            findChild(ghost, "srcTex").scheduledUpdateCompleted();
            wait(0);
            verify(ghost.started, "Uncompiled must not disable the selected effect");
            verify(findChild(ghost, "anim").running);
            compare(root.hides, data.mode === "minimize" ? 1 : 0);
            compare(fx.status, ShaderEffect.Uncompiled);
            tryCompare(root, "removals", 1);
            compare(root.restores, data.mode === "restore" ? 1 : 0);
        }
        function test_otherMonitorCannotHideOrStart() {
            const ghost = makeGhost("minimize", "genie", "TEST-2", "SHOT");
            tryCompare(findChild(ghost, "srcImg"), "status", Image.Ready);
            root.Window.window.update();
            verify(waitForRendering(root)); wait(100);
            compare(ghost.started, false);
            compare(root.hides, 0); compare(root.removals, 0);
        }
        function test_imageFailure_data() {
            return [{tag: "minimize", mode: "minimize"}, {tag: "restore", mode: "restore"}];
        }
        function test_imageFailure(data) {
            ignoreWarning(/.*Cannot open:.*missing.png.*/);
            makeGhost(data.mode, "genie", "TEST-1", "MISSING");
            tryCompare(root, "removals", 1);
            compare(root.hides, data.mode === "minimize" ? 1 : 0);
            compare(root.restores, data.mode === "restore" ? 1 : 0);
            compare(root.textureAtHide, false, "A failed image skips the visual handoff");
            wait(50); compare(root.removals, 1);
        }
        function test_shaderFailureFallsBackOnce() {
            const ghost = makeGhost("minimize", "genie", "TEST-1", "SHOT");
            findChild(ghost, "fx").status = ShaderEffect.Error;
            tryCompare(root, "removals", 1);
            compare(root.hides, 1);
            wait(100); compare(root.removals, 1); compare(root.hides, 1);
        }
    }
}
'''.replace("GHOST", ghost).replace("PREPARED", prepared).replace("DIRECT", direct).replace("MINIMIZE", minimize).replace("NATIVE_FAILURE", native_failure)
        with tempfile.TemporaryDirectory(prefix="minimize-handoff-") as directory:
            task = Path(directory)
            runtime = task / "runtime"
            runtime.mkdir(mode=0o700)
            shot = task / "shot.png"
            Image.new("RGB", (320, 240), "#27bd6e").save(shot)
            qml = qml.replace("SNAPSHOT", str(task / "snapshot.png"))
            qml = qml.replace("SHOT", str(shot)).replace("MISSING", str(task / "missing.png"))
            test = task / "tst_handoff.qml"
            test.write_text(qml)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_RUNTIME_DIR=str(runtime))
            result = subprocess.run(["/usr/lib/qt6/bin/qmltestrunner", "-input", str(test)],
                                    env=env, capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            print(output)
            self.assertEqual(result.returncode, 0, output)
            self.assertNotRegex(output, r"QWARN|TypeError|ReferenceError|Unable to assign")
            with Image.open(task / "snapshot.png") as snapshot:
                self.assertEqual(snapshot.size, (320, 240))
                self.assertEqual(snapshot.convert("RGBA").getpixel((160, 120)), (39, 189, 110, 255))


    def test_dock_and_preview_restore_real_window(self):
        source = (SHELL / "MacMinimize.qml").read_text()
        dock = (SHELL / "MacDock.qml").read_text()

        def function(text, name):
            start = text.index("    function " + name + "(")
            opening = text.index("{", start)
            depth, end = 1, opening + 1
            while depth:
                depth += (text[end] == "{") - (text[end] == "}")
                end += 1
            return text[start:end]

        functions = "\n".join(function(source, name) for name in
                              ("norm", "isMinimized", "cancelGhosts", "restore", "finishRestore", "recoverRestores",
                               "removeGhost", "doRestore", "saveSnapshot"))
        functions = functions.replace("Hyprland.dispatch", "fakeHyprland.dispatch")
        functions = functions.replace("Corners.DesktopPreferences.settings.minimizeEffect", '\"genie\"')
        functions = functions.replace("Corners.DesktopPreferences.settings.position", '\"bottom\"')
        recovery = qml_block(source, "restoreRecovery").replace("root.", "owner.")
        dock_functions = "\n".join(function(dock, name) for name in ("activate", "focusWindow"))
        dock_functions = dock_functions.replace("Quickshell.execDetached", "root.ignoreDetached")
        qml = r'''
import QtQuick
import QtTest
Item {
    id: fixture
    width: 600; height: 400
    property var commands: []
    property int activations: 0
    property int saves: 0
    property var window: ({addr: "abc123", activated: false})
    QtObject {
        id: fakeHyprland
        function dispatch(command) { fixture.commands = fixture.commands.concat([command]); }
    }
    Item {
        id: owner
        property var records: ({})
        property var onSpecial: ({})
        property var preparing: ({})
        property var canceledPreparations: ({})
    property bool nativeCaptureAvailable: true
    property var screenshotQueue: []
        property var prepareQueue: []
        property var pendingRestore: ({})
        property var restoreReleases: []
        property var restoreDeadlines: ({})
        property bool targetEnabled: false
        property bool captureAvailable: false
        property bool failGhostCreation: false
        property int ghostSeq: 0
        function trace(stage,detail) {}
        function screenForMon(mon) { return {name: "TEST-1", x: 0, y: 0}; }
        function screenForPoint(x,y) { return screenForMon(0); }
        function dockKey(appId) { return "test"; }
        function dockTarget(key, mon, addr) { return targetEnabled ? {screen: "TEST-1", x: 300, y: 390, size: 48} : null; }
        function toplevelFor(addr) { return captureAvailable ? fixture.window : null; }
        RECOVERY
        property var hub: ({desktopController: {activate: function(addr) { fixture.activations++; }}})
        property string shotDir: ""
        function saveState() { fixture.saves++; }
        function defaultRect(mon) { return {x: 10, y: 30, w: 800, h: 600}; }
        function clampRect(rect, mon) { return rect; }
        function currentWorkspaceId(rect) { return 3; }
        Timer { id: releaseRestored }
        Timer { id: hotspotsSoon }
        ListModel { id: ghostModel }
        function addGhost(mode) {
            if (typeof mode === "object") {
                if (failGhostCreation) { finishRestore(mode.gaddr); return; }
                mode.gid = ++ghostSeq; ghostModel.append(mode);
            } else ghostModel.append({gid: ++ghostSeq, gaddr: "abc123", gmode: mode});
        }
        function ghostAt(i) { return ghostModel.get(i); }
        function ghostCount() { return ghostModel.count; }
        FUNCTIONS
    }
    Item {
        id: dockRoot
        property var minimize: owner
        property string launchpadKey: "launchpad"
        property var desktopPrefs: ({stageManager: false})
        property var hub: ({desktopController: {send: function(request) {}, revealed: []}})
        function ignoreDetached(command) {}
        function rememberApp(appId) {}
        function windowsFor(key) { return [fixture.window]; }
        function winAddr(tl) { return tl.addr; }
        DOCK_FUNCTIONS
    }
    TestCase {
        name: "DockRestore"
        when: windowShown
        function init() {
            owner.records = {abc123: {ws: 2, wsName: "2", mon: 0, at: [140,80], size: [900,600], floating: true, shot: ""}};
            owner.onSpecial = {abc123: true};
            owner.preparing = ({}); owner.canceledPreparations = ({});
            owner.prepareQueue = []; owner.pendingRestore = ({}); owner.restoreDeadlines = ({});
            owner.targetEnabled = false; owner.captureAvailable = false; owner.failGhostCreation = false;
            fixture.commands = []; fixture.activations = 0; fixture.saves = 0;
        }
        function cleanup() { owner.cancelGhosts("abc123"); }
        function assertRestored() {
            compare(owner.ghostCount(), 0, "All old frozen overlays must be removed");
            compare(owner.isMinimized("abc123"), false);
            compare(owner.records.abc123, undefined);
            compare(owner.pendingRestore.abc123, undefined);
            compare(fixture.activations, 1);
            verify(fixture.commands.some(function(c) { return c.indexOf("workspace = 2") >= 0; }),
                "Move the real window out of the minimized workspace synchronously");
            verify(fixture.commands.some(function(c) { return c.indexOf('hl.dsp.focus({ window = "address:0xabc123"') >= 0; }));
            verify(fixture.commands.some(function(c) { return c.indexOf('x = 140, y = 80') >= 0; }));
            verify(fixture.commands.every(function(c) { return c.indexOf("special:minimized") < 0; }));
        }
        function test_dockIconDuringMinimize() {
            owner.addGhost("minimize");
            dockRoot.activate({kind: "app", key: "test", appId: "test"}, false);
            assertRestored();
        }
        function test_livePreviewDuringMinimize() {
            owner.addGhost("minimize");
            dockRoot.activate({kind: "win", tl: fixture.window}, false);
            assertRestored();
        }
        function test_focusPreviewWithStuckRestore() {
            owner.pendingRestore = {abc123: {x: 140, y: 80, w: 900, h: 600}};
            owner.addGhost("restore");
            dockRoot.focusWindow(fixture.window);
            assertRestored();
        }
        function test_missingPreviewImageDoesNotBlockRestore() {
            dockRoot.focusWindow(fixture.window);
            assertRestored();
        }
        function test_latePreparationAndPreviewAreCanceled() {
            owner.preparing = {abc123: true};
            owner.prepareQueue = ["abc123", "def456"];
            owner.addGhost("minimize");
            dockRoot.focusWindow(fixture.window);
            assertRestored();
            compare(owner.preparing.abc123, undefined);
            compare(owner.canceledPreparations.abc123, true);
            compare(owner.prepareQueue.length, 1);
            compare(owner.prepareQueue[0], "def456");
            // A late optional screenshot cannot recreate minimized bookkeeping.
            owner.saveSnapshot("abc123", {saveToFile: function(path) { fail("Restored windows must not save a stale preview"); }});
            compare(owner.isMinimized("abc123"), false);
        }
        function animateFromDock() {
            owner.targetEnabled = true;
            owner.records.abc123.shot = "saved-preview.png";
            dockRoot.activate({kind: "app", key: "test", appId: "test"}, false);
            compare(owner.ghostCount(), 1);
            compare(owner.ghostAt(0).gmode, "restore");
            compare(owner.ghostAt(0).geffect, "genie");
            compare(owner.ghostAt(0).gcapture, false);
            verify(owner.pendingRestore.abc123 !== undefined);
            verify(owner.restoreDeadlines.abc123 > Date.now());
            compare(fixture.activations, 0, "The real window appears when the Genie lands");
        }
        function test_dockIconPlaysGenieRestore() {
            animateFromDock();
            owner.finishRestore("abc123"); owner.cancelGhosts("abc123");
            assertRestored();
        }
        function test_livePreviewPlaysGenieWithoutSavedImage() {
            owner.targetEnabled = true; owner.captureAvailable = true;
            dockRoot.focusWindow(fixture.window);
            compare(owner.ghostCount(), 1);
            compare(owner.ghostAt(0).gmode, "restore");
            compare(owner.ghostAt(0).geffect, "genie");
            compare(owner.ghostAt(0).gcapture, true);
            owner.finishRestore("abc123"); owner.cancelGhosts("abc123");
            assertRestored();
        }
        function test_repeatedClickRecoversAnimatedRestore() {
            animateFromDock();
            dockRoot.focusWindow(fixture.window);
            assertRestored();
        }
        function test_rootDeadlineRecoversIfDelegateNeverFinishes() {
            animateFromDock();
            owner.restoreDeadlines = {abc123: Date.now() + 30};
            tryCompare(fixture, "activations", 1);
            assertRestored();
        }
        function test_removedGhostStillRestoresWindow() {
            animateFromDock();
            owner.removeGhost(owner.ghostAt(0).gid);
            assertRestored();
        }
        function test_syncFailureSeesPendingRestore() {
            owner.targetEnabled = true; owner.failGhostCreation = true;
            owner.records.abc123.shot = "saved-preview.png";
            dockRoot.focusWindow(fixture.window);
            assertRestored();
            compare(Object.keys(owner.restoreDeadlines).length, 0);
        }
        function test_recordMissingStillRecoversParkedWindow() {
            owner.records = ({});
            dockRoot.focusWindow(fixture.window);
            compare(owner.isMinimized("abc123"), false);
            verify(fixture.commands.some(function(c) { return c.indexOf("workspace = 3") >= 0; }));
            compare(fixture.activations, 1);
        }
    }
}
'''
        # The production functions use root in their own component scope.
        qml = qml.replace("RECOVERY", recovery)
        qml = qml.replace("DOCK_FUNCTIONS", dock_functions.replace("root.", "dockRoot."))
        qml = qml.replace("FUNCTIONS", functions.replace("root.", "owner."))
        with tempfile.TemporaryDirectory(prefix="dock-restore-") as directory:
            task = Path(directory)
            runtime = task / "runtime"
            runtime.mkdir(mode=0o700)
            test = task / "tst_restore.qml"
            test.write_text(qml)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_RUNTIME_DIR=str(runtime))
            result = subprocess.run(["/usr/lib/qt6/bin/qmltestrunner", "-input", str(test)],
                                    env=env, capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            print(output)
            self.assertEqual(result.returncode, 0, output)
            self.assertNotRegex(output, r"QWARN|TypeError|ReferenceError|Unable to assign")


if __name__ == "__main__":
    unittest.main()
