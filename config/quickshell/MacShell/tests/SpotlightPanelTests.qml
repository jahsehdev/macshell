import QtQuick
import QtTest
import ".." as Shell

Window {
    id: window
    visible: true
    width: 640; height: 500
    Component {
        id: panelComponent
        Shell.SpotlightPanel {
            width: 640; height: 450
            capsuleWidth: 400
            Rectangle { objectName: "surface"; anchors.fill: parent; color: "black" }
        }
    }
    TestCase {
        name: "SpotlightPanel"
        when: window.visible
        onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
        function makePanel() {
            return createTemporaryObject(panelComponent, parent);
        }
        function test_unfolds_without_scaling_content() {
            const panel = makePanel();
            compare(panel.revealedWidth, 400);
            compare(panel.revealedHeight, 48);
            verify(!panel.visible);
            panel.active = true;
            wait(90);
            verify(panel.reveal > 0 && panel.reveal < 1);
            verify(panel.revealedWidth > 400 && panel.revealedWidth < 640);
            verify(panel.revealedHeight > 48 && panel.revealedHeight < 450);
            compare(findChild(panel, "surface").scale, 1);
            tryCompare(panel, "reveal", 1);
            compare(panel.revealedWidth, 640);
            compare(panel.revealedHeight, 450);
            panel.active = false;
            verify(!panel.enabled);
            tryCompare(panel, "visible", false);
        }
        function test_interrupt_and_reverse() {
            const panel = makePanel();
            panel.active = true;
            wait(80);
            panel.active = false;
            wait(40);
            panel.active = true;
            tryCompare(panel, "reveal", 1);
            verify(panel.visible && panel.enabled);
        }
        function test_reduced_motion_only_fades() {
            const panel = makePanel();
            panel.reduceMotion = true;
            panel.active = true;
            compare(panel.revealedWidth, 640);
            compare(panel.revealedHeight, 450);
            tryCompare(panel, "reveal", 1);
        }
        function test_shortcut_opens_directly() {
            const panel = makePanel();
            panel.animateEntrance = false;
            panel.active = true;
            compare(panel.reveal, 1);
            compare(panel.revealedHeight, 450);
        }
    }
}
