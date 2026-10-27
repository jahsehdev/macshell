pragma ComponentBehavior: Bound
import QtQuick
import QtCore

// MacTahoe window controls, using the same artwork and spacing as Nautilus.
Item {
    id: controls
    property bool dark: true
    property bool windowActive: true
    property bool restored: false
    property bool minimizeEnabled: true
    property bool zoomEnabled: true
    property bool closeOnly: false
    // Shared assets are outside Quickshell's virtual config tree: use a real file URL.
    readonly property string assetsPath: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/macshell/window-controls/"
    signal closeClicked()
    signal minimizeClicked()
    signal zoomClicked()
    implicitWidth: closeOnly ? 18 : 66
    implicitHeight: 24

    Row {
        anchors.fill: parent
        spacing: 6
        Repeater {
            model: controls.closeOnly ? ["close"] : ["close", "minimize", "maximize"]
            delegate: Item {
                id: button
                required property string modelData
                width: 18
                height: controls.height
                readonly property string kind: modelData === "maximize" && controls.restored ? "restore" : modelData
                readonly property bool available: modelData === "minimize" ? controls.minimizeEnabled
                    : modelData === "maximize" ? controls.zoomEnabled : true
                readonly property string stateSuffix: !available ? "-backdrop" : mouse.pressed ? "-active"
                    : !controls.windowActive ? (mouse.containsMouse ? "-backdrop-hover" : "-backdrop")
                    : mouse.containsMouse ? "-hover" : ""

                Image {
                    anchors.centerIn: parent
                    width: 16; height: 16
                    source: controls.assetsPath + (controls.dark ? "dark/" : "light/")
                        + "titlebutton-" + button.kind + button.stateSuffix
                        + (controls.dark ? "-dark" : "") + "@2.png"
                    sourceSize: Qt.size(32, 32)
                    smooth: true
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: button.available
                    onClicked: {
                        if (button.modelData === "close") controls.closeClicked();
                        else if (button.modelData === "minimize") controls.minimizeClicked();
                        else controls.zoomClicked();
                    }
                }
            }
        }
    }
}
