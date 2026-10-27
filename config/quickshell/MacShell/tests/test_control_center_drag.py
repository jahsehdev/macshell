"""Exercise the production tile delegate and shared preview during pointer drags."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_launchpad_menubar import qml_block


SHELL = Path(__file__).resolve().parents[1]


class ControlCenterDragTests(unittest.TestCase):
    def test_original_tile_and_pointer_lifecycle(self):
        source = (SHELL / "UpstreamBar/MacBar.qml").read_text()
        qml = r'''
import QtQuick
import QtTest
import "SHELL" as LocalEffects
import "SHELL/ControlCatalog.js" as ControlCatalog
Item {
    id: root
    width: 640; height: 320
    property bool effDark: false
    property real ccGap: 6
    property real barHeight: 28
    property int dropped: 0
    property int removed: 0
    property int pinned: 0
    property var ccCatalog: [{id:"record"}, {id:"timer"}]
    property var ccPlan: ({items:[
        {id:"record", col:0, row:0, y:0, w:2, h:1, hpx:66},
        {id:"timer", col:2, row:0, y:0, w:1, h:1, hpx:66}
    ]})
    function ccDrop() { dropped++; }
    function ccRemove() { removed++; }
    QtObject { id: ccPal; property bool dark: false }
    Item {
        id: controlsGallery
        property int menus: 0
        function closeActions() {}
        function showActions() { menus++; }
    }
    Component {
        id: sampleControl
        Rectangle {
            color: "#aaaaaa"; radius: 30
            Text { anchors.centerIn: parent; text: "Record Screen"; color: "white" }
        }
    }
    QtObject {
        id: cc
        property int openSeq: 0
        property bool opening: true
        property bool visible: true
        function ccComp(id) { return sampleControl; }
    }
    Item {
        id: ui
        anchors.fill: parent
        property bool ccEdit: true
        property string ccDragId: ""
        property Item ccDragTile: null
        onCcDragIdChanged: if (ccDragId === "") ccDragTile = null
        property point ccDragPoint: Qt.point(0,0)
        function dropControl() { root.pinned++; }
        PREVIEW
        Item {
            id: ccGrid
            x: 20; y: 70; width: 300; height: 200
            readonly property real cw: (width - 3 * root.ccGap) / 4
            readonly property real chh: 66
            Repeater {
                model: root.ccCatalog
                DELEGATE
            }
        }
    }
    TestCase {
        name: "ControlCenterDrag"
        when: windowShown
        function init() {
            ui.ccEdit = true;
            root.dropped=0; root.removed=0; root.pinned=0; controlsGallery.menus=0;
            wait(220);
        }
        function test_originalTileDrag_data() {
            return [{tag:"wide", id:"record"}, {tag:"circle", id:"timer"}];
        }
        function test_hiddenControlsReleaseAndRecreate() {
            const content = findChild(ui, "ccControlContent_record");
            verify(content.item !== null);
            cc.opening = false;
            compare(content.active, true, "keep controls through the closing animation");
            cc.visible = false;
            compare(content.item, null, "release hidden control content, keep its slot");
            cc.opening = true;
            cc.visible = true;
            verify(content.item !== null, "restore the control when reopened");
        }
        function test_originalTileDrag(data) {
            var content=findChild(ui,"ccControlContent_"+data.id);
            var badge=findChild(ui,"ccRemoveBadge_"+data.id);
            verify(content); verify(badge);
            verify(content.visible); verify(badge.visible); verify(!ccDragPreview.visible);
            var tile=content.parent;
            var start=tile.mapToItem(ui,tile.width/2,tile.height/2);
            mousePress(ui,start.x,start.y);
            mouseMove(ui,start.x+35,start.y+18,40);
            tryCompare(tile,"dragging",true);
            compare(ui.ccDragId,data.id);
            compare(ui.ccDragTile,tile);
            verify(!ccDragPreview.visible);
            verify(content.visible); verify(badge.visible);
            verify(tile.dx>0 && tile.dy>0,"The original control follows the pointer");
            verify(tile.visible,"The drag owner must retain the pointer grab");
            grabImage(root).save("/tmp/macshell-single-drag-"+data.id+".png");
            mouseRelease(ui,start.x+35,start.y+18);
            tryCompare(tile,"dragging",false);
            verify(!ccDragPreview.visible); verify(content.visible); verify(badge.visible);
            compare(ui.ccDragId,""); compare(root.dropped,1); compare(controlsGallery.menus,0);
            compare(ui.ccDragTile,null);
            tryCompare(tile,"dx",0); tryCompare(tile,"dy",0);
        }
        function test_clickStillOpensActions() {
            var tile=findChild(ui,"ccControlContent_record").parent;
            mouseClick(tile,tile.width/2,tile.height/2);
            compare(controlsGallery.menus,1); compare(root.dropped,0);
            verify(!ccDragPreview.visible);
        }
        function test_dragOutsideRemovesControl() {
            var content=findChild(ui,"ccControlContent_record");
            var tile=content.parent;
            var start=tile.mapToItem(ui,tile.width/2,tile.height/2);
            mousePress(ui,start.x,start.y);
            mouseMove(ui,500,150,40);
            tryCompare(tile,"dragging",true); verify(content.visible); verify(!ccDragPreview.visible);
            mouseRelease(ui,500,150);
            compare(root.removed,1); compare(root.dropped,0);
            verify(content.visible); verify(!ccDragPreview.visible);
        }
        function test_cancelRestoresControl() {
            var content=findChild(ui,"ccControlContent_record");
            var tile=content.parent;
            var start=tile.mapToItem(ui,tile.width/2,tile.height/2);
            mousePress(ui,start.x,start.y);
            mouseMove(ui,start.x+35,start.y+18,40);
            tryCompare(tile,"dragging",true);
            ui.ccEdit=false;
            tryCompare(tile,"dragging",false);
            verify(content.visible); verify(!ccDragPreview.visible);
            compare(root.dropped,0); compare(root.removed,0);
            mouseRelease(ui,start.x+35,start.y+18);
        }
        function test_dragToMenubar() {
            var content=findChild(ui,"ccControlContent_record");
            var tile=content.parent;
            var start=tile.mapToItem(ui,tile.width/2,tile.height/2);
            mousePress(ui,start.x,start.y);
            mouseMove(ui,180,14,40);
            tryCompare(tile,"dragging",true);
            verify(content.visible); verify(!ccDragPreview.visible);
            mouseRelease(ui,180,14);
            compare(root.pinned,1); compare(root.dropped,0); compare(root.removed,0);
            verify(content.visible); verify(!ccDragPreview.visible);
        }
        function test_externalDragKeepsPreview() {
            compare(ui.ccDragTile,null);
            ui.ccDragId="timer";
            verify(ccDragPreview.visible,"Gallery and menu bar drags keep their preview");
            ui.ccDragId="";
            verify(!ccDragPreview.visible);
        }
    }
}
'''.replace("SHELL", SHELL.as_uri()).replace(
            "PREVIEW", qml_block(source, "ccDragPreview")
        ).replace("DELEGATE", qml_block(source, "ct"))
        with tempfile.TemporaryDirectory(prefix="control-center-drag-") as directory:
            task = Path(directory)
            runtime = task / "runtime"
            runtime.mkdir(mode=0o700)
            test = task / "tst_drag.qml"
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
