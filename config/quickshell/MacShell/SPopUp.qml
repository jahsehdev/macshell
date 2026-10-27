pragma ComponentBehavior: Bound
// macOS pop-up button (System Settings style): right-aligned value + grey chevrons; opens a menu ON the button with
// the current item lined up on it, a check mark, accent hover, and a fade/scale animation
import "Common" as Corners
import QtQuick
import QtQuick.Controls

Item {
    id: pu
    required property var t
    property var model: []
    property int current: 0
    property var colorSwatches: []
    property bool allowReselect: false
    property string accessibleLabel: ""
    signal picked(int index)
    width: 220; height: 26
    activeFocusOnTab: true
    Accessible.role: Accessible.ComboBox
    Accessible.name: accessibleLabel || String(model[current] || "")
    Accessible.onPressAction: openMenu()
    Keys.onSpacePressed: openMenu()
    Keys.onReturnPressed: openMenu()
    Keys.onUpPressed: { if (model.length) picked((current + model.length - 1) % model.length); }
    Keys.onDownPressed: { if (model.length) picked((current + 1) % model.length); }
    Corners.ContinuousRectangle {
        anchors.fill: parent; radius: 6
        color: puMa.containsMouse || menu.visible ? pu.t.hover : "transparent"
        border.width: pu.activeFocus ? 1 : 0
        border.color: pu.t.accent
        Behavior on color { ColorAnimation { duration: 160 } }
    }
    Text {
        id: selectedValue
        anchors.right: chev.left; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 30; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
        text: pu.model[pu.current] !== undefined ? pu.model[pu.current] : ""
        color: pu.t.text; font.family: pu.t.fam; font.pixelSize: 13
    }
    Corners.ColorDot {
        visible: pu.colorSwatches.length > 0
        value: pu.colorSwatches[pu.current] || "multicolor"
        width: 16; height: 16
        x: Math.max(2, selectedValue.x + selectedValue.width - Math.min(selectedValue.contentWidth, selectedValue.width) - 23)
        anchors.verticalCenter: parent.verticalCenter
    }
    Canvas {
        id: chev
        anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter
        width: 8; height: 12
        property color ink: pu.t.text2
        onInkChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset();
            c.strokeStyle = ink; c.lineWidth = 1.4; c.lineCap = "round"; c.lineJoin = "round";
            c.beginPath(); c.moveTo(1, 4.2); c.lineTo(4, 1.2); c.lineTo(7, 4.2); c.stroke();
            c.beginPath(); c.moveTo(1, 7.8); c.lineTo(4, 10.8); c.lineTo(7, 7.8); c.stroke();
        }
    }
    function openMenu() { menu.open(); }
    MouseArea { id: puMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: menu.open() }

    Popup {
        id: menu
        readonly property real rowH: 26
        width: Math.max(pu.width, 180)
        x: pu.width - width
        // macOS: the current item sits right on the button; if that would leave the window, the menu shifts to fit,
        // and a menu taller than the window scrolls (no separate popup window: those fought Hyprland's pointer grabs)
        // Qt keeps the popup inside the window (8 px margin): it shifts up and, if still too tall, shrinks — the list scrolls
        margins: 8
        height: pu.model.length * rowH + 2 * padding
        y: -(padding + pu.current * rowH)
        padding: Corners.CornerTheme.menuInset
        modal: false; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 320; easing.type: Easing.OutQuint }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; to: 0.97; duration: 180; easing.type: Easing.OutCubic }
            }
        }
        background: Item {
            Corners.ContinuousRectangle {
                anchors.fill: parent; radius: Corners.CornerTheme.menuRadius
                color: pu.t.dark ? Qt.rgba(0.16, 0.16, 0.18, 0.985) : Qt.rgba(0.98, 0.98, 0.99, 0.99)
                border.width: 1; border.color: pu.t.dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.10)
            }
        }
        contentItem: Flickable {
            clip: true
            contentHeight: menuCol.height
            boundsBehavior: Flickable.StopAtBounds
            Component.onCompleted: contentY = Math.max(0, Math.min(contentHeight - height, (pu.current - 2) * menu.rowH))
        Column {
            id: menuCol
            Repeater {
                model: pu.model
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: menu.width - 2 * menu.padding; height: menu.rowH
                    Corners.MenuHighlight {
                        anchors.fill: parent
                        color: rowMa.containsMouse ? pu.t.accent : "transparent"
                    }
                    Text {
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        text: "\u2713"; visible: row.index === pu.current
                        color: rowMa.containsMouse ? "white" : pu.t.text; font.pixelSize: 12; font.bold: true
                    }
                    Text {
                        x: pu.colorSwatches.length > 0 ? 49 : 26; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 8; elide: Text.ElideRight
                        text: row.modelData
                        color: rowMa.containsMouse ? "white" : pu.t.text; font.family: pu.t.fam; font.pixelSize: 13
                    }
                    Corners.ColorDot {
                        visible: pu.colorSwatches.length > 0
                        value: pu.colorSwatches[row.index] || "multicolor"
                        x: 27; width: 16; height: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    MouseArea {
                        id: rowMa; anchors.fill: parent; hoverEnabled: true
                        onClicked: { menu.close(); if (pu.allowReselect || row.index !== pu.current) pu.picked(row.index); }
                    }
                }
            }
        }
        }
    }
}
