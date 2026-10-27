pragma ComponentBehavior: Bound
import "Common" as Corners
import QtQuick

Corners.ContinuousRectangle {
    id: menu
    property var entries: []
    property bool dark: true
    property string fontFamily: "SF Pro Text"
    signal chosen(string action)
    width: 228
    height: rows.height + 2 * Corners.CornerTheme.menuInset
    radius: Corners.CornerTheme.menuRadius
    color: dark ? "#F02B2C32" : "#F0F4F4F6"
    border.width: 1
    border.color: dark ? "#50FFFFFF" : "#40000000"
    visible: false
    z: 100
    // Stop a menu press from reaching the desktop selection rectangle.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    Column {
        id: rows
        x: Corners.CornerTheme.menuInset; y: x; width: parent.width - 2 * x
        Repeater {
            model: menu.entries
            delegate: Item {
                id: row
                required property var modelData
                width: rows.width
                height: modelData.separator ? 9 : 29
                readonly property bool allowed: modelData.enabled !== false
                Corners.MenuHighlight {
                    anchors.fill: parent
                    panelRadius: menu.effectiveRadius
                    color: hit.containsMouse && row.allowed && !row.modelData.separator ? "#287AE5" : "transparent"
                }
                Corners.ContinuousRectangle {
                    visible: row.modelData.separator === true
                    x: 7; y: 4; width: parent.width - 14; height: 1
                    color: menu.dark ? "#30FFFFFF" : "#25000000"
                }
                Text {
                    x: 9; anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.label || ""
                    font.family: menu.fontFamily
                    font.pixelSize: 13
                    color: hit.containsMouse && row.allowed ? "white" : (menu.dark ? "#F2F2F5" : "#242428")
                    opacity: row.allowed ? 1 : 0.4
                }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    enabled: row.allowed && !row.modelData.separator
                    hoverEnabled: true
                    onClicked: menu.chosen(row.modelData.action)
                }
            }
        }
    }
}
