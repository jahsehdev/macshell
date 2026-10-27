import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: desktop
    required property var widgets
    property string directoryOverride: ""
    property string stateOverride: ""
    property string directory: ""
    property bool ready: false
    property bool busy: false
    property string busyAction: ""
    property string message: ""
    property bool messageIsError: false
    property var sourceItems: []
    property var items: []
    property int overflowCount: 0
    property var selected: []
    property real screenWidth: 1280
    property real screenHeight: 800
    readonly property int iconWidth: 104
    readonly property int iconHeight: 108
    readonly property int pitch: 116
    readonly property int layoutRevision: widgets.rev
    property bool arranging: false
    signal renameRequested(string name)

    function tell(text, error) {
        messageIsError = error === true;
        message = text;
        clearMessage.restart();
    }
    Timer { id: clearMessage; interval: 6000; onTriggered: desktop.message = "" }

    function send(request) {
        if (!worker.running || !ready) {
            tell("The desktop service is starting. Please try again.", true);
            return;
        }
        worker.write(JSON.stringify(request) + "\n");
    }

    function overlaps(a, b) {
        return a.x < b.x + b.width && a.x + a.width > b.x
            && a.y < b.y + b.height && a.y + a.height > b.y;
    }
    function intersectsWidgets(rect) {
        for (var i = 0; i < widgets.model.count; ++i) {
            var w = widgets.model.get(i), d = widgets.dims(w.wsize);
            if (overlaps(rect, { x: w.wx, y: w.wy, width: d[0] + 8, height: d[1] + 8 })) return true;
        }
        return false;
    }
    function intersectsIcons(x, y, width, height) {
        var rect = { x: x, y: y, width: width, height: height };
        for (var i = 0; i < items.length; ++i)
            if (overlaps(rect, { x: items[i].x, y: items[i].y, width: iconWidth, height: iconHeight })) return true;
        return false;
    }

    function arrange(cleanup) {
        if (arranging || !ready || screenWidth < 160 || screenHeight < 220) return;
        arranging = true;
        var slots = [], output = [], used = [], overflow = 0;
        var cols = Math.max(1, Math.floor((screenWidth - 40) / pitch));
        var rows = Math.max(1, Math.floor((screenHeight - 156) / pitch));
        for (var c = 0; c < cols; ++c)
            for (var r = 0; r < rows; ++r) {
                var rect = { x: screenWidth - 24 - iconWidth - c * pitch, y: 52 + r * pitch,
                             width: iconWidth, height: iconHeight };
                if (!intersectsWidgets(rect)) slots.push(rect);
            }
        // Preserve existing places before assigning new files to the right.
        var ordered = sourceItems.slice().sort(function(a, b) {
            return Number(!!b.position && !cleanup) - Number(!!a.position && !cleanup);
        });
        for (var i = 0; i < ordered.length; ++i) {
            var file = ordered[i], best = -1, distance = Infinity;
            for (var s = 0; s < slots.length; ++s) {
                if (used[s]) continue;
                if (!file.position || cleanup) { best = s; break; }
                var dx = slots[s].x - file.position.x, dy = slots[s].y - file.position.y;
                if (dx * dx + dy * dy < distance) { distance = dx * dx + dy * dy; best = s; }
            }
            if (best < 0) { overflow++; continue; }
            var at = slots[best];
            used[best] = true;
            var entry = Object.assign({}, file, { x: at.x, y: at.y });
            file.position = { x: at.x, y: at.y };
            output.push(entry);
        }
        items = output;
        overflowCount = overflow;
        arranging = false;
        savePositions.restart();
    }
    onScreenWidthChanged: arrange(false)
    onScreenHeightChanged: arrange(false)
    onLayoutRevisionChanged: arrange(false)

    function move(name, x, y) {
        for (var i = 0; i < sourceItems.length; ++i)
            if (sourceItems[i].name === name) sourceItems[i].position = { x: x, y: y };
        // Give the moved icon first choice of its new grid cell.
        sourceItems = sourceItems.slice().sort(function(a, b) {
            return Number(b.name === name) - Number(a.name === name);
        });
        arrange(false);
    }

    Timer {
        id: savePositions
        interval: 250
        onTriggered: {
            var positions = {};
            for (var i = 0; i < desktop.items.length; ++i)
                positions[desktop.items[i].name] = { x: desktop.items[i].x, y: desktop.items[i].y };
            desktop.send({ action: "positions", positions: positions });
        }
    }

    function select(name, additive) {
        if (additive) {
            var next = selected.slice(), index = next.indexOf(name);
            if (index < 0) next.push(name); else next.splice(index, 1);
            selected = next;
        } else selected = [name];
    }
    function selectRectangle(x, y, width, height, original) {
        var names = original.slice(), rect = { x: x, y: y, width: width, height: height };
        for (var i = 0; i < items.length; ++i)
            if (overlaps(rect, { x: items[i].x, y: items[i].y, width: iconWidth, height: iconHeight })
                    && names.indexOf(items[i].name) < 0) names.push(items[i].name);
        selected = names;
    }
    function open(name) {
        for (var i = 0; i < items.length; ++i) if (items[i].name === name) {
            Quickshell.execDetached([items[i].directory ? Quickshell.env("HOME") + "/.local/bin/macshell-files" : "xdg-open", items[i].path]);
            break;
        }
    }
    function trashSelected() { if (selected.length) send({ action: "trash", names: selected }); }
    function copyUrls(urls) {
        var values = [];
        for (var i = 0; i < urls.length; ++i) values.push(urls[i].toString());
        if (values.length) send({ action: "copy", urls: values });
    }
    function openFolder() { if (directory) Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/macshell-files", directory]); }

    Process {
        id: worker
        command: {
            var args = ["python3", "-u", decodeURIComponent(Qt.resolvedUrl("bin/desktop_files.py").toString().replace("file://", ""))];
            if (desktop.directoryOverride) args.push("--desktop", desktop.directoryOverride);
            if (desktop.stateOverride) args.push("--state", desktop.stateOverride);
            return args;
        }
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    var event = JSON.parse(data);
                    if (event.event === "files") {
                        desktop.directory = event.directory;
                        desktop.sourceItems = event.items;
                        desktop.ready = true;
                        desktop.selected = desktop.selected.filter(function(name) {
                            return event.items.some(function(file) { return file.name === name; });
                        });
                        desktop.arrange(false);
                    } else if (event.event === "busy") { desktop.busy = true; desktop.busyAction = event.action; }
                    else if (event.event === "result") {
                        desktop.busy = false;
                        if (event.names && event.names.length) desktop.selected = event.names;
                        if (event.error) desktop.tell(event.error, true);
                        else if (event.message) desktop.tell(event.message, false);
                        if (event.action === "mkdir" && event.names) desktop.renameRequested(event.names[0]);
                    }
                } catch (error) { console.warn("[macdesktop]", error); }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("[macdesktop]", text.trim()) }
        onExited: (code, status) => {
            desktop.ready = false;
            desktop.busy = false;
            if (code !== 0) desktop.tell("The desktop file service stopped. Retrying…", true);
            restartWorker.restart();
        }
    }
    Timer { id: restartWorker; interval: 3000; onTriggered: worker.running = true }
}
