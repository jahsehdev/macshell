import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool dark: true
    property string glyph: ""
    property bool selected: false
    property bool prominent: false
    property real cornerRadius: height / 2
    property color tint: "transparent"
    readonly property color ink: prominent ? "#ffffff" : tint.a > 0 ? tint : dark ? "#f5f5f7" : "#26262b"
    implicitHeight: 32
    implicitWidth: text.length ? Math.max(64, contentItem.implicitWidth + 28) : implicitHeight
    padding: 7
    horizontalPadding: text.length ? 14 : 7
    hoverEnabled: true
    font.family: booth.fontFamily
    font.pixelSize: 12
    font.weight: Font.Medium
    scale: down ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
    Accessible.name: text.length ? text : glyph
    background: ButtonSurface {
        dark: control.dark
        pressed: control.down
        hovered: control.hovered
        selected: control.selected
        prominent: control.prominent
        tint: control.tint
        cornerRadius: control.cornerRadius
        focusVisible: control.visualFocus
        opacity: control.enabled ? 1 : 0.4
    }
    contentItem: Item {
        implicitWidth: labelRow.implicitWidth
        implicitHeight: labelRow.implicitHeight
        opacity: control.enabled ? 1 : 0.4
        Row {
            id: labelRow
            anchors.centerIn: parent
            spacing: 6
            Glyph {
                visible: control.glyph.length > 0
                name: control.glyph
                width: 16; height: 16
                anchors.verticalCenter: parent.verticalCenter
                ink: control.ink
            }
            Text {
                visible: control.text.length > 0
                text: control.text
                font: control.font
                anchors.verticalCenter: parent.verticalCenter
                color: control.ink
            }
        }
    }
    DockToolTip {
        objectName: control.objectName + "-tooltip"
        target: control
        dark: control.dark
        visible: control.enabled && control.hovered && !control.down && control.text.length === 0 && !control.selected
        text: control.Accessible.name
    }
}
