pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: row
    required property var menu
    property string label: ""
    property alias text: input.text
    property alias validator: input.validator
    property alias fieldName: input.objectName
    readonly property bool acceptableInput: input.acceptableInput
    width: parent ? parent.width : 296
    height: 34
    Text {
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 100; text: row.label; color: row.menu.foreground
        font.family: row.menu.host.family; font.pixelSize: 12; font.weight: Font.Medium
    }
    NotchInput {
        id: input
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        width: 84; height: 32; family: row.menu.host.family; dark: row.menu.dark; frosted: true
        horizontalAlignment: TextInput.AlignRight
        Accessible.name: row.label
        onAccepted: if (row.menu.acceptable) row.menu.saveRequested()
    }
}
