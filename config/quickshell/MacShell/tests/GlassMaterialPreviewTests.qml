import QtQuick
import QtTest
import Quickshell.Io
import "../Common" as Common
import ".." as Shell

Window {
    id: window
    visible: true
    width: 560; height: 420
    Shell.GlassMaterialPreview {
        id: preview
        x: 20; y: 20; width: 400
        value: 0
        reducedTransparency: false
        onMoved: value => preview.value = value
        t: QtObject {
            property bool dark: false
            property string fam: "sans-serif"
            property color text2: "#777777"
            property color accent: "#007aff"
            property color track: "#dddddd"
        }
    }
    FileView {
        id: saved
        path: Common.GlassMaterial.configDir + "/liquidglass.json"
        printErrors: false
    }
    TestCase {
        name: "GlassMaterialPreview"
        when: window.visible
        onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
        function cleanup() { console.log("RESULT", qtest_results.functionName, qtest_results.failed ? "FAIL" : "PASS"); }
        function init() {
            preview.value = 0;
            preview.reducedTransparency = false;
            const page = findChild(preview, "appleParkPage");
            page.cancelFlick();
            page.contentY = 0;
            findChild(preview, "liquidGlassSlider").focus = false;
            mouseMove(window.contentItem, 0, 0);
        }
        function test_value_label_tracks_knob() {
            const slider = findChild(preview, "liquidGlassSlider");
            const label = findChild(preview, "liquidGlassValueLabel");
            slider.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => label.visible && label.opacity === 1);
            for (const width of [260, 400, 500]) {
                preview.width = width;
                for (const value of [0, 0.21, 0.5, 1]) {
                    preview.value = value;
                    compare(label.text, Math.round(value * 100) + "% tinted");
                    const knobX = slider.x + slider.handle.x + slider.handle.width / 2;
                    fuzzyCompare(label.x + label.tailX, knobX, 0.1);
                    verify(label.x >= 0 && label.x + label.width <= width);
                    verify(label.y + label.height < slider.y + slider.handle.y);
                }
            }
            preview.width = 400;
            slider.focus = false;
            mousePress(slider, slider.width * 0.25, slider.height / 2);
            tryVerify(() => label.visible);
            mouseMove(slider, slider.width * 0.75, slider.height / 2, 10, Qt.LeftButton);
            compare(label.text, Math.round(preview.value * 100) + "% tinted");
            fuzzyCompare(label.x + label.tailX, slider.x + slider.handle.x + slider.handle.width / 2, 0.1);
            mouseRelease(slider, slider.width * 0.75, slider.height / 2);
            mouseMove(window.contentItem, 0, 0);
            tryVerify(() => !label.visible);
        }
        function test_scroll_to_address() {
            const page = findChild(preview, "appleParkPage");
            const address = findChild(preview, "appleParkAddress");
            verify(page.contentHeight > page.height);
            mouseWheel(page, page.width / 2, page.height * 0.7, 0, -120);
            tryVerify(() => page.contentY > 0);
            page.cancelFlick();
            page.contentY = page.contentHeight - page.height;
            const location = address.mapToItem(page, 0, 0);
            verify(location.y >= 0);
            verify(location.y + address.height <= page.height);
            compare(preview.value, 0, "Scrolling must leave the glass slider unchanged");
            page.contentY = 0;
            mouseDrag(page, page.width / 2, page.height * 0.7, 0, -80);
            tryVerify(() => page.contentY > 0);
        }
        function test_drag_and_keyboard() {
            const slider = findChild(preview, "liquidGlassSlider");
            verify(slider !== null);
            mouseClick(slider, slider.width / 2, slider.height / 2);
            fuzzyCompare(preview.value, 0.5, 0.02);
            mouseDrag(slider, slider.width / 2, slider.height / 2, slider.width, 0);
            compare(preview.value, 1);
            mouseDrag(slider, slider.width - 10, slider.height / 2, -slider.width, 0);
            compare(preview.value, 0);
            slider.forceActiveFocus();
            keyClick(Qt.Key_Right);
            fuzzyCompare(preview.value, 0.01, 0.001);
            keyClick(Qt.Key_End);
            compare(preview.value, 1);
            keyClick(Qt.Key_Home);
            compare(preview.value, 0);
        }
        function test_accessibility_override() {
            preview.value = 0.37;
            preview.reducedTransparency = true;
            const slider = findChild(preview, "liquidGlassSlider");
            verify(!slider.enabled);
            compare(preview.amount, 1);
            mouseClick(slider, slider.width - 1, slider.height / 2);
            compare(preview.value, 0.37);
            preview.reducedTransparency = false;
            compare(preview.amount, 0.37);
        }
        function test_z_shared_persistence() {
            Common.GlassMaterial.setMode("tinted");
            compare(Common.GlassMaterial.intensity, 1);
            Common.GlassMaterial.setMode("clear");
            compare(Common.GlassMaterial.intensity, 0);
            Common.GlassMaterial.setIntensity(0.2);
            Common.GlassMaterial.setIntensity(0.8);
            Common.GlassMaterial.setIntensity(0.37);
            compare(Common.GlassMaterial.intensity, 0.37);
            wait(350);
            saved.reload();
            tryVerify(() => saved.text().includes("intensity"));
            const state = JSON.parse(saved.text());
            compare(state.intensity, 0.37);
        }
        function test_resize_and_external_value() {
            const slider = findChild(preview, "liquidGlassSlider");
            preview.width = 260;
            preview.value = 0.63;
            compare(slider.value, 0.63);
            verify(slider.width > 0);
            preview.width = 500;
            preview.value = 0.22;
            compare(slider.value, 0.22);
            preview.width = 400;
        }
    }
}
