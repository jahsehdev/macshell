// Dock material for a screen-positioned vertical surface. No self screen capture.
import "Common" as Common
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
Item {
    id: glass
    required property var dock
    required property var monitor
    property var hub: null
    property real screenX: 0
    property real screenY: 0
    property bool live: true
    readonly property var mon: dock.monData.filter(function(m) { return m.name === glass.monitor.name; })[0] || null
    Item {
        id: backdrop
        width: glass.monitor.width; height: glass.monitor.height
        Image {
            anchors.fill: parent
            source: glass.dock.fileUrl(glass.dock.wallpaperFor(glass.monitor.name))
            fillMode: Image.PreserveAspectCrop; asynchronous: true
        }
        ListModel { id: captures }
        Repeater {
            model: captures
            delegate: Item {
                id: windowCapture
                required property string addr
                required property real wx
                required property real wy
                required property real ww
                required property real wh
                required property real wz
                required property bool gone
                x: wx; y: wy; width: ww; height: wh; z: wz
                readonly property var tl: {
                    if (!glass.hub || gone) return null;
                    var tick = glass.hub.tlTick;
                    return glass.hub.tlFor(addr);
                }
                ScreencopyView {
                    anchors.fill: parent
                    captureSource: windowCapture.tl
                    live: glass.live && glass.hub && !glass.hub.glassHold && !windowCapture.gone
                }
            }
        }
        Loader {
            anchors.fill: parent; z: 10000
            active: Common.LaunchpadGlassState.covers(glass.monitor.name)
            sourceComponent: Common.LaunchpadBackground { screenName: glass.monitor.name }
        }
    }
    function syncCaptures() {
        if (!hub || !mon) return;
        var wanted = {}, clients = hub.glassClients;
        for (var i = 0; i < clients.length; i++) {
            var c = clients[i];
            if (!c.mapped || c.hidden || c.monitor !== mon.id || c.workspace.id !== mon.activeWorkspace.id) continue;
            wanted[c.address] = {addr: c.address, wx: c.at[0] - monitor.x, wy: c.at[1] - monitor.y,
                ww: c.size[0], wh: c.size[1], wz: c.floating ? 100 - Math.min(c.focusHistoryID,90) : 0, gone: false};
        }
        for (var j = captures.count - 1; j >= 0; j--) {
            var a = captures.get(j).addr;
            if (wanted[a]) { captures.set(j,wanted[a]); delete wanted[a]; }
            else if (!captures.get(j).gone) { captures.setProperty(j,"gone",true); sweep.restart(); }
        }
        for (var key in wanted) captures.append(wanted[key]);
    }
    Timer {
        id: sweep; interval: 600
        onTriggered: { for (var i = captures.count - 1; i >= 0; i--) if (captures.get(i).gone) captures.remove(i); }
    }
    Connections { target: glass.hub; function onGlassClientsChanged() { glass.syncCaptures(); } }
    onMonChanged: syncCaptures()
    Component.onCompleted: syncCaptures()
    ShaderEffectSource {
        id: texture
        sourceItem: backdrop; hideSource: true; visible: false
        sourceRect: Qt.rect(glass.screenX - 60, glass.screenY - 60, glass.width + 120, glass.height + 120)
        textureSize: Qt.size(Math.ceil(sourceRect.width), Math.ceil(sourceRect.height))
        live: glass.live
    }
    MultiEffect {
        id: blur
        source: texture; width: texture.sourceRect.width; height: texture.sourceRect.height
        visible: false; blurEnabled: true; blurMax: 64
        blur: Math.min(1, glass.dock.materialBlur * 1.4 / 64)
        autoPaddingEnabled: false
    }
    ShaderEffectSource { id: blurred; sourceItem: blur; visible: false; live: glass.live }
    Common.ContinuousRectangle {
        anchors.fill: parent; radius: glass.dock.cornerRadius
        visible: !glass.dock.liquidActive
        color: glass.dock.dockDark ? Qt.rgba(0.1,0.1,0.11,glass.dock.glassOpacity) : Qt.rgba(1,1,1,glass.dock.glassOpacity * 0.55)
        border.color: glass.dock.dockDark ? "#40000000" : "#20000000"
    }
    ShaderEffect {
        anchors.fill: parent; visible: glass.dock.liquidActive
        fragmentShader: glass.dock.glassShaderUrl
        property variant src: blurred
        property vector2d itemSize: Qt.vector2d(width, height)
        property vector2d glassSize: itemSize
        property vector2d srcSize: Qt.vector2d(texture.sourceRect.width, texture.sourceRect.height)
        property vector2d srcOffset: Qt.vector2d(60,60)
        property real pad: 0
        property real radius: glass.dock.cornerRadius
        property real squircle: glass.dock.cornerSquircle
        property real bezel: Math.min(width * 0.36,26)
        property real thickness: 30 * glass.dock.glassLiquid
        property real dispersion: 0.06 * glass.dock.glassLiquid
        property real magnify: 0.08 * glass.dock.glassLiquid
        property real rim: glass.dock.glassRim
        property real grain: glass.dock.glassGrain
        property real blurPx: 1.5
        property real tintMix: glass.dock.glassOpacity * 0.55
        property real saturation: 1.25
        property real dark: glass.dock.dockDark ? 1 : 0
        property real debug: 0
        property real shadowAmt: 0
        property real flatInner: 0
        property real rimTint: 0
        property real ringW: 0
    }
}
