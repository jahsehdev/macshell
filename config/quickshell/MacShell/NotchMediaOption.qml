pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry
import QtQuick.Controls

CheckBox {
    id:option
    required property var menu
    implicitHeight:30;implicitWidth:parent?parent.width:280
    opacity:enabled?1:0.45
    spacing:9
    indicator:Rectangle {
        x:0;y:(option.height-height)/2;width:17;height:17;radius:Geometry.innerRadius(Geometry.controlRadius,Geometry.controlPadding,width,height)
        color:option.checked?"#087EF5":option.menu.dark?"#13FFFFFF":"#0C000000"
        border.width:1;border.color:option.checked?"#439EFF":option.menu.dark?"#66FFFFFF":"#55000000"
        Text{anchors.centerIn:parent;text:"✓";color:"white";font.pixelSize:13;font.bold:true;visible:option.checked}
    }
    contentItem:Text {leftPadding:26;text:option.text;color:option.menu.foreground;font.family:option.menu.host.family;font.pixelSize:12;verticalAlignment:Text.AlignVCenter}
    HoverHandler{cursorShape:Qt.PointingHandCursor}
}
