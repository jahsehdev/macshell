import QtQuick

Item {
    id: surface
    property bool dark: false
    property bool pressed: false
    property bool hovered: false
    property bool selected: false
    property bool prominent: false
    property bool focusVisible: false
    property color tint: "transparent"
    property real cornerRadius: height / 2
    readonly property color accent: tint.a > 0 ? tint : "#007aff"
    readonly property real wash: selected ? 0.19 : tint.a > 0 ? 0.09 : 0
    readonly property color topColor: prominent
        ? (pressed ? Qt.darker(accent, 1.12) : hovered ? Qt.lighter(accent, 1.16) : Qt.lighter(accent, 1.08))
        : Qt.tint(dark ? (pressed ? "#49494f" : hovered ? "#64646b" : "#56565e")
                       : (pressed ? "#dedee3" : hovered ? "#ffffff" : "#fdfdff"),
                  Qt.rgba(accent.r, accent.g, accent.b, wash))
    readonly property color bottomColor: prominent
        ? (pressed ? Qt.darker(accent, 1.25) : accent)
        : Qt.tint(dark ? (pressed ? "#39393f" : hovered ? "#4d4d54" : "#424249")
                       : (pressed ? "#d2d2d9" : hovered ? "#f2f2f6" : "#eaeaf0"),
                  Qt.rgba(accent.r, accent.g, accent.b, wash))

    // Layered rims stay crisp on both the GPU and the software renderer.
    Rectangle {
        x: 1; y: surface.pressed ? 1 : 2
        width: parent.width - 2; height: parent.height
        radius: surface.cornerRadius
        color: surface.dark ? "#23000000" : "#12000000"
        antialiasing: true
    }
    Rectangle {
        anchors.fill: parent
        radius: surface.cornerRadius
        antialiasing: true
        gradient: Gradient {
            GradientStop {
                position: 0; color: surface.topColor
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            GradientStop {
                position: 1; color: surface.bottomColor
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
        border.width: 1
        border.color: surface.prominent ? "#20000000" : surface.dark ? "#48ffffff" : "#20000000"
        Rectangle {
            anchors.fill: parent; anchors.margins: 1
            radius: Math.max(0, surface.cornerRadius - 1)
            color: "transparent"
            border.width: 1
            border.color: surface.dark || surface.prominent ? "#16ffffff" : "#b3ffffff"
            antialiasing: true
        }
    }
    Rectangle {
        objectName: "keyboardFocusRing"
        anchors.fill: parent; anchors.margins: -3
        radius: surface.cornerRadius + 3
        color: "transparent"
        border.width: 2.5; border.color: "#800a84ff"
        visible: surface.focusVisible
        antialiasing: true
    }
}
