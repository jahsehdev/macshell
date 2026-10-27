import "Common" as Common
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
Scope {
    id: root
    required property var dock
    property var hub: null
    Variants {
        model: root.dock.settingsReady && root.dock.dockEnabled && root.dock.position !== "bottom" ? Quickshell.screens : []
        PanelWindow {
            id: windowPanel
            required property var modelData
            screen: modelData
            visible: !root.dock.launchpadHidesDock && (!root.dock.monitor || root.dock.monitor === modelData.name)
            readonly property bool left: root.dock.position === "left"
            anchors { left: windowPanel.left; right: !windowPanel.left; top: true; bottom: true }
            implicitWidth: root.dock.iconSize * root.dock.effMag + root.dock.hPad * 2 + root.dock.margin + 250
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.dock.hideMode === "never" ? root.dock.iconSize + root.dock.hPad * 2 + root.dock.margin : 0
            WlrLayershell.namespace: "macdock"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            property bool revealed: false
            property bool menuOpen: false
            property string hoveredKey: ""
            property string dragKey: ""
            property int dragIndex: -1
            property var menuEntries: []
            readonly property bool wantsHide: root.dock.hideMode === "always" || (root.dock.hideMode === "smart" && root.dock.busyMonitors[modelData.name] === true)
            readonly property bool tucked: wantsHide && !revealed && !menuOpen && !dragKey
            readonly property real fit: Math.min(1, (height - 96) / Math.max(1, root.dock.totalW0 + root.dock.hPad * 2))
            readonly property real base: root.dock.iconSize * fit
            readonly property real slabWidth: base + root.dock.hPad * 2
            readonly property real naturalTop: (height - root.dock.totalW0 * fit) / 2
            mask: Region { item: sideContent.hitItem }
            SideDockContent {
                id: sideContent
                anchors.fill: parent
                panel: windowPanel
                dock: root.dock; hub: root.hub
            }
        }
    }
}
