import QtQuick
import QtTest
import ".." as Shell

Window {
    id: window
    visible: true
    width: 640; height: 100
    QtObject {
        id: context
        property bool liquid: true
        property var frame: window.contentItem
        property var src: null
        property rect srcRect: Qt.rect(0, 0, 640, 100)
        property bool dark: true
        property bool debug: false
    }
    Shell.SpotlightGooey {
        id: effect
        width: 640; height: 48
        pillWidth: 400
        buttonCount: 4
        ready: true
        gx: context
        shaderUrl: Qt.resolvedUrl("../../Common/LiquidGlass-spotlight-gooey.frag.qsb")
    }
    TestCase {
        name: "SpotlightGooey"
        when: window.visible
        onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
        function cleanup() { effect.finish(); }
        function test_no_transparency_dip_during_handoff() {
            const loader = findChild(effect, "spotlightOpeningGlassLoader");
            for (const progress of [0.86, 0.90, 0.93, 0.96, 0.99]) {
                effect.progress = progress;
                tryVerify(() => loader.item !== null);
                const backingAlpha = loader.item.opacity;
                compare(backingAlpha, 1);
                const coverage = effect.handoff + backingAlpha * (1 - effect.handoff);
                compare(coverage, 1);
                for (let index = 0; index < effect.buttonCount; index++)
                    compare(effect.phase(index), 1);
            }
            effect.progress = 1;
            compare(effect.handoff, 1);
            verify(!loader.active);
        }
        function test_waiting_uses_complete_capsule() {
            effect.progress = 0;
            compare(effect.handoff, 1);
            compare(effect.openingOffset, 120);
            verify(!findChild(effect, "spotlightOpeningGlassLoader").active);
        }
        function test_failure_falls_back_without_gap() {
            effect.progress = 0.93;
            effect.failed = true;
            compare(effect.handoff, 1);
            verify(!effect.morphing);
            effect.failed = false;
        }
    }
}
