pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "NotchToolsState.js" as Logic
import "NotchDeviceState.js" as Devices

Scope {
    id: tools
    property var bar: null
    property string storagePath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/macshell/notch-tools.json"
    property bool persistence: true
    property bool notifications: true
    property bool loaded: !persistence
    property bool saveBlocked: false
    property var state: Logic.defaults(Date.now())
    property real nowMs: Date.now()
    property string error: ""
    property var shelfQueue: []
    property string deviceEvent: ""
    property var feedbackDevice: null
    property string deviceEventReason: "connected"
    property bool deviceEventExpanded: false
    property var deviceEventQueue: []
    property var bluetoothBatteries: ({})
    property int deviceExpandedMs: 4500
    property int deviceCompactMs: 5000
    property var knownBluetooth: []
    property bool bluetoothPrimed: false
    property bool pomodoroDismissed: false
    property int rotationClients: 0
    property int rotationHolds: 0
    readonly property bool dialogOpen: filePicker.visible || folderPicker.visible
    readonly property bool shelfBusy: shelfProcess.running || shelfQueue.length > 0
    readonly property var settings: state.settings
    readonly property var pomodoro: state.pomodoro
    readonly property real pomodoroLeft: Logic.remaining(pomodoro, nowMs)
    readonly property bool pomodoroActive: pomodoro.state === "running" || pomodoro.state === "paused" || pomodoro.state === "finished"
    readonly property int sessionsToday: Logic.sessionsToday(state, nowMs)
    readonly property var targetTask: state.tasks.find(t => t.id === pomodoro.targetId) || null
    readonly property var focusContexts: state.focus.contexts.filter(id => state.menus.indexOf(id) >= 0)
    readonly property bool rotationRunning: loaded && state.focus.rotate && focusContexts.length > 1 && rotationClients > 0 && rotationHolds === 0
        && (!bar || (bar.notchEnabled && !bar.osdVisible)) && deviceEvent === ""
        && !(bar && bar.hub && bar.hub.clock && bar.hub.clock.ringing)
    readonly property int waterTotal: Logic.waterTotal(state, nowMs)
    readonly property var waterHours: Logic.waterHours(state, nowMs)
    readonly property int doneToday: Logic.doneToday(state, nowMs)
    readonly property int pendingTasks: state.tasks.filter(t => !t.done).length
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("bin/notch_shelf.py").toString().replace(/^file:\/\//, ""))
    readonly property var calendar: calendarService
    NotchCalendar { id:calendarService;ioEnabled:tools.persistence;enabled:tools.loaded && tools.persistence && !!tools.bar && tools.bar.notchEnabled && tools.state.page==="calendar" }
    readonly property var stats: statsService
    NotchStats {id:statsService;ioEnabled:tools.persistence;enabled:tools.loaded && !!tools.bar && tools.bar.notchEnabled}
    signal reminder(string title, string body)

    function deviceKey(device) { return Devices.key(device); }
    function showDeviceEvent(kind, device, reason) {
        if (!bar || !bar.notchEnabled || !bar.osdReady) return;
        feedbackDevice=device || null; deviceEventReason=reason || "connected";
        deviceEventExpanded=true; deviceEvent=kind; deviceEventTimer.restart();
    }
    function queueDeviceEvent(kind, device, reason) {
        if (!bar || !bar.notchEnabled || !bar.osdReady) return;
        if (deviceEvent === "" || (kind === "bluetooth" && deviceEvent === kind && feedbackDevice && deviceKey(device) === deviceKey(feedbackDevice))) {
            showDeviceEvent(kind,device,reason); return;
        }
        const pending=deviceEventQueue.filter(e=>kind!=="bluetooth" || e.kind!==kind || deviceKey(e.device)!==deviceKey(device));
        pending.push({kind:kind,device:device,reason:reason || "connected"});deviceEventQueue=pending.slice(-8);
    }
    function dismissDeviceEvent() {
        deviceEventTimer.stop();deviceEvent="";feedbackDevice=null;deviceEventExpanded=false;deviceEventReason="connected";deviceEventQueue=[];
    }
    function finishDeviceEvent() {
        const next=deviceEventQueue.slice();dismissDeviceEvent();
        if(next.length){const event=next.shift();deviceEventQueue=next;showDeviceEvent(event.kind,event.device,event.reason);}
    }
    function expandDeviceEvent() { if(deviceEvent==="bluetooth"){deviceEventExpanded=true;deviceEventTimer.restart();} }
    function advanceDeviceEvent() {
        if(deviceEvent==="bluetooth" && deviceEventExpanded){deviceEventExpanded=false;deviceEventTimer.restart();}
        else finishDeviceEvent();
    }
    function observeBluetooth() {
        if (!bar || bar.btReady === false) return;
        const connected=bar.btOn && bar.btDevices ? bar.btDevices.filter(d=>d.connected) : [];
        const scan=Devices.observe(bluetoothPrimed ? bluetoothBatteries : {},connected,bluetoothPrimed);
        bluetoothBatteries=scan.history;knownBluetooth=scan.keys;bluetoothPrimed=true;
        deviceEventQueue=deviceEventQueue.filter(e=>e.kind!=="bluetooth" || scan.keys.indexOf(deviceKey(e.device))>=0)
            .map(e=>e.kind==="bluetooth" ? Object.assign({},e,{device:connected.find(d=>deviceKey(d)===deviceKey(e.device))}) : e);
        if(deviceEvent==="bluetooth") {
            const fresh=connected.find(d=>feedbackDevice && deviceKey(d)===deviceKey(feedbackDevice));
            if(!fresh)finishDeviceEvent();else feedbackDevice=fresh;
        }
        for(const event of scan.events)queueDeviceEvent("bluetooth",event.device,event.reason);
    }
    onBarChanged: { bluetoothPrimed = false; knownBluetooth = []; bluetoothBatteries = {}; Qt.callLater(observeBluetooth); }
    Component.onCompleted: observeBluetooth()
    Connections {
        target: tools.bar
        ignoreUnknownSignals: true
        function onBtReadyChanged() { tools.observeBluetooth(); }
        function onBtDevicesChanged() { tools.observeBluetooth(); }
        function onBtOnChanged() { tools.observeBluetooth(); }
        function onChargingChanged() {
            if (tools.bar.charging && tools.bar.hasBattery) tools.showDeviceEvent("charging", null);
            else if (tools.deviceEvent === "charging") tools.finishDeviceEvent();
        }
        function onNotchEnabledChanged() { if (!tools.bar.notchEnabled) tools.dismissDeviceEvent(); }
    }
    Timer { id: deviceEventTimer; interval: tools.deviceEventExpanded ? tools.deviceExpandedMs : tools.deviceCompactMs; onTriggered: tools.advanceDeviceEvent() }

    function notify(title, body, silent) {
        reminder(title, body);
        if (notifications) Quickshell.execDetached(["notify-send", "-a", "Dynamic Notch"].concat(silent ? ["--hint=boolean:suppress-sound:true"] : []).concat([title, body]));
    }
    function commit(next) { state = next; if (persistence && loaded) saveLater.restart(); }
    function setStatsView(view) {
        if (["overview","detail"].indexOf(view)<0 || state.stats.view===view) return;
        const s=Logic.copy(state);s.stats.view=view;commit(s);
    }
    function selectStatsMetric(slot,id) {
        if (["primary","secondary"].indexOf(slot)<0 || Logic.statsIds.indexOf(id)<0) return false;
        if(state.stats[slot]===id)return true;
        const s=Logic.copy(state),other=slot==="primary"?"secondary":"primary";
        if(s.stats[other]===id)s.stats[other]=s.stats[slot];
        s.stats[slot]=id;commit(s);return true;
    }
    function setPage(page) {
        if (state.menus.indexOf(page) < 0 || state.page === page) return;
        const s = Logic.copy(state); s.page = page; commit(s);
        if (rotationRunning) rotationTimer.restart();
    }
    function setMenu(page, enabled) {
        if (Logic.pageIds.indexOf(page) < 0) return;
        const s = Logic.copy(state);
        s.menus = Logic.pageIds.filter(id => id === page ? enabled : s.menus.indexOf(id) >= 0);
        if (!s.menus.length) { error = "Keep at least one notch page enabled."; return; }
        if (s.menus.indexOf(s.page) < 0) s.page = s.menus[0];
        s.focus.contexts=s.focus.contexts.filter(id=>s.menus.indexOf(id)>=0);
        if(!s.focus.contexts.length)s.focus.contexts=[s.menus[0]];
        error = ""; commit(s);
    }
    function updateMenus(ids) {
        const menus = Logic.pageIds.filter(id => ids.indexOf(id) >= 0);
        if (!menus.length) { error = "Keep at least one notch page enabled."; return false; }
        const s=Logic.copy(state); s.menus=menus;
        if (menus.indexOf(s.page)<0) s.page=menus[0];
        s.focus.contexts=s.focus.contexts.filter(id=>menus.indexOf(id)>=0);
        if (!s.focus.contexts.length) s.focus.contexts=[menus[0]];
        error=""; commit(s); return true;
    }
    function configureFocus(ids, rotate, seconds) {
        const contexts=state.menus.filter(id=>ids.indexOf(id)>=0);
        if (!contexts.length) { error="Choose at least one focus activity."; return false; }
        const s=Logic.copy(state);s.focus={contexts:contexts,rotate:!!rotate,seconds:Logic.number(seconds,5,3,30)};
        commit(s); if(rotationRunning)rotationTimer.restart(); return true;
    }
    Timer {
        id:rotationTimer;interval:tools.state.focus.seconds*1000;repeat:true;running:tools.rotationRunning
        onTriggered:{const ids=tools.focusContexts;const at=ids.indexOf(tools.state.page);tools.setPage(ids[(at+1)%ids.length]);}
    }
    function updateSettings(values) {
        const s = Logic.copy(state); s.settings = Logic.settings(Object.assign({}, settings, values));
        if (pomodoro.state === "idle") { s.pomodoro.total = s.settings[pomodoro.mode] * 60000; s.pomodoro.left = s.pomodoro.total; }
        if (values.reminder !== undefined || values.remind !== undefined) s.water.lastReminder = Date.now();
        commit(s);
    }
    function setPhase(mode) {
        if (["focus", "short", "long", "quick", "custom"].indexOf(mode) < 0) return;
        pomodoroDismissed=false;
        const s = Logic.copy(state), total = settings[mode] * 60000;
        s.pomodoro = Object.assign({}, s.pomodoro, { mode: mode, state: "idle", total: total, left: total, endAt: 0 });
        commit(s);
    }
    function togglePomodoro() {
        pomodoroDismissed=false;
        nowMs = Date.now();
        if (pomodoro.state === "finished") setPhase(Logic.nextMode(state));
        const s = Logic.copy(state), p = s.pomodoro;
        if (p.state === "running") { p.left = Logic.remaining(p, nowMs); p.endAt = 0; p.state = "paused"; }
        else { p.endAt = nowMs + p.left; p.state = "running"; }
        commit(s);
    }
    function resetPomodoro() { setPhase(pomodoro.mode); }
    function skipPomodoro() {
        const running=pomodoro.state==="running";
        const work=pomodoro.mode==="focus" || pomodoro.mode==="custom";
        setPhase(pomodoro.mode==="quick" ? "focus" : work && pomodoro.state!=="finished" ? "short" : Logic.nextMode(state));
        if(running)togglePomodoro();
    }
    function setPomodoroLayout(wide) { const s=Logic.copy(state);s.pomodoro.targetsOpen=!!wide;commit(s); }
    function selectTarget(id) {
        if(id && !state.tasks.some(t=>t.id===id))return;
        const s=Logic.copy(state);s.pomodoro.targetId=id;commit(s);
    }
    function drink() {
        nowMs = Date.now(); const s = Logic.copy(state);
        s.water.entries = s.water.entries.filter(e => e.at >= nowMs - 30 * 86400000);
        s.water.entries.push({ at: nowMs, ml: settings.glass }); s.water.lastReminder = nowMs; commit(s);
    }
    function undoDrink() {
        const s = Logic.copy(state), today = Logic.day(Date.now());
        for (let i = s.water.entries.length - 1; i >= 0; i--) {
            if (Logic.day(s.water.entries[i].at) === today) { s.water.entries.splice(i, 1); commit(s); return; }
        }
    }
    function addTask(text) {
        text = text.trim().slice(0, 300);
        if (!text) return false;
        if (state.tasks.length >= 500) { error = "The task list is full. Remove an old task first."; return false; }
        const s = Logic.copy(state), at = Date.now();
        s.tasks.unshift({ id: at.toString(36) + Math.floor(Math.random() * 1000000).toString(36), text: text, done: false, createdAt: at, doneAt: 0 });
        error = ""; commit(s); return true;
    }
    function editTask(id, text) {
        text = text.trim().slice(0, 300); if (!text) return false;
        const s = Logic.copy(state); s.tasks = s.tasks.map(t => t.id === id ? Object.assign({}, t, { text: text }) : t);
        commit(s); return true;
    }
    function toggleTask(id) {
        const s = Logic.copy(state), at = Date.now();
        s.tasks = s.tasks.map(t => t.id === id ? Object.assign({}, t, { done: !t.done, doneAt: t.done ? 0 : at }) : t);
        commit(s);
    }
    function removeTask(id) { const s = Logic.copy(state); s.tasks = s.tasks.filter(t => t.id !== id); if(s.pomodoro.targetId===id)s.pomodoro.targetId=""; commit(s); }
    function removeShelf(url) { const s = Logic.copy(state); s.shelf = s.shelf.filter(e => e.url !== url); commit(s); }
    function clearShelf() { const s = Logic.copy(state); s.shelf = []; error = ""; commit(s); }
    function addShelf(urls) {
        shelfQueue = shelfQueue.concat([{ action: "inspect", payload: JSON.stringify(Array.from(urls).map(u => String(u))) }]); runShelf();
    }
    function openShelf(url) { shelfQueue = shelfQueue.concat([{ action: "open", payload: url }]); runShelf(); }
    function runShelf() {
        if (shelfProcess.running || !shelfQueue.length) return;
        const job = shelfQueue[0]; shelfQueue = shelfQueue.slice(1);
        shelfProcess.command = ["python3", helper, job.action, job.payload]; shelfProcess.running = true;
    }
    function pickFiles() { filePicker.open(); }
    function pickFolder() { folderPicker.open(); }
    FileDialog { id: filePicker; title: "Add files to Shelf"; fileMode: FileDialog.OpenFiles; onAccepted: tools.addShelf(selectedFiles) }
    FolderDialog { id: folderPicker; title: "Add a folder to Shelf"; onAccepted: tools.addShelf([selectedFolder]) }
    Process {
        id: shelfProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.items) {
                        const s = Logic.copy(tools.state), existing = s.shelf.map(e => e.url);
                        s.shelf = s.shelf.concat(result.items.filter(e => existing.indexOf(e.url) < 0)).slice(0, 100);
                        tools.commit(s);
                    }
                    tools.error = (result.errors || []).join(" · ");
                } catch (e) { tools.error = "Could not read the Shelf response."; }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) tools.error = "Shelf could not open this file. Check that it still exists.";
            Qt.callLater(tools.runShelf);
        }
    }
    FileView {
        id: store
        path: tools.persistence ? tools.storagePath : ""
        printErrors: false; atomicWrites: true; blockWrites: true; watchChanges: false
        onLoaded: {
            if (tools.loaded) return;
            try {
                const raw = JSON.parse(text());
                tools.state = Logic.restore(raw, Date.now());
                if (JSON.stringify(raw) !== JSON.stringify(tools.state)) saveLater.restart();
            }
            catch (e) { tools.saveBlocked = true; tools.error = "Saved notch data could not be read. Keeping a backup before saving."; backupProcess.running = true; }
            tools.loaded = true; tools.refresh();
        }
        onLoadFailed: cause => {
            if (!tools.persistence) return;
            tools.loaded = true;
            if (cause === FileViewError.FileNotFound) ensureDirectory.running = true;
            else { tools.saveBlocked = true; tools.error = "Saved notch data could not be opened. Saving is paused to preserve that file."; }
        }
        onSaveFailed: tools.error = "Notch data could not be saved. Check the configuration folder permissions."
    }
    Process {
        id: ensureDirectory
        command: ["mkdir", "-p", tools.storagePath.substring(0, tools.storagePath.lastIndexOf("/"))]
        onExited: exitCode => {
            if (exitCode === 0) saveLater.restart();
            else { tools.saveBlocked = true; tools.error = "The notch data folder could not be created."; }
        }
    }
    Process {
        id: backupProcess
        command: ["cp", "--", tools.storagePath, tools.storagePath + ".unreadable-" + Date.now()]
        onExited: exitCode => {
            if (exitCode === 0) { tools.saveBlocked = false; saveLater.restart(); }
            else tools.error = "Saved notch data could not be backed up. Saving is paused to preserve that file.";
        }
    }
    Timer { id: saveLater; interval: 150; onTriggered: if (tools.loaded && tools.persistence && !tools.saveBlocked) store.setText(JSON.stringify(tools.state, null, 1)) }
    function refresh() {
        nowMs = Date.now(); if (!loaded) return;
        const prior = state, next = Logic.tick(state, nowMs, (!bar || bar.notchEnabled) && state.menus.indexOf("water") >= 0);
        if (next !== prior) {
            commit(next);
            if (prior.pomodoro.state === "running" && next.pomodoro.state === "finished")
                pomodoroDismissed=false;
            if (prior.pomodoro.state === "running" && next.pomodoro.state === "finished") {
                if (notifications && settings.pomodoroSound) Quickshell.execDetached(["canberra-gtk-play", "--id=complete", "--description=Pomodoro complete"]);
                notify(next.pomodoro.mode === "quick" ? "Quick timer complete" : next.pomodoro.mode === "focus" || next.pomodoro.mode === "custom" ? "Focus session complete" : "Break complete",
                    next.pomodoro.mode === "quick" ? "Your countdown has finished." : next.pomodoro.mode === "focus" || next.pomodoro.mode === "custom" ? "Take a moment to rest. Your next break is ready." : "Ready for another focus session?", true);
            }
            if (next.water.lastReminder !== prior.water.lastReminder) notify("Water reminder", "Time for a drink. Add it from Dynamic Notch when you are ready.");
        }
    }
    Timer {
        interval: tools.pomodoro.state === "running" ? 1000 : 60000
        repeat: true; running: tools.loaded
        onTriggered: tools.refresh()
    }
    Component.onDestruction: if (loaded && persistence && !saveBlocked) store.setText(JSON.stringify(state, null, 1))
}
