pragma ComponentBehavior: Bound
import QtQuick
import "Common" as Common

Row {
    id: picker
    required property var t
    spacing: 6
    Repeater {
        model: Common.ThemeColors.colorChoices
        delegate: FocusScope {
            id: swatch
            required property var modelData
            readonly property bool selected: modelData.id === "multicolor" ? Common.ThemeColors.multicolor
                : !Common.ThemeColors.multicolor && Common.ThemeColors.settings.accent === modelData.c
            width: 32; height: 50
            activeFocusOnTab: true
            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData.name
            Accessible.checkable: true
            Accessible.checked: selected
            Accessible.onPressAction: choose()
            function choose() {
                Common.ThemeColors.setAccent(modelData.id === "multicolor" ? "multicolor" : "single", modelData.c);
            }
            Keys.onSpacePressed: choose()
            Keys.onReturnPressed: choose()
            Common.ColorDot { x: 4; y: 4; value: swatch.modelData.c }
            Rectangle {
                width: 32; height: 32; radius: 16
                color: "transparent"
                visible: swatch.selected || swatch.activeFocus
                border.width: 2
                border.color: swatch.modelData.id === "multicolor" ? picker.t.accent : swatch.modelData.c
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 36
                visible: swatch.selected
                text: swatch.modelData.name
                color: picker.t.text2
                font.family: picker.t.fam
                font.pixelSize: 10
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { swatch.forceActiveFocus(); swatch.choose(); }
            }
        }
    }
}
