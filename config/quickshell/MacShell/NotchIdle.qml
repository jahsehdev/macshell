pragma ComponentBehavior: Bound
import QtQuick
import "NotchShape.js" as Shape

Item {
    id: idle
    required property var host
    readonly property bool running: host.available && host.idleEyesEnabled && host.activity === "idle" && !host.expanded
    readonly property bool reducedMotion: host.reducedMotion
    property real idleSeconds: 0
    property real idleSince: Date.now()
    property real eyeOpen: 1
    property real gazeX: 0
    property real gazeY: 0
    readonly property string mood: idleSeconds >= 120 ? "sleepy" : idleSeconds >= 45 ? "bored" : "curious"
    readonly property real eyeHeight: mood === "sleepy" ? 3 : mood === "bored" ? 7 : 13
    readonly property real eyeWidth: mood === "sleepy" ? 10 : 8
    readonly property real eyeScale: Math.min(1.15, Math.max(0.7, (host.bar ? host.bar.barHeight : 28) / 28))

    objectName: "notchIdle"
    opacity: running ? 1 : 0
    visible: opacity > 0.001
    Behavior on opacity { enabled: !idle.reducedMotion; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    onRunningChanged: {
        resetPose();
        if (running) wake();
    }
    onReducedMotionChanged: if (reducedMotion) resetPose();
    function resetPose() {
        // Bypass the behaviors while resetting, even when their enabled
        // bindings have not caught up with an accessibility change yet.
        gazeXBehavior.enabled = false; gazeYBehavior.enabled = false;
        blink.stop();
        eyeOpen = 1; gazeX = 0; gazeY = 0;
        gazeXBehavior.enabled = Qt.binding(() => idle.running && !idle.reducedMotion);
        gazeYBehavior.enabled = Qt.binding(() => idle.running && !idle.reducedMotion);
    }
    function wake() { idleSince = Date.now(); idleSeconds = 0; }
    function glance(direction, vertical) { gazeX = Math.max(-5, Math.min(5, direction)); gazeY = Math.max(-2, Math.min(2, vertical)); }
    Behavior on gazeX { id: gazeXBehavior; enabled: idle.running && !idle.reducedMotion; NumberAnimation { duration: 360; easing.type: Easing.InOutSine } }
    Behavior on gazeY { id: gazeYBehavior; enabled: idle.running && !idle.reducedMotion; NumberAnimation { duration: 320; easing.type: Easing.InOutSine } }
    Timer {
        interval: 1000; repeat: true; running: idle.running
        onTriggered: idle.idleSeconds = Math.max(0, (Date.now() - idle.idleSince) / 1000)
    }
    Timer {
        id: blinkSoon
        interval: 3200; repeat: true; running: idle.running && !idle.reducedMotion
        onTriggered: {
            blink.restart();
            interval = idle.mood === "sleepy" ? 6200 : 2800 + Math.random() * 4200;
        }
    }
    SequentialAnimation {
        id: blink
        NumberAnimation { target: idle; property: "eyeOpen"; to: 0.08; duration: 85; easing.type: Easing.InSine }
        PauseAnimation { duration: idle.mood === "sleepy" ? 420 : 45 }
        NumberAnimation { target: idle; property: "eyeOpen"; to: 1; duration: idle.mood === "sleepy" ? 430 : 150; easing.type: Easing.OutSine }
    }
    Timer {
        interval: 4400; repeat: true; running: idle.running && !idle.reducedMotion
        onTriggered: {
            const direction = Math.random();
            idle.glance(idle.mood === "sleepy" ? 0 : direction < 0.33 ? -4 : direction > 0.66 ? 4 : 0,
                idle.mood === "curious" ? (Math.random() - 0.5) * 2 : 1);
            interval = idle.mood === "sleepy" ? 11000 : 3000 + Math.random() * 4000;
        }
    }

    Canvas {
        id: glow
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: idle.host
            function onModeChanged() { glow.requestPaint(); }
            function onShapeProgressChanged() { glow.requestPaint(); }
        }
        onPaint: {
            const c = getContext("2d"); c.reset();
            const wash = c.createLinearGradient(0, 0, 0, height);
            wash.addColorStop(0, Qt.rgba(0, 0, 0, 0)); wash.addColorStop(0.30, Qt.rgba(0, 0, 0, 0));
            wash.addColorStop(0.76, Qt.rgba(0.95, 0.35, 0.04, 0.22)); wash.addColorStop(1, Qt.rgba(1, 0.72, 0.14, 0.58));
            Shape.trace(c, width, height, idle.host.mode, idle.host.shapeMix, false, idle.host.cornerScale);
            c.fillStyle = wash; c.fill();
        }
    }
    Item {
        id: eyes
        anchors.centerIn: parent
        width: 36; height: 20
        scale: idle.eyeScale
        transform: Translate { x: idle.gazeX; y: idle.gazeY }
        Repeater {
            model: 2
            Item {
                id: eye
                required property int index
                x: index * 25; width: 11; height: 20
                Rectangle {
                    anchors.centerIn: parent
                    width: idle.eyeWidth + 5; height: Math.max(2, pupil.height + 5)
                    radius: width / 2; color: "#20C9E5FF"
                }
                Rectangle {
                    id: pupil
                    objectName: "notchIdleEye" + eye.index
                    anchors.centerIn: parent
                    width: idle.eyeWidth; height: Math.max(1.4, idle.eyeHeight * idle.eyeOpen)
                    radius: Math.min(width / 2, height / 2)
                    color: "#FBFDFF"
                    rotation: idle.mood === "bored" ? (eye.index === 0 ? 8 : -8) : 0
                    Behavior on width { enabled: !idle.reducedMotion; NumberAnimation { duration: 650; easing.type: Easing.InOutSine } }
                    Behavior on height { enabled: !idle.reducedMotion && !blink.running; NumberAnimation { duration: 650; easing.type: Easing.InOutSine } }
                    Behavior on rotation { enabled: !idle.reducedMotion; NumberAnimation { duration: 650; easing.type: Easing.InOutSine } }
                }
            }
        }
    }
}
