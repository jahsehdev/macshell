pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import "../../MacShell" as Shell

Window {
    id: window
    width: 1040; height: 800; visible: true
    Rectangle {
        anchors.fill: parent
        gradient: Gradient { GradientStop { position: 0; color: "#90d5e4" } GradientStop { position: 1; color: "#0045ab" } }
    }
    QtObject {
        id: desktop
        property var items: [{name: "Recipes", path: Quickshell.env("MACSHELL_CUSTOMIZE_FOLDER"), directory: true,
            x: 910, y: 40, icon: "folder", fallback: "folder", image: false, url: "", customIcon: Quickshell.env("MACSHELL_PREVIEW_ICON")}]
        property var selected: ["Recipes"]
        property var requests: []
        property bool busy: false
        property string busyAction: ""
        property string message: ""
        property bool messageIsError: false
        property int overflowCount: 0
        property int iconWidth: 104
        property int iconHeight: 108
        signal renameRequested(string name)
        function send(value) { requests = requests.concat([value]); }
        function select(name, additive) { selected = [name]; }
        function selectRectangle() {}
        function openFolder() {}
        function open(name) {}
        function trashSelected() {}
        function arrange(cleanup) {}
    }
    QtObject {
        id: widgets
        property bool darkGlass: false
        property string fontFamily: "sans-serif"
        property string pickError: ""
        property bool editing: false
        property var hub: null
        function finishEditing() {}
        function supportsXL(id) { return false; }
        function typeOf(id) { return ""; }
    }
    Shell.DesktopSurface {
        id: surface
        anchors.fill: parent
        desktop: desktop
        widgets: widgets
    }
    TestCase {
        name: "DesktopFolderIntegration"
        when: window.visible
        onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
        function test_01_context_menu_has_palette_for_single_folder() {
            surface.openFileMenu(800, 80);
            const menu = findChild(surface, "folderContextMenu");
            verify(menu.entries.some(function(row) { return row.palette === true; }));
            verify(menu.entries.some(function(row) { return row.action === "customize"; }));
            for (const action of ["open", "folder", "rename", "trash", "customize"]) {
                const icon = findChild(menu, "desktopMenuIcon-" + action);
                verify(icon !== null);
                tryCompare(icon, "status", Image.Ready);
            }
            menu.chosen("folderColor:#ffd43b");
            compare(desktop.requests[0].action, "customize");
            compare(desktop.requests[0].color, "#ffd43b");
            compare(desktop.requests[0].name, "Recipes");
        }
        function test_02_menu_preview() {
            surface.openFileMenu(720, 80);
            const menu = findChild(surface, "folderContextMenu");
            mouseMove(menu, 100, menu.height - 20);
            wait(100);
            const dir = Quickshell.env("MACSHELL_PREVIEW_DIR");
            if (dir) {
                let done = false;
                window.contentItem.grabToImage(function(result) { result.saveToFile(dir + "/customize-folder-context-menu.png"); done = true; });
                tryVerify(function() { return done; });
            }
        }
        function test_03_nonfolder_and_multiple_selection_excluded() {
            desktop.selected = ["missing"];
            surface.openFileMenu(800, 80);
            const menu = findChild(surface, "folderContextMenu");
            verify(!menu.entries.some(function(row) { return row.action === "customize"; }));
            desktop.selected = ["Recipes", "another"];
            surface.openFileMenu(800, 80);
            verify(!menu.entries.some(function(row) { return row.palette === true; }));
            desktop.selected = ["Recipes"];
        }
        function test_04_real_customizer_loads_and_stays_inside_screen() {
            surface.customizeFolder();
            const loader = findChild(surface, "folderCustomizerLoader");
            tryVerify(function() { return loader.item && loader.item.ready; }, 5000);
            compare(loader.item.name, "Recipes");
            compare(loader.item.symbols.length, 71);
            const font = findChild(loader.item, "folderEmojiTypeface");
            verify(font !== null);
            tryCompare(font, "status", FontLoader.Ready);
            compare(font.name, loader.item.emojiFontFamily);
            verify(loader.x >= 0 && loader.x + loader.width <= surface.width);
            verify(loader.y >= 0 && loader.y + loader.height <= surface.height);
            verify(loader.height <= 620);
            verify(loader.y + loader.height <= surface.height - 112);
            // The menu is clamped left of this icon. Its position must not
            // create a large gap between the customizer and the folder.
            compare(loader.item.tailOnLeft, false);
            compare(desktop.items[0].x + 20 - (loader.x + loader.width + 10), 8);
            compare(loader.y + loader.item.pointerY, desktop.items[0].y + 38);
            const dir = Quickshell.env("MACSHELL_PREVIEW_DIR");
            if (dir) {
                let done = false;
                window.contentItem.grabToImage(function(result) { result.saveToFile(dir + "/customize-folder-near-icon.png"); done = true; });
                tryVerify(function() { return done; });
            }
            loader.item.dismissed();
            compare(loader.active, false);
        }
        function test_05_left_edge_flips_tail_and_bottom_edge_tracks_folder() {
            desktop.items = [Object.assign({}, desktop.items[0], { x: 16, y: 580 })];
            surface.customizeFolder();
            const loader = findChild(surface, "folderCustomizerLoader");
            tryVerify(function() { return loader.item && loader.item.ready; }, 5000);
            compare(loader.item.tailOnLeft, true);
            compare(loader.x - 10 - (desktop.items[0].x + 84), 8);
            compare(loader.y + loader.item.pointerY, desktop.items[0].y + 38);
            verify(loader.y + loader.height <= surface.height - 112);
            const dir = Quickshell.env("MACSHELL_PREVIEW_DIR");
            if (dir) {
                let done = false;
                window.contentItem.grabToImage(function(result) { result.saveToFile(dir + "/customize-folder-left-edge.png"); done = true; });
                tryVerify(function() { return done; });
            }
            loader.item.dismissed();
        }
    }
}
