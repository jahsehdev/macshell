import "Common" as Common
pragma ComponentBehavior: Bound
import QtQuick

// Opening-only liquid separation. The controls keep their normal Row slots;
// their visuals and this shared glass silhouette read the same button shapes.
Item {
    id: goo
    required property var gx
    required property url shaderUrl
    property bool ready: false
    property real pillWidth: 340
    property real pitch: 60
    property int buttonCount: 5
    property int openingDelay: 1000
    property real progress: 1
    property bool failed: false
    readonly property bool available: ready && gx.liquid && !failed
    readonly property bool waiting: available && progress === 0
    readonly property real handoff: available && !waiting ? smooth(0.86, 1, progress) : 1
    readonly property bool morphing: available && progress < 1
    // Center the lone pill, then slide it left as the buttons separate to its right.
    readonly property real openingOffset: (width - pillWidth) / 2 * (1 - smooth(0, 0.86, progress))
    readonly property real padding: 10
    readonly property point framePosition: {
        var px = 0, py = 0, item = goo;
        while (item && item !== gx.frame) {
            px += item.x; py += item.y; item = item.parent;
        }
        return Qt.point(px, py);
    }

    function smooth(a, b, value) {
        var t = Math.max(0, Math.min(1, (value - a) / (b - a)));
        return t * t * (3 - 2 * t);
    }

    function phase(index) {
        return Math.max(0, Math.min(1, (progress - index * 0.035) / 0.72));
    }

    function buttonShape(index) {
        if (index >= buttonCount) return Qt.vector4d(-10000, -10000, 1, 1);
        var t = phase(index), back = t - 1;
        // A small overshoot, with a stretch that settles before the handoff.
        var spread = 1 + 1.55 * back * back * back + 0.55 * back * back;
        var size = 0.62 + 0.38 * (1 - Math.pow(1 - t, 3));
        var stretch = 1 + 0.17 * Math.sin(Math.PI * t);
        return Qt.vector4d(pillWidth - 24 + (60 + index * pitch) * spread,
                           height / 2, 24 * size * stretch, 24 * size / stretch);
    }

    function restart() {
        opening.stop();
        progress = available ? 0 : 1;
        if (available) opening.start();
    }

    function finish() {
        opening.stop();
        progress = 1;
    }

    // Stopping on dismissal freezes the current silhouette during the existing
    // close fade; reopening always starts a fresh, complete separation.
    function pause() { opening.stop(); }
    SequentialAnimation {
        id: opening
        // Hold the merged silhouette, then keep the complete gooey separation.
        PauseAnimation { duration: goo.openingDelay }
        NumberAnimation {
            target: goo; property: "progress"
            from: 0; to: 1; duration: 760
            easing.type: Easing.Linear
        }
    }

    Loader {
        objectName: "spotlightOpeningGlassLoader"
        x: -goo.padding; y: -goo.padding
        width: goo.width + 2 * goo.padding
        height: goo.height + 2 * goo.padding
        active: goo.morphing && !goo.waiting && goo.visible
        sourceComponent: Common.LiquidGlassSurface {
            objectName: "spotlightOpeningGlass"
            width: goo.width + 2 * goo.padding
            height: goo.height + 2 * goo.padding
            // Keep an opaque backing while the settled surfaces fade in above.
            // Complementary alpha fades expose the backdrop at mid-handoff
            // (0.5 over 0.5 covers only 0.75), producing a visible flash.
            // The loader retires only once the settled surfaces are fully opaque.
            opacity: 1
            fragmentShader: goo.shaderUrl
            onStatusChanged: if (status === ShaderEffect.Error) {
                goo.failed = true;
                goo.finish();
            }
            src: goo.gx.src
            itemSize: Qt.vector2d(width, height)
            glassSize: Qt.vector2d(goo.width, goo.height)
            srcSize: Qt.vector2d(goo.gx.srcRect.width, goo.gx.srcRect.height)
            srcOffset: Qt.vector2d(goo.framePosition.x - goo.padding - goo.gx.srcRect.x,
                                                   goo.framePosition.y - goo.padding - goo.gx.srcRect.y)
            pad: goo.padding
            radius: 24
            bezel: goo.height * 0.36
            dark: goo.gx.dark ? 1 : 0
            debug: goo.gx.debug ? 1 : 0
            shadowAmt: 0
            squircle: 0 // Match the capsule search bar throughout the gooey opening.
            property real pillWidth: goo.pillWidth
            property real mergeRadius: 1 + 31 * goo.smooth(0, 0.15, goo.progress) * (1 - goo.smooth(0.35, 0.88, goo.progress))
            property vector4d button0: goo.buttonShape(0)
            property vector4d button1: goo.buttonShape(1)
            property vector4d button2: goo.buttonShape(2)
            property vector4d button3: goo.buttonShape(3)
            property vector4d button4: goo.buttonShape(4)
        }
    }
}
