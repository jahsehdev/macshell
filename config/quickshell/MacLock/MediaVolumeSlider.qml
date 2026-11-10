import QtQuick
import QtQuick.Controls as Controls
import "Common" as Common

Common.GlassSlider {
    id: slider
    property bool muted: false
    signal muteRequested()
    dark: true
    accentColor: "#62d58a"
    trackColor: Qt.rgba(0, 0, 0, 0.30)
    handleColor: "white"
    from: 0; to: 1; stepSize: 0.01
    padding: 0
    leftPadding: 28 * uiScale
    rightPadding: 34 * uiScale
    implicitWidth: 220 * uiScale
    implicitHeight: 26 * uiScale
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    opacity: enabled ? 1 : 0.4
    Accessible.name: "System volume"
    HoverHandler {
        id: knobHover
        parent: slider.handle
        enabled: slider.enabled
    }
    Binding {
        target: slider.handle
        property: "pressProgress"
        value: slider.pressed ? 1 : (knobHover.hovered ? 0.35 : 0)
    }
    Glyph {
        objectName: "lockMediaVolumeLevel"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 20 * slider.uiScale; height: width
        kind: "speaker"
        level: slider.muted ? 0 : slider.value * 3
        color: Qt.rgba(1, 1, 1, 0.85)
        Accessible.role: Accessible.StaticText
        Accessible.name: slider.muted ? "Muted" : "Volume " + Math.round(slider.value * 100) + "%"
    }
    Controls.ToolButton {
        id: muteButton
        objectName: "lockMediaMuteButton"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 28 * slider.uiScale; height: width
        padding: 4 * slider.uiScale
        focusPolicy: Qt.StrongFocus
        Accessible.name: slider.muted ? "Unmute" : "Mute"
        onClicked: slider.muteRequested()
        contentItem: Glyph {
            kind: "speaker"; level: 0
            color: slider.muted ? "#94e5ac" : "white"
        }
        background: Rectangle {
            radius: 7 * slider.uiScale
            color: Qt.rgba(1, 1, 1, muteButton.down ? 0.22 : (muteButton.hovered ? 0.12 : 0))
            border.width: muteButton.visualFocus ? 1 : 0
            border.color: "#94e5ac"
        }
        Controls.ToolTip.visible: hovered
        Controls.ToolTip.text: slider.muted ? "Unmute" : "Mute"
    }
}
