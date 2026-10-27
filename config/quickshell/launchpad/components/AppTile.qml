import "../Common" as Corners
import QtQuick
import QtQuick.Shapes
import ".."

// ─────────────────────────────────────────────────────────────────────────────
//  AppTile — one app icon + label + hover/edit/drag behaviour.
//  The shadow is a single shared texture painted behind the icon.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    objectName: "app-tile-" + (item ? item.id : "")

    property var item: null
    property int pageIndex: 0
    property int itemIndex: 0
    property bool editMode: false
    property bool interactive: true
    property real dropPopScale: 1
    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.iconSize / 2
        xScale: root.dropPopScale
        yScale: root.dropPopScale
    }
    function showDropPop() {
        if (interactive && item && LaunchpadState.justDroppedId === item.id && Theme.animationsEnabled
                && (!LaunchpadState.folderOpen || !Theme.closeAfterRemove))
            dropPop.restart();
    }
    SequentialAnimation {
        id: dropPop
        PropertyAction { target: root; property: "dropPopScale"; value: 0.85 }
        NumberAnimation { target: root; property: "dropPopScale"; to: 1; duration: Theme.animDropPop; easing.type: Easing.OutBack }
    }
    onItemChanged: Qt.callLater(showDropPop)
    Connections {
        target: LaunchpadState
        function onJustDroppedIdChanged() { root.showDropPop(); }
        function onFolderOpenChanged() { root.showDropPop(); }
    }

    // geometry knobs — the large folder panel renders this same tile kind with
    // bigger icons (Theme.folderIconSize) without touching the main grid
    property real iconSize: Theme.iconSize
    property real labelFont: Theme.labelFontSize
    property real labelGap: Theme.labelOffset
    property real labelWidth: Theme.pitch - iconSize * 0.1

    signal contextRequested(var item, int page, int index, real x, real y)
    signal dragDropped(var item, int page, int index, real x, real y)

    readonly property bool isMock: item && item.kind === "mock"
    readonly property bool isFolder: item && item.kind === "folder"
    readonly property bool dragSource: LaunchpadState.drag !== null && LaunchpadState.drag.item === item
    readonly property bool dragTarget: LaunchpadState.drag !== null && LaunchpadState.drag.overIndex === itemIndex
                                     && LaunchpadState.drag.overPage === pageIndex

    width: root.iconSize
    height: root.iconSize + root.labelGap + label.implicitHeight + 4
    opacity: dragSource ? 0.38 : 1.0

    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

    property bool pressed: false
    property bool dragging: false
    property bool justDragged: false
    property real pressX: 0
    property real pressY: 0
    property real wobble: 0

    rotation: editMode && Theme.animationsEnabled ? wobble : 0
    transformOrigin: Item.Center
    scale: dragTarget && LaunchpadState.drag && LaunchpadState.drag.folderReady ? 1.15 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    z: dragging ? 50 : 1

    SequentialAnimation on wobble {
        running: root.editMode && Theme.animationsEnabled
        loops: Animation.Infinite
        PauseAnimation { duration: 20 + Math.random() * 100 }
        NumberAnimation { from: -1.2; to: 1.2; duration: 120; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.2; to: -1.2; duration: 120; easing.type: Easing.InOutSine }
    }

    onEditModeChanged: if (!editMode) wobble = 0

    IconView {
        id: icon

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.iconSize
        height: root.iconSize
        iconName: root.item ? (root.item.icon || "") : ""
        fallbackText: root.item ? root.item.name : ""
        fallbackColor: root.isMock && root.item ? root.item.color : "transparent"
        cornerRadius: root.iconSize * Theme.iconRadiusRatio
    }

    // ── label ─────────────────────────────────────────────────────────────────
    Text {
        id: labelShadow
        x: label.x + 1
        y: label.y + 1
        width: label.width
        text: label.text
        visible: false
    }

    Text {
        id: label
        anchors.top: icon.bottom
        anchors.topMargin: root.labelGap - implicitHeight / 2
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.labelWidth
        text: root.item ? root.item.name : ""
        color: Theme.labelColor
        font.family: Theme.fontFamily
        font.pixelSize: root.labelFont
        font.weight: Font.Normal
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
        maximumLineCount: 1
        style: Text.Raised
        styleColor: Theme.labelShadow
    }

    // hidden duplicate kept for readers that want a real offset shadow
    Text {
        visible: false
        text: ""
    }

    // ── edit badge ────────────────────────────────────────────────────────────
    Item {
        visible: root.editMode && !root.isFolder
        width: Theme.iconSize * 0.30
        height: width
        x: -width * 0.28
        y: -height * 0.28
        z: 20

        Squircle {
            anchors.fill: parent
            radius: width / 2
            exponent: 2
            segmentsPerCorner: 20
            fillColor: Theme.editBadgeFill
            strokeColor: Theme.editBadgeRim
            strokeWidth: 1
        }

        Corners.ContinuousRectangle { cornerSmoothing: 0;
            anchors.centerIn: parent
            width: parent.width * 0.46
            height: Math.max(1.5, parent.height * 0.075)
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.92)
            rotation: 45
        }
        Corners.ContinuousRectangle { cornerSmoothing: 0;
            anchors.centerIn: parent
            width: parent.width * 0.46
            height: Math.max(1.5, parent.height * 0.075)
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.92)
            rotation: -45
        }

        MouseArea {
            enabled: root.interactive
            anchors.fill: parent
            anchors.margins: -2
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.item && root.item.kind === "app")
                    LaunchpadState.hideApp(root.item.id);
            }
        }
    }

    // ── interaction ───────────────────────────────────────────────────────────
    Timer {
        id: pressTimer
        interval: Theme.longPressDelay
        repeat: false
        onTriggered: {
            if (!root.editMode)
                LaunchpadState.editMode = true;
        }
    }

    MouseArea {
        id: mouse
        enabled: root.interactive
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor

        onEntered: {
            if (!LaunchpadState.drag) {
                LaunchpadState.selectionVisible = true;
                LaunchpadState.hoverIndex = root.itemIndex;
                LaunchpadState.page = root.pageIndex;
            }
        }
        onExited: {
            if (!LaunchpadState.drag && LaunchpadState.hoverIndex === root.itemIndex)
                LaunchpadState.hoverIndex = -1;
        }

        onPressed: function (ev) {
            if (ev.button === Qt.LeftButton) {
                root.pressed = true;
                root.dragging = false;
                root.justDragged = false;
                const p = root.mapToItem(null, ev.x, ev.y);
                root.pressX = p.x;
                root.pressY = p.y;
                pressTimer.restart();
            }
        }

        onPositionChanged: function (ev) {
            if (!root.pressed)
                return;
            const p = root.mapToItem(null, ev.x, ev.y);
            const dx = p.x - root.pressX;
            const dy = p.y - root.pressY;
            if (!root.dragging && Math.sqrt(dx * dx + dy * dy) > 8) {
                root.dragging = true;
                pressTimer.stop();
                LaunchpadState.beginDrag(root.item, root.pageIndex, root.itemIndex);
            }
            if (root.dragging) {
                LaunchpadState.updateDrag(p.x, p.y);
                LaunchpadState.updateDropTarget(p.x, p.y);
            }
        }

        onReleased: function (ev) {
            root.pressed = false;
            pressTimer.stop();
            if (root.dragging) {
                const p = root.mapToItem(null, ev.x, ev.y);
                root.justDragged = true;
                root.dragging = false;
                LaunchpadState.finishDrag(p.x, p.y);
            }
        }

        onCanceled: {
            root.pressed = false;
            pressTimer.stop();
            if (root.dragging) {
                root.dragging = false;
                LaunchpadState.cancelDrag();
            }
        }

        onClicked: function (ev) {
            if (root.justDragged) {
                root.justDragged = false;
                return;
            }
            if (ev.button === Qt.RightButton) {
                const p = root.mapToItem(null, ev.x, ev.y);
                root.contextRequested(root.item, root.pageIndex, root.itemIndex, p.x, p.y);
                return;
            }
            if (ev.button === Qt.MiddleButton) {
                if (root.item && root.item.kind !== "folder")
                    LaunchpadState.launch(root.item, false);
                return;
            }
            if (root.editMode)
                return;
            if (root.item && root.item.kind === "folder") {
                const p = root.mapToItem(null, 0, 0);
                LaunchpadState.openFolder(root.item, Qt.rect(p.x - (Theme.plateSize - width) / 2,
                                                  p.y - (Theme.plateSize - height) / 2,
                                                  Theme.plateSize, Theme.plateSize));
            } else {
                LaunchpadState.selected = root.itemIndex;
                LaunchpadState.launch(root.item, true);
            }
        }
    }

    Component.onCompleted: {
        if (!root.item)
            return;
        if (LaunchpadState.drag && LaunchpadState.drag.item === root.item)
            return;
    }
}
