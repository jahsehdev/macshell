"""Exercise recording state and the actual recorder command without capturing a desktop."""
import ast
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "UpstreamBar/MacBar.qml"


def function_source(source, name):
    pattern = rf"^(?P<indent> +)function {name}\([^\n]*\) \{{\n.*?^(?P=indent)\}}"
    return re.search(pattern, source, re.M | re.S)[0].strip()


class ScreenRecordingTests(unittest.TestCase):
    def test_recording_indicator(self):
        source = SOURCE.read_text()
        region = re.search(r"    readonly property rect recordRegion: \{\n.*?^    }", source, re.M | re.S)[0]
        model = re.search(r"model: (root.recording && root.recordRegion.width.*?: \[\])", source, re.S)[1]
        model = model.split("\n        PanelWindow", 1)[0].replace("Quickshell.screens", "root.screens")
        visual = re.search(r"            LocalEffects.RecordingRegion \{\n.*?^            }", source, re.M | re.S)[0]
        visual = visual.replace("LocalEffects.RecordingRegion {", "LocalEffects.RecordingRegion {\nrequired property var modelData")
        visual = visual.replace("recordingOverlay.modelData", "modelData")
        overlay = source.split("id: recordingOverlay", 1)[1].split("function pickColor", 1)[0]
        self.assertRegex(overlay, r"mask: Region\s*\{\s*}")
        self.assertIn("WlrLayershell.keyboardFocus: WlrKeyboardFocus.None", overlay)
        with tempfile.TemporaryDirectory(prefix="recording-indicator-test-") as directory:
            base = Path(directory)
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            qml = r'''
import QtQuick
import QtTest
import "COMPONENTS" as LocalEffects
Item {
    id: root
    width: 360; height: 240
    property bool recording: true
    property bool recRun: false
    property string recordGeometry: "-1880,160 200x120"
    property string recordOutput: "LEFT"
    property string fontFamily: "sans-serif"
    property int clicks: 0
    property var screens: [{name:"LEFT", x:-1920, y:120}, {name:"OTHER", x:0, y:0}]
    REGION
    function recTime() { return "0:07"; }
    Rectangle { anchors.fill: parent; color: "#99b8a2" }
    MouseArea { anchors.fill: parent; onClicked: root.clicks++ }
    Repeater {
        id: overlays
        model: MODEL
        VISUAL
    }
    TestCase {
        name: "RecordingIndicator"
        when: windowShown
        function init() {
            root.recording=true; root.recRun=false;
            root.recordGeometry="-1880,160 200x120"; root.recordOutput="LEFT";
            wait(10);
        }
        function test_geometryAndStatus() {
            compare(overlays.count, 1);
            const item=overlays.itemAt(0);
            compare(item.region, Qt.rect(40,40,200,120));
            const frame=findChild(item,"recordingAreaFrame");
            compare(frame.x,37); compare(frame.y,37);
            compare(frame.width,206); compare(frame.height,126);
            compare(item.statusText,"Starting\u2026");
            root.recRun=true;
            compare(item.statusText,"REC 0:07");
        }
        function test_clickThrough() {
            const before=root.clicks;
            mouseClick(root,100,100);
            compare(root.clicks,before+1);
        }
        function test_screenEdges() {
            root.recordGeometry="-1920,120 360x240";
            const item=overlays.itemAt(0), frame=findChild(item,"recordingAreaFrame");
            compare(frame.x,0); compare(frame.y,0);
            compare(frame.width,360); compare(frame.height,240);
            const badge=findChild(item,"recordingAreaBadge");
            verify(badge.x>=0 && badge.x+badge.width<=root.width);
            verify(badge.y>=0 && badge.y+badge.height<=root.height);
        }
        function test_lifecycle() {
            root.recording=false; compare(overlays.count,0);
            root.recording=true; compare(overlays.count,1);
            root.recordOutput="DISCONNECTED"; compare(overlays.count,0);
            root.recordOutput="LEFT";
            root.recordGeometry=""; compare(overlays.count,0);
            root.recordGeometry="invalid"; compare(overlays.count,0);
        }
    }
}
'''.replace("COMPONENTS", SOURCE.parent.parent.as_uri()).replace("REGION", region).replace("MODEL", model).replace("VISUAL", visual)
            test = base / "tst_indicator.qml"
            test.write_text(qml)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime))
            result = subprocess.run(["/usr/lib/qt6/bin/qmltestrunner", "-input", str(test)],
                                    env=env, capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotRegex(output, r"QWARN|TypeError|ReferenceError|Unable to assign")

    def test_selection_and_recording_state(self):
        source = SOURCE.read_text()
        names = ("startRecording", "selectRecordingArea", "finishRecordingSelection",
                 "toggleRecording", "shotStart", "shotClose")
        functions = "\n".join(function_source(source, name) for name in names)
        capture = function_source(source, "capture")
        script = r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const timer = () => ({starts: 0, stops: 0,
    restart() { this.starts++; }, stop() { this.stops++; }});
function fresh() {
    const state = {
        recording: false, recRun: false, recGuardUntil: 0, recSecs: 99,
        recordGeometry: '', recordOutput: '', recordFile: '',
        recordAudio: 'none', recordAudioActive: 'none',
        shotOpen: false, shotBusy: false, shotMode: 'screenshot', shotId: 0,
        shotTmp: '/tmp/test-runtime', shotSnap: {},
        recStartDelay: timer(), recSelectDelay: timer(), recKill: timer(),
        Hyprland: {focusedMonitor: {name: 'FOCUSED'}},
        Qt: {formatDateTime() { return '20261027-120000'; }},
        Quickshell: {screens: [{name: 'SECONDARY'}],
            env() { return '/home/test'; }, execDetached() {}},
    };
    state.root = state;
    vm.createContext(state);
    vm.runInContext(FUNCTIONS, state);
    return state;
}
let s = fresh();
s.selectRecordingArea();
assert.equal(s.recSelectDelay.starts, 1);
assert.equal(s.recording, false, 'selection must not start the recorder');
s.shotStart('record');
assert.equal(s.shotMode, 'record');
assert.equal(s.shotBusy, true);
assert.equal(s.shotSnap.running, true);
s.shotBusy = false; s.shotOpen = true;
s.shotClose(); // Escape and right-click both use this production cancellation.
assert.equal(s.shotMode, 'screenshot');
assert.equal(s.recording, false);
assert.equal(s.recStartDelay.starts, 0);

s = fresh(); s.shotOpen = true; s.shotMode = 'record';
// Negative output origin and a scale of two: geometry remains logical.
s.finishRecordingSelection({name:'LEFT', x:-1920, y:120,
    width:1920, height:1080, scale:2}, 10.4, 20.6, 301, 199);
assert.equal(s.recordGeometry, '-1910,141 301x199');
assert.equal(s.recordOutput, 'LEFT', 'use the selected output, not the focused one');
assert.equal(s.recording, true);
assert.equal(s.shotOpen, false, 'hide the picker before starting');
assert.equal(s.recStartDelay.starts, 1);
assert.equal(s.recSecs, 0);
s.startRecording('', 'OTHER');
assert.equal(s.recordOutput, 'LEFT', 'double start must not change the active command');

s = fresh(); s.shotOpen = true;
s.finishRecordingSelection({name:'A',x:0,y:0,width:100,height:100}, 20,20,1,1);
assert.equal(s.recording, false, 'ignore accidental tiny selections');
assert.equal(s.shotOpen, true);

s = fresh(); s.recordGeometry = 'stale'; s.recordOutput = 'stale';
s.toggleRecording();
assert.equal(s.recordGeometry, '', 'full-screen must clear the previous crop');
assert.equal(s.recordOutput, 'FOCUSED');
assert.equal(s.recording, true);
s.recGuardUntil = 0;
s.toggleRecording();
assert.equal(s.recording, false);
assert.equal(s.recStartDelay.stops, 1, 'stop must cancel a pending start');
s.recGuardUntil = 0; s.recRun = true;
s.startRecording('', 'OTHER');
assert.equal(s.recording, false, 'do not restart while the old recorder is finalizing');

s = fresh(); s.shotStart();
assert.equal(s.shotMode, 'screenshot', 'normal screenshot shortcuts keep their mode');

s = fresh(); s.shotMode = 'record'; s.shotOpen = true;
s.grabbing = false; s.grabTimer = timer();
s.shw = {modelData: {name:'A',x:0,y:0,width:1920,height:1080}};
vm.runInContext(CAPTURE, s);
s.capture(100, 200, 640, 480);
assert.equal(s.recordGeometry, '100,200 640x480');
assert.equal(s.grabTimer.starts, 0, 'recording must not crop or save a screenshot');
s = fresh(); s.grabbing = false; s.grabTimer = timer();
vm.runInContext(CAPTURE, s);
s.capture(100, 200, 640, 480);
assert.equal(s.grabTimer.starts, 1, 'screenshot capture keeps its normal path');
assert.equal(s.recording, false);
console.log('PASS: selection, cancellation, output geometry, duplicate guard, stop, screenshot compatibility');
'''.replace("FUNCTIONS", json.dumps(functions)).replace("CAPTURE", json.dumps(capture))
        result = subprocess.run(["node", "-e", script], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_recorder_arguments(self):
        source = SOURCE.read_text()
        command = source.split('id: recordProc\n', 1)[1].split('].join("\\n")', 1)[0]
        lines = re.findall(r"^\s*('.*?'),?\s*$", command, re.M)
        script = "\n".join(ast.literal_eval(line) for line in lines)
        self.assertIn('exec wf-recorder "$@"', script)
        with tempfile.TemporaryDirectory(prefix="recording-test-") as directory:
            base = Path(directory)
            fake = base / "wf-recorder"
            fake.write_text('#!/usr/bin/env python3\nimport json, sys\n'
                            'print("--framerate" if "--help" in sys.argv else json.dumps(sys.argv[1:]))\n')
            fake.chmod(0o755)
            env = dict(os.environ, PATH=str(base) + os.pathsep + os.environ["PATH"],
                       XDG_RUNTIME_DIR=directory)
            filename = str(base / "Videos with spaces" / "recording.mp4")
            for geometry in ("-1910,141 301x199", ""):
                with self.subTest(geometry=geometry):
                    result = subprocess.run(["sh", "-c", script, "sh", filename, "LEFT", geometry],
                                            env=env, capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    args = json.loads(result.stdout)
                    self.assertEqual(args[args.index("-f") + 1], filename)
                    self.assertEqual(args[args.index("-o") + 1], "LEFT")
                    self.assertEqual(args[args.index("-r") + 1], "60")
                    if geometry:
                        self.assertEqual(args[args.index("-g") + 1], geometry)
                        self.assertEqual(args[args.index("-F") + 1], "pad=ceil(iw/2)*2:ceil(ih/2)*2")
                    else:
                        self.assertNotIn("-g", args)
                        self.assertNotIn("-F", args)

    def test_recorder_audio_argument(self):
        """GG-08: the audio device is passed in the attached --audio=DEV form."""
        source = SOURCE.read_text()
        command = source.split('id: recordProc\n', 1)[1].split('].join("\\n")', 1)[0]
        script = "\n".join(ast.literal_eval(line)
                           for line in re.findall(r"^\s*('.*?'),?\s*$", command, re.M))
        # wf-recorder 0.6.0 silently records the default source for a separate
        # "-a DEV"; only the attached "--audio=DEV" form is accepted.
        self.assertIn('"--audio=$', script)
        self.assertNotIn('"-a"', script)
        # the chosen source travels with the start snapshot so a running
        # recorder cannot be re-routed by changing the setting
        self.assertIn("recordAudioActive", source)
        self.assertIn('"recordAudio"', source.split("settingKeys", 1)[1].split(";", 1)[0])


if __name__ == "__main__":
    unittest.main()
