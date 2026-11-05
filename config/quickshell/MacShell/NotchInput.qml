import QtQuick
import "NotchGeometry.js" as Geometry
import QtQuick.Controls

TextField {
    id: field
    property string family: "SF Pro Text"
    property bool dark: true
    property bool frosted: false
    implicitHeight: 32
    color: dark ? "#FAFAFC" : "#202124"; placeholderTextColor: dark ? "#8D8D95" : "#777780"
    font.family: family; font.pixelSize: 13; selectByMouse: true
    selectionColor: "#2C70B0"; selectedTextColor: "white"
    leftPadding: 10; rightPadding: 10
    background: Rectangle { radius: Geometry.radius(Geometry.controlRadius,width,height); color: field.frosted ? (field.dark ? "#4010141C" : "#90FFFFFF") : "#181C23"; border.width: 1; border.color: field.activeFocus ? "#75BBFF" : field.dark ? "#24FFFFFF" : "#30000000" }
}
