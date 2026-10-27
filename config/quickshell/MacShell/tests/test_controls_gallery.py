"""Exercise the real gallery and production layout/pin functions in Qt Quick."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SHELL = Path(__file__).resolve().parents[1]


def function(source, name):
    start = source.index('    function ' + name + '(')
    opening = source.index('{', start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


class ControlsGalleryTests(unittest.TestCase):
    def test_render_and_interaction(self):
        source = Path(os.environ.get('MACSHELL_CONTROL_SOURCE', SHELL / 'UpstreamBar/MacBar.qml')).read_text()
        functions = '\n'.join(function(source, name) for name in (
            'nativeControlWidget', 'controlPinned', 'pinControl', 'moveControlPin',
            'resizeControl', 'barWidgetEnabled', 'setBarWidget', 'ccDef', 'ccLayout',
            'ccAdd', 'ccRemove', 'ccDrop', 'saveSettings', 'applySettings'))
        qml = r'''
import QtQuick
import QtTest
import "SHELL" as Shell
import "SHELL/ControlCatalog.js" as ControlCatalog
Item {
    id: host
    width: 620; height: 740
    QtObject {
        id: root
        property var ccControls: []
        property var ccSizes: ({})
        property var barControlPins: []
        property var barWidgets: ["wifi", "bluetooth", "volume"]
        property real ccGap: 6
        property real ccSliderGap: 10
        property real ccCellH: 66
        readonly property var ccPlan: ccLayout(ccControls)
        readonly property var settingKeys: ["ccControls", "ccSizes", "barControlPins", "barWidgets"]
        readonly property string settingsSig: SETTINGSSIG
        FUNCTIONS
    }
    QtObject { id: store; property string saved: ""; function setText(value) { saved = value; } }
    Shell.ControlsGallery {
        id: gallery
        x: 24; y: 20; width: 570; height: 690
        controller: root; dragLayer: host
    }
    SignalSpy { id: drops; target: gallery; signalName: "controlDropped" }
    SignalSpy { id: drags; target: gallery; signalName: "controlDragged" }
    SignalSpy { id: finishes; target: gallery; signalName: "finished" }
    TestCase {
        name: "ControlsGallery"
        when: windowShown
        function init() {
            gallery.width = 570;
            root.ccControls = []; root.ccSizes = ({}); root.barControlPins = [];
            root.barWidgets = ["wifi", "bluetooth", "volume"];
            gallery.category = "all"; gallery.dark = false;
            findChild(gallery,"controlSearch").text = "";
            gallery.closeActions();
            gallery.forceActiveFocus(Qt.OtherFocusReason);
            gallery.message = "Drag controls to Control Center or the menu bar.";
            drops.clear(); drags.clear(); finishes.clear(); wait(40);
        }
        function test_searchAndEmptyResults() {
            var input=findChild(gallery,"controlSearch");
            mouseClick(input,20,5); keySequence("S,T,O,P,W,A,T,C,H");
            compare(gallery.sections.length,1);
            compare(gallery.sections[0].controls.length,1);
            compare(gallery.sections[0].controls[0].id,"stopwatch");
            input.text="no-such-control";
            compare(gallery.sections.length,0);
            keyClick(Qt.Key_Escape); compare(input.text,"");
        }
        function test_addRemoveAndPinMenu() {
            gallery.category="clock"; wait(30);
            var card=findChild(gallery,"galleryMouse_timer"); verify(card);
            mouseClick(card,20,20); wait(20);
            var menu=findChild(gallery,"controlActions"); compare(menu.visible,true);
            mouseClick(findChild(gallery,"controlAction_cc"),20,15);
            compare(root.ccControls.join(","),"timer");
            mouseClick(card,20,20); wait(20);
            mouseClick(findChild(gallery,"controlAction_bar"),20,15);
            compare(root.barControlPins.join(","),"timer");
            mouseClick(card,20,20,Qt.RightButton); wait(20);
            mouseClick(findChild(gallery,"controlAction_cc"),20,15);
            compare(root.ccControls.length,0);
            verify(root.controlPinned("timer"));
        }
        function test_sizesRepackAndSerialize() {
            root.ccAdd("timer"); root.ccAdd("sound"); root.ccAdd("nowplaying");
            root.resizeControl("timer","large");
            root.resizeControl("sound","medium");
            root.resizeControl("nowplaying","large");
            compare(root.ccDef("timer").w,2); compare(root.ccDef("timer").h,2);
            compare(root.ccDef("sound").w,2); compare(root.ccDef("nowplaying").w,4);
            var seen={}; root.ccPlan.items.forEach(function(slot){
                for(var y=slot.row;y<slot.row+slot.h;y++) for(var x=slot.col;x<slot.col+slot.w;x++) {
                    var key=x+","+y; verify(!seen[key],"Controls must not overlap"); seen[key]=true;
                }
            });
            root.ccSizes=JSON.parse(JSON.stringify(root.ccSizes));
            compare(root.ccDef("timer").h,2);
            gallery.showActions("timer",300,220); wait(20);
            mouseClick(findChild(gallery,"controlAction_small"),20,15);
            compare(root.ccDef("timer").w,1); compare(root.ccDef("timer").h,1);
        }
        function test_nativePinsDoNotDuplicateAndOrderIsStable() {
            verify(root.controlPinned("wifi"));
            root.pinControl("wifi",true);
            verify(!root.barWidgetEnabled("wifi")); compare(root.barControlPins.join(","),"wifi");
            root.pinControl("wifi",true); compare(root.barControlPins.length,1);
            root.pinControl("timer",true); root.moveControlPin("timer",-1);
            compare(root.barControlPins.join(","),"timer,wifi");
            root.barControlPins=JSON.parse(JSON.stringify(root.barControlPins));
            compare(root.barControlPins.join(","),"timer,wifi");
            root.pinControl("wifi",false); verify(!root.controlPinned("wifi"));
            root.pinControl("unknown",true); compare(root.barControlPins.join(","),"timer");
        }
        function test_savedConfigurationRestoresPinsOrderAndSizes() {
            root.ccAdd("timer"); root.ccAdd("sound"); root.ccAdd("screenshot");
            root.pinControl("timer",true); root.pinControl("sound",true); root.moveControlPin("sound",-1);
            var before = root.settingsSig;
            root.resizeControl("timer","large"); verify(root.settingsSig !== before);
            root.saveSettings();
            var saved = store.saved; verify(saved.indexOf('"large"') >= 0);
            root.ccControls=[]; root.barControlPins=[]; root.ccSizes=({}); root.barWidgets=[];
            root.applySettings(JSON.parse(saved),root.settingKeys);
            compare(root.ccControls.join(","),"timer,sound,screenshot");
            compare(root.barControlPins.join(","),"sound,timer");
            compare(root.ccDef("timer").h,2);
            verify(!root.barWidgetEnabled("volume"));
        }
        function test_dragReportsDestinationAndClickDoesNotDrag() {
            gallery.category="clock"; wait(30);
            var card=findChild(gallery,"galleryMouse_timer");
            mousePress(card,20,20); mouseMove(card,80,20,50); mouseMove(card,100,-30,50); mouseRelease(card,100,-30);
            compare(drops.count,1); verify(drags.count>0); compare(drops.signalArguments[0][0],"timer");
            compare(gallery.dragging,false);
            drops.clear(); mouseClick(card,20,20); compare(drops.count,0);
        }
        function test_categoryAndDone() {
            mouseClick(findChild(gallery,"controlCategory_display"),25,15);
            compare(gallery.category,"display");
            compare(gallery.sections.length,1); compare(gallery.sections[0].controls.length,3);
            mouseClick(findChild(gallery,"galleryDone"),20,10);
            compare(finishes.count,1);
        }
        function test_keyboardActions() {
            var category=findChild(gallery,"controlCategory_connectivity");
            category.forceActiveFocus(Qt.TabFocusReason); keyClick(Qt.Key_Space);
            compare(gallery.category,"connectivity");
            var card=findChild(gallery,"galleryControl_wifi").parent;
            card.forceActiveFocus(Qt.TabFocusReason); keyClick(Qt.Key_Space);
            compare(findChild(gallery,"controlActions").visible,true);
            keyClick(Qt.Key_Escape); compare(findChild(gallery,"controlActions").visible,false);
            findChild(gallery,"galleryDone").forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return); compare(finishes.count,1);
        }
        function test_compactLayoutAndSearch() {
            gallery.width=330; gallery.category="connectivity"; wait(80);
            ["wifi","bluetooth","airplane"].forEach(function(id) {
                var control=findChild(gallery,"galleryControl_"+id); verify(control);
                var p=control.mapToItem(gallery,0,0);
                verify(p.x>=gallery.sidebarWidth && p.x+control.width<=gallery.width);
                verify(control.width>=50 && control.height>=50);
            });
            mouseClick(findChild(gallery,"galleryMouse_wifi"),25,25); wait(30);
            var menu=findChild(gallery,"controlActions"); verify(menu.visible);
            verify(menu.x>=0 && menu.x+menu.width<=gallery.width);
            verify(menu.y>=0 && menu.y+menu.height<=gallery.height);
            gallery.closeActions();
            var input=findChild(gallery,"controlSearch");
            input.text="Bluetooth"; compare(gallery.sections[0].controls.length,1);
            mouseClick(findChild(gallery,"clearControlSearch"),10,10);
            compare(input.text,""); compare(gallery.sections[0].controls.length,3);
            verify(input.activeFocus);
        }
        function test_renderBothThemes() {
            wait(150); grabImage(host).save("/tmp/macshell-controls-light.png");
            gallery.dark=true; wait(140);
            grabImage(host).save("/tmp/macshell-controls-dark.png");
            root.ccControls=["wifi","bluetooth","airplane"];
            gallery.category="connectivity"; wait(150);
            grabImage(host).save("/tmp/macshell-controls-connectivity-dark.png");
            mouseClick(findChild(gallery,"galleryMouse_wifi"),25,25); wait(150);
            grabImage(host).save("/tmp/macshell-controls-menu-dark.png");
            gallery.closeActions(); gallery.dark=false; wait(150);
            grabImage(host).save("/tmp/macshell-controls-connectivity-light.png");
            gallery.width=330; wait(150);
            grabImage(host).save("/tmp/macshell-controls-compact-light.png");
        }
    }
}
'''.replace('SHELL', SHELL.as_uri()).replace('FUNCTIONS', functions).replace('SETTINGSSIG', source.split('readonly property string settingsSig: ', 1)[1].split('\n', 1)[0])
        with tempfile.TemporaryDirectory(prefix='macshell-controls-test-') as temporary:
            task = Path(temporary)
            runtime = task/'runtime'; runtime.mkdir(mode=0o700)
            test = task/'tst_controls.qml'; test.write_text(qml)
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       XDG_RUNTIME_DIR=str(runtime))
            result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-input',str(test)],
                                    env=env,capture_output=True,text=True,timeout=30)
            output=result.stdout+result.stderr
            print(output)
            self.assertEqual(result.returncode,0,output)
            self.assertNotRegex(output,r'(QWARN|TypeError|ReferenceError|Unable to assign|is not a function)')


if __name__=='__main__':
    unittest.main()
