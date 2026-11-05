pragma ComponentBehavior: Bound
import QtQuick
import "NotchPomodoroStyle.js" as Style

Item {
    id: compact
    required property var host
    readonly property var tools: host.tools
    readonly property color tint: "#FF9F0A"
    Row {
        x: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 6
        NotchPomodoroButton {
            reducedMotion: compact.host.reducedMotion
            iconSize: 14; objectName: "notchPomodoroCompactToggle"
            implicitWidth: 24; implicitHeight: 24; round: true
            symbol: compact.tools.pomodoro.state === "running" ? "pomoPause" : "pomoPlay"
            fill: "#382506"; ink: compact.tint; family: compact.host.family
            Accessible.name: compact.tools.pomodoro.state === "running" ? "Pause timer" : compact.tools.pomodoro.state === "finished" ? "Start next session" : "Resume timer"
            onClicked: compact.tools.togglePomodoro()
        }
        NotchPomodoroButton {
            reducedMotion: compact.host.reducedMotion
            iconSize: 14; objectName: "notchPomodoroCompactClose"
            implicitWidth: 24; implicitHeight: 24; round: true
            symbol: "close"; fill: "#252528"; ink: "#B4B4BF"; family: compact.host.family
            Accessible.name: "Hide Pomodoro controls, keep timer running"
            onClicked: {compact.tools.pomodoroDismissed=true; compact.host.close();}
        }
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 6
        Text {
            anchors.baseline: timeText.baseline
            text: compact.tools.pomodoro.state === "paused" ? "Paused" : compact.tools.pomodoro.state === "finished" ? "Done" : Style.phaseName(compact.tools.pomodoro.mode)
            color: compact.tint; font.family: compact.host.family; font.pixelSize: 12; font.weight: Font.DemiBold
        }
        Text {
            id: timeText; objectName: "notchPomodoroCompactTime"
            text: Style.time(compact.tools.pomodoroLeft)
            color: compact.tint; font.family: compact.host.family; font.pixelSize: 16; font.weight: Font.DemiBold; font.features: ({"tnum":1})
        }
    }
}
