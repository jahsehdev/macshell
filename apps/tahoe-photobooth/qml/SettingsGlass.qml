import QtQuick

Item {
    id: glass
    required property Item backdrop
    required property bool dark
    required property real progress
    required property size originSize
    required property real originOffset
    readonly property bool hardwareEffects: GraphicsInfo.api !== GraphicsInfo.Software
    // A monotonic timeline drives a small, damped elastic settle. Keeping it in
    // geometry (rather than the animation) makes interrupted transitions reversible.
    readonly property real growth: 1 - Math.pow(1 - progress, 3)
        + Math.sin(3 * Math.PI * progress) * Math.sin(Math.PI * progress) * 0.025
    readonly property real surfaceLeft: (width - originSize.width) * (1 - growth)
    readonly property real surfaceTop: -originOffset * (1 - growth)
    readonly property real surfaceHeight: originSize.height + (height - originSize.height) * growth
    readonly property real surfaceRadius: 16 + (Math.min(width - surfaceLeft, surfaceHeight) / 2 - 16)
        * Math.pow(1 - progress, 2)
    readonly property real capturePadding: 8

    // Capture the menu and button together; extra padding retains the liquid rim
    // and slight overshoot. The fixed render target never includes this overlay.
    ShaderEffectSource {
        id: backdropTexture
        visible: false
        sourceItem: glass.visible && glass.hardwareEffects ? glass.backdrop : null
        sourceRect: {
            glass.progress; glass.width; glass.height;
            const position = glass.mapToItem(glass.backdrop, -glass.capturePadding,
                -glass.originOffset - glass.capturePadding);
            return Qt.rect(position.x, position.y, refraction.width, refraction.height);
        }
        textureSize: Qt.size(Math.ceil(refraction.width), Math.ceil(refraction.height))
        live: glass.visible
        smooth: true
        hideSource: false
        recursive: false
    }
    // Software rendering retains the elastic silhouette and readable material.
    Rectangle {
        x: glass.surfaceLeft; y: glass.surfaceTop
        width: glass.width - x; height: glass.surfaceHeight
        visible: !glass.hardwareEffects || refraction.status === ShaderEffect.Error
        radius: glass.surfaceRadius
        antialiasing: true
        border.width: 1
        border.color: glass.dark ? "#77777e" : "#ffffff"
        gradient: Gradient {
            GradientStop { position: 0; color: glass.dark ? "#424249" : "#fafafd" }
            GradientStop { position: 1; color: glass.dark ? "#303035" : "#e7e7ec" }
        }
    }
    ShaderEffect {
        id: refraction
        objectName: "settingsRefraction"
        x: -glass.capturePadding
        y: -glass.originOffset - glass.capturePadding
        width: glass.width + 2 * glass.capturePadding
        height: glass.height + glass.originOffset + 2 * glass.capturePadding
        visible: glass.hardwareEffects
        property var source: backdropTexture
        property vector2d captureSize: Qt.vector2d(width, height)
        property vector4d bodyRect: Qt.vector4d(glass.surfaceLeft + glass.capturePadding,
            glass.surfaceTop + glass.originOffset + glass.capturePadding,
            glass.width - glass.surfaceLeft, glass.surfaceHeight)
        property vector2d originCenter: Qt.vector2d(glass.width - glass.originSize.width / 2 + glass.capturePadding,
            glass.originSize.height / 2 + glass.capturePadding)
        property real originRadius: glass.originSize.height / 2
        property real cornerRadius: glass.surfaceRadius
        property real progress: glass.progress
        property real darkMode: glass.dark ? 1 : 0
        fragmentShader: "qrc:/shaders/settings-glass.frag.qsb"
    }
}
