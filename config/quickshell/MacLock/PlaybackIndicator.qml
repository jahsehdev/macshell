import QtQuick
import "Common" as Common

// Animated Now Playing bars follow playback and the user's motion preference.
Item {
    id: indicator
    property bool playing: false
    property real uiScale: 1
    property real phase: 0
    property bool reducedMotion: Common.DesktopPreferences.reduceMotion
    implicitWidth: 30 * uiScale
    implicitHeight: 20 * uiScale
    Accessible.role: Accessible.StaticText
    Accessible.name: playing ? "Playing" : "Paused"
    NumberAnimation on phase {
        from: 0; to: Math.PI * 2; duration: 1100; loops: Animation.Infinite
        running: indicator.visible && indicator.playing && !indicator.reducedMotion
    }
    Row {
        anchors.centerIn: parent
        height: indicator.height
        spacing: 4 * indicator.uiScale
        Repeater {
            model: 4
            Rectangle {
                required property int index
                objectName: "playbackBar" + index
                width: 3 * indicator.uiScale
                height: (indicator.playing
                    ? 6 + 14 * (0.5 + 0.5 * Math.sin(indicator.phase + index * 1.7))
                    : 5) * indicator.uiScale
                y: (indicator.height - height) / 2
                radius: width / 2
                color: "#e6ffffff"
            }
        }
    }
}
