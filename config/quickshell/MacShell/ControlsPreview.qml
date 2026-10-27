import QtQuick

// A small, illustrative desktop; it never reads or changes real controls.
Rectangle {
    id: preview
    property bool dark: false
    radius: 9
    clip: true
    antialiasing: true
    gradient: Gradient {
        GradientStop { position: 0; color: preview.dark ? "#365e8c" : "#8fc7ea" }
        GradientStop { position: 0.5; color: preview.dark ? "#655686" : "#b6aad9" }
        GradientStop { position: 1; color: preview.dark ? "#824c79" : "#b77aaf" }
    }
    border.width: 1; border.color: "#30ffffff"
    Accessible.role: Accessible.Graphic
    Accessible.name: "Preview of arranging controls on a desktop"

    Rectangle {
        width: parent.width; height: 9
        color: "#48ffffff"
        Row {
            x: 5; anchors.verticalCenter: parent.verticalCenter; spacing: 3
            Repeater { model: 3; Rectangle { width: 8; height: 2; radius: 1; color: "#a0ffffff" } }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 5; anchors.verticalCenter: parent.verticalCenter; spacing: 3
            Repeater { model: 3; Rectangle { width: 3; height: 3; radius: 1.5; color: "#c0ffffff" } }
        }
    }
    Rectangle {
        id: miniGallery
        x: 8; y: 24; width: preview.width * 0.55; height: preview.height - 36
        radius: 5; color: "#45ffffff"
        border.width: 0.5; border.color: "#60ffffff"
        Rectangle { x: 4; y: 5; width: parent.width * 0.45; height: 3; radius: 1.5; color: "#b0ffffff" }
        Grid {
            x: 5; y: 15; columns: 3; spacing: 4
            Repeater {
                model: ["sun", "speaker", "moon", "wifi", "timer", "desktop"]
                Rectangle {
                    required property string modelData
                    width: (miniGallery.width - 18) / 3; height: width; radius: width / 2
                    color: "#60ffffff"
                    ControlIcon { anchors.centerIn: parent; width: parent.width * 0.6; height: width; kind: modelData; color: "#e8ffffff" }
                }
            }
        }
    }
    Rectangle {
        id: miniCenter
        x: preview.width * 0.65; y: 16
        width: preview.width * 0.29; height: preview.height - 29
        radius: 6; color: "#40ffffff"
        border.width: 0.5; border.color: "#60ffffff"
        Column {
            x: 4; y: 5; width: parent.width - 8; spacing: 4
            Rectangle {
                width: parent.width; height: 17; radius: 8.5; color: "#60ffffff"
                ControlIcon { x: 5; anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; kind: "wifi"; color: "white" }
            }
            Rectangle {
                width: parent.width; height: 17; radius: 8.5; color: "#60ffffff"
                ControlIcon { x: 5; anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; kind: "bluetooth"; color: "white" }
            }
            Rectangle { width: parent.width; height: 6; radius: 3; color: "#a0ffffff" }
            Rectangle { width: parent.width; height: 6; radius: 3; color: "#70ffffff" }
        }
    }
    Rectangle {
        anchors.bottom: parent.bottom; anchors.bottomMargin: 4; anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.46; height: 8; radius: 4; color: "#50ffffff"
        Row {
            anchors.centerIn: parent; spacing: 3
            Repeater { model: 5; Rectangle { width: 4; height: 4; radius: 1; color: "#b0ffffff" } }
        }
    }
}
