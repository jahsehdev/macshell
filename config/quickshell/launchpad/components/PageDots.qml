import "../Common" as Corners
import QtQuick
import ".."

// ─────────────────────────────────────────────────────────────────────────────
//  PageDots — three (or more) dots, active one bright white.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property int count: 1
    property int current: 0
    signal activated(int index)

    implicitWidth: row.width
    implicitHeight: Math.max(Theme.dotDiameter, 8)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Math.max(6, Theme.dotSpacing - Theme.dotDiameter)

        Repeater {
            model: root.count

            Item {
                required property int index
                width: Theme.dotDiameter
                height: Theme.dotDiameter

                Corners.ContinuousRectangle {
                    anchors.centerIn: parent
                    width: Theme.dotDiameter
                    height: Theme.dotDiameter
                    radius: width / 2
                    color: index === root.current ? Qt.rgba(1, 1, 1, 0.95) : Qt.rgba(1, 1, 1, 0.38)

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                    }
                    scale: index === root.current ? 1.12 : 0.92
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -5
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activated(index)
                }
            }
        }
    }
}
