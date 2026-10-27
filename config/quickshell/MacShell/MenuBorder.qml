import "Common" as Corners
import QtQuick

// Extra edge detail for the top-bar dropdown menus, drawn over the glass (whose own shader draws the bright rim that
// follows the local wallpaper colour):
//   * a dark hairline just outside the menu, like the separator macOS draws between a menu and the desktop
//   * a very faint line in the wallpaper's dominant colour along the edge, so the whole border leans towards it
// `tint` animates, so the colour slides to the new one when the wallpaper changes.
Item {
    id: mb
    property color tint: "#8A9AB5"
    property bool dark: true
    property real cornerR: 14
    readonly property real effectiveRadius: Corners.CornerTheme.panelRadius(width,height,cornerR,Corners.CornerTheme.smoothing)
    property real amount: 1             // overall strength of both lines (1 = menus, <1 = subtler)

    Behavior on tint { ColorAnimation { duration: 450; easing.type: Easing.OutCubic } }

    Corners.ContinuousRectangle {                                         // dark hairline, just outside
        anchors.fill: parent
        anchors.margins: -1
        radius: mb.effectiveRadius + 1
        color: "transparent"
        antialiasing: true
        border.width: 1
        border.color: mb.dark ? Qt.rgba(0, 0, 0, 0.42 * mb.amount) : Qt.rgba(0, 0, 0, 0.14 * mb.amount)
    }
    Corners.ContinuousRectangle {                                         // faint dominant-colour edge
        anchors.fill: parent
        radius: mb.effectiveRadius
        color: "transparent"
        antialiasing: true
        border.width: 1.25
        border.color: Qt.rgba(mb.tint.r, mb.tint.g, mb.tint.b, (mb.dark ? 0.16 : 0.12) * mb.amount)
    }
}
