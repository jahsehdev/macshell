pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

Item {
    id: glass
    property url wallpaper: ""
    property Item backdrop: null
    property size screenSize: Qt.size(1920, 1080)
    property point screenPosition: Qt.point(0, 0)
    property real radius: 30
    property real tintMix: 0.32
    property real rimStrength: 0.40
    // Zero samples the sharp backdrop directly; one keeps the old search
    // frosting (two 64 px blur passes). The default is a light frost so the
    // backdrop stays readable through the glass.
    property real frostAmount: 0.26
    readonly property real frost: Math.max(0, Math.min(1, frostAmount))
    property size captureSize: Qt.size(width + 256, height + 256)
    property bool failed: false
    readonly property bool available: !failed && GraphicsInfo.api !== GraphicsInfo.Software

    Rectangle {
        anchors.fill: parent
        visible: !glass.available
        radius: glass.radius
        color: "#e61c1c20"
        border.width: 1; border.color: "#55ffffff"
    }
    Loader {
        anchors.fill: parent
        // Preserve the blur/shader objects while the cached menu is hidden.
        active: glass.available
        sourceComponent: Item {
            readonly property real margin: 128
            Item {
                id: scene
                visible: glass.backdrop === null
                width: glass.captureSize.width; height: glass.captureSize.height
                Rectangle { anchors.fill: parent; color: "#49443d" }
                Image {
                    x: 128 - glass.screenPosition.x; y: 128 - glass.screenPosition.y
                    width: glass.screenSize.width; height: glass.screenSize.height
                    source: glass.wallpaper; fillMode: Image.PreserveAspectCrop
                    asynchronous: true; smooth: true
                }
            }
            ShaderEffectSource {
                id: texture
                sourceItem: glass.backdrop || scene
                sourceRect: glass.backdrop ? Qt.rect(glass.screenPosition.x - 128, glass.screenPosition.y - 128, scene.width, scene.height) : Qt.rect(0, 0, scene.width, scene.height)
                hideSource: true; visible: false
            }
            MultiEffect {
                id: firstBlur
                source: texture; width: scene.width; height: scene.height
                blurEnabled: true; blurMax: 64; blur: glass.frost
                autoPaddingEnabled: false; visible: false
            }
            ShaderEffectSource { id: firstTexture; sourceItem: firstBlur; visible: false }
            MultiEffect {
                id: secondBlur
                source: firstTexture; width: scene.width; height: scene.height
                blurEnabled: true; blurMax: 64; blur: 0.75 * glass.frost
                autoPaddingEnabled: false; visible: false
            }
            ShaderEffectSource { id: blurred; sourceItem: secondBlur; visible: false }
            ShaderEffect {
                x: -10; y: -10; width: glass.width + 20; height: glass.height + 20
                fragmentShader: Qt.resolvedUrl("liquidglass.frag.qsb")
                onStatusChanged: if (status === ShaderEffect.Error) glass.failed = true
                property variant src: glass.frost > 0 ? blurred : texture
                property vector2d itemSize: Qt.vector2d(width, height)
                property vector2d glassSize: Qt.vector2d(glass.width, glass.height)
                property vector2d srcSize: Qt.vector2d(scene.width, scene.height)
                property vector2d srcOffset: Qt.vector2d(118, 118)
                property real pad: 10
                property real radius: glass.radius
                property real bezel: 22
                property real thickness: 22
                property real dispersion: 0.04
                property real magnify: 0.04
                property real rim: glass.rimStrength
                property real grain: 0.006 * glass.frost
                property real blurPx: 1.5 * glass.frost
                property real tintMix: glass.tintMix
                property real saturation: 1 + 0.15 * glass.frost
                property real dark: 1
                property real debug: 0
                property real shadowAmt: 0
                property real flatInner: 1 - glass.frost
                property real rimTint: 1
                property real ringW: 1
                property real squircle: 0
            }
        }
    }
}
