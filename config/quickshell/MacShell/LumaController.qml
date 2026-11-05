pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var hub: null
    property bool connected: false
    property bool ready: false
    property bool runtimeReady: false
    property bool loaded: false
    property string busy: ""
    property string error: ""
    property string stage: ""
    property real progress: 0
    property string selectedModel: "gemma-3-1b"
    property var catalog: []
    property var conversations: []
    property var messages: []
    property string currentConversation: ""
    property string response: ""
    property string draft: ""
    property var pending: []
    signal quickRequested()
    signal closeQuickRequested()

    function ensure() {
        if (!worker.running) { error = ""; worker.running = true; }
    }
    function send(request) {
        error = "";
        if (connected) worker.write(JSON.stringify(request) + "\n");
        else { pending = pending.concat([request]); ensure(); }
    }
    function refresh() { send({action: "status"}); }
    function install(id) { progress = 0; stage = "Preparing installation…"; send({action: "install", model: id}); }
    function importModel(id, path) { progress = 0; stage = "Preparing import…"; send({action: "import", model: id, path: path}); }
    function open(prompt) {
        closeQuickRequested();
        ensure();
        if (prompt) draft = prompt;
        panel.active = true;
        Qt.callLater(function() { if (panel.item) panel.item.open(); });
        refresh();
    }
    function settings() { if (hub) hub.openSettings("luma"); }
    function recordAction(text, result) { send({action: "record_action", text: text, result: result}); }
    function submit() {
        var text = draft.trim();
        if (!text || busy || !ready) return;
        if (text.length > 3500) { error = "Please keep the message below 3500 characters."; return; }
        draft = ""; response = ""; stage = "";
        // Desktop actions use explicit intents and installed application entries.
        // Model output is displayed as text and is never executed as a command.
        var intent = /^(?:buka|open|launch)\s+(.+?)[.!]?$/i.exec(text);
        if (intent && hub) {
            var name = intent[1].trim().toLowerCase();
            var panes = {settings: "general", pengaturan: "general", "system settings": "general",
                         "luma settings": "luma", "pengaturan luma": "luma", wallpaper: "wallpaper",
                         bluetooth: "bluetooth", wifi: "wifi", "wi-fi": "wifi", sound: "sound", suara: "sound",
                         appearance: "appearance", tampilan: "appearance"};
            if (typeof panes[name] === "string") {
                hub.openSettings(panes[name]);
                recordAction(text, "Opened " + name + " settings."); return;
            }
            if (name === "terminal" || name === "files" || name === "file manager" || name === "file") {
                Quickshell.execDetached([name === "terminal" ? "macshell-terminal" : "macshell-files"]);
                recordAction(text, "Requested opening " + name + "."); return;
            }
            var entries = DesktopEntries.applications.values;
            for (var i = 0; i < entries.length; i++) {
                var app = entries[i];
                if (app.name.toLowerCase() === name || app.id.replace(/\.desktop$/, "").toLowerCase() === name) {
                    app.execute();
                    recordAction(text, "Requested opening " + app.name + "."); return;
                }
            }
            recordAction(text, "No installed application named “" + intent[1] + "” was found. Use its full application name.");
            return;
        }
        busy = "chat";
        send({action: "chat", text: text});
    }

    IpcHandler {
        target: "luma"
        function open(): void { root.open(""); }
        function ask(text: string): void { root.open(text); }
        function toggle(): void { root.quickRequested(); }
        function settings(): void { root.settings(); }
    }

    Process {
        id: worker
        command: ["python3", "-B", "-u", Quickshell.shellPath("bin/luma.py")]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    var event = JSON.parse(data);
                    if (event.event === "hello") {
                        root.connected = true;
                        var requests = root.pending; root.pending = [];
                        for (var i = 0; i < requests.length; i++) worker.write(JSON.stringify(requests[i]) + "\n");
                    } else if (event.event === "status") {
                        root.catalog = event.catalog;
                        root.selectedModel = event.model;
                        root.ready = event.ready;
                        root.runtimeReady = event.runtime_ready;
                        root.loaded = event.loaded;
                        root.busy = event.busy;
                    } else if (event.event === "progress") {
                        root.stage = event.stage;
                        root.progress = event.total > 0 ? Math.min(1, event.done / event.total) : 0;
                    } else if (event.event === "history") {
                        root.conversations = event.conversations; root.currentConversation = event.current;
                    } else if (event.event === "messages") {
                        root.messages = event.messages; root.response = "";
                    } else if (event.event === "token") root.response = event.text;
                    else if (event.event === "error") root.error = event.message;
                    else if (event.event === "done") { root.busy = ""; root.response = ""; }
                } catch (e) { root.error = "Could not read the Luma AI response."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("[luma]", text.trim()) }
        onExited: {
            root.connected = false; root.busy = ""; root.ready = false;
            root.pending = []; root.response = "";
        }
    }
    Loader {
        id: panel
        active: false
        sourceComponent: LumaWindow { controller: root; hub: root.hub }
    }
}
