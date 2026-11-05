// MacMinimize.qml — macOS-style "minimize to the Dock" for MacShell.
//
// Hyprland has no native minimize, so a window is parked on the special:minimized
// workspace while a captured frame flies down to the app's Dock icon. Clicking
// that icon reverses the animation and restores its workspace, position and size.
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
    readonly property string shotDir: (Quickshell.env("XDG_CACHE_HOME") || root.home + "/.cache") + "/macshell/minimize"

    // ───────── state ─────────
    property var records: ({})          // addr(no 0x) -> record   (our minimize bookkeeping)
    property var onSpecial: ({})        // addr(no 0x) -> true     (live: window sits on special:minimized)
    property var hotspots: ({})         // screenName -> [ { x, y, w, h, addr } ]  (invisible click targets)
    property var pendingRestore: ({})   // addr -> { x, y, w, h }  (shown once the restore ghost lands)
    property var restoreDeadlines: ({})
    property var prepareQueue: []
    property var preparing: ({})
    property var canceledPreparations: ({})
    // Toplevel export stops in this compositor session (also observed by Dock
    // previews). Use the reliable screen snapshot path by default; it starts
    // immediately with cached geometry and no focus/preparation timer.
    property bool nativeCaptureAvailable: false
    property var screenshotQueue: []
    function prepareNext() {
        if (prepProc.running || prepareQueue.length === 0) return;
        var queue = prepareQueue.slice(); prepProc.addr = queue.shift(); prepareQueue = queue;
        prepProc.running = true;
    }
    property int ghostSeq: 0
    readonly property int durMin: 560
    readonly property int durRes: 520

    function trace(stage, detail) { console.log("[macmin-trace]", stage, JSON.stringify(detail || {})); }

    ListModel { id: ghostModel }

    // ───────── geometry helpers ─────────
    function norm(a) { var value = String(a === undefined || a === null ? "" : a).replace(/^0x/, ""); return /^[a-fA-F0-9]+$/.test(value) ? value : ""; }

    function addrOf(tl) {
        var v = Hyprland.toplevels.values;
        for (var i = 0; i < v.length; i++) if (v[i].wayland === tl) return root.norm(v[i].address);
        return "";
    }

    function toplevelFor(a) {
        var values = Hyprland.toplevels.values;
        for (var i = 0; i < values.length; i++)
            if (root.norm(values[i].address) === a) return values[i].wayland;
        return null;
    }

    // Window metadata is already maintained by Quickshell's IPC connection.
    // No metadata subprocess, focus change or preparation timer is needed.
    function prepareDirect(a) {
        var values = Hyprland.toplevels.values;
        for (var i = 0; i < values.length; i++) {
            var tl = values[i], c = tl.lastIpcObject;
            if (root.norm(tl.address) !== a || !tl.wayland || !c || !c.at || !c.size
                    || !c.workspace || c.size[0] < 8 || c.size[1] < 8) continue;
            if (c.workspace.name === "special:minimized") return true;
            root.onPrepared({addr: a, appId: c.class || c.initialClass || "", title: c.title || "",
                ws: c.workspace.id, wsName: c.workspace.name, mon: c.monitor, pid: c.pid,
                fullscreen: c.fullscreen || 0, at: c.at, size: c.size,
                floating: c.floating !== false, shot: "", capture: root.nativeCaptureAvailable,
                screenshot: !root.nativeCaptureAvailable});
            return true;
        }
        return false;
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
            var ghost = ghostModel.get(i);
            if (ghost.gid !== gid) continue;
            // Even a discarded/stalled restore ghost must release its window.
            if (ghost.gmode === "restore") root.finishRestore(ghost.gaddr);
            ghostModel.remove(i);
            return;
        }
    }

    function cancelGhosts(a) {
        for (var i = ghostModel.count - 1; i >= 0; i--)
            if (ghostModel.get(i).gaddr === a) ghostModel.remove(i);
    }

    // ───────── minimize ─────────
    function minimizeFocused() { var a = root.focusedAddr(); if (a !== "") root.minimize(a); }

    function minimize(a) {
        a = root.norm(a);
        root.trace("request-minimize", {addr:a, recorded:!!root.records[a], parked:!!root.onSpecial[a]});
        if (a === "" || root.records[a] !== undefined) return;
        if (root.onSpecial[a] === true || root.preparing[a]) return;
        delete root.canceledPreparations[a];
        var inFlight = Object.assign({}, preparing); inFlight[a] = true; preparing = inFlight;
        if (root.prepareDirect(a)) {
            var ready = Object.assign({}, preparing); delete ready[a]; preparing = ready;
            return;
        }
        prepareQueue = prepareQueue.concat([a]); prepareNext();
    }

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
                if (o && o.ok && !root.canceledPreparations[root.norm(o.addr)]) root.onPrepared(o);
            }
        }
    }

    function onPrepared(o) {
        var a = root.norm(o.addr);
        root.trace("prepared", {addr:a, screenshot:!!o.screenshot, capture:!!o.capture, shot:!!o.shot, size:o.size});
        var rec = { addr: a, appId: o.appId, title: o.title, ws: o.ws, wsName: o.wsName,
                    mon: o.mon, pid: o.pid, fullscreen: o.fullscreen || 0, at: o.at, size: o.size, floating: o.floating, shot: o.shot, born: Date.now() };
        var m = {};
        for (var k in root.records) m[k] = root.records[k];
        m[a] = rec;
        root.records = m;
        root.saveState();

        if (o.screenshot) { root.queueScreenshot(rec); return; }

        var key = root.dockKey(o.appId);
        var t = root.dockTarget(key, o.mon, a);
        var scr = root.screenForMon(o.mon) || root.screenForPoint(o.at[0], o.at[1]);
        root.trace("target", {addr:a, target: t, screen:scr ? scr.name : "", effect:Corners.DesktopPreferences.settings.minimizeEffect});
        if (t && scr && t.screen === scr.name && (o.capture || o.shot !== "")) {
            root.addGhost({ gmode: "minimize", gaddr: a, gsrc: o.shot, gcapture: !!o.capture, gscreen: scr.name,
                wx: o.at[0] - scr.x, wy: o.at[1] - scr.y, ww: o.size[0], wh: o.size[1],
                icx: t.x - scr.x, icy: t.y - scr.y, icsz: t.size, geffect: Corners.DesktopPreferences.settings.minimizeEffect,
                gdirection: Corners.DesktopPreferences.settings.position });
        } else root.hideWindow(a);
    }

    function queueScreenshot(rec) {
        if (!rec || root.canceledPreparations[rec.addr]) return;
        root.screenshotQueue = root.screenshotQueue.concat([rec]);
        root.nextScreenshot();
    }

    function nextScreenshot() {
        if (screenshotProc.running || root.screenshotQueue.length === 0) return;
        var queue = root.screenshotQueue.slice(), rec = queue.shift();
        root.screenshotQueue = queue;
        root.trace("snapshot-start", {addr:rec.addr, at:rec.at, size:rec.size});
        screenshotProc.request = rec;
        screenshotProc.running = true;
    }

    function nativeCaptureFailed(a) {
        // Some compositor sessions cannot export a toplevel. Preserve the
        // chosen animation by capturing its visible region instead of skipping
        // Genie/Scale. Later clicks use this path directly, without a timeout.
        root.nativeCaptureAvailable = false;
        var rec = root.records[a];
        root.cancelGhosts(a);
        if (rec) root.queueScreenshot(rec);
    }

    Process {
        id: screenshotProc
        property var request: null
        readonly property string path: request ? root.shotDir + "/" + request.addr + ".png" : ""
        command: request ? ["grim", "-l", "0", "-g",
            request.at[0] + "," + request.at[1] + " " + request.size[0] + "x" + request.size[1], path] : []
        onExited: function(code, status) {
            var rec = request;
            root.trace("snapshot-exit", {addr:rec ? rec.addr : "", code:code});
            if (rec && root.records[rec.addr] && !root.canceledPreparations[rec.addr]) {
                if (code === 0) root.onPrepared(Object.assign({}, rec, {shot: path, capture: false}));
                else {
                    console.warn("[macmin] screenshot unavailable for", rec.addr);
                    root.hideWindow(rec.addr);
                }
            }
            Qt.callLater(root.nextScreenshot);
        }
    }

    function hideWindow(a) {
        root.trace("hide-native", {addr:a});
        // The ghost owns the visual transition. Suppress Hyprland's additional
        // move/fade so a second copy cannot flash underneath the warped frame.
        Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "1", window = "address:0x' + a + '" })');
        Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:0x' + a + '" })');
    }

    function saveSnapshot(a, image) {
        var r = root.records[a];
        if (!r) return;
        var path = root.shotDir + "/" + a + ".png";
        if (!image.saveToFile(path)) return;
        var next = Object.assign({}, root.records);
        next[a] = Object.assign({}, r, {shot: path});
        root.records = next;
        root.saveState();
    }

    function releaseAnimation(a) {
        Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "unset", window = "address:0x' + a + '" })');
    }

    property var restoreReleases: []
    Timer {
        id: releaseRestored
        interval: 60
        onTriggered: {
            var addresses = root.restoreReleases; root.restoreReleases = [];
            for (var i = 0; i < addresses.length; i++) root.releaseAnimation(addresses[i]);
        }
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
        root.trace("request-restore", {addr:a, pending:!!root.pendingRestore[a], shot:!!(root.records[a] && root.records[a].shot)});
        if (a === "") return;
        // A repeated click recovers immediately; the initial click animates.
        // Nothing waits for the old minimize animation or optional preview save.
        if (root.pendingRestore[a]) {
            root.finishRestore(a);
            root.cancelGhosts(a);
            return;
        }
        var next = Object.assign({}, root.preparing); delete next[a]; root.preparing = next;
        root.canceledPreparations[a] = true;
        root.prepareQueue = root.prepareQueue.filter(function(addr) { return addr !== a; });
        root.screenshotQueue = root.screenshotQueue.filter(function(rec) { return rec.addr !== a; });
        delete root.pendingRestore[a];
        root.cancelGhosts(a);
        var r = root.records[a];
        var mon = r ? r.mon : null;
        var rect = (r && r.at && r.size) ? { x: r.at[0], y: r.at[1], w: r.size[0], h: r.size[1] }
                                        : root.defaultRect(mon);
        rect = root.clampRect(rect, mon);

        var scr = root.screenForMon(mon) || root.screenForPoint(rect.x, rect.y);
        var t = root.dockTarget(r ? root.dockKey(r.appId) : "", mon, a);
        var capture = !(r && r.shot);
        if (r && t && scr && t.screen === scr.name && (!capture || root.toplevelFor(a))) {
            // Register recovery BEFORE delegate creation: loading can fail or
            // complete synchronously. The root deadline outlives the delegate.
            var pending = Object.assign({}, root.pendingRestore); pending[a] = rect;
            root.pendingRestore = pending;
            var deadlines = Object.assign({}, root.restoreDeadlines);
            deadlines[a] = Date.now() + 900;
            root.restoreDeadlines = deadlines;
            root.addGhost({ gmode: "restore", gaddr: a, gsrc: r.shot || "", gcapture: capture, gscreen: scr.name,
                wx: rect.x - scr.x, wy: rect.y - scr.y, ww: rect.w, wh: rect.h,
                icx: t.x - scr.x, icy: t.y - scr.y, icsz: t.size,
                geffect: Corners.DesktopPreferences.settings.minimizeEffect,
                gdirection: Corners.DesktopPreferences.settings.position });
            return;
        }
        root.doRestore(a, rect);
    }

    function finishRestore(a) {
        a = root.norm(a);
        var rect = root.pendingRestore[a];
        var pending = Object.assign({}, root.pendingRestore); delete pending[a];
        root.pendingRestore = pending;
        var deadlines = Object.assign({}, root.restoreDeadlines); delete deadlines[a];
        root.restoreDeadlines = deadlines;
        if (rect) root.doRestore(a, rect);
    }

    function recoverRestores() {
        var now = Date.now(), deadlines = root.restoreDeadlines;
        for (var a in deadlines) {
            if (deadlines[a] > now) continue;
            root.finishRestore(a);
            root.cancelGhosts(a);
        }
    }

    Timer {
        id: restoreRecovery
        interval: 25
        repeat: true
        running: Object.keys(root.restoreDeadlines).length > 0
        onTriggered: root.recoverRestores()
    }

    function doRestore(a, rect) {
        var r = root.records[a];
        var sel = 'window = "address:0x' + a + '"';
        var wsSel;
        if (r && r.wsName && String(r.wsName).indexOf("special:") === 0) wsSel = '"' + r.wsName + '"';
        else if (r && r.ws !== undefined && Number(r.ws) >= 0) wsSel = Number(r.ws);
        else wsSel = root.currentWorkspaceId(rect);
        Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "1", ' + sel + ' })');
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
        var special = Object.assign({}, root.onSpecial); delete special[a]; root.onSpecial = special;
        root.saveState();
        root.restoreReleases = root.restoreReleases.concat([a]);
        releaseRestored.restart();
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
            else {
                changed = true;
                if (current) root.releaseAnimation(addr);
            }
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
            var deadlines = Object.assign({}, root.restoreDeadlines); delete deadlines[a];
            root.restoreDeadlines = deadlines;
            root.cancelGhosts(a);
        }
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root.cfgDir, root.shotDir]);
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
                    required property bool gcapture
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
                    property bool started: false
                    property bool textureReady: false
                    property bool saving: false
                    property bool finished: false
                    property Item frozenSource: null
                    readonly property bool sourceReady: gcapture ? capture.hasContent : srcImg.status === Image.Ready
                    onSourceReadyChanged: freezeSource()

                    function freezeSource() {
                        if (!sourceReady || frozenSource) return;
                        frozenSource = gcapture ? capture : srcImg;
                        srcTex.scheduleUpdate();
                    }

                    // A ready texture is sufficient to begin. A ShaderEffect
                    // using Qt's cached shader metadata can retain Uncompiled
                    // status even while it renders correctly. Only Error is a
                    // failure; requiring Compiled silently skips cached effects.
                    function maybeStart() {
                        if (started || !visible || !frozenSource || !textureReady
                                || fx.status === ShaderEffect.Error) return;
                        started = true;
                        root.trace("animation-start", {addr:gaddr, mode:gmode, effect:geffect, texture:textureReady,
                            shader:fx.status, width:fx.width, height:fx.height, visible:fx.visible});
                        if (gmode === "minimize") root.hideWindow(gaddr);
                        anim.start();
                        if (gcapture && gmode === "minimize") snapshotSoon.start();
                    }

                    function savePreview() {
                        if (saving) return;
                        saving = true;
                        // Optional thumbnail only. Neither completion nor
                        // failure owns the animation or restore lifecycle.
                        frozenSource.grabToImage(function(image) {
                            root.saveSnapshot(gh.gaddr, image);
                        });
                    }

                    function completeMinimize() {
                        finished = true;
                        root.removeGhost(gid);
                    }

                    function skipAnimation() {
                        if (started || !visible) return;
                        root.trace("animation-skipped", {addr:gaddr, mode:gmode, effect:geffect, sourceReady:sourceReady, texture:textureReady, shader:fx.status, image:srcImg.status, hasWindow:!!gh.Window.window});
                        started = true;
                        finished = true;
                        // Do not destroy a delegate inside its loading callback.
                        Qt.callLater(function() {
                            if (gh.gmode === "minimize" && gh.gcapture) {
                                root.nativeCaptureFailed(gh.gaddr);
                                return;
                            }
                            if (gh.gmode === "minimize") root.hideWindow(gh.gaddr);
                            else root.finishRestore(gh.gaddr);
                            root.removeGhost(gh.gid);
                        });
                    }

                    visible: gscreen === animWin.modelData.name
                    x: Math.min(wx, icx - icsz / 2) - pad
                    y: Math.min(wy, icy - icsz / 2) - pad
                    width: Math.max(wx + ww, icx + icsz / 2) - x + pad
                    height: Math.max(wy + wh, icy + icsz / 2) - y + pad

                    // Capture this window itself, including when another app
                    // overlaps it. No desktop pixels or focus flash enter it.
                    ScreencopyView {
                        id: capture
                        x: gh.wx - gh.x
                        y: gh.wy - gh.y
                        width: gh.ww
                        height: gh.wh
                        captureSource: gh.gcapture && gh.visible ? root.toplevelFor(gh.gaddr) : null
                        live: false
                        paintCursor: false
                        visible: false
                        onStopped: if (!hasContent) gh.skipAnimation();
                    }

                    // Old records and shell reloads can still use saved images.
                    Image {
                        id: srcImg
                        x: gh.wx - gh.x
                        y: gh.wy - gh.y
                        width: gh.ww
                        height: gh.wh
                        source: gh.gsrc !== "" ? ("file://" + gh.gsrc) : ""
                        fillMode: Image.Stretch
                        visible: false
                        smooth: true
                        asynchronous: true
                        cache: false
                        onStatusChanged: {
                            root.trace("image-status", {addr:gh.gaddr, status:status});
                            if (status === Image.Error) gh.skipAnimation();
                        }
                    }

                    ShaderEffectSource {
                        id: srcTex
                        // Keep this texture producer in the scene graph. Hiding
                        // it prevents updatePaintNode from initializing the GPU
                        // layer, even when the shader requests its texture.
                        // Zero display size prevents a second unwarped window;
                        // the texture still uses the source item's full size.
                        width: 0
                        height: 0
                        sourceItem: gh.frozenSource
                        hideSource: true
                        live: false
                        recursive: false
                        onScheduledUpdateCompleted: {
                            if (!gh.frozenSource || gh.textureReady) return;
                            gh.textureReady = true;
                            root.trace("texture-ready", {addr:gh.gaddr, mode:gh.gmode});
                            Qt.callLater(gh.maybeStart);
                        }
                    }

                    ShaderEffect {
                        id: fx
                        anchors.fill: parent
                        // Prepare at the transparent Dock endpoint so the shader
                        // keeps rendering without covering the live app.
                        opacity: gh.finished ? 0 : 1
                        fragmentShader: Qt.resolvedUrl("window-transition.frag.qsb")
                        property variant src: srcTex
                        property vector2d itemSize: Qt.vector2d(width, height)
                        property vector4d win: Qt.vector4d(gh.wx - gh.x, gh.wy - gh.y, gh.wx - gh.x + gh.ww, gh.wy - gh.y + gh.wh)
                        property vector4d icon: Qt.vector4d(gh.icx - gh.x - gh.icsz / 2, gh.icy - gh.y - gh.icsz / 2,
                                                            gh.icx - gh.x + gh.icsz / 2, gh.icy - gh.y + gh.icsz / 2)
                        // Prepare at the invisible Dock endpoint while keeping
                        // the shader renderable. The minimize animation sets
                        // progress to zero on the first frame that takes over.
                        property real progress: 1
                        property real effect: gh.geffect === "scale" ? 1 : 0
                        property real direction: gh.gdirection === "left" ? 1 : gh.gdirection === "right" ? 2 : 0
                        onStatusChanged: {
                            root.trace("shader-status", {addr:gh.gaddr, mode:gh.gmode, status:status,
                                width:width, height:height, visible:visible, opacity:opacity});
                            if (status === ShaderEffect.Error) {
                                console.log("[macmin] genie shader error:", log);
                                gh.skipAnimation();
                            } else if (status === ShaderEffect.Compiled)
                                Qt.callLater(gh.maybeStart);
                        }
                    }

                    NumberAnimation {
                        id: anim
                        target: fx
                        property: "progress"
                        from: gh.gmode === "minimize" ? 0.0 : 1.0
                        to: gh.gmode === "minimize" ? 1.0 : 0.0
                        duration: gh.geffect === "scale" ? 260 : gh.gmode === "minimize" ? root.durMin : root.durRes
                        easing.type: Easing.OutCubic
                        onFinished: {
                            if (gh.gscreen !== animWin.modelData.name) return;
                            root.trace("animation-finished", {addr:gh.gaddr, mode:gh.gmode, effect:gh.geffect});
                            if (gh.gmode === "minimize") gh.completeMinimize();
                            else { root.finishRestore(gh.gaddr); landTimer.start(); }
                        }
                    }

                    Timer {
                        id: landTimer
                        interval: 60
                        onTriggered: root.removeGhost(gh.gid)
                    }

                    Timer {
                        id: startDeadline
                        interval: 180
                        running: gh.visible && !gh.started
                        onTriggered: gh.skipAnimation()
                    }

                    Timer {
                        id: snapshotSoon
                        interval: 1
                        onTriggered: gh.savePreview()
                    }

                    Timer {
                        interval: 1100
                        running: gh.visible
                        onTriggered: {
                            if (!gh.started && gh.gmode === "minimize") root.hideWindow(gh.gaddr);
                            if (gh.gmode === "restore") root.finishRestore(gh.gaddr);
                            root.removeGhost(gh.gid);
                        }
                    }

                    Component.onCompleted: {
                        root.trace("delegate-created", {addr:gaddr, mode:gmode, effect:geffect, visible:visible, screen:gscreen, host:animWin.modelData.name});
                        if (srcImg.status === Image.Error || fx.status === ShaderEffect.Error)
                            skipAnimation();
                        else freezeSource();
                    }
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
