import "../Common" as Corners
import QtQuick
import QtQuick.Effects
import Quickshell.Wayland
import ".."

// MacBar-style dropdown: inset accent rows, shared nested menu corners and a
// separate shadow. A one-shot screen capture never includes the menu itself.
Item {
    id: root
    property var actions: []
    property bool shown: false
    property var captureScreen: null
    property bool captureTimedOut: false
    signal invoked(int index)

    readonly property real rowHeight: Theme.menuRowHeight
    readonly property real padY: Theme.menuInsetY
    readonly property real padX: Theme.menuInsetX
    readonly property int rowCount: actions && actions.length ? actions.length : 0
    readonly property bool glassReady: material.item !== null && material.item.ready
    function rowOffset(index) {
        let offset = 0;
        for (let i = 0; i < index; ++i)
            offset += rowHeight + (actions[i].separatorBefore ? Theme.menuSeparatorHeight : 0);
        return offset;
    }
    implicitWidth: Math.max(Theme.menuWidth, metrics.implicitWidth + 2 * (padX + Theme.menuTextInset))
    implicitHeight: rowOffset(rowCount) + padY * 2
    enabled: shown
    visible: shown || opacity > 0.01
    opacity: shown && (!captureScreen || glassReady || captureTimedOut) ? 1 : 0
    scale: shown ? 1 : 0.97
    transformOrigin: Item.TopLeft
    Behavior on opacity { NumberAnimation { duration: Theme.animationsEnabled ? 90 : 0 } }
    Behavior on scale { NumberAnimation { duration: Theme.animationsEnabled ? 110 : 0; easing.type: Easing.OutCubic } }
    onShownChanged: {
        if (shown) {
            captureTimedOut = false;
            if (captureScreen) captureWait.restart();
        } else captureWait.stop();
    }
    Timer {
        id: captureWait
        interval: 180
        onTriggered: root.captureTimedOut = true
    }

    Corners.ContinuousRectangle {
        anchors.fill: parent
        radius: Theme.menuRadius
        color: Theme.menuBackground
        antialiasing: true
    }

    Loader {
        id: material
        anchors.fill: parent
        active: root.captureScreen !== null && !root.captureTimedOut && (root.shown || root.opacity > 0.01)
        sourceComponent: Item {
            id: glass
            readonly property bool ready: snapshot.hasContent
            readonly property real margin: 72
            readonly property real ds: 0.5
            readonly property real sx: root.x
            readonly property real sy: root.y + Theme.topInset
            ScreencopyView {
                id: snapshot
                width: root.captureScreen ? root.captureScreen.width : 1
                height: root.captureScreen ? root.captureScreen.height : 1
                opacity: 0
                captureSource: root.captureScreen
                live: !hasContent && root.shown
                paintCursor: false
                onHasContentChanged: if (hasContent) captureWait.stop()
            }
            ShaderEffectSource {
                id: crop
                visible: false
                sourceItem: snapshot
                readonly property real cropX: Math.max(0, glass.sx - glass.margin)
                readonly property real cropY: Math.max(0, glass.sy - glass.margin)
                sourceRect: Qt.rect(cropX, cropY,
                    Math.max(1, Math.min(snapshot.width, glass.sx + root.width + glass.margin) - cropX),
                    Math.max(1, Math.min(snapshot.height, glass.sy + root.height + glass.margin) - cropY))
                textureSize: Qt.size(Math.max(1, Math.round(sourceRect.width * glass.ds)),
                                     Math.max(1, Math.round(sourceRect.height * glass.ds)))
                live: true
                smooth: true
            }
            MultiEffect {
                id: frost
                visible: false
                width: crop.sourceRect.width * glass.ds
                height: crop.sourceRect.height * glass.ds
                source: crop
                blurEnabled: true
                blurMax: 64
                blur: Math.min(1, 42 * 1.4 * glass.ds / 64)
                autoPaddingEnabled: false
            }
            ShaderEffectSource {
                id: frosted
                sourceItem: frost
                visible: false
                live: true
                mipmap: true
                smooth: true
            }
            ShaderEffect {
                anchors.fill: parent
                visible: glass.ready
                // The same shader used by MacShell's top-bar menus, bundled
                // with Launchpad for the folder material as well.
                fragmentShader: Qt.resolvedUrl("../assets/folder-liquidglass.frag.qsb")
                onStatusChanged: if (status === ShaderEffect.Error) {
                    console.warn("launchpad: menu glass unavailable; using the neutral surface:", log);
                    root.captureTimedOut = true;
                }
                property variant src: frosted
                property vector2d itemSize: Qt.vector2d(width, height)
                property vector2d glassSize: Qt.vector2d(width, height)
                property vector2d srcSize: Qt.vector2d(crop.sourceRect.width, crop.sourceRect.height)
                property vector2d srcOffset: Qt.vector2d(glass.sx - crop.sourceRect.x, glass.sy - crop.sourceRect.y)
                property real pad: 0
                property real radius: Theme.menuRadius
                property real bezel: Math.min(height * 0.36, 26)
                property real thickness: 22 * 0.55 * Theme.menuGlassLiquid * 1.6
                property real dispersion: 0.06 * 0.55 * Theme.menuGlassLiquid * 1.3
                property real blurPx: 1.5
                property real tintMix: Theme.menuTintMix
                property real saturation: 1.25
                property real dark: Theme.menuDark ? 1 : 0
                property real debug: 0
                property real rim: Theme.menuGlassRim
                property real grain: Theme.menuGlassGrain * 0.2
                property real magnify: 0.05 * 0.55 * Theme.menuGlassLiquid * 1.6
                property real shadowAmt: 0
                property real rimTint: 1
                property real ringW: 1.4
                property real flatInner: 0
                property real squircle: Corners.CornerTheme.smoothing
            }
        }
    }

    // Keep every outline on the shared contour, including the glass material.
    Corners.ContinuousRectangle {
        anchors.fill: parent
        anchors.margins: -1
        radius: Theme.menuRadius + 1
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, Theme.menuDark ? 0.42 : 0.14)
        antialiasing: true
    }
    Corners.ContinuousRectangle {
        anchors.fill: parent
        radius: Theme.menuRadius
        color: "transparent"
        border.width: 1
        border.color: Theme.menuRim
        antialiasing: true
        z: 2
    }
    Text {
        id: metrics
        visible: false
        font.family: Theme.menuFontFamily
        font.pixelSize: Theme.menuFontSize
        text: {
            let longest = "";
            for (let i = 0; i < root.rowCount; ++i) {
                const label = String(root.actions[i].label);
                if (label.length > longest.length) longest = label;
            }
            return longest;
        }
    }

    // The padding catches clicks before any item behind the dropdown can.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }
    Item {
        x: root.padX
        y: root.padY
        width: root.width - root.padX * 2
        height: root.height - root.padY * 2
        Repeater {
            model: root.actions
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool separated: modelData.separatorBefore === true
                readonly property bool hot: rowHover.containsMouse && modelData.enabled !== false
                x: 0
                y: root.rowOffset(index)
                width: parent.width
                height: root.rowHeight + (separated ? Theme.menuSeparatorHeight : 0)
                Corners.ContinuousRectangle {
                    visible: row.separated
                    x: 8; y: Theme.menuSeparatorHeight / 2
                    width: parent.width - 16; height: 1
                    color: Theme.menuSeparator
                }
                Item {
                    y: row.separated ? Theme.menuSeparatorHeight : 0
                    width: parent.width
                    height: root.rowHeight
                    Corners.MenuHighlight {
                        anchors.fill: parent
                        panelRadius: Theme.menuRadius
                        inset: Math.max(root.padX, root.padY)
                        color: row.hot ? Theme.menuHover : "transparent"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.menuTextInset
                        width: parent.width - x * 2
                        text: row.modelData.label
                        elide: Text.ElideRight
                        color: row.hot ? "white" : row.modelData.danger ? Theme.menuDanger : Theme.menuText
                        opacity: row.modelData.enabled === false ? 0.45 : 1
                        font.family: Theme.menuFontFamily
                        font.pixelSize: Theme.menuFontSize
                    }
                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: row.modelData.enabled !== false
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.invoked(row.index)
                    }
                }
            }
        }
    }
}
