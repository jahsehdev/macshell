pragma ComponentBehavior: Bound
import QtQuick
import "Common" as Common

FocusScope {
    id: tile
    required property var t
    required property string choice
    readonly property string label: ({ default: "Default", dark: "Dark", clear: "Clear", tinted: "Tinted" })[choice]
    readonly property bool selected: Common.IconStyle.mode === choice
    width: 64; height: 82
    activeFocusOnTab: true
    Accessible.role: Accessible.RadioButton
    Accessible.name: label
    Accessible.checked: selected
    Accessible.checkable: true
    Accessible.onPressAction: choose()
    function choose() { Common.IconStyle.setValue("style", choice); }
    Keys.onSpacePressed: choose()
    Keys.onReturnPressed: choose()
    Rectangle {
        x: 3; y: 0; width: 58; height: 58; radius: 16
        color: "transparent"
        border.width: tile.selected || tile.activeFocus ? 3 : 0
        border.color: tile.t.accent
    }
    Common.ContinuousRectangle {
        x: 8; y: 5; width: 48; height: 48; radius: 12; cornerSmoothing: 0.35
        gradient: Gradient {
            GradientStop { position: 0; color: tile.choice === "dark" ? "#36373b" : tile.choice === "clear"
                ? "#888f969c" : tile.choice === "tinted" ? Qt.lighter(Common.IconStyle.tintColor, 1.15) : "#38b5ff" }
            GradientStop { position: 1; color: tile.choice === "dark" ? "#141519" : tile.choice === "clear"
                ? "#556b747e" : tile.choice === "tinted" ? Qt.darker(Common.IconStyle.tintColor, 1.35) : "#0877e8" }
        }
        border.width: tile.choice === "clear" ? 1 : 0
        border.color: "#60ffffff"
        Canvas {
            anchors.fill: parent
            property color ink: tile.choice === "default" ? "#e9f7ff" : "#e4e7e9"
            property color sun: tile.choice === "default" ? "#ffcf55" : tile.choice === "tinted" ? Common.IconStyle.tintForeground : "#c6cbd0"
            onInkChanged: requestPaint()
            onSunChanged: requestPaint()
            onPaint: {
                const c = getContext("2d"); c.reset();
                c.fillStyle = sun; c.beginPath(); c.arc(31,17,9,0,Math.PI*2); c.fill();
                const g = c.createLinearGradient(0,21,0,36); g.addColorStop(0,ink); g.addColorStop(1,"#9ec1d9");
                c.fillStyle = g; c.beginPath(); c.moveTo(12,35);
                c.bezierCurveTo(3,35,3,23,12,22); c.bezierCurveTo(14,12,28,12,31,23);
                c.bezierCurveTo(41,22,43,35,34,35); c.closePath(); c.fill();
            }
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 64; text: tile.label
        color: tile.selected ? tile.t.text : tile.t.text2
        font.family: tile.t.fam; font.pixelSize: 12
        font.weight: tile.selected ? Font.DemiBold : Font.Normal
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { tile.forceActiveFocus(); tile.choose(); } }
}
