import QtQuick
import QtQuick.Shapes
import ".."

// ─────────────────────────────────────────────────────────────────────────────
//  SelectionPlate — the dark indigo squircle behind the focused/hovered icon.
//  One instance per tile, fixed behind its icon.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool shown: false

    width: Theme.plateSize
    height: Theme.plateSize

    opacity: shown ? 1 : 0
    visible: opacity > 0.01

    Behavior on opacity {
        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }

    Squircle {
        anchors.fill: parent
        radius: Theme.plateRadius
        exponent: Theme.squircleExponent
        segmentsPerCorner: Theme.squircleSegments
        fillColor: Theme.plateFill
    }

    Squircle {
        anchors.fill: parent
        radius: Theme.plateRadius
        exponent: Theme.squircleExponent
        segmentsPerCorner: Theme.squircleSegments
        ring: true
        ringInset: 1
        fillColor: Theme.plateRim
    }
}
