pragma ComponentBehavior: Bound
import QtQuick

// A menu selection is an inset surface, with the same continuous curve as its panel.
Item {
    id: highlight
    property color color: "transparent"
    property real panelRadius: CornerTheme.menuRadius
    property real inset: CornerTheme.menuInset
    readonly property real radius: CornerTheme.menuItemRadius(panelRadius, inset, height)

    // Only the hovered row needs curve geometry, even in a long application menu.
    Loader {
        anchors.fill: parent
        active: highlight.visible && highlight.color.a > 0
        sourceComponent: ContinuousRectangle {
            color: highlight.color
            radius: highlight.radius
        }
    }
}
