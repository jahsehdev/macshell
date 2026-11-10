pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import QtQuick.Controls.Basic as Basic
import Quickshell
import ".." as Common
import "../../MacShell" as Shell

Window {
    id: window
    width: 580; height: 360; visible: true
    property bool systemDark: true
    property int chosen: 0
    color: systemDark ? "#343740" : "#c8ced8"
    Rectangle {
        id: testBackdrop
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#e8a682" }
            GradientStop { position: 0.45; color: "#72c4d5" }
            GradientStop { position: 1; color: "#284b96" }
        }
        Repeater {
            model: 58
            Rectangle { required property int index; x: index * 10; width: 3; height: testBackdrop.height; color: "#600c244b" }
        }
    }
    Binding { target: Common.IconStyle; property: "systemDark"; value: window.systemDark }
    Shell.DesktopMenu {
        id: desktopMenu
        x: 20; y: 40
        dark: window.systemDark
        visible: true
        backdrop: testBackdrop
        entries: [{ label: "New Folder", action: "mkdir" },
            { label: "Open Desktop in Files", action: "folder" },
            { separator: true }, { label: "Edit Widgets…", action: "widgets" },
            { label: "Clean Up Icons", action: "cleanup" },
            { separator: true }, { label: "Change Wallpaper…", action: "wallpaper" }]
    }
    Common.ThemedMenu {
        id: menu
        x: 290; y: 40
        backdrop: testBackdrop
        Common.ThemedMenuItem { text: "Open"; onTriggered: window.chosen = 1 }
        Common.ThemedMenuItem { text: "Unavailable action"; enabled: false }
        Common.ThemedMenuSeparator {}
        Common.ThemedMenuItem { text: "Cancel"; onTriggered: window.chosen = 2 }
    }
    TestCase {
        name: "MenuAppearance"
        when: window.visible
        onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
        function init() {
            window.systemDark = true;
            window.chosen = 0;
            menu.popupType = Basic.Popup.Window;
            menu.open();
            tryCompare(menu, "opened", true);
            menu.contentItem.Window.window.requestActivate();
            menu.contentItem.forceActiveFocus();
            mouseMove(window.contentItem, 560, 330);
            menu.currentIndex = -1;
        }
        function cleanup() { menu.close(); }
        function capture(name) {
            const dir = Quickshell.env("MACSHELL_PREVIEW_DIR");
            if (!dir) return;
            if (GraphicsInfo.api !== GraphicsInfo.Software) {
                tryCompare(findChild(desktopMenu, "desktopMenuMaterial"), "ready", true);
                tryCompare(menu.background, "ready", true);
                wait(80);
            }
            let done = false;
            window.contentItem.grabToImage(function(result) {
                result.saveToFile(dir + "/" + name + ".png"); done = true;
            });
            tryVerify(function() { return done; });
        }
        function test_live_theme_changes_while_open() {
            compare(menu.itemAt(0).palette.windowText, "#f2f2f5");
            compare(menu.itemAt(1).palette.windowText, "#85858c");
            capture("menus-dark");
            window.systemDark = false;
            compare(menu.opened, true);
            compare(menu.itemAt(0).palette.windowText, "#242428");
            compare(menu.itemAt(1).palette.windowText, "#929298");
            compare(desktopMenu.dark, false);
            capture("menus-light");
            window.systemDark = true;
            compare(menu.itemAt(0).palette.windowText, "#f2f2f5");
        }
        function test_keyboard_skips_disabled_and_separator() {
            // QtTest injects keys into the harness window. Window popups are
            // exercised by the other tests; use the same menu in that window
            // for keyboard injection.
            menu.close();
            menu.popupType = Basic.Popup.Item;
            window.requestActivate();
            menu.open();
            tryCompare(menu, "opened", true);
            menu.currentIndex = 0;
            keyClick(Qt.Key_Down);
            compare(menu.currentIndex, 3);
            compare(menu.itemAt(3).palette.windowText, "#ffffff");
            keyClick(Qt.Key_Return);
            compare(window.chosen, 2);
            tryCompare(menu, "opened", false);
        }
        function test_mouse_action() {
            mouseClick(menu.itemAt(0), 50, 14);
            compare(window.chosen, 1);
            tryCompare(menu, "opened", false);
        }
        function test_menu_consumers_compile() {
            for (const file of ["SideDockContent", "StageManagerContent", "StudioApp"]) {
                const component = Qt.createComponent("../../MacShell/" + file + ".qml");
                tryCompare(component, "status", Component.Ready);
                compare(component.errorString(), "");
            }
        }
        function test_shared_frosted_material_and_opaque_fallback() {
            const material = findChild(desktopMenu, "desktopMenuMaterial");
            compare(material.blurRadius, 32);
            verify(material.shaderUrl.toString().endsWith("LiquidGlass-frosted-menu.frag.qsb"));
            verify(menu.background.shaderUrl.toString().endsWith("LiquidGlass-frosted-menu.frag.qsb"));
            if (GraphicsInfo.api !== GraphicsInfo.Software) tryCompare(material, "ready", true);
            material.opaque = true;
            tryCompare(material, "ready", false);
            material.opaque = false;
            if (GraphicsInfo.api !== GraphicsInfo.Software) tryCompare(material, "ready", true);
        }
        function test_popup_can_extend_beyond_a_narrow_stage_manager_window() {
            window.width = 178;
            try {
                compare(menu.popupType, Basic.Popup.Window);
                verify(menu.contentItem.Window.window !== window);
                verify(menu.width > window.width);
                verify(menu.contentItem.Window.window.width >= menu.width);
            } finally { window.width = 580; }
        }
    }
}
