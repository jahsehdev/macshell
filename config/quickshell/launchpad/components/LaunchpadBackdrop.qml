import "../Common" as Corners
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import ".."

// ─────────────────────────────────────────────────────────────────────────────
//  LaunchpadBackdrop — a full-screen *normal* window that sits behind the
//  top bar and dock (those are layer-shell surfaces on WlrLayer.Top) but above
//  every application window.
//
//  Render the same opaque, blurred scene sampled by the bar, dock and search
//  glass. Compositor-only blur cannot be reproduced by a window screencopy.
//
//  The actual content (search field, icons, folders) lives in a separate
//  layer surface, which is above this window.
// ─────────────────────────────────────────────────────────────────────────────
FloatingWindow {
    id: root

    required property var modelData
    screen: modelData

    readonly property bool focusedHere: !Hyprland.focusedMonitor
                                        || Hyprland.focusedMonitor.name === (modelData ? modelData.name : "")

    visible: LaunchpadState.windowVisible && focusedHere
    title: "qs-launchpad-backdrop"
    // Visual-only surface: all pointer input belongs to the content or panels.
    mask: Region {}
    color: "transparent"

    implicitWidth: modelData ? modelData.width : 1280
    implicitHeight: modelData ? modelData.height : 800
    // Keep the window host stable; decoded images only live while it is shown.
    Loader {
        anchors.fill: parent
        active: LaunchpadState.windowVisible && root.focusedHere
        sourceComponent: Corners.LaunchpadBackground {
            screenName: root.modelData ? root.modelData.name : ""
            imageSource: Theme.backgroundType === "wallpaper" ? "file://" + Theme.tahoeWallpaper
                       : Theme.backgroundType === "custom" ? Theme.customImage
                       : Corners.LaunchpadGlassState.imageFor(screenName)
            backgroundBlur: Theme.backgroundBlur
            dimming: Theme.backgroundOpacity
        }
    }
}
