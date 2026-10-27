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
    property real progress: 1
    property bool failed: false
    readonly property bool available: ready && gx.liquid && !failed
    readonly property real handoff: available ? smooth(0.86, 1, progress) : 1
    readonly property bool morphing: available && progress < 1
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
        return Qt.vector4d(pillWidth - 12 + (48 + index * pitch) * spread,
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
    NumberAnimation {
        id: opening
        target: goo; property: "progress"
        from: 0; to: 1; duration: 760
        easing.type: Easing.Linear
    }

    Loader {
        x: -goo.padding; y: -goo.padding
        width: goo.width + 2 * goo.padding
        height: goo.height + 2 * goo.padding
        active: goo.morphing && goo.visible
        sourceComponent: ShaderEffect {
            width: goo.width + 2 * goo.padding
            height: goo.height + 2 * goo.padding
            opacity: 1 - goo.handoff
            fragmentShader: goo.shaderUrl
            onStatusChanged: if (status === ShaderEffect.Error) {
                goo.failed = true;
                goo.finish();
            }
            property variant src: goo.gx.src
            property vector2d itemSize: Qt.vector2d(width, height)
            property vector2d glassSize: Qt.vector2d(goo.width, goo.height)
            property vector2d srcSize: Qt.vector2d(goo.gx.srcRect.width, goo.gx.srcRect.height)
            property vector2d srcOffset: Qt.vector2d(goo.framePosition.x - goo.padding - goo.gx.srcRect.x,
                                                   goo.framePosition.y - goo.padding - goo.gx.srcRect.y)
            property real pad: goo.padding
            property real radius: 24
            property real bezel: goo.height * 0.36
            property real thickness: 22 * goo.gx.strength * goo.gx.liquidMul * 1.6
            property real dispersion: 0.06 * goo.gx.strength * goo.gx.liquidMul * 1.3
            property real magnify: 0.05 * goo.gx.strength * goo.gx.liquidMul * 1.6
            property real rim: goo.gx.rim
            property real grain: goo.gx.grain * 0.2
            property real blurPx: 1.5
            property real tintMix: goo.gx.tint * 0.55
            property real saturation: 1.25
            property real dark: goo.gx.dark ? 1 : 0
            property real debug: goo.gx.debug ? 1 : 0
            property real shadowAmt: 0
            property real flatInner: 0
            property real rimTint: goo.gx.rimTint
            property real ringW: goo.gx.ringW
            property real squircle: 0 // Match the capsule search bar throughout the gooey opening.
            property real pillWidth: goo.pillWidth
            property real mergeRadius: 1 + 31 * (1 - goo.smooth(0.35, 0.88, goo.progress))
            property vector4d button0: goo.buttonShape(0)
            property vector4d button1: goo.buttonShape(1)
            property vector4d button2: goo.buttonShape(2)
            property vector4d button3: goo.buttonShape(3)
            property vector4d button4: goo.buttonShape(4)
        }
    }
}
