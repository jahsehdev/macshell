import QtQuick
import QtQuick.Shapes
import ".."

// ─────────────────────────────────────────────────────────────────────────────
//  GlassBorder — the liquid-glass rim used by the search pill and the folder
//  panel. A thin gradient ring (bright top-left, dim middle, brighter again at
//  the bottom-right) plus a soft highlight that follows the top edge.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real radius: 0
    property real exponent: Theme.squircleExponent
    property real inset: 1
    property color bright: Theme.searchBorderBright
    property color mid: Theme.searchBorderMid
    property color dim: Theme.searchBorderDim
    property color sheen: Theme.searchSheen
    property bool showSheen: true
    property bool cornerHighlightsOnly: false

    Squircle {
        anchors.fill: parent
        radius: root.radius
        exponent: root.exponent
        segmentsPerCorner: Theme.squircleSegments
        ring: true
        ringInset: Math.max(1, root.inset)

        fillGradient: LinearGradient {
            x1: 0
            y1: 0
            x2: root.width
            y2: root.height
            GradientStop { position: 0.00; color: root.bright }
            GradientStop { position: 0.22; color: root.mid }
            GradientStop { position: 0.40; color: root.cornerHighlightsOnly ? "transparent" : root.dim }
            GradientStop { position: 0.60; color: root.cornerHighlightsOnly ? "transparent" : root.dim }
            GradientStop { position: 0.80; color: root.mid }
            GradientStop { position: 1.00; color: root.bright }
        }
    }

    Squircle {
        anchors.fill: parent
        visible: root.showSheen
        radius: root.radius
        exponent: root.exponent
        segmentsPerCorner: Theme.squircleSegments
        ring: true
        ringInset: Math.max(1, root.inset)

        fillGradient: LinearGradient {
            x1: 0
            y1: 0
            x2: 0
            y2: root.height
            GradientStop { position: 0.00; color: root.sheen }
            GradientStop { position: 0.45; color: "transparent" }
            GradientStop { position: 1.00; color: "transparent" }
        }
    }
}
