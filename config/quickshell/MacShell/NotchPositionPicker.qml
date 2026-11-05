pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "NotchShape.js" as Shape

Item {
    id: picker
    required property var t
    property string mode: "attached"
    property bool reducedMotion: false
    signal picked(string mode)
    implicitHeight: 144

    Row {
        width: parent.width
        spacing: 12
        Repeater {
            model: [
                { mode: "attached", label: "Attached", hint: "Connected to the top edge" },
                { mode: "floating", label: "Floating", hint: "A little space above the notch" }
            ]
            delegate: AbstractButton {
                id: tile
                required property var modelData
                readonly property bool selected: picker.mode === modelData.mode
                objectName: "notchPosition" + modelData.mode
                width: (picker.width - 12) / 2
                height: 132
                padding: 0
                focusPolicy: Qt.StrongFocus
                onClicked: { forceActiveFocus(Qt.MouseFocusReason); picker.picked(modelData.mode); }
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.label + ": " + modelData.hint
                Accessible.checkable: true
                Accessible.checked: selected
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                background: Rectangle {
                    radius: 11
                    color: tile.down || tile.hovered ? picker.t.hover : "transparent"
                    border.width: tile.selected || tile.activeFocus ? 2 : 1
                    border.color: tile.selected || tile.activeFocus ? picker.t.accent : picker.t.buttonBorder
                    Behavior on border.color { enabled: !picker.reducedMotion; ColorAnimation { duration: 150 } }
                }
                contentItem: Item {
                    Item {
                        id: desktop
                        x: 6; y: 6; width: parent.width - 12; height: 90
                        Image {
                            anchors.fill: parent
                            source: Qt.resolvedUrl("assets/settings/appearance-preview.svg")
                            fillMode: Image.Stretch
                        }
                        Rectangle {
                            x: 1; y: 1; width: parent.width - 2; height: 15; radius: 6
                            color: "#CBEDF5F8"
                            Rectangle { y: 7; width: parent.width; height: 8; color: parent.color }
                        }
                        Text {
                            x: 9; y: 3; text: "Finder"
                            color: "#343E48"; font.family: picker.t.fam; font.pixelSize: 8; font.weight: Font.Medium
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 9; y: 3; text: "9:41"
                            color: "#343E48"; font.family: picker.t.fam; font.pixelSize: 8
                        }
                        Item {
                            width: 172; height: tile.modelData.mode === "attached" ? 28 : 32
                            scale: 0.58; transformOrigin: Item.TopLeft
                            x: (desktop.width - width * scale) / 2
                            y: tile.modelData.mode === "attached" ? 0 : 5
                            Canvas {
                                anchors.fill: parent
                                onPaint: {
                                    const c = getContext("2d"); c.reset();
                                    const wash = c.createLinearGradient(0, 0, 0, height);
                                    wash.addColorStop(0, "#050505"); wash.addColorStop(0.55, "#050505");
                                    wash.addColorStop(0.80, "#3B2007"); wash.addColorStop(1, "#967024");
                                    Shape.trace(c, width, height, tile.modelData.mode, 0, false);
                                    c.fillStyle = wash; c.fill();
                                }
                            }
                            Row {
                                anchors.centerIn: parent; spacing: 17
                                Rectangle { width: 8; height: 13; radius: 4; color: "#FBFDFF" }
                                Rectangle { width: 8; height: 13; radius: 4; color: "#FBFDFF" }
                            }
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                            width: 70; height: 13; radius: 4; color: "#70FFFFFF"
                            Row {
                                anchors.centerIn: parent; spacing: 3
                                Repeater {
                                    model: ["#308BEB", "#F2F4F7", "#FFB354", "#57C589", "#818CE4"]
                                    Rectangle {
                                        required property string modelData
                                        width: 8; height: 8; radius: 2; color: modelData
                                    }
                                }
                            }
                        }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 105; spacing: 7
                        Rectangle {
                            width: 14; height: 14; radius: 7
                            color: tile.selected ? picker.t.accent : "transparent"
                            border.width: tile.selected ? 0 : 1
                            border.color: picker.t.text2
                            Rectangle { anchors.centerIn: parent; visible: tile.selected; width: 6; height: 6; radius: 3; color: "white" }
                        }
                        Text {
                            text: tile.modelData.label
                            color: picker.t.text; font.family: picker.t.fam; font.pixelSize: 12
                            font.weight: tile.selected ? Font.Medium : Font.Normal
                        }
                    }
                }
            }
        }
    }
}
