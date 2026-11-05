pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry
import QtQuick.Controls

Button {
    id: button
    required property var host
    required property string symbol
    property bool round: false
    property bool filledIcon: false
    property bool active: false
    property real iconSize: 19
    property real strokeWidth: 2.8
    property color ink: "#FFFFFF"
    property bool tooltipEnabled: true
    implicitWidth: 30; implicitHeight: 30
    Accessible.name: symbol
    background: Rectangle {
        radius: button.round ? Math.min(width,height)/2 : Geometry.radius(Geometry.controlRadius,width,height)
        color: button.down ? "#25FFFFFF" : button.hovered ? "#16FFFFFF" : button.active ? "#22FFFFFF" : button.round ? "#12FFFFFF" : "transparent"
        Behavior on color { ColorAnimation { duration:button.host.reducedMotion?0:120 } }
    }
    contentItem: Item {
        NotchIcon { anchors.centerIn:parent;width:button.iconSize;height:width;kind:button.symbol;filled:button.filledIcon;ink:button.ink;strokeWidth:button.strokeWidth }
        Rectangle { anchors.horizontalCenter:parent.horizontalCenter;anchors.bottom:parent.bottom;width:3;height:3;radius:1.5;color:"white";visible:button.active }
    }
    HoverHandler { enabled:button.enabled;cursorShape:Qt.PointingHandCursor }
    NotchToolTip {
        objectName:"notchMusicTooltip"+button.symbol
        control:button;wanted:button.tooltipEnabled && !button.down;text:button.Accessible.name
    }
}
