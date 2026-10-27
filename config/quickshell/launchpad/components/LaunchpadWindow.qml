import "../Common" as Corners
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import ".."

// ─────────────────────────────────────────────────────────────────────────────
//  LaunchpadWindow — one fullscreen layer surface per screen.
//
//  The top bar and the Dock live in their own WlrLayer.Top surfaces. This
//  window also sits on Top, so instead of fighting their stacking order we
//  simply keep the tint/blur + input region between topInset and bottomInset:
//  the bar and dock stay visible, crisp and clickable above/through it.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    required property var modelData
    screen: modelData

    readonly property bool focusedHere: !Hyprland.focusedMonitor
                                        || Hyprland.focusedMonitor.name === (modelData ? modelData.name : "")
    // Map only while the Launchpad is open. The surface deliberately stops at
    // the top bar / dock margins, so clicks outside its body (the bar, the
    // dock) go to MacShell, which dismisses the Launchpad before showing its
    // own popover or focusing the clicked app.
    visible: LaunchpadState.windowVisible && focusedHere

    // Explicit input region: only the visible body is clickable.
    mask: Region {
        x: 0
        y: 0
        width: win.width
        height: win.height
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    // The layer surface itself stops below the top bar and above the dock, so
    // neither of them is blurred, tinted or covered. The Launchpad is still
    // edge-to-edge in the large area in between.
    margins {
        top: Theme.topInset
        bottom: Theme.showDock ? Theme.bottomInset : 0
    }
    implicitWidth: modelData ? modelData.width : 1280
    implicitHeight: modelData ? (modelData.height - Theme.topInset - (Theme.showDock ? Theme.bottomInset : 0)) : 800
    color: "transparent"

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-launchpad"
    WlrLayershell.layer: Theme.layerLevel === "overlay" ? WlrLayer.Overlay
                       : Theme.layerLevel === "bottom" ? WlrLayer.Bottom
                       : WlrLayer.Top
    // Allow the dock and menu bar to receive input while Launchpad is open.
    WlrLayershell.keyboardFocus: LaunchpadState.shown && focusedHere
                                 ? WlrKeyboardFocus.OnDemand
                                 : WlrKeyboardFocus.None

    property bool optionsOpen: false
    property real wheelX: 0
    property real wheelY: 0
    property real lastPageScroll: 0

    // True while an icon is being dragged OUT of the open folder: the grid
    // behind the folder lights up so the user can see where to drop it.
    readonly property bool revealGrid: contentLoader.item !== null && contentLoader.item.revealGrid

    readonly property real dotsCenterY: height - 16
    readonly property real searchBottom: Theme.searchTop + Theme.searchHeight
    readonly property real gridY: searchBottom + Math.max(20,
        (dotsCenterY - 24 - searchBottom - Theme.gridHeight - Theme.labelOffset - Theme.labelFontSize) / 2)
    readonly property real gridX: (width - Theme.gridWidth) / 2

    function updateLayout() {
        if (!focusedHere || !Theme.configLoaded || width <= 0 || height <= 0) return;
        Theme.updateLayout(width, height);
    }
    onWidthChanged: Qt.callLater(updateLayout)
    onHeightChanged: Qt.callLater(updateLayout)
    onFocusedHereChanged: Qt.callLater(updateLayout)
    Component.onCompleted: Qt.callLater(updateLayout)
    Connections {
        target: Theme
        function onSettingsSaved() { Qt.callLater(win.updateLayout); }
        function onConfigLoadedChanged() { Qt.callLater(win.updateLayout); }
        function onIconSizeChanged() { Qt.callLater(win.updateLayout); }
        function onAutoLayoutChanged() { Qt.callLater(win.updateLayout); }
    }

    // Clicking a real window (a dock app, a Spotlight result, a MacShell app)
    // dismisses the Launchpad, exactly like clicking outside it on macOS.
    Connections {
        target: Hyprland

        function onActiveToplevelChanged() {
            if (!LaunchpadState.shown || LaunchpadState.settingsOpen)
                return;
            const tl = Hyprland.activeToplevel;
            if (!tl)
                return;
            if (tl.title === "qs-launchpad-backdrop")
                return;
            LaunchpadState.close();
        }
    }

    // Preserve the layer host and its order while releasing the hidden UI.
    // windowVisible remains true until the existing close animation finishes.
    Loader {
        id: contentLoader
        anchors.fill: parent
        readonly property var hostWindow: win
        focus: true
        active: LaunchpadState.windowVisible && win.focusedHere
        // Resolve the file explicitly so an already-running QML engine can pick
        // up the new component during reload, without a stale module type cache.
        Component.onCompleted: setSource(Qt.resolvedUrl("LaunchpadContent.qml"), { win: contentLoader.hostWindow })
    }
}
