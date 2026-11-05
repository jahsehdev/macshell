pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import "CornerMath.js" as Curve

Button {
    id: button
    property bool dark: false
    property bool selected: false
    property bool subtle: false
    property bool round: false
    property string hint: ""
    property color foreground: dark ? "#eeeeef" : "#3e3e42"
    implicitHeight: 30
    implicitWidth: 80
    focusPolicy: Qt.StrongFocus
    Accessible.name: hint || text
    background: Rectangle {
        radius: button.round ? Math.min(width, height) / 2 : 6
        color: button.selected ? "#245e95ff" : button.down ? (button.dark ? "#626269" : "#c9c9ce")
            : button.hovered ? (button.dark ? "#505057" : "#d6d6da")
            : button.subtle ? "transparent" : button.dark ? "#424249" : "#dddddf"
        border.width: button.selected || button.activeFocus ? 2 : 0
        border.color: "#347cff"
    }
    contentItem: Text {
        text: button.text
        font: button.font
        color: button.foreground
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    font.family: "sans-serif"
    font.pixelSize: 13
    ToolTip {
        id: popup
        objectName: "folderTooltip-" + button.objectName
        parent: button.Window.contentItem
        readonly property point topAnchor: {
            // Track scrolling and panel movement as well as the button itself.
            let item = button;
            while (item && item !== parent) {
                item.x; item.y; item.width; item.height; item.scale; item.rotation;
                item = item.parent;
            }
            return parent ? button.mapToItem(parent, button.width / 2, 0) : Qt.point(0, 0);
        }
        readonly property point bottomAnchor: {
            topAnchor;
            return parent ? button.mapToItem(parent, button.width / 2, button.height) : Qt.point(0, 0);
        }
        readonly property bool below: topAnchor.y - height - 6 < 8
            && !!parent && parent.height - bottomAnchor.y >= topAnchor.y
        x: Math.max(8, Math.min(parent ? parent.width - width - 8 : topAnchor.x, topAnchor.x - width / 2))
        y: Math.max(8, Math.min(parent ? parent.height - height - 8 : Infinity,
            below ? bottomAnchor.y + 6 : topAnchor.y - height - 6))
        visible: button.hovered && !button.down && button.visible && button.hint !== ""
        text: button.hint
        delay: 650
        timeout: -1
        padding: 0; margins: 8
        implicitWidth: bubble.implicitWidth
        implicitHeight: bubble.implicitHeight
        popupType: Popup.Item
        closePolicy: Popup.NoAutoClose
        focus: false
        background: null
        // Copy DockTooltip's frosted label directly, using its same shared curve.
        // Native items keep this usable through both directory imports and reloads.
        contentItem: Item {
            id: bubble
            readonly property real bodyHeight: 32
            readonly property real tailHeight: 7
            readonly property real tailHalfWidth: 9
            readonly property real edgePadding: 16
            readonly property real tailX: Math.max(bodyHeight / 2 + tailHalfWidth,
                Math.min(width - bodyHeight / 2 - tailHalfWidth, popup.topAnchor.x - popup.x))
            implicitWidth: Math.min(Math.max(60, Math.min(320, popup.parent ? popup.parent.width - 16 : 320)),
                Math.max(60, label.implicitWidth + edgePadding * 2))
            implicitHeight: bodyHeight + tailHeight
            function outline(inset) {
                return Curve.tailPath(width, bodyHeight, bodyHeight / 2,
                    tailHeight, tailX, tailHalfWidth, 0, inset);
            }
            Shape {
                anchors.fill: parent
                transform: Scale { origin.y: bubble.height / 2; yScale: popup.below ? -1 : 1 }
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: button.dark ? Qt.rgba(0.12, 0.12, 0.13, 0.86) : Qt.rgba(0.97, 0.97, 0.98, 0.86)
                    strokeWidth: 1
                    strokeColor: button.dark ? Qt.rgba(0, 0, 0, 0.42) : Qt.rgba(0, 0, 0, 0.14)
                    PathSvg { path: bubble.outline(0.5) }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeWidth: 1
                    strokeColor: button.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.55)
                    PathSvg { path: bubble.outline(1.5) }
                }
            }
            Text {
                id: label
                objectName: "folderTooltipLabel"
                x: bubble.edgePadding
                y: (popup.below ? bubble.tailHeight : 0) + (bubble.bodyHeight - height) / 2
                width: bubble.width - bubble.edgePadding * 2
                text: popup.text
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.PlainText
                color: button.dark ? "#f5f5f7" : "#1d1d1f"
                font.pixelSize: 13
                font.weight: Font.Normal
                font.family: "SF Pro Text"
                horizontalAlignment: Text.AlignHCenter
            }
        }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 120 } }
    }
}
