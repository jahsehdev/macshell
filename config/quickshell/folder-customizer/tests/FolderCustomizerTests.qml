pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import Quickshell.Io
import ".." as Custom

Window {
    id: window
    visible: true
    width: 540; height: 780
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#9bdce8" }
            GradientStop { position: 0.5; color: "#207fc5" }
            GradientStop { position: 1; color: "#0044a6" }
        }
    }
    Custom.FolderCustomizer {
        id: panel
        x: 48; y: 30
        folderPath: Quickshell.env("MACSHELL_CUSTOMIZE_FOLDER")
        demo: true
        name: "Recipes"
        colorValue: "#ffd43b"
        ready: true
        iconUrl: Quickshell.env("MACSHELL_PREVIEW_ICON")
    }
    FileView {
        path: Qt.resolvedUrl("../symbols.json").toString().replace("file://", "")
        onLoaded: panel.symbols = JSON.parse(text())
    }
    SignalSpy { id: changeSpy; target: panel; signalName: "changed" }
    SignalSpy { id: dismissSpy; target: panel; signalName: "dismissed" }
    TestCase {
        name: "FolderCustomizer"
        when: window.visible
        onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
        function cleanup() {
            keyClick(Qt.Key_Escape);
            panel.error = "";
            changeSpy.clear();
            dismissSpy.clear();
        }
        function test_01_symbols_load_and_selection() {
            tryCompare(panel, "symbols", panel.symbols, 1000);
            tryVerify(function() { return panel.symbols.length === 71; });
            panel.applySymbol("cutlery");
            compare(panel.symbolValue, "cutlery");
            compare(panel.emojiValue, "");
            compare(changeSpy.count, 1);
            panel.applySymbol("cutlery");
            compare(panel.symbolValue, "");
        }
        function test_02_color_preserves_symbol() {
            panel.applySymbol("joystick");
            panel.applyColor("#ff453a");
            compare(panel.colorValue, "#ff453a");
            compare(panel.symbolValue, "joystick");
            compare(panel.settings().symbol, "joystick");
        }
        function test_03_emoji_picker_search_and_apply() {
            mouseClick(findChild(panel, "emojiButton"));
            const search = findChild(panel, "emojiSearch");
            tryCompare(search, "activeFocus", true);
            search.text = "game";
            tryVerify(function() { return panel.visibleEmoji.length > 0 && panel.visibleEmoji.length < 60; });
            verify(panel.visibleEmoji.some(function(e) { return e[0] === "🎮"; }));
            panel.applyEmoji("🎮");
            compare(panel.emojiValue, "🎮");
            compare(panel.symbolValue, "");
            compare(panel.recentEmoji[0], "🎮");
            search.text = "xyz_no_emoji_exists";
            compare(panel.visibleEmoji.length, 0);
            search.text = "";
        }
        function test_04_custom_color_validation() {
            mouseClick(findChild(panel, "customColorButton"));
            const hex = findChild(panel, "customColorHex");
            hex.text = "#ab12ef";
            verify(hex.acceptableInput);
            hex.text = "#12";
            verify(!hex.acceptableInput);
        }
        function test_05_clear_and_dismiss() {
            panel.applySymbol("cutlery");
            mouseClick(findChild(panel, "clearFolderButton"));
            compare(panel.customized, false);
            compare(panel.symbolValue, "");
            verify(findChild(panel, "closeCustomizer") === null);
            panel.forceActiveFocus();
            keyClick(Qt.Key_Escape);
            compare(dismissSpy.count, 1);
        }
        function test_06_light_preview() {
            panel.forceActiveFocus();
            panel.dark = false;
            panel.colorValue = "#ffd43b";
            panel.symbolValue = "cutlery";
            panel.customized = true;
            wait(250);
            const preview = Quickshell.env("MACSHELL_PREVIEW_DIR");
            if (preview) {
                let done = false;
                window.contentItem.grabToImage(function(result) { result.saveToFile(preview + "/customize-folder-light.png"); done = true; });
                tryVerify(function() { return done; });
            }
        }
        function test_07_emoji_preview() {
            panel.showEmojiPicker();
            const search = findChild(panel, "emojiSearch");
            search.text = "";
            panel.emojiCategory = 0;
            wait(250);
            const preview = Quickshell.env("MACSHELL_PREVIEW_DIR");
            if (preview) {
                let done = false;
                window.contentItem.grabToImage(function(result) { result.saveToFile(preview + "/customize-folder-emoji.png"); done = true; });
                tryVerify(function() { return done; });
            }
        }
        function test_08_dark_preview() {
            panel.dark = true;
            wait(250);
            const preview = Quickshell.env("MACSHELL_PREVIEW_DIR");
            if (preview) {
                let done = false;
                window.contentItem.grabToImage(function(result) { result.saveToFile(preview + "/customize-folder-dark.png"); done = true; });
                tryVerify(function() { return done; });
            }
        }
        function test_09_keyboard_closes_picker_first() {
            panel.showEmojiPicker();
            wait(50);
            keyClick(Qt.Key_Escape);
            compare(dismissSpy.count, 0);
        }
        function test_10_scroll_reaches_other_categories() {
            const scroll = findChild(panel, "symbolScroll");
            verify(scroll.contentHeight > scroll.height);
            scroll.contentY = scroll.contentHeight - scroll.height;
            verify(scroll.contentY > 100);
        }
        function test_11_tail_is_a_single_continuous_surface() {
            const surface = findChild(panel, "folderPopoverSurface");
            surface.shadow = false;
            panel.dark = false;
            wait(50);
            let image = grabImage(surface);
            const y = Math.round(surface.tailY);
            compare(image.pixel(surface.bodyWidth - 3, y), image.pixel(surface.bodyWidth + 3, y));
            panel.dark = true;
            wait(50);
            image = grabImage(surface);
            compare(image.pixel(surface.bodyWidth - 3, y), image.pixel(surface.bodyWidth + 3, y));
            verify(surface.outline.indexOf(" C ") >= 0);
            surface.shadow = true;
        }
        function test_12_tooltip_matches_dock_label() {
            const button = findChild(panel, "customColorButton");
            const popup = findChild(window, "folderTooltip-customColorButton");
            verify(popup !== null);
            panel.dark = false;
            mouseMove(button, button.width / 2, button.height / 2);
            tryCompare(popup, "opened", true, 2000);
            const bubble = popup.contentItem;
            const component = Qt.createComponent(Qt.resolvedUrl("../../MacShell/DockTooltip.qml"));
            compare(component.status, Component.Ready);
            const dockLabel = component.createObject(window.contentItem, {
                visible: false, text: popup.text, frosted: true,
                width: bubble.width, pointerX: bubble.tailX
            });
            verify(dockLabel !== null);
            tryCompare(bubble, "height", dockLabel.implicitHeight);
            compare(bubble.outline(0.5), dockLabel.outline(0.5));
            compare(bubble.outline(1.5), dockLabel.outline(1.5));
            const label = findChild(bubble, "folderTooltipLabel");
            const original = findChild(dockLabel, "dockTooltipLabel");
            compare(label.font.family, original.font.family);
            compare(label.font.pixelSize, original.font.pixelSize);
            compare(label.font.weight, original.font.weight);
            for (const dark of [false, true]) {
                panel.dark = dark;
                dockLabel.dark = dark;
                compare(label.color, original.color);
                wait(150);
                const dir = Quickshell.env("MACSHELL_PREVIEW_DIR");
                if (dir) {
                    let done = false;
                    window.contentItem.grabToImage(function(result) {
                        result.saveToFile(dir + "/customize-folder-tooltip-" + (dark ? "dark" : "light") + ".png");
                        done = true;
                    });
                    tryVerify(function() { return done; });
                }
            }
            dockLabel.destroy();
            mouseMove(window.contentItem, window.width - 2, window.height - 2);
            tryCompare(popup, "visible", false);
        }
        function test_13_tooltip_flips_and_stays_inside_window() {
            const button = findChild(panel, "restoreFolderButton");
            const popup = findChild(window, "folderTooltip-restoreFolderButton");
            panel.customized = true;
            panel.x = -10; panel.y = -120;
            mouseMove(button, button.width / 2, button.height / 2);
            tryCompare(popup, "opened", true, 2000);
            verify(popup.below);
            verify(popup.x >= 8);
            verify(popup.x + popup.width <= window.width - 8);
            verify(popup.y >= popup.bottomAnchor.y + 6);
            mouseMove(window.contentItem, window.width - 2, window.height - 2);
            tryCompare(popup, "visible", false);
            panel.x = 48; panel.y = 30;
        }
    }
}
