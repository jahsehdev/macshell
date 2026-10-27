import "../Common" as Corners
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Window
import Quickshell.Wayland
import ".."

// ─────────────────────────────────────────────────────────────────────────────
//  FolderPanel — a centered glass panel that zooms out of the folder tile.
//
//  Drag-out
//    Press and drag an app past the panel edge. The panel fades, the Launchpad
//    grid behind it lights up and a slot indicator shows where the app will
//    land. Release outside the panel to move the app from the folder back into
//    the Launchpad at that slot; release inside to cancel.
//
//    Needs ONE function in LaunchpadState:
//        removeFromFolder(item, page, index)
//    index = slot inside page `page` (0..N), or -1 for "end of the page".
//    If that function does not exist, drag-out stays disabled and a warning is
//    printed in the Quickshell log.
//
//    The tiles in this panel use their own overlay MouseArea (click = launch,
//    right click = menu, drag = remove), so they can never conflict with the
//    grid drag logic inside AppTile.
//
//  Background
//    Freeze one screen frame before revealing the folder, then blur it or
//    refract it with MacShell's Liquid Glass shader. `backdrop` supplies a
//    content-only fallback when screen capture is unavailable.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var folder: LaunchpadState.foldered
    property rect origin: LaunchpadState.folderOrigin
    property bool renaming: false
    property real panelScale: 0.2

    // ── blur settings ─────────────────────────────────────────────────────────
    // Item whose pixels are behind this panel. Must NOT be an ancestor of the
    // panel. Set it from LaunchpadWindow:  FolderPanel { backdrop: contentLayer }
    property Item backdrop: null
    property real backdropBlur: Theme.folderBackgroundBlur // 0..1
    property int backdropBlurMax: 64               // larger = wider blur
    property real backdropBlurMultiplier: 1.4      // extra strength
    property real backdropTextureScale: backdropBlur > 0 ? 0.5 : 1.0

    // ── drag-out settings ─────────────────────────────────────────────────────
    // The PagedGrid behind the panel, used to find the drop slot.
    property Item gridItem: null
    property bool closeAfterRemove: Theme.closeAfterRemove
    property bool closing: false
    property int selectedIndex: 0
    property bool keyboardSelection: false
    signal dragCancelled()

    property Item autoBackdrop: null
    property var captureScreen: null
    property bool captureTimedOut: false
    property bool shaderFailed: false
    readonly property bool liquidGlass: Theme.folderBackgroundStyle === "liquid"
                                       && screenSnapshot.hasContent && !shaderFailed
    readonly property Item effectiveBackdrop: screenSnapshot.hasContent ? screenSnapshot : (backdrop ? backdrop : autoBackdrop)
    readonly property bool hasBackdrop: effectiveBackdrop !== null
    property rect backdropRect: Qt.rect(0, 0, 1, 1)

    readonly property int count: folder ? folder.items.length : 0
    onCountChanged: selectedIndex = Math.max(0, Math.min(selectedIndex, count - 1))
    readonly property int cols: Math.max(1, Math.min(Theme.folderCols, Math.floor((width - 32 - Theme.iconSize * 0.8) / Theme.pitch), Math.max(1, count)))
    readonly property int rows: Math.max(1, Math.ceil(count / cols))
    readonly property real panelW: cols * Theme.pitch + Theme.iconSize * 0.8
    readonly property real panelH: Math.max(0, Math.min(height - 32, Theme.iconSize * 0.95 + Theme.folderRows * Theme.pitch + Theme.iconSize * 0.45,
                                               Theme.iconSize * 0.95 + rows * Theme.pitch + Theme.iconSize * 0.45))

    // ── drag state ────────────────────────────────────────────────────────────
    readonly property bool canRemove: typeof LaunchpadState.removeFromFolder === "function"
    property var dragItem: null
    property point dragScenePos: Qt.point(0, 0) // pointer, window coordinates
    property point dragPos: Qt.point(0, 0)      // pointer, this item's coordinates
    property point dragGrab: Qt.point(0, 0)     // icon center minus pointer at drag start
    property int dropIndex: -1                  // slot under the pointer (-1 = none)
    property rect dropRect: Qt.rect(0, 0, 0, 0) // that slot, this item's coordinates
    readonly property bool dragging: dragItem !== null
    readonly property bool dragOutside: dragging && isOutsidePanel(dragPos)

    width: parent ? parent.width : 0
    height: parent ? parent.height : 0

    opacity: 0

    Component.onCompleted: {
        forceActiveFocus();
        findBackdrop();
        syncBackdropRect();
        // Stay transparent until the one-shot capture completes, so the folder
        // cannot be included in its own backdrop. Never continuously screen-copy.
        if (!captureScreen) revealPanel();
        if (!canRemove)
            console.warn("launchpad: LaunchpadState.removeFromFolder(item, page, index) is missing - drag-out is disabled.");
    }
    Component.onDestruction: cancelDrag()
    onVisibleChanged: if (!visible) cancelDrag()
    onEnabledChanged: if (!enabled) cancelDrag()
    Connections {
        target: root.Window.window
        function onActiveChanged() { if (!root.Window.window.active) root.cancelDrag(); }
    }

    function revealPanel() {
        if (closing) return;
        syncBackdropRect();
        opacity = 1;
        panelScale = 1;
    }

    ScreencopyView {
        id: screenSnapshot
        x: 0
        y: -Theme.topInset
        width: root.captureScreen ? root.captureScreen.width : root.width
        height: root.captureScreen ? root.captureScreen.height : root.height
        opacity: 0
        captureSource: root.captureTimedOut ? null : root.captureScreen
        // The recording context is created asynchronously. Let it produce its
        // first frame, then freeze immediately before the panel is revealed.
        live: !hasContent && !root.captureTimedOut
        paintCursor: false
        onHasContentChanged: if (hasContent) { captureTimeout.stop(); root.revealPanel(); }
    }

    // Unsupported screencopy must not prevent a folder from opening.
    Timer {
        id: captureTimeout
        interval: 180
        running: true
        onTriggered: {
            if (!screenSnapshot.hasContent) root.captureTimedOut = true;
            root.revealPanel();
        }
    }

    onWidthChanged: syncBackdropRect()
    onHeightChanged: syncBackdropRect()
    onEffectiveBackdropChanged: syncBackdropRect()

    Behavior on opacity { NumberAnimation { duration: Theme.animationsEnabled ? 180 : 0; easing.type: Easing.OutCubic } }
    Behavior on panelScale { NumberAnimation { duration: Theme.animationsEnabled ? Theme.animFolder : 0; easing.type: Easing.OutCubic } }

    // ── helpers: backdrop ─────────────────────────────────────────────────────
    // Fallback only (when this panel is NOT created through a Loader): pick the
    // sibling with the most children.
    function findBackdrop() {
        if (backdrop || !parent)
            return;
        let best = null;
        let bestScore = -1;
        for (let i = 0; i < parent.children.length; ++i) {
            const c = parent.children[i];
            if (c === root || !c.visible || c.width <= 0 || c.height <= 0)
                continue;
            const score = c.children ? c.children.length : 0;
            if (score > bestScore) {
                best = c;
                bestScore = score;
            }
        }
        autoBackdrop = best;
    }

    // Where the panel sits inside the backdrop item (ignores the zoom transform).
    function syncBackdropRect() {
        const b = effectiveBackdrop;
        if (!b)
            return;
        const p = root.mapToItem(b, panel.x, panel.y);
        backdropRect = Qt.rect(p.x, p.y, Math.max(1, panel.width), Math.max(1, panel.height));
    }

    // The grid may still be animating (dim / scale) while the panel opens, so
    // re-sync for the first ~0.7 s only. No timers run while idle.
    Timer {
        id: syncTimer
        property int ticks: 0
        interval: 16
        repeat: true
        running: root.hasBackdrop
        onTriggered: {
            root.syncBackdropRect();
            if (++ticks > 45)
                stop();
        }
    }

    Connections {
        target: panel
        function onXChanged() { root.syncBackdropRect(); }
        function onYChanged() { root.syncBackdropRect(); }
        function onWidthChanged() { root.syncBackdropRect(); }
        function onHeightChanged() { root.syncBackdropRect(); }
    }

    // ── helpers: drag-out ─────────────────────────────────────────────────────
    function isOutsidePanel(p) {
        const m = Theme.iconSize * 0.25;
        const local = panel.mapFromItem(root, p.x, p.y);
        return local.x < -m || local.x > panel.width + m
            || local.y < -m || local.y > panel.height + m;
    }

    function beginDrag(cell, it, scenePos) {
        if (!canRemove || closing || dragging || LaunchpadState.folderRemovalBusy || LaunchpadState.drag) return false;
        LaunchpadState.cancelFolderClose();
        LaunchpadState.menu = null;
        forceActiveFocus();
        const p = root.mapFromItem(null, scenePos.x, scenePos.y);
        const c = cell.mapToItem(root, cell.width / 2, Theme.iconSize / 2);
        dragGrab = Qt.point(c.x - p.x, c.y - p.y);
        dragScenePos = scenePos;
        dragPos = p;
        dragItem = it;
        if (Theme.debugDrag) console.info("launchpad: folder drag started", it.id);
        return true;
    }

    function updateDrag(scenePos) {
        if (dragItem === null)
            return;
        dragScenePos = scenePos;
        dragPos = root.mapFromItem(null, scenePos.x, scenePos.y);
        updateDropTarget();
    }

    // Slot indicator on the grid while the icon is outside the panel.
    function updateDropTarget() {
        if (!gridItem || !isOutsidePanel(dragPos)) {
            dropIndex = -1;
            return;
        }
        const idx = gridItem.slotAt(dragScenePos.x, dragScenePos.y);
        if (idx < 0) {
            dropIndex = -1;
            return;
        }
        const r = gridItem.slotRect(idx);
        const tl = root.mapFromItem(null, r.x, r.y);
        const br = root.mapFromItem(null, r.x + r.width, r.y + r.height);
        dropRect = Qt.rect(tl.x, tl.y, br.x - tl.x, br.y - tl.y);
        dropIndex = idx;
    }

    function cancelDrag() {
        dragItem = null;
        dropIndex = -1;
        dragCancelled();
    }

    function endDrag(scenePos) {
        if (dragItem === null)
            return;
        if (scenePos) updateDrag(scenePos);
        const it = dragItem;
        const outside = isOutsidePanel(dragPos);
        const slot = (outside && gridItem) ? gridItem.slotAt(dragScenePos.x, dragScenePos.y) : -1;
        dragItem = null;
        dropIndex = -1;
        if (Theme.debugDrag) console.info("launchpad: folder drag ended", it.id, "outside", outside, "slot", slot);
        if (outside)
            commitRemoval(it, slot);
    }

    function commitRemoval(it, slot) {
        if (!canRemove || closing) return false;
        const success = LaunchpadState.removeFromFolder(it, LaunchpadState.page, slot);
        if (success && closeAfterRemove && LaunchpadState.folderOpen) requestClose();
        return success;
    }

    function requestClose() {
        if (closing) return;
        cancelDrag();
        closing = true;
        opacity = 0;
        panelScale = 0.2;
        if (Theme.animationsEnabled) closeTimer.start();
        else LaunchpadState.closeFolder();
    }
    Timer { id: closeTimer; interval: Theme.animFolder; onTriggered: LaunchpadState.closeFolder() }

    function removeSelected() {
        if (folder && folder.items.length) return commitRemoval(folder.items[Math.min(selectedIndex, folder.items.length - 1)], -1);
        return false;
    }

    function handleKey(event) {
        if (closing || renaming) return false;
        if (event.key === Qt.Key_Escape) {
            if (!cancelDragOnEscape()) {
                if (LaunchpadState.menu) LaunchpadState.menu = null;
                else requestClose();
            }
            return true;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (event.modifiers & Qt.ShiftModifier) removeSelected();
            else if (folder && folder.items.length) LaunchpadState.launch(folder.items[selectedIndex], true);
            return true;
        }
        let offset = 0;
        if (event.key === Qt.Key_Left) offset = -1;
        else if (event.key === Qt.Key_Right) offset = 1;
        else if (event.key === Qt.Key_Up) offset = -cols;
        else if (event.key === Qt.Key_Down) offset = cols;
        else if (event.key === Qt.Key_Tab) offset = event.modifiers & Qt.ShiftModifier ? -1 : 1;
        else return false;
        if (!dragging) {
            selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + offset));
            keyboardSelection = true;
            const top = Math.floor(selectedIndex / cols) * Theme.pitch;
            if (top < flick.contentY) flick.contentY = top;
            else if (top + Theme.pitch > flick.contentY + flick.height)
                flick.contentY = Math.min(flick.contentHeight - flick.height, top + Theme.pitch - flick.height);
        }
        return true;
    }

    // The same handler is used by the window before its ordinary Escape chain.
    function cancelDragOnEscape() {
        if (!dragging) return false;
        cancelDrag();
        return true;
    }
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
        if (handleKey(event)) event.accepted = true;
    }

    // click outside closes the folder
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: { if (LaunchpadState.menu) LaunchpadState.menu = null; else root.requestClose(); }
    }

    Item {
        id: panel
        objectName: "folder-panel"
        enabled: !root.closing

        width: root.panelW
        height: root.panelH
        anchors.horizontalCenter: parent.horizontalCenter
        y: (parent.height - height) / 2

        // fades while an icon is dragged outside, as a "release to remove" cue
        opacity: root.dragOutside ? Theme.panelDragOutsideOpacity : 1.0
        Behavior on opacity { NumberAnimation { duration: Theme.animationsEnabled ? 150 : 0; easing.type: Easing.OutCubic } }

        transform: Scale {
            origin.x: Math.max(0, Math.min(panel.width, root.origin.x + root.origin.width / 2 - panel.x))
            origin.y: Math.max(0, Math.min(panel.height, root.origin.y + root.origin.height / 2 - panel.y))
            xScale: root.panelScale
            yScale: root.panelScale
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function (mouse) { mouse.accepted = true; }
        }

        // ── frosted backdrop: blurred copy of what is behind the panel ────────
        ShaderEffectSource {
            id: backdropTex
            visible: false
            width: panel.width
            height: panel.height
            sourceItem: root.effectiveBackdrop
            // Extra pixels keep blur/refraction from smearing the panel edges.
            readonly property real margin: 96
            readonly property real captureX: Math.max(0, root.backdropRect.x - margin)
            readonly property real captureY: Math.max(0, root.backdropRect.y - margin)
            readonly property real insetX: root.backdropRect.x - captureX
            readonly property real insetY: root.backdropRect.y - captureY
            sourceRect: Qt.rect(captureX, captureY,
                Math.max(1, Math.min(root.effectiveBackdrop ? root.effectiveBackdrop.width : 1,
                                    root.backdropRect.x + panel.width + margin) - captureX),
                Math.max(1, Math.min(root.effectiveBackdrop ? root.effectiveBackdrop.height : 1,
                                    root.backdropRect.y + panel.height + margin) - captureY))
            textureSize: Qt.size(Math.max(1, Math.round(sourceRect.width * root.backdropTextureScale)),
                                 Math.max(1, Math.round(sourceRect.height * root.backdropTextureScale)))
            live: true
            hideSource: false
            smooth: true
        }

        Squircle {
            id: frostMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            radius: Theme.folderPanelRadius
            exponent: Theme.squircleExponent
            segmentsPerCorner: Theme.squircleSegments
            fillColor: "white"
        }

        MultiEffect {
            id: backdropFrost
            x: -backdropTex.insetX
            y: -backdropTex.insetY
            width: backdropTex.sourceRect.width
            height: backdropTex.sourceRect.height
            visible: false
            source: backdropTex
            autoPaddingEnabled: false

            blurEnabled: root.backdropBlur > 0
            blur: root.backdropBlur
            blurMax: root.backdropBlurMax
            blurMultiplier: root.backdropBlurMultiplier

            saturation: root.liquidGlass ? 0 : 0.25
            brightness: root.liquidGlass ? 0 : 0.04
        }

        ShaderEffectSource {
            id: frostedTexture
            sourceItem: root.liquidGlass ? backdropFrost : null
            live: true
            visible: false
            mipmap: true
            smooth: true
        }

        MultiEffect {
            anchors.fill: parent
            visible: root.hasBackdrop && !root.liquidGlass
            source: normalTexture
            // Crop the padded pre-blur back to the panel before masking it.
            maskEnabled: true
            maskSource: frostMask
            autoPaddingEnabled: false
        }

        ShaderEffectSource {
            id: normalTexture
            sourceItem: !root.liquidGlass ? backdropFrost : null
            sourceRect: Qt.rect(backdropTex.insetX, backdropTex.insetY, panel.width, panel.height)
            live: true
            visible: false
            smooth: true
        }

        ShaderEffect {
            id: liquidSurface
            anchors.fill: parent
            visible: root.liquidGlass
            // Shares Common/DarkGlass.glsl's shallow Dark material with the shell.
            fragmentShader: Qt.resolvedUrl("../assets/folder-liquidglass.frag.qsb")
            onStatusChanged: if (status === ShaderEffect.Error) {
                root.shaderFailed = true;
                console.warn("FolderPanel: Liquid Glass unavailable; using Normal Blur:", log);
            }
            property variant src: frostedTexture
            property vector2d itemSize: Qt.vector2d(width, height)
            property vector2d glassSize: Qt.vector2d(width, height)
            property vector2d srcSize: Qt.vector2d(backdropTex.sourceRect.width, backdropTex.sourceRect.height)
            property vector2d srcOffset: Qt.vector2d(backdropTex.insetX, backdropTex.insetY)
            property real pad: 0
            property real radius: Theme.folderPanelRadius
            property real bezel: Math.min(height * 0.36, 26)
            property real thickness: 30 * 1.6
            property real dispersion: 0.06 * 1.3
            property real blurPx: root.backdropBlur > 0 ? 1.5 * root.backdropBlur : 0
            property real tintMix: 0.12
            property real saturation: 1.25
            property real dark: Theme.darkMode ? 1 : 0
            property real debug: 0
            property real rim: 0.45
            property real grain: 0.006
            property real magnify: 0.05 * 1.6
            property real shadowAmt: 0
            property real rimTint: 0
            property real ringW: -1.4
            property real flatInner: 1
            property real squircle: Math.max(0, Math.min(1, (Theme.squircleExponent - 2) / 2))
        }

        // glass body (a bit more opaque when no backdrop is available, to imitate frost)
        Squircle {
            anchors.fill: parent
            visible: !root.liquidGlass
            radius: Theme.folderPanelRadius
            exponent: Theme.squircleExponent
            segmentsPerCorner: Theme.squircleSegments

            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: panel.height
                GradientStop { position: 0.0; color: Qt.rgba(190 / 255, 205 / 255, 255 / 255, root.hasBackdrop ? 0.26 : 0.50) }
                GradientStop { position: 1.0; color: Qt.rgba(120 / 255, 140 / 255, 235 / 255, root.hasBackdrop ? 0.20 : 0.40) }
            }
        }

        Squircle {
            anchors.fill: parent
            visible: !root.liquidGlass
            radius: Theme.folderPanelRadius
            exponent: Theme.squircleExponent
            segmentsPerCorner: Theme.squircleSegments
            ring: true
            ringInset: 1
            fillColor: Qt.rgba(1, 1, 1, 0.30)
        }

        // title / rename
        Item {
            id: titleArea
            x: Theme.iconSize * 0.4
            y: Theme.iconSize * 0.22
            width: panel.width - Theme.iconSize * 0.8
            height: Theme.iconSize * 0.52

            Text {
                anchors.centerIn: parent
                visible: !root.renaming
                text: root.folder ? root.folder.name : ""
                color: Qt.rgba(1, 1, 1, 0.96)
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(13, Theme.iconSize * 0.28)
                font.weight: Font.DemiBold

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onClicked: {
                        root.renaming = true;
                        renameInput.text = root.folder ? root.folder.name : "";
                        renameInput.forceActiveFocus();
                    }
                }
            }

            TextInput {
                selectionColor: Corners.ThemeColors.selectionFor("launchpad", Theme.darkMode)
                selectedTextColor: Corners.ThemeColors.selectedTextFor("launchpad", Theme.darkMode)
                id: renameInput
                objectName: "folder-rename-input"
                anchors.fill: parent
                visible: root.renaming
                text: root.folder ? root.folder.name : ""
                color: Qt.rgba(1, 1, 1, 0.98)
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(13, Theme.iconSize * 0.28)
                font.weight: Font.DemiBold
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                function commitRename() {
                    LaunchpadState.renameFolder(text);
                    root.renaming = false;
                    root.forceActiveFocus();
                }
                onAccepted: commitRename()
                // Consume the key before it can bubble into folder activation.
                Keys.onReturnPressed: event => { commitRename(); event.accepted = true; }
                Keys.onEnterPressed: event => { commitRename(); event.accepted = true; }
                Keys.onEscapePressed: event => { root.renaming = false; root.forceActiveFocus(); event.accepted = true; }
            }
        }

        Flickable {
            id: flick
            objectName: "folder-scroll"
            x: Theme.iconSize * 0.4
            y: Theme.iconSize * 0.95
            width: panel.width - Theme.iconSize * 0.8
            height: Math.max(0, panel.height - Theme.iconSize * 1.4)
            contentWidth: width
            contentHeight: root.rows * Theme.pitch
            clip: true
            interactive: !root.dragging
            boundsBehavior: Flickable.StopAtBounds

            Item {
                width: flick.width
                height: root.rows * Theme.pitch

                Repeater {
                    model: root.folder ? root.folder.items : []

                    Item {
                        id: cell
                        objectName: "folder-cell-" + index

                        required property var modelData
                        required property int index

                        x: (index % root.cols) * Theme.pitch + (Theme.pitch - Theme.iconSize) / 2
                        y: Math.floor(index / root.cols) * Theme.pitch
                        width: Theme.iconSize
                        height: Theme.iconSize + Theme.labelOffset + Theme.labelFontSize * 1.4 + 4

                        opacity: root.dragItem === modelData ? 0.28 : 1.0
                        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                        Accessible.name: modelData.name
                        Accessible.role: Accessible.Button
                        SelectionPlate {
                            z: -1
                            x: (Theme.iconSize - width) / 2
                            y: (Theme.iconSize - height) / 2
                            shown: root.keyboardSelection && root.selectedIndex === cell.index && !root.dragging
                        }

                        // visual only; all input is handled by the overlay below
                        AppTile {
                            interactive: false
                            item: cell.modelData
                            pageIndex: LaunchpadState.page
                            itemIndex: cell.index
                            editMode: false
                            width: cell.width
                            height: cell.height

                            onContextRequested: function (it, pg, ix, gx, gy) {
                                LaunchpadState.menu = { item: it, page: pg, index: ix, x: gx, y: gy };
                            }
                        }

                        // click = launch, right click = menu, drag = remove from folder
                        MouseArea {
                            id: cellMouse
                            objectName: "folder-input-" + cell.index

                            property point pressScene: Qt.point(0, 0)
                            property bool pressedLeft: false
                            property bool didDrag: false

                            anchors.fill: parent
                            z: 10
                            hoverEnabled: true
                            preventStealing: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                            onEntered: if (!root.dragging) { root.selectedIndex = cell.index; root.keyboardSelection = false; }
                            Connections {
                                target: root
                                function onDragCancelled() {
                                    if (cellMouse.pressedLeft) cellMouse.didDrag = true;
                                    cellMouse.pressedLeft = false;
                                    pressTimer.stop();
                                }
                            }
                            Timer {
                                id: pressTimer
                                interval: Theme.longPressDelay
                                onTriggered: LaunchpadState.editMode = true
                            }

                            onPressed: function (ev) {
                                if (ev.button !== Qt.LeftButton || root.dragging || root.closing)
                                    return;
                                root.selectedIndex = cell.index;
                                pressedLeft = true;
                                didDrag = false;
                                pressScene = mapToItem(null, ev.x, ev.y);
                                pressTimer.restart();
                            }

                            onPositionChanged: function (ev) {
                                if (!pressedLeft)
                                    return;
                                const s = mapToItem(null, ev.x, ev.y);
                                if (!root.dragging) {
                                    if (!root.canRemove)
                                        return;
                                    const dx = s.x - pressScene.x;
                                    const dy = s.y - pressScene.y;
                                    if (dx * dx + dy * dy < Theme.dragThreshold * Theme.dragThreshold)
                                        return;
                                    pressTimer.stop();
                                    didDrag = root.beginDrag(cell, cell.modelData, pressScene);
                                }
                                root.updateDrag(s);
                            }

                            onReleased: function (ev) {
                                if (ev.button !== Qt.LeftButton)
                                    return;
                                pressedLeft = false;
                                pressTimer.stop();
                                if (root.dragging)
                                    root.endDrag(mapToItem(null, ev.x, ev.y));
                            }

                            onCanceled: {
                                pressedLeft = false;
                                pressTimer.stop();
                                if (root.dragging)
                                    root.cancelDrag();
                            }

                            onClicked: function (ev) {
                                if (root.dragging || root.closing) return;
                                if (ev.button === Qt.RightButton) {
                                    const p = mapToItem(null, ev.x, ev.y);
                                    LaunchpadState.menu = { item: cell.modelData, page: LaunchpadState.page, index: cell.index, x: p.x, y: p.y, source: "folder" };
                                    return;
                                }
                                if (didDrag) {
                                    didDrag = false;
                                    return;
                                }
                                if (LaunchpadState.editMode) return;
                                LaunchpadState.launch(cell.modelData, true);
                            }
                        }
                    }
                }
            }
        }

        // subtle inner glow
        Squircle {
            anchors.fill: parent
            radius: Theme.folderPanelRadius
            exponent: Theme.squircleExponent
            segmentsPerCorner: Theme.squircleSegments
            ring: true
            ringInset: 2
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: panel.height
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.09) }
                GradientStop { position: 0.5; color: "transparent" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    // ── drop slot indicator (on the grid behind the panel) ────────────────────
    Item {
        id: dropIndicator
        objectName: "folder-drop-indicator"

        visible: root.dragging && root.dragOutside && root.dropIndex >= 0
        z: 90
        x: root.dropRect.x
        y: root.dropRect.y
        width: root.dropRect.width
        height: root.dropRect.height
        Behavior on x { NumberAnimation { duration: Theme.animDropIndicator } }
        Behavior on y { NumberAnimation { duration: Theme.animDropIndicator } }

        Squircle {
            anchors.fill: parent
            radius: Theme.iconRadius * 1.3
            exponent: Theme.squircleExponent
            segmentsPerCorner: Theme.squircleSegments
            fillColor: Theme.dropIndicatorFill
            strokeColor: Theme.dropIndicatorStroke
            strokeWidth: Theme.dropIndicatorStrokeWidth
        }
    }

    // ── drag ghost ────────────────────────────────────────────────────────────
    // Lives directly in root (not in the clipped Flickable) so it can leave the panel.
    Item {
        id: ghost
        objectName: "folder-drag-ghost"

        visible: root.dragging
        z: 100
        width: Theme.iconSize
        height: Theme.iconSize
        x: root.dragPos.x + root.dragGrab.x - width / 2
        y: root.dragPos.y + root.dragGrab.y - height / 2
        scale: root.dragOutside ? 1.14 : 1.06
        opacity: 0.96

        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

        layer.enabled: root.dragging
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0.12, 0.45)
            shadowBlur: 0.7
            shadowVerticalOffset: 6
        }

        IconView {
            anchors.fill: parent
            iconName: root.dragItem ? (root.dragItem.icon || "") : ""
            fallbackText: root.dragItem ? root.dragItem.name : ""
            fallbackColor: root.dragItem && root.dragItem.kind === "mock" ? root.dragItem.color : "transparent"
            cornerRadius: Theme.iconRadius
        }
    }
}
