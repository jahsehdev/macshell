import "Common" as Common
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: goo
    required property var gx
    required property url shaderUrl
    property bool ready: false
    property bool requested: false
    property real bodyY: 52
    property real bodyHeight: 174
    property real progress: 1
    property bool failed: false
    readonly property bool available: ready && gx.liquid && !failed && GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool morphing: progress < 1
    readonly property real spread: {
        const t = Math.min(1, progress / 0.88), back = t - 1;
        return 1 + 1.55 * back * back * back + 0.55 * back * back;
    }
    readonly property vector4d bodyShape: Qt.vector4d(
        width / 2,
        22 + (bodyY + bodyHeight / 2 - 22) * spread,
        width / 2 * (0.16 + 0.84 * spread),
        bodyHeight / 2 * (0.08 + 0.92 * spread))
    readonly property real bodyRadius: 18 + (Math.min(bodyShape.z, bodyShape.w) - 18) * (1 - smooth(0.2, 0.85, progress))
    readonly property real padding: 14
    readonly property point framePosition: {
        let px = 0, py = 0, item = goo;
        while (item && item !== gx.frame) { px += item.x; py += item.y; item = item.parent; }
        return Qt.point(px, py);
    }

    function smooth(a, b, value) {
        const t = Math.max(0, Math.min(1, (value - a) / (b - a)));
        return t * t * (3 - 2 * t);
    }
    function restart() { opening.stop(); progress = 0; opening.start(); }
    onRequestedChanged: if (requested) restart(); else opening.stop()
    Component.onCompleted: if (requested) restart()
    NumberAnimation { id: opening; target: goo; property: "progress"; from: 0; to: 1; duration: 520; easing.type: Easing.Linear }

    Loader {
        x: -goo.padding; y: -goo.padding
        width: goo.width + 2 * goo.padding; height: goo.height + 2 * goo.padding
        // Keep the settled silhouette on the same surface. Crossfading into
        // separate panes changes the combined opacity and refraction at rest.
        active: goo.available && goo.visible
        sourceComponent: Common.LiquidGlassSurface {
            width: goo.width + 2 * goo.padding; height: goo.height + 2 * goo.padding
            opacity: goo.gx.paneOpacity
            fragmentShader: goo.shaderUrl
            onStatusChanged: if (status === ShaderEffect.Error) goo.failed = true
            src: goo.gx.src
            itemSize: Qt.vector2d(width, height)
            glassSize: Qt.vector2d(goo.width, goo.height)
            srcSize: Qt.vector2d(goo.gx.srcRect.width, goo.gx.srcRect.height)
            srcOffset: Qt.vector2d(goo.framePosition.x - goo.padding - goo.gx.srcRect.x, goo.framePosition.y - goo.padding - goo.gx.srcRect.y)
            pad: goo.padding
            radius: 22
            bezel: 26
            dark: goo.gx.dark ? 1 : 0
            debug: goo.gx.debug ? 1 : 0
            shadowAmt: 0.5
            squircle: 0
            property vector4d lumaInput: Qt.vector4d(goo.width / 2, 22, goo.width / 2, 22)
            property vector4d lumaBody: goo.bodyShape
            property real lumaBodyRadius: goo.bodyRadius
            property real lumaMergeRadius: 0.5 + 30 * (1 - goo.smooth(0.3, 0.92, goo.progress))
        }
    }
}
