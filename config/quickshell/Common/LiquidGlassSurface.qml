import QtQuick

// Geometry and backdrop coordinates belong to each surface. Optical tuning
// belongs to GlassMaterial, including local previews of the shared intensity.
ShaderEffect {
    id: surface
    objectName: "sharedLiquidGlassSurface"
    property real materialIntensity: -1
    readonly property var material: GlassMaterial.profile(materialIntensity < 0 ? GlassMaterial.intensity : materialIntensity)
    fragmentShader: GlassMaterial.shaderUrl
    property variant src: null
    property vector2d itemSize: Qt.vector2d(width, height)
    property vector2d glassSize: itemSize
    property vector2d srcSize: Qt.vector2d(1, 1)
    property vector2d srcOffset: Qt.vector2d(0, 0)
    property real pad: 0
    property real radius: CornerTheme.panelRadius(glassSize.x, glassSize.y, 24, squircle)
    property real bezel: Math.min(glassSize.y * 0.36, 26)
    property real squircle: CornerTheme.smoothing
    property real thickness: DesktopPreferences.reduceTransparency ? 0 : material.thickness
    property real dispersion: DesktopPreferences.reduceTransparency ? 0 : material.dispersion
    property real magnify: DesktopPreferences.reduceTransparency ? 0 : material.magnify
    property real rim: DesktopPreferences.glassRim(material.rim)
    property real grain: DesktopPreferences.glassGrain(material.grain)
    property real blurPx: material.blurPx
    property real tintMix: DesktopPreferences.reduceTransparency ? 0.94 : material.tint
    property real saturation: material.saturation
    property real flatInner: material.flatInner
    property real rimTint: material.rimTint
    property real ringW: material.ringW
    property real dark: 1
    property real debug: 0
    property real shadowAmt: 0
}
