import QtQuick
import QtQuick.Controls

// Shared Settings capsule; matches Launchpad SettingsPanel.ToggleRow.
Item {
    id: sw
    required property var t
    property bool checked: false
    property bool animationsEnabled: true
    property bool reduceMotion: false
    property color tint: t.accent
    property string accessibleLabel: {
        let item = parent;
        while (item) {
            if (typeof item.title === "string" && item.title) return item.title;
            item = item.parent;
        }
        return "Toggle";
    }
    signal toggled(bool value)
    width: 58; height: 27
    opacity: enabled ? 1 : 0.4

    AbstractButton {
        id: switchButton
        objectName: "settingsSwitchButton"
        anchors.fill: parent
        checkable: true
        checked: sw.checked
        focusPolicy: Qt.StrongFocus
        Accessible.name: sw.accessibleLabel
        onToggled: sw.toggled(checked)
        background: ContinuousRectangle {
            cornerSmoothing: 0
            radius: height / 2
            color: switchButton.checked ? sw.tint : (sw.t.dark ? "#444448" : "#c3c3ca")
            Behavior on color { ColorAnimation { duration: sw.animationsEnabled && !sw.reduceMotion ? 140 : 0 } }
            ContinuousRectangle {
                cornerSmoothing: 0
                width: switchButton.down ? 37 : 34; height: 23; radius: height / 2
                x: switchButton.checked ? parent.width - width - 2 : 2; y: 2
                color: switchButton.checked ? "#e0ecff" : "#e2e2e4"
                Behavior on x { NumberAnimation { duration: sw.animationsEnabled && !sw.reduceMotion ? 160 : 0; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: sw.animationsEnabled && !sw.reduceMotion ? 100 : 0 } }
            }
        }
    }
}
