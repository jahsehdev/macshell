pragma ComponentBehavior: Bound
import QtQuick

FocusScope {
    id: ruler
    property int value: 25
    property int maximum: 180
    property string family: "sans-serif"
    property color accent: "#FF9F0A"
    readonly property real tickSpacing: 11
    readonly property bool pressed: input.pressed
    signal moved(int minutes)
    implicitHeight: 72
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.name: "Timer duration"
    Accessible.description: value + " minutes. Drag, scroll, or use arrow keys to adjust."
    Accessible.onIncreaseAction: select(value + 1)
    Accessible.onDecreaseAction: select(value - 1)
    function select(minutes) {
        const next = Math.max(1, Math.min(maximum, Math.round(minutes)));
        if (next !== value) moved(next);
    }
    Keys.onLeftPressed: select(value - 1)
    Keys.onRightPressed: select(value + 1)
    Keys.onUpPressed: select(value + 5)
    Keys.onDownPressed: select(value - 5)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) { select(1); event.accepted = true; }
        else if (event.key === Qt.Key_End) { select(maximum); event.accepted = true; }
    }
    Item {
        anchors.fill: parent
        clip: true
        Repeater {
            model: ruler.maximum
            Item {
                id: tick
                required property int index
                readonly property int minutes: index + 1
                readonly property real distance: Math.abs(minutes - ruler.value)
                readonly property bool selected: minutes === ruler.value
                x: ruler.width / 2 + (minutes - ruler.value) * ruler.tickSpacing - width / 2
                width: 48; height: 56
                opacity: selected ? 1 : Math.pow(Math.max(0, 1 - distance / (ruler.width / ruler.tickSpacing / 2)), 0.8)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tick.minutes
                    visible: tick.selected || (tick.minutes % 5 === 0 && tick.distance > 2)
                    color: tick.selected ? "#FFF3DE" : "#A4ACB8"
                    font.family: ruler.family; font.pixelSize: tick.selected ? 18 : 13; font.weight: tick.selected ? Font.DemiBold : Font.Medium
                    font.features: ({"tnum": 1})
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 51 - height; width: tick.selected ? 3 : 2; height: tick.selected ? 28 : tick.minutes % 5 === 0 ? 22 : 12; radius: width / 2
                    color: tick.selected ? ruler.accent : tick.distance <= 2 ? "#BD8F4E" : tick.minutes % 5 === 0 ? "#919AA8" : "#596371"
                }
            }
        }
    }
    Canvas {
        id: pointer
        anchors.horizontalCenter: parent.horizontalCenter
        y: 58; width: 10; height: 6
        onPaint: {
            const c = getContext("2d"); c.reset(); c.fillStyle = ruler.accent;
            c.beginPath(); c.moveTo(5, 0); c.lineTo(10, 6); c.lineTo(0, 6); c.closePath(); c.fill();
        }
        Connections { target: ruler; function onAccentChanged() { pointer.requestPaint(); } }
    }
    MouseArea {
        id: input
        objectName: "notchPomodoroRulerInput"
        anchors.fill: parent
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        preventStealing: true
        property real startX: 0
        property int startValue: 0
        property bool dragged: false
        onPressed: mouse => { startX = mouse.x; startValue = ruler.value; dragged = false; ruler.forceActiveFocus(); }
        onPositionChanged: mouse => {
            if (!pressed) return;
            if (Math.abs(mouse.x - startX) > 4) dragged = true;
            if (dragged) ruler.select(startValue + (startX - mouse.x) / ruler.tickSpacing);
        }
        onClicked: mouse => { if (!dragged) ruler.select(ruler.value + (mouse.x - width / 2) / ruler.tickSpacing); }
        onWheel: wheel => {
            const delta = wheel.angleDelta.y || wheel.angleDelta.x || wheel.pixelDelta.y || wheel.pixelDelta.x;
            if (delta) ruler.select(ruler.value + (delta > 0 ? 1 : -1));
            wheel.accepted = true;
        }
    }
}
