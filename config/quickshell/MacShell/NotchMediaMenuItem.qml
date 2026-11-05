pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry
import QtQuick.Controls

Button {
    id:item
    required property var menu
    implicitWidth:parent?parent.width:280;implicitHeight:34
    font.family:menu.host.family;font.pixelSize:12
    background:Rectangle{radius:Geometry.radius(Geometry.controlRadius,width,height);color:item.down?"#28FFFFFF":item.hovered?"#18FFFFFF":item.menu.dark?"#0CFFFFFF":"#08000000"}
    contentItem:Text{text:item.text;color:item.menu.foreground;font:item.font;elide:Text.ElideRight;verticalAlignment:Text.AlignVCenter;leftPadding:10;rightPadding:10}
    HoverHandler{cursorShape:Qt.PointingHandCursor}
}
