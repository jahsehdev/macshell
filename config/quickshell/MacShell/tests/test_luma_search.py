"""Exercise the independent desktop search menu with real Qt controls."""
import os
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


SHELL = Path(__file__).resolve().parents[1]


class LumaSearchTests(unittest.TestCase):
    def test_backdrop_tracks_windows_on_selected_workspace(self):
        source = (SHELL / 'LumaSearchBackdrop.js').read_text().replace('.pragma library', '')
        script = r'''
const assert=require('node:assert/strict');
const vm=require('node:vm');
const context=vm.createContext({});
vm.runInContext(SOURCE,context);
const monitor={id:1,name:'LEFT',x:-1920,y:100,activeWorkspace:{id:2},specialWorkspace:{id:-99}};
const region={x:200,y:200,width:400,height:100};
function window(address,extra={}) {return {address,mapped:true,hidden:false,monitor:1,workspace:{id:2},at:[-1800,250],size:[600,300],floating:false,focusHistoryID:0,...extra};}
const clients=[window('tiled'),window('floating',{floating:true}),window('background',{floating:true,focusHistoryID:3}),
window('special',{workspace:{id:-99}}),window('otherWorkspace',{workspace:{id:3}}),window('otherScreen',{monitor:0}),
window('closed',{mapped:false}),window('hidden',{hidden:true}),window('outside',{at:[0,0]})];
let result=Array.from(context.windowsForRegion(clients,monitor,region));
assert.deepEqual(result.map(w=>w.addr),['tiled','floating','background','special']);
assert.equal(result[1].wx,120); assert.equal(result[1].wy,150);
assert.ok(result[1].wz>result[0].wz); assert.ok(result[1].wz>result[2].wz);
assert.equal(context.windowsForRegion(clients,null,region).length,0);
clients[1].at=[-1000,600];
result=Array.from(context.windowsForRegion(clients,monitor,region));
assert.ok(!result.some(w=>w.addr==='floating'),'moving away removes a window from capture');
monitor.activeWorkspace.id=3; monitor.specialWorkspace.id=0;
assert.deepEqual(Array.from(context.windowsForRegion(clients,monitor,region)).map(w=>w.addr),['otherWorkspace']);
'''.replace('SOURCE', json.dumps(source))
        result = subprocess.run(['node', '-e', script], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_menu_is_independent(self):
        shell = (SHELL / 'shell.qml').read_text()
        bar = (SHELL / 'UpstreamBar/MacBar.qml').read_text()
        menu = (SHELL / 'LumaSearchMenu.qml').read_text()
        self.assertIn('LumaSearchMenu { controller: lumaAi; hub: sharedHub }', shell)
        self.assertNotIn('id: lumaWin', bar)
        self.assertNotIn('function onQuickRequested()', bar)
        self.assertIn('id: lumaGoo', bar)
        self.assertIn('target: "lumasearch"', menu)
        self.assertIn('function onQuickRequested() { root.toggle(); }', menu)
        self.assertNotIn('ui.pop', menu)
        self.assertNotIn('lumaMenuEnabled', menu)
        self.assertIn('maclumasearch', menu)
        config = (SHELL.parents[1] / 'hypr/hyprland.lua').read_text()
        self.assertIn('hl.bind("SUPER + SHIFT + Space", hl.dsp.exec_cmd(qs .. "lumasearch toggle"))', config)

    def test_centered_panel_and_keyboard(self):
        source = (SHELL / 'LumaSearchMenu.qml').read_text()
        popup = re.search(r'^(?P<indent> +)Item \{\n\s*id: menu\n.*?^(?P=indent)}', source, re.M | re.S)[0]
        popup = popup.replace('sourceComponent: LumaSearchView {', 'sourceComponent: LocalEffects.LumaSearchView {')
        popup = popup.replace('sourceComponent: LocalEffects.LumaSearchView {', 'sourceComponent: LocalEffects.LumaSearchView {\n dictationEnabled: false; voiceBackend: Qt.resolvedUrl("MockVoice.qml"); microphoneBackend: Qt.resolvedUrl("MockMicrophone.qml")')
        qml = r'''
import QtQuick
import QtTest
import "SHELL" as LocalEffects
Item {
    id: root; width: 800; height: 600
    property bool opened: false
    property var controller: ctl
    property var hub: null
    function close() { opened=false; }
    QtObject {
        id: ctl
        property bool connected: true
        property bool ready: true
        property string busy: ""
        property string error: ""
        property string response: ""
        property string draft: ""
        property string stage: ""
        property var messages: []
        property int submitted: 0
        function submit() { submitted++; draft=""; busy="chat"; }
        function send(value) { if (value.action === "stop") busy=""; }
        function open(value) {}
        function settings() {}
    }
    QtObject {
        id: win
        readonly property bool selected: root.opened
        onSelectedChanged: if (selected && content.item) content.item.resetMessages()
        readonly property bool openish: selected || menu.opacity>0.001
        property var modelData: ({name:"TEST"})
    }
    Item {
        id: frame; anchors.fill: parent
        Loader { id: liveBackdrop; active: false }
        MouseArea { anchors.fill: parent; enabled: win.selected; onPressed: root.close() }
        // The real menu defines the context bridge outside the popup block;
        // the harness stands in for it so the view bindings resolve.
        QtObject {
            id: contextSearch
            property var results: []
            property bool searching: false
            function activate(result) {}
        }
        POPUP
    }
    TestCase {
        name: "LumaSearch"; when: windowShown
        function init() {
            root.opened=false; tryCompare(menu,"opacity",0,500);
            if (content.item) content.item.dictationEnabled=false;
            root.width=800; root.height=600;
            ctl.ready=true; ctl.busy=""; ctl.error=""; ctl.response=""; ctl.draft=""; ctl.messages=[];
            ctl.submitted=0;
            root.opened=true;
            tryCompare(menu,"scale",1,700);
            tryCompare(menu,"opacity",1,500);
            wait(40); // Commit the final transition frame before pixel/focus assertions.
            content.item.focusInput();
            tryVerify(() => findChild(menu,"lumaSearchInput").activeFocus, 200);
        }
        function test_emptyCapsuleAndFocus() {
            compare(menu.width,380); compare(menu.x,210); compare(menu.y,60);
            compare(menu.height,60); compare(content.item.showBody,false);
            const input=findChild(menu,"lumaSearchInput");
            compare(input.placeholderText,"Search or Ask"); verify(input.activeFocus);
        }
        function test_typingWorksWithoutInstalledModel() {
            // The gated model may be absent: the field must still accept text
            // and Enter must not be swallowed silently.
            ctl.ready=false;
            const input=findChild(menu,"lumaSearchInput");
            verify(input.enabled,"search field accepts typing without a model");
            input.text="spotify";
            compare(ctl.draft,"spotify");
            compare(ctl.submitted,0);
            keyClick(Qt.Key_Return);
            compare(ctl.submitted,0);
            verify(findChild(menu,"lumaSearchAnswer").visible,"install hint stays visible");
            ctl.ready=true;
        }
        function test_noMessageCardFromHistoryWithoutAnswer() {
            // Old conversation history must not open the message card by
            // itself; the card belongs to a live answer or an explicit action.
            ctl.ready=false;
            ctl.messages=[{role:"user",content:"coba kamu bukan in saya spotify app"}];
            compare(content.item.showBody,false);
            compare(findChild(menu,"lumaSearchAnswer").visible,false);
            compare(menu.height,60);
            ctl.ready=true;
        }
        function test_composedCapsuleKeepsFullRenderedSize() {
            const previousLayer=surface.layer.enabled;
            surface.layer.enabled=true;
            verify(surface.layer.enabled,"exercise the composed layer on the test renderer too");
            const glass=findChild(menu,"lumaInputGlass");
            const pane=Qt.createQmlObject('import QtQuick; Rectangle { anchors.fill: parent; radius: 30; color: "#00ff00" }',glass);
            wait(30);
            const image=grabImage(root);
            const cx=menu.x+menu.width/2, cy=menu.y+menu.height/2;
            function capsuleAt(x,y) {
                const pixel=Qt.color(image.pixel(x,y));
                return pixel.g>pixel.r+0.01 && pixel.g>pixel.b+0.01;
            }
            verify(capsuleAt(cx,menu.y+2),"capsule reaches its full top edge");
            verify(capsuleAt(cx,menu.y+menu.height-3),"capsule reaches its full bottom edge");
            verify(capsuleAt(menu.x+2,cy),"capsule reaches its full left edge");
            verify(capsuleAt(menu.x+menu.width-3,cy),"capsule reaches its full right edge");
            verify(!capsuleAt(cx,menu.y-3) && !capsuleAt(cx,menu.y+menu.height+3),"padding must stay outside the capsule");
            pane.destroy();
            surface.layer.enabled=previousLayer;
        }
        function test_gradientStaysAboveLateGlassContent() {
            const glass=findChild(menu,"lumaInputGlass");
            const gradient=findChild(menu,"lumaTopGradient");
            verify(gradient.z>glass.z);
            const pane=Qt.createQmlObject('import QtQuick; Rectangle { anchors.fill: parent; radius: 30; color: "white" }',glass);
            wait(30);
            const image=grabImage(root);
            const top=Qt.color(image.pixel(menu.x+190,menu.y+5)), bottom=Qt.color(image.pixel(menu.x+190,menu.y+55));
            verify(top.r<0.15 && top.g<0.15 && top.b<0.15,"top remains black above late-created glass: " + top + ", bottom: " + bottom + ", image: " + image.width + "x" + image.height);
            verify(bottom.r>top.r+0.5,"gradient fades downward");
            pane.destroy();
        }
        function test_sendAndAnswer() {
            const input=findChild(menu,"lumaSearchInput");
            input.text="Halo Luma"; keyClick(Qt.Key_Return);
            compare(ctl.submitted,1); compare(ctl.busy,"chat");
            verify(content.item.showBody); verify(menu.height>60);
            compare(menu.y,60);
            ctl.response="Halo!"; ctl.busy="";
            verify(findChild(menu,"lumaSearchAnswer").visible);
        }
        function test_micChangesToSend() {
            const input=findChild(menu,"lumaSearchInput"), button=findChild(menu,"lumaSearchSend");
            const mic=findChild(menu,"lumaSearchMic");
            const sendIcon=findChild(menu,"lumaSearchSendIcon");
            compare(button.iconState,"mic"); verify(mic.visible);
            compare(sendIcon.visible,false);
            input.text="Halo";
            compare(button.iconState,"send"); compare(mic.visible,false); verify(button.enabled);
            verify(sendIcon.visible);
            input.text="   ";
            compare(button.iconState,"mic"); verify(mic.visible);
            input.text="Halo";
            mouseClick(button,16,16);
            compare(ctl.submitted,1); compare(button.iconState,"stop");
            ctl.busy="";
            compare(button.iconState,"mic"); verify(mic.visible);
        }
        function test_microphoneClickShowsOrbAndStopsOnClose() {
            const view=content.item, button=findChild(menu,"lumaSearchSend");
            compare(view.listening,false); verify(button.enabled);
            mouseClick(button,16,16);
            compare(view.listening,true);
            compare(view.micVolume,0.65);
            const orb=findChild(menu,"lumaMicrophonePane"), glass=findChild(menu,"lumaInputGlass");
            tryCompare(view,"voiceProgress",1,850);
            verify(orb.visible); compare(menu.height,74); compare(menu.y,60);
            compare(orb.micVolume,0.65); compare(orb.width,88); compare(orb.height,88);
            compare(glass.width,glass.height); compare(glass.radius,44);
            compare(findChild(menu,"lumaSearchControls").visible,false);
            root.opened=false;
            compare(view.listening,false); compare(view.micVolume,0);
            root.opened=true; tryCompare(menu,"opacity",1,500);
            compare(view.listening,false);
            tryCompare(orb,"visible",false,850);
            compare(menu.height,60);
        }
        function test_missingSpeechModelKeepsOrbOpen() {
            const view=content.item, button=findChild(menu,"lumaSearchSend");
            view.dictationEnabled=true;
            // The optional recognizer fails just after the microphone is clicked.
            // Its failure must not cancel the independent microphone visualizer.
            for (let attempt=0; attempt<2; attempt++) {
                mouseClick(button,16,16);
                tryCompare(view.voice,"state","error",500);
                tryCompare(view,"voiceProgress",1,850);
                verify(view.listening,"missing speech model must leave the orb open");
                compare(view.micVolume,0.65);
                verify(view.voice.active);
                const orb=findChild(menu,"lumaMicrophonePane");
                verify(orb.visible); compare(orb.opacity,1);
                const status=findChild(menu,"lumaMicrophoneStatus");
                verify(status.visible); compare(status.text,"Offline speech model unavailable.");
                keyClick(Qt.Key_Escape);
                compare(view.listening,false); compare(view.micVolume,0);
                compare(view.voice.active,false);
                tryCompare(view,"voiceProgress",0,850);
                verify(findChild(menu,"lumaSearchInput").activeFocus);
            }
            mouseClick(button,16,16);
            tryCompare(view.voice,"state","error",500);
            root.opened=false;
            compare(view.listening,false); compare(view.micVolume,0);
            compare(view.voice.active,false);
        }
        function test_orbClickAndEscapeRestoreSearch() {
            const view=content.item, button=findChild(menu,"lumaSearchSend");
            mouseClick(button,16,16); verify(view.listening);
            tryCompare(view,"voiceProgress",1,850);
            const orb=findChild(menu,"lumaMicrophoneOrbButton");
            mouseClick(orb,orb.width/2,orb.height/2);
            compare(view.listening,false); compare(view.micVolume,0);
            tryCompare(view,"voiceProgress",0,850);
            const input=findChild(menu,"lumaSearchInput");
            verify(input.activeFocus); verify(input.visible); verify(input.enabled);
            mouseClick(button,16,16); verify(view.listening);
            keyClick(Qt.Key_Escape);
            compare(view.listening,false); compare(view.micVolume,0);
            compare(root.opened,true,"escape from voice returns to search");
            tryCompare(view,"voiceProgress",0,850);
            tryVerify(function() { return input.activeFocus; },500);
            keyClick(Qt.Key_A);
            compare(button.iconState,"send");
        }
        function test_capsuleMorphKeepsCenterAndReusesGlass() {
            const view=content.item, glass=findChild(menu,"lumaInputGlass");
            const controls=findChild(menu,"lumaSearchControls");
            const captureSize=glass.captureSize;
            mouseClick(findChild(menu,"lumaSearchSend"),16,16);
            let sawShortPill=false, sawCircle=false;
            const start=Date.now();
            while (Date.now()-start<620) {
                wait(16);
                compare(findChild(menu,"lumaInputGlass"),glass,"one glass surface throughout morph");
                fuzzyCompare(glass.x+glass.width/2,190,0.01);
                fuzzyCompare(glass.y+glass.height/2,30,0.01);
                verify(glass.width>=glass.height-0.01,"capsule never becomes a vertical oval");
                compare(glass.captureSize,captureSize,"blur texture does not resize each frame");
                if (glass.width>120 && glass.width<330 && glass.height<70) sawShortPill=true;
                if (view.voiceReveal>0.01) { compare(controls.visible,false); sawCircle=true; }
            }
            verify(sawShortPill,"search bar shortens before revealing voice");
            verify(sawCircle,"voice appears after capsule becomes round");
            compare(glass.width,88); compare(glass.height,88);
            const wave=findChild(menu,"lumaMicWaveFallback");
            const mapped=wave.mapToItem(view,wave.width/2,wave.height/2);
            fuzzyCompare(mapped.x,190,0.01); fuzzyCompare(mapped.y,30,0.01);
        }
        function test_reverseMorphDoesNotJump() {
            const view=content.item, glass=findChild(menu,"lumaInputGlass");
            mouseClick(findChild(menu,"lumaSearchSend"),16,16);
            wait(200);
            verify(view.voiceProgress>0 && view.voiceProgress<1);
            const width=glass.width, height=glass.height, progress=view.voiceProgress;
            keyClick(Qt.Key_Escape);
            fuzzyCompare(view.voiceProgress,progress,0.001);
            fuzzyCompare(glass.width,width,0.5); fuzzyCompare(glass.height,height,0.5); // Subpixel render-thread timing is not a visible geometry jump.
            tryCompare(view,"voiceProgress",0,850);
            compare(glass.width,380); compare(glass.height,60);
        }
        function test_historyHiddenOnOpenAndRapidReopen() {
            const history=[{role:"user",content:"Pesan lama"},{role:"assistant",content:"Jawaban lama"}];
            ctl.messages=history;
            compare(menu.height,60); compare(content.item.showBody,false);
            compare(ctl.messages,history,"keep conversation history intact");
            const input=findChild(menu,"lumaSearchInput");
            input.text="Pesan baru"; keyClick(Qt.Key_Return);
            verify(content.item.showBody);
            ctl.response="Jawaban baru"; ctl.busy="";
            root.opened=false; wait(35); root.opened=true; wait(20);
            compare(content.item.showBody,false); compare(menu.height,60);
            compare(ctl.messages,history);
        }
        function test_escapeAndReopen() {
            const cachedView=content.item;
            keyClick(Qt.Key_Escape); compare(root.opened,false);
            tryCompare(menu,"opacity",0,500);
            compare(menu.visible,false);
            compare(content.item,cachedView,"keep glass resources between openings");
            root.opened=true; tryCompare(menu,"scale",1,700);
            compare(content.item,cachedView);
            content.item.focusInput();
            verify(findChild(menu,"lumaSearchInput").activeFocus);
        }
        function test_revealCompletesQuicklyWithoutOvershoot() {
            root.opened=false; tryCompare(menu,"opacity",0,500);
            const cachedView=content.item;
            let previousOpacity=0, peakScale=0, intermediate=false;
            root.opened=true;
            const start=Date.now();
            while (Date.now()-start<140) {
                wait(16);
                verify(menu.opacity>=previousOpacity-0.001,"fade must not blink backwards");
                verify(menu.opacity>=0 && menu.opacity<=1,"opacity never bounces");
                if (menu.opacity>0.05 && menu.opacity<0.95) intermediate=true;
                previousOpacity=menu.opacity;
                peakScale=Math.max(peakScale,menu.scale);
                compare(content.item,cachedView);
            }
            verify(intermediate,"opening must fade through intermediate frames");
            verify(peakScale<=1.001,"instant expansion must not overshoot: "+peakScale);
            fuzzyCompare(menu.opacity,1,0.001); fuzzyCompare(menu.scale,1,0.001);
        }
        function test_reopeningDuringCloseKeepsCurrentAnimation() {
            const cachedView=content.item;
            root.opened=false; wait(45);
            verify(menu.opacity>0 && menu.opacity<1);
            const opacity=menu.opacity, scale=menu.scale;
            root.opened=true;
            fuzzyCompare(menu.opacity,opacity,0.001);
            fuzzyCompare(menu.scale,scale,0.001);
            compare(content.item,cachedView);
            tryVerify(() => Math.abs(menu.scale-1)<0.001 && Math.abs(menu.opacity-1)<0.001,180);
        }
        function test_outsideClick() {
            mouseClick(frame,12,12); compare(root.opened,false);
        }
        function test_setupAndSmallDisplay() {
            // No model: an idle menu stays a bare capsule, no message card.
            ctl.ready=false;
            compare(content.item.showBody,false);
            // A live answer grows the panel; it must still fit the small screen.
            ctl.ready=true;
            const input=findChild(menu,"lumaSearchInput");
            input.text="halo"; keyClick(Qt.Key_Return);
            verify(content.item.showBody);
            root.width=360; root.height=480; wait(10);
            compare(menu.width,312); compare(menu.x,24);
            verify(menu.y+menu.height<=root.height);
        }
    }
}
'''.replace('SHELL', SHELL.as_uri()).replace('POPUP', popup)
        with tempfile.TemporaryDirectory(prefix='luma-search-test-') as directory:
            base = Path(directory)
            runtime = base / 'runtime'
            runtime.mkdir(mode=0o700)
            test = base / 'tst_luma.qml'
            test.write_text(qml)
            (base / 'MockMicrophone.qml').write_text('import QtQuick; QtObject { property bool active: false; property real volume: active ? 0.65 : 0; property bool connected: active; property string error: "" }')
            (base / 'MockVoice.qml').write_text('''import QtQuick
Item {
    id: voice
    property bool active: false
    property string state: "idle"
    property string error: ""
    signal transcript(string text)
    signal unavailable()
    function cancel() { state="idle"; }
    onActiveChanged: if (active) { error=""; state="starting"; failure.restart(); }
    Timer {
        id: failure; interval: 10
        onTriggered: {
            voice.error="Offline speech model unavailable.";
            voice.state="error";
            voice.unavailable();
        }
    }
}''')
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(runtime))
            result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-input', str(test)],
                                    env=env, capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotRegex(output, r'QWARN|TypeError|ReferenceError|Unable to assign')


if __name__ == '__main__':
    unittest.main()
