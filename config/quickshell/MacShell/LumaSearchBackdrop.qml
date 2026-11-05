pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "LumaSearchBackdrop.js" as Layout

Item {
    id: scene
    required property var monitor
    property var hub: null
    property url wallpaper: ""
    property rect region: Qt.rect(0, 0, 0, 0)
    readonly property var mon: hub ? hub.monData.filter(m => m.name === monitor.name)[0] || null : null
    width: monitor.width; height: monitor.height
    opacity: 0 // only rendered into the glass texture, never over the real windows
    Rectangle { z: -2002; anchors.fill: parent; color: "#49443d" }
    Image { z: -2001; anchors.fill: parent; source: scene.wallpaper; fillMode: Image.PreserveAspectCrop; asynchronous: true }
    ListModel { id: captures }
    Repeater {
        model: captures
        delegate: Item {
            id: window
            required property string addr
            required property real wx
            required property real wy
            required property real ww
            required property real wh
            required property real wz
            required property bool gone
            visible: !gone // A detached screencopy can retain its last texture until swept.
            x: wx; y: wy; width: ww; height: wh; z: wz
            readonly property var handle: {
                if (!scene.hub || gone) return null;
                const tick = scene.hub.tlTick;
                return scene.hub.tlFor(addr);
            }
            ScreencopyView {
                id: capture
                anchors.fill: parent
                captureSource: window.handle
                live: scene.visible && !window.gone && scene.hub && !scene.hub.glassHold && !scene.hub.captureQuiet
                onCaptureSourceChanged: firstFrame.restart()
                Timer {
                    id: firstFrame; interval: 90
                    onTriggered: if (capture.captureSource && !capture.live && scene.hub && !scene.hub.glassHold) capture.captureFrame()
                }
                Timer {
                    interval: 1500; repeat: true
                    running: scene.visible && capture.captureSource !== null && !capture.live && scene.hub && !scene.hub.glassHold
                    onTriggered: capture.captureFrame()
                }
            }
        }
    }
    function sync() {
        const wanted = {};
        const windows = Layout.windowsForRegion(hub ? hub.glassClients : [], mon, region);
        for (const window of windows) wanted[window.addr] = window;
        for (let i = captures.count - 1; i >= 0; i--) {
            const address = captures.get(i).addr;
            if (wanted[address]) { captures.set(i, wanted[address]); delete wanted[address]; }
            else if (!captures.get(i).gone) { captures.setProperty(i, "gone", true); sweep.restart(); }
        }
        for (const address in wanted) captures.append(wanted[address]);
    }
    Timer {
        id: sweep; interval: 600
        onTriggered: { for (let i = captures.count - 1; i >= 0; i--) if (captures.get(i).gone) captures.remove(i); }
    }
    Connections { target: scene.hub; function onGlassClientsChanged() { scene.sync(); } }
    onMonChanged: sync()
    onRegionChanged: sync()
    Component.onCompleted: sync()
}
