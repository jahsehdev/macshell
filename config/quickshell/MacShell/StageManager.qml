import "Common" as Common
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
Scope {
    id: root
    property var hub: null
    readonly property var controller: hub ? hub.desktopController : null
    Variants {
        model: Common.DesktopPreferences.settings.stageManager ? Quickshell.screens : []
        PanelWindow {
            id: windowPanel
            required property var modelData
            screen: modelData
            anchors { left: Common.DesktopPreferences.settings.position !== "left"; right: Common.DesktopPreferences.settings.position === "left"; top: true; bottom: true }
            implicitWidth: 178
            visible: !(root.hub && root.hub.dock.launchpadHidesDock) && !(root.hub && root.hub.glassClients.some(function(c) {
                var mon = root.hub.monData.filter(function(m) { return m.name === windowPanel.modelData.name; })[0];
                return mon && c.monitor === mon.id && c.workspace.id === mon.activeWorkspace.id && c.fullscreen === 2;
            }))
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "macshell-stages"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            readonly property var groups: root.controller ? root.controller.stages.filter(function(g) { return g.monitor === windowPanel.modelData.name && !g.active; }) : []
            readonly property var currentGroup: root.controller ? root.controller.stages.filter(function(g) { return g.monitor === windowPanel.modelData.name && g.active; }) : []
            property bool menuOpen: false
            mask: Region { item: stageContent.hitItem }
            StageManagerContent {
                id: stageContent
                anchors.fill: parent
                panel: windowPanel
                hub: root.hub
            }
        }
    }
}
