import "../Common" as Corners
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import ".."

// Visual resources are created on open; persistent state remains in LaunchpadState.
Item {
    required property var win
    readonly property bool revealGrid: folderLoader.item !== null && folderLoader.item.dragOutside === true

    // Hidden full-screen copy: search glass samples the finished Launchpad
    // scene rather than a screenshot taken before the backdrop appears.
    Corners.LaunchpadBackground {
        id: searchBackdrop
        width: win.modelData ? win.modelData.width : win.width
        height: win.modelData ? win.modelData.height : win.height
        opacity: 0
        screenName: win.modelData ? win.modelData.name : ""
        imageSource: Theme.backgroundType === "wallpaper" ? "file://" + Theme.tahoeWallpaper
                   : Theme.backgroundType === "custom" ? Theme.customImage
                   : Corners.LaunchpadGlassState.imageFor(screenName)
        backgroundBlur: Theme.backgroundBlur
        dimming: Theme.backgroundOpacity
    }

    FocusScope {
        id: keyboard

        anchors.fill: parent
        focus: LaunchpadState.shown

        Item {
            id: contentLayer

            anchors.fill: parent
            enabled: !LaunchpadState.settingsOpen
            opacity: LaunchpadState.folderOpen ? (win.revealGrid ? Theme.revealGridOpacity : 0.35) : (LaunchpadState.shown && win.focusedHere ? 1 : 0)
            scale: LaunchpadState.folderOpen ? 0.96 : (LaunchpadState.shown && win.focusedHere ? 1 : 1.06)
            transformOrigin: Item.Center

            Behavior on opacity {
                NumberAnimation {
                    duration: LaunchpadState.shown ? (Theme.animationsEnabled ? Theme.animOpen : 0) : (Theme.animationsEnabled ? Theme.animClose : 0)
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: LaunchpadState.shown ? (Theme.animationsEnabled ? Theme.animOpen : 0) : (Theme.animationsEnabled ? Theme.animClose : 0)
                    easing.type: Easing.OutCubic
                }
            }

            // click empty space
            MouseArea {
                anchors.fill: parent
                z: -5
                onClicked: {
                    if (win.optionsOpen) {
                        win.optionsOpen = false;
                    } else if (LaunchpadState.menu) {
                        LaunchpadState.menu = null;
                    } else if (LaunchpadState.folderOpen) {
                        LaunchpadState.closeFolder();
                    } else if (LaunchpadState.editMode) {
                        LaunchpadState.editMode = false;
                    } else {
                        LaunchpadState.close();
                    }
                }
            }

            SearchPill {
                id: searchPill

                x: (contentLayer.width - width) / 2
                y: Theme.searchTop
                captureScreen: win.modelData
                backdrop: searchBackdrop
                screenPosition: Qt.point(x, y + Theme.topInset)
                materialActive: LaunchpadState.windowVisible && win.focusedHere
                onOptionsRequested: {
                    win.optionsOpen = !win.optionsOpen;
                    LaunchpadState.menu = null;
                }
            }

            PagedGrid {
                id: grid

                x: win.gridX
                y: win.gridY
                backdrop: searchBackdrop
                backdropPosition: Qt.point(x, y + Theme.topInset)
                onContextRequested: function (item, page, index, gx, gy) {
                    LaunchpadState.menu = { item: item, page: page, index: index, x: gx, y: gy };
                    win.optionsOpen = false;
                }
            }

            PageDots {
                id: dots

                visible: LaunchpadState.pageCount > 1
                opacity: LaunchpadState.shown ? 1 : 0
                x: (contentLayer.width - implicitWidth) / 2
                y: win.dotsCenterY - implicitHeight / 2
                count: LaunchpadState.pageCount
                current: LaunchpadState.page
                onActivated: function (index) { LaunchpadState.setPage(index); }
            }

            // ── edit mode "Done" pill ──────────────────────────────────────────
            Item {
                id: donePill

                visible: LaunchpadState.editMode
                width: Math.max(70, Theme.iconSize * 1.45)
                height: Math.max(28, Theme.iconSize * 0.52)
                x: contentLayer.width - width - Math.max(16, Theme.iconSize * 0.35)
                y: Theme.topInset + Math.max(14, Theme.iconSize * 0.28)
                opacity: LaunchpadState.editMode ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                Squircle {
                    anchors.fill: parent
                    radius: height / 2
                    exponent: Theme.squircleExponent
                    segmentsPerCorner: 24
                    fillColor: Theme.doneFill
                    strokeColor: Theme.menuRim
                    strokeWidth: 1
                }

                Text {
                    anchors.centerIn: parent
                    text: "Done"
                    color: Theme.doneText
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(11, Math.round(Theme.iconSize * 0.20))
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: LaunchpadState.editMode = false
                }
            }

            // ── drag ghost ────────────────────────────────────────────────────
            Item {
                id: dragGhost

                visible: LaunchpadState.drag !== null
                x: LaunchpadState.drag ? LaunchpadState.drag.x - Theme.iconSize / 2 : 0
                y: LaunchpadState.drag ? LaunchpadState.drag.y - Theme.iconSize / 2 : 0
                width: Theme.iconSize
                height: Theme.iconSize
                scale: 1.10
                opacity: 0.95
                z: 1000

                IconView {
                    anchors.fill: parent
                    iconName: LaunchpadState.drag && LaunchpadState.drag.item ? (LaunchpadState.drag.item.icon || "") : ""
                    fallbackText: LaunchpadState.drag && LaunchpadState.drag.item ? LaunchpadState.drag.item.name : ""
                    fallbackColor: LaunchpadState.drag && LaunchpadState.drag.item && LaunchpadState.drag.item.kind === "mock"
                                   ? LaunchpadState.drag.item.color : "transparent"
                }
            }

            // ── wheel / touchpad paging ───────────────────────────────────────
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: function (event) {
                    if (LaunchpadState.settingsOpen || LaunchpadState.folderOpen || LaunchpadState.drag || LaunchpadState.pageCount <= 1
                            || Date.now() - win.lastPageScroll < Theme.scrollDebounce)
                        return;

                    const ax = event.angleDelta.x;
                    const ay = event.angleDelta.y;
                    const px = event.pixelDelta.x;
                    const py = event.pixelDelta.y;

                    if (Math.abs(ax) > Math.abs(ay) || Math.abs(px) > Math.abs(py)) {
                        win.wheelX += Math.abs(px) > 0 ? px : ax;
                        win.wheelY = 0;
                        if (Math.abs(win.wheelX) > Theme.scrollThreshold) {
                            LaunchpadState.setPage(LaunchpadState.page + (win.wheelX > 0 ? 1 : -1));
                            win.lastPageScroll = Date.now();
                            win.wheelX = 0;
                        }
                    } else {
                        win.wheelY += Math.abs(ay) > 0 ? -ay : -py;
                        win.wheelX = 0;
                        if (Math.abs(win.wheelY) > Theme.scrollThreshold) {
                            LaunchpadState.setPage(LaunchpadState.page + (win.wheelY > 0 ? 1 : -1));
                            win.lastPageScroll = Date.now();
                            win.wheelY = 0;
                        }
                    }
                }
            }

            // reset the accumulation when a gesture ends
            Timer {
                interval: Math.max(200, Theme.scrollDebounce)
                repeat: false
                running: win.wheelX !== 0 || win.wheelY !== 0
                onTriggered: {
                    win.wheelX = 0;
                    win.wheelY = 0;
                }
            }
        }

        // ── folder panel (zooms from the folder tile) ─────────────────────────
        Loader {
            id: folderLoader
            anchors.fill: parent
            active: LaunchpadState.folderOpen && LaunchpadState.foldered !== null
            sourceComponent: folderPanelComponent
            z: 500
        }

        Component {
            id: folderPanelComponent
            FolderPanel {
                captureScreen: win.modelData
                // The panel is created by a Loader, so it cannot discover these itself.
                backdrop: contentLayer
                gridItem: grid
            }
        }

        Corners.ContinuousRectangle {
            visible: Theme.debugDrag
            x: LaunchpadState.gridRect.x; y: LaunchpadState.gridRect.y
            width: LaunchpadState.gridRect.width; height: LaunchpadState.gridRect.height
            color: "transparent"; border.color: "#00ffcc"; border.width: 1
            z: 900
        }

        // ── right-click menu ──────────────────────────────────────────────────
        ContextMenu {
            id: menu
            captureScreen: win.modelData

            shown: LaunchpadState.menu !== null
            z: 700
            actions: {
                if (!LaunchpadState.menu || !LaunchpadState.menu.item)
                    return [];
                if (LaunchpadState.menu.item.kind === "folder")
                    return [{ label: "Open Folder", enabled: true }];
                const actions = [
                    { label: "Open", enabled: true },
                    { label: LaunchpadState.appPinnedInDock(LaunchpadState.menu.item) ? "In Dock" : "Add to Dock",
                      enabled: !LaunchpadState.appPinnedInDock(LaunchpadState.menu.item) },
                    { label: "Hide from Launchpad", enabled: true, danger: true },
                    { label: "Show in File Manager", enabled: true }
                ];
                if (LaunchpadState.menu.source === "folder")
                    actions.push({ label: "Remove from Folder", enabled: !LaunchpadState.folderRemovalBusy });
                return actions;
            }
            x: LaunchpadState.menu ? Math.max(8, Math.min(win.implicitWidth - implicitWidth - 8, LaunchpadState.menu.x)) : 0
            y: LaunchpadState.menu ? Math.max(Theme.topInset + 8,
                                     Math.min(win.implicitHeight - Theme.bottomInset - implicitHeight - 8, LaunchpadState.menu.y)) : 0

            onInvoked: function (index) {
                const m = LaunchpadState.menu;
                if (!m || !m.item)
                    return;
                if (m.item.kind === "folder") {
                    LaunchpadState.openFolder(m.item, LaunchpadState.folderOrigin);
                } else if (index === 0) {
                    LaunchpadState.launch(m.item, true);
                } else if (index === 1) {
                    LaunchpadState.addToDock(m.item);
                } else if (index === 2) {
                    LaunchpadState.hideApp(m.item.id);
                } else if (index === 3) {
                    Quickshell.execDetached(["xdg-open", "/usr/share/applications"]);
                } else if (index === 4 && m.source === "folder" && folderLoader.item) {
                    folderLoader.item.commitRemoval(m.item, -1);
                }
                LaunchpadState.menu = null;
            }
        }

        // ── search-pill options menu ──────────────────────────────────────────
        ContextMenu {
            id: optionsMenu
            captureScreen: win.modelData
            transformOrigin: Item.TopRight

            shown: win.optionsOpen
            z: 710
            actions: [
                { label: LaunchpadState.editMode ? "Exit Edit Mode" : "Edit Mode", enabled: true },
                { label: "Reset Layout", enabled: true, danger: true },
                { label: "Launchpad Settings…", enabled: true, separatorBefore: true }
            ]
            x: Math.max(8, Math.min(win.implicitWidth - implicitWidth - 8,
                                    searchPill.x + searchPill.width - implicitWidth))
            y: searchPill.y + searchPill.height + 8

            onInvoked: function (index) {
                win.optionsOpen = false;
                if (index === 0)
                    LaunchpadState.editMode = !LaunchpadState.editMode;
                else if (index === 1)
                    LaunchpadState.resetLayout();
                else if (index === 2)
                    LaunchpadState.settingsOpen = true;
            }
        }

        Loader {
            anchors.fill: parent
            z: 900
            active: LaunchpadState.settingsOpen
            sourceComponent: Component {
                SettingsPanel {
                    onDismissed: {
                        LaunchpadState.settingsOpen = false;
                        searchPill.focusInput();
                    }
                }
            }
        }

        // ── keyboard ──────────────────────────────────────────────────────────
        Timer {
            id: altTimer
            interval: 600
            repeat: false
            onTriggered: LaunchpadState.editMode = true
        }

        Connections {
            target: LaunchpadState
            function onShownChanged() {
                if (LaunchpadState.shown)
                    Qt.callLater(searchPill.focusInput);
            }
            function onFolderOpenChanged() {
                if (!LaunchpadState.folderOpen && LaunchpadState.shown)
                    Qt.callLater(searchPill.focusInput);
            }
        }

        Keys.onPressed: function (event) {
            if (LaunchpadState.settingsOpen) return;
            if (event.key === Qt.Key_Alt) {
                altTimer.restart();
                return;
            }
            if (event.key === Qt.Key_Escape) {
                if (folderLoader.item && folderLoader.item.cancelDragOnEscape()) {
                    event.accepted = true;
                    return;
                }
                if (win.optionsOpen) {
                    win.optionsOpen = false;
                } else if (LaunchpadState.menu) {
                    LaunchpadState.menu = null;
                } else if (LaunchpadState.folderOpen && folderLoader.item) {
                    folderLoader.item.requestClose();
                } else if (LaunchpadState.query !== "") {
                    LaunchpadState.setQuery("");
                } else if (LaunchpadState.folderOpen) {
                    LaunchpadState.closeFolder();
                } else if (LaunchpadState.editMode) {
                    LaunchpadState.editMode = false;
                } else {
                    LaunchpadState.close();
                }
                event.accepted = true;
                return;
            }
            if (LaunchpadState.folderOpen && folderLoader.item && folderLoader.item.handleKey(event)) {
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                LaunchpadState.launch(LaunchpadState.currentItem, true);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Left) {
                if (event.modifiers & Qt.ControlModifier)
                    LaunchpadState.setPage(LaunchpadState.page - 1);
                else
                    LaunchpadState.moveSelection(-1, 0);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Right) {
                if (event.modifiers & Qt.ControlModifier)
                    LaunchpadState.setPage(LaunchpadState.page + 1);
                else
                    LaunchpadState.moveSelection(1, 0);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Up) {
                LaunchpadState.moveSelection(0, -1);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Down) {
                LaunchpadState.moveSelection(0, 1);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Tab) {
                LaunchpadState.moveSelection((event.modifiers & Qt.ShiftModifier) ? -1 : 1, 0);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Home) {
                LaunchpadState.selected = 0;
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_End) {
                LaunchpadState.selected = Math.max(0, LaunchpadState.viewItems.length - 1);
                event.accepted = true;
                return;
            }
            if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                    && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                LaunchpadState.setQuery(LaunchpadState.query + event.text);
                searchPill.focusInput();
                event.accepted = true;
            }
        }

        Keys.onReleased: function (event) {
            if (event.key === Qt.Key_Alt)
                altTimer.stop();
        }

        Component.onCompleted: {
            if (LaunchpadState.shown)
                Qt.callLater(searchPill.focusInput);
        }
    }

    // close the options menu when clicking outside (the mask still covers the body)
    Connections {
        target: LaunchpadState
        function onShownChanged() {
            if (!LaunchpadState.shown) {
                win.optionsOpen = false;
                win.wheelX = 0;
                win.wheelY = 0;
            }
        }
    }
}
