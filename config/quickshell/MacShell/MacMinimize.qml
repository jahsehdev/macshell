// MacMinimize.qml — macOS-style "minimize to the Dock" for MacShell.
//
// Hyprland has no native minimize, so a window is parked on the special:minimized
// workspace while a screenshot ("ghost") flies down to the app's Dock icon.  Clicking
// that icon flies it back and restores the exact workspace, position and size.
//
// Triggers
//   * qs -c MacShell ipc call minimize focused          (hyprbars yellow button, SUPER+M)
//   * qs -c MacShell ipc call minimize addr 0x...        (Dock context menu)
//   * the yellow dot of Firefox's own (WhiteSur) titlebar: an invisible click target is
//     placed over it, because Firefox's own xdg set_minimized request is ignored by
//     Hyprland, so the app-drawn button cannot minimize by itself.

import "Common" as Corners
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: root
    property var hub: null

    // ───────── configuration ─────────
    readonly property string home: Quickshell.env("HOME")
    readonly property string bin: root.home + "/.config/quickshell/MacShell/bin/macmin.py"
    readonly property string cfgDir: root.home + "/.config/macshell"
    readonly property string stateFile: root.cfgDir + "/minimized.json"

    // ───────── state ─────────
    property var records: ({})          // addr(no 0x) -> record   (our minimize bookkeeping)
    property var onSpecial: ({})        // addr(no 0x) -> true     (live: window sits on special:minimized)
    property var hotspots: ({})         // screenName -> [ { x, y, w, h, addr } ]  (invisible click targets)
    property var pendingRestore: ({})   // addr -> { x, y, w, h }  (shown once the restore ghost lands)
    property string pending: ""
    property var prepareQueue: []
    property var preparing: ({})
    function prepareNext() {
        if (prepProc.running || prepDelay.running || prepareQueue.length === 0) return;
        var queue = prepareQueue.slice(); pending = queue.shift(); prepareQueue = queue;
        Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + pending + '" })');
        prepDelay.restart();
    }
    property int ghostSeq: 0
    readonly property int durMin: 560
    readonly property int durRes: 520

    ListModel { id: ghostModel }

    // ───────── geometry helpers ─────────
    function norm(a) { var value = String(a === undefined || a === null ? "" : a).replace(/^0x/, ""); return /^[a-fA-F0-9]+$/.test(value) ? value : ""; }

    function addrOf(tl) {
        var v = Hyprland.toplevels.values;
        for (var i = 0; i < v.length; i++) if (v[i].wayland === tl) return root.norm(v[i].address);
        return "";
    }

    function focusedAddr() {
        var v = Hyprland.toplevels.values;
        for (var i = 0; i < v.length; i++) if (v[i].activated) return root.norm(v[i].address);
        return "";
    }

    function isMinimized(a) {
        a = root.norm(a);
        return a !== "" && (root.records[a] !== undefined || root.onSpecial[a] === true);
    }

    function screenByName(n) {
        var s = Quickshell.screens;
        for (var i = 0; i < s.length; i++) if (s[i].name === n) return s[i];
        return s.length > 0 ? s[0] : null;
    }

    function screenForMon(id) {
        var ms = Hyprland.monitors.values;
        for (var i = 0; i < ms.length; i++) {
            var o = ms[i].lastIpcObject;
            if (o && o.id === id && o.name !== undefined) return root.screenByName(o.name);
        }
        var s = Quickshell.screens;
        return s.length > 0 ? s[0] : null;
    }

    function screenForPoint(x, y) {
        var s = Quickshell.screens;
        for (var i = 0; i < s.length; i++)
            if (x >= s[i].x && x < s[i].x + s[i].width && y >= s[i].y && y < s[i].y + s[i].height) return s[i];
        return s.length > 0 ? s[0] : null;
    }

    function currentWorkspaceId(rect) {
        var mx = rect.x + rect.w / 2, my = rect.y + rect.h / 2;
        var ms = Hyprland.monitors.values;
        for (var i = 0; i < ms.length; i++) {
            var o = ms[i].lastIpcObject;
            if (!o || !o.activeWorkspace) continue;
            if (mx >= o.x && mx < o.x + o.width && my >= o.y && my < o.y + o.height) return o.activeWorkspace.id;
        }
        return 1;
    }

    function defaultRect(monId) {
        var scr = root.screenForMon(monId);
        if (!scr) return { x: 80, y: 80, w: 900, h: 600 };
        var w = Math.min(1040, Math.round(scr.width * 0.72));
        var h = Math.min(660, Math.round(scr.height * 0.72));
        return { x: Math.round(scr.x + (scr.width - w) / 2), y: Math.round(scr.y + (scr.height - h) / 2), w: w, h: h };
    }

    function clampRect(rect, monId) {
        var scr = root.screenForMon(monId);
        if (!scr) return rect;
        var w = Math.min(rect.w, scr.width);
        var h = Math.min(rect.h, scr.height);
        var x = Math.max(scr.x, Math.min(rect.x, scr.x + scr.width - 48));
        var y = Math.max(scr.y, Math.min(rect.y, scr.y + scr.height - 48));
        return { x: x, y: y, w: w, h: h };
    }

    // ───────── Dock geometry ─────────
    function dockKey(appId) {
        var d = root.hub ? root.hub.dock : null;
        if (d && typeof d.keyOf === "function") { try { return d.keyOf(appId); } catch (e) { } }
        return String(appId || "").toLowerCase();
    }

    // global screen coordinates of the Dock cell for an app key
    function dockTarget(key, monId, addr) {
        var d = root.hub ? root.hub.dock : null;
        var scr = root.screenForMon(monId);
        if (!d || !scr || !d.dockEnabled) return null;
        if (d.monitor) scr = root.screenByName(d.monitor) || scr;
        if (!Corners.DesktopPreferences.settings.minimizeIntoApp && addr && d.itemMap["win:" + addr]) key = "win:" + addr;
        var iconSize = d.iconSize, spacing = d.spacing, sepW = d.sepWidth;
        var it = d.itemMap ? d.itemMap[key] : null;
        var c0;
        if (it) {
            var isSep = it.kind === "sep";
            c0 = (it.nA || 0) * (iconSize + spacing) + (it.nS || 0) * (sepW + spacing) + (isSep ? sepW : iconSize) / 2;
        } else {
            c0 = d.totalW0 / 2;
        }
        if (d.position !== "bottom") {
            var fit = Math.min(1, (scr.height - 96) / Math.max(1, d.totalW0 + d.hPad * 2));
            var base = iconSize * fit;
            return {x: scr.x + (d.position === "left" ? d.margin + d.hPad + base / 2 : scr.width - d.margin - d.hPad - base / 2),
                y: scr.y + (scr.height - d.totalW0 * fit) / 2 + c0 * fit, size: base, screen: scr.name};
        }
        var refLeft = (scr.width - d.totalW0) / 2;
        return { x: scr.x + refLeft + c0,
                 y: scr.y + scr.height - d.margin - d.bottomPad - iconSize / 2,
                 size: iconSize, screen: scr.name };
    }

    // ───────── ghosts ─────────
    function addGhost(g) {
        g.gid = ++root.ghostSeq;
        ghostModel.append(g);
    }

    function removeGhost(gid) {
        for (var i = 0; i < ghostModel.count; i++) {
            if (ghostModel.get(i).gid === gid) { ghostModel.remove(i); return; }
        }
    }

    // ───────── minimize ─────────
    function minimizeFocused() { var a = root.focusedAddr(); if (a !== "") root.minimize(a); }

    function minimize(a) {
        a = root.norm(a);
        if (a === "" || root.records[a] !== undefined) return;
        if (root.onSpecial[a] === true || root.preparing[a]) return;
        var inFlight = Object.assign({}, preparing); inFlight[a] = true; preparing = inFlight;
        prepareQueue = prepareQueue.concat([a]); prepareNext();
    }

    Timer { id: prepDelay; interval: 90; onTriggered: { var a = root.pending; root.pending = ""; if (a !== "") { prepProc.addr = a; prepProc.running = true; } } }

    Process {
        id: prepProc
        property string addr: ""
        command: addr === "" ? [] : ["python3", root.bin, "prep", addr]
        onExited: {
            var next = Object.assign({}, root.preparing); delete next[addr]; root.preparing = next;
            Qt.callLater(root.prepareNext);
        }
        stdout: StdioCollector {
            onStreamFinished: {
                var o = null;
                try { o = JSON.parse(text); } catch (e) { o = null; }
                if (o && o.ok) root.onPrepared(o);
            }
        }
    }

    function onPrepared(o) {
        var a = root.norm(o.addr);
        var rec = { addr: a, appId: o.appId, title: o.title, ws: o.ws, wsName: o.wsName,
                    mon: o.mon, pid: o.pid, fullscreen: o.fullscreen || 0, at: o.at, size: o.size, floating: o.floating, shot: o.shot, born: Date.now() };
        var m = {};
        for (var k in root.records) m[k] = root.records[k];
        m[a] = rec;
        root.records = m;
        root.saveState();

        var key = root.dockKey(o.appId);
        var t = root.dockTarget(key, o.mon, a);
        var scr = root.screenForMon(o.mon) || root.screenForPoint(o.at[0], o.at[1]);
        if (t && scr && t.screen === scr.name && o.shot !== "") {
            root.addGhost({ gmode: "minimize", gaddr: a, gsrc: o.shot, gscreen: scr.name,
                wx: o.at[0] - scr.x, wy: o.at[1] - scr.y, ww: o.size[0], wh: o.size[1],
                icx: t.x - scr.x, icy: t.y - scr.y, icsz: t.size, geffect: Corners.DesktopPreferences.settings.minimizeEffect,
                gdirection: Corners.DesktopPreferences.settings.position });
        }
        root.hideWindow(a);
    }

    function hideWindow(a) {
        Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:0x' + a + '" })');
    }

    // ───────── restore ─────────
    function restoreFocused() {
        var a = root.focusedAddr();
        if (a !== "" && root.isMinimized(a)) root.restore(a);
    }

    function toggleFocused() {
        var a = root.focusedAddr();
        if (a === "") return;
        if (root.isMinimized(a)) root.restore(a); else root.minimize(a);
    }

    function restore(a) {
        a = root.norm(a);
        if (a === "" || root.pendingRestore[a]) return;
        var r = root.records[a];
        var mon = r ? r.mon : null;
        var rect = (r && r.at && r.size) ? { x: r.at[0], y: r.at[1], w: r.size[0], h: r.size[1] }
                                        : root.defaultRect(mon);
        rect = root.clampRect(rect, mon);

        var scr = root.screenForMon(mon) || root.screenForPoint(rect.x, rect.y);
        var t = root.dockTarget(r ? root.dockKey(r.appId) : "", mon, a);
        if (t && scr && t.screen === scr.name && r && r.shot && r.shot !== "") {
            root.addGhost({ gmode: "restore", gaddr: a, gsrc: r.shot, gscreen: scr.name,
                wx: rect.x - scr.x, wy: rect.y - scr.y, ww: rect.w, wh: rect.h,
                icx: t.x - scr.x, icy: t.y - scr.y, icsz: t.size, geffect: Corners.DesktopPreferences.settings.minimizeEffect,
                gdirection: Corners.DesktopPreferences.settings.position });
            root.pendingRestore[a] = rect;
        } else {
            root.doRestore(a, rect);
        }
    }

    function finishRestore(a) {
        a = root.norm(a);
        var rect = root.pendingRestore[a];
        delete root.pendingRestore[a];
        if (rect) root.doRestore(a, rect);
    }

    function doRestore(a, rect) {
        var r = root.records[a];
        var sel = 'window = "address:0x' + a + '"';
        var wsSel;
        if (r && r.wsName && String(r.wsName).indexOf("special:") === 0) wsSel = '"' + r.wsName + '"';
        else if (r && r.ws !== undefined && Number(r.ws) >= 0) wsSel = Number(r.ws);
        else wsSel = root.currentWorkspaceId(rect);
        Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + wsSel + ', follow = false, ' + sel + ' })');
        if (!r || r.floating !== false) {
            Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel + ' })');
            Hyprland.dispatch('hl.dsp.window.resize({ x = ' + Math.round(rect.w) + ', y = ' + Math.round(rect.h) + ', exact = true, ' + sel + ' })');
            Hyprland.dispatch('hl.dsp.window.move({ x = ' + Math.round(rect.x) + ', y = ' + Math.round(rect.y) + ', exact = true, ' + sel + ' })');
        } else Hyprland.dispatch('hl.dsp.window.float({action="disable", ' + sel + '})');
        if (r && r.fullscreen) Hyprland.dispatch('hl.dsp.window.fullscreen({mode="' + (r.fullscreen === 2 ? "fullscreen" : "maximized") + '", action="enable", ' + sel + '})');
        if (root.hub && root.hub.desktopController) root.hub.desktopController.activate(a);
        Hyprland.dispatch('hl.dsp.focus({ ' + sel + ' })');

        var m = {};
        for (var k in root.records) if (k !== a) m[k] = root.records[k];
        root.records = m;
        root.saveState();
        hotspotsSoon.restart();
    }

    // ───────── persistence ─────────
    FileView {
        id: stateStore
        path: root.stateFile
        printErrors: false
        onLoaded: {
            try {
                var o = JSON.parse(text());
                if (o && typeof o === "object") root.records = o;
            } catch (e) { }
        }
    }

    function saveState() {
        stateStore.setText(JSON.stringify(root.records));
    }

    // ───────── live window geometry (Dock hotspots) ─────────
    Process {
        id: clientsProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector { onStreamFinished: root.applyClients(text) }
    }

    Timer {
        id: pollTimer
        interval: 350
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: if (!clientsProc.running) clientsProc.running = true
    }

    Timer { id: hotspotsSoon; interval: 60; onTriggered: if (!clientsProc.running) clientsProc.running = true }

    function applyClients(txt) {
        var cs;
        try { cs = JSON.parse(txt); } catch (e) { return; }
        var os = {}, hs = {};
        for (var i = 0; i < cs.length; i++) {
            var c = cs[i];
            var ws = c.workspace || {};
            if (ws.name === "special:minimized") os[root.norm(c.address)] = true;

            // Firefox draws its own traffic lights: put an invisible click target exactly on
            // its (focused) yellow dot, so it minimizes like the other windows.
            var cls = String(c.class || "").toLowerCase();
            if (cls === "firefox" && c.focusHistoryID === 0 && c.mapped && !c.hidden && c.fullscreen === 0) {
                var scr = root.screenForMon(c.monitor) || root.screenForPoint(c.at[0], c.at[1]);
                if (scr) {
                    var arr = hs[scr.name] || (hs[scr.name] = []);
                    // measured: the middle (yellow) dot is centred at (+48, +24) from the window's top-left
                    arr.push({ x: c.at[0] + 36 - scr.x, y: c.at[1] + 12 - scr.y, w: 24, h: 24, addr: root.norm(c.address) });
                }
            }
        }
        var live = {}, kept = {}, changed = false;
        for (var j = 0; j < cs.length; j++) live[root.norm(cs[j].address)] = cs[j];
        for (var addr in root.records) {
            var record = root.records[addr], current = live[addr];
            var parked = current && current.workspace && current.workspace.name === "special:minimized";
            var inTransit = root.pendingRestore[addr] || Date.now() - (record.born || 0) < 1500;
            if (current && (!record.pid || record.pid === current.pid) && (parked || inTransit)) kept[addr] = record;
            else changed = true;
        }
        if (changed) { root.records = kept; root.saveState(); }
        root.onSpecial = os;
        root.hotspots = hs;
    }

    // ───────── cleanup: minimized windows that get closed ─────────
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "closewindow") return;
            var a = root.norm(String(event.data).split(",")[0]);
            if (root.records[a] !== undefined) {
                Quickshell.execDetached(["python3", root.bin, "cleanup", a]);
                var m = {};
                for (var k in root.records) if (k !== a) m[k] = root.records[k];
                root.records = m;
                root.saveState();
            }
            delete root.pendingRestore[a];
        }
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root.cfgDir]);
        if (root.hub && root.hub.dock) root.hub.dock.minimize = root;
    }

    // ───────── UI: one full-screen click-through overlay per monitor ─────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: animWin
            required property var modelData
            screen: modelData
            visible: true
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            // empty input region: the ghost is drawn on top but every click passes
            // through to the window underneath
            mask: Region {}

            WlrLayershell.namespace: "macshell-anim"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Repeater {
                model: ghostModel

                delegate: Item {
                    id: gh
                    required property int gid
                    required property string gmode
                    required property string gaddr
                    required property string gsrc
                    required property string gscreen
                    required property real wx
                    required property real wy
                    required property real ww
                    required property real wh
                    required property real icx
                    required property real icy
                    required property real icsz
                    required property string geffect
                    required property string gdirection

                    readonly property real pad: 24

                    visible: gscreen === animWin.modelData.name
                    x: Math.min(wx, icx - icsz / 2) - pad
                    y: Math.min(wy, icy - icsz / 2) - pad
                    width: Math.max(wx + ww, icx + icsz / 2) - x + pad
                    height: Math.max(wy + wh, icy + icsz / 2) - y + pad

                    // the screenshot the genie warps
                    Image {
                        id: srcImg
                        x: gh.wx - gh.x
                        y: gh.wy - gh.y
                        width: gh.ww
                        height: gh.wh
                        source: gh.gsrc !== "" ? ("file://" + gh.gsrc) : ""
                        fillMode: Image.Stretch
                        smooth: true
                        asynchronous: true
                        cache: false
                    }

                    ShaderEffectSource {
                        id: srcTex
                        sourceItem: gh.gsrc !== "" ? srcImg : null
                        hideSource: true
                        live: true
                        recursive: false
                    }

                    ShaderEffect {
                        id: fx
                        anchors.fill: parent
                        fragmentShader: Qt.resolvedUrl("window-transition.frag.qsb")
                        property variant src: srcTex
                        property vector2d itemSize: Qt.vector2d(width, height)
                        property vector4d win: Qt.vector4d(gh.wx - gh.x, gh.wy - gh.y, gh.wx - gh.x + gh.ww, gh.wy - gh.y + gh.wh)
                        property vector4d icon: Qt.vector4d(gh.icx - gh.x - gh.icsz / 2, gh.icy - gh.y - gh.icsz / 2,
                                                            gh.icx - gh.x + gh.icsz / 2, gh.icy - gh.y + gh.icsz / 2)
                        property real progress: 0
                        property real effect: gh.geffect === "scale" ? 1 : 0
                        property real direction: gh.gdirection === "left" ? 1 : gh.gdirection === "right" ? 2 : 0
                        onStatusChanged: if (status === ShaderEffect.Error) console.log("[macmin] genie shader error:", log)
                    }

                    NumberAnimation {
                        id: anim
                        target: fx
                        property: "progress"
                        from: gh.gmode === "minimize" ? 0.0 : 1.0
                        to: gh.gmode === "minimize" ? 1.0 : 0.0
                        duration: gh.geffect === "scale" ? 260 : gh.gmode === "minimize" ? root.durMin : root.durRes
                        easing.type: Easing.InOutQuad
                        onFinished: {
                            if (gh.gscreen !== animWin.modelData.name) return;
                            if (gh.gmode === "minimize") root.removeGhost(gh.gid);
                            else { root.finishRestore(gh.gaddr); landTimer.start(); }
                        }
                    }

                    Timer {
                        id: landTimer
                        interval: 60
                        onTriggered: root.removeGhost(gh.gid)
                    }

                    Component.onCompleted: if (gscreen === animWin.modelData.name) anim.start();
                }
            }
        }
    }

    // ───────── UI: tiny input-only surface over Firefox's yellow dot ─────────
    // Hyprland ignores xdg_toplevel.set_minimized, and Firefox paints its own CSD
    // dots, so we place an invisible click target exactly on the minimize dot of
    // the focused Firefox window. It exists only while that window is focused.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: hotWin
            required property var modelData
            readonly property var hs: root.hotspots[modelData.name] || []
            readonly property var h: hs.length > 0 ? hs[0] : null

            screen: modelData
            visible: h !== null
            anchors { left: true; top: true }
            margins { left: h ? Math.round(h.x) : 0; top: h ? Math.round(h.y) : 0 }
            implicitWidth: h ? h.w : 1
            implicitHeight: h ? h.h : 1
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "macshell-hotspot"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            MouseArea {
                id: hotArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                onClicked: if (hotWin.h) root.minimize(hotWin.h.addr)

                // Firefox would draw its own hover glyph (the WhiteSur theme swaps the
                // button background for titlebutton-minimize-hover.svg), but this surface
                // takes the pointer events, so we draw the identical glyph ourselves:
                // an 8x2 black bar at 50% over the yellow dot.
                Corners.ContinuousRectangle {
                    anchors.centerIn: parent
                    width: 8
                    height: 2
                    radius: 1
                    color: Qt.rgba(0, 0, 0, 0.5)
                    visible: hotArea.containsMouse
                }
            }
        }
    }
}
