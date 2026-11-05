pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry
import QtQuick.Controls

Button {
    id: action
    property string symbol: ""
    property real iconSize:15
    property real iconStrokeWidth:1.8
    property color ink: "#FAFAFC"
    property color fill: "#12FFFFFF"
    property bool reducedMotion: false
    property bool round: false
    property real cornerRadius: Geometry.controlRadius
    property string family: "SF Pro Text"
    implicitHeight: 30
    implicitWidth: symbol && !text ? 30 : label.implicitWidth + (symbol ? iconSize+28 : 24)
    opacity: enabled ? 1 : 0.3
    font.family: family; font.pixelSize: 12; font.weight: Font.Medium
    background: Rectangle {
        radius: action.round ? Math.min(width,height) / 2 : Geometry.radius(action.cornerRadius,width,height)
        color: action.fill
        Rectangle { anchors.fill: parent; radius: parent.radius; color: action.down ? "#18FFFFFF" : action.hovered ? "#0CFFFFFF" : "transparent" }
    }
    contentItem: Item {
        Row {
            anchors.centerIn: parent; spacing: 6
            NotchIcon { width: action.iconSize; height: width; strokeWidth:action.iconStrokeWidth; anchors.verticalCenter: parent.verticalCenter; visible: action.symbol !== ""; kind: action.symbol; ink: action.ink }
            Text { id: label; text: action.text; visible: action.text !== ""; color: action.ink; font: action.font; textFormat: Text.PlainText }
        }
    }
    HoverHandler { enabled: action.enabled; cursorShape: Qt.PointingHandCursor }
    Accessible.name: text || symbol
    NotchToolTip {
        control: action; wanted: !action.down && action.Accessible.name !== ""
        text: action.Accessible.name
    }
}
