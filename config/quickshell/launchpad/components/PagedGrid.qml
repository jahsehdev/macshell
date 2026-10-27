import "../Common" as Corners
import QtQuick
import ".."

// ─────────────────────────────────────────────────────────────────────────────
//  PagedGrid — the current page of tiles with a hover plate per icon.
//  Only the current page is instantiated (40 tiles max at 8 x 5), which is
//  what keeps a 600-app Launchpad cheap.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    property Item backdrop: null
    property point backdropPosition: Qt.point(x, y)

    // Share one backdrop texture between every folder on the current page.
    SearchGlassContext {
        id: folderGlass
        anchors.fill: parent
        backdrop: root.backdrop
        screenPosition: root.backdropPosition
        blurAmount: Theme.folderBackgroundBlur * 0.16
        active: root.backdrop !== null && LaunchpadState.windowVisible
                && GraphicsInfo.api !== GraphicsInfo.Software
                && LaunchpadState.viewItems.some(it => it.kind === "folder")
    }

    signal contextRequested(var item, int page, int index, real x, real y)

    width: Theme.gridWidth
    height: Theme.gridHeight

    // Window-space rect of the grid. Both corners are mapped so the scale of
    // the content layer (1.06 while hidden, 1.0 shown, 0.96 with a folder open)
    // is included.
    function updateGridRect() {
        const a = mapToItem(null, 0, 0);
        const b = mapToItem(null, width, height);
        LaunchpadState.gridRect = Qt.rect(a.x, a.y, b.x - a.x, b.y - a.y);
        if (Theme.debugDrag) console.info("launchpad: gridRect", LaunchpadState.gridRect);
    }

    // Slot (0..N) under a window-space point = insert position for a drop.
    // Returns -1 while searching (results are not a layout).
    function slotAt(sx, sy) {
        if (LaunchpadState.searching)
            return -1;
        const p = root.mapFromItem(null, sx, sy);
        const cols = Math.max(1, Theme.columns);
        const rows = Math.max(1, Theme.rows);
        const half = (Theme.pitch - Theme.iconSize) / 2;
        const col = Math.max(0, Math.min(cols - 1, Math.floor((p.x + half) / Theme.pitch)));
        const row = Math.max(0, Math.min(rows - 1, Math.floor((p.y + half) / Theme.pitch)));
        const n = LaunchpadState.viewItems ? LaunchpadState.viewItems.length : 0;
        return Math.min(n, row * cols + col);
    }

    // Window-space rect (icon + a little padding) of slot `index`.
    function slotRect(index) {
        const cols = Math.max(1, Theme.columns);
        const col = index % cols;
        const row = Math.floor(index / cols);
        const pad = Math.max(0, (Theme.plateSize - Theme.iconSize) / 2);
        const a = root.mapToItem(null, col * Theme.pitch - pad, row * Theme.pitch - pad);
        const b = root.mapToItem(null, col * Theme.pitch + Theme.iconSize + pad, row * Theme.pitch + Theme.iconSize + pad);
        return Qt.rect(a.x, a.y, b.x - a.x, b.y - a.y);
    }

    // The Launchpad content is scaled while it fades in/out and while a folder
    // is open, so the rect must be refreshed after those animations too, not
    // only when x / y / width / height change.
    Timer {
        id: rectTimer
        interval: Math.max(Theme.animOpen, Theme.animClose, Theme.animFolder) + 80
        repeat: false
        onTriggered: root.updateGridRect()
    }

    Connections {
        target: LaunchpadState
        function onShownChanged() { root.updateGridRect(); rectTimer.restart(); }
        function onFolderOpenChanged() { root.updateGridRect(); rectTimer.restart(); }
        function onViewItemsChanged() { root.updateGridRect(); rectTimer.restart(); }
    }

    Component.onCompleted: updateGridRect()
    onWidthChanged: updateGridRect()
    onHeightChanged: updateGridRect()
    onXChanged: updateGridRect()
    onYChanged: updateGridRect()

    // Debug only; uses the same mapping as hit-testing under ancestor scales.
    Repeater {
        model: Theme.debugDrag ? Math.min(Theme.pageSize, LaunchpadState.viewItems.length + 1) : 0
        Corners.ContinuousRectangle {
            required property int index
            x: (index % Theme.columns) * Theme.pitch - (Theme.plateSize - Theme.iconSize) / 2
            y: Math.floor(index / Theme.columns) * Theme.pitch - (Theme.plateSize - Theme.iconSize) / 2
            width: Theme.plateSize; height: Theme.plateSize
            color: "transparent"; border.color: "#ffcc00"; border.width: 1
            z: 100
        }
    }

    Item {
        id: pageItem

        width: root.width
        height: root.height

        Repeater {
            model: LaunchpadState.viewItems

            Loader {
                id: tileLoader

                required property var modelData
                required property int index

                readonly property int col: index % Theme.columns
                readonly property int row: Math.floor(index / Theme.columns)

                x: col * Theme.pitch
                y: row * Theme.pitch
                width: Theme.iconSize
                height: Theme.iconSize + Theme.labelOffset + Theme.labelFontSize * 1.4 + 4
                z: 2

                // Each tile owns its highlight; it never travels between icons.
                SelectionPlate {
                    z: -1
                    x: (Theme.iconSize - width) / 2
                    y: (Theme.iconSize - height) / 2
                    shown: LaunchpadState.hoverIndex === tileLoader.index
                           && !LaunchpadState.editMode && !LaunchpadState.folderOpen
                           && !LaunchpadState.drag
                }

                sourceComponent: modelData && modelData.kind === "folder" ? folderComponent : appComponent

                onLoaded: {
                    item.item = Qt.binding(function () { return tileLoader.modelData; });
                    item.pageIndex = Qt.binding(function () { return LaunchpadState.page; });
                    item.itemIndex = Qt.binding(function () { return tileLoader.index; });
                    item.editMode = Qt.binding(function () { return LaunchpadState.editMode; });
                    item.contextRequested.connect(function (it, pg, ix, gx, gy) {
                        root.contextRequested(it, pg, ix, gx, gy);
                    });
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: LaunchpadState.viewItems.length === 0 && LaunchpadState.searching
        text: "No results"
        color: Theme.emptyText
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(14, Theme.iconSize * 0.22)
        font.weight: Font.Medium
    }

    Component {
        id: appComponent

        AppTile {
            width: Theme.iconSize
            height: Theme.iconSize + Theme.labelOffset + Theme.labelFontSize * 1.4 + 4
        }
    }

    Component {
        id: folderComponent

        FolderTile {
            width: Theme.iconSize
            height: Theme.iconSize + Theme.labelOffset + Theme.labelFontSize * 1.4 + 4
            glassContext: folderGlass
            glassOffset: Qt.point(parent.x + pageItem.x, parent.y)
        }
    }

    // ── page slide-in ─────────────────────────────────────────────────────────
    ParallelAnimation {
        id: pageAnim

        NumberAnimation {
            target: pageItem
            property: "x"
            to: 0
            duration: Theme.animationsEnabled ? Theme.animPage : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: pageItem
            property: "opacity"
            to: 1
            duration: Theme.animationsEnabled ? Theme.animPage * 0.8 : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: pageItem
            property: "scale"
            to: 1
            duration: Theme.animationsEnabled ? Theme.animPage : 0
            easing.type: Easing.OutCubic
        }
    }

    Connections {
        target: LaunchpadState
        function onPageChanged() {
            if (!Theme.animationsEnabled || LaunchpadState.pageDirection === 0) {
                pageAnim.stop();
                pageItem.x = 0;
                pageItem.opacity = 1;
                pageItem.scale = 1;
                return;
            }
            pageItem.x = (LaunchpadState.pageDirection >= 0 ? 1 : -1) * Math.min(140, root.width * 0.18);
            pageItem.opacity = 0.35;
            pageItem.scale = 0.985;
            pageAnim.restart();
        }
    }
}
