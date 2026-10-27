pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../Common" as Common

// ─────────────────────────────────────────────────────────────────────────────
//  LaunchpadState — the data + interaction brain of the Launchpad.
//
//  * applications come from Quickshell's DesktopEntries singleton
//  * the user's layout is persisted in
//      ~/.local/state/quickshell/launchpad/layout.json
//  * search, paging, selection, folders and edit mode live here so every
//    component can talk to one source of truth.
// ─────────────────────────────────────────────────────────────────────────────
Scope {
    id: root

    // ── window / animation state ──────────────────────────────────────────────
    property bool shown: false
    property bool windowVisible: false
    property bool ready: false
    property bool mockMode: Theme.mockMode
    Connections {
        target: Common.AppMenu
        function onModeChanged() { if (Common.AppMenu.spotlight) root.dismiss(); }
    }

    property real lastMenuDismissRequest: Date.now()
    FileView {
        id: menuDismissRequest
        path: Theme.stateDir + "/menu-dismiss-request.json"
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const request = JSON.parse(text());
                if (Number(request.updated) <= root.lastMenuDismissRequest) return;
                root.lastMenuDismissRequest = Number(request.updated);
                root.dismiss();
            } catch (error) {
                console.warn("launchpad: cannot read menu dismiss request:", error);
            }
        }
    }

    FileView {
        id: dockVisibility
        path: Theme.stateDir + "/dock-visibility.json"
        printErrors: false
    }
    function syncDockVisibility() {
        dockVisibility.setText(JSON.stringify({ hideDock: shown && !Theme.showDock, updated: Date.now() }));
    }
    Timer {
        interval: 1000
        running: root.shown && !Theme.showDock
        repeat: true
        onTriggered: root.syncDockVisibility()
    }
    FileView {
        id: glassBackdropState
        path: Theme.stateDir + "/glass-backdrop.json"
        printErrors: false
    }
    function syncGlassBackdrop() {
        const monitor = Hyprland.focusedMonitor;
        const screen = monitor ? monitor.name : (Quickshell.screens.length ? Quickshell.screens[0].name : "");
        glassBackdropState.setText(JSON.stringify({ active: windowVisible, screen: screen, updated: Date.now() }));
    }
    Timer {
        interval: 1000
        running: root.windowVisible
        repeat: true
        onTriggered: root.syncGlassBackdrop()
    }
    onWindowVisibleChanged: syncGlassBackdrop()
    onShownChanged: syncDockVisibility()
    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() { root.syncGlassBackdrop(); }
    }
    Connections {
        target: Theme
        function onShowDockChanged() { root.syncDockVisibility(); }
    }

    // ── "Add to Dock" (Launchpad right-click menu) ────────────────────────────
    // Writing straight into the Dock's pinned.json would race the Dock's own
    // saves, so a small request file is dropped here (same pattern as
    // dock-visibility.json) and MacDock picks it up.
    FileView {
        id: dockPinRequest
        path: Theme.stateDir + "/dock-pin-request.json"
        printErrors: false
    }
    function addToDock(item) {
        if (!item || item.kind !== "app" || !item.id)
            return;
        dockPinRequest.setText(JSON.stringify({ id: item.id, updated: Date.now() }));
    }
    // Watch the Dock's pins so the menu can disable the action once the app is
    // already in the Dock.
    property var dockPins: []
    FileView {
        id: dockPinStore
        path: Quickshell.env("HOME") + "/.config/macdock/pinned.json"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const a = JSON.parse(text());
                if (Array.isArray(a)) root.dockPins = a;
            } catch (e) {
                // Keep the last known pins during an incomplete write.
            }
        }
    }
    function appPinnedInDock(item) {
        if (!item || item.kind !== "app") return false;
        const key = String(item.id).replace(/\.desktop$/, "").toLowerCase();
        for (let i = 0; i < dockPins.length; ++i)
            if (String(dockPins[i]).replace(/\.desktop$/, "").toLowerCase() === key)
                return true;
        return false;
    }

    // ── layout ────────────────────────────────────────────────────────────────
    property var pages: [[]]
    property var hidden: []
    property var usage: ({})
    property string sortMode: "manual"
    property bool layoutDirty: false
    property string layoutSaveError: ""
    property bool layoutReloadBeforeSave: false

    // ── view state ────────────────────────────────────────────────────────────
    property string query: ""
    property var results: []
    property var viewItems: []
    property int page: 0
    property int pageCount: 1
    property int pageDirection: 1
    property int selected: 0
    property int hoverIndex: -1
    // macOS shows no selection plate until the pointer or keyboard is used.
    property bool selectionVisible: false

    // ── overlays ──────────────────────────────────────────────────────────────
    property bool settingsOpen: false
    property bool editMode: false
    property bool folderOpen: false
    property var foldered: null
    property rect folderOrigin: Qt.rect(0, 0, 0, 0)
    property var menu: null
    property var drag: null
    property int dropIndex: -1
    property rect gridRect: Qt.rect(0, 0, 0, 0)
    property string launchId: ""
    property bool folderRemovalBusy: false
    property string justDroppedId: ""
    Timer { id: justDroppedTimer; interval: 400; onTriggered: root.justDroppedId = "" }

    readonly property bool searching: query.trim().length > 0
    readonly property var currentItem: (selected >= 0 && selected < viewItems.length) ? viewItems[selected] : null

    // ═════════════════════════════════════════════════════════════════════════
    //  lifecycle
    // ═════════════════════════════════════════════════════════════════════════
    Component.onCompleted: {
        desktopEntriesTimer.restart();
        mockMode = Theme.mockMode;
        load();
        ready = true;
        if (mockMode) {
            pages = buildMockPages();
            refreshView();
        } else {
            rebuild();
        }
    }

    // DesktopEntries is populated asynchronously (and changes when apps are
    // installed / removed). Merge the new state without losing the layout.
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            desktopEntriesTimer.restart();
        }
    }
    property bool desktopEntriesSettled: false
    Timer {
        id: desktopEntriesTimer
        interval: 250
        onTriggered: {
            root.desktopEntriesSettled = true;
            if (root.awaitingDesktopEntries) root.load();
            root.rebuild();
            reflowTimer.restart();
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  persistence
    // ═════════════════════════════════════════════════════════════════════════
    property bool _loadedFromDisk: false
    property bool awaitingDesktopEntries: false

    FileView {
        id: layoutFile
        atomicWrites: true
        blockWrites: true
        onSaveFailed: {
            root.layoutSaveError = "Could not save the app layout. Please try again.";
            root.layoutReloadBeforeSave = true;
            root.layoutDirty = true;
        }
        path: Theme.stateDir + "/layout.json"
        preload: true
        blockLoading: true
        printErrors: false
    }

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", Theme.stateDir]
        running: true
    }

    Timer {
        id: saveTimer
        interval: 500
        repeat: false
        onTriggered: root.saveNow()
    }

    function saveSoon() {
        if (mockMode || awaitingDesktopEntries)
            return;
        layoutDirty = true;
        saveTimer.restart();
    }

    function saveNow() {
        if (!ready || mockMode)
            return true;
        if (awaitingDesktopEntries) return false;
        layoutSaveError = "";
        if (layoutReloadBeforeSave) { layoutFile.reload(); layoutFile.waitForJob(); layoutReloadBeforeSave = false; }
        const data = {
            version: 1,
            sortMode: sortMode,
            pages: pages.map(function (page) {
                return page.map(serializeItem);
            }),
            hidden: hidden,
            usage: usage
        };
        try {
            layoutFile.setText(JSON.stringify(data, null, 2));
            if (layoutSaveError !== "") return false;
            layoutDirty = false;
            return true;
        } catch (e) {
            layoutSaveError = "Could not save the app layout. Please try again.";
            layoutReloadBeforeSave = true;
            return false;
        }
    }

    function serializeItem(item) {
        if (!item)
            return null;
        if (item.kind === "folder")
            return { type: "folder", name: item.name, items: item.items.map(function (it) { return it.id; }) };
        if (item.kind === "app")
            return { type: "app", id: item.id };
        return null;
    }

    function load() {
        const txt = layoutFile.text();
        if (!txt || txt.trim() === "") {
            _loadedFromDisk = false;
            return;
        }
        try {
            const data = JSON.parse(txt);
            _loadedFromDisk = true;
            hidden = Array.isArray(data.hidden) ? data.hidden.slice() : [];
            usage = data.usage && typeof data.usage === "object" ? data.usage : ({});
            sortMode = data.sortMode || "manual";
            if (Array.isArray(data.pages)) {
                // DesktopEntries is asynchronous. Keep the persisted structure
                // until ids can be resolved, and never save an empty substitute.
                const entries = DesktopEntries.applications ? DesktopEntries.applications.values : [];
                if ((!desktopEntriesSettled || entries.length === 0)
                        && data.pages.some(p => Array.isArray(p) && p.length > 0)) {
                    awaitingDesktopEntries = true;
                    if (!desktopEntriesSettled) desktopEntriesTimer.restart();
                    return;
                }
                awaitingDesktopEntries = false;
                const restored = [];
                for (let p = 0; p < data.pages.length; ++p) {
                    const items = [];
                    const raw = data.pages[p];
                    if (!Array.isArray(raw))
                        continue;
                    for (let i = 0; i < raw.length; ++i) {
                        const it = raw[i];
                        if (!it)
                            continue;
                        if (it.type === "app") {
                            const entry = entryById(it.id);
                            if (entry && !entry.noDisplay && hidden.indexOf(it.id) < 0)
                                items.push(appItem(entry));
                        } else if (it.type === "folder") {
                            const children = [];
                            const ids = Array.isArray(it.items) ? it.items : [];
                            for (let k = 0; k < ids.length; ++k) {
                                const entry = entryById(ids[k]);
                                if (entry && !entry.noDisplay && hidden.indexOf(ids[k]) < 0)
                                    children.push(appItem(entry));
                            }
                            if (children.length > 0)
                                items.push(folderItem(it.name || "Folder", children));
                        }
                    }
                    restored.push(items);
                }
                if (restored.length > 0)
                    pages = restored;
            }
        } catch (e) {
            console.warn("launchpad: layout.json is not valid JSON, rebuilding:", e);
            _loadedFromDisk = false;
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  application data
    // ═════════════════════════════════════════════════════════════════════════
    function entryById(id) {
        const values = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        for (let i = 0; i < values.length; ++i) {
            if (values[i] && values[i].id === id)
                return values[i];
        }
        return null;
    }

    function visibleEntries() {
        const values = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        const out = [];
        const seen = {};
        for (let i = 0; i < values.length; ++i) {
            const e = values[i];
            if (!e || !e.id || !e.name)
                continue;
            if (e.noDisplay)
                continue;
            if (hidden.indexOf(e.id) >= 0)
                continue;
            if (seen[e.id])
                continue;
            seen[e.id] = true;
            out.push(e);
        }
        out.sort(function (a, b) { return a.name.toLowerCase().localeCompare(b.name.toLowerCase()); });
        return out;
    }

    function appItem(entry) {
        return {
            kind: "app",
            id: entry.id,
            name: entry.name,
            icon: entry.icon || "",
            entry: entry
        };
    }

    function folderItem(name, children) {
        return {
            kind: "folder",
            id: "__folder__" + name,
            name: name,
            items: children
        };
    }

    function categoryList(entry) {
        const raw = entry.categories;
        const parts = Array.isArray(raw) ? raw : [raw];
        const out = [];
        for (let i = 0; i < parts.length; ++i) {
            const bits = String(parts[i] || "").split(/[,;]/);
            for (let k = 0; k < bits.length; ++k) {
                const c = bits[k].trim();
                if (c !== "")
                    out.push(c);
            }
        }
        return out;
    }

    function hasCategory(entry, names) {
        const cats = categoryList(entry);
        for (let i = 0; i < cats.length; ++i) {
            if (names.indexOf(cats[i]) >= 0)
                return true;
        }
        return false;
    }

    function pack(items) {
        const size = Theme.pageSize;
        const out = [];
        for (let i = 0; i < items.length; i += size)
            out.push(items.slice(i, i + size));
        if (out.length === 0)
            out.push([]);
        return out;
    }

    function buildDefault() {
        if (mockMode) {
            pages = buildMockPages();
            refreshView();
            return;
        }
        const entries = visibleEntries();
        if (entries.length === 0) {
            pages = [[]];
            refreshView();
            return;
        }

        const utilCats = ["System", "Utility", "Settings", "Monitor", "TerminalEmulator",
                          "FileManager", "DesktopSettings"];
        const otherCats = ["Development", "Building", "AudioVideo", "ConsoleOnly"];

        const top = [];
        const utils = [];
        const others = [];

        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            const cats = categoryList(e);
            if (hasCategory(e, utilCats))
                utils.push(e);
            else if (cats.length === 0 || hasCategory(e, otherCats))
                others.push(e);
            else
                top.push(e);
        }

        const items = top.map(appItem);
        if (Theme.autoFolders) {
            // Automatic folders, but never let them swallow the whole first
            // page: a folder is only created while at least one full row of
            // top-level tiles (columns) remains. With a small app list this
            // keeps the grid readable; with a large one the folders appear.
            const groups = [];
            if (others.length >= 3)
                groups.push({ name: "Other", entries: others });
            if (utils.length >= 2)
                groups.push({ name: "Utilities", entries: utils });
            groups.sort(function (a, b) { return b.entries.length - a.entries.length; });

            const minTopLevel = Math.max(4, Math.floor(Theme.columns / 2));
            let topLevel = items.length;
            for (let g = 0; g < groups.length; ++g) {
                const grp = groups[g];
                if (topLevel - grp.entries.length + 1 >= minTopLevel) {
                    items.push(folderItem(grp.name, grp.entries.map(appItem)));
                    topLevel = topLevel - grp.entries.length + 1;
                } else {
                    for (let k = 0; k < grp.entries.length; ++k)
                        items.push(appItem(grp.entries[k]));
                    topLevel += grp.entries.length;
                }
            }
        } else {
            for (let i = 0; i < entries.length; ++i) {
                if (top.indexOf(entries[i]) < 0)
                    items.push(appItem(entries[i]));
            }
        }

        pages = pack(items);
        refreshView();
        saveSoon();
    }

    function rebuild() {
        if (!ready || awaitingDesktopEntries || !desktopEntriesSettled)
            return;
        if (mockMode) {
            pages = buildMockPages();
            refreshView();
            return;
        }

        const entries = visibleEntries();
        if (entries.length === 0) {
            pages = [[]];
            refreshView();
            return;
        }

        if (!_loadedFromDisk && pages.length <= 1 && (!pages[0] || pages[0].length === 0)) {
            buildDefault();
            return;
        }

        const map = {};
        for (let i = 0; i < entries.length; ++i)
            map[entries[i].id] = entries[i];

        const placed = {};
        const next = [];

        for (let p = 0; p < pages.length; ++p) {
            const out = [];
            const page = pages[p] || [];
            for (let i = 0; i < page.length; ++i) {
                const item = page[i];
                if (!item)
                    continue;
                if (item.kind === "app") {
                    const e = map[item.id];
                    if (e) {
                        out.push(appItem(e));
                        placed[e.id] = true;
                    }
                } else if (item.kind === "folder") {
                    const kids = [];
                    const src = item.items || [];
                    for (let k = 0; k < src.length; ++k) {
                        const e = map[src[k].id];
                        if (e) {
                            kids.push(appItem(e));
                            placed[e.id] = true;
                        }
                    }
                    if (kids.length > 0)
                        out.push(folderItem(item.name, kids));
                }
            }
            next.push(out);
        }

        if (next.length === 0)
            next.push([]);

        // append apps installed after the layout was written
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (placed[e.id])
                continue;
            let last = next[next.length - 1];
            if (last.length >= Theme.pageSize) {
                last = [];
                next.push(last);
            }
            last.push(appItem(e));
            placed[e.id] = true;
        }

        pages = next;
        refreshView();
        if (next.some(function (p) { return p.length > 0; }))
            saveSoon();
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  view / search
    // ═════════════════════════════════════════════════════════════════════════
    function refreshView() {
        if (searching) {
            const size = Theme.pageSize;
            pageCount = Math.max(1, Math.ceil(results.length / size));
            if (page >= pageCount)
                page = pageCount - 1;
            viewItems = results.slice(page * size, (page + 1) * size);
        } else {
            pageCount = Math.max(1, pages.length);
            if (page >= pageCount)
                page = pageCount - 1;
            if (page < 0)
                page = 0;
            viewItems = pages[page] || [];
        }
        if (selected >= viewItems.length)
            selected = Math.max(0, viewItems.length - 1);
        if (selected < 0)
            selected = 0;
    }

    // Reflow existing items in order when the focused screen changes size.
    Timer {
        id: reflowTimer
        property bool forceRepack: false
        interval: 0
        onTriggered: {
            if (!root.ready || root.awaitingDesktopEntries || !root.desktopEntriesSettled) return;
            // Preserve valid partial pages on startup. Repacking them would
            // move an explicitly dropped app to another page after a restart.
            if (forceRepack || root.pages.some(p => p.length > Theme.pageSize)) {
                const items = [].concat.apply([], root.pages);
                root.pages = root.pack(items);
            }
            forceRepack = false;
            root.hoverIndex = -1;
            root.refreshView();
            root.saveSoon();
        }
    }
    onReadyChanged: reflowTimer.restart()
    Connections {
        target: Theme
        function onPageSizeChanged() {
            if (root.desktopEntriesSettled && !root.awaitingDesktopEntries) reflowTimer.forceRepack = true;
            reflowTimer.restart();
        }
    }

    onPagesChanged: refreshView()
    onPageChanged: refreshView()
    onResultsChanged: refreshView()

    onQueryChanged: {
        if (query.trim() === "") {
            results = [];
        } else {
            computeResults();
        }
        page = 0;
        selected = 0;
        hoverIndex = -1;
        selectionVisible = false;
        refreshView();
    }

    function setQuery(q) {
        if (query === q)
            return;
        query = q;
    }

    function allAppsFlat() {
        const out = [];
        const seen = {};
        function add(item) {
            if (!item || item.kind !== "app" && item.kind !== "mock")
                return;
            if (seen[item.id])
                return;
            seen[item.id] = true;
            out.push(item);
        }
        for (let p = 0; p < pages.length; ++p) {
            const page = pages[p] || [];
            for (let i = 0; i < page.length; ++i) {
                const item = page[i];
                if (item.kind === "folder") {
                    for (let k = 0; k < item.items.length; ++k)
                        add(item.items[k]);
                } else {
                    add(item);
                }
            }
        }
        return out;
    }

    function isSubsequence(needle, haystack) {
        if (needle.length === 0)
            return true;
        let j = 0;
        for (let i = 0; i < haystack.length && j < needle.length; ++i) {
            if (haystack[i] === needle[j])
                ++j;
        }
        return j === needle.length;
    }

    function score(item, q) {
        if (item.kind === "mock")
            return item.name.toLowerCase().indexOf(q) >= 0 ? 500 : -1;
        const entry = item.entry;
        if (!entry)
            return -1;
        const name = String(entry.name || "").toLowerCase();
        const generic = String(entry.genericName || "").toLowerCase();
        const keywords = (Array.isArray(entry.keywords) ? entry.keywords.join(" ") : String(entry.keywords || "")).toLowerCase();
        const id = String(entry.id || "").toLowerCase();

        if (name === q)
            return 1200;
        if (name.indexOf(q) === 0)
            return 1000;
        const words = name.split(/[\s\-_.]+/);
        for (let i = 0; i < words.length; ++i) {
            if (words[i].indexOf(q) === 0)
                return 850;
        }
        if (name.indexOf(q) >= 0)
            return 650;
        if (generic.indexOf(q) >= 0 || keywords.indexOf(q) >= 0)
            return 450;
        if (id.indexOf(q) >= 0)
            return 350;
        if (isSubsequence(q, name))
            return 220;
        return -1;
    }

    function computeResults() {
        const q = query.trim().toLowerCase();
        const all = allAppsFlat();
        const scored = [];
        for (let i = 0; i < all.length; ++i) {
            const s = score(all[i], q);
            if (s >= 0)
                scored.push({ item: all[i], score: s });
        }
        scored.sort(function (a, b) {
            if (b.score !== a.score)
                return b.score - a.score;
            const ua = root.usage[a.item.id] || 0;
            const ub = root.usage[b.item.id] || 0;
            if (ub !== ua)
                return ub - ua;
            return a.item.name.toLowerCase().localeCompare(b.item.name.toLowerCase());
        });
        results = scored.map(function (x) { return x.item; });
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  navigation
    // ═════════════════════════════════════════════════════════════════════════
    function setPage(p) {
        const n = Math.max(0, Math.min(pageCount - 1, p));
        if (n === page)
            return;
        pageDirection = n > page ? 1 : -1;
        page = n;
        selected = 0;
        hoverIndex = -1;
    }

    function moveSelection(dx, dy) {
        if (viewItems.length === 0)
            return;
        selectionVisible = true;
        const cols = Theme.columns;
        let idx = selected;

        if (dx !== 0) {
            let n = idx + dx;
            if (n < 0) {
                if (page > 0) {
                    pageDirection = -1;
                    page = page - 1;
                    selected = Math.max(0, viewItems.length - 1);
                }
            } else if (n >= viewItems.length) {
                if (page < pageCount - 1) {
                    pageDirection = 1;
                    page = page + 1;
                    selected = 0;
                }
            } else {
                selected = n;
            }
        }

        if (dy !== 0) {
            const n = idx + dy * cols;
            if (n >= 0 && n < viewItems.length) {
                selected = n;
            } else if (dy < 0 && page > 0) {
                const prevCount = Theme.pageSize;
                pageDirection = -1;
                page = page - 1;
                selected = Math.min(prevCount - 1, Math.max(0, prevCount + n));
            } else if (dy > 0 && page < pageCount - 1) {
                pageDirection = 1;
                page = page + 1;
                selected = Math.max(0, Math.min(viewItems.length - 1, n - Theme.pageSize));
            }
        }
        hoverIndex = -1;
    }

    function activate(item) {
        if (!item)
            return;
        if (item.kind === "folder")
            openFolder(item, folderOrigin);
        else
            launch(item, true);
    }

    function launch(item, closeAfter) {
        if (!item)
            return;
        if (item.kind === "app" && item.entry) {
            const next = {};
            for (const k in usage)
                next[k] = usage[k];
            next[item.id] = (next[item.id] || 0) + 1;
            usage = next;
            try {
                item.entry.execute();
            } catch (e) {
                console.warn("launchpad: could not launch", item.name, e);
            }
            saveSoon();
        }
        if (closeAfter)
            close();
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  folders
    // ═════════════════════════════════════════════════════════════════════════
    function openFolder(item, origin) {
        if (!item || item.kind !== "folder")
            return;
        foldered = item;
        folderOrigin = origin || Qt.rect(0, 0, 0, 0);
        folderOpen = true;
        menu = null;
        selected = 0;
        hoverIndex = -1;
    }

    function closeFolder() {
        folderCloseTimer.stop();
        folderOpen = false;
        foldered = null;
        selected = 0;
        hoverIndex = -1;
    }

    // The large folder panel asks for a delayed close when the pointer leaves
    // it; hovering a folder tile (or re-entering the panel) cancels the
    // request, so switching between folders by hovering is seamless.
    function requestFolderClose() { folderCloseTimer.restart(); }
    function cancelFolderClose() { folderCloseTimer.stop(); }

    Timer {
        id: folderCloseTimer
        interval: Theme.folderCloseDelay
        repeat: false
        onTriggered: root.closeFolder()
    }

    function renameFolder(name) {
        if (!foldered)
            return;
        const clean = String(name || "").trim() || "Folder";
        const id = foldered.id;
        const next = pages.map(function (page) {
            return page.map(function (item) {
                if (item.kind === "folder" && item.id === id)
                    return folderItem(clean, item.items);
                return item;
            });
        });
        pages = next;
        foldered = folderItem(clean, foldered.items);
        saveSoon();
    }

    function hideApp(id) {
        if (!id || hidden.indexOf(id) >= 0)
            return;
        hidden = hidden.concat([id]);
        folderOpen = false;
        foldered = null;
        rebuild();
        if (searching) computeResults();
        saveSoon();
    }

    function restoreHidden(ids) {
        if (!Array.isArray(ids) || ids.length === 0) return true;
        hidden = hidden.filter(function(id) { return ids.indexOf(id) < 0; });
        rebuild();
        if (searching) computeResults();
        saveTimer.stop();
        return saveNow();
    }

    function unhideAll() {
        hidden = [];
        rebuild();
        saveSoon();
    }

    function resetLayout() {
        hidden = [];
        usage = ({});
        pages = [[]];
        _loadedFromDisk = false;
        buildDefault();
        saveNow();
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  drag & drop
    // ═════════════════════════════════════════════════════════════════════════
    Timer {
        id: dragHoverTimer
        interval: Theme.dropDelay
        repeat: false
        onTriggered: {
            if (!root.drag)
                return;
            root.drag.folderReady = true;
            root.drag = Object.assign({}, root.drag);
        }
    }

    function beginDrag(item, fromPage, fromIndex) {
        if (!item)
            return;
        drag = {
            item: item,
            fromPage: fromPage,
            fromIndex: fromIndex,
            active: true,
            x: 0,
            y: 0,
            overIndex: -1,
            overPage: -1,
            folderReady: false
        };
    }

    function updateDrag(x, y) {
        if (!drag)
            return;
        drag.x = x;
        drag.y = y;
        drag = Object.assign({}, drag);
    }

    function updateDropTarget(x, y) {
        if (!drag)
            return;
        let idx = -1;
        const g = gridRect;
        if (x >= g.x && x <= g.x + g.width && y >= g.y && y <= g.y + g.height) {
            const col = Math.floor((x - g.x) / Theme.pitch);
            const row = Math.floor((y - g.y) / Theme.pitch);
            if (col >= 0 && col < Theme.columns && row >= 0 && row < Theme.rows) {
                const n = row * Theme.columns + col;
                if (n < viewItems.length && n !== drag.fromIndex)
                    idx = n;
            }
        }
        if (idx !== dropIndex) {
            dropIndex = idx;
            drag.overIndex = idx;
            drag.overPage = page;
            drag.folderReady = false;
            drag = Object.assign({}, drag);
            dragHoverTimer.stop();
            if (idx >= 0)
                dragHoverTimer.restart();
        }
    }

    function cancelDrag() {
        dragHoverTimer.stop();
        drag = null;
        dropIndex = -1;
    }

    function finishDrag(x, y) {
        if (!drag)
            return;
        updateDropTarget(x, y);
        const d = drag;
        const target = dropIndex >= 0 ? viewItems[dropIndex] : null;

        if (target && target.kind === "folder" && target.id !== d.item.id) {
            addAppToFolder(d.item, d.fromPage, d.fromIndex, target);
        } else if (target && d.folderReady && target.id !== d.item.id) {
            createFolderWith(d.item, d.fromPage, d.fromIndex, target, page, dropIndex);
        } else if (dropIndex >= 0) {
            moveItem(d.fromPage, d.fromIndex, page, dropIndex);
        }
        cancelDrag();
    }

    function removeItem(fromPage, fromIndex) {
        const next = pages.map(function (p) { return p.slice(); });
        if (!next[fromPage])
            return null;
        const item = next[fromPage][fromIndex];
        if (!item)
            return null;
        next[fromPage].splice(fromIndex, 1);
        pages = next.filter(function (p, i) { return p.length > 0 || i === 0; });
        sortMode = "manual";
        refreshView();
        return item;
    }

    function moveItem(fromPage, fromIndex, toPage, toIndex) {
        let dest = toIndex;
        if (fromPage === toPage && dest > fromIndex)
            dest -= 1;
        const item = removeItem(fromPage, fromIndex);
        if (!item)
            return;
        const next = pages.map(function (p) { return p.slice(); });
        if (!next[toPage])
            next.push([]);
        next[toPage].splice(Math.max(0, Math.min(next[toPage].length, dest)), 0, item);
        pages = next;
        sortMode = "manual";
        refreshView();
        saveSoon();
    }

    function createFolderWith(itemA, pageA, indexA, itemB, pageB, indexB) {
        if (!itemA || !itemB || itemA === itemB)
            return;
        const next = pages.map(function (p) { return p.slice(); });
        const a = next[pageA] ? next[pageA][indexA] : null;
        const b = next[pageB] ? next[pageB][indexB] : null;
        if (!a || !b)
            return;
        next[pageA].splice(indexA, 1);
        const adjustedB = (pageA === pageB && indexB > indexA) ? indexB - 1 : indexB;
        next[pageB].splice(adjustedB, 1);
        const folder = folderItem("Folder", [a, b]);
        if (!next[pageA])
            next[pageA] = [];
        next[pageA].splice(Math.min(indexA, next[pageA].length), 0, folder);
        pages = next.filter(function (p, i) { return p.length > 0 || i === 0; });
        sortMode = "manual";
        refreshView();
        saveSoon();
    }

    function addAppToFolder(item, fromPage, fromIndex, folder) {
        if (!item || !folder || folder.kind !== "folder")
            return;
        const removed = removeItem(fromPage, fromIndex);
        if (!removed)
            return;
        const next = pages.map(function (page) {
            return page.map(function (it) {
                if (it.kind === "folder" && it.id === folder.id)
                    return folderItem(it.name, it.items.concat([removed]));
                return it;
            });
        });
        pages = next;
        sortMode = "manual";
        refreshView();
        saveSoon();
    }

    // Insert positions refer to the layout BEFORE folder cleanup. Only local
    // copies are spliced; observers see one complete replacement of pages.
    function listCopy(value) {
        // QML models can expose QVariantList/list<var> as V4Sequence, which is
        // indexable but deliberately fails JavaScript's Array.isArray().
        if (!value || typeof value !== "object" || !Number.isInteger(value.length) || value.length < 0)
            return null;
        return Array.prototype.slice.call(value);
    }

    function removeFromFolder(item, targetPage, index) {
        function fail(reason) {
            console.warn("launchpad: removeFromFolder:", reason);
            return false;
        }
        if (folderRemovalBusy) return fail("another removal is in progress");
        if (!item || !item.id)
            return fail("an app with an id is required (received " + typeof item + ")");
        const openItems = foldered ? listCopy(foldered.items) : null;
        if (!openItems) return fail("an open folder with an items list is required for " + item.id);
        if (!openItems.some(it => it && it.id === item.id))
            return fail("app is not in the open folder");
        if (hidden.indexOf(item.id) >= 0) return fail("app is hidden; keeping it hidden");

        folderRemovalBusy = true;
        try {
            let folderPage = -1, folderIndex = -1, occurrences = 0;
            for (let p = 0; p < pages.length; ++p) {
                for (let i = 0; i < pages[p].length; ++i) {
                    const it = pages[p][i];
                    if (it.kind === "folder") {
                        const members = listCopy(it.items);
                        if (!members) return fail("invalid items list in folder " + it.id);
                        occurrences += members.filter(child => child.id === item.id).length;
                        if (it.id === foldered.id && members.some(child => child.id === item.id)) {
                            folderPage = p;
                            folderIndex = i;
                        }
                    } else if (it.id === item.id) ++occurrences;
                }
            }
            if (folderPage < 0) return fail("source folder no longer exists in the layout");
            if (occurrences !== 1) return fail("app must occur exactly once in the layout");
            const source = pages[folderPage][folderIndex];
            const sourceItems = listCopy(source.items);
            const children = sourceItems.filter(child => child.id !== item.id);
            const newFolder = Object.assign({}, source, { items: children });
            const removed = Object.assign({}, sourceItems.find(child => child.id === item.id));
            delete removed.folder;
            delete removed.folderId;
            const wasSearching = searching;
            const destinationPage = wasSearching ? folderPage
                : Math.max(0, Math.min(pages.length - 1, Number.isFinite(targetPage) ? Math.floor(targetPage) : folderPage));
            const length = pages[destinationPage].length;
            let destinationIndex = wasSearching ? folderIndex + 1
                : (!Number.isFinite(index) || index < 0 || index > length ? length : Math.floor(index));
            const next = listCopy(pages).map(p => listCopy(p));
            const dissolved = children.length === 1 && Theme.dissolveSingleItemFolders;
            if (children.length === 0) {
                next[folderPage].splice(folderIndex, 1);
                if (destinationPage === folderPage && folderIndex < destinationIndex) --destinationIndex;
            } else {
                next[folderPage][folderIndex] = dissolved ? children[0] : newFolder;
            }
            next[destinationPage].splice(Math.min(next[destinationPage].length, destinationIndex), 0, removed);
            // Cascade only overflow, preserving deliberately partial pages.
            for (let p = 0; p < next.length; ++p) {
                if (next[p].length <= Theme.pageSize) continue;
                const overflow = next[p].splice(Theme.pageSize);
                if (p + 1 === next.length) next.push([]);
                next[p + 1] = overflow.concat(next[p + 1]);
            }
            while (next.length > 1 && next[next.length - 1].length === 0) next.pop();
            let landedPage = 0, landedIndex = 0;
            for (let p = 0; p < next.length; ++p) {
                const i = next[p].findIndex(it => it.kind !== "folder" && it.id === removed.id);
                if (i >= 0) { landedPage = p; landedIndex = i; break; }
            }
            pageDirection = 0;
            justDroppedId = removed.id;
            justDroppedTimer.restart();
            sortMode = "manual";
            pages = next;
            if (children.length === 0 || dissolved) closeFolder();
            else foldered = newFolder;
            if (wasSearching) {
                computeResults();
                // Search pages index results rather than layout pages.
                const resultIndex = results.findIndex(it => it.id === removed.id);
                page = resultIndex >= 0 ? Math.floor(resultIndex / Theme.pageSize) : page;
                selected = resultIndex >= 0 ? resultIndex % Theme.pageSize : 0;
            } else {
                page = landedPage;
                selected = landedIndex;
            }
            hoverIndex = -1;
            refreshView();
            saveSoon();
            if (Theme.debugDrag) {
                checkLayoutInvariants();
                console.info("launchpad: removed", removed.id, "to page", landedPage, "slot", landedIndex);
            }
            return true;
        } catch (e) {
            return fail(String(e));
        } finally {
            folderRemovalBusy = false;
        }
    }

    function checkLayoutInvariants() {
        const seen = new Set();
        const errors = [];
        function visit(it) {
            if (it.kind === "folder") {
                if (!it.items.length) errors.push("empty folder: " + it.id);
                it.items.forEach(visit);
            } else {
                if (seen.has(it.id)) errors.push("duplicate app: " + it.id);
                if (hidden.indexOf(it.id) >= 0) errors.push("hidden app in layout: " + it.id);
                seen.add(it.id);
            }
        }
        pages.forEach(p => {
            if (p.length > Theme.pageSize) errors.push("page exceeds capacity");
            p.forEach(visit);
        });
        if (pages.length > 1 && !pages[pages.length - 1].length) errors.push("empty trailing page");
        errors.forEach(reason => console.warn("launchpad: layout invariant:", reason));
        return errors.length === 0;
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  open / close
    // ═════════════════════════════════════════════════════════════════════════
    function open() {
        if (Common.AppMenu.spotlight) {
            Common.AppMenu.toggle();
            return;
        }
        if (shown)
            return;
        windowVisible = true;
        closeTimer.stop();
        Qt.callLater(function () {
            if (!root.windowVisible || Common.AppMenu.spotlight) return;
            shown = true;
            if (Theme.resetSearch) { query = ""; results = []; }
            page = 0;
            selected = 0;
            hoverIndex = -1;
            selectionVisible = false;
            editMode = false;
            folderOpen = false;
            foldered = null;
            menu = null;
            refreshView();
        });
    }

    function close() {
        if (!shown && !windowVisible)
            return;
        shown = false;
        settingsOpen = false;
        if (Theme.resetSearch) { query = ""; results = []; }
        menu = null;
        selectionVisible = false;
        folderOpen = false;
        foldered = null;
        editMode = false;
        drag = null;
        closeTimer.restart();
    }

    // Menu-bar buttons reveal the desktop immediately before their action.
    function dismiss() {
        const wasVisible = shown || windowVisible;
        close();
        closeTimer.stop();
        windowVisible = false;
        if (wasVisible) console.log("[launchpad] menu bar request: Launchpad dismissed");
    }

    function toggle() {
        if (shown || windowVisible)
            close();
        else
            open();
    }

    Timer {
        id: closeTimer
        interval: Theme.closeDelay
        repeat: false
        onTriggered: {
            if (!root.shown)
                root.windowVisible = false;
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  mock data (reference screenshot)
    // ═════════════════════════════════════════════════════════════════════════
    readonly property var mockRows: [
        ["App Store", "Safari", "Mail", "Contacts", "Calendar", "Reminders", "Notes", "Clock"],
        ["FaceTime", "Messages", "Maps", "Find My", "Photo Booth", "Photos", "Music", "Preview"],
        ["Podcasts", "TV", "Voice Memos", "Keynote", "Numbers", "Pages", "Journal", "Weather"],
        ["Stocks", "Books", "Xcode", "Calculator", "Freeform", "Home", "Tips", "Siri"],
        ["Game Center", "Mission Control", "Passwords", "System Settings"]
    ]

    readonly property var mockExtra: [
        "Activity Monitor", "AirPort Utility", "Automator", "Bluetooth File Exchange",
        "Chess", "ColorSync Utility", "Dictionary", "Disk Utility", "Font Book",
        "Grapher", "Image Capture", "Keychain Access", "Migration Assistant",
        "Script Editor", "Stickies", "System Information", "Terminal", "Time Machine",
        "VoiceOver Utility", "Accessibility", "Directory Utility", "Network Utility",
        "Print Center", "Screen Sharing", "Shortcuts", "Translate", "Visual Studio Code",
        "Warp", "Zed", "Fig", "Raycast", "Notion"
    ]

    function mockApp(name, idx) {
        return {
            kind: "mock",
            id: "mock:" + name,
            name: name,
            icon: "",
            color: Theme.fallbackPalette[Math.abs(idx) % Theme.fallbackPalette.length]
        };
    }

    function mockFolder(name, start) {
        const kids = [];
        for (let i = 0; i < 9; ++i)
            kids.push(mockApp(name + " " + (i + 1), start + i));
        return { kind: "folder", id: "__mockfolder__" + name, name: name, items: kids };
    }

    function buildMockPages() {
        const page1 = [];
        let n = 0;
        for (let r = 0; r < mockRows.length; ++r) {
            for (let c = 0; c < mockRows[r].length; ++c) {
                page1.push(mockApp(mockRows[r][c], n));
                ++n;
            }
        }
        page1.push(mockFolder("Utilities", 100));
        page1.push(mockFolder("Other", 120));

        const page2 = [];
        for (let i = 0; i < 20; ++i)
            page2.push(mockApp(mockExtra[i], 200 + i));

        const page3 = [];
        for (let i = 20; i < mockExtra.length; ++i)
            page3.push(mockApp(mockExtra[i], 200 + i));

        return [page1, page2, page3];
    }

    function setMock(on) {
        mockMode = !!on;
        if (mockMode) {
            pages = buildMockPages();
            refreshView();
        } else {
            _loadedFromDisk = false;
            pages = [[]];
            load();
            rebuild();
        }
    }
}

// Folder drag-out state and persistence share the same singleton.
