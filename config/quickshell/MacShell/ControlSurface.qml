import QtQuick

Item {
    id: surface
    property bool dark: false
    property bool hovered: false
    property bool pressed: false
    property bool selected: false
    property bool prominent: false
    property bool neutral: false
    property bool focusVisible: false
    property color accent: "#007aff"
    property real radius: height / 2
    readonly property color topColor: neutral
        ? (dark ? (pressed ? "#555559" : hovered ? "#707074" : "#626266")
                : (pressed ? "#929296" : hovered ? "#9c9ca0" : "#aaaaae"))
        : prominent
        ? (pressed ? Qt.darker(accent, 1.12) : hovered ? Qt.lighter(accent, 1.18) : Qt.lighter(accent, 1.08))
        : Qt.tint(dark ? (pressed ? "#3d3f47" : hovered ? "#565963" : "#494c56")
                       : (pressed ? "#e3e5ed" : "#ffffff"),
                  Qt.rgba(accent.r, accent.g, accent.b, selected ? 0.12 : 0))
    readonly property color bottomColor: neutral ? topColor : prominent
        ? (pressed ? Qt.darker(accent, 1.2) : accent)
        : Qt.tint(dark ? (pressed ? "#30323a" : hovered ? "#444751" : "#383b44")
                       : (pressed ? "#d8dbe5" : hovered ? "#f8f9fd" : "#eef0f6"),
                  Qt.rgba(accent.r, accent.g, accent.b, selected ? 0.1 : 0))
    Rectangle {
        visible: !surface.neutral
        x: 1; y: surface.pressed ? 1 : 2
        width: parent.width - 2; height: parent.height
        radius: surface.radius; antialiasing: true
        color: surface.dark ? "#28000000" : "#100e1733"
    }
    Rectangle {
        anchors.fill: parent
        radius: surface.radius; antialiasing: true
        gradient: Gradient {
            GradientStop { position: 0; color: surface.topColor; Behavior on color { ColorAnimation { duration: 130 } } }
            GradientStop { position: 1; color: surface.bottomColor; Behavior on color { ColorAnimation { duration: 130 } } }
        }
        border.width: surface.neutral ? 0 : 1
        border.color: surface.prominent ? "#18000000" : surface.dark ? "#32ffffff" : "#200e1733"
        Rectangle {
            visible: !surface.neutral
            anchors.fill: parent; anchors.margins: 1
            radius: Math.max(0, surface.radius - 1); antialiasing: true
            color: "transparent"; border.width: 1
            border.color: surface.dark || surface.prominent ? "#16ffffff" : "#d0ffffff"
        }
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: -3
        radius: surface.radius + 3; antialiasing: true
        color: "transparent"; border.width: 2.5; border.color: "#800a84ff"
        visible: surface.focusVisible
    }
}
