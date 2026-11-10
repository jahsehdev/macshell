pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "NotchShape.js" as Shape
import "NotchGeometry.js" as Geometry
import "Common" as Common

Item {
    id: glass
    required property var host
    property bool failed: false
    readonly property real margin: 128
    readonly property real cropWidth: width + margin * 2
    readonly property real cropHeight: height + margin * 2
    // Use the same effective blur as System Settings, including clear values.
    readonly property real materialBlurRadius: host.glassBlurRadius
    readonly property var material: Common.GlassMaterial.profile(Common.GlassMaterial.intensity)
    readonly property real downsample: materialBlurRadius >= 8 ? 0.5 : 1
    readonly property real blurAmount: Math.min(1, materialBlurRadius * 1.4 * downsample / 64)
    readonly property real wing: host.mode === "attached" ? Math.min(Geometry.wing(host.mode, host.shapeMix, host.wideShape) * (1 + (host.cornerScale - 1) * host.shapeMix), width / 2) : 0
    readonly property real lensRadius: host.mode === "attached"
        ? Math.min(height / 2, Math.max(0, (width - 2 * wing) / 2), 12 * (1 - host.shapeMix) + Geometry.panelRadius * host.cornerScale * host.shapeMix)
        : Math.min(width / 2, height / 2, height / 2 * (1 - host.shapeMix) + Geometry.panelRadius * host.cornerScale * host.shapeMix)

    // Fallback scene when a live compositor backdrop has not arrived yet.
    Item {
        id: wallpaper
        width: glass.host.screenSize.width; height: glass.host.screenSize.height
        visible: false
        Rectangle { anchors.fill: parent; color: "#34383B" }
        Image { anchors.fill: parent; source: glass.host.wallpaperUrl; fillMode: Image.PreserveAspectCrop; asynchronous: true }
    }
    ShaderEffectSource {
        id: captured
        sourceItem: glass.host.backdrop || wallpaper
        sourceRect: Qt.rect(glass.host.backdropPosition.x - glass.margin, glass.host.backdropPosition.y - glass.margin, glass.cropWidth, glass.cropHeight)
        textureSize: Qt.size(Math.max(1, Math.ceil(glass.cropWidth * glass.downsample)), Math.max(1, Math.ceil(glass.cropHeight * glass.downsample)))
        hideSource: true; visible: false
    }
    MultiEffect {
        id: frost
        objectName: "notchGlassBlur"
        source: captured
        width: Math.ceil(glass.cropWidth * glass.downsample); height: Math.ceil(glass.cropHeight * glass.downsample)
        blurEnabled: glass.materialBlurRadius > 0; blurMax: 64; blur: glass.blurAmount
        autoPaddingEnabled: false; visible: false
    }
    ShaderEffectSource { id: blurred; sourceItem: frost; visible: false }
    Canvas {
        id: shape
        width: glass.width; height: glass.height
        visible: false
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: glass.host
            function onShapeProgressChanged() { shape.requestPaint(); }
            function onModeChanged() { shape.requestPaint(); }
            function onActivityChanged() { shape.requestPaint(); }
            function onCornerScaleChanged() { shape.requestPaint(); }
        }
        onPaint: {
            const c = getContext("2d"); c.reset();
            Shape.trace(c, width, height, glass.host.mode, glass.host.shapeMix, glass.host.wideShape, glass.host.cornerScale);
            c.fillStyle = "white"; c.fill();
        }
    }
    ShaderEffectSource { id: mask; sourceItem: shape; hideSource: true; visible: false }
    ShaderEffect {
        id: lens
        objectName: "notchGlassLens"
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("Common/LiquidGlass-notch.frag.qsb")
        onStatusChanged: if (status === ShaderEffect.Error) { glass.failed = true; console.warn("[dynamic-notch-glass]", log); }
        property variant src: glass.materialBlurRadius > 0 ? blurred : captured
        property variant clearSrc: glass.materialBlurRadius > 0 ? blurred : captured
        property variant maskTex: mask
        property vector2d itemSize: Qt.vector2d(width, height)
        property vector2d cropSize: Qt.vector2d(glass.cropWidth, glass.cropHeight)
        property real captureMargin: glass.margin
        property real strength: glass.host.shapeMix
        property real wingSize: glass.wing
        property real radius: glass.lensRadius
        property vector4d optics: Qt.vector4d(glass.material.thickness, glass.material.dispersion, glass.material.magnify, glass.material.saturation)
        property vector4d finish: Qt.vector4d(glass.material.tint, Common.DesktopPreferences.glassRim(glass.material.rim), Common.DesktopPreferences.glassGrain(glass.material.grain), glass.material.blurPx)
    }
}
