import QtQuick
import ".."

ShaderEffect {
    id: surface
    property var context: null
    property point offset: Qt.point(0, 0)
    signal failed()
    visible: context !== null && context.ready
    fragmentShader: Qt.resolvedUrl("../assets/folder-liquidglass.frag.qsb")
    onStatusChanged: if (status === ShaderEffect.Error) {
        console.warn("Launchpad search glass:", log);
        failed();
    }
    property variant src: context ? context.texture : null
    property vector2d itemSize: Qt.vector2d(width, height)
    property vector2d glassSize: itemSize
    property vector2d srcSize: context ? context.textureSize : Qt.vector2d(1, 1)
    property vector2d srcOffset: context ? Qt.vector2d(context.sourceOffset.x + offset.x,
                                                      context.sourceOffset.y + offset.y) : Qt.vector2d(0, 0)
    property real pad: 0
    property real radius: height / 2
    property real bezel: Math.min(height * 0.25, 12)
    property real thickness: 14 * Theme.menuGlassLiquid
    property real dispersion: 0.04 * Theme.menuGlassLiquid
    property real blurPx: 1.5
    property real tintMix: Theme.searchTintMix
    property real saturation: 1.15
    property real dark: Theme.darkMode ? 1 : 0
    property real debug: 0
    property real rim: Theme.menuGlassRim
    property real grain: 0.001
    property real magnify: 0.025 * Theme.menuGlassLiquid
    property real shadowAmt: 0
    property real rimTint: 0
    property real ringW: 0
    property real flatInner: 1
    property real squircle: 0
}
