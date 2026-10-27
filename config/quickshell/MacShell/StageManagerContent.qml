import "Common" as Common
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
Item {
    id: root
    required property var panel
    property var hub: null
    readonly property var controller: hub ? hub.desktopController : null
    function appEntry(id) {
        try { return DesktopEntries.heuristicLookup(id); } catch (e) { return null; }
    }
    property alias hitItem: railHit
            Item {
                id: railHit
                anchors.verticalCenter: rail.verticalCenter
                x: Common.DesktopPreferences.settings.position === "left" ? panel.width - width : 0
                width: rail.opacity > 0.1 ? panel.width : 3
                height: Math.max(60,rail.height)
                HoverHandler { id: edgeReveal }
            }
            Item {
                id: rail
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Math.min(parent.height - 90, stack.implicitHeight + 12)
                opacity: Common.DesktopPreferences.settings.stageRecent || edge.hovered || edgeReveal.hovered || panel.menuOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
                HoverHandler { id: edge }
                Flickable {
                    anchors.fill: parent
                    contentHeight: stack.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: stack
                        width: parent.width
                        spacing: 12
                        Repeater {
                            model: panel.groups
                            delegate: Item {
                                id: card
                                required property var modelData
                                property string dragAddress: modelData.windows.length ? modelData.windows[0].addr : ""
                                width: stack.width
                                height: 112
                                                                Item {
                                    id: dragProxy
                                    width: card.width; height: card.height
                                    Drag.active: mover.active
                                    Drag.source: card
                                    Drag.keys: ["macshell-stage"]
                                    Drag.hotSpot.x: width / 2
                                    Drag.hotSpot.y: height / 2
                                Rectangle {
                                    x: 14; y: 6
                                    width: 142; height: 83; radius: 12
                                    color: root.hub && root.hub.dock.dockDark ? "#D034353C" : "#D0EBECF1"
                                    border.width: 1; border.color: "#30FFFFFF"
                                    transform: Rotation { origin.x: 71; origin.y: 42; angle: -4 }
                                    visible: card.modelData.windows.length > 1
                                }
                                Common.ContinuousRectangle {
                                    x: 10; y: 0
                                    width: 142; height: 87; radius: 12
                                    color: root.hub && root.hub.dock.dockDark ? "#D02B2D34" : "#D0F0F1F5"
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        source: card.modelData.windows.length && card.modelData.windows[0].shot ? "file://" + card.modelData.windows[0].shot : ""
                                        asynchronous: true; fillMode: Image.PreserveAspectFit
                                    }
                                    Column {
                                        anchors.centerIn: parent
                                        visible: !card.modelData.windows.length || !card.modelData.windows[0].shot
                                        Image {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 40; height: 40
                                            readonly property var entry: root.appEntry(card.modelData.windows.length ? card.modelData.windows[0].app : "")
                                            source: entry ? Quickshell.iconPath(entry.icon) : ""
                                            fillMode: Image.PreserveAspectFit
                                            layer.enabled: Common.IconStyle.effectMode !== 0
                                            layer.effect: Common.IconStyleEffect {}
                                        }
                                        Text { width: 126; text: card.modelData.title; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter; color: Common.IconStyle.dark ? "white" : "#343640"; font.pixelSize: 11 }
                                    }
                                    Rectangle { anchors.fill: parent; radius: 12; color: target.containsDrag ? "#403B90FF" : "transparent" }
                                }
                                Text {
                                    x: 10; y: 91; width: 146
                                    text: card.modelData.title + (card.modelData.windows.length > 1 ? " · " + card.modelData.windows.length : "")
                                    color: "white"; style: Text.Outline; styleColor: "#80000000"
                                    font.pixelSize: 11; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                                }
                                }
                                TapHandler { acceptedButtons: Qt.LeftButton; onTapped: if (card.dragAddress) root.controller.activate(card.dragAddress) }
                                TapHandler { acceptedButtons: Qt.RightButton; onTapped: stageMenu.popup() }
                                DragHandler {
                                    id: mover; target: dragProxy
                                    xAxis.enabled: true; yAxis.enabled: true
                                    onActiveChanged: if (!active) { dragProxy.Drag.drop(); dragProxy.x = 0; dragProxy.y = 0; }
                                }
                                DropArea {
                                    id: target
                                    anchors.fill: parent
                                    keys: ["macshell-stage"]
                                    onDropped: drop => {
                                        if (drop.source && drop.source !== card) {
                                            var members = drop.source.modelData.windows;
                                            for (var i = 0; i < members.length; i++) root.controller.send({action: "join", addr: members[i].addr, group: card.modelData.id});
                                            drop.acceptProposedAction();
                                        }
                                    }
                                }
                                Menu {
                                    id: stageMenu
                                    onOpened: panel.menuOpen = true
                                    onClosed: panel.menuOpen = false
                                    MenuItem { text: "Open Stage"; onTriggered: root.controller.activate(card.dragAddress) }
                                    MenuItem { text: "Add to Current Group"; enabled: panel.currentGroup.length > 0; onTriggered: { for (var i = 0; i < card.modelData.windows.length; i++) root.controller.send({action: "join", addr: card.modelData.windows[i].addr}); } }
                                    MenuSeparator {}
                                    Repeater {
                                        model: card.modelData.windows
                                        MenuItem {
                                            required property var modelData
                                            text: "Open: " + modelData.title
                                            onTriggered: root.controller.activate(modelData.addr)
                                        }
                                    }
                                }
                            }
                        }
                        DropArea {
                            width: stack.width - 20; height: panel.groups.length ? 38 : 0
                            keys: ["macshell-stage"]
                            Rectangle {
                                anchors.fill: parent; radius: 10
                                color: parent.containsDrag ? "#9063A8EF" : "#404A4A50"
                                Text { anchors.centerIn: parent; text: "Add to Current Group"; color: "white"; font.pixelSize: 11 }
                            }
                            onDropped: drop => { if (drop.source) { root.controller.send({action: "join", addr: drop.source.dragAddress}); drop.acceptProposedAction(); } }
                        }
                    }
                }
            }
}
