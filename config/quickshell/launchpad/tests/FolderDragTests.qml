import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Io
import ".."
import "../components"

Window {
    id: window
    width: 1000; height: 800; visible: true
    color: "#293344"
    property int launches: 0
    property bool bootstrapped: false
    property list<var> qtFolderItems: []
    FocusScope {
        id: surface
        anchors.fill: parent
        focus: true
        Item {
            id: content
            anchors.fill: parent
            scale: LaunchpadState.folderOpen ? 0.96 : (LaunchpadState.shown ? 1 : 1.06)
            opacity: LaunchpadState.folderOpen ? (folderLoader.item && folderLoader.item.dragOutside ? Theme.revealGridOpacity : 0.35) : 1
            Behavior on scale { NumberAnimation { duration: Theme.animOpen } }
            PagedGrid { id: grid; x: 80; y: 90 }
        }
        Loader {
            id: folderLoader
            anchors.fill: parent
            active: LaunchpadState.folderOpen && LaunchpadState.foldered !== null
            sourceComponent: FolderPanel { backdrop: content; gridItem: grid }
        }
    }
    FileView { id: expectedFile; path: Theme.stateDir + "/expected-layout.json"; atomicWrites: true; blockWrites: true; printErrors: false }
    TestCase {
        id: tests
        name: "FolderDrag"
        when: window.visible && window.bootstrapped
        onCompletedChanged: if (completed) console.log("TOTALS",qtest_results.passCount,"passed,",qtest_results.failCount,"failed")
        function app(id) { return {kind:"app",id:id,name:"App " + id,icon:"",entry:{execute:function() { window.launches++; }}}; }
        function folder(ids) { return LaunchpadState.folderItem("Utilities", ids.map(app)); }
        function labels() { return LaunchpadState.pages.map(p => p.map(it => it.kind === "folder" ? "F("+it.items.map(x=>x.id).join(",")+")" : it.id)); }
        function serialized() { return JSON.stringify(LaunchpadState.pages.map(p => p.map(LaunchpadState.serializeItem))); }
        function setup(pages, folderPage) {
            LaunchpadState.pages = pages;
            LaunchpadState.refreshView();
            const f = pages[folderPage || 0].find(it=>it.kind === "folder");
            LaunchpadState.openFolder(f, Qt.rect(450,350,Theme.iconSize,Theme.iconSize));
            tryVerify(()=>folderLoader.item !== null);
            wait(30);
            return folderLoader.item;
        }
        function begin(index, offset) {
            const input = findChild(folderLoader.item,"folder-input-"+index);
            verify(input !== null);
            const x=Theme.iconSize/2 + (offset || 0), y=Theme.iconSize/2;
            mousePress(input,x,y,Qt.LeftButton);
            mouseMove(input,x+12,y,1,Qt.LeftButton);
            verify(folderLoader.item.dragging);
            compare(LaunchpadState.drag,null,"top-level drag must stay inactive");
            return input;
        }
        function target(slot) {
            const r=grid.slotRect(slot);
            return Qt.point(r.x+r.width/2,r.y+r.height/2);
        }
        function moveOutside(slot) {
            const p=target(slot);
            mouseMove(surface,p.x,p.y,1,Qt.LeftButton);
            verify(folderLoader.item.dragOutside);
            compare(folderLoader.item.dropIndex,slot);
            const r=grid.slotRect(slot), actual=folderLoader.item.dropRect;
            fuzzyCompare(actual.x,r.x,0.01); fuzzyCompare(actual.y,r.y,0.01);
            return p;
        }
        function drop(slot) { const p=moveOutside(slot); mouseRelease(surface,p.x,p.y,Qt.LeftButton); wait(20); }
        function initTestCase() {
            wait(300);
            Theme.autoLayout=false; Theme.columns=4; Theme.rows=3;
            Theme.animationsEnabled=false;
            wait(20);
        }
        function init() {
            LaunchpadState.closeFolder();
            LaunchpadState.query="";
            LaunchpadState.mockMode=true;
            LaunchpadState.hidden=[];
            LaunchpadState.page=0;
            LaunchpadState.pageDirection=0;
            LaunchpadState.justDroppedId="";
            LaunchpadState.shown=true;
            LaunchpadState.windowVisible=true;
            LaunchpadState.menu=null;
            LaunchpadState.editMode=false;
            Theme.closeAfterRemove=true;
            Theme.dissolveSingleItemFolders=false;
            Theme.animationsEnabled=false;
            window.launches=0;
            wait(20);
        }
        function cleanup() {
            console.log("RESULT", qtest_results.functionName, qtest_results.failed ? "FAIL" : "PASS");
            LaunchpadState.closeFolder(); wait(10);
        }
        function test_T01_append_and_preview() {
            setup([[app("A"),app("B"),folder(["X","Y","Z"]),app("C")]]);
            begin(1); drop(4);
            compare(labels(),[["A","B","F(X,Z)","C","Y"]]);
            verify(!LaunchpadState.folderOpen);
            verify(LaunchpadState.checkLayoutInvariants());
        }
        function test_qml_sequence_folder_items() {
            window.qtFolderItems=[app("X"),app("Y"),app("Z")];
            const f=LaunchpadState.folderItem("Qt sequence",window.qtFolderItems);
            console.log("QML SEQUENCE",Array.isArray(f.items),Object.prototype.toString.call(f.items),f.items.length);
            setup([[app("A"),f]]);
            begin(0); drop(0);
            compare(labels(),[["X","A","F(Y,Z)"]]);
        }
        function openThroughGrid() {
            LaunchpadState.pages=[[app("A"),folder(["X","Y","Z"]),app("B")]];
            LaunchpadState.refreshView(); wait(30);
            const tile=findChild(grid,"folder-tile-__folder__Utilities"); verify(tile!==null);
            mouseClick(tile,Theme.iconSize/2,Theme.iconSize/2,Qt.LeftButton);
            tryVerify(()=>folderLoader.item!==null); wait(30);
        }
        function test_grid_folder_tile_drag_out() {
            openThroughGrid(); begin(0); drop(0);
            compare(labels(),[["X","A","F(Y,Z)","B"]]);
        }
        function test_grid_folder_tile_manual_commit() {
            openThroughGrid();
            mouseClick(findChild(folderLoader.item,"folder-input-0"),20,20,Qt.RightButton);
            compare(LaunchpadState.menu.source,"folder");
            const source=LaunchpadState.menu.item;
            verify(folderLoader.item.commitRemoval(source,-1));
            compare(labels(),[["A","F(Y,Z)","B","X"]]);
        }
        function test_T02_insert_between_apps() {
            setup([[app("A"),app("B"),folder(["X","Y","Z"]),app("C")]]);
            begin(0); drop(1);
            compare(labels(),[["A","X","B","F(Y,Z)","C"]]);
        }
        function test_T03_keep_single_and_dissolve() {
            setup([[app("A"),folder(["X","Y"])]]); begin(0); drop(0);
            compare(labels(),[["X","A","F(Y)"]]);
            Theme.dissolveSingleItemFolders=true;
            setup([[app("A"),folder(["X","Y"])]]); begin(0); drop(0);
            compare(labels(),[["X","A","Y"]]); verify(!LaunchpadState.folderOpen);
        }
        function test_T04_last_child_removes_folder() {
            setup([[app("A"),folder(["X"])]]); begin(0); drop(2);
            compare(labels(),[["A","X"]]); verify(!LaunchpadState.folderOpen);
        }
        function test_T05_full_page_overflow() {
            const top=[folder(["X","Y"])];
            for(let i=0;i<11;i++)top.push(app("A"+i));
            setup([top,[app("Q")]]); begin(0); drop(0);
            compare(labels()[0][0],"X"); compare(labels()[1],["A10","Q"]);
            compare(LaunchpadState.pages[0].length,Theme.pageSize);
            verify(LaunchpadState.checkLayoutInvariants());
        }
        function test_T06_release_inside_cancels() {
            setup([[app("A"),folder(["X","Y","Z"])]]);
            const before=serialized(), input=begin(0);
            mouseRelease(input,Theme.iconSize/2+12,Theme.iconSize/2,Qt.LeftButton);
            compare(serialized(),before); verify(LaunchpadState.folderOpen);
            verify(!folderLoader.item.dragging); verify(LaunchpadState.shown);
        }
        function test_T07_escape_cancels_without_restarting() {
            const f=folder(["X","Y","Z"]);
            LaunchpadState.pages=[[app("A"),f]];
            LaunchpadState.query="App";
            LaunchpadState.openFolder(f,Qt.rect(400,350,64,64)); wait(20);
            const before=serialized(); begin(0);
            keyClick(Qt.Key_Escape);
            verify(!folderLoader.item.dragging); verify(LaunchpadState.folderOpen);
            compare(LaunchpadState.query,"App");
            mouseMove(surface,50,50,1,Qt.LeftButton);
            verify(!folderLoader.item.dragging,"Esc must end the active press");
            mouseRelease(surface,50,50,Qt.LeftButton);
            compare(serialized(),before); verify(LaunchpadState.shown);
        }
        function test_T08_click_and_context() {
            setup([[app("A"),folder(["X","Y","Z"])]]);
            mouseClick(findChild(folderLoader.item,"folder-input-0"),20,20,Qt.RightButton);
            compare(LaunchpadState.menu.source,"folder"); compare(LaunchpadState.menu.item.id,"X");
            LaunchpadState.menu=null;
            mouseClick(findChild(folderLoader.item,"folder-input-0"),20,20,Qt.LeftButton);
            compare(window.launches,1); verify(!LaunchpadState.shown);
        }
        function test_T09_search_appends_after_folder() {
            const f=folder(["X","Y"]);
            LaunchpadState.pages=[[app("A"),f,app("B")],[app("C")]];
            LaunchpadState.query="App"; LaunchpadState.openFolder(f,Qt.rect(400,350,64,64)); wait(20);
            begin(0); mouseMove(surface,20,20,1,Qt.LeftButton);
            compare(folderLoader.item.dropIndex,-1);
            mouseRelease(surface,20,20,Qt.LeftButton);
            compare(labels(),[["A","F(Y)","X","B"],["C"]]);
            compare(LaunchpadState.query,"App");
        }
        function test_T11_scroll_and_drag() {
            const ids=Array.from({length:30},(_,i)=>"X"+i);
            setup([[app("A"),folder(ids)]]);
            const flick=findChild(folderLoader.item,"folder-scroll");
            verify(flick.contentHeight>flick.height);
            const p=flick.mapToItem(surface,flick.width/2,flick.height/2);
            mouseWheel(surface,p.x,p.y,0,-240,Qt.NoButton);
            tryVerify(()=>flick.contentY>0);
            flick.cancelFlick(); flick.contentY=0; wait(20);
            begin(0); verify(!flick.interactive); drop(0);
            compare(LaunchpadState.pages[0][0].id,"X0");
        }
        function test_T12_grab_offset_and_final_release() {
            setup([[app("A"),folder(["X","Y","Z"])]]);
            begin(0,-8);
            const panel=folderLoader.item, ghost=findChild(panel,"folder-drag-ghost");
            fuzzyCompare(ghost.x+ghost.width/2,panel.dragPos.x+panel.dragGrab.x,0.01);
            const end=target(0);
            // No intermediate move at the destination: release coordinates win.
            mouseRelease(surface,end.x,end.y,Qt.LeftButton);
            compare(LaunchpadState.pages[0][0].id,"X");
            setup([[app("A"),folder(["X","Y","Z"])]]); begin(0);
            for(let x=350;x>=30;x-=20)mouseMove(surface,x,60,5,Qt.LeftButton);
            mouseRelease(surface,30,60,Qt.LeftButton);
            compare(LaunchpadState.pages[0][0].id,"X");
        }
        function test_T13_scale_mapping_and_reopen() {
            Theme.animationsEnabled=true;
            for(let i=0;i<3;i++) {
                LaunchpadState.shown=false; wait(Theme.animClose+30);
                LaunchpadState.shown=true; wait(Theme.animOpen+100);
            }
            setup([[app("A"),folder(["X","Y","Z"])]]); wait(Theme.animOpen+100);
            grid.updateGridRect();
            const a=grid.mapToItem(null,0,0),b=grid.mapToItem(null,grid.width,grid.height);
            fuzzyCompare(LaunchpadState.gridRect.x,a.x,0.01);
            fuzzyCompare(LaunchpadState.gridRect.width,b.x-a.x,0.01);
            begin(0); const p=moveOutside(0); wait(100);
            const plate=findChild(folderLoader.item,"folder-drop-indicator"),r=grid.slotRect(0);
            fuzzyCompare(plate.x,r.x,0.02); fuzzyCompare(plate.y,r.y,0.02);
            mouseRelease(surface,p.x,p.y,Qt.LeftButton); wait(Theme.animFolder+50);
            compare(LaunchpadState.pages[0][0].id,"X"); verify(!LaunchpadState.folderOpen);
        }
        function test_closeAfterRemove_false_and_keyboard() {
            Theme.closeAfterRemove=false;
            setup([[app("A"),folder(["X","Y","Z"])]]); begin(0); drop(0);
            verify(LaunchpadState.folderOpen);
            compare(folderLoader.item.folder.items.map(x=>x.id),["Y","Z"]);
            keyClick(Qt.Key_Return,Qt.ShiftModifier);
            verify(LaunchpadState.folderOpen); compare(LaunchpadState.foldered.items.length,1);
            keyClick(Qt.Key_Return,Qt.ShiftModifier); verify(!LaunchpadState.folderOpen);
            verify(LaunchpadState.checkLayoutInvariants());
        }
        function test_long_press_rename_and_outside_close() {
            setup([[app("A"),folder(["X","Y","Z"])]]);
            const input=findChild(folderLoader.item,"folder-input-0");
            mousePress(input,20,20,Qt.LeftButton);
            wait(Theme.longPressDelay+50);
            verify(LaunchpadState.editMode);
            mouseRelease(input,20,20,Qt.LeftButton);
            compare(window.launches,0);
            LaunchpadState.editMode=false;
            folderLoader.item.renaming=true;
            const rename=findChild(folderLoader.item,"folder-rename-input");
            rename.forceActiveFocus(); rename.text="Renamed";
            keyClick(Qt.Key_Return);
            compare(LaunchpadState.foldered.name,"Renamed");
            compare(LaunchpadState.pages[0][1].name,"Renamed");
            mouseClick(surface,20,20,Qt.LeftButton);
            verify(!LaunchpadState.folderOpen);
        }
        function test_teardown_cancels_mid_drag() {
            setup([[app("A"),folder(["X","Y","Z"])]]);
            const before=serialized(); begin(0); moveOutside(0);
            LaunchpadState.closeFolder(); wait(20);
            compare(folderLoader.item,null); compare(content.opacity,1);
            compare(LaunchpadState.drag,null); compare(serialized(),before);
            mouseRelease(surface,20,20,Qt.LeftButton);
        }
        function test_pop_in_after_folder_close() {
            Theme.animationsEnabled=true;
            setup([[app("A"),folder(["X","Y","Z"])]]);
            wait(Theme.animOpen+30);
            begin(0); drop(0);
            const tile=findChild(grid,"app-tile-X"); verify(tile!==null);
            tryVerify(()=>tile.dropPopScale!==1);
            verify(!LaunchpadState.folderOpen);
            tryCompare(tile,"dropPopScale",1,600);
            tryCompare(LaunchpadState,"justDroppedId","",600);
        }
        function test_z_T10_real_persistence() {
            // Use actual desktop ids so the production loader can restore them.
            const entries=LaunchpadState.visibleEntries(); verify(entries.length>=4);
            LaunchpadState.mockMode=false;
            const apps=entries.map(LaunchpadState.appItem);
            const f=LaunchpadState.folderItem("Persistence test",apps.slice(0,3));
            // Include a partial first page to verify startup does not repack it.
            LaunchpadState.pages=[[f],...LaunchpadState.pack(apps.slice(3))];
            LaunchpadState.openFolder(f,Qt.rect(0,0,64,64));
            verify(LaunchpadState.removeFromFolder(apps[0],0,-1));
            const before=serialized();
            verify(LaunchpadState.saveNow());
            LaunchpadState.load(); LaunchpadState.refreshView();
            compare(serialized(),before,"layout.json save/load round trip");
            expectedFile.setText(before);
            console.log("PASS native persistence round trip");
        }
    }
    Timer { interval:500; running:true; onTriggered: window.bootstrapped=true }
    Timer { interval:50000; running:true; onTriggered: { console.error("TEST TIMEOUT"); Qt.quit(); } }
}
