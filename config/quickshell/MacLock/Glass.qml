// One Liquid Glass slab (pill, card, button) that refracts the shared, pre-blurred lock screen backdrop.
// Same uniforms / tuning as MacShell's GGlass (MacBar.qml), so it looks like the bar's popovers.
import "Common" as Corners
import QtQuick

Item {
    id: gg
    property var src: null              // ShaderEffectSource with mipmaps: the blurred scene
    property Item frame: null           // coordinate space the backdrop texture covers (the whole screen)
    readonly property bool reduced: Corners.DesktopPreferences.reduceTransparency
    property url shaderUrl: Corners.GlassMaterial.shaderUrl
    property real cornerR: 22
    property real cornerSmoothing: Corners.CornerTheme.smoothing
    property real shadowAmt: 0
    property bool dark: true
    readonly property real pad: 10
    readonly property bool failed: fx.status === ShaderEffect.Error

    // position inside `frame`; reads every ancestor's x/y so it follows animated parents
    function framePos() {
        var px = 0, py = 0, it = gg;
        while (it && it !== frame) { px += it.x; py += it.y; it = it.parent; }
        return Qt.point(px, py);
    }
    readonly property point fp: framePos()

    // flat fallback if the shader can't load
    Corners.ContinuousRectangle {
        cornerSmoothing: gg.cornerSmoothing
        visible: gg.failed || !gg.src || gg.reduced
        anchors.fill: parent
        radius: gg.cornerR
        color: Qt.rgba(0.12, 0.12, 0.14, gg.reduced ? 0.96 : 0.45)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)
    }

    Corners.LiquidGlassSurface {
        id: fx
        visible: gg.src !== null && gg.frame !== null && !gg.reduced
        x: -gg.pad; y: -gg.pad
        width: gg.width + 2 * gg.pad
        height: gg.height + 2 * gg.pad
        fragmentShader: gg.shaderUrl
        onStatusChanged: if (status === ShaderEffect.Error) console.log("[maclock] glass shader:", log)
        src: gg.src
        itemSize: Qt.vector2d(width, height)
        glassSize: Qt.vector2d(gg.width, gg.height)
        srcSize: Qt.vector2d(gg.frame ? gg.frame.width : 1, gg.frame ? gg.frame.height : 1)
        srcOffset: Qt.vector2d(gg.fp.x - gg.pad, gg.fp.y - gg.pad)
        pad: gg.pad
        radius: Corners.CornerTheme.panelRadius(gg.width,gg.height,gg.cornerR,gg.cornerSmoothing)
        bezel: Math.min(gg.height * 0.36, 26)
        dark: gg.dark ? 1 : 0
        debug: 0
        shadowAmt: gg.shadowAmt
        squircle: gg.cornerSmoothing
    }
}
