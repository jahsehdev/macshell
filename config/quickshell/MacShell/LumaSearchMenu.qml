pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    required property var controller
    property var hub: null
    property bool opened: false
    property string activeScreen: ""
    Binding { target: root.hub; property: "searchWantsGeo"; value: root.opened; when: root.hub !== null }

    function open() {
        if (opened) { refocus(); return; }
        controller.closeQuickRequested();
        const monitor = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        activeScreen = monitor ? monitor.name : (screens.length ? screens[0].name : "");
        if (!activeScreen) return;
        if (hub) hub.refreshWallpaper();
        controller.refresh();
        opened = true;
        focusDelay.restart();
    }
    function close() { opened = false; }
    function toggle() { if (opened) close(); else open(); }
    signal refocus()
    Timer { id: focusDelay; interval: 0; onTriggered: root.refocus() }
    Connections {
        target: root.controller
        function onQuickRequested() { root.toggle(); }
        function onCloseQuickRequested() { root.close(); }
    }
    IpcHandler {
        target: "lumasearch"
        function toggle(): void { root.toggle(); }
        function open(): void { root.open(); }
        function close(): void { root.close(); }
    }
    // Personal-context results for Search or Ask (A3/GG-04): while the user
    // types, query bin/context.py for enabled Notes/Calendar/file matches.
    // Rows keep their provenance; disabled sources are already excluded by
    // the bridge CLI, so nothing here can surface data the user turned off.
    Item {
        id: contextSearch
        property var results: []
        property bool searching: false
        property bool pendingRun: false
        readonly property string ctxPy: Quickshell.shellPath("bin/context.py")
        function schedule() {
            const q = root.controller.draft.trim();
            if (q.length < 2) {
                pendingRun = false;
                results = [];
                searching = false;
                return;
            }
            debounce.restart();
        }
        function run(q) {
            if (q.length < 2) { results = []; searching = false; return; }
            if (ctxProc.running) { pendingRun = true; return; }
            searching = true;
            results = [];
            ctxProc.args = ["search", "--query", q, "--limit", "5"];
            ctxProc.running = true;
        }
        function finish(raw) {
            searching = false;
            const parsed = parse(raw);
            // A late answer for an older draft is dropped; typing already
            // scheduled a fresh search.
            if (!parsed || parsed.error || parsed.query !== root.controller.draft.trim()) {
                results = [];
                return;
            }
            results = parsed.results || [];
        }
        function parse(text) {
            try { return JSON.parse(text || ""); } catch (err) { return null; }
        }
        function activate(result) {
            if (!result) return;
            if (result.kind === "notes")
                Quickshell.execDetached(["qs", "-c", "MacShell", "ipc", "call", "notes", "open"]);
            else if (result.kind === "calendar") {
                Quickshell.execDetached(["qs", "-c", "MacShell", "ipc", "call", "calendar", "open"]);
            } else if (result.kind === "files") {
                Quickshell.execDetached(["xdg-open", String(result.ref)]);
            }
            else if (result.kind === "mail") Quickshell.execDetached(["qs", "-c", "MacShell", "ipc", "call", "mail", "open"]);
            root.close();
        }
        Timer {
            id: debounce
            interval: 250
            onTriggered: contextSearch.run(root.controller.draft.trim())
        }
        Connections {
            target: root.controller
            function onDraftChanged() { contextSearch.schedule(); }
        }
        Connections {
            target: root
            function onOpenedChanged() {
                if (root.opened) contextSearch.schedule();
                else { contextSearch.results = []; contextSearch.searching = false; }
            }
        }
        Process {
            id: ctxProc
            property var args: []
            command: ["python3", "-B", contextSearch.ctxPy].concat(ctxProc.args)
            stdout: StdioCollector { onStreamFinished: contextSearch.finish(text) }
            onExited: {
                contextSearch.searching = false;
                if (contextSearch.pendingRun) {
                    contextSearch.pendingRun = false;
                    contextSearch.run(root.controller.draft.trim());
                }
            }
        }
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool selected: root.opened && root.activeScreen === modelData.name
            onSelectedChanged: if (selected && content.item) content.item.resetMessages()
            readonly property bool openish: selected || menu.opacity > 0.001
            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            mask: Region { item: win.openish ? frame : noInput }
            WlrLayershell.namespace: "maclumasearch"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: selected ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            Item { id: noInput; width: 0; height: 0 }
            Item {
                id: frame
                anchors.fill: parent
                Loader {
                    id: liveBackdrop
                    active: menu.primed
                    visible: win.openish
                    sourceComponent: LumaSearchBackdrop {
                        hub: root.hub; monitor: win.modelData
                        region: Qt.rect(menu.x - 128, menu.y - 128, menu.width + 256, menu.height + 256)
                        wallpaper: root.hub && root.hub.widgets ? root.hub.widgets.fileUrl(root.hub.widgets.wallpaperFor(win.modelData.name)) : ""
                    }
                }
                MouseArea {
                    anchors.fill: parent; enabled: win.selected
                    acceptedButtons: Qt.AllButtons
                    onPressed: root.close()
                }
                Item {
                    id: menu
                    property bool primed: false
                    width: Math.min(380, frame.width - 48)
                    height: content.item ? content.item.height : 60
                    x: Math.round((frame.width - width) / 2)
                    // Hang the search bar under the menu bar with a breathing gap
                    // instead of centring it on the desktop. The mic orb grows
                    // around the same centre, so it keeps a smaller gap (half of
                    // the diameter difference).
                    readonly property int menuBarHeight: root.hub && root.hub.bar ? root.hub.bar.barHeight : 28
                    readonly property int topGap: 32
                    y: Math.min(menuBarHeight + topGap,
                                Math.max(24, Math.round(frame.height - height - 24)))
                    opacity: 0
                    scale: 0.985
                    transformOrigin: Item.Center
                    visible: win.selected || opacity > 0.001
                    enabled: win.selected
                    state: win.selected && content.status === Loader.Ready ? "open" : ""
                    states: State {
                        name: "open"
                        PropertyChanges { target: menu; opacity: 1; scale: 1 }
                    }
                    transitions: [
                        Transition {
                            to: "open"
                            NumberAnimation { property: "opacity"; duration: (root.hub && root.hub.dock && root.hub.dock.reduceMotion ? 0 : 55); easing.type: Easing.OutCubic }
                            NumberAnimation { property: "scale"; duration: (root.hub && root.hub.dock && root.hub.dock.reduceMotion ? 0 : 85); easing.type: Easing.OutCubic }
                        },
                        Transition {
                            from: "open"; to: ""
                            NumberAnimation { properties: "opacity,scale"; duration: (root.hub && root.hub.dock && root.hub.dock.reduceMotion ? 0 : 70); easing.type: Easing.OutCubic }
                        }
                    ]
                    // Keep the shader/blur chain after its first use, including
                    // rapid reversals. Hidden backdrop captures are paused above.
                    Connections {
                        target: win
                        function onSelectedChanged() { if (win.selected) menu.primed = true; }
                    }
                    Component.onCompleted: if (win.selected) primed = true
                    MouseArea { anchors.fill: parent }
                    Item {
                        // Give the glass rim real space in the composed layer.
                        // Enlarging sourceRect instead would squeeze its texture
                        // into the menu's smaller bounds, distorting the capsule.
                        id: surface
                        x: -48; y: -48
                        width: menu.width + 96; height: menu.height + 96
                        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                        layer.smooth: true
                        Loader {
                            id: content
                            onLoaded: if (win.selected) Qt.callLater(function() { if (content.item) content.item.focusInput(); })
                            x: 48; y: 48
                            width: menu.width; active: menu.primed
                            sourceComponent: LumaSearchView {
                                width: menu.width; controller: root.controller
                                microphoneAllowed: win.selected
                                backdrop: liveBackdrop.item
                                screenSize: Qt.size(frame.width, frame.height)
                                screenPosition: Qt.point(menu.x, menu.y)
                                fontFamily: root.hub && root.hub.dock ? root.hub.dock.fontFamily : "sans-serif"
                                wallpaper: root.hub && root.hub.widgets ? root.hub.widgets.fileUrl(root.hub.widgets.wallpaperFor(win.modelData.name)) : ""
                                maxBodyHeight: Math.max(100, Math.min(360, frame.height / 2 - 100))
                                contextResults: contextSearch.results
                                contextSearching: contextSearch.searching
                                onContextResultActivated: result => contextSearch.activate(result)
                                onDismissed: root.close()
                                onFullRequested: { root.close(); root.controller.open(""); }
                                onSettingsRequested: { root.close(); root.controller.settings(); }
                            }
                        }
                    }
                }
            }
            Connections {
                target: root
                function onRefocus() { if (win.selected && content.item) content.item.focusInput(); }
            }
        }
    }
}
