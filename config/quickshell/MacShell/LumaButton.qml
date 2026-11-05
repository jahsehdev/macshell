pragma ComponentBehavior: Bound
import QtQuick
import "Common" as Common

Common.ContinuousRectangle {
    id: root
    required property var t
    property string text: ""
    property bool primary: false
    signal clicked()
    width: label.implicitWidth + 26
    height: 30
    radius: 8
    cornerSmoothing: 0
    opacity: enabled ? 1 : .45
    color: primary ? t.accent : (mouse.pressed ? t.buttonPressed : t.button)
    border.width: primary ? 0 : 1
    border.color: t.buttonBorder
    Accessible.role: Accessible.Button
    Accessible.name: text
    activeFocusOnTab: true
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    Text { id: label; anchors.centerIn: parent; text: root.text; color: root.primary ? "white" : root.t.text; font.family: root.t.fam; font.pixelSize: 13 }
    MouseArea { id: mouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
