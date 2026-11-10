pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    property real micVolume: 0
    property bool animate: visible
    property real phase: 0
    // Versioned resource avoids Qt reusing the previous material on live reload.
    property url shaderUrl: Qt.resolvedUrl("Common/LiquidGlass-voice.frag.qsb")
    property bool failed: false
    property bool glassBackground: true
    property url wallpaper: ""
    property Item backdrop: null
    property size screenSize: Qt.size(1920, 1080)
    property point screenPosition: Qt.point(0, 0)
    readonly property real level: Math.max(0, Math.min(1, isFinite(micVolume) ? micVolume : 0))
    property real animatedLevel: level
    Behavior on animatedLevel { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }
    readonly property bool shaderAvailable: GraphicsInfo.api !== GraphicsInfo.Software && !failed
    // Matches LumaSearchView.voiceDiameter.
    implicitWidth: 88; implicitHeight: 88
    // One diameter in both axes, even if the available container is rectangular.
    Item {
        id: sphere
        anchors.centerIn: parent
        anchors.alignWhenCentered: false
        width: Math.min(root.width, root.height)
        height: width
        Loader {
            anchors.fill: parent
            active: root.glassBackground
            sourceComponent: LumaSearchGlass {
                radius: width / 2
                tintMix: 0
                frostAmount: 0
                rimStrength: 0
                backdrop: root.backdrop; wallpaper: root.wallpaper
                screenSize: root.screenSize; screenPosition: root.screenPosition
            }
        }
        ShaderEffect {
            id: effect
            objectName: "lumaMicOrbShader"
            anchors.fill: parent
            visible: root.shaderAvailable
            fragmentShader: root.shaderUrl
            property real micVolume: root.animatedLevel
            property real iTime: root.phase
            property vector2d resolution: Qt.vector2d(width, height)
            onStatusChanged: if (status === ShaderEffect.Error) root.failed = true
        }
        // A centered wave over the same circular glass on software renderers.
        Rectangle {
            objectName: "lumaMicWaveFallback"
            visible: !root.shaderAvailable
            anchors.centerIn: parent
            anchors.alignWhenCentered: false
            width: parent.width * 0.84
            height: 2 + root.animatedLevel * 7
            radius: height / 2
            antialiasing: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#70a1ffff" }
                GradientStop { position: 0.3; color: "#ff98c7ff" }
                GradientStop { position: 0.5; color: "#ffffffff" }
                GradientStop { position: 0.7; color: "#ffffdd95" }
                GradientStop { position: 1; color: "#70ff9bd8" }
            }
        }
    }
    FrameAnimation {
        running: root.animate && root.visible && root.shaderAvailable
        onTriggered: root.phase = (root.phase + Math.min(frameTime, 0.05) * (0.8 + 0.65 * root.animatedLevel)) % 3600
    }
}
