import QtQuick
import QtQuick.Shapes
import ".."

// ─────────────────────────────────────────────────────────────────────────────
//  FolderTile — a glass squircle with a 3 x 3 mini grid of the first 9 apps.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    objectName: "folder-tile-" + (item ? item.id : "")

    property var item: null
    property int pageIndex: 0
    property int itemIndex: 0
    property bool editMode: false
    property bool pressed: false
    property var glassContext: null
    property point glassOffset: Qt.point(0, 0)
    property bool shaderFailed: false
    readonly property bool glassReady: glassContext !== null && glassContext.ready && !shaderFailed

    signal contextRequested(var item, int page, int index, real x, real y)

    readonly property bool dragSource: LaunchpadState.drag !== null && LaunchpadState.drag.item === item
    readonly property bool dragTarget: LaunchpadState.drag !== null && LaunchpadState.drag.overIndex === itemIndex
                                     && LaunchpadState.drag.overPage === pageIndex && !dragSource

    width: Theme.iconSize
    height: Theme.iconSize + Theme.labelOffset + label.implicitHeight + 4
    opacity: dragSource ? 0.38 : 1.0
    scale: dragTarget ? 1.15 : 1.0
    z: dragTarget ? 10 : 1
    property real wobble: 0

    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

    rotation: editMode && Theme.animationsEnabled ? wobble : 0
    transformOrigin: Item.Center

    SequentialAnimation on wobble {
        running: root.editMode && Theme.animationsEnabled
        loops: Animation.Infinite
        PauseAnimation { duration: 30 + Math.random() * 90 }
        NumberAnimation { from: -1.2; to: 1.2; duration: 120; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.2; to: -1.2; duration: 120; easing.type: Easing.InOutSine }
    }
    onEditModeChanged: if (!editMode) wobble = 0

    Squircle {
        visible: !root.glassReady
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Theme.iconSize
        height: Theme.iconSize
        radius: Theme.iconRadius
        exponent: Theme.squircleExponent
        segmentsPerCorner: Theme.squircleSegments

        fillGradient: LinearGradient {
            x1: 0
            y1: 0
            x2: 0
            y2: Theme.iconSize
            GradientStop { position: 0.0; color: Theme.folderFillTop }
            GradientStop { position: 1.0; color: Theme.folderFillBottom }
        }
    }

    SearchGlassSurface {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Theme.iconSize; height: Theme.iconSize
        context: root.glassReady ? root.glassContext : null
        offset: root.glassOffset
        radius: Theme.iconRadius
        squircle: (Theme.squircleExponent - 2) / 2
        bezel: Math.min(width * 0.12, 10)
        thickness: Theme.folderBackgroundStyle === "liquid" ? 14 * Theme.menuGlassLiquid : 0
        dispersion: Theme.folderBackgroundStyle === "liquid" ? 0.04 * Theme.menuGlassLiquid : 0
        magnify: Theme.folderBackgroundStyle === "liquid" ? 0.025 * Theme.menuGlassLiquid : 0
        blurPx: 1.5 * Theme.folderBackgroundBlur
        grain: Theme.menuGlassGrain
        onFailed: root.shaderFailed = true
    }

    GlassBorder {
        visible: !root.glassReady
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Theme.iconSize; height: Theme.iconSize
        radius: Theme.iconRadius
        bright: Theme.folderGlow
        mid: Theme.folderBorder
        dim: Theme.folderBorder
        sheen: Theme.folderGlow
    }


    Grid {
        id: previewGrid
        readonly property int previewCount: root.item ? Math.min(9, root.item.items.length) : 0
        readonly property real miniSize: previewCount <= 4 ? Theme.iconSize * 0.34 : Theme.folderMiniIcon
        x: (parent.width - width) / 2
        y: (Theme.iconSize - height) / 2
        columns: previewCount <= 4 ? 2 : 3
        spacing: Theme.folderMiniGap

        Repeater {
            model: root.item ? root.item.items.slice(0, 9) : []

            IconView {
                required property var modelData
                width: previewGrid.miniSize
                height: previewGrid.miniSize
                iconName: modelData.icon || ""
                fallbackText: modelData.name
                fallbackColor: modelData.kind === "mock" ? modelData.color : "transparent"
                cornerRadius: previewGrid.miniSize * Theme.iconRadiusRatio
                showInnerEdge: false
            }
        }
    }

    Text {
        id: label
        anchors.top: parent.top
        anchors.topMargin: Theme.iconSize + Theme.labelOffset - implicitHeight / 2
        anchors.horizontalCenter: parent.horizontalCenter
        width: Theme.pitch - Theme.iconSize * 0.1
        text: root.item ? root.item.name : ""
        color: Theme.folderLabelColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.labelFontSize
        font.weight: Font.Normal
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
        maximumLineCount: 1
        style: Text.Raised
        styleColor: Theme.labelShadow
    }

    Timer {
        id: pressTimer
        interval: 600
        repeat: false
        onTriggered: LaunchpadState.editMode = true
    }

    // Open folders explicitly from a click.
    function openSelf() {
        if (!root.item || root.item.kind !== "folder")
            return;
        const p = root.mapToItem(null, 0, 0);
        LaunchpadState.openFolder(root.item, Qt.rect(p.x - (Theme.plateSize - root.width) / 2,
                                              p.y - (Theme.plateSize - root.height) / 2,
                                              Theme.plateSize, Theme.plateSize));
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onEntered: {
            if (LaunchpadState.drag)
                return;
            LaunchpadState.selectionVisible = true;
            LaunchpadState.hoverIndex = root.itemIndex;
            LaunchpadState.page = root.pageIndex;
        }
        onExited: {
            if (!LaunchpadState.drag && LaunchpadState.hoverIndex === root.itemIndex)
                LaunchpadState.hoverIndex = -1;
        }
        onPressed: function (ev) {
            if (ev.button === Qt.LeftButton) {
                root.pressed = true;
                pressTimer.restart();
            }
        }
        onReleased: {
            root.pressed = false;
            pressTimer.stop();
        }
        onCanceled: {
            root.pressed = false;
            pressTimer.stop();
        }

        onClicked: function (ev) {
            if (ev.button === Qt.RightButton) {
                const p = root.mapToItem(null, ev.x, ev.y);
                root.contextRequested(root.item, root.pageIndex, root.itemIndex, p.x, p.y);
                return;
            }
            if (root.editMode)
                return;
            root.openSelf();
        }
    }
}
