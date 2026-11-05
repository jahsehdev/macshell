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
import QtQuick.Controls as Controls
import "SHELL" as LocalEffects
import "SHELL/ControlCatalog.js" as ControlCatalog
Item {
    id: root
    width: 640; height: 320
    property bool effDark: false
    property bool reduceMotion: false
    property bool withSlider: false
    property int activated: 0
    property int arrowActivated: 0
    property int footerActivated: 0
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
    QtObject {
        id: ccPal
        property bool dark: false
        property color fg: "white"
        property string fam: "sans-serif"
        property color borderTint: "#aaaaaa"
        property real borderAmount: 1
    }
    component GGlass: Item {
        property var gx
        property real cornerR: 0
        property real thickness: 0
        property real strengthMul: 0
        property real shadowAmt: 0
        property real flatInner: 0
        Rectangle { anchors.fill: parent; radius: parent.cornerR; color: "#aaaaaa" }
    }
    component CornerBorder: Item {
        property real cornerR: 0
        property bool dark: false
        property color tint: "white"
        property real amount: 1
        property real lineW: 1
    }
    PILL_COMPONENT
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
            MouseArea { anchors.fill: parent; onClicked: root.activated++ }
            MouseArea {
                x: parent.width - 25; width: 25; height: parent.height
                onClicked: root.arrowActivated++
            }
            Controls.Slider {
                objectName: "ccValueSlider"
                x: 10; y: 25; width: parent.width - 40; height: 30
                visible: root.withSlider
                enabled: visible
                value: 0.5
            }
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
        Item { id: ccCol }
        OVERLAY
        CCPill {
            id: footer
            x: 20; y: 280; t: ccPal; gx: ccPal
            text: "Edit Controls"
            onClicked: root.footerActivated++
        }
        Flickable {
            id: ccScroll
            x: 20; y: 70; width: 300; height: 200
            contentHeight: ccGrid.height; contentWidth: width
            clip: true
            interactive: !ui.ccEdit && !ccGrid.elasticBusy
        Item {
            id: ccGrid
            width: 300; height: 200
            readonly property real cw: (width - 3 * root.ccGap) / 4
            readonly property real chh: 66
            readonly property bool elasticBusy: {
                for (var i = 0; i < children.length; i++)
                    if (children[i].elasticEngaged) return true;
                return false;
            }
            Repeater {
                model: root.ccCatalog
                DELEGATE
            }
        }
        }
    }
    TestCase {
        name: "ControlCenterDrag"
        when: windowShown
        function init() {
            ui.ccEdit = true;
            root.reduceMotion = false; root.withSlider = false;
            cc.opening = true; cc.visible = true;
            root.activated = 0; root.arrowActivated = 0;
            root.footerActivated = 0;
            root.dropped=0; root.removed=0; root.pinned=0; controlsGallery.menus=0;
            for (var id of ["record", "timer"]) {
                const elastic = findChild(ui, "ccElasticDrag_" + id);
                tryCompare(elastic, "engaged", false, 3000);
            }
            wait(220);
        }
        function normalControl(id) {
            ui.ccEdit = false;
            return findChild(ui, "ccControlContent_" + (id || "record"));
        }
        function test_footerClickAndElasticDrag() {
            mouseClick(footer, footer.width/2, footer.height/2);
            compare(root.footerActivated, 1);
            const elastic = findChild(footer, "ccPillElasticDrag");
            const start = footer.mapToItem(ui, footer.width/2, footer.height/2);
            mousePress(ui, start.x, start.y);
            mouseMove(ui, start.x + 40, start.y - 20, 20);
            mouseMove(ui, start.x + 80, start.y - 40, 20);
            verify(elastic.active);
            const center = footer.mapToItem(ui, footer.width/2, footer.height/2);
            fuzzyCompare(center.x, start.x + elastic.offsetX, 0.1);
            fuzzyCompare(center.y, start.y + elastic.offsetY, 0.1);
            mouseRelease(ui, start.x + 80, start.y - 40);
            tryCompare(elastic, "engaged", false, 3000);
            compare(root.footerActivated, 1, "Dragging the footer must not enter/exit edit mode");
        }
        function test_elasticDirections_data() {
            var rows = [];
            for (var id of ["record", "timer"])
                for (var d of [[95,0],[-95,0],[0,95],[0,-95],[80,65],[-80,-65],[80,-65],[-80,65]])
                    rows.push({tag:id+":"+d.join(","), id:id, x:d[0], y:d[1]});
            return rows;
        }
        function test_elasticDirections(data) {
            const content = normalControl(data.id), tile = content.parent;
            const elastic = findChild(tile, "ccElasticDrag_" + data.id);
            const start = content.mapToItem(ui, content.width/2, content.height/2);
            mousePress(ui, start.x, start.y);
            mouseMove(ui, start.x + data.x/2, start.y + data.y/2, 20);
            mouseMove(ui, start.x + data.x, start.y + data.y, 20);
            tryCompare(elastic, "active", true);
            verify(elastic.offsetX * data.x >= 0 && elastic.offsetY * data.y >= 0);
            const distance = Math.hypot(elastic.offsetX, elastic.offsetY);
            verify(distance > 0 && distance < Math.hypot(data.x, data.y) * 0.55);
            verify(distance <= 5, "Keep even distant pulls close to the original slot");
            const center = content.mapToItem(ui, content.width/2, content.height/2);
            fuzzyCompare(center.x, start.x + elastic.offsetX, 0.1, "Lifting must not jump horizontally");
            fuzzyCompare(center.y, start.y + elastic.offsetY, 0.1, "Lifting must not jump vertically");
            compare(content.parent, ccElasticLayer, "The surface escapes the clipped viewport");
            verify(!ccScroll.interactive, "Keep the input frame fixed while dragging");
            compare(tile.dx, 0); compare(tile.dy, 0);
            compare(root.activated, 0); compare(root.arrowActivated, 0);
            compare(ui.ccDragId, "");
            const pull = elastic.matrix;
            const maximumScale = (pull.m11 + pull.m22 + Math.hypot(pull.m11 - pull.m22, 2 * pull.m12)) / 2;
            verify(maximumScale > 1.01, "Deform the shape along the pull, including diagonal pulls");
            verify(maximumScale <= 1.08001, "Stretch must stay below eight percent");
            verify((maximumScale - 1) * Math.max(content.width, content.height) <= 8.001,
                   "Wide controls must not grow more than eight pixels");
            mouseRelease(ui, start.x + data.x, start.y + data.y);
            compare(elastic.active, false);
            verify(elastic.engaged, "Spring physics continues after release");
            tryCompare(elastic, "engaged", false, 3000);
            compare(elastic.offsetX, 0); compare(elastic.offsetY, 0);
            compare(content.parent, tile, "Restore the original anchors and parent");
            const settled = content.mapToItem(ui, content.width/2, content.height/2);
            fuzzyCompare(settled.x, start.x, 0.1); fuzzyCompare(settled.y, start.y, 0.1);
            compare(root.activated, 0); compare(root.arrowActivated, 0);
            compare(root.removed, 0); compare(root.dropped, 0); compare(root.pinned, 0);
        }
        function test_normalClicksAndSmallMotion() {
            const content = normalControl();
            mouseClick(content, content.width/2, content.height/2);
            compare(root.activated, 1);
            mouseClick(content, content.width - 10, content.height/2);
            compare(root.arrowActivated, 1);
            mousePress(content, content.width/2, content.height/2);
            mouseMove(content, content.width/2 + 2, content.height/2 + 1, 10);
            mouseRelease(content, content.width/2 + 2, content.height/2 + 1);
            compare(root.activated, 2);
            compare(root.dropped, 0);
        }
        function test_sliderKeepsItsGrab() {
            root.withSlider = true;
            const content = normalControl();
            const elastic = findChild(content.parent, "ccElasticDrag_record");
            const slider = findChild(content, "ccValueSlider");
            compare(elastic.valueControl, slider);
            mousePress(slider, slider.width/2, slider.height/2);
            verify(slider.pressed);
            mouseMove(slider, slider.width - 5, slider.height/2, 30);
            mouseMove(slider, slider.width - 2, slider.height/2, 30);
            compare(elastic.active, false);
            verify(slider.value > 0.8);
            mouseRelease(slider, slider.width - 2, slider.height/2);
            compare(root.activated, 0);
        }
        function test_resistanceAndSpringOvershoot() {
            const content = normalControl();
            const elastic = findChild(content.parent, "ccElasticDrag_record");
            const start = content.mapToItem(ui, content.width/2, content.height/2);
            mousePress(ui, start.x, start.y);
            mouseMove(ui, start.x + 40, start.y, 20);
            const near = elastic.offsetX;
            mouseMove(ui, start.x + 80, start.y, 20);
            const middle = elastic.offsetX;
            mouseMove(ui, start.x + 120, start.y, 20);
            const far = elastic.offsetX;
            verify(near > 0 && middle > near && far > middle);
            verify(far - middle < middle - near, "Resistance increases with distance");
            grabImage(root).save("/tmp/macshell-elastic-drag-stretch.png");
            mouseRelease(ui, start.x + 120, start.y);
            tryVerify(() => elastic.offsetX < -0.05, 2000, "The spring crosses its resting position");
            tryCompare(elastic, "engaged", false, 3000);
        }
        function test_cancelAndReducedMotion() {
            const content = normalControl(), tile = content.parent;
            const elastic = findChild(tile, "ccElasticDrag_record");
            const start = content.mapToItem(ui, content.width/2, content.height/2);
            mousePress(ui, start.x, start.y);
            mouseMove(ui, start.x + 80, start.y + 30, 20);
            verify(elastic.active);
            cc.opening = false;
            tryCompare(elastic, "active", false);
            mouseRelease(ui, start.x + 80, start.y + 30);
            tryCompare(elastic, "engaged", false, 3000);
            compare(content.parent, tile);
            cc.opening = true;
            root.reduceMotion = true;
            mousePress(ui, start.x, start.y);
            mouseMove(ui, start.x + 80, start.y + 30, 20);
            compare(elastic.offsetX, 0); compare(elastic.offsetY, 0);
            mouseRelease(ui, start.x + 80, start.y + 30);
            compare(elastic.engaged, false);
            compare(root.activated, 0);
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
        ).replace("DELEGATE", qml_block(source, "ct")).replace(
            "OVERLAY", qml_block(source, "ccElasticLayer")
        ).replace("PILL_COMPONENT", qml_block(source, "pl"))
        with tempfile.TemporaryDirectory(prefix="control-center-drag-") as directory:
            task = Path(directory)
            runtime = task / "runtime"
            runtime.mkdir(mode=0o700)
            test = task / "tst_drag.qml"
            test.write_text(qml)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_RUNTIME_DIR=str(runtime))
            result = subprocess.run(["/usr/lib/qt6/bin/qmltestrunner", "-input", str(test)],
                                    env=env, capture_output=True, text=True, timeout=75)
            output = result.stdout + result.stderr
            print(output)
            self.assertEqual(result.returncode, 0, output)
            self.assertNotRegex(output, r"QWARN|TypeError|ReferenceError|Unable to assign")


if __name__ == "__main__":
    unittest.main()
