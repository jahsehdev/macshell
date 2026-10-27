pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls

// The preference affects the Dock surface only.
Item {
    id: row
    objectName: "continuousCornerSettingsRow"
    required property var host
    required property var t
    width: parent ? parent.width : 520
    height: Math.max(78, copy.height + 24)

    Rectangle {
        x: 14; width: parent.width - 14; height: 1
        color: row.t.sep
    }
    Column {
        id: copy
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(100, row.width - control.width - 42)
        spacing: 3
        Text {
            width: parent.width
            text: "Dock Continuous Corner"
            color: row.t.text
            font.family: row.t.fam; font.pixelSize: 13
        }
        Text {
            width: parent.width
            text: "Dock corner smoothing · " + Math.round(row.host.cornerSquircle * 100) + "%"
            color: row.t.text2
            font.family: row.t.fam; font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
        Text {
            width: parent.width
            text: "Other UI uses default continuous corners."
            color: row.t.text2
            font.family: row.t.fam; font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }
    Item {
        id: control
        anchors.right: parent.right; anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(230, row.width * 0.46)
        height: 42
        Controls.Slider {
            id: slider
            objectName: "continuousCornerSlider"
            width: parent.width; height: 24
            from: 0; to: 1; stepSize: 0.01
            value: row.host.cornerSquircle
            onMoved: row.host.cornerSquircle = Math.round(value * 100) / 100
            Accessible.name: "Dock continuous corner smoothing"
            leftPadding: 0; rightPadding: 0
            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: slider.availableWidth; height: 4; radius: 2
                color: row.t.track
                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height; radius: 2
                    color: row.t.accent
                }
            }
            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: 20; height: 20; radius: 10
                color: slider.pressed ? "#f0f0f3" : "white"
                border.width: 1
                border.color: slider.activeFocus ? row.t.accent : "#50000000"
            }
        }
        Text {
            y: 27; text: "Rounded"
            color: row.t.text2; font.family: row.t.fam; font.pixelSize: 11
        }
        Text {
            y: 27; anchors.right: parent.right; text: "Squircle"
            color: row.t.text2; font.family: row.t.fam; font.pixelSize: 11
        }
    }
    Component.onCompleted: console.log("[corner-settings] visible control ready", width, height)
}
