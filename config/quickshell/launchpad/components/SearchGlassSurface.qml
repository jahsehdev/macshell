import "../Common" as Common
import QtQuick
import ".."

Common.LiquidGlassSurface {
    id: surface
    property var context: null
    property point offset: Qt.point(0, 0)
    signal failed()
    visible: context !== null && context.ready
    fragmentShader: Common.GlassMaterial.shaderUrl
    onStatusChanged: if (status === ShaderEffect.Error) {
        console.warn("Launchpad search glass:", log);
        failed();
    }
    src: context ? context.texture : null
    itemSize: Qt.vector2d(width, height)
    glassSize: itemSize
    srcSize: context ? context.textureSize : Qt.vector2d(1, 1)
    srcOffset: context ? Qt.vector2d(context.sourceOffset.x + offset.x,
                                                      context.sourceOffset.y + offset.y) : Qt.vector2d(0, 0)
    pad: 0
    radius: height / 2
    bezel: Math.min(height * 0.25, 12)
    dark: Theme.darkMode ? 1 : 0
    debug: 0
    shadowAmt: 0
    squircle: 0
}
