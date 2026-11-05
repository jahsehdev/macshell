pragma ComponentBehavior: Bound
import "Common" as Corners
import QtQuick
import QtQuick.Controls

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
    // Built-in Image delegates avoid custom type discovery during live reload.
    readonly property var actionIconPaths: ({
        open: "M14 3h7v7M21 3 11 13M10 5H5Q3 5 3 7v12q0 2 2 2h12q2 0 2-2v-5",
        folder: "M3 6q0-2 2-2h5l3 3h7q2 0 2 2v10q0 2-2 2H4q-2 0-2-2V6Z",
        rename: "M4 16 16 4q2-2 4 0t0 4L8 20l-5 1ZM14 6l4 4M4 16l4 4",
        trash: "M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7",
        customize: "M3 3h9l9 9q1 1 0 2l-7 7q-1 1-2 0l-9-9ZM9 7a2 2 0 1 1-4 0 2 2 0 1 1 4 0",
        mkdir: "M3 6q0-2 2-2h5l3 3h7q2 0 2 2v10q0 2-2 2H4q-2 0-2-2V6ZM12 10v8m-4-4h8",
        widgets: "M3 3h7v7H3ZM14 3h7v7h-7ZM3 14h7v7H3ZM14 14h7v7h-7Z",
        cleanup: "M3 4h3v3H3ZM10 5h11M3 11h3v3H3ZM10 12h11M3 18h3v3H3ZM10 19h11",
        wallpaper: "M3 3h18v18H3ZM3 17l6-7 5 6 3-3 4 4M17 7h.01",
        small: "M7 7h10v10H7Z",
        medium: "M3 7h18v10H3Z",
        large: "M3 3h18v18H3Z",
        xl: "M2 2h20v20H2ZM6 6h12v12H6Z",
        removeWidget: "M22 12a10 10 0 1 1-20 0 10 10 0 1 1 20 0M7 12h10"
    })
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
                height: modelData.separator ? 9 : modelData.palette ? 32 : 29
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
                Image {
                    id: actionIcon
                    readonly property string action: row.modelData.action || ""
                    readonly property color color: hit.containsMouse && row.allowed ? "white" : (menu.dark ? "#b8b8c0" : "#77777c")
                    objectName: "desktopMenuIcon-" + action
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    width: 14; height: 14
                    visible: action !== ""
                    opacity: row.allowed ? 1 : 0.4
                    sourceSize: Qt.size(42, 42)
                    source: action && menu.actionIconPaths[action] ? "data:image/svg+xml;charset=utf-8," + encodeURIComponent(
                        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="' + color
                        + '" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="'
                        + menu.actionIconPaths[action] + '"/></svg>') : ""
                }
                Text {
                    x: 31; anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.label || ""
                    font.family: menu.fontFamily
                    font.pixelSize: 13
                    color: hit.containsMouse && row.allowed ? "white" : (menu.dark ? "#F2F2F5" : "#242428")
                    opacity: row.allowed ? 1 : 0.4
                }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    enabled: row.allowed && !row.modelData.separator && !row.modelData.palette
                    hoverEnabled: true
                    onClicked: menu.chosen(row.modelData.action)
                }
                Row {
                    visible: row.modelData.palette === true
                    anchors.centerIn: parent
                    spacing: 9
                    Repeater {
                        model: row.modelData.palette ? ["#ff453a", "#ff9f0a", "#ffd43b", "#30c85a", "#0a84ff", "#bf5af2", "#929296"] : []
                        delegate: Button {
                            id: swatch
                            required property string modelData
                            width: 17; height: 24
                            Accessible.name: "Folder color " + modelData
                            background: Rectangle {
                                anchors.centerIn: parent; width: 15; height: 15; radius: 8
                                color: swatch.modelData
                                border.width: swatch.hovered || swatch.activeFocus ? 2 : 1
                                border.color: swatch.hovered || swatch.activeFocus ? "white" : "#20000000"
                            }
                            onClicked: menu.chosen("folderColor:" + modelData)
                        }
                    }
                }
            }
        }
    }
}
