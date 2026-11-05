pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Button {
    id: button
    property bool dark: false
    property bool selected: false
    property bool subtle: false
    property bool round: false
    property string hint: ""
    property color foreground: dark ? "#eeeeef" : "#3e3e42"
    implicitHeight: 30
    implicitWidth: 80
    focusPolicy: Qt.StrongFocus
    Accessible.name: hint || text
    background: Rectangle {
        radius: button.round ? Math.min(width, height) / 2 : 6
        color: button.selected ? "#245e95ff" : button.down ? (button.dark ? "#626269" : "#c9c9ce")
            : button.hovered ? (button.dark ? "#505057" : "#d6d6da")
            : button.subtle ? "transparent" : button.dark ? "#424249" : "#dddddf"
        border.width: button.selected || button.activeFocus ? 2 : 0
        border.color: "#347cff"
    }
    contentItem: Text {
        text: button.text
        font: button.font
        color: button.foreground
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    font.family: "sans-serif"
    font.pixelSize: 13
    ToolTip.visible: hovered && hint !== ""
    ToolTip.text: hint
    ToolTip.delay: 650
}
