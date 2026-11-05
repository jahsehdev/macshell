pragma ComponentBehavior: Bound
import QtQuick
import "NotchToolStyle.js" as Style

NotchAction {
    iconSize:Style.iconSize
    iconStrokeWidth:Style.iconStroke
    implicitHeight:32
    font.pixelSize:Style.buttonSize
}
