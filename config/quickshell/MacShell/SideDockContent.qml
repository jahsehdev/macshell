import "Common" as Common
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
Item {
    id: root
    required property var panel
    required property var dock
    property var hub: null
    property alias hitItem: hit
            Item {
                id: hit
                x: panel.menuOpen ? 0 : panel.left ? 0 : panel.width - width
                width: panel.menuOpen ? panel.width : panel.tucked ? 3 : panel.slabWidth + root.dock.margin + (pointer.hovered ? panel.base * (root.dock.effMag - 1) + 12 : 0)
                y: panel.menuOpen ? 0 : panel.naturalTop - 20
                height: panel.menuOpen ? panel.height : root.dock.totalW0 * panel.fit + 40
                HoverHandler {
                    id: pointer
                    onHoveredChanged: {
                        if (hovered) { hide.stop(); panel.revealed = true; }
                        else { panel.hoveredKey = ""; hide.restart(); }
                    }
                }
            }
            Timer { id: hide; interval: root.dock.hideDelay; onTriggered: if (!pointer.hovered && !panel.menuOpen) panel.revealed = false }
            Item {
                id: slab
                x: panel.left ? root.dock.margin - (panel.tucked ? width + root.dock.margin + 3 : 0)
                    : panel.width - root.dock.margin - width + (panel.tucked ? width + root.dock.margin + 3 : 0)
                y: (panel.height - height) / 2
                width: panel.slabWidth
                height: column.height + root.dock.hPad * 2
                Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                DockGlassSurface {
                    anchors.fill: parent; dock: root.dock; monitor: panel.modelData; hub: root.hub
                    screenX: panel.left ? slab.x : panel.modelData.width - panel.width + slab.x
                    screenY: slab.y; live: !panel.tucked
                }
                Column {
                    id: column
                    x: root.dock.hPad; y: root.dock.hPad
                    spacing: root.dock.spacing * panel.fit
                    Repeater {
                        model: root.dock.cellModel
                        delegate: Item {
                            id: cell
                            required property string key
                            required property int index
                            readonly property var modelData: root.dock.itemMap[key] || {kind: "sep", key: key}
                            readonly property bool sep: modelData.kind === "sep"
                            readonly property bool useThumb: root.dock.windowCapture && modelData.kind === "win" && modelData.tl !== null
                            readonly property bool liveThumbReady: useThumb && capture.hasContent
                            readonly property bool snapshotReady: useThumb && !liveThumbReady && modelData.minimized === true && saved.status === Image.Ready
                            readonly property string winAddr: modelData.tl ? root.dock.winAddr(modelData.tl) : ""
                            readonly property bool closingWin: winAddr !== "" && root.hub && root.hub.closingWins[winAddr] === true
                            readonly property real c0: ((modelData.nA || 0) * (root.dock.iconSize + root.dock.spacing)
                                + (modelData.nS || 0) * (root.dock.sepWidth + root.dock.spacing) + root.dock.iconSize / 2) * panel.fit
                            readonly property real distance: Math.abs(pointer.point.position.y + hit.y - panel.naturalTop - c0)
                            readonly property real mag: !sep && pointer.hovered && root.dock.magnificationEnabled
                                ? 1 + (root.dock.effMag - 1) * Math.max(0, distance < root.dock.magRadius ? (1 + Math.cos(Math.PI * distance / root.dock.magRadius)) / 2 : 0) : 1
                            width: panel.base
                            height: sep ? root.dock.sepWidth * panel.fit : panel.base * mag
                            enabled: !modelData.leaving
                            opacity: modelData.leaving ? 0 : 1
                            Behavior on height { NumberAnimation { duration: 100 } }
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                            Rectangle { visible: cell.sep; width: panel.base * 0.85; height: 1; anchors.centerIn: parent; color: root.dock.dockDark ? "#45FFFFFF" : "#35000000" }
                            Image {
                                id: icon
                                width: panel.base * cell.mag; height: width
                                anchors.verticalCenter: parent.verticalCenter
                                x: panel.left ? 0 : panel.base - width
                                visible: !cell.sep && !cell.liveThumbReady && !cell.snapshotReady
                                source: !cell.sep ? root.dock.cellIconSrc(cell.modelData) : ""
                                sourceSize: Qt.size(128,128); fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
                                layer.enabled: Common.IconStyle.effectMode !== 0
                                layer.effect: Common.IconStyleEffect {}
                                property real lift: 0
                                transform: Translate { x: panel.left ? icon.lift : -icon.lift }
                                SequentialAnimation on lift {
                                    running: root.dock.bounceOnLaunch && root.dock.launching[cell.modelData.key] !== undefined && !panel.tucked
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 13; duration: 250; easing.type: Easing.OutQuad }
                                    NumberAnimation { to: 0; duration: 280; easing.type: Easing.InQuad }
                                    PauseAnimation { duration: 450 }
                                }
                            }
                            Image {
                                id: saved
                                anchors.fill: icon
                                visible: cell.snapshotReady
                                source: cell.modelData.shot ? root.dock.fileUrl(cell.modelData.shot) : ""
                                fillMode: Image.PreserveAspectFit; asynchronous: true; cache: false
                            }
                            ScreencopyView {
                                id: capture
                                anchors.fill: icon
                                visible: cell.useThumb
                                opacity: cell.liveThumbReady ? 1 : 0.01
                                captureSource: cell.useThumb ? cell.modelData.tl : null
                                live: cell.useThumb && pointer.hovered && !panel.tucked && !root.dock.previewHold && !cell.closingWin
                                Timer {
                                    interval: 2000; repeat: true; triggeredOnStart: true
                                    running: !capture.live && !panel.tucked && !root.dock.previewHold && !cell.closingWin && capture.captureSource !== null
                                    onTriggered: if (typeof capture.captureFrame === "function") capture.captureFrame()
                                }
                            }
                            Rectangle {
                                visible: root.dock.showIndicators && cell.modelData.running === true && !cell.sep
                                width: 3; height: 3; radius: 1.5
                                anchors.verticalCenter: parent.verticalCenter
                                x: panel.left ? -7 : parent.width + 4
                                color: root.dock.dockDark ? "#D0FFFFFF" : "#B0000000"
                            }
                            MouseArea {
                                anchors.fill: icon; visible: !cell.sep
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                hoverEnabled: true
                                property real pressY: 0
                                onEntered: panel.hoveredKey = cell.modelData.key
                                onExited: if (!panel.menuOpen) panel.hoveredKey = ""
                                onPressed: mouse => {
                                    pressY = mouse.y;
                                    if (mouse.button === Qt.RightButton) {
                                        panel.menuEntries = root.dock.menuFor(cell.modelData);
                                        appMenu.x = panel.left ? panel.slabWidth + root.dock.margin + 5 : Math.max(0, panel.width - panel.slabWidth - appMenu.width - root.dock.margin - 5);
                                        appMenu.y = Math.max(6, Math.min(panel.height - appMenu.implicitHeight - 6, slab.y + column.y + cell.y));
                                        appMenu.open();
                                    } else if (cell.modelData.pinned && !cell.modelData.special) {
                                        panel.dragKey = cell.modelData.key; panel.dragIndex = cell.index;
                                    }
                                }
                                onReleased: mouse => {
                                    var delta = mouse.y - pressY;
                                    if (panel.dragKey && Math.abs(delta) > 10) {
                                        var target = panel.dragIndex + Math.round(delta / (panel.base + root.dock.spacing));
                                        root.dock.reorderPinned(panel.dragIndex, target);
                                    } else if (mouse.button === Qt.LeftButton) root.dock.activate(cell.modelData, false);
                                    panel.dragKey = "";
                                }
                                onCanceled: panel.dragKey = ""
                            }
                        }
                    }
                }
            }
            Menu {
                id: appMenu
                width: 235
                onOpened: panel.menuOpen = true
                onClosed: { panel.menuOpen = false; hide.restart(); }
                Repeater {
                    model: panel.menuEntries
                    MenuItem {
                        required property var modelData
                        text: modelData.kind === "sep" ? "──────────" : modelData.label
                        enabled: modelData.kind !== "sep" && !modelData.disabled
                        onTriggered: {
                            if (modelData.confirm) { confirmation.action = modelData.run; confirmation.open(); }
                            else if (typeof modelData.run === "function") modelData.run();
                        }
                    }
                }
            }
            Menu {
                id: confirmation
                property var action: null
                x: appMenu.x; y: appMenu.y
                onOpened: panel.menuOpen = true
                onClosed: panel.menuOpen = false
                MenuItem { text: "Empty Trash"; onTriggered: if (confirmation.action) confirmation.action() }
                MenuItem { text: "Cancel" }
            }
            Rectangle {
                visible: root.dock.showLabels && !!panel.hoveredKey && !panel.menuOpen && !panel.tucked
                x: panel.left ? root.dock.margin + panel.slabWidth + panel.base * (root.dock.effMag - 1) + 9 : 4
                y: Math.max(5, Math.min(panel.height - height - 5, pointer.point.position.y + hit.y - height / 2))
                width: Math.min(220, label.implicitWidth + 24); height: 32; radius: 16
                color: root.dock.dockDark ? "#E0303238" : "#EAF3F4F7"
                Text { id: label; anchors.centerIn: parent; width: Math.min(196, implicitWidth); text: root.dock.itemMap[panel.hoveredKey] ? root.dock.itemMap[panel.hoveredKey].name : ""; elide: Text.ElideRight; color: root.dock.dockDark ? "white" : "#202126"; font.family: root.dock.fontFamily; font.pixelSize: 12 }
            }
}
