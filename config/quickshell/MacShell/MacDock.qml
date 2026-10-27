// macdock v2 — a macOS-style dock for Hyprland, built on Quickshell.
//
// Part of the combined macbar + macdock shell (see shell.qml). Keep this file, MacBar.qml, shell.qml and
// liquidglass.frag together in ~/.config/quickshell/macbar/ and run:  qs -c macbar
// Pins are saved to ~/.config/macdock/pinned.json once you use "Keep in Dock".
//
// Settings are saved to ~/.config/macdock/settings.json (right-click the dock → Dock Preferences…).
// The preferences window is frameless; make it float in Hyprland, e.g. (hyprland.conf syntax):
//   windowrule = float, title:^(Dock Preferences)$
//   windowrule = center, title:^(Dock Preferences)$
//
// Dock renderers (legacy settings-file compatibility; no Appearance selector):
//   Normal Blur         – the original translucent tint; blur comes from the Hyprland layer rule below.
//   Apple Liquid Glass  – real-time refraction shader (liquidglass.frag, next to this file). It is compiled
//                         with `qsb` (package qt6-shadertools) on first use and cached in ~/.config/macdock/.
//                         The backdrop it refracts is the wallpaper + the live windows behind the Dock;
//                         set "wallpaperPath" in settings.json if the wallpaper isn't auto-detected.
//
// Hyprland (Lua) layer rule for the glass:
//   hl.layer_rule({ name = "macdock", match = { namespace = "macdock" },
//                   blur = true, ignore_alpha = 0.2, no_anim = true })

import "Common/CornerMath.js" as Curve
import "Common/DockVisibility.js" as DockVisibility
import "Common/DesktopPreferences.js" as DesktopValues
import "Common" as Corners
import QtQuick
import QtQuick.Effects
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Scope {
    id: root

    // shared helpers from shell.qml (window geometry poller, wallpaper lookup)
    property var hub: null
    // MacMinimize bridge (set by shell.qml): minimizes / restores windows with the Dock animation
    property var minimize: null
    readonly property var desktopPrefs: Corners.DesktopPreferences.settings
    readonly property string position: desktopPrefs.position
    property var recentApps: []
    property var previousRunning: ({})
    property bool recentReady: false
    function rememberApp(id) {
        if (!recentReady || !id || id === "systemsettings" || id === launchpadKey || id === "__trash") return;
        var entry = lookup(id);
        if (!entry) return;
        var next = DesktopValues.recent(recentApps, entry.id);
        if (JSON.stringify(next) === JSON.stringify(recentApps)) return;
        recentApps = next;
        recentStore.setText(JSON.stringify(next));
    }
    FileView {
        id: recentStore
        path: root.configDir + "/recent-apps.json"
        printErrors: false
        onLoaded: { try { var saved = JSON.parse(text()); if (Array.isArray(saved)) root.recentApps = saved.filter(function(v) { return typeof v === "string"; }).slice(0,20); } catch (e) {} root.recentReady = true; root.rebuild(); }
        onLoadFailed: root.recentReady = true
    }
    onDesktopPrefsChanged: if (settingsReady) rebuild()
    Connections {
        target: root.minimize
        function onRecordsChanged() { root.rebuild(); }
        function onOnSpecialChanged() { root.rebuild(); }
    }
    function focusWindow(tl) {
        if (!tl) return;
        var addr = winAddr(tl);
        if (root.minimize && root.minimize.isMinimized(addr)) {
            root.minimize.restore(addr);
        } else if (root.hub && root.hub.desktopController
                && (desktopPrefs.stageManager || root.hub.desktopController.revealed.length > 0)) {
            // The controller restores parked windows before focusing them. One
            // owner avoids a second activation overriding the user's next click.
            root.hub.desktopController.activate(addr);
        } else {
            tl.activate();
        }
    }
    SideDock { dock: root; hub: root.hub }

    property bool launchpadHidesDock: false
    property real launchpadVisibilityUpdated: 0
    FileView {
        id: launchpadVisibility
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/launchpad/dock-visibility.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const state = JSON.parse(text());
                root.launchpadVisibilityUpdated = state.updated || 0;
                root.launchpadHidesDock = state.hideDock === true && Date.now() - root.launchpadVisibilityUpdated < 3500;
            }
            catch (e) { root.launchpadHidesDock = false; }
        }
    }
    Timer {
        interval: 1500
        running: root.launchpadHidesDock
        repeat: true
        onTriggered: {
            if (Date.now() - root.launchpadVisibilityUpdated > 3500) root.launchpadHidesDock = false;
        }
    }
    // "Add to Dock" from the Launchpad's right-click menu: the Launchpad drops
    // a request file in its state dir and this Dock picks it up here.
    property real lastPinTransacted: 0
    FileView {
        id: launchpadPinRequest
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/launchpad/dock-pin-request.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const state = JSON.parse(text());
                const updated = state.updated || 0;
                if (updated > root.lastPinTransacted && typeof state.id === "string" && state.id !== "") {
                    root.lastPinTransacted = updated;
                    root.addPin(state.id);
                }
            } catch (e) {
                // Ignore malformed / incomplete request writes.
            }
        }
    }
    property bool dockEnabled: true      // false = no Dock at all (settings window stays available)
    property bool settingsEnabled: true  // false = keep the System Settings window closed
    readonly property var bar: hub ? hub.bar : null
    property string userName: Quickshell.env("USER") || ""

    // ═════ Displays: main display + resolution / refresh, with a macOS-style "keep or revert" safety net ═════
    property var displays: ({ primary: "", modes: {} })      // saved in ~/.config/macshell/displays.json
    property var monList: []                                  // hyprctl monitors (live)
    property string pendingOut: ""                            // a mode change waiting for "Keep"
    property string pendingPrev: ""
    property int revertLeft: 0
    FileView {
        id: dispFile
        path: Quickshell.env("HOME") + "/.config/macshell/displays.json"
        printErrors: false
        onLoaded: { try { root.displays = JSON.parse(text()); } catch (e) {} root.applySavedModes(); }
    }
    function saveDisplays() { dispFile.setText(JSON.stringify(root.displays, null, 2)); }
    function refreshMons() { if (!monListProc.running) monListProc.running = true; }
    Process {
        id: monListProc
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector { onStreamFinished: { try { root.monList = JSON.parse(text); } catch (e) {} } }
    }
    function modeOf(m) { return m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2); }
    function applyMode(out, mode) {
        var m = null;
        for (var i = 0; i < monList.length; i++) if (monList[i].name === out) m = monList[i];
        var pos = m ? (m.x + "x" + m.y) : "auto", sc = m ? m.scale : 1;
        Quickshell.execDetached(["hyprctl", "eval", "hl.monitor({ output = \"" + out + "\", mode = \"" + mode + "\", position = \"" + pos + "\", scale = " + sc + " })"]);
        monRefreshSoon.restart();
    }
    Timer { id: monRefreshSoon; interval: 700; onTriggered: root.refreshMons() }
    // change a monitor's mode; it reverts by itself after 15 s unless kept
    function tryMode(out, mode) {
        var m = null;
        for (var i = 0; i < monList.length; i++) if (monList[i].name === out) m = monList[i];
        if (!m) return;
        if (pendingOut === "") pendingPrev = modeOf(m);
        pendingOut = out;
        applyMode(out, mode);
        pendingMode = mode;
        revertLeft = 15;
        revertTimer.restart();
    }
    property string pendingMode: ""
    Timer {
        id: revertTimer; interval: 1000; repeat: true
        onTriggered: { root.revertLeft--; if (root.revertLeft <= 0) root.revertMode(); }
    }
    function keepMode() {
        revertTimer.stop();
        var d = displays, mm = {}; for (var k in d.modes) mm[k] = d.modes[k];
        mm[pendingOut] = pendingMode;
        displays = { primary: d.primary || "", modes: mm };
        saveDisplays();
        pendingOut = ""; pendingMode = "";
    }
    function revertMode() {
        revertTimer.stop();
        if (pendingOut !== "" && pendingPrev !== "") applyMode(pendingOut, pendingPrev);
        pendingOut = ""; pendingMode = "";
    }
    function applySavedModes() {
        var mm = displays.modes || {};
        for (var k in mm) Quickshell.execDetached(["hyprctl", "eval", "hl.monitor({ output = \"" + k + "\", mode = \"" + mm[k] + "\", position = \"auto\", scale = 1 })"]);
        if (displays.primary) root.monitorPrimary = displays.primary;
        refreshMons();
    }
    property string monitorPrimary: ""
    function setPrimary(name) {
        var d = displays;
        displays = { primary: name, modes: d.modes || {} };
        saveDisplays();
        monitorPrimary = name;
        root.monitor = name;                                         // the Dock lives on the main display
    }
    Process {
        running: true
        command: ["sh", "-c", "n=$(getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1); printf '%s' \"${n:-$USER}\""]
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "") root.userName = text.trim() }
    }
    readonly property bool captureCut: hub ? hub.captureCut : false
    readonly property bool glassHold: hub ? hub.glassHold : false          // windows opening / closing: the glass's live captures pause, source stays attached
    readonly property bool previewHold: hub ? hub.previewHold : false
    readonly property bool captureHold: hub ? hub.captureHold : false     // windows opening / closing: the dock PREVIEW capture stops (source released 0.5 s later); the glass is not affected
    // appearance values shared by Dock and Menu Bar
    function setLook(k, v) {
        if (k === "accent") { Corners.ThemeColors.setAccent("single", String(v)); return; }
        root[k] = v; if (bar) bar[k] = v;
    }
    // Appearance: the Menu Bar resolves "auto" (light by day, dark by night) and keeps both windows in step
    function setAppearance(mode) {
        if (bar && bar.setAppearance) { bar.setAppearance(mode); return; }
        appearanceMode = mode;
        if (mode === "auto") { var h = new Date().getHours(); darkMode = (h < 7 || h >= 19); } else darkMode = (mode === "dark");
    }
    function syncAppearance() {
        if (!bar || !bar.settingsReady) return;
        appearanceMode = bar.appearanceMode;
        darkMode = bar.darkMode;
    }
    Connections {
        target: root.bar
        function onDarkModeChanged() { root.syncAppearance(); }
        function onAppearanceModeChanged() { root.syncAppearance(); }
        function onSettingsReadyChanged() { root.syncAppearance(); }
    }

    // ───────────── CONFIG ───────────── Lachowski
    property string monitor: ""          // "" = every monitor, or e.g. "DP-1"
    property int iconSize: 52
    property real magnification: 1.7     // peak icon scale
    property int spacing: 6
    property int hPad: 10
    property int topPad: 8
    property int bottomPad: 9            // room under icons (running dots live here)
    property int cornerRadius: 18
    // Dock surface only: 0 = circular corners, 1 = continuous Lamé corners.
    property real cornerSquircle: 0
    Binding { target: Corners.CornerTheme; property: "owner"; value: true }
    Binding { target: Corners.IconStyle; property: "owner"; value: true }
    Binding { target: Corners.IconStyle; property: "systemDark"; value: root.darkMode }
    property int margin: 6
    property bool darkMode: true
    // the dock glass follows the Light / Dark system appearance (was: a fixed dark look)
    readonly property bool dockDark: darkMode
    property string appearanceMode: "dark"      // light | dark | auto (kept in step with the Menu Bar, see setAppearance)
    property string dockStyle: "blur"   // legacy saved renderer; the obsolete UI selector was removed
    // Liquid Glass tuning (settings.json): rim = edge highlight, grain = noise, liquid = refraction depth
    property real glassRim: 0.45
    property real glassGrain: 0.03
    property real glassLiquid: 1.0
    readonly property bool glassRT: bar ? bar.glassRealtime : true     // real-time glass (Menu Bar settings)
    property real glassBlur: 5            // legacy Clear blur; the UI now uses Clear / Tinted presets
    readonly property real materialBlur: Corners.GlassMaterial.blurRadius(glassBlur)
    property bool glassDebug: false       // settings.json only: draw the raw Liquid Glass backdrop texture
    property string wallpaperPath: ""    // optional override for the wallpaper the Liquid Glass refracts
    property real glassOpacity: 0.42     // 0 = fully clear; below the layerrule's ignore_alpha (0.2) the blur turns off
    // "smart"  = hide while a non-floating window is open on that monitor's workspace
    // "always" = always auto-hide, "never" = always visible and reserves space
    property string hideMode: "smart"
    function reservesSpaceOn(screenName) {
        return dockEnabled && hideMode === "never" && (!monitor || monitor === screenName);
    }
    property bool showTrash: true
    property string fontFamily: "SF Pro Text"  // installed by macshell-install-sf-fonts
    onFontFamilyChanged: if (fontFamily.indexOf("Inter") === 0) fontFamily = "SF Pro Text"
    property bool magnificationEnabled: true
    property bool showLabels: true       // hover tooltips
    property bool showIndicators: true   // dots under running apps
    property bool bounceOnLaunch: true
    property bool showThumbs: true       // open windows get a live preview cell next to the Trash
    property bool windowCapture: true    // live window capture for those previews (off: the cells show the app icon, nothing is captured). Liquid Glass is not affected
    property int hideDelay: 450          // ms before the dock hides after the pointer leaves
    readonly property color accent: Corners.ThemeColors.accentFor("settings")
    // Dock icon tint: every icon is re-coloured with one colour (works with any icon pack)
    readonly property bool iconTint: Corners.IconStyle.mode === "tinted"
    readonly property string iconTintColor: String(Corners.IconStyle.tintColor)
    readonly property real iconTintStrength: 1.0
    readonly property string launchpadKey: "__launchpad"
    // Use the resolved system appearance, not dockDark (the Dock stays dark).
    readonly property string launchpadIcon: Qt.resolvedUrl(darkMode
        ? "assets/launchpad/launchpad-dark.svg" : "assets/launchpad/launchpad-light.svg").toString()
    readonly property bool launchpadPinned: hasPin(launchpadKey)
    onLaunchpadIconChanged: if (settingsReady) rebuild()
    Connections {
        target: Corners.AppMenu
        function onModeChanged() { if (root.settingsReady) root.rebuild(); }
    }
    readonly property var defaultPinned: [
        launchpadKey,
        "org.gnome.Nautilus", "systemsettings", "thunar",
        "firefox", "zen", "chromium", "google-chrome",
        "tabby", "com.mitchellh.ghostty", "Alacritty", "foot",
        "code", "discord", "spotify", "steam", "obsidian"
    ]   // used until you change pins from the dock; unknown ids are skipped
    property var pinned: defaultPinned
    // ──────────────────────────────────

    // ═════════════════════════════════════════════════════════════════
    //  SETTINGS UI  —  macOS "System Settings" look
    //  (inline components; they receive the palette through `t`)
    // ═════════════════════════════════════════════════════════════════

    // Rounded, inset group box (the white/grey "card" in System Settings)
    component SCard: Corners.ContinuousRectangle {
        id: card
        cornerSmoothing: 0
        required property var t
        default property alias content: col.data
        width: parent ? parent.width : 0
        height: col.implicitHeight + 8
        radius: 16
        color: t.card
        border.width: 0
        border.color: t.cardBorder
        Column { id: col; y: 4; width: parent.width }
    }

    // One row inside a card: title (+ subtitle) on the left, control on the right
    component SRow: Item {
        id: r
        required property var t
        property string title: ""
        property string subtitle: ""
        property url iconSource: ""
        default property alias control: slot.data
        width: parent ? parent.width : 0
        readonly property bool stacked: slot.width > 0 && width - slot.width - 48 < 150
        height: stacked ? textCol.height + slot.height + 36 : Math.max(52, textCol.height + 26, slot.height + 24)

        Corners.ContinuousRectangle {
            visible: r.y > 0.5
            x: 16
            width: parent.width - 32
            height: 1
            color: r.t.sep
        }
        Image {
            id: ic
            visible: r.iconSource != ""
            source: r.iconSource
            x: 16
            width: 28; height: 28
            anchors.verticalCenter: parent.verticalCenter
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
        Column {
            id: textCol
            x: ic.visible ? 56 : 16
            y: r.stacked ? 14 : (r.height - height) / 2
            width: Math.max(0, r.width - x - (r.stacked ? 16 : slot.width + 32))
            spacing: 4
            Text {
                width: parent.width
                text: r.title
                elide: Text.ElideRight
                color: r.t.text
                font.family: r.t.fam
                font.pixelSize: 14
            }
            Text {
                visible: r.subtitle !== ""
                width: parent.width
                text: r.subtitle
                wrapMode: Text.WordWrap
                color: r.t.text2
                font.family: r.t.fam
                font.pixelSize: 12
            }
        }
        Item {
            id: slot
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: r.stacked ? textCol.y + textCol.height + 10 : (r.height - height) / 2
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    // Section header / footnote text
    component SLabel: Text {
        required property var t
        property bool header: false
        width: parent ? parent.width : 0
        leftPadding: header ? 12 : 4
        topPadding: header ? 16 : 0
        bottomPadding: header ? 2 : 0
        wrapMode: Text.WordWrap
        color: header ? t.text : t.text2
        font.family: t.fam
        font.pixelSize: header ? 14 : 12
        font.weight: header ? Font.DemiBold : Font.Normal
    }

    // iOS 26 toggle switch: a wide, flat capsule track with a wide pill knob (not a circle).
    // Every size derives from ONE value, `height` (= track height, default 32):
    //   track 2.30H wide with radius H/2 (perfect capsule)
    //   knob 1.26H x 0.80H, radius knobHeight/2, inset 0.10H from the track edge
    // Pressing stretches the knob into a slight glass lens, growing towards the free space
    // so it always stays inside the track.
    // NOTE: the fill property is called `tint`, not `onColor` — QML treats `on<Capital>`
    // names as signal handlers, which silently turned the track black.
    component SSwitch: Item {
        id: sw
        required property var t
        property bool checked: false
        property bool animationsEnabled: true
        property color tint: t.accent           // follows the Accent colour picked in Appearance
        signal toggled(bool value)

        height: 22
        width: 2.30 * height
        opacity: enabled ? 1 : 0.4

        // ── ratios (everything scales with `height`) ──
        readonly property real knobInset: 0.10 * height
        readonly property real knobW: 1.26 * height
        readonly property real knobH: 0.80 * height
        // liquid: pressing stretches the lens, a fast drag stretches it along the travel,
        // and `jellyOff` adds a damped wobble while the knob settles after a toggle
        readonly property real wobble: dragStretch + jellyOff
        readonly property real effKnobW: knobW * (pressed ? 1.14 : 1.0) * (1.0 + wobble)
        readonly property real effKnobH: knobH * (pressed ? 1.04 : 1.0) * (1.0 - wobble * 0.55)
        readonly property real travel: width - 2 * knobInset - effKnobW  // knob x range
        readonly property real knobX: dragging ? dragX
                                              : (checked ? width - knobInset - effKnobW : knobInset)

        // ── colours ──
        readonly property color offFill: t.dark ? Qt.rgba(120 / 255, 120 / 255, 128 / 255, 0.32) : "#E9E9EB"
        readonly property color fill: checked ? tint : offFill
        readonly property color rimOnDim: Qt.darker(tint, 1.12)
        readonly property color rimOn: Qt.rgba(rimOnDim.r, rimOnDim.g, rimOnDim.b, 0.9)
        readonly property color rimOff: t.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)

        // ── interaction state ──
        property bool pressed: false
        property bool dragging: false
        property real dragX: 0
        property real pressX: 0
        property real grabDx: 0
        property real vel: 0                    // px per ms, for flick toggles
        property bool moved: false
        property real lastX: 0
        property real lastT: 0

        // ── liquid glass state ──
        property real glass: 0                  // 0 = flat white pill, 1 = full glass coat
        property real sweep: -0.35              // position of the travelling specular band
        property real jellyOff: 0               // damped wobble offset, settles back to 0
        property real dragStretch: 0             // stretch that follows the pointer speed
        property bool ready: false               // the initial `checked` binding must not flash

        Behavior on glass { NumberAnimation { duration: sw.animationsEnabled ? 150 : 0; easing.type: Easing.OutQuad } }
        Behavior on dragStretch { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

        Component.onCompleted: sw.ready = true
        // a toggle (click, flick or drag-release) runs the glass coat + the specular sweep
        onCheckedChanged: if (sw.ready && !sw.dragging) { sw.pulseGlass(560, true); jellyDelay.restart(); }

        function pulseGlass(hold, doSweep) {
            sw.glass = 1;
            glassTimer.interval = hold;
            glassTimer.restart();
            if (doSweep) sweepAnim.restart();
        }
        function startJelly() { jellyAnim.restart(); }

        Timer { id: glassTimer; interval: 560; onTriggered: sw.glass = 0 }
        Timer { id: jellyDelay; interval: 215; onTriggered: sw.startJelly() }

        // damped "jelly" settle: one overshoot, one rebound, then rest
        SequentialAnimation {
            id: jellyAnim
            NumberAnimation { target: sw; property: "jellyOff"; from: 0;     to: 0.10;  duration: 90;  easing.type: Easing.OutQuad }
            NumberAnimation { target: sw; property: "jellyOff"; from: 0.10;  to: -0.06; duration: 120; easing.type: Easing.InOutQuad }
            NumberAnimation { target: sw; property: "jellyOff"; from: -0.06; to: 0.028; duration: 115; easing.type: Easing.InOutQuad }
            NumberAnimation { target: sw; property: "jellyOff"; from: 0.028; to: 0;     duration: 115; easing.type: Easing.InOutQuad }
        }
        // light sweeping across the pill, so the glass catches the light while it travels
        NumberAnimation {
            id: sweepAnim
            target: sw; property: "sweep"
            from: -0.35; to: 1.35
            duration: 560
            easing.type: Easing.InOutCubic
        }

        // ── track ──
        Corners.ContinuousRectangle { cornerSmoothing: 0;
            id: rail
            anchors.fill: parent
            radius: height / 2
            color: (sw.pressed || ma.containsMouse) ? Qt.lighter(sw.fill, sw.pressed ? 1.04 : 1.02) : sw.fill
            Behavior on color { ColorAnimation { duration: sw.animationsEnabled ? 250 : 0; easing.type: Easing.OutCubic } }
        }

        // thin rim just inside the edge: darker green when on, light edge when off
        Corners.ContinuousRectangle { cornerSmoothing: 0;
            anchors.fill: parent
            radius: rail.radius
            color: "transparent"
            border.width: Math.max(1, (sw.checked ? 0.033 : 0.025) * sw.height)
            border.color: sw.checked ? sw.rimOn : sw.rimOff
            Behavior on border.color { ColorAnimation { duration: sw.animationsEnabled ? 250 : 0; easing.type: Easing.OutCubic } }
        }

        // very faint inset shadow along the top inside edge, for a slightly sunken track
        Corners.ContinuousRectangle { cornerSmoothing: 0;
            anchors.fill: parent
            radius: rail.radius
            opacity: sw.checked ? 0.5 : 1.0
            Behavior on opacity { NumberAnimation { duration: sw.animationsEnabled ? 250 : 0 } }
            gradient: Gradient {
                GradientStop { position: 0.0;  color: Qt.rgba(0, 0, 0, 0.07) }
                GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.0) }
            }
        }

        // ── knob ──
        Item {
            id: knobHolder
            x: sw.knobX
            y: (sw.height - sw.effKnobH) / 2
            width: sw.effKnobW
            height: sw.effKnobH

            Behavior on x {
                enabled: sw.animationsEnabled && !sw.dragging
                NumberAnimation {
                    duration: sw.pressed ? 120 : 260
                    easing.type: sw.pressed ? Easing.OutQuad : Easing.OutBack
                    easing.overshoot: 1.1
                }
            }
            Behavior on width {
                enabled: sw.animationsEnabled && !sw.dragging && !jellyAnim.running
                NumberAnimation {
                    duration: sw.pressed ? 120 : 220
                    easing.type: sw.pressed ? Easing.OutQuad : Easing.OutBack
                    easing.overshoot: 1.2
                }
            }
            Behavior on height {
                enabled: sw.animationsEnabled && !sw.dragging && !jellyAnim.running
                NumberAnimation {
                    duration: sw.pressed ? 120 : 220
                    easing.type: sw.pressed ? Easing.OutQuad : Easing.OutBack
                    easing.overshoot: 1.2
                }
            }
            Behavior on y {
                enabled: sw.animationsEnabled
                NumberAnimation { duration: sw.pressed ? 120 : 220; easing.type: Easing.OutQuad }
            }

            // frosted white capsule. It goes slightly translucent while the glass coat is
            // on, so the accent track bleeds through and the pill reads as a lens.
            Corners.ContinuousRectangle { cornerSmoothing: 0;
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 1.0 - 0.10 * sw.glass - (sw.pressed ? 0.04 : 0.0))
                border.width: 1
                border.color: sw.pressed ? Qt.rgba(1, 1, 1, 0.95) : Qt.rgba(0, 0, 0, 0.05)
                Behavior on color { ColorAnimation { duration: sw.animationsEnabled ? 150 : 0 } }
                Behavior on border.color { ColorAnimation { duration: sw.animationsEnabled ? 150 : 0 } }
            }

            // liquid glass coat: fresnel rim, accent-tinted thickness at the bottom edge
            // and a specular band that sweeps across while the knob travels.
            ShaderEffect {
                anchors.fill: parent
                visible: sw.glass > 0.002
                blending: true
                fragmentShader: Qt.resolvedUrl("knobglass.frag.qsb")
                property vector2d itemSize: Qt.vector2d(width, height)
                property real radius: height / 2
                property vector4d tint: Qt.vector4d(sw.tint.r, sw.tint.g, sw.tint.b, 1.0)
                property real glass: sw.glass
                property real sweep: sw.sweep
                property real press: sw.pressed ? 1.0 : 0.0
            
                property real squircle: 0
            }
        }

        // ── mouse: click anywhere to toggle, drag the knob 1:1 with snap-to-nearest + flick ──
        MouseArea {
            id: ma
            anchors.fill: parent
            enabled: sw.enabled
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => {
                var kx = sw.knobX;                       // grab offset before the press stretches the knob
                sw.pressX = mouse.x;
                sw.moved = false;
                sw.vel = 0;
                sw.lastX = mouse.x;
                sw.lastT = Date.now();
                sw.grabDx = (mouse.x >= kx && mouse.x <= kx + sw.knobW) ? mouse.x - kx : sw.knobW / 2;
                sw.dragX = kx;
                sw.pressed = true;
            }
            onPositionChanged: mouse => {
                if (!sw.pressed) return;
                if (!sw.moved && Math.abs(mouse.x - sw.pressX) > 4) {
                    sw.moved = true;
                    sw.dragging = true;
                    sw.jellyOff = 0;
                    jellyAnim.stop();
                    sw.glass = 1;                 // the glass coat only shows while the knob travels
                    glassTimer.stop();
                }
                if (!sw.dragging) return;
                sw.dragX = Math.max(sw.knobInset,
                                    Math.min(sw.knobInset + sw.travel, mouse.x - sw.grabDx));
                var now = Date.now();
                var dt = now - sw.lastT;
                if (dt > 0) {
                    sw.vel = sw.vel * 0.6 + ((mouse.x - sw.lastX) / dt) * 0.4;
                    sw.lastX = mouse.x;
                    sw.lastT = now;
                    sw.dragStretch = Math.min(0.11, Math.abs(sw.vel) * 0.09);   // stretch with the flick speed
                }
            }
            onReleased: mouse => {
                var target = sw.checked;
                if (sw.dragging) {
                    var frac = (sw.dragX - sw.knobInset) / Math.max(1, sw.travel);
                    if (sw.vel > 0.35) target = true;            // quick flick right
                    else if (sw.vel < -0.35) target = false;     // quick flick left
                    else target = frac > 0.5;                    // snap to the nearest side
                } else if (!sw.moved) {
                    target = !sw.checked;                        // a drag under 4px counts as a click
                }
                var wasDragging = sw.dragging;
                sw.pressed = false;
                sw.dragging = false;
                sw.dragStretch = 0;
                if (target !== sw.checked) {
                    // fallback fade in case the parent never applies the new value
                    glassTimer.interval = 900;
                    glassTimer.restart();
                    sw.toggled(target);        // onCheckedChanged then fires the glass, sweep and jelly
                } else if (wasDragging) {
                    sw.pulseGlass(220, false); // state unchanged: just let the coat fade out
                    sw.startJelly();           // ...and settle the stretch with a small wobble
                }
            }
            onCanceled: { sw.pressed = false; sw.dragging = false; sw.dragStretch = 0; }
        }
    }

    // macOS slider (thin track, accent fill, white round knob)
    component SSlider: Item {
        id: s
        required property var t
        property real from: 0
        property real to: 1
        property real value: 0
        property real stepSize: 0
        property string leftLabel: ""
        property string rightLabel: ""
        signal moved(real v)
        readonly property real pos: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0
        width: 230
        height: leftLabel !== "" || rightLabel !== "" ? 40 : 22
        opacity: enabled ? 1 : 0.4

        Corners.ContinuousRectangle { cornerSmoothing: 0;
            id: track
            y: 11 - 2
            width: parent.width
            height: 4
            radius: 2
            color: s.t.track
        }
        Corners.ContinuousRectangle { cornerSmoothing: 0;
            y: track.y
            width: knob.x + knob.width / 2
            height: 4
            radius: 2
            color: s.t.accent
        }
        Corners.ContinuousRectangle { cornerSmoothing: 0;
            id: knob
            x: s.pos * (s.width - 20)
            y: 1
            width: 20; height: 20; radius: 10
            color: "white"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.16)
        }
        Text {
            visible: s.leftLabel !== ""
            y: 25
            text: s.leftLabel
            color: s.t.text2
            font.family: s.t.fam
            font.pixelSize: 11
        }
        Text {
            visible: s.rightLabel !== ""
            y: 25
            x: s.width - implicitWidth
            text: s.rightLabel
            color: s.t.text2
            font.family: s.t.fam
            font.pixelSize: 11
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            function setFrom(mx) {
                var p = Math.max(0, Math.min(1, (mx - 10) / (s.width - 20)));
                var v = s.from + p * (s.to - s.from);
                if (s.stepSize > 0) v = Math.round(v / s.stepSize) * s.stepSize;
                v = Math.round(v * 1000) / 1000;
                s.moved(v);
            }
            onPressed: mouse => setFrom(mouse.x)
            onPositionChanged: mouse => { if (pressed) setFrom(mouse.x); }
        }
    }

    // macOS segmented control
    component SSegmented: Item {
        id: g
        required property var t
        property var model: []
        property int current: 0
        property real segWidth: 72
        signal picked(int index)
        width: model.length * segWidth + 4
        height: 26
        Corners.ContinuousRectangle { cornerSmoothing: 0; anchors.fill: parent; radius: 7; color: g.t.ctrl }
        Corners.ContinuousRectangle { cornerSmoothing: 0;
            visible: g.current >= 0
            y: 2
            x: 2 + g.current * g.segWidth
            width: g.segWidth
            height: parent.height - 4
            radius: 5
            color: g.t.ctrlSel
            border.width: g.t.dark ? 0 : 1
            border.color: Qt.rgba(0, 0, 0, 0.10)
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
        Row {
            x: 2; y: 2
            Repeater {
                model: g.model
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: g.segWidth
                    height: g.height - 4
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: g.t.text
                        font.family: g.t.fam
                        font.pixelSize: 12
                        font.weight: parent.index === g.current ? Font.Medium : Font.Normal
                    }
                    MouseArea { anchors.fill: parent; onClicked: g.picked(parent.index) }
                }
            }
        }
    }

    // macOS push button
    component SButton: Corners.ContinuousRectangle { cornerSmoothing: 0;
        id: b
        required property var t
        property string text: ""
        property bool destructive: false
        signal clicked()
        width: lbl.implicitWidth + 26
        height: 24
        radius: 6
        color: ma.pressed ? t.buttonPressed : t.button
        border.width: 1
        border.color: t.buttonBorder
        Text {
            id: lbl
            anchors.centerIn: parent
            text: b.text
            color: b.destructive ? b.t.danger : b.t.text
            font.family: b.t.fam
            font.pixelSize: 13
        }
        MouseArea { id: ma; anchors.fill: parent; onClicked: b.clicked() }
    }

    // A miniature desktop for Light, Dark, and the split Auto appearance.
    component SThemeTile: Item {
        id: tile
        required property var t
        property bool dark: false
        property bool split: false
        property bool selected: false
        property string label: ""
        signal clicked()
        width: 92; height: 86
        Repeater {
            model: tile.split ? 2 : 1
            delegate: Item {
                required property int index
                readonly property bool previewDark: tile.split ? index === 1 : tile.dark
                x: tile.split ? index * tile.width / 2 : 0
                width: tile.split ? tile.width / 2 : tile.width
                height: 64
                clip: true
                Item {
                    x: tile.split ? -parent.index * tile.width / 2 : 0
                    width: tile.width; height: 64
                    Image {
                        anchors.fill: parent
                        source: Qt.resolvedUrl("assets/settings/appearance-preview.svg")
                        sourceSize: Qt.size(184, 128)
                        smooth: true
                    }
                    Rectangle {
                        anchors.fill: parent; radius: 10
                        color: "black"; opacity: parent.parent.previewDark ? 0.30 : 0
                    }
                    Rectangle {
                        x: 4; y: 9; width: 44; height: 23; radius: 5
                        color: parent.parent.previewDark ? "#292C38" : "#F0F0F4"
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.14)
                        Rectangle { x: 4; y: 6; width: 34; height: 5; radius: 2; color: tile.t.accent }
                        Rectangle { x: 4; y: 14; width: 22; height: 3; radius: 1.5; color: parent.parent.parent.previewDark ? "#5B6072" : "#AEB5C5" }
                    }
                    Rectangle {
                        x: 28; y: 29; width: 60; height: 32; radius: 7
                        color: parent.parent.previewDark ? "#1C1E22" : "#FFFFFF"
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.16)
                        Rectangle { x: 0; y: 0; width: 19; height: parent.height; radius: 7; color: parent.parent.parent.previewDark ? "#36393F" : "#E9EDF1" }
                        Row {
                            x: 7; y: 10; spacing: 4
                            Repeater {
                                model: ["#FF5F57", "#FEBC2E", "#28C840"]
                                delegate: Rectangle { required property color modelData; width: 6; height: 6; radius: 3; color: modelData }
                            }
                        }
                    }
                }
            }
        }
        Rectangle {
            width: tile.width; height: 64; radius: 10
            color: "transparent"
            border.width: tile.selected ? 3 : 1
            border.color: tile.selected ? tile.t.accent : tile.t.cardBorder
        }
        Text {
            y: 70
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.label
            color: tile.selected ? tile.t.text : tile.t.text2
            font.family: tile.t.fam
            font.pixelSize: 12
            font.weight: tile.selected ? Font.DemiBold : Font.Normal
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.clicked() }
    }

    // Colored rounded-square sidebar icon with a tiny drawn glyph
    component SGlyph: Corners.ContinuousRectangle {
        id: gl
        property string kind: ""
        property string wg: ""          // a menu-bar glyph (WGlyph.qml) instead of the hand-drawn kinds below
        property color c1: "#4FA8FF"
        property color c2: "#0A6CFF"
        width: 24; height: 24; radius: 6
        gradient: Gradient {
            GradientStop { position: 0.0; color: gl.c1 }
            GradientStop { position: 1.0; color: gl.c2 }
        }
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.14)

        WGlyph { visible: gl.wg !== ""; anchors.centerIn: parent; width: 16; height: 16; kind: gl.wg; color: "white" }
        Item {
            anchors.centerIn: parent
            width: 16; height: 16
            visible: gl.wg === ""

            // dock
            Item {
                visible: gl.kind === "dock"; anchors.fill: parent
                Corners.ContinuousRectangle { x: 1; y: 11; width: 14; height: 4; radius: 2; color: "white" }
                Corners.ContinuousRectangle { x: 2;    y: 4.5; width: 3.4; height: 3.4; radius: 1; color: "white" }
                Corners.ContinuousRectangle { x: 6.3;  y: 4.5; width: 3.4; height: 3.4; radius: 1; color: "white" }
                Corners.ContinuousRectangle { x: 10.6; y: 4.5; width: 3.4; height: 3.4; radius: 1; color: "white" }
            }
            // appearance (half-filled circle)
            Item {
                visible: gl.kind === "appearance"; anchors.fill: parent
                Corners.ContinuousRectangle {
                    x: 1.5; y: 1.5; width: 13; height: 13; radius: 6.5
                    color: "transparent"; border.width: 2; border.color: "white"
                }
                Item {
                    x: 8; y: 1.5; width: 6.5; height: 13; clip: true
                    Corners.ContinuousRectangle { x: -6.5; width: 13; height: 13; radius: 6.5; color: "white" }
                }
            }
            // behavior (two toggles)
            Item {
                visible: gl.kind === "behavior"; anchors.fill: parent
                Corners.ContinuousRectangle { x: 1; y: 2; width: 14; height: 5.5; radius: 2.75; color: "white" }
                Corners.ContinuousRectangle { x: 10.2; y: 3.2; width: 3.1; height: 3.1; radius: 1.55; color: gl.c2 }
                Corners.ContinuousRectangle {
                    x: 1; y: 9.5; width: 14; height: 5.5; radius: 2.75
                    color: "transparent"; border.width: 1; border.color: "white"
                }
                Corners.ContinuousRectangle { x: 2.7; y: 10.7; width: 3.1; height: 3.1; radius: 1.55; color: "white" }
            }
            // applications (2×2 grid)
            Item {
                visible: gl.kind === "apps"; anchors.fill: parent
                Corners.ContinuousRectangle { x: 1.5; y: 1.5; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Corners.ContinuousRectangle { x: 8.9; y: 1.5; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Corners.ContinuousRectangle { x: 1.5; y: 8.9; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Corners.ContinuousRectangle { x: 8.9; y: 8.9; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
            }
            // menu bar
            Item {
                visible: gl.kind === "menubar"; anchors.fill: parent
                Corners.ContinuousRectangle { x: 1; y: 2; width: 14; height: 4.5; radius: 1.5; color: "white" }
                Corners.ContinuousRectangle { x: 2.5; y: 3.4; width: 4; height: 1.6; radius: 0.8; color: gl.c2 }
                Corners.ContinuousRectangle {
                    x: 1; y: 8.5; width: 14; height: 6.5; radius: 2
                    color: "transparent"; border.width: 1; border.color: "white"
                }
            }
            // wallpaper (picture with a sun and hills)
            Item {
                visible: gl.kind === "wallpaper"; anchors.fill: parent
                Corners.ContinuousRectangle {
                    x: 1; y: 2.5; width: 14; height: 11; radius: 2
                    color: "transparent"; border.width: 1.5; border.color: "white"
                }
                Corners.ContinuousRectangle { x: 9.5; y: 4.6; width: 2.8; height: 2.8; radius: 1.4; color: "white" }
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var c = getContext("2d"); c.reset(); c.fillStyle = "white";
                        c.beginPath(); c.moveTo(2.5, 12.5); c.lineTo(6.2, 7.6); c.lineTo(9.2, 11); c.lineTo(10.8, 9.4); c.lineTo(13.5, 12.5); c.closePath(); c.fill();
                    }
                }
            }
            // about
            Item {
                visible: gl.kind === "about"; anchors.fill: parent
                Corners.ContinuousRectangle {
                    x: 1; y: 1; width: 14; height: 14; radius: 7
                    color: "transparent"; border.width: 2; border.color: "white"
                }
                Text {
                    anchors.centerIn: parent
                    text: "i"
                    color: "white"
                    font.pixelSize: 10
                    font.bold: true
                }
            }
        }
    }

    // ─────────────────────────── THE WINDOW ───────────────────────────
    Window {
        id: prefsWindow
        title: "Setting"
        width: preferredWidth
        // tall enough for the longest pane, but never taller than the monitor we open on
        height: prefsWindow.preferredHeight
        minimumWidth: 760
        minimumHeight: 520
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint

        // ── navigation state ──
        property int cur: 0
        property var backStack: []
        property var fwdStack: []
        property string query: ""

        // grouped like macOS System Settings (sec = sidebar section; a gap is drawn between sections)
        readonly property var panes: [
            { id: "wifi",       sec: 1, name: "Wi-Fi",           wg: "wifi",       c1: "#3D9BFF", c2: "#0A6CFF", keys: "wireless network internet ssid join" },
            { id: "bluetooth",  sec: 1, name: "Bluetooth",       wg: "bluetooth",  c1: "#3D9BFF", c2: "#0A6CFF", keys: "devices pair headphones mouse keyboard" },
            { id: "network",    sec: 1, name: "Network",         wg: "ethernet",   c1: "#3D9BFF", c2: "#0A6CFF", keys: "ethernet ip address vpn tailscale connection" },
            { id: "battery",    sec: 1, name: "Battery",         wg: "bolt",       c1: "#4CD964", c2: "#28A745", keys: "power energy charge profile performance game mode" },
            { id: "general",    sec: 2, name: "General",         glyph: "behavior", c1: "#8E8E93", c2: "#636366", keys: "enable disable dock menu bar panel show hide off on widgets sound game" },
            { id: "system",     sec: 2, name: "System Information", glyph: "about", c1: "#A7A7AD", c2: "#7C7C82", keys: "about linux computer hardware model processor chip cpu memory ram serial kernel graphics storage firmware" },
            { id: "appearance", sec: 2, name: "Appearance",      glyph: "appearance", c1: "#3A3A3C", c2: "#1C1C1E", keys: "theme dark light mode accent color multicolor text highlight selection automatic icon widget style folder tinted default glass liquid clear tinted apple style translucency blur corner radius font" },
            { id: "controlcenter", sec: 2, name: "Control Center", wg: "cc",       c1: "#8E8E93", c2: "#636366", keys: "modules tiles controls" },
            { id: "dock",       sec: 2, name: "Desktop & Dock",  glyph: "dock",     c1: "#2C2C2E", c2: "#1C1C1E", keys: "size icon magnification zoom spacing margin distance edge hide auto labels indicators bounce trash monitor preview" },
            { id: "displays",   sec: 2, name: "Displays",        wg: "sun",        c1: "#3D9BFF", c2: "#0A6CFF", keys: "brightness night shift monitor resolution refresh scale" },
            { id: "menubar",    sec: 2, name: "Menu Bar",        glyph: "menubar",  c1: "#3D9BFF", c2: "#0A6CFF", keys: "panel bar height clock date seconds 24 hour battery tray search spotlight week monday style liquid bluetooth widget" },
            { id: "wallpaper",  sec: 2, name: "Wallpaper",       glyph: "wallpaper", c1: "#5AC8FA", c2: "#007AFF", keys: "wallpaper background picture image video animated live motion desktop dynamic" },
            { id: "notifications", sec: 3, name: "Notifications", wg: "bell",      c1: "#FF5E57", c2: "#E8342A", keys: "alerts banners popups do not disturb" },
            { id: "sound",      sec: 3, name: "Sound",           wg: "speaker",    c1: "#FF5E7E", c2: "#E8344F", keys: "volume output input microphone speakers headphones effects" },
            { id: "focus",      sec: 3, name: "Focus",           wg: "moon",       c1: "#7D7AFF", c2: "#5856D6", keys: "do not disturb keep awake sleep" },
            { id: "lockscreen", sec: 4, name: "Lock Screen",     wg: "lock",       c1: "#3A3A3C", c2: "#1C1C1E", keys: "lock password album lyrics media clock" },
            { id: "users",      sec: 4, name: "Users & Groups",  wg: "smile",      c1: "#3D9BFF", c2: "#0A6CFF", keys: "account user name picture avatar" },
            { id: "keyboard",   sec: 5, name: "Keyboard",        wg: "keyboard",   c1: "#A7A7AD", c2: "#7C7C82", keys: "repeat rate delay layout typing" },
            { id: "mouse",      sec: 5, name: "Mouse",           wg: "mouse",      c1: "#A7A7AD", c2: "#7C7C82", keys: "tracking speed scroll natural" },
            { id: "trackpad",   sec: 5, name: "Trackpad",        wg: "trackpad",   c1: "#A7A7AD", c2: "#7C7C82", keys: "tap click natural scroll touchpad gestures" },
            { id: "apps",       sec: 6, name: "Applications",    glyph: "apps",     c1: "#FFB340", c2: "#FF9500", keys: "pinned apps keep remove reset dock menu launcher spotlight launchpad super a" },
            { id: "about",      sec: 6, name: "About",           glyph: "about",    c1: "#A7A7AD", c2: "#7C7C82", keys: "version reset config folder macdock macbar macshell" }
        ]

        readonly property var filtered: {
            var q = query.trim().toLowerCase();
            var out = [];
            for (var i = 0; i < panes.length; i++) {
                var hay = (panes[i].name + " " + panes[i].keys).toLowerCase();
                if (q === "" || hay.indexOf(q) >= 0) out.push(i);
            }
            return out;
        }

        function go(i) {
            if (i === cur) return;
            backStack = backStack.concat([cur]);
            fwdStack = [];
            cur = i;
        }
        function back() {
            if (backStack.length === 0) return;
            var b = backStack.slice();
            var p = b.pop();
            fwdStack = fwdStack.concat([cur]);
            backStack = b;
            cur = p;
        }
        function forward() {
            if (fwdStack.length === 0) return;
            var f = fwdStack.slice();
            var p = f.pop();
            backStack = backStack.concat([cur]);
            fwdStack = f;
            cur = p;
        }
        onCurChanged: flick.contentY = 0

        Shortcut { sequences: ["Escape", "Ctrl+W"]; onActivated: prefsWindow.visible = false }

        // Settings always opens as a floating, centred window (no windowrule needed in hyprland.conf)
        onVisibleChanged: if (visible) { showNormal(); floatTries = 0; floatTimer.restart(); }
        property int floatTries: 0
        readonly property int preferredWidth: Math.min(1000, (screen ? screen.width : 1280) - 80)
        readonly property bool squareCorners: !!(root.hub && root.hub.desktopController.hasSquareCorners(title))
        readonly property real windowRadius: squareCorners ? 0 : 26
        readonly property real sidebarInset: 10
        readonly property real sidebarRadius: Math.max(0, 26 - sidebarInset)
        readonly property real sidebarWidth: Math.max(230, Math.min(288, width * 0.30))
        readonly property real headerHeight: 66
        // never taller than the monitor we open on (a 900p design size on an 800p screen
        // used to push the window's own traffic lights off the top edge)
        readonly property int preferredHeight: Math.min(820, (prefsWindow.screen ? prefsWindow.screen.height : 900) - 64)
        Timer {
            id: floatTimer
            interval: 140
            repeat: true
            onTriggered: {
                // the compositor maps the window a moment after it becomes visible: send the dispatches a few times
                var sel = 'window = "title:^(' + prefsWindow.title + ')$"';
                Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel + ' })');
                // Hyprland can remember an older floating size; reapply the compact size after mapping.
                if (prefsWindow.floatTries >= 1) {
                    Hyprland.dispatch('hl.dsp.window.resize({ x = ' + prefsWindow.preferredWidth + ', y = ' + prefsWindow.preferredHeight + ', "exact", ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.center({ ' + sel + ' })');
                }
                if (++prefsWindow.floatTries >= 4) stop();
            }
        }

        // ── palette ──
        QtObject {
            id: pal
            readonly property bool dark: root.darkMode
            readonly property string fam: root.fontFamily
            readonly property color accent: root.accent
            readonly property real materialOpacity: Math.max(0, Math.min(1, root.glassOpacity))
            readonly property color content: dark ? Qt.rgba(0.09, 0.10, 0.11, 0.50 + materialOpacity * 0.35)
                                                   : Qt.rgba(0.97, 0.97, 0.98, 0.45 + materialOpacity * 0.35)
            readonly property color sidebar: dark ? Qt.rgba(0.045, 0.05, 0.055, 0.50 + materialOpacity * 0.25)
                                                   : Qt.rgba(1, 1, 1, 0.45 + materialOpacity * 0.30)
            readonly property color card: dark ? Qt.rgba(1, 1, 1, 0.085)
                                                : Qt.rgba(1, 1, 1, 0.60)
            readonly property color cardBorder: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.07)
            readonly property color windowBorder: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.22)
            readonly property color sep: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
            readonly property color text: dark ? "#F5F5F7" : "#1D1D1F"
            readonly property color text2: dark ? Qt.rgba(1, 1, 1, 0.56) : Qt.rgba(0, 0, 0, 0.52)
            readonly property color text3: dark ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(0, 0, 0, 0.30)
            readonly property color track: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.13)
            readonly property color switchOff: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
            readonly property color ctrl: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
            readonly property color ctrlSel: dark ? "#636366" : "#FFFFFF"
            readonly property color button: dark ? Qt.rgba(1, 1, 1, 0.13) : "#FFFFFF"
            readonly property color buttonPressed: dark ? Qt.rgba(1, 1, 1, 0.24) : "#E4E4E7"
            readonly property color buttonBorder: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.14)
            readonly property color field: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
            readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
            readonly property color selInactive: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
            readonly property color danger: "#FF453A"
        }

        NumberAnimation { id: fadeIn; target: paneLoader; property: "opacity"; from: 0; to: 1; duration: 160 }

        // ── frame ──
        Corners.ContinuousRectangle {
            id: frame
            anchors.fill: parent
            radius: prefsWindow.windowRadius
            normalizeRadius: false
            // Frosted blur is supplied by the compositor; no refraction shader.
            color: pal.content
            border.width: 1
            border.color: pal.windowBorder

            // Native Wayland resize handles for this frameless window.
            MouseArea { x: 12; y: 0; width: parent.width - 24; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; onPressed: prefsWindow.startSystemResize(Qt.TopEdge) }
            MouseArea { x: 12; y: parent.height - 6; width: parent.width - 24; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; onPressed: prefsWindow.startSystemResize(Qt.BottomEdge) }
            MouseArea { x: 0; y: 12; width: 6; height: parent.height - 24; z: 1000; cursorShape: Qt.SizeHorCursor; onPressed: prefsWindow.startSystemResize(Qt.LeftEdge) }
            MouseArea { x: parent.width - 6; y: 12; width: 6; height: parent.height - 24; z: 1000; cursorShape: Qt.SizeHorCursor; onPressed: prefsWindow.startSystemResize(Qt.RightEdge) }
            MouseArea { x: 0; y: 0; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeFDiagCursor; onPressed: prefsWindow.startSystemResize(Qt.TopEdge | Qt.LeftEdge) }
            MouseArea { x: parent.width - 12; y: 0; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeBDiagCursor; onPressed: prefsWindow.startSystemResize(Qt.TopEdge | Qt.RightEdge) }
            MouseArea { x: 0; y: parent.height - 12; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeBDiagCursor; onPressed: prefsWindow.startSystemResize(Qt.BottomEdge | Qt.LeftEdge) }
            MouseArea { x: parent.width - 12; y: parent.height - 12; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeFDiagCursor; onPressed: prefsWindow.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }

            // drag the window by its top strip
            Item {
                width: parent.width
                height: 52
                TapHandler { acceptedButtons: Qt.LeftButton; onDoubleTapped: if (root.hub) root.hub.desktopController.titlebar() }
                DragHandler {
                    target: null
                    onActiveChanged: if (active) prefsWindow.startSystemMove()
                }
            }

            // ───────── sidebar ─────────
            Corners.ContinuousRectangle {
                id: sidebar
                // Concentric corners: 32px window, 10px inset, 22px sidebar.
                x: prefsWindow.sidebarInset; y: prefsWindow.sidebarInset
                width: prefsWindow.sidebarWidth
                height: parent.height - 2 * prefsWindow.sidebarInset
                radius: prefsWindow.sidebarRadius
                normalizeRadius: false
                color: pal.sidebar
                border.width: 1
                border.color: pal.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)

                // Use Nautilus's MacTahoe artwork and button states.
                WindowControls {
                    x: 17; y: 11
                    dark: pal.dark
                    windowActive: prefsWindow.active
                    restored: prefsWindow.visibility === Window.FullScreen || prefsWindow.visibility === Window.Maximized
                    onCloseClicked: prefsWindow.visible = false
                    onMinimizeClicked: {
                        var a = root.prefsAddr();
                        if (a !== "" && root.minimize) root.minimize.minimize(a);
                    }
                    onZoomClicked: {
                        if (prefsWindow.visibility === Window.FullScreen || prefsWindow.visibility === Window.Maximized) prefsWindow.showNormal();
                        else if (root.reservesSpaceOn(prefsWindow.screen ? prefsWindow.screen.name : "")) prefsWindow.showMaximized();
                        else prefsWindow.showFullScreen();
                    }
                }

                // search field
                Corners.ContinuousRectangle { cornerSmoothing: 0;
                    id: search
                    x: 14; y: 62
                    width: parent.width - 28
                    height: 34
                    radius: height / 2
                    color: pal.field

                    // Two separate strokes: upper-left and lower-right only.
                    Canvas {
                        anchors.fill: parent
                        antialiasing: true
                        property bool dark: pal.dark
                        property bool focused: searchInput.activeFocus
                        onDarkChanged: requestPaint()
                        onFocusedChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset();
                            var inset = focused ? 0.75 : 0.5;
                            var r = Math.max(0, Math.min(width, height) / 2 - inset);
                            ctx.lineWidth = focused ? 1.5 : 1;
                            ctx.lineCap = "round";
                            var upper = ctx.createLinearGradient(0, 0, width * 0.48, 0);
                            upper.addColorStop(0, Qt.rgba(1, 1, 1, dark ? (focused ? 0.65 : 0.42) : 0.95));
                            upper.addColorStop(1, "transparent");
                            ctx.strokeStyle = upper;
                            ctx.beginPath();
                            ctx.arc(inset + r, inset + r, r, Math.PI, Math.PI * 1.5);
                            ctx.lineTo(width * 0.48, inset);
                            ctx.stroke();
                            var lower = ctx.createLinearGradient(width, height, width * 0.52, height);
                            lower.addColorStop(0, Qt.rgba(1, 1, 1, dark ? (focused ? 0.55 : 0.32) : 0.85));
                            lower.addColorStop(1, "transparent");
                            ctx.strokeStyle = lower;
                            ctx.beginPath();
                            ctx.arc(width - inset - r, height - inset - r, r, 0, Math.PI * 0.5);
                            ctx.lineTo(width * 0.52, height - inset);
                            ctx.stroke();
                        }
                    }
                    WGlyph {
                        kind: "search"
                        x: 11
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 18
                        color: pal.text2
                    }
                    TextInput {
                        selectionColor: Corners.ThemeColors.selectionFor("settings", root.darkMode)
                        selectedTextColor: Corners.ThemeColors.selectedTextFor("settings", root.darkMode)
                        id: searchInput
                        x: 38
                        width: parent.width - 64
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        selectByMouse: true
                        color: pal.text

                        font.family: pal.fam
                        font.pixelSize: 13
                        onTextChanged: prefsWindow.query = text
                    }
                    Text {
                        x: 38
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text === ""
                        text: "Search"
                        color: pal.text3
                        font.family: pal.fam
                        font.pixelSize: 13
                    }
                    Corners.ContinuousRectangle { cornerSmoothing: 0;   // clear button
                        visible: searchInput.text !== ""
                        anchors.right: parent.right
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14; radius: 7
                        color: pal.text3
                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -0.5
                            text: "\u00D7"
                            color: pal.sidebar
                            font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: searchInput.text = "" }
                    }
                }

                // account card (macOS: your name + picture at the top of the sidebar) → Users & Groups
                Corners.ContinuousRectangle { cornerSmoothing: 0;
                    id: acct
                    x: 12; y: search.y + search.height + 12
                    width: parent.width - 24; height: 60; radius: 12
                    visible: prefsWindow.query === ""
                    readonly property int idx: { for (var i = 0; i < prefsWindow.panes.length; i++) if (prefsWindow.panes[i].id === "users") return i; return 0; }
                    color: prefsWindow.cur === idx ? (prefsWindow.active ? pal.accent : pal.selInactive) : (acctMa.containsMouse ? pal.hover : "transparent")
                    Item {
                        id: acctPic
                        x: 6; anchors.verticalCenter: parent.verticalCenter; width: 44; height: 44
                        Item { id: acctMask; anchors.fill: parent; visible: false; layer.enabled: true; Corners.ContinuousRectangle { anchors.fill: parent; radius: width / 2; color: "black" } }
                        Corners.ContinuousRectangle { anchors.fill: parent; radius: width / 2; color: pal.ctrl }
                        Image {
                            anchors.fill: parent; source: "file://" + Quickshell.env("HOME") + "/.face"; sourceSize: Qt.size(96, 96)
                            fillMode: Image.PreserveAspectCrop; cache: false
                            layer.enabled: true; layer.effect: MultiEffect { maskEnabled: true; maskSource: acctMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                        }
                    }
                    Column {
                        x: 60; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 10
                        Text { width: parent.width; elide: Text.ElideRight; text: root.userName; color: prefsWindow.cur === acct.idx && prefsWindow.active ? "white" : pal.text; font.family: pal.fam; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { text: "Local Account"; color: prefsWindow.cur === acct.idx && prefsWindow.active ? Qt.rgba(1, 1, 1, 0.8) : pal.text2; font.family: pal.fam; font.pixelSize: 11 }
                    }
                    MouseArea { id: acctMa; anchors.fill: parent; hoverEnabled: true; onClicked: prefsWindow.go(acct.idx) }
                }

                // pane list (scrolls; sections separated by a gap, like System Settings)
                Flickable {
                    id: navFlick
                    x: 12; y: acct.visible ? acct.y + acct.height + 16 : search.y + search.height + 12
                    width: parent.width - 24
                    height: parent.height - y - 12
                    contentHeight: navCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: navCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: prefsWindow.filtered
                        delegate: Item {
                            id: navItem
                            required property int modelData
                            required property int index
                            readonly property bool gap: index > 0 && prefsWindow.panes[prefsWindow.filtered[index - 1]].sec !== prefsWindow.panes[modelData].sec
                            width: parent.width
                            height: 38 + (gap ? 18 : 0)
                        Corners.ContinuousRectangle { cornerSmoothing: 0;
                            id: navRow
                            readonly property int modelData: navItem.modelData
                            readonly property var p: prefsWindow.panes[modelData]
                            readonly property bool sel: prefsWindow.cur === modelData
                            y: navItem.gap ? 18 : 0
                            width: parent.width
                            height: 38
                            radius: 10
                            color: sel ? pal.accent
                                       : (navMa.containsMouse ? pal.hover : "transparent")

                            SGlyph {
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                kind: navRow.p.glyph || ""
                                wg: navRow.p.wg || ""
                                c1: navRow.p.c1
                                c2: navRow.p.c2
                            }
                            Text {
                                x: 42
                                anchors.verticalCenter: parent.verticalCenter
                                text: navRow.p.name
                                color: navRow.sel ? "white" : pal.text
                                font.family: pal.fam
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: navMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: prefsWindow.go(navRow.modelData)
                            }
                        }
                        }
                    }

                    Text {
                        visible: prefsWindow.filtered.length === 0
                        width: parent.width
                        topPadding: 14
                        horizontalAlignment: Text.AlignHCenter
                        text: "No Results"
                        color: pal.text2
                        font.family: pal.fam
                        font.pixelSize: 12
                    }
                }
                }
            }

            // ───────── toolbar ─────────
            Item {
                id: header
                x: sidebar.x + sidebar.width + 12
                width: parent.width - x - 12
                height: prefsWindow.headerHeight

                Rectangle {
                    id: historyPill
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    // Match MacTahoe's Nautilus history group and 40px controls.
                    width: 84; height: 40; radius: height / 2
                    color: "transparent"
                    border.width: 1
                    border.color: pal.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.90)
                    gradient: Gradient {
                        GradientStop { position: 0; color: pal.dark ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(0, 0, 0, 0.015) }
                        GradientStop { position: 1; color: pal.dark ? Qt.rgba(1, 1, 1, 0.02) : Qt.rgba(0, 0, 0, 0.01) }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 1; height: 18
                        color: pal.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                    }
                    Row {
                        spacing: 4
                        Repeater {
                            model: [ { dir: -1 }, { dir: 1 } ]
                            delegate: Rectangle {
                                id: navBtn
                                required property var modelData
                                readonly property bool ok: modelData.dir < 0 ? prefsWindow.backStack.length > 0
                                                                               : prefsWindow.fwdStack.length > 0
                                width: 40; height: 40; radius: 20
                                color: !ok ? "transparent" : navHover.pressed
                                    ? (pal.dark ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0.34, 0.34, 0.34, 0.25))
                                    : navHover.containsMouse
                                    ? (pal.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0.34, 0.34, 0.34, 0.10))
                                    : "transparent"
                                Canvas {
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    property color ink: pal.dark ? "#FDFDFD" : "#575757"
                                    onInkChanged: requestPaint()
                                    opacity: navBtn.ok ? 1 : 0.35
                                    onPaint: {
                                        var ctx = getContext("2d"); ctx.reset();
                                        ctx.strokeStyle = ink; ctx.lineWidth = 2;
                                        ctx.lineCap = "round"; ctx.lineJoin = "round";
                                        ctx.beginPath();
                                        ctx.moveTo(navBtn.modelData.dir < 0 ? 10.5 : 5.5, 2.5);
                                        ctx.lineTo(navBtn.modelData.dir < 0 ? 5 : 11, 8);
                                        ctx.lineTo(navBtn.modelData.dir < 0 ? 10.5 : 5.5, 13.5);
                                        ctx.stroke();
                                    }
                                }
                                MouseArea {
                                    id: navHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: navBtn.ok ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (!navBtn.ok) return;
                                        if (navBtn.modelData.dir < 0) prefsWindow.back();
                                        else prefsWindow.forward();
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    x: 116
                    anchors.verticalCenter: parent.verticalCenter
                    text: prefsWindow.panes[prefsWindow.cur].name
                    color: pal.text
                    font.family: pal.fam
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
                Corners.ContinuousRectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: pal.sep
                    opacity: flick.contentY > 4 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
            }

            // ───────── scrolling content ─────────
            Flickable {
                id: flick
                x: header.x
                y: prefsWindow.headerHeight
                width: header.width
                height: parent.height - y - 20
                contentWidth: width
                contentHeight: paneLoader.height + 36
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                Loader {
                    id: paneLoader
                    // nothing of Settings stays built while the window is closed
                    active: prefsWindow.visible
                    x: 8
                    y: 4
                    width: flick.width - 20
                    sourceComponent: ({
                        wifi: paneWifi, bluetooth: paneBt, network: paneNetwork, battery: paneBattery,
                        general: paneGeneral, appearance: paneAppearance, controlcenter: paneCC, dock: paneDesktopDock,
                        displays: paneDisplays, menubar: paneMenuBar, wallpaper: paneWallpaper,
                        notifications: paneNotif, sound: paneSound, focus: paneFocus,
                        lockscreen: paneLock, users: paneUsers, keyboard: paneKeyboard, mouse: paneMouse, trackpad: paneTrackpad,
                        apps: paneApps, about: paneAbout, system: paneSystem
                    })[prefsWindow.panes[prefsWindow.cur].id]
                    onLoaded: fadeIn.restart()
                }
            }
            Corners.ContinuousRectangle {   // thin overlay scrollbar
                visible: flick.contentHeight > flick.height + 1
                x: frame.width - 8
                y: flick.y + flick.visibleArea.yPosition * flick.height
                width: 4
                height: Math.max(28, flick.visibleArea.heightRatio * flick.height)
                radius: 2
                color: pal.text3
                opacity: flick.moving ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
        }

        // ═════════════ PANES ═════════════

        // ── General ──
        Component {
            id: paneGeneral
            Column {
                spacing: 10

                SLabel { t: pal; header: true; text: "Shell" }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Dock"
                        subtitle: "Show the Dock at the selected screen edge"
                        SSwitch { t: pal; checked: root.dockEnabled; onToggled: v => root.dockEnabled = v }
                    }
                    SRow {
                        t: pal
                        title: "Menu Bar"
                        subtitle: "Show the panel at the top of the screen. Spotlight, Control Center and the calendar belong to it."
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.barEnabled : true
                            onToggled: v => { if (root.bar) root.bar.barEnabled = v; }
                        }
                    }
                }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Spotlight & top bar menus"
                        subtitle: "Automatically follows Appearance → Light, Dark or Auto"
                    }
                }
                SLabel {
                    t: pal
                    text: "If you turn both off, reopen this window with:  qs -c macbar ipc call settings open"
                }

                SLabel { t: pal; header: true; text: "Desktop Widgets" }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Arrange widgets"
                        subtitle: (root.hub && root.hub.widgets && root.hub.widgets.editing)
                                  ? "Editing is on: drag a widget to move it, use the \u2212 badge to remove it, then click Stop Editing."
                                  : "Drag a widget to move it (it snaps to the grid). Use the \u2212 badge on a widget to remove it."
                        SButton {
                            t: pal
                            text: (root.hub && root.hub.widgets && root.hub.widgets.editing) ? "Stop Editing" : "Edit on Desktop"
                            onClicked: {
                                if (!root.hub || !root.hub.widgets) return;
                                if (root.hub.widgets.editing) root.hub.widgets.finishEditing();
                                else { root.hub.widgets.openGallery(); prefsWindow.visible = false; }
                            }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Widget size"
                        subtitle: "Makes every desktop widget smaller or larger (" + Math.round((root.hub && root.hub.widgets ? root.hub.widgets.widgetScale : 1) * 100) + "%)"
                        SSlider {
                            t: pal
                            from: 0.6; to: 1.5; stepSize: 0.05
                            value: root.hub && root.hub.widgets ? root.hub.widgets.widgetScale : 1
                            leftLabel: "Small"; rightLabel: "Large"
                            onMoved: v => { if (root.hub && root.hub.widgets) root.hub.widgets.widgetScale = Math.round(v * 100) / 100; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Temperature unit"
                        subtitle: "Used by the Weather widget"
                        SSegmented {
                            t: pal
                            model: ["\u00B0C", "\u00B0F"]
                            segWidth: 56
                            current: root.hub && root.hub.widgets && root.hub.widgets.tempUnit === "F" ? 1 : 0
                            onPicked: i => { if (root.hub && root.hub.widgets) root.hub.widgets.tempUnit = (i === 1 ? "F" : "C"); }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Weather location"
                        subtitle: "Automatic uses your IP address; or type a city name"
                        SSegmented {
                            t: pal
                            model: ["Automatic", "City"]
                            segWidth: 80
                            current: root.hub && root.hub.widgets && root.hub.widgets.locMode === "city" ? 1 : 0
                            onPicked: i => { if (root.hub && root.hub.widgets) root.hub.widgets.locMode = (i === 1 ? "city" : "auto"); }
                        }
                    }
                    SRow {
                        t: pal
                        visible: root.hub && root.hub.widgets && root.hub.widgets.locMode === "city"
                        title: "City"
                        subtitle: "For example: Riyadh, Dubai, London"
                        Corners.ContinuousRectangle { cornerSmoothing: 0;
                            width: 210; height: 26; radius: 6
                            color: pal.ctrl
                            border.width: 1
                            border.color: pal.cardBorder
                            TextInput {
                                selectionColor: Corners.ThemeColors.selectionFor("settings", root.darkMode)
                                selectedTextColor: Corners.ThemeColors.selectedTextFor("settings", root.darkMode)
                                id: wxCityInput
                                anchors.fill: parent
                                anchors.leftMargin: 8; anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                selectByMouse: true
                                color: pal.text

                                font.family: pal.fam
                                font.pixelSize: 12
                                text: root.hub && root.hub.widgets ? root.hub.widgets.cityName : ""
                                onEditingFinished: { if (root.hub && root.hub.widgets) root.hub.widgets.cityName = text; }
                            }
                        }
                    }
                }

                SLabel { t: pal; header: true; text: "Add a Widget" }
                SCard {
                    t: pal
                    Repeater {
                        model: [
                            { type: "weather",  name: "Weather",  hint: "Current conditions, hourly and daily forecast", styles: [["system", "System"]] },
                            { type: "calendar", name: "Calendar", hint: "Today's date and the month", styles: [["system", "System"]] },
                            { type: "clock",    name: "Clock",    hint: "Analog clock face", styles: [["system", "System"]] },
                            { type: "player",   name: "Player",   hint: "Now Playing with controls and lyrics", styles: [["system", "System"]] },
                            { type: "image",    name: "Image",    hint: "Your own picture (you choose the file)", styles: [["normal", "Photo"]] }
                        ]
                        delegate: SRow {
                            id: addRow
                            required property var modelData
                            property int styleIdx: 0
                            readonly property var wdg: root.hub ? root.hub.widgets : null
                            t: pal
                            title: modelData.name
                            subtitle: modelData.hint + (wdg ? "  \u00B7  " + (wdg.rev >= 0 ? wdg.count(modelData.type) : 0) + " on desktop" : "")
                            Row {
                                spacing: 8
                                SSegmented {
                                    t: pal
                                    visible: addRow.modelData.styles.length > 1
                                    model: addRow.modelData.styles.map(function (s) { return s[1]; })
                                    segWidth: 84
                                    current: addRow.styleIdx
                                    onPicked: i => addRow.styleIdx = i
                                }
                                Repeater {
                                    model: ["small", "medium", "large"]
                                    delegate: SButton {
                                        id: widgetSizeButton
                                        required property string modelData
                                        t: pal
                                        text: "+ " + ({ small: "S", medium: "M", large: "L" })[modelData]
                                        onClicked: {
                                            if (!addRow.wdg) return;
                                            if (addRow.modelData.type === "image") addRow.wdg.pickImage("", widgetSizeButton.modelData);
                                            else addRow.wdg.addWidget(addRow.modelData.type, "system", widgetSizeButton.modelData);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                SLabel {
                    t: pal
                    visible: root.hub && root.hub.widgets && root.hub.widgets.pickError !== ""
                    text: root.hub && root.hub.widgets ? root.hub.widgets.pickError : ""
                    color: pal.danger
                }
                SLabel {
                    t: pal
                    text: "Image widgets: pick a picture with + S / M / L (needs zenity, kdialog or yad). To change it later, use Edit on Desktop and press Choose Image on the widget."
                }

                SLabel { t: pal; header: true; text: "Sound" }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Play user interface sound effects"
                        subtitle: "Volume pop, notifications, screenshots, charger, emptying the Trash and the lock screen"
                        SSwitch { t: pal; checked: root.bar ? root.bar.uiSounds : true; onToggled: v => { if (root.bar) root.bar.uiSounds = v; } }
                    }
                }

                SLabel { t: pal; header: true; text: "Lock Screen" }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Album background when the cover is enlarged"
                        subtitle: "Tap the album cover on the lock screen: the background turns into a blurred version of the artwork"
                        SSwitch { t: pal; checked: root.bar ? root.bar.lockArtBackground : true; onToggled: v => { if (root.bar) root.bar.lockArtBackground = v; } }
                    }
                }

                SLabel { t: pal; header: true; text: "Game Mode" }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Game Mode"
                        subtitle: "Turns off blur, shadows, animations and Liquid Glass, pauses an animated wallpaper and uses the performance power profile. Everything comes back when it turns off."
                        SSwitch { t: pal; checked: root.bar ? root.bar.gamingMode : false; onToggled: v => { if (root.bar) root.bar.gamingMode = v; } }
                    }
                    SRow {
                        t: pal
                        title: "Turn on automatically for fullscreen games"
                        subtitle: root.bar && root.bar.gamingAutoActive ? "On now: a game is fullscreen" : "Steam, Sober (Roblox), Minecraft, Lutris, Heroic and Windows games"
                        SSwitch { t: pal; checked: root.bar ? root.bar.gamingAuto : true; onToggled: v => { if (root.bar) root.bar.gamingAuto = v; } }
                    }
                }
            }
        }

        // ── Menu Bar ──
        Component {
            id: paneMenuBar
            Column {
                spacing: 10

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Menu Bar style"
                        subtitle: (root.bar && root.bar.barStyle === "liquid" && root.bar.glassState === "failed")
                                  ? "Liquid Glass couldn't start (install qt6-shadertools)"
                                  : "Style of the menus and popovers"
                        SSegmented {
                            t: pal
                            model: ["Normal Blur", "Apple Liquid Glass"]
                            segWidth: 128
                            current: (root.bar && root.bar.barStyle === "liquid") ? 1 : 0
                            onPicked: i => { if (root.bar) root.bar.barStyle = (i === 1 ? "liquid" : "blur"); }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Liquid Glass bar"
                        subtitle: "The menu bar strip itself is Liquid Glass, refracting the wallpaper and windows under it (needs Apple Liquid Glass style)"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.barGlass : true
                            onToggled: v => { if (root.bar) root.bar.barGlass = v; }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Menu Bar and widget size"
                        subtitle: "Scales the bar widgets; the left and right groups stay tucked into the screen corners"
                        SSlider {
                            t: pal; from: 22; to: 48; stepSize: 1
                            value: root.bar ? root.bar.barHeight : 28
                            leftLabel: "Compact"; rightLabel: "Large"
                            onMoved: v => { if (root.bar) root.bar.barHeight = Math.round(v); }
                        }
                    }
                }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Menu Bar logo"
                        subtitle: "Choose the Arch mark, Apple logo, or a custom image"
                        SSegmented {
                            t: pal
                            model: ["Arch", "Apple", "Custom"]
                            segWidth: 68
                            current: !root.bar || root.bar.barLogoMode === "arch" ? 0 : (root.bar.barLogoMode === "apple" ? 1 : 2)
                            onPicked: i => {
                                if (root.bar) root.bar.barLogoMode = ["arch", "apple", "custom"][i];
                            }
                        }
                    }
                    SRow {
                        t: pal
                        visible: root.bar && root.bar.barLogoMode === "custom"
                        title: "Custom image path"
                        subtitle: "Enter a local image path (PNG, SVG, or other supported format)"
                        Row {
                            spacing: 8
                            Corners.ContinuousRectangle { cornerSmoothing: 0;
                                width: 210; height: 26; radius: 6
                                color: pal.ctrl
                                border.width: 1
                                border.color: pal.cardBorder
                                TextInput {
                                    selectionColor: Corners.ThemeColors.selectionFor("settings", root.darkMode)
                                    selectedTextColor: Corners.ThemeColors.selectedTextFor("settings", root.darkMode)
                                    id: barLogoPathInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8; anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    selectByMouse: true
                                    color: pal.text

                                    font.family: pal.fam
                                    font.pixelSize: 12
                                    text: root.bar ? root.bar.barCustomLogoPath : ""
                                    onTextEdited: { if (root.bar) root.bar.barCustomLogoPath = text; }
                                    Connections {
                                        target: root.bar
                                        function onBarCustomLogoPathChanged() {
                                            if (root.bar && barLogoPathInput.text !== root.bar.barCustomLogoPath)
                                                barLogoPathInput.text = root.bar.barCustomLogoPath;
                                        }
                                    }
                                }
                                Text {
                                    visible: barLogoPathInput.text === ""
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "~/Pictures/logo.png"
                                    color: pal.text3
                                    font.family: pal.fam
                                    font.pixelSize: 12
                                }
                            }
                            SButton {
                                t: pal; text: "Clear"
                                onClicked: { if (root.bar) root.bar.barCustomLogoPath = ""; }
                            }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Bar background"
                        subtitle: "A separate layer (macbarbg) so Hyprland can blur it. Needs: layerrule = blur, macbarbg"
                        SSlider {
                            t: pal
                            from: 0; to: 0.6; stepSize: 0.01
                            value: root.bar ? root.bar.barBgOpacity : 0.10
                            leftLabel: "Hidden"; rightLabel: "Tinted"
                            onMoved: v => { if (root.bar) root.bar.barBgOpacity = v; }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "24-hour clock"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.use24h : false
                            onToggled: v => { if (root.bar) root.bar.use24h = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Show date"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.showDate : false
                            onToggled: v => { if (root.bar) root.bar.showDate = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Show seconds"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.showSeconds : false
                            onToggled: v => { if (root.bar) root.bar.showSeconds = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Week starts on Monday"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.weekStartsMonday : false
                            onToggled: v => { if (root.bar) root.bar.weekStartsMonday = v; }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Battery percentage"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.showBatteryPercent : false
                            onToggled: v => { if (root.bar) root.bar.showBatteryPercent = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Real-time glass"
                        subtitle: "Keep window captures live so popovers, Spotlight and the Dock open on current pixels. Turn off to save GPU."
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.glassRealtime : true
                            onToggled: v => { if (root.bar) root.bar.glassRealtime = v; }
                        }
                    }
                }

                SLabel { t: pal; header: true; text: "Top Bar Widgets" }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Apple menu"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("appleMenu") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("appleMenu", v); } }
                    }
                    SRow {
                        t: pal; title: "Application menus"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("appMenus") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("appMenus", v); } }
                    }
                    SRow {
                        t: pal; title: "Workspace switcher"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("workspaces") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("workspaces", v); } }
                    }
                    SRow {
                        t: pal; title: "System tray"
                        SSwitch { t: pal; checked: root.bar ? root.bar.showTray : true; onToggled: v => { if (root.bar) root.bar.showTray = v; } }
                    }
                    SRow {
                        t: pal; title: "Volume"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("volume") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("volume", v); } }
                    }
                    SRow {
                        t: pal; title: "Bluetooth"
                        subtitle: "Show the Bluetooth status icon, even while Bluetooth is off"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("bluetooth") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("bluetooth", v); } }
                    }
                    SRow {
                        t: pal; title: "Keyboard layout"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("keyboard") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("keyboard", v); } }
                    }
                    SRow {
                        t: pal; title: "Notifications"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("notifications") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("notifications", v); } }
                    }
                    SRow {
                        t: pal; title: "Wi-Fi and network"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("wifi") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("wifi", v); } }
                    }
                    SRow {
                        t: pal; title: "Spotlight search"
                        SSwitch { t: pal; checked: root.bar ? root.bar.showSearch : true; onToggled: v => { if (root.bar) root.bar.showSearch = v; } }
                    }
                    SRow {
                        t: pal; title: "Privacy indicators"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("privacy") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("privacy", v); } }
                    }
                    SRow {
                        t: pal; title: "Control Center"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("controlCenter") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("controlCenter", v); } }
                    }
                    SRow {
                        t: pal; title: "Clock and calendar"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("clock") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("clock", v); } }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Keep clipboard history"
                        subtitle: "Spotlight \u2192 Clipboard (needs wl-clipboard and cliphist). Turn off to stop recording what you copy"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.clipHistory : false
                            onToggled: v => { if (root.bar) root.bar.clipHistory = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Paste after choosing"
                        subtitle: "Insert the chosen clipboard entry or emoji into the focused app (Shift+Return only copies)"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.clipAutoPaste : false
                            onToggled: v => { if (root.bar) root.bar.clipAutoPaste = v; }
                        }
                    }
                }
                SLabel { t: pal; header: true; text: "Screenshots" }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Save to a folder"
                        subtitle: "Press Print to select an area. Turn off to only copy it to the clipboard"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.screenshotSave : true
                            onToggled: v => { if (root.bar) root.bar.screenshotSave = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Save location"
                        subtitle: "Leave empty for ~/Pictures/Screenshots"
                        Row {
                            spacing: 8
                            Corners.ContinuousRectangle { cornerSmoothing: 0;
                                width: 200; height: 24; radius: 6
                                color: pal.ctrl
                                border.width: 1
                                border.color: pal.cardBorder
                                TextInput {
                                    selectionColor: Corners.ThemeColors.selectionFor("settings", root.darkMode)
                                    selectedTextColor: Corners.ThemeColors.selectedTextFor("settings", root.darkMode)
                                    id: shotDirInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8; anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    selectByMouse: true
                                    color: pal.text

                                    font.family: pal.fam
                                    font.pixelSize: 12
                                    text: root.bar ? root.bar.screenshotDir : ""
                                    onTextEdited: { if (root.bar) root.bar.screenshotDir = text; }
                                }
                                Text {
                                    visible: shotDirInput.text === ""
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "~/Pictures/Screenshots"
                                    color: pal.text3
                                    font.family: pal.fam
                                    font.pixelSize: 12
                                }
                            }
                            SButton { t: pal; text: "Choose\u2026"; onClicked: shotPick.running = true }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Quick folders"
                        SSegmented {
                            t: pal
                            property var dirs: ["~/Pictures/Screenshots", "~/Pictures", "~/Desktop", "~/Downloads"]
                            model: ["Screenshots", "Pictures", "Desktop", "Downloads"]
                            segWidth: 84
                            current: {
                                var d = root.bar ? root.bar.screenshotDir.replace(/\/+$/, "") : "";
                                return dirs.indexOf(d === "" ? dirs[0] : d);
                            }
                            onPicked: i => { if (root.bar) root.bar.screenshotDir = dirs[i]; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Copy to clipboard"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.screenshotClipboard : true
                            onToggled: v => { if (root.bar) root.bar.screenshotClipboard = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Show a notification"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.screenshotNotify : true
                            onToggled: v => { if (root.bar) root.bar.screenshotNotify = v; }
                        }
                    }
                }
                SLabel {
                    t: pal
                    text: "Bind the Print key:  bind = , Print, exec, qs -c macbar ipc call screenshot region.  Choose\u2026 needs zenity, kdialog or yad; otherwise type the path. Screenshots need grim."
                }
                Process {
                    id: shotPick
                    command: ["sh", "-c",
                        "if command -v zenity >/dev/null 2>&1; then zenity --file-selection --directory --title='Screenshot folder' 2>/dev/null; "
                        + "elif command -v kdialog >/dev/null 2>&1; then kdialog --getexistingdirectory \"$HOME\" 2>/dev/null; "
                        + "elif command -v yad >/dev/null 2>&1; then yad --file --directory --title='Screenshot folder' 2>/dev/null; fi"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            var d = text.trim();
                            if (d !== "" && root.bar) root.bar.screenshotDir = d;
                        }
                    }
                }
                SLabel {
                    t: pal
                    text: "Translucency, accent color, appearance and font are in Appearance. Commands (terminal, launcher, files, clipboard) can be edited in ~/.config/macbar/settings.json."
                }
            }
        }

        // ── Dock ──
        Component {
            id: paneDock
            Column {
                spacing: 10

                // live preview
                Corners.ContinuousRectangle {
                    id: pv
                    width: parent.width
                    height: 150
                    radius: 10
                    clip: true
                    border.width: 1
                    border.color: pal.cardBorder
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#4158D0" }
                        GradientStop { position: 0.55; color: "#9B59D0" }
                        GradientStop { position: 1.0; color: "#F3805A" }
                    }
                    readonly property real base: root.iconSize * 0.5
                    readonly property var apps: root.items.filter(function (i) {
                        return i.kind === "app" && !i.special;
                    }).slice(0, 6)

                    Corners.ContinuousRectangle {
                        id: pbar
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10 + root.margin * 0.5
                        width: prow.width + 16
                        height: pv.base + 14
                        radius: root.cornerRadius * 0.6
                        color: root.dockDark ? Qt.rgba(0.10, 0.10, 0.11, root.glassOpacity)
                                             : Qt.rgba(1, 1, 1, root.glassOpacity * 0.55)
                        border.width: 1
                        border.color: root.dockDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.45)
                    }
                    Row {
                        id: prow
                        anchors.horizontalCenter: pbar.horizontalCenter
                        anchors.bottom: pbar.bottom
                        anchors.bottomMargin: 7
                        spacing: root.spacing * 0.5
                        Repeater {
                            model: pv.apps
                            delegate: Item {
                                id: pi
                                required property var modelData
                                required property int index
                                width: pv.base
                                height: pv.base
                                readonly property int mid: Math.min(2, pv.apps.length - 1)
                                readonly property int d: Math.abs(index - mid)
                                readonly property real f: d === 0 ? 1 : (d === 1 ? 0.5 : (d === 2 ? 0.12 : 0))
                                Image {
                                    id: pimg
                                    anchors.fill: parent
                                    visible: false
                                    source: root.iconSrc(pi.modelData.icon)
                                    sourceSize: Qt.size(96, 96)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }
                                MultiEffect {
                                    anchors.fill: pimg
                                    source: pimg
                                    layer.enabled: Corners.IconStyle.effectMode !== 0
                                    layer.effect: Corners.IconStyleEffect {}
                                    transformOrigin: Item.Bottom
                                    scale: root.magnificationEnabled ? 1 + (root.magnification - 1) * pi.f : 1
                                    Behavior on scale { NumberAnimation { duration: 120 } }
                                }
                            }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Size"
                        SSlider {
                            t: pal
                            from: 32; to: 128; stepSize: 1
                            value: root.iconSize
                            leftLabel: "Small"; rightLabel: "Large"
                            onMoved: v => root.iconSize = Math.round(v)
                        }
                    }
                    SRow {
                        t: pal
                        title: "Magnification"
                        subtitle: "Enlarge icons as the pointer moves over them"
                        SSwitch {
                            t: pal
                            checked: root.magnificationEnabled
                            onToggled: v => root.magnificationEnabled = v
                        }
                    }
                    SRow {
                        t: pal
                        title: "Magnification amount"
                        opacity: root.magnificationEnabled ? 1 : 0.45
                        SSlider {
                            t: pal
                            enabled: root.magnificationEnabled
                            from: 1.1; to: 2.5; stepSize: 0.05
                            value: root.magnification
                            leftLabel: "Min"; rightLabel: "Max"
                            onMoved: v => root.magnification = v
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Icon & widget style"
                        subtitle: "Change the look of all icons and widgets in Appearance"
                        SButton { t: pal; text: "Appearance…"; onClicked: root.openPrefs("appearance") }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Icon spacing"
                        SSlider {
                            t: pal
                            from: 0; to: 20; stepSize: 1
                            value: root.spacing
                            leftLabel: "Tight"; rightLabel: "Loose"
                            onMoved: v => root.spacing = Math.round(v)
                        }
                    }
                    SRow {
                        t: pal
                        title: "Distance from screen edge"
                        SSlider {
                            t: pal
                            from: 0; to: 40; stepSize: 1
                            value: root.margin
                            leftLabel: "Flush"; rightLabel: "Floating"
                            onMoved: v => root.margin = Math.round(v)
                        }
                    }
                }
                SLabel { t: pal; text: "Changes apply to the Dock immediately." }
            }
        }

        // ── Appearance ──
        Component {
            id: paneAppearance
            Column {
                spacing: 16

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Appearance"
                        subtitle: "Choose the appearance of your desktop and apps."
                        Row {
                            spacing: 14
                            SThemeTile {
                                t: pal; label: "Auto"; split: true
                                selected: root.appearanceMode === "auto"
                                onClicked: root.setAppearance("auto")
                            }
                            SThemeTile {
                                t: pal; label: "Light"; dark: false
                                selected: root.appearanceMode === "light"
                                onClicked: root.setAppearance("light")
                            }
                            SThemeTile {
                                t: pal; label: "Dark"; dark: true
                                selected: root.appearanceMode === "dark"
                                onClicked: root.setAppearance("dark")
                            }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Liquid Glass"
                        subtitle: "Clear glass or maximum backdrop blur."
                        Row {
                            spacing: 14
                            GlassMaterialTile {
                                t: pal
                                tinted: false
                                selected: !Corners.GlassMaterial.tinted
                                onClicked: Corners.GlassMaterial.setMode("clear")
                            }
                            GlassMaterialTile {
                                t: pal
                                tinted: true
                                selected: Corners.GlassMaterial.tinted
                                onClicked: Corners.GlassMaterial.setMode("tinted")
                            }
                        }
                    }
                }

                SLabel { t: pal; header: true; text: "Theme" }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Color"
                        subtitle: Corners.ThemeColors.multicolor ? "Each app uses its own accent color" : "Buttons, menus and controls"
                        ThemeColorPicker { t: pal }
                    }
                    SRow {
                        t: pal
                        title: "Text highlight color"
                        subtitle: "The background of selected text"
                        SPopUp {
                            t: pal
                            width: 180
                            accessibleLabel: "Text highlight color"
                            model: Corners.ThemeColors.highlightChoices.map(function(c) { return c.name; })
                            colorSwatches: Corners.ThemeColors.highlightChoices.map(function(c) {
                                return c.id === "automatic" ? "multicolor" : (c.id === "custom" ? Corners.ThemeColors.settings.customHighlight : c.c);
                            })
                            current: Math.max(0, Corners.ThemeColors.highlightChoices.findIndex(function(c) { return c.id === Corners.ThemeColors.highlight; }))
                            allowReselect: true
                            onPicked: index => {
                                const choice = Corners.ThemeColors.highlightChoices[index];
                                if (choice.id === "custom") highlightColorDialog.open();
                                else Corners.ThemeColors.setHighlight(choice.id);
                            }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Preview"
                        TextInput {
                            selectionColor: Corners.ThemeColors.selectionFor("settings", root.darkMode)
                            selectedTextColor: Corners.ThemeColors.selectedTextFor("settings", root.darkMode)
                            text: "Select this text to preview"
                            readOnly: true
                            selectByMouse: true
                            persistentSelection: true
                            color: pal.text
                            font.family: pal.fam
                            font.pixelSize: 12
                            Component.onCompleted: selectAll()
                        }
                    }
                }
                ColorDialog {
                    id: highlightColorDialog
                    title: "Text highlight color"
                    selectedColor: Corners.ThemeColors.settings.customHighlight
                    onAccepted: Corners.ThemeColors.setHighlight("custom", selectedColor.toString())
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Icon & widget style"
                        Row {
                            spacing: 8
                            Repeater {
                                model: ["default", "dark", "clear", "tinted"]
                                IconStyleTile { required property string modelData; t: pal; choice: modelData }
                            }
                        }
                    }
                    SRow {
                        t: pal; visible: Corners.IconStyle.mode === "dark"
                        title: "Dark appearance"
                        SPopUp {
                            t: pal; model: ["Always", "Auto"]
                            current: Corners.IconStyle.settings.darkAppearance === "auto" ? 1 : 0
                            onPicked: i => Corners.IconStyle.setValue("darkAppearance", i === 0 ? "always" : "auto")
                        }
                    }
                    SRow {
                        t: pal; visible: Corners.IconStyle.mode === "clear"
                        title: "Clear appearance"
                        SPopUp {
                            t: pal; model: ["Light", "Dark", "Auto"]
                            current: Math.max(0, ["light", "dark", "auto"].indexOf(Corners.IconStyle.settings.clearAppearance))
                            onPicked: i => Corners.IconStyle.setValue("clearAppearance", ["light", "dark", "auto"][i])
                        }
                    }
                    SRow {
                        t: pal
                        title: Corners.IconStyle.mode === "tinted" ? "Icon, widget, & folder color" : "Folder color"
                        SPopUp {
                            t: pal; width: 190
                            readonly property string colorKey: Corners.IconStyle.mode === "tinted" ? "tintColor" : "folderColor"
                            readonly property string value: Corners.IconStyle.settings[colorKey]
                            readonly property var choices: Corners.ThemeColors.colorChoices.slice(1)
                            model: ["Automatic"].concat(choices.map(c => c.name)).concat(["Other…"])
                            colorSwatches: [String(Corners.IconStyle.mode === "tinted" ? Corners.IconStyle.tintColor : Corners.IconStyle.folderColor)]
                                .concat(choices.map(c => c.c)).concat([value === "automatic" ? "#0a84ff" : value])
                            current: value === "automatic" ? 0 : (choices.findIndex(c => c.c === value) < 0 ? 9 : choices.findIndex(c => c.c === value) + 1)
                            allowReselect: true
                            accessibleLabel: "Icon and folder color"
                            onPicked: i => {
                                if (i === 9) { iconColorDialog.targetKey = colorKey; iconColorDialog.selectedColor = value === "automatic" ? Corners.IconStyle.folderColor : value; iconColorDialog.open(); }
                                else Corners.IconStyle.setValue(colorKey, i === 0 ? "automatic" : choices[i - 1].c);
                            }
                        }
                    }
                }
                ColorDialog {
                    id: iconColorDialog
                    property string targetKey: "folderColor"
                    title: "Icon and folder color"
                    onAccepted: Corners.IconStyle.setValue(targetKey, selectedColor.toString())
                }

                SLabel { t: pal; header: true; text: "Glass & Corners" }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Translucency"
                        subtitle: root.dockStyle === "liquid" ? "How much tint the glass adds over the refraction"
                                                              : "How frosted the Dock's glass looks"
                        SSlider {
                            t: pal
                            from: 0.0; to: 0.85; stepSize: 0.01
                            value: root.glassOpacity
                            leftLabel: "Clear"; rightLabel: "Frosted"
                            onMoved: v => root.setLook("glassOpacity", v)
                        }
                    }
                    SRow {
                        t: pal
                        visible: root.dockStyle === "liquid"
                        title: "Liquid strength"
                        subtitle: "Refraction, magnification and colour fringing of the glass"
                        SSlider {
                            t: pal
                            from: 0.5; to: 2.5; stepSize: 0.05
                            value: root.glassLiquid
                            leftLabel: "Subtle"; rightLabel: "Very liquid"
                            onMoved: v => root.setLook("glassLiquid", v)
                        }
                    }
                    SRow {
                        t: pal
                        title: "Corner radius"
                        subtitle: "Shared by the blurred Dock and the Liquid Glass shape"
                        SSlider {
                            t: pal
                            from: 0; to: 32; stepSize: 1
                            value: root.cornerRadius
                            leftLabel: "Square"; rightLabel: "Round"
                            onMoved: v => root.cornerRadius = Math.round(v)
                        }
                    }
                    CornerSmoothingSettingsRow { host: root; t: pal }
                }

                SLabel { t: pal; header: true; text: "Typography" }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Font"
                        subtitle: "Used for labels and menus"
                        SSegmented {
                            t: pal
                            model: ["SF Pro Text", "SF Pro Display", "System"]
                            segWidth: 76
                            current: root.fontFamily === "SF Pro Text" ? 0 : (root.fontFamily === "SF Pro Display" ? 1 : 2)
                            onPicked: i => root.setLook("fontFamily", ["SF Pro Text", "SF Pro Display", "sans-serif"][i])
                        }
                    }
                }
                SLabel { t: pal; text: root.dockStyle === "liquid"
                                       ? "Liquid Glass refracts the wallpaper and windows behind the Dock in real time. Corner radius also shapes the glass."
                                       : "The blur behind the Dock comes from your Hyprland layer rule; translucency only controls the tint." }
            }
        }

        // ── Behavior ──
        Component {
            id: paneBehavior
            Column {
                spacing: 10

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Automatically hide and show the Dock"
                        subtitle: root.hideMode === "smart" ? "Hides while a tiled, maximized or fullscreen window needs the space"
                                : (root.hideMode === "always" ? "Always hidden until the pointer touches the screen edge"
                                                              : "Always visible and reserves screen space")
                        SSegmented {
                            t: pal
                            model: ["Smart", "Always", "Never"]
                            segWidth: 64
                            current: root.hideMode === "smart" ? 0 : (root.hideMode === "always" ? 1 : 2)
                            onPicked: i => root.hideMode = ["smart", "always", "never"][i]
                        }
                    }
                    SRow {
                        t: pal
                        visible: root.hideMode !== "never"
                        title: "Hide delay"
                        SSlider {
                            t: pal
                            from: 0; to: 1500; stepSize: 50
                            value: root.hideDelay
                            leftLabel: "Instant"; rightLabel: "1.5 s"
                            onMoved: v => root.hideDelay = Math.round(v)
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Show Dock on"
                        SSegmented {
                            t: pal
                            model: ["All Displays", "Primary Only"]
                            segWidth: 96
                            current: root.monitor === "" ? 0 : 1
                            onPicked: i => {
                                if (i === 0) root.monitor = "";
                                else if (Quickshell.screens.length > 0) root.monitor = Quickshell.screens[0].name;
                            }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Show labels"
                        subtitle: "Display an app's name when you hover its icon"
                        SSwitch { t: pal; checked: root.showLabels; onToggled: v => root.showLabels = v }
                    }
                    SRow {
                        t: pal
                        title: "Show window previews"
                        subtitle: "Open windows appear as live previews next to the Trash, each with its app's icon"
                        SSwitch { t: pal; checked: root.showThumbs; onToggled: v => root.showThumbs = v }
                    }
                    SRow {
                        t: pal
                        title: "Live window capture"
                        subtitle: "Capture open windows for the previews. Turn off and the previews show the app icon instead (Liquid Glass is not affected)"
                        SSwitch { t: pal; checked: root.windowCapture; onToggled: v => root.windowCapture = v }
                    }
                    SRow {
                        t: pal
                        title: "Show indicators for open applications"
                        SSwitch { t: pal; checked: root.showIndicators; onToggled: v => root.showIndicators = v }
                    }
                    SRow {
                        t: pal
                        title: "Animate opening applications"
                        subtitle: "Icons bounce while an app is launching"
                        SSwitch { t: pal; checked: root.bounceOnLaunch; onToggled: v => root.bounceOnLaunch = v }
                    }
                    SRow {
                        t: pal
                        title: "Show Trash in the Dock"
                        SSwitch { t: pal; checked: root.showTrash; onToggled: v => root.showTrash = v }
                    }
                }
            }
        }

        // ── Applications ──
        Component {
            id: paneApps
            Column {
                id: appsCol
                spacing: 10
                readonly property int pinCount: root.items.filter(function (i) {
                    return i.kind === "app" && i.pinned && !i.special;
                }).length

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "App menu"
                        subtitle: "Choose which app menu opens from the Dock or Super+A"
                        SPopUp {
                            t: pal
                            width: 190
                            accessibleLabel: "App menu"
                            model: ["Apps in Spotlight", "Launchpad"]
                            current: Corners.AppMenu.spotlight ? 0 : 1
                            onPicked: index => {
                                if (index === 0 && root.bar) root.bar.spotlightEnabled = true;
                                Corners.AppMenu.setMode(index === 0 ? "spotlight" : "launchpad");
                            }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Show " + Corners.AppMenu.label + " in Dock"
                        subtitle: "Super+A opens the selected app menu even when the icon is hidden"
                        iconSource: root.launchpadIcon
                        SSwitch {
                            t: pal
                            checked: root.launchpadPinned
                            onToggled: value => root.setLaunchpadPinned(value)
                        }
                    }
                }

                SLabel { t: pal; header: true; text: "Kept in Dock" }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        visible: appsCol.pinCount === 0
                        title: "No apps are kept in the Dock"
                        subtitle: "Right-click a running app and choose Keep in Dock."
                    }
                    Repeater {
                        model: root.items
                        delegate: SRow {
                            id: appRow
                            required property var modelData
                            t: pal
                            visible: modelData.kind === "app" && modelData.pinned === true && !modelData.special
                            title: modelData.name || ""
                            iconSource: modelData.icon ? root.iconSrc(modelData.icon) : ""
                            SButton {
                                t: pal
                                text: "Remove"
                                onClicked: root.togglePin(appRow.modelData)
                            }
                        }
                    }
                }
                SLabel { t: pal; text: "Drag icons in the Dock to reorder them. Pins are saved to ~/.config/macdock/pinned.json." }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Reset Dock Items"
                        subtitle: "Go back to the default set of apps"
                        SButton { t: pal; text: "Reset"; onClicked: root.resetPins() }
                    }
                }
            }
        }

        // ── System Information ──
        Component {
            id: paneSystem
            Column {
                spacing: 10
                readonly property var systemAbout: root.hub ? root.hub.about : null
                Component.onCompleted: if (systemAbout) systemAbout.refresh()
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: systemAbout ? systemAbout.info.deviceName || "This Computer" : "This Computer"
                        subtitle: systemAbout ? systemAbout.info.distro || "Linux" : "Linux"
                        iconSource: Qt.resolvedUrl(systemAbout && systemAbout.info.portable ? "assets/about/laptop.svg" : "assets/about/desktop.svg")
                        SButton { t: pal; text: "Overview…"; onClicked: if (systemAbout) systemAbout.open() }
                    }
                }
                SLabel { t: pal; header: true; text: "Hardware" }
                SCard {
                    t: pal
                    Repeater {
                        model: systemAbout ? systemAbout.hardwareRows : []
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.label
                            subtitle: modelData.value
                        }
                    }
                }
                SLabel { t: pal; header: true; text: "Software & Storage" }
                SCard {
                    t: pal
                    Repeater {
                        model: systemAbout ? systemAbout.softwareRows : []
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.label
                            subtitle: modelData.value
                        }
                    }
                }
            }
        }

        // ═════════ macOS-style panes linked to the shell ═════════

        // ── Wi-Fi ──
        Component {
            id: paneWifi
            Column {
                id: wifiPane
                spacing: 10
                property string ethInfo: ""
                Component.onCompleted: { if (root.bar) root.bar.scanWifi(); ethProc.running = true; }
                Timer { interval: 4000; repeat: true; running: prefsWindow.visible; onTriggered: if (!ethProc.running) ethProc.running = true }
                Process {
                    id: ethProc
                    command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev 2>/dev/null | awk -F: '$2==\"ethernet\"' | head -1 | while IFS=: read -r d t st c; do ip=$(ip -4 -o addr show \"$d\" 2>/dev/null | awk '{print $4}' | head -1); sp=$(cat /sys/class/net/$d/speed 2>/dev/null); printf '%s\t%s\t%s\t%s\t%s' \"$d\" \"$st\" \"$c\" \"$ip\" \"$sp\"; done"]
                    stdout: StdioCollector { onStreamFinished: wifiPane.ethInfo = text.trim() }
                }
                readonly property var eth: { var f = ethInfo.split("\t"); return f.length >= 2 ? { dev: f[0], up: f[1].indexOf("connected") === 0, con: f[2] || "", ip: f[3] || "", speed: f[4] || "" } : null; }
                // Ethernet first: it's what you're actually online through when it's plugged in
                SCard {
                    t: pal
                    visible: wifiPane.eth !== null
                    SRow {
                        t: pal; title: "Ethernet"
                        subtitle: !wifiPane.eth ? "" : (wifiPane.eth.up
                                  ? "Connected" + (wifiPane.eth.ip !== "" ? " · " + wifiPane.eth.ip : "") + (parseInt(wifiPane.eth.speed) > 0 ? " · " + wifiPane.eth.speed + " Mb/s" : "")
                                  : "Cable unplugged")
                        Row {
                            spacing: 8
                            WGlyph { width: 18; height: 18; kind: "ethernet"; color: pal.text; anchors.verticalCenter: parent.verticalCenter }
                            Corners.ContinuousRectangle { width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter; color: wifiPane.eth && wifiPane.eth.up ? "#30D158" : pal.text3 }
                        }
                    }
                }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Wi-Fi"
                        subtitle: !root.bar ? "" : (!root.bar.wifiOn ? "Off" : (root.bar.wifiSsid !== "" ? "Connected to " + root.bar.wifiSsid : "Not connected"))
                        SSwitch { t: pal; checked: root.bar ? root.bar.wifiOn : false; onToggled: v => { if (root.bar && root.bar.wifiOn !== v) root.bar.toggleWifi(); } }
                    }
                }
                SLabel { t: pal; header: true; text: "Known Networks & Other Networks"; visible: root.bar && root.bar.wifiOn }
                SCard {
                    t: pal
                    visible: root.bar && root.bar.wifiOn
                    Repeater {
                        model: root.bar ? root.bar.wifiNets : []
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.ssid + (modelData.inUse ? "  ✓" : "")
                            subtitle: (modelData.secure ? "Secured" : "Open") + (modelData.saved ? " · Saved" : "") + " · " + modelData.signal + "%"
                            SButton {
                                t: pal
                                text: modelData.inUse ? "Connected" : (modelData.saved || !modelData.secure ? "Connect" : "Join…")
                                onClicked: {
                                    if (modelData.inUse) return;
                                    if (modelData.saved || !modelData.secure) root.bar.connectWifi(modelData.ssid, "");
                                    else { prefsWindow.visible = false; root.bar.wifiJoin ? root.bar.wifiJoin(modelData.ssid) : null; }
                                }
                            }
                        }
                    }
                }
                Row {
                    spacing: 8
                    SButton { t: pal; text: "Scan Again"; onClicked: if (root.bar) root.bar.scanWifi() }
                }
            }
        }

        // ── Bluetooth ── (uses the Menu Bar's Bluetooth backend, so pairing, scanning and errors behave like the Control Center)
        Component {
            id: paneBt
            Column {
                id: btPane
                spacing: 10
                readonly property var bar: root.bar
                readonly property var allDevs: bar ? bar.btDevices : []
                readonly property var myDevs: allDevs.filter(function (d) { return d.paired || d.connected; })
                readonly property var nearby: allDevs.filter(function (d) { return !d.paired && !d.connected; })
                Component.onCompleted: { if (bar) { bar.refreshBt(); bar.scanBt(); } }
                Timer { interval: 4000; repeat: true; running: prefsWindow.visible; onTriggered: if (btPane.bar) btPane.bar.refreshBt() }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Bluetooth"
                        subtitle: root.bar && root.bar.btOn ? "This computer is discoverable as \"" + root.userName + "\"" : "Off"
                        SSwitch { t: pal; checked: root.bar ? root.bar.btOn : false; onToggled: v => { if (root.bar && root.bar.btOn !== v) root.bar.toggleBt(); } }
                    }
                }
                SLabel { t: pal; header: true; text: "My Devices"; visible: btPane.myDevs.length > 0 }
                SCard {
                    t: pal
                    visible: btPane.myDevs.length > 0
                    Repeater {
                        model: btPane.myDevs
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.name
                            subtitle: (root.bar && root.bar.btBusy === modelData.mac ? (modelData.connected ? "Disconnecting\u2026" : "Connecting\u2026")
                                       : (modelData.connected ? "Connected" : "Not Connected")) + (modelData.bat !== "" ? " \u00B7 " + modelData.bat + "%" : "")
                            SButton {
                                t: pal; text: modelData.connected ? "Disconnect" : "Connect"
                                enabled: !(root.bar && root.bar.btBusy !== "")
                                onClicked: { if (root.bar) root.bar.connectBt(modelData.mac, modelData.connected); }
                            }
                        }
                    }
                }
                SLabel { t: pal; header: true; text: (root.bar && root.bar.btScanning) ? "Nearby Devices \u2014 searching\u2026" : "Nearby Devices"; visible: root.bar && root.bar.btOn }
                SCard {
                    t: pal
                    visible: root.bar && root.bar.btOn
                    Repeater {
                        model: btPane.nearby
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.name
                            subtitle: root.bar && root.bar.btBusy === modelData.mac ? "Pairing\u2026" : "Not paired"
                            SButton {
                                t: pal; text: "Connect"
                                enabled: !(root.bar && root.bar.btBusy !== "")
                                onClicked: { if (root.bar) root.bar.connectBt(modelData.mac, false); }
                            }
                        }
                    }
                    SRow {
                        t: pal
                        visible: btPane.nearby.length === 0
                        title: root.bar && root.bar.btScanning ? "Searching for devices\u2026" : "No new devices found"
                        subtitle: "Put the device in pairing mode, then scan again"
                        SButton { t: pal; text: "Scan Again"; enabled: !(root.bar && root.bar.btScanning); onClicked: { if (root.bar) root.bar.scanBt(); } }
                    }
                }
                SLabel { t: pal; text: root.bar ? root.bar.btError : ""; visible: root.bar && root.bar.btError !== "" }
            }
        }

        // ── Network ──
        Component {
            id: paneNetwork
            Column {
                id: netPane
                spacing: 10
                property var devs: []
                Component.onCompleted: netProc.running = true
                Timer { interval: 4000; repeat: true; running: prefsWindow.visible; onTriggered: if (!netProc.running) netProc.running = true }
                Process {
                    id: netProc
                    command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev 2>/dev/null | grep -vE ':(loopback|wifi-p2p|bridge):' | while IFS=: read -r d t s c; do ip=$(ip -4 -o addr show \"$d\" 2>/dev/null | awk '{print $4}' | head -1); printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$d\" \"$t\" \"$s\" \"$c\" \"$ip\"; done"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            var out = [], l = text.split("\n");
                            for (var i = 0; i < l.length; i++) { var f = l[i].split("\t"); if (f.length >= 3 && f[0] !== "") out.push({ dev: f[0], type: f[1], state: f[2], con: f[3] || "", ip: f[4] || "" }); }
                            netPane.devs = out;
                        }
                    }
                }
                SCard {
                    t: pal
                    Repeater {
                        model: netPane.devs
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            readonly property bool up: modelData.state.indexOf("connected") === 0
                            title: ({ ethernet: "Ethernet", wifi: "Wi-Fi", tun: modelData.dev === "tailscale0" ? "Tailscale" : "VPN" })[modelData.type] || modelData.dev
                            subtitle: (up ? "Connected" : "Not Connected") + (modelData.con !== "" ? " · " + modelData.con : "") + (modelData.ip !== "" ? " · " + modelData.ip : "")
                            Corners.ContinuousRectangle { width: 10; height: 10; radius: 5; color: parent.up ? "#30D158" : pal.text3 }
                        }
                    }
                }
            }
        }

        // ── Battery ──
        Component {
            id: paneBattery
            Column {
                id: batPane
                spacing: 10
                readonly property var dev: UPower.displayDevice
                readonly property real pct: dev ? Math.round(dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage) : 0
                readonly property bool charging: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
                property string profile: ""
                Component.onCompleted: ppGet.running = true
                Process { id: ppGet; command: ["powerprofilesctl", "get"]; stdout: StdioCollector { onStreamFinished: batPane.profile = text.trim() } }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Battery Level"
                        subtitle: batPane.charging ? "Charging" : (batPane.dev && batPane.dev.timeToEmpty > 0 ? Math.floor(batPane.dev.timeToEmpty / 3600) + " h " + Math.round(batPane.dev.timeToEmpty % 3600 / 60) + " min remaining" : "On battery")
                        Row {
                            spacing: 8
                            Corners.ContinuousRectangle {
                                width: 120; height: 10; radius: 5; color: pal.track; anchors.verticalCenter: parent.verticalCenter
                                Corners.ContinuousRectangle { width: parent.width * batPane.pct / 100; height: parent.height; radius: 5; color: batPane.pct <= 20 && !batPane.charging ? "#FF453A" : "#30D158" }
                            }
                            Text { text: batPane.pct + "%"; color: pal.text; font.family: pal.fam; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    SRow {
                        t: pal; title: "Energy Mode"
                        subtitle: "Power profile used by the system"
                        SSegmented {
                            t: pal; model: ["Low Power", "Automatic", "High Power"]; segWidth: 84
                            current: ["power-saver", "balanced", "performance"].indexOf(batPane.profile)
                            onPicked: i => { var p = ["power-saver", "balanced", "performance"][i]; Quickshell.execDetached(["powerprofilesctl", "set", p]); batPane.profile = p; }
                        }
                    }
                }
                SLabel { t: pal; header: true; text: "Game Mode" }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Game Mode"
                        subtitle: "Turns off blur, shadows, animations and Liquid Glass, pauses an animated wallpaper and uses High Power"
                        SSwitch { t: pal; checked: root.bar ? root.bar.gamingMode : false; onToggled: v => { if (root.bar) root.bar.gamingMode = v; } }
                    }
                    SRow {
                        t: pal; title: "Turn on automatically for fullscreen games"
                        SSwitch { t: pal; checked: root.bar ? root.bar.gamingAuto : true; onToggled: v => { if (root.bar) root.bar.gamingAuto = v; } }
                    }
                }
            }
        }

        // ── Control Center ──
        Component {
            id: paneCC
            Column {
                spacing: 10
                SLabel { t: pal; text: "Choose which controls appear in Control Center. Open the gallery to search, resize, or pin controls to the menu bar." }
                SButton {
                    t: pal; text: "Edit Controls…"
                    onClicked: { if (root.bar) root.bar.ccGalleryRequest(); }
                }
                SCard {
                    t: pal
                    Repeater {
                        model: root.bar ? root.bar.ccCatalog : []
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.label
                            SSwitch {
                                t: pal
                                checked: root.bar ? root.bar.ccControls.indexOf(modelData.id) >= 0 : false
                                onToggled: v => {
                                    if (!root.bar) return;
                                    var cl = root.bar.ccControls.filter(function (x) { return x !== modelData.id; });
                                    if (v) cl.push(modelData.id);
                                    root.bar.ccControls = cl;
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Desktop & Dock = Dock + Dock Behavior ──
        Component {
            id: paneDesktopDock
            Column {
                spacing: 18
                Loader { width: parent.width; sourceComponent: paneDock }
                SCard {
                    t: pal
                    SRow { t: pal; title: "Dock position on screen"
                        SPopUp { t: pal; model: ["Left", "Bottom", "Right"]; current: ["left", "bottom", "right"].indexOf(root.position)
                            onPicked: i => Corners.DesktopPreferences.setValue("position", ["left", "bottom", "right"][i]) }
                    }
                    SRow { t: pal; title: "Minimize windows using"
                        SPopUp { t: pal; model: ["Genie Effect", "Scale Effect"]; current: root.desktopPrefs.minimizeEffect === "scale" ? 1 : 0
                            onPicked: i => Corners.DesktopPreferences.setValue("minimizeEffect", i === 0 ? "genie" : "scale") }
                    }
                    SRow { t: pal; title: "Window title bar double-click action"
                        SPopUp { t: pal; model: ["Fill", "Zoom", "Minimize", "No Action"]; current: ["fill", "zoom", "minimize", "none"].indexOf(root.desktopPrefs.titlebarAction)
                            onPicked: i => Corners.DesktopPreferences.setValue("titlebarAction", ["fill", "zoom", "minimize", "none"][i]) }
                    }
                    SRow { t: pal; title: "Minimize windows into application icon"
                        SSwitch { t: pal; checked: root.desktopPrefs.minimizeIntoApp; onToggled: v => Corners.DesktopPreferences.setValue("minimizeIntoApp", v) }
                    }
                    SRow { t: pal; title: "Show recent apps in Dock"; subtitle: "Up to three recently opened apps"
                        SSwitch { t: pal; checked: root.desktopPrefs.showRecentApps; onToggled: v => Corners.DesktopPreferences.setValue("showRecentApps", v) }
                    }
                }
                Loader { width: parent.width; sourceComponent: paneBehavior }
                SLabel { t: pal; header: true; text: "Desktop & Stage Manager" }
                SCard {
                    t: pal
                    SRow { t: pal; title: "Show items on desktop"
                        SSwitch { t: pal; checked: root.desktopPrefs.desktopItems; onToggled: v => Corners.DesktopPreferences.setValue("desktopItems", v) }
                    }
                    SRow { t: pal; title: "Show items in Stage Manager"
                        SSwitch { t: pal; checked: root.desktopPrefs.stageItems; onToggled: v => Corners.DesktopPreferences.setValue("stageItems", v) }
                    }
                    SRow { t: pal; title: "Click wallpaper to show desktop"
                        SPopUp { t: pal; model: ["Always", "Only in Stage Manager"]; current: root.desktopPrefs.wallpaperClick === "always" ? 0 : 1
                            onPicked: i => Corners.DesktopPreferences.setValue("wallpaperClick", i === 0 ? "always" : "stage") }
                    }
                    SRow { t: pal; title: "Stage Manager"; subtitle: "Keep the current group in view and other apps at the side"
                        SSwitch { t: pal; checked: root.desktopPrefs.stageManager; onToggled: v => Corners.DesktopPreferences.setValue("stageManager", v) }
                    }
                    SRow { t: pal; title: "Show recent apps in Stage Manager"; visible: root.desktopPrefs.stageManager
                        SSwitch { t: pal; checked: root.desktopPrefs.stageRecent; onToggled: v => Corners.DesktopPreferences.setValue("stageRecent", v) }
                    }
                    SRow { t: pal; title: "Show windows from an application"; visible: root.desktopPrefs.stageManager
                        SPopUp { t: pal; model: ["All at Once", "One at a Time"]; current: root.desktopPrefs.stageWindows === "one" ? 1 : 0
                            onPicked: i => Corners.DesktopPreferences.setValue("stageWindows", i === 0 ? "all" : "one") }
                    }
                    SRow { t: pal; title: "Show widgets on desktop"
                        SSwitch { t: pal; checked: root.desktopPrefs.desktopWidgets; onToggled: v => Corners.DesktopPreferences.setValue("desktopWidgets", v) }
                    }
                    SRow { t: pal; title: "Show widgets in Stage Manager"
                        SSwitch { t: pal; checked: root.desktopPrefs.stageWidgets; onToggled: v => Corners.DesktopPreferences.setValue("stageWidgets", v) }
                    }
                }
                SLabel { t: pal; header: true; text: "App Switcher (Alt + Tab)" }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Display mode"
                        subtitle: "App icons groups windows by app. Live window previews shows each window separately."
                        SPopUp {
                            t: pal; model: ["App Icons", "Live Window Previews"]
                            current: root.bar && root.bar.switcherMode === "windows" ? 1 : 0
                            onPicked: i => { if (root.bar) root.bar.switcherMode = i === 1 ? "windows" : "icons"; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Style"
                        subtitle: "Liquid Glass refracts what's behind it, Frosted blurs it, Opaque is a solid panel"
                        SSegmented {
                            t: pal
                            model: ["Liquid Glass", "Frosted", "Opaque"]
                            segWidth: 92
                            current: Math.max(0, ["glass", "frosted", "opaque"].indexOf(root.bar ? root.bar.switcherStyle : "glass"))
                            onPicked: i => { if (root.bar) root.bar.switcherStyle = ["glass", "frosted", "opaque"][i]; }
                        }
                    }
                }
            }
        }

        // ── Displays ──
        Component {
            id: paneDisplays
            Column {
                id: dispPane
                spacing: 10
                property var mons: []
                Component.onCompleted: { monList.running = true; root.refreshMons(); }
                Process {
                    id: monList
                    command: ["hyprctl", "-j", "monitors"]
                    stdout: StdioCollector { onStreamFinished: { try { dispPane.mons = JSON.parse(text); } catch (e) {} } }
                }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Brightness"
                        SSlider { t: pal; value: root.bar ? root.bar.brightness : 0.5; onMoved: v => { if (root.bar) root.bar.setBrightness(v); } }
                    }
                    SRow {
                        t: pal; title: "Night Shift"
                        subtitle: "Warmer colours to reduce blue light"
                        SSwitch { t: pal; checked: root.bar ? root.bar.nightOn : false; onToggled: v => { if (root.bar) root.bar.nightOn = v; } }
                    }
                    SRow {
                        t: pal; title: "Colour Temperature"; visible: root.bar && root.bar.nightOn
                        SSlider {
                            t: pal; leftLabel: "Less Warm"; rightLabel: "More Warm"
                            value: root.bar ? 1 - (root.bar.nightTemp - 2500) / 3500 : 0.5
                            onMoved: v => { if (root.bar) root.bar.nightTemp = Math.round(2500 + (1 - v) * 3500); }
                        }
                    }
                }
                SLabel { t: pal; header: true; text: "Displays" }
                // keep / revert sheet (macOS: "Keep these display settings?")
                Corners.ContinuousRectangle {
                    visible: root.pendingOut !== ""
                    width: parent.width; height: 64; radius: 10
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
                    border.width: 1; border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
                    Text {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 220; wrapMode: Text.WordWrap
                        text: "Keep these display settings? Reverting in " + root.revertLeft + " s."
                        color: pal.text; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        SButton { t: pal; text: "Revert"; onClicked: root.revertMode() }
                        SButton { t: pal; text: "Keep Changes"; onClicked: root.keepMode() }
                    }
                }
                SCard {
                    t: pal
                    visible: root.monList.length > 1
                    SRow {
                        t: pal; title: "Main display"
                        subtitle: "The Dock, the lock screen controls and new widgets go here"
                        SSegmented {
                            t: pal
                            model: root.monList.map(function (m) { return m.name; })
                            segWidth: 96
                            current: { var p = root.monitorPrimary || root.monitor; for (var i = 0; i < root.monList.length; i++) if (root.monList[i].name === p) return i; return -1; }
                            onPicked: i => root.setPrimary(root.monList[i].name)
                        }
                    }
                }
                Repeater {
                    model: root.monList
                    delegate: SCard {
                        id: monCard
                        required property var modelData
                        t: pal
                        // available modes → resolutions (largest first) and the refresh rates of the chosen one
                        readonly property var modes: {
                            var seen = {}, out = [];
                            var am = modelData.availableModes || [];
                            for (var i = 0; i < am.length; i++) {
                                var m = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(am[i]); if (!m) continue;
                                var k = m[1] + "x" + m[2] + "@" + parseFloat(m[3]).toFixed(2);
                                if (seen[k]) continue; seen[k] = true;
                                out.push({ w: parseInt(m[1]), h: parseInt(m[2]), hz: parseFloat(m[3]) });
                            }
                            return out;
                        }
                        readonly property var resolutions: {
                            var seen = {}, out = [];
                            for (var i = 0; i < modes.length; i++) { var r = modes[i].w + "x" + modes[i].h; if (!seen[r]) { seen[r] = true; out.push(modes[i]); } }
                            out.sort(function (a, b) { return b.w * b.h - a.w * a.h; });
                            var cur = modelData.width + "x" + modelData.height;
                            if (!seen[cur]) out.unshift({ w: modelData.width, h: modelData.height, hz: modelData.refreshRate, custom: true });
                            return out;
                        }
                        property string selRes: modelData.width + "x" + modelData.height
                        readonly property var rates: {
                            var out = [];
                            for (var i = 0; i < modes.length; i++) if (modes[i].w + "x" + modes[i].h === selRes && out.indexOf(Math.round(modes[i].hz)) < 0) out.push(Math.round(modes[i].hz));
                            out.sort(function (a, b) { return b - a; });
                            if (out.length === 0) out.push(Math.round(modelData.refreshRate));
                            return out;
                        }
                        function bestHz(res, hz) {
                            var best = null;
                            for (var i = 0; i < modes.length; i++) if (modes[i].w + "x" + modes[i].h === res && (best === null || Math.abs(modes[i].hz - hz) < Math.abs(best - hz))) best = modes[i].hz;
                            return best === null ? hz : best;
                        }
                        SRow {
                            t: pal
                            title: (modelData.description || modelData.name).replace(/\s*\(.*\)$/, "")
                            subtitle: modelData.name + " · " + modelData.width + " × " + modelData.height + " @ " + Math.round(modelData.refreshRate) + " Hz · Scale " + modelData.scale
                        }
                        SRow {
                            t: pal; title: "Resolution"
                            SPopUp {
                                t: pal
                                model: monCard.resolutions.map(function (r) { return r.w + " × " + r.h + (r.custom ? "  (current)" : ""); })
                                current: { for (var i = 0; i < monCard.resolutions.length; i++) if (monCard.resolutions[i].w + "x" + monCard.resolutions[i].h === monCard.selRes) return i; return 0; }
                                onPicked: i => {
                                    var r = monCard.resolutions[i];
                                    if (r.custom) return;
                                    monCard.selRes = r.w + "x" + r.h;
                                    var hz = monCard.bestHz(monCard.selRes, monCard.modelData.refreshRate);
                                    root.tryMode(monCard.modelData.name, monCard.selRes + "@" + hz.toFixed(2));
                                }
                            }
                        }
                        SRow {
                            t: pal; title: "Refresh rate"
                            SPopUp {
                                t: pal
                                model: monCard.rates.map(function (h) { return h + " Hz"; })
                                current: { var c = Math.round(monCard.modelData.refreshRate), i = monCard.rates.indexOf(c); return i < 0 ? 0 : i; }
                                onPicked: i => {
                                    var hz = monCard.bestHz(monCard.selRes, monCard.rates[i]);
                                    root.tryMode(monCard.modelData.name, monCard.selRes + "@" + hz.toFixed(2));
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Notifications ──
        Component {
            id: paneNotif
            Column {
                spacing: 10
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Show notification banners"
                        subtitle: "Off = Do Not Disturb: notifications still go to Notification Center, without banners"
                        SSwitch { t: pal; checked: root.bar ? !root.bar.notifDnd : true; onToggled: v => { if (root.bar) root.bar.notifDnd = !v; } }
                    }
                    SRow {
                        t: pal; title: "Play sound for notifications"
                        SSwitch { t: pal; checked: root.bar ? root.bar.uiSounds : true; onToggled: v => { if (root.bar) root.bar.uiSounds = v; } }
                    }
                    SRow {
                        t: pal; title: "Screenshot notifications"
                        SSwitch { t: pal; checked: root.bar ? root.bar.screenshotNotify : true; onToggled: v => { if (root.bar) root.bar.screenshotNotify = v; } }
                    }
                }
                Row {
                    spacing: 8
                    SButton { t: pal; text: "Send Test Notification"; onClicked: Quickshell.execDetached(["notify-send", "-a", "Settings", "Test notification", "Notifications are working"]) }
                    SButton { t: pal; text: "Clear Notification Center"; onClicked: if (root.bar) root.bar.notifClearAnimated() }
                }
            }
        }

        // ── Sound ──
        Component {
            id: paneSound
            Column {
                id: sndPane
                spacing: 10
                readonly property var outs: Pipewire.nodes.values.filter(function (n) { return n.isSink && !n.isStream && n.audio; })
                readonly property var ins: Pipewire.nodes.values.filter(function (n) { return !n.isSink && !n.isStream && n.audio && (n.name || "").indexOf("monitor") < 0; })
                readonly property var src: Pipewire.defaultAudioSource
                PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Play user interface sound effects"
                        SSwitch { t: pal; checked: root.bar ? root.bar.uiSounds : true; onToggled: v => { if (root.bar) root.bar.uiSounds = v; } }
                    }
                }
                SLabel { t: pal; header: true; text: "Output" }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Output volume"
                        SSlider { t: pal; value: root.bar ? (root.bar.muted ? 0 : root.bar.volume) : 0; onMoved: v => { if (root.bar) root.bar.setVolume(v); } }
                    }
                    SRow {
                        t: pal; title: "Mute"
                        SSwitch { t: pal; checked: root.bar ? root.bar.muted : false; onToggled: v => { if (root.bar && root.bar.muted !== v) root.bar.toggleMute(); } }
                    }
                    Repeater {
                        model: sndPane.outs
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.description || modelData.nickname || modelData.name
                            id: devRowSink
                            readonly property bool cur: Pipewire.defaultAudioSink === modelData
                            subtitle: cur ? "Selected" : ""
                            SButton { t: pal; text: devRowSink.cur ? "In Use" : "Use"; onClicked: Pipewire.preferredDefaultAudioSink = devRowSink.modelData }
                        }
                    }
                }
                SLabel { t: pal; header: true; text: "Input" }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Input volume"
                        SSlider { t: pal; value: sndPane.src && sndPane.src.audio ? sndPane.src.audio.volume : 0; onMoved: v => { if (sndPane.src && sndPane.src.audio) sndPane.src.audio.volume = v; } }
                    }
                    Repeater {
                        model: sndPane.ins
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.description || modelData.nickname || modelData.name
                            id: devRowSource
                            readonly property bool cur: Pipewire.defaultAudioSource === modelData
                            subtitle: cur ? "Selected" : ""
                            SButton { t: pal; text: devRowSource.cur ? "In Use" : "Use"; onClicked: Pipewire.preferredDefaultAudioSource = devRowSource.modelData }
                        }
                    }
                }
            }
        }

        // ── Focus ──
        Component {
            id: paneFocus
            Column {
                spacing: 10
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Do Not Disturb"
                        subtitle: "Silences notification banners"
                        SSwitch { t: pal; checked: root.bar ? root.bar.notifDnd : false; onToggled: v => { if (root.bar) root.bar.notifDnd = v; } }
                    }
                    SRow {
                        t: pal; title: "Keep Awake"
                        subtitle: "Stop the computer from going to sleep or locking"
                        SSwitch { t: pal; checked: root.bar ? root.bar.keepAwake : false; onToggled: v => { if (root.bar) root.bar.keepAwake = v; } }
                    }
                }
            }
        }

        // ── Lock Screen ──
        Component {
            id: paneLock
            Column {
                id: lockPane
                spacing: 10
                property string slot: "top"
                Component.onCompleted: slotGet.running = true
                Process { id: slotGet; command: ["sh", "-c", "jq -r '.mediaSlot // \"top\"' \"$HOME/.config/maclock/settings.json\" 2>/dev/null || echo top"]
                          stdout: StdioCollector { onStreamFinished: lockPane.slot = text.trim() === "bottom" ? "bottom" : "top" } }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Now Playing position"
                        subtitle: "You can also drag it on the lock screen"
                        SSegmented {
                            t: pal; model: ["Under Clock", "Above Password"]; segWidth: 110
                            current: lockPane.slot === "bottom" ? 1 : 0
                            onPicked: i => {
                                lockPane.slot = i === 1 ? "bottom" : "top";
                                Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/.config/maclock\" && printf '{\\n  \"mediaSlot\": \"%s\"\\n}\\n' \"$1\" > \"$HOME/.config/maclock/settings.json\"", "sh", lockPane.slot]);
                            }
                        }
                    }
                    SRow {
                        t: pal; title: "Album background when the cover is enlarged"
                        SSwitch { t: pal; checked: root.bar ? root.bar.lockArtBackground : true; onToggled: v => { if (root.bar) root.bar.lockArtBackground = v; } }
                    }
                    SRow {
                        t: pal; title: "24-hour clock"
                        subtitle: "Shared with the menu bar clock"
                        SSwitch { t: pal; checked: root.bar ? root.bar.use24h : true; onToggled: v => { if (root.bar) root.bar.use24h = v; } }
                    }
                }
                // ── Clock ──
                // Clock presets use SF Pro Display with their existing weights and materials.
                SLabel { t: pal; text: "Clock"; font.weight: Font.DemiBold; topPadding: 6 }
                SCard {
                    t: pal
                    // preset tiles
                    Item {
                        width: parent.width; height: 132
                        Row {
                            anchors.centerIn: parent
                            spacing: 10
                            Repeater {
                                model: [
                                    { id: "glass",   name: "Glass",   fam: "SF Pro Display",        w: 680, tall: true,  liquid: false },
                                    { id: "classic", name: "Classic", fam: "SF Pro Display",             w: 640, tall: false, liquid: false },
                                    { id: "serif",   name: "Display",   fam: "SF Pro Display", w: 560, tall: false, liquid: false },
                                    { id: "liquid",  name: "Liquid",  fam: "SF Pro Display",        w: 560, tall: true,  liquid: true },
                                    { id: "thin",    name: "Thin",    fam: "SF Pro Display",             w: 220, tall: false, liquid: true }
                                ]
                                delegate: Column {
                                    id: tile
                                    required property var modelData
                                    readonly property bool sel: root.bar && root.bar.lockClockStyle === modelData.id
                                    spacing: 6
                                    Corners.ContinuousRectangle { cornerSmoothing: 0;
                                        width: 92; height: 92; radius: 14
                                        gradient: Gradient {
                                            GradientStop { position: 0; color: "#8C7A6B" }
                                            GradientStop { position: 1; color: "#3E3530" }
                                        }
                                        border.width: tile.sel ? 3 : 0; border.color: pal.accent
                                        Behavior on border.width { NumberAnimation { duration: 160 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "9:41"
                                            font.family: tile.modelData.fam; font.pixelSize: tile.modelData.tall ? 40 : 30
                                            font.weight: Math.max(100, Math.min(900, tile.modelData.w))
                                            color: tile.modelData.liquid ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.78)
                                            style: tile.modelData.liquid ? Text.Outline : Text.Normal
                                            styleColor: Qt.rgba(1, 1, 1, 0.85)
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.bar) root.bar.applyLockClockPreset(tile.modelData.id) }
                                    }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.name; color: tile.sel ? pal.accent : pal.text; font.family: pal.fam; font.pixelSize: 12; font.weight: tile.sel ? Font.DemiBold : Font.Normal }
                                }
                            }
                        }
                    }
                    SRow {
                        t: pal; title: "Font"
                        SPopUp {
                            t: pal
                            model: ["SF Pro Display", "SF Pro Text"]
                            readonly property var ids: ["condensed", "inter"]
                            current: Math.max(0, ids.indexOf(root.bar ? root.bar.lockClockFont : "condensed"))
                            onPicked: i => { if (root.bar) { root.bar.lockClockFont = ids[i]; root.bar.lockClockStyle = "custom"; } }
                        }
                    }
                    SRow {
                        t: pal; title: "Weight"
                        SSlider {
                            t: pal; width: 220; from: 100; to: 1000; stepSize: 10
                            leftLabel: "Thin"; rightLabel: "Heavy"
                            value: root.bar ? root.bar.lockClockWeight : 680
                            onMoved: v => { if (root.bar) { root.bar.lockClockWeight = Math.round(v); root.bar.lockClockStyle = "custom"; } }
                        }
                    }
                    SRow {
                        t: pal; title: "Style"
                        subtitle: "Solid glows with a hint of the wallpaper; Glass is Liquid Glass that catches the light"
                        SSegmented {
                            t: pal; model: ["Solid", "Glass"]; segWidth: 80
                            current: root.bar && root.bar.lockClockMaterial === "solid" ? 0 : 1
                            onPicked: i => { if (root.bar) { root.bar.lockClockMaterial = i === 0 ? "solid" : "glass"; root.bar.lockClockStyle = "custom"; } }
                        }
                    }
                    SRow {
                        t: pal; title: root.bar && root.bar.lockClockMaterial === "solid" ? "Brightness" : "Glass"
                        SSlider {
                            t: pal; width: 220; from: 0; to: 1
                            leftLabel: root.bar && root.bar.lockClockMaterial === "solid" ? "Subtle" : "Clear"
                            rightLabel: root.bar && root.bar.lockClockMaterial === "solid" ? "Bright" : "Frosted"
                            value: root.bar ? root.bar.lockClockIntensity : 0.6
                            onMoved: v => { if (root.bar) { root.bar.lockClockIntensity = v; root.bar.lockClockStyle = "custom"; } }
                        }
                    }
                    SRow {
                        t: pal; title: "Color"
                        Row {
                            spacing: 8
                            Repeater {
                                model: ["#FFFFFF", "#FFE7C2", "#FFC2D6", "#D9C8FF", "#BFE3FF", "#C6F2D6", "#FFF3A8"]
                                delegate: Corners.ContinuousRectangle { cornerSmoothing: 0;
                                    required property string modelData
                                    readonly property bool sel: root.bar && root.bar.lockClockTint.toUpperCase() === modelData
                                    width: 22; height: 22; radius: 11
                                    color: modelData
                                    border.width: sel ? 2.5 : 1
                                    border.color: sel ? pal.accent : Qt.rgba(0, 0, 0, 0.2)
                                    scale: swMa.pressed ? 0.88 : 1
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                                    MouseArea { id: swMa; anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: if (root.bar) root.bar.lockClockTint = parent.modelData }
                                }
                            }
                        }
                    }
                    SRow {
                        t: pal; title: "Tall digits"
                        subtitle: "Stretches the Condensed font to fill the space, like iOS 26"
                        SSwitch {
                            t: pal
                            enabled: root.bar && root.bar.lockClockFont === "condensed"
                            checked: root.bar ? root.bar.lockClockTall : true
                            onToggled: v => { if (root.bar) { root.bar.lockClockTall = v; root.bar.lockClockStyle = "custom"; } }
                        }
                    }
                    SRow {
                        t: pal; title: "Date"
                        SSegmented {
                            t: pal; model: ["Friday, October 16", "Fri Oct 16"]; segWidth: 130
                            current: root.bar && root.bar.lockClockDate === "short" ? 1 : 0
                            onPicked: i => { if (root.bar) { root.bar.lockClockDate = i === 1 ? "short" : "long"; root.bar.lockClockStyle = "custom"; } }
                        }
                    }
                }
                Row {
                    spacing: 8
                    // a 6-second look at the lock screen (no real lock) with the settings above
                    SButton {
                        t: pal; text: "Preview"
                        onClicked: {
                            var b = root.bar;
                            var cfg = JSON.stringify({ f: b.lockClockFont, w: b.lockClockWeight, m: b.lockClockMaterial, i: b.lockClockIntensity, c: b.lockClockTint, t: b.lockClockTall, d: b.lockClockDate });
                            Quickshell.execDetached(["sh", "-c", "MACLOCK_PREVIEW=1 MACLOCK_CLOCK=\"$1\" timeout 6 qs -c MacLock >/dev/null 2>&1", "sh", cfg]);
                        }
                    }
                    SButton { t: pal; text: "Lock Screen Now"; onClicked: { prefsWindow.visible = false; Quickshell.execDetached(["sh", "-c", "pgrep -f -- \"-c [M]acLock\" >/dev/null 2>&1 || qs -c MacLock"]); } }
                }
            }
        }

        // ── Users & Groups ──
        Component {
            id: paneUsers
            Column {
                spacing: 14
                Item {
                    width: parent.width; height: 120
                    Item {
                        id: upic
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 84; height: 84
                        property int ver: 0
                        Item { id: upMask; anchors.fill: parent; visible: false; layer.enabled: true; Corners.ContinuousRectangle { anchors.fill: parent; radius: width / 2; color: "black" } }
                        Corners.ContinuousRectangle { anchors.fill: parent; radius: width / 2; color: pal.ctrl }
                        Image {
                            anchors.fill: parent; cache: false; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(200, 200)
                            source: "file://" + Quickshell.env("HOME") + "/.face?" + upic.ver
                            layer.enabled: true; layer.effect: MultiEffect { maskEnabled: true; maskSource: upMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                        }
                    }
                    Text { anchors.top: upic.bottom; anchors.topMargin: 8; anchors.horizontalCenter: parent.horizontalCenter; text: root.userName; color: pal.text; font.family: pal.fam; font.pixelSize: 17; font.weight: Font.DemiBold }
                }
                SCard {
                    t: pal
                    SRow { t: pal; title: "Full name"; Text { text: root.userName; color: pal.text2; font.family: pal.fam; font.pixelSize: 13 } }
                    SRow { t: pal; title: "Account name"; Text { text: Quickshell.env("USER"); color: pal.text2; font.family: pal.fam; font.pixelSize: 13 } }
                    SRow { t: pal; title: "Home folder"; Text { text: Quickshell.env("HOME"); color: pal.text2; font.family: pal.fam; font.pixelSize: 13 } }
                    SRow {
                        t: pal; title: "Picture"
                        subtitle: "Used on the lock screen and here"
                        SButton {
                            t: pal; text: "Change…"
                            onClicked: picProc.running = true
                        }
                    }
                }
                Process {
                    id: picProc
                    command: ["sh", "-c", "f=$(zenity --file-selection --title='Choose a picture' --file-filter='Images | *.png *.jpg *.jpeg *.webp' 2>/dev/null || kdialog --getopenfilename \"$HOME/Pictures\" 'image/png image/jpeg image/webp' 2>/dev/null); [ -n \"$f\" ] && magick \"$f\" -resize 512x512^ -gravity center -extent 512x512 \"$HOME/.face\" && echo ok"]
                    stdout: StdioCollector { onStreamFinished: if (text.indexOf("ok") >= 0) upic.ver++ }
                }
            }
        }

        // ── Keyboard ──
        Component {
            id: paneKeyboard
            Column {
                spacing: 10
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Key repeat rate"
                        SSlider { t: pal; leftLabel: "Slow"; rightLabel: "Fast"; from: 10; to: 80; value: root.bar ? root.bar.kbRepeatRate : 35; onMoved: v => { if (root.bar) root.bar.kbRepeatRate = Math.round(v); } }
                    }
                    SRow {
                        t: pal; title: "Delay until repeat"
                        SSlider { t: pal; leftLabel: "Long"; rightLabel: "Short"; from: 0; to: 1; value: root.bar ? 1 - (root.bar.kbRepeatDelay - 150) / 650 : 0.6; onMoved: v => { if (root.bar) root.bar.kbRepeatDelay = Math.round(150 + (1 - v) * 650); } }
                    }
                }
                SLabel { t: pal; text: "Layout: " + "us" + ". Changes apply right away." }
            }
        }

        // ── Mouse ──
        Component {
            id: paneMouse
            Column {
                spacing: 10
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Tracking speed"
                        SSlider { t: pal; leftLabel: "Slow"; rightLabel: "Fast"; from: -1; to: 1; value: root.bar ? root.bar.mouseSens : 0; onMoved: v => { if (root.bar) root.bar.mouseSens = v; } }
                    }
                    SRow {
                        t: pal; title: "Natural scrolling"
                        subtitle: "Content tracks finger movement"
                        SSwitch { t: pal; checked: root.bar ? root.bar.mouseNatural : false; onToggled: v => { if (root.bar) root.bar.mouseNatural = v; } }
                    }
                }
            }
        }

        // ── Trackpad ──
        Component {
            id: paneTrackpad
            Column {
                spacing: 10
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Tap to click"
                        SSwitch { t: pal; checked: root.bar ? root.bar.tpTap : true; onToggled: v => { if (root.bar) root.bar.tpTap = v; } }
                    }
                    SRow {
                        t: pal; title: "Natural scrolling"
                        SSwitch { t: pal; checked: root.bar ? root.bar.tpNatural : true; onToggled: v => { if (root.bar) root.bar.tpNatural = v; } }
                    }
                    SRow {
                        t: pal; title: "Ignore trackpad while typing"
                        SSwitch { t: pal; checked: root.bar ? root.bar.tpDwt : true; onToggled: v => { if (root.bar) root.bar.tpDwt = v; } }
                    }
                    SRow {
                        t: pal; title: "Scrolling speed"
                        SSlider { t: pal; leftLabel: "Slow"; rightLabel: "Fast"; from: 0.2; to: 2; value: root.bar ? root.bar.tpScroll : 0.7; onMoved: v => { if (root.bar) root.bar.tpScroll = v; } }
                    }
                }
            }
        }

        // ── Wallpaper ──
        Component {
            id: paneWallpaper
            Column {
                id: wpPane
                spacing: 10
                property int filter: 0          // 0 all, 1 pictures, 2 animated, 3 favourites
                property string searchText: ""
                readonly property var files: root.bar ? root.bar.wpFiles : []
                readonly property var shown: {
                    var out = [], f = files, q = searchText.trim().toLowerCase();
                    for (var i = 0; i < f.length; i++) {
                        var typeMatch = filter === 0 || (filter === 1 && !f[i].video) || (filter === 2 && f[i].video) || (filter === 3 && f[i].fav);
                        var textMatch = q === "" || f[i].name.toLowerCase().indexOf(q) >= 0;
                        if (typeMatch && textMatch) out.push(f[i]);
                    }
                    return out;
                }
                readonly property string curVideo: root.bar ? root.bar.wallpaperVideo : ""
                readonly property string curStill: root.bar ? root.bar.wallpaperPath : root.wallpaperPath
                readonly property string curPath: curVideo !== "" ? curVideo : curStill
                readonly property string curPreview: (root.bar && curVideo !== "") ? (root.bar.wpPreviews[curVideo] || "") : ""
                function nameOf(p) { var n = p.substring(p.lastIndexOf("/") + 1); var k = n.lastIndexOf("."); return k > 0 ? n.substring(0, k) : n; }
                Component.onCompleted: if (root.bar) root.bar.wpRefresh()

                // current wallpaper, big, playing if it's animated
                SCard {
                    t: pal
                    Item {
                        width: parent.width
                        height: 190
                        Item {
                            id: curBox
                            x: 14; y: 14
                            width: 256; height: 160
                            Item {
                                id: curMask
                                anchors.fill: parent; visible: false
                                layer.enabled: true; layer.smooth: true
                                Corners.ContinuousRectangle { anchors.fill: parent; radius: 10; color: "black" }
                            }
                            Item {
                                anchors.fill: parent
                                layer.enabled: true; layer.smooth: true
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: curMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                                Corners.ContinuousRectangle { anchors.fill: parent; color: pal.ctrl }
                                Image {
                                    anchors.fill: parent
                                    source: wpPane.curStill !== "" ? "file://" + wpPane.curStill : ""
                                    sourceSize.width: 520
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true; smooth: true
                                }
                                Loader {
                                    anchors.fill: parent
                                    active: wpPane.curVideo !== "" && prefsWindow.visible && wpPane.curPreview !== ""
                                    sourceComponent: AnimatedImage {
                                        source: "file://" + wpPane.curPreview
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true; cache: false; playing: true
                                    }
                                }
                            }
                            Corners.ContinuousRectangle { anchors.fill: parent; radius: 10; color: "transparent"; border.width: 1; border.color: pal.cardBorder }
                        }
                        Column {
                            x: curBox.x + curBox.width + 18
                            anchors.verticalCenter: curBox.verticalCenter
                            width: parent.width - x - 14
                            spacing: 6
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: wpPane.curPath !== "" ? wpPane.nameOf(wpPane.curPath) : "No wallpaper"
                                color: pal.text; font.family: pal.fam; font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width
                                text: wpPane.curVideo !== "" ? "Animated wallpaper" : "Picture"
                                color: pal.text2; font.family: pal.fam; font.pixelSize: 12
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                visible: wpPane.curVideo !== ""
                                text: "Plays on every display and pauses behind fullscreen windows. The Liquid Glass and the lock screen use it too."
                                color: pal.text3; font.family: pal.fam; font.pixelSize: 11
                            }
                            Row {
                                spacing: 8
                                topPadding: 4
                                SButton { t: pal; text: "Open Folder"; onClicked: Quickshell.execDetached(["xdg-open", root.bar ? root.bar.wpDirEff : ""]) }
                                SButton { t: pal; text: "Refresh"; onClicked: if (root.bar) root.bar.wpRefresh() }
                            }
                        }
                    }
                }

                // macOS: a wallpaper that comes in light and dark versions gets an appearance picker
                SCard {
                    t: pal
                    visible: root.bar && root.bar.wpHasPair
                    SRow {
                        t: pal
                        title: "Appearance"
                        subtitle: {
                            var a = root.bar ? root.bar.wallpaperAppearance : "auto";
                            return a === "auto" ? "Follows Light / Dark Mode"
                                 : a === "dynamic" ? "Changes through the day: light by day, dark at night, blending at sunrise and sunset"
                                 : a === "light" ? "Always the light version" : "Always the dark version";
                        }
                        SSegmented {
                            t: pal
                            model: ["Automatic", "Light", "Dark", "Dynamic"]
                            segWidth: 78
                            current: ["auto", "light", "dark", "dynamic"].indexOf(root.bar ? root.bar.wallpaperAppearance : "auto")
                            onPicked: i => { if (root.bar) root.bar.wallpaperAppearance = ["auto", "light", "dark", "dynamic"][i]; }
                        }
                    }
                }

                Item {
                    width: parent.width; height: 30
                    SLabel { t: pal; header: true; width: 200; anchors.verticalCenter: parent.verticalCenter; text: "Wallpapers"; topPadding: 0 }
                    SSegmented {
                        t: pal
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        model: ["All", "Pictures", "Animated", "★ Favourites"]
                        segWidth: 88
                        current: wpPane.filter
                        onPicked: i => wpPane.filter = i
                    }
                }

                Corners.ContinuousRectangle {
                    width: parent.width
                    height: 36
                    radius: 10
                    color: pal.ctrl
                    border.width: 1
                    border.color: wpSearchInput.activeFocus ? pal.accent : pal.cardBorder
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "⌕"
                            color: pal.text3
                            font.pixelSize: 19
                        }
                        Item {
                            width: parent.width - 52
                            height: parent.height
                            TextInput {
                                selectionColor: Corners.ThemeColors.selectionFor("settings", root.darkMode)
                                selectedTextColor: Corners.ThemeColors.selectedTextFor("settings", root.darkMode)
                                id: wpSearchInput
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                color: pal.text

                                font.family: pal.fam
                                font.pixelSize: 12
                                clip: true
                                selectByMouse: true
                                onTextChanged: wpPane.searchText = text
                            }
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "Search wallpapers"
                                color: pal.text3
                                font.family: pal.fam
                                font.pixelSize: 12
                                visible: wpSearchInput.text === "" && !wpSearchInput.activeFocus
                                MouseArea { anchors.fill: parent; onClicked: wpSearchInput.forceActiveFocus() }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: wpSearchInput.text !== ""
                            text: "×"
                            color: pal.text2
                            font.pixelSize: 18
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                onClicked: { wpSearchInput.clear(); wpSearchInput.forceActiveFocus(); }
                            }
                        }
                    }
                }

                GridView {
                    id: wpFlow
                    width: parent.width
                    cellWidth: Math.floor((width - 20) / 3)
                    cellHeight: Math.round(cellWidth * 0.625) + 32
                    height: Math.min(contentHeight, cellHeight * 3)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: wpPane.shown
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: 6
                        background: Corners.ContinuousRectangle {
                            color: pal.cardBorder
                            radius: 3
                            opacity: 0.45
                        }
                        contentItem: Corners.ContinuousRectangle {
                            color: pal.text3
                            radius: 3
                        }
                    }
                    delegate: Item {
                            id: wt
                            required property var modelData
                            width: wpFlow.cellWidth
                            height: wpFlow.cellHeight
                            readonly property bool cur: modelData.video ? wpPane.curVideo === modelData.path
                                                                        : (wpPane.curVideo === "" && wpPane.curStill === modelData.path)
                            Item {
                                id: wtBox
                                x: 5; y: 5
                                width: parent.width - 10; height: parent.height - 32
                                scale: wtMa.pressed ? 0.98 : 1
                                Item {
                                    id: wtMask
                                    anchors.fill: parent; visible: false
                                    layer.enabled: true; layer.smooth: true
                                    Corners.ContinuousRectangle { anchors.fill: parent; radius: 9; color: "black" }
                                }
                                Item {
                                    anchors.fill: parent
                                    layer.enabled: true; layer.smooth: true
                                    layer.effect: MultiEffect { maskEnabled: true; maskSource: wtMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                                    Corners.ContinuousRectangle { anchors.fill: parent; color: pal.ctrl }
                                    Image {
                                        anchors.fill: parent
                                        source: "file://" + (wt.modelData.video ? wt.modelData.thumb : wt.modelData.path)
                                        sourceSize.width: 260
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true; smooth: true
                                        opacity: status === Image.Ready ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 250 } }
                                    }
                                    Loader {
                                        anchors.fill: parent
                                        active: wt.modelData.video && wt.modelData.preview !== "" && wtMa.containsMouse
                                        sourceComponent: AnimatedImage {
                                            source: "file://" + wt.modelData.preview
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true; cache: false; playing: true
                                        }
                                    }
                                    Corners.ContinuousRectangle {
                                        visible: wt.modelData.video
                                        x: 6; y: 6
                                        width: wtBadge.implicitWidth + 12; height: 18; radius: 9
                                        color: Qt.rgba(0, 0, 0, 0.5)
                                        Text {
                                            id: wtBadge
                                            anchors.centerIn: parent
                                            text: "\u25B6  Animated"
                                            color: "white"; font.family: pal.fam; font.pixelSize: 9; font.weight: Font.DemiBold
                                        }
                                    }
                                }
                                Corners.ContinuousRectangle {
                                    anchors.fill: parent; anchors.margins: wt.cur ? -3 : 0
                                    radius: wt.cur ? 12 : 9
                                    color: "transparent"
                                    border.width: wt.cur ? 2.5 : 1
                                    border.color: wt.cur ? pal.accent : pal.cardBorder
                                }
                                MouseArea {
                                    id: wtMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (root.bar) root.bar.wpApply(wt.modelData.path)
                                }
                                    Corners.ContinuousRectangle { cornerSmoothing: 0;
                                        anchors.right: parent.right; anchors.top: parent.top
                                        anchors.margins: 7
                                        width: 26; height: 26; radius: 13
                                        visible: wt.modelData.fav || wtMa.containsMouse || wtFavMa.containsMouse
                                        color: Qt.rgba(0, 0, 0, wtFavMa.containsMouse ? 0.72 : 0.52)
                                        Text {
                                            anchors.centerIn: parent
                                            text: wt.modelData.fav ? "★" : "☆"
                                            color: wt.modelData.fav ? "#ffd60a" : "white"
                                            font.pixelSize: 16
                                        }
                                        MouseArea {
                                            id: wtFavMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: if (root.bar) root.bar.wpToggleFav(wt.modelData.path)
                                        }
                                    }
                            }
                            Text {
                                anchors.bottom: parent.bottom
                                x: 5
                                width: parent.width - 10
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideMiddle
                                text: wt.modelData.name
                                color: wt.cur ? pal.text : pal.text2
                                font.family: pal.fam; font.pixelSize: 11
                            }
                    }
                }
                SLabel {
                    t: pal
                    visible: wpPane.shown.length === 0
                    text: wpPane.searchText.trim() !== "" ? "No wallpapers match “" + wpPane.searchText + "”."
                        : wpPane.filter === 2 ? "No animated wallpapers yet. Drop .mp4 / .webm videos into " + (root.bar ? root.bar.wpDirEff : "~/Pictures/Wallpapers") + "."
                                              : "Nothing here yet."
                }
                SLabel { t: pal; text: "Tip: Ctrl+Alt+W opens the quick wallpaper picker, which shows animated wallpapers too." }
            }
        }

        Component {
            id: paneAbout
            Column {
                id: aboutCol
                spacing: 10
                property bool armed: false
                Timer { id: disarm; interval: 3000; onTriggered: aboutCol.armed = false }

                SCard {
                    t: pal
                    Item {
                        width: parent.width
                        height: 176
                        SGlyph {
                            x: (parent.width - width) / 2
                            y: 44
                            kind: "dock"
                            scale: 3.4
                        }
                        Text {
                            y: 108
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: "macshell"
                            color: pal.text
                            font.family: pal.fam
                            font.pixelSize: 21
                            font.weight: Font.DemiBold
                        }
                        Text {
                            y: 138
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: "Version 0.1.8 \u2022 Hyprland \u2022 Quickshell"
                            color: pal.text2
                            font.family: pal.fam
                            font.pixelSize: 12
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Configuration"
                        Text {
                            text: "~/.config/macdock"
                            color: pal.text2
                            font.family: pal.fam
                            font.pixelSize: 13
                        }
                    }
                    SRow {
                        t: pal
                        title: "Open configuration folder"
                        SButton {
                            t: pal
                            text: "Open"
                            onClicked: Quickshell.execDetached(["xdg-open", root.configDir])
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Install dependencies"
                        subtitle: "Installs everything MacShell uses (Quickshell, awww, mpvpaper, ffmpeg, wf-recorder, fonts, icons…) with your package manager, in a terminal"
                        SButton {
                            t: pal
                            text: "Install\u2026"
                            onClicked: {
                                var inst = Quickshell.env("HOME") + "/.local/share/macshell/install.sh";
                                var term = root.bar ? root.bar.terminal : "@BIN_DIR@/macshell-terminal";
                                Quickshell.execDetached(["sh", "-c", term + " -e sh -c '\"$0\" --deps-only; echo; echo Press Enter to close; read x'", inst]);
                            }
                        }
                    }
                }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Reset MacShell"
                        subtitle: "Restore every setting to its default (appearance, Dock, Menu Bar, widgets, lock screen, input). Pinned apps and your widgets' layout are kept."
                        SButton {
                            t: pal
                            destructive: true
                            text: aboutCol.armed ? "Click to Confirm" : "Reset\u2026"
                            onClicked: {
                                if (aboutCol.armed) { aboutCol.armed = false; root.resetSettings(); }
                                else { aboutCol.armed = true; disarm.restart(); }
                            }
                        }
                    }
                }

                // ── Credits ──
                SLabel { t: pal; header: true; text: "Credits" }
                SCard {
                    t: pal
                    Repeater {
                        model: [
                            { img: "assets/credits/0-ss.jpg", name: "Rickky", gh: "0-ss",
                              role: "Owner — the menu bar, the Dock, the Liquid Glass and the widgets. The one who actually knew what he was doing" },
                            { img: "assets/credits/vsoultann.png", name: "vSuol", gh: "vsoultann",
                              role: "Collaborator — improved the Settings app and window, and every bug you will ever find" }
                        ]
                        delegate: Item {
                            id: cr
                            required property var modelData
                            width: parent.width; height: 72
                            Corners.ContinuousRectangle { visible: cr.y > 0.5; x: 14; width: parent.width - 14; height: 1; color: pal.sep }
                            Item {
                                id: crPic
                                x: 14; anchors.verticalCenter: parent.verticalCenter
                                width: 44; height: 44
                                Item { id: crMask; anchors.fill: parent; visible: false; layer.enabled: true; Corners.ContinuousRectangle { anchors.fill: parent; radius: width / 2; color: "black" } }
                                Image {
                                    anchors.fill: parent
                                    source: Qt.resolvedUrl(cr.modelData.img)
                                    sourceSize: Qt.size(96, 96)
                                    fillMode: Image.PreserveAspectCrop; smooth: true; mipmap: true
                                    layer.enabled: true
                                    layer.effect: MultiEffect { maskEnabled: true; maskSource: crMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                                }
                                Corners.ContinuousRectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.width: 1; border.color: pal.cardBorder }
                            }
                            Column {
                                x: 70; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 70 - 90
                                spacing: 2
                                Text { text: cr.modelData.name; color: pal.text; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { width: parent.width; text: cr.modelData.role; wrapMode: Text.WordWrap; color: pal.text2; font.family: pal.fam; font.pixelSize: 11 }
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                                text: "@" + cr.modelData.gh
                                color: pal.accent; font.family: pal.fam; font.pixelSize: 12
                                font.underline: crMa.containsMouse
                                MouseArea { id: crMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["xdg-open", "https://github.com/" + cr.modelData.gh]) }
                            }
                        }
                    }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 4
                    text: "Designed by Apple in California.\nRebuilt on Linux by two people who could not afford the Mac."
                    color: pal.text3; font.family: pal.fam; font.pixelSize: 11
                }

                // (keep scrolling…)
                Item { width: 1; height: 900 }

                // ── AppleCare+ — nobody asked. The button does nothing. ──
                SCard {
                    t: pal
                    Item {
                        width: parent.width; height: 214
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 16
                            width: 36; height: 36
                            source: Qt.resolvedUrl(pal.dark ? "apple-logo-white.svg" : "apple-logo-black.svg")
                            sourceSize: Qt.size(72, 72); fillMode: Image.PreserveAspectFit; smooth: true
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 64
                            text: "Protect your MacShell with AppleCare+"
                            color: pal.text; font.family: pal.fam; font.pixelSize: 17; font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 90
                            width: parent.width - 60; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                            text: "Unlimited repairs for accidental damage, 24/7 priority access to Apple experts, and battery service coverage. Same price as for a MacBook Pro."
                            color: pal.text2; font.family: pal.fam; font.pixelSize: 12
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 136
                            text: "$279.00 for 3 years or $99.99/yr."
                            color: pal.text; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.Medium
                        }
                        Corners.ContinuousRectangle { cornerSmoothing: 0;
                            anchors.horizontalCenter: parent.horizontalCenter; y: 166
                            width: 150; height: 32; radius: 16
                            color: careMa.pressed ? Qt.darker(pal.accent, 1.15) : pal.accent
                            scale: careMa.pressed ? 0.96 : 1
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                            Text { anchors.centerIn: parent; text: "Add AppleCare+"; color: "white"; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                            MouseArea { id: careMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor }
                        }
                    }
                }
            }
        }
    }

    readonly property real effMag: magnificationEnabled ? magnification : 1
    readonly property int bgHeight: iconSize + topPad + bottomPad
    readonly property int sepWidth: 9
    readonly property real magRadius: (iconSize + spacing) * 2.6
    readonly property int menuRoom: 300
    readonly property int windowHeight: Math.ceil(margin + bgHeight + iconSize * (effMag - 1) + 72 + menuRoom)
    readonly property string configDir: Quickshell.env("HOME") + "/.config/macdock"

    property var items: []
    property int appCount: 0
    property int sepCount: 0
    readonly property real totalW0: Math.max(0, appCount * (iconSize + spacing) + sepCount * (sepWidth + spacing) - spacing)
    property var launching: ({})
    property var knownKeys: ({})
    // the Dock's cells live in a keyed ListModel updated in place: a cell is only created when its item appears and
    // only destroyed after it has animated out — every other cell (and its live window preview) keeps running
    property var itemMap: ({})
    ListModel { id: dockModel }
    readonly property var cellModel: dockModel
    function syncModel(list) {
        var m = dockModel;
        for (var i = 0; i < list.length; i++) {
            var k = list[i].key;
            if (i < m.count && m.get(i).key === k) continue;
            var j = -1;
            for (var x = i + 1; x < m.count; x++) if (m.get(x).key === k) { j = x; break; }
            if (j >= 0) m.move(j, i, 1); else m.insert(i, { key: k });
        }
        while (m.count > list.length) m.remove(m.count - 1);
    }
    property var leaving: ({})          // key → time it started leaving
    readonly property int leaveMs: 340
    Timer { id: leaveTimer; interval: root.leaveMs + 30; onTriggered: root.rebuild() }
    property string lastSig: ""

    // ───────────── LOGIC ─────────────
    function openPrefs(pane) {
        if (!settingsEnabled) return;
        if (pane !== undefined && pane !== "") {
            for (var i = 0; i < prefsWindow.panes.length; i++)
                if (prefsWindow.panes[i].id === pane) { prefsWindow.go(i); break; }
        }
        prefsWindow.visible = true;
        prefsWindow.requestActivate();
    }

    function resetPins() {
        pinned = defaultPinned;
        store.setText(JSON.stringify(defaultPinned.slice(), null, 2));
        rebuild();
    }

    function resetSettings() {
        Corners.DesktopPreferences.reset();
        Corners.ThemeColors.reset();
        Corners.IconStyle.reset();
        Corners.GlassMaterial.setMode("clear");
        dockEnabled = true;
        settingsEnabled = true;
        if (bar) {
            bar.resetSettings();
            bar.uiSounds = true; bar.gamingMode = false; bar.gamingAuto = true; bar.lockArtBackground = true;
            bar.applyLockClockPreset("glass");
            bar.wallpaperAppearance = "auto"; bar.notifDnd = false; bar.nightOn = false; bar.keepAwake = false;
            bar.kbRepeatRate = 35; bar.kbRepeatDelay = 250; bar.mouseSens = 0; bar.mouseNatural = false;
            bar.tpNatural = true; bar.tpTap = true; bar.tpDwt = true; bar.tpScroll = 0.7;
        }
        if (hub && hub.widgets) { hub.widgets.tempUnit = "C"; hub.widgets.locMode = "auto"; hub.widgets.cityName = ""; hub.widgets.widgetScale = 1.0; }
        Quickshell.execDetached(["sh", "-c", "rm -f \"$HOME/.config/maclock/settings.json\""]);
        iconSize = 52; magnification = 1.7; magnificationEnabled = true;
        spacing = 6; margin = 6; cornerRadius = 18; cornerSquircle = 0;
        darkMode = true; appearanceMode = "dark"; glassOpacity = 0.42; glassBlur = 5; glassLiquid = 1.0; dockStyle = "blur"; fontFamily = "SF Pro Text";
        hideMode = "smart"; hideDelay = 450; monitor = "";
        showTrash = true; showLabels = true; showIndicators = true; bounceOnLaunch = true; showThumbs = true; windowCapture = true;
    }

    // ── settings persistence (~/.config/macdock/settings.json) ──
    readonly property string settingsSig: [dockEnabled, settingsEnabled, iconSize, magnification, magnificationEnabled, spacing, margin,
        cornerRadius, cornerSquircle, darkMode, appearanceMode, glassOpacity, glassBlur, glassLiquid, dockStyle, wallpaperPath, String(accent), fontFamily, hideMode, hideDelay, monitor,
        showTrash, showLabels, showIndicators, bounceOnLaunch, showThumbs, windowCapture, iconTint, iconTintColor, iconTintStrength].join("|")
    property bool settingsReady: false
    onSettingsSigChanged: if (settingsReady) saveTimer.restart()
    onShowTrashChanged: { rebuild(); if (showTrash) trashCheck(); }
    onShowThumbsChanged: rebuild()
    onWindowCaptureChanged: rebuild()

    function saveSettings() {
        var o = {
            dockEnabled: dockEnabled, settingsEnabled: settingsEnabled, iconSize: iconSize, magnification: magnification, magnificationEnabled: magnificationEnabled,
            spacing: spacing, margin: margin, cornerRadius: cornerRadius, cornerSquircle: cornerSquircle,
            darkMode: darkMode, appearanceMode: appearanceMode, glassOpacity: glassOpacity, dockStyle: dockStyle, wallpaperPath: wallpaperPath, glassDebug: glassDebug,
            glassRim: glassRim, glassGrain: glassGrain, glassLiquid: glassLiquid, glassBlur: glassBlur,
            accent: String(accent), fontFamily: fontFamily,
            hideMode: hideMode, hideDelay: hideDelay, monitor: monitor,
            showTrash: showTrash, showLabels: showLabels, showIndicators: showIndicators,
            bounceOnLaunch: bounceOnLaunch, showThumbs: showThumbs, windowCapture: windowCapture,
            iconTint: iconTint, iconTintColor: iconTintColor, iconTintStrength: iconTintStrength
        };
        settingsStore.setText(JSON.stringify(o, null, 2));
    }

    function applySettings(o) {
        if (!o || typeof o !== "object") return;
        if (typeof o.cornerSquircle === "number" && isFinite(o.cornerSquircle))
            root.cornerSquircle = Math.max(0, Math.min(1, o.cornerSquircle));
        var keys = ["dockEnabled", "settingsEnabled", "iconSize", "magnification", "magnificationEnabled", "spacing", "margin", "cornerRadius",
                    "darkMode", "appearanceMode", "glassOpacity", "dockStyle", "wallpaperPath", "glassDebug", "glassRim", "glassGrain", "glassLiquid", "glassBlur", "accent", "fontFamily", "hideMode", "hideDelay", "monitor",
                    "showTrash", "showLabels", "showIndicators", "bounceOnLaunch", "showThumbs", "windowCapture", "iconTint", "iconTintColor", "iconTintStrength"];
        for (var i = 0; i < keys.length; i++) {
            if (["accent", "iconTint", "iconTintColor", "iconTintStrength"].indexOf(keys[i]) >= 0 || o[keys[i]] === undefined) continue;
            try { root[keys[i]] = o[keys[i]]; } catch (err) { }
        }
    }

    FileView {
        id: settingsStore
        path: root.configDir + "/settings.json"
        printErrors: false
        onLoaded: {
            try { root.applySettings(JSON.parse(text())); } catch (err) { }
            root.settingsReady = true;
            root.syncAppearance();
            if (root.dockStyle === "liquid") root.startGlass();
        }
        onLoadFailed: root.settingsReady = true
    }
    Timer { id: saveTimer; interval: 400; onTriggered: root.saveSettings() }

    function lookup(appId) {
        if (!appId) return null;
        var e = DesktopEntries.byId(appId);
        if (!e && DesktopEntries.heuristicLookup) e = DesktopEntries.heuristicLookup(appId);
        return e;
    }

    function keyOf(appId) {
        var e = lookup(appId);
        return (e ? e.id : appId).toLowerCase();
    }

    // stable ids so a window's preview cell isn't rebuilt on every refresh
    property var winIdList: []
    property int winIdNext: 1
    function winIdFor(tl) {
        for (var i = 0; i < winIdList.length; i++) if (winIdList[i].tl === tl) return winIdList[i].id;
        var id = winIdNext++;
        winIdList.push({ tl: tl, id: id, born: Date.now() });
        return id;
    }
    function winAge(tl) {
        for (var i = 0; i < winIdList.length; i++) if (winIdList[i].tl === tl) return Date.now() - winIdList[i].born;
        return 0;
    }
    Timer { id: youngWin; interval: 250; onTriggered: root.rebuild() }

    function iconSrc(icon) {
        icon = String(icon || "");
        if (!icon) return Quickshell.iconPath("application-x-executable");
        const folder = Corners.IconStyle.folderSource(icon);
        if (folder) return folder;
        if (/^(file|qrc|image):/.test(icon)) return icon;
        if (icon.charAt(0) === "/") return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }
    // icon of a dock cell; the Trash switches to the "full" icon while there is something in it
    function cellIconSrc(it) {
        if (it && it.special === "trash" && trashFull) {
            var p = Quickshell.iconPath("user-trash-full", true);
            if (p !== "") return p;
        }
        return iconSrc(it ? it.icon : "");
    }

    // ── Trash state: the standard XDG trash (~/.local/share/Trash/files) is what Dolphin's trash:/ shows ──
    // inotifywait (inotify-tools) reports changes at once; without it the folder is checked every 3 s.
    property bool trashFull: false
    property bool trashReady: false           // first check done (it also creates the folder, which inotifywait needs)
    property bool trashPoll: false            // no inotifywait: poll instead
    readonly property string trashDir: {
        var x = Quickshell.env("XDG_DATA_HOME");
        return ((x && x !== "") ? x : Quickshell.env("HOME") + "/.local/share") + "/Trash/files";
    }
    function trashCheck() { if (!trashCheckProc.running) trashCheckProc.running = true; }
    Process {
        id: trashCheckProc
        command: ["sh", "-c", "mkdir -p \"$1\"; if [ -n \"$(ls -A \"$1\" 2>/dev/null | head -n 1)\" ]; then s=1; else s=0; fi; "
                              + "if command -v inotifywait >/dev/null 2>&1; then w=w; else w=p; fi; echo \"$s $w\"", "sh", root.trashDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.trim().split(" ");
                root.trashFull = t[0] === "1";
                root.trashPoll = t[1] === "p";
                root.trashReady = true;
            }
        }
    }
    Process {
        id: trashWatch
        running: root.showTrash && root.trashReady && !root.trashPoll
        command: ["inotifywait", "-m", "-q", "-e", "create", "-e", "delete", "-e", "moved_to", "-e", "moved_from", root.trashDir]
        stdout: SplitParser { onRead: data => trashDebounce.restart() }
    }
    // Empty Trash: KDE's ktrash when it exists (it also cleans trashes on other drives and keeps Dolphin's trash icon in sync),
    // otherwise the standard XDG trash folder is cleared directly. (gio is not used: without gvfs it "succeeds" without doing anything.)
    function emptyTrash() {
        Quickshell.execDetached(["sh", "-c",
            "command -v ktrash6 >/dev/null 2>&1 && ktrash6 --empty && exit 0; "
            + "command -v ktrash5 >/dev/null 2>&1 && ktrash5 --empty && exit 0; "
            + "d=\"${XDG_DATA_HOME:-$HOME/.local/share}/Trash\"; "
            + "chmod -R u+w \"$d/files\" 2>/dev/null; "
            + "find \"$d/files\" \"$d/info\" -mindepth 1 -delete 2>/dev/null; "
            + "rm -f \"$d/directorysizes\""]);
        trashAfterEmpty.restart();
        if (bar) bar.playSound("trash", 0.8);
    }
    Timer { id: trashAfterEmpty; interval: 900; onTriggered: root.trashCheck() }
    Timer { id: trashDebounce; interval: 150; onTriggered: root.trashCheck() }
    Timer { interval: 3000; repeat: true; running: root.showTrash && root.trashPoll; onTriggered: root.trashCheck() }

    // bumped (debounced) whenever windows open, close or change focus; thumbnails re-pick their window from it
    property int windowTick: 0
    Timer { id: tickDebounce; interval: 120; onTriggered: root.windowTick++ }

    // the window an unpinned app is represented by: the focused one, else the first
    function thumbWindow(key) {
        var w = windowsFor(key);
        for (var i = 0; i < w.length; i++) if (w[i].activated) return w[i];
        return w.length > 0 ? w[0] : null;
    }

    // MacShell's own windows all have the app id "org.quickshell": the Clock window counts as the Clock app.
    // Utility surfaces do not create Dock apps or window previews.
    readonly property string settingAppIcon: Quickshell.env("HOME") + "/.local/share/icons/MacTahoe/apps/scalable/preferences-system.svg"
    function isSettingApp(appId) { return String(appId) === "systemsettings"; }
    function internalWindow(tl) {
        return !!tl && (tl.title === "qs-launchpad-backdrop"
            || (tl.appId === "org.quickshell" && tl.title === "About This Linux"));
    }
    function appOf(tl) {
        if (internalWindow(tl)) return "";
        if (tl.appId === "org.quickshell") {
            if (tl.title === "Clock") return "macshell-clock";
            if (["Setting", "Settings", "macshell Settings"].indexOf(tl.title) >= 0) return "systemsettings";   // the Setting app
        }
        return tl.appId;
    }
    function windowsFor(key) {
        var out = [];
        var tls = ToplevelManager.toplevels.values;
        for (var i = 0; i < tls.length; i++) {
            if (tls[i].appId && !internalWindow(tls[i]) && keyOf(appOf(tls[i])) === key) out.push(tls[i]);
        }
        return out;
    }

    // points for a superellipse ("squircle") rounded rectangle, for the Shape fallback
    function squirclePoints(w, h, rad, sq, inset) {
        return Curve.points(w,h,rad,sq,inset);
    }

    // address of the settings window itself (it is a Wayland toplevel of this same process),
    // so its own yellow traffic light can use the macOS minimize/genie pipeline
    function prefsAddr() {
        var tls = ToplevelManager.toplevels.values;
        for (var i = 0; i < tls.length; i++)
            if (tls[i].title === prefsWindow.title) return winAddr(tls[i]);
        return "";
    }

    // Hyprland address (no 0x) of a Wayland toplevel, for the minimize bridge
    function winAddr(tl) {
        if (!tl) return "";
        var v = Hyprland.toplevels.values;
        for (var i = 0; i < v.length; i++) if (v[i].wayland === tl) return String(v[i].address).replace(/^0x/, "");
        return "";
    }

    // the toplevel that a Dock click should act on (the focused one, else the first)
    function firstMinimized(list) {
        for (var i = 0; i < list.length; i++) {
            var a = winAddr(list[i]);
            if (a !== "" && root.minimize.isMinimized(a)) return a;
        }
        return "";
    }

    function activate(item, forceNew) {
        // Handle Launchpad before the normal-app path dismisses the launcher.
        // Both this icon and Super+A use the helper, which starts it if needed.
        if (!item) return;
        if (root.hub) root.hub.desktopController.send({action: "resume"});
        if (item.kind === "app" && !forceNew) rememberApp(item.appId || item.key);
        if (item && item.key === launchpadKey) {
            Corners.AppMenu.toggle();
            return;
        }
        // Any Dock click dismisses an open Launchpad (the app then opens/focuses
        // normally). Idempotent when the Launchpad is already closed.
        Quickshell.execDetached(["qs", "-c", "launchpad", "ipc", "call", "launchpad", "close"]);
        // a minimized (parked) window: bring it back with the Dock animation instead of focusing.
        // a running window that is already in front: clicking its Dock presence parks it, so the
        // same click toggles minimize/restore without reaching for the traffic light.
        if (root.minimize) {
            if (item.kind === "win") {
                var wa = winAddr(item.tl);
                if (wa !== "") {
                    if (root.minimize.isMinimized(wa)) { root.minimize.restore(wa); return; }
                    
                }
            } else if (item.kind === "app" && item.key && item.key !== "__trash") {
                var ws = windowsFor(item.key), visible = false, minAddr = "", actAddr = "";
                for (var wi = 0; wi < ws.length; wi++) {
                    var a2 = winAddr(ws[wi]);
                    if (a2 === "") continue;
                    if (root.minimize.isMinimized(a2)) { if (minAddr === "") minAddr = a2; }
                    else { visible = true; if (ws[wi].activated && actAddr === "") actAddr = a2; }
                }
                if (!visible && minAddr !== "") { root.minimize.restore(minAddr); return; }
                // the app is running and in front: the Dock click minimizes it (click again to restore)
                
                // otherwise fall through: a background app is brought forward like a normal Dock click
            }
        }
        if (item.kind === "win") { focusWindow(item.tl); return; }
        if (item.special === "trash") {
            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/macshell-files", "trash:///"]);
            return;
        }
        var wins = windowsFor(item.key);
        if (wins.length > 0 && !forceNew) {
            var idx = -1;
            for (var i = 0; i < wins.length; i++) if (wins[i].activated) idx = i;
            focusWindow(wins[(idx + 1) % wins.length]);
            return;
        }
        if (item.key === "systemsettings") { root.openPrefs(); return; }   // the Setting app is MacShell's own window
        if (item.entry || item.key) {
            var L = {};
            for (var k in launching) L[k] = launching[k];
            L[item.key] = Date.now();
            launching = L;
            // resolve the desktop entry again at click time: the one stored in the dock model can be a stale object
            // (after the app database reloads it turned into "TypeError ... execute is not a function", and Files never opened)
            var ent = null;
            var rid = item.appId || item.key;
            try { ent = DesktopEntries.byId(rid); } catch (err) { ent = null; }
            if (!ent) { try { ent = DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(item.key) : null; } catch (err2) { ent = null; } }
            var ok = false;
            if (ent && typeof ent.execute === "function") { try { ent.execute(); ok = true; } catch (err3) { ok = false; } }
            if (!ok) {
                var id = rid;
                console.log("[macdock] launching", id, "via gtk-launch (desktop entry unavailable)");
                Quickshell.execDetached(["sh", "-c", 'gtk-launch "$1" 2>/dev/null || gtk-launch "$1.desktop" 2>/dev/null || exec "$1"', "sh", id]);
            }
            pruneTimer.restart();
        }
    }

    function hasPin(key) {
        if (!pinned) return false;
        for (var i = 0; i < pinned.length; ++i)
            if (String(pinned[i]).replace(/\.desktop$/, "").toLowerCase() === key) return true;
        return false;
    }

    function setLaunchpadPinned(enabled) {
        if (enabled === launchpadPinned) return;
        togglePin({ key: launchpadKey });
    }

    // Append a pin (used by "Add to Dock" from the Launchpad) without touching
    // an existing pin order.
    function addPin(id) {
        var key = String(id).replace(/\.desktop$/, "");
        if (key === "" || hasPin(key)) return;
        var out = pinned.slice();
        out.push(key);
        pinned = out;
        store.setText(JSON.stringify(out, null, 2));
        rebuild();
    }

    function togglePin(item) {
        var out = [], found = false;
        for (var i = 0; i < pinned.length; i++) {
            var id = String(pinned[i]).replace(/\.desktop$/, "");
            if (id.toLowerCase() === item.key) { found = true; continue; }
            out.push(pinned[i]);
        }
        if (!found && item.key === launchpadKey) out.unshift(launchpadKey);
        else if (!found && item.entry) out.push(item.entry.id);
        pinned = out;
        store.setText(JSON.stringify(out, null, 2));
        rebuild();
    }

    function reorderPinned(from, to) {
        var vis = [];
        for (var i = 0; i < items.length; i++) {
            var it = items[i];
            if (it.kind === "app" && it.pinned && !it.special) vis.push(it);
            else break;
        }
        if (from < 0 || from >= vis.length) return;
        var moved = vis.splice(from, 1)[0];
        vis.splice(Math.max(0, Math.min(to, vis.length)), 0, moved);

        var out = [], have = {};
        for (var v = 0; v < vis.length; v++) { out.push(vis[v].appId || vis[v].entry.id); have[vis[v].key] = true; }
        for (var p = 0; p < pinned.length; p++) {
            var id = String(pinned[p]).replace(/\.desktop$/, "");
            if (!have[id.toLowerCase()]) out.push(pinned[p]);
        }
        pinned = out;
        store.setText(JSON.stringify(out, null, 2));
        rebuild();
    }

    function menuFor(item) {
        var m = [];
        if (item.kind === "win") {
            var wa = root.minimize ? winAddr(item.tl) : "";
            if (root.minimize && wa !== "") {
                if (root.minimize.isMinimized(wa))
                    m.push({ kind: "item", label: "Restore", run: function () { root.minimize.restore(wa); } });
                else
                    m.push({ kind: "item", label: "Minimize", run: function () { root.minimize.minimize(wa); } });
                m.push({ kind: "sep" });
            }
            m.push({ kind: "item", label: "Show", run: function () { activate(item, false); } });
            m.push({ kind: "item", label: "Close", run: function () { if (item.tl) item.tl.close(); } });
            m.push({ kind: "sep" });
            m.push({ kind: "item", label: "Settings\u2026", run: function() { root.openPrefs(); } });
            return m;
        }
        if (item.special === "trash") {
            m.push({ kind: "item", label: "Open", run: function () { activate(item, false); } });
            m.push({ kind: "item", label: "Empty Trash", confirm: true, disabled: !trashFull, run: function () { root.emptyTrash(); } });
            m.push({ kind: "sep" });
            m.push({ kind: "item", label: "Settings\u2026", run: function() { root.openPrefs(); } });
            return m;
        }
        if (item.key === launchpadKey) {
            m.push({ kind: "item", label: "Open", run: function () { activate(item, false); } });
            m.push({ kind: "item", label: "Remove from Dock", run: function () { togglePin(item); } });
            m.push({ kind: "sep" });
            m.push({ kind: "item", label: "Settings\u2026", run: function () { root.openPrefs("apps"); } });
            return m;
        }
        var wins = windowsFor(item.key);
        if (wins.length > 0) {
            for (var i = 0; i < wins.length && i < 8; i++) {
                (function (w) {
                    var t = w.title && w.title.length > 0 ? w.title : item.name;
                    m.push({ kind: "item", label: (w.activated ? "\u2713  " : "") + t,
                             run: function () { root.focusWindow(w); } });
                    if (desktopPrefs.stageManager && root.hub) {
                        m.push({kind: "item", label: "Add to Current Group: " + t,
                            run: function() { root.hub.desktopController.send({action:"join", addr:winAddr(w)}); }});
                        m.push({kind: "item", label: "Separate Window: " + t,
                            run: function() { root.hub.desktopController.send({action:"ungroup", addr:winAddr(w)}); }});
                    }
                })(wins[i]);
            }
            if (root.minimize) {
                var mvAddr = "";
                for (var mi = 0; mi < wins.length; mi++) {
                    var ma = winAddr(wins[mi]);
                    if (ma !== "" && !root.minimize.isMinimized(ma)) { mvAddr = ma; break; }
                }
                if (mvAddr !== "")
                    m.push({ kind: "item", label: "Minimize", run: function () { root.minimize.minimize(mvAddr); } });
            }
            m.push({ kind: "sep" });
        }
        if (item.entry) {
            m.push({ kind: "item", label: item.pinned ? "Remove from Dock" : "Keep in Dock",
                     run: function () { togglePin(item); } });
            m.push({ kind: "item", label: wins.length > 0 ? "New Window" : "Open",
                     run: function () { activate(item, true); } });
        }
        if (wins.length > 0) {
            m.push({ kind: "sep" });
            m.push({ kind: "item", label: "Quit", run: function () {
                var ws = windowsFor(item.key);
                for (var j = 0; j < ws.length; j++) ws[j].close();
            } });
        }
        
        m.push({ kind: "sep" });
        m.push({ kind: "item", label: "Settings\u2026", run: function() { root.openPrefs(); } });

        return m;
    }

    function rebuild() {
        var tls = ToplevelManager.toplevels.values;
        var running = {};
        var runOrder = [];
        for (var i = 0; i < tls.length; i++) {
            var id = appOf(tls[i]);
            if (!id) continue;
            var k = keyOf(id);
            if (!running[k]) { running[k] = true; runOrder.push({ key: k, appId: id }); }
        }

        for (var recentIndex = 0; recentIndex < runOrder.length; recentIndex++) {
            if (!previousRunning[runOrder[recentIndex].key]) rememberApp(runOrder[recentIndex].appId);
        }
        previousRunning = running;
        var L = {}, now = Date.now(), changed = false;
        for (var lk in launching) {
            if (!running[lk] && now - launching[lk] < 8000) L[lk] = launching[lk];
            else changed = true;
        }
        if (changed) launching = L;

        var list = [], seen = {};
        for (var p = 0; p < pinned.length; p++) {
            if (String(pinned[p]).replace(/\.desktop$/, "").toLowerCase() === launchpadKey) {
                if (!seen[launchpadKey]) {
                    seen[launchpadKey] = true;
                    list.push({ kind: "app", key: launchpadKey, appId: launchpadKey, name: Corners.AppMenu.label,
                                icon: launchpadIcon, entry: null, running: false, pinned: true });
                }
                continue;
            }
            if (isSettingApp(String(pinned[p]).replace(/\.desktop$/, ""))) {   // the Setting app: identity is hard-coded (no .desktop file)
                if (!seen["systemsettings"]) {
                    seen["systemsettings"] = true;
                    list.push({ kind: "app", key: "systemsettings", appId: "systemsettings", name: "Settings",
                                icon: settingAppIcon, entry: null, running: !!running["systemsettings"], pinned: true });
                }
                continue;
            }
            var e = DesktopEntries.byId(String(pinned[p]).replace(/\.desktop$/, ""));
            if (!e) continue;
            var ek = e.id.toLowerCase();
            if (seen[ek]) continue;
            seen[ek] = true;
            list.push({ kind: "app", key: ek, appId: e.id, name: e.name, icon: e.icon, entry: e,
                        running: !!running[ek], pinned: true });
        }

        var extras = [];
        for (var r = 0; r < runOrder.length; r++) if (!seen[runOrder[r].key]) { extras.push(runOrder[r]); seen[runOrder[r].key] = true; }
        if (extras.length > 0 && list.length > 0) list.push({ kind: "sep", key: "sep:run" });
        for (var x = 0; x < extras.length; x++) {
            if (isSettingApp(extras[x].appId)) {          // the Setting app (no .desktop file -> hard-coded identity)
                list.push({ kind: "app", key: extras[x].key, appId: "systemsettings",
                            name: "Settings", icon: settingAppIcon,
                            entry: null, running: true, pinned: false });
                continue;
            }
            var e2 = lookup(extras[x].appId);
            list.push({ kind: "app", key: extras[x].key, appId: e2 ? e2.id : extras[x].appId,
                        name: e2 ? e2.name : extras[x].appId,
                        icon: e2 ? e2.icon : extras[x].appId.toLowerCase(),
                        entry: e2, running: true, pinned: false });
        }

        if (desktopPrefs.showRecentApps) {
            var recentItems = [];
            for (var ri = 0; ri < recentApps.length && recentItems.length < 3; ri++) {
                var re = lookup(recentApps[ri]);
                if (!re || seen[keyOf(re.id)]) continue;
                seen[keyOf(re.id)] = true;
                recentItems.push({kind: "app", key: keyOf(re.id), appId: re.id, name: re.name,
                    icon: re.icon, entry: re, running: false, pinned: false, recent: true});
            }
            if (recentItems.length) {
                if (list.length) list.push({kind: "sep", key: "sep:recent"});
                list = list.concat(recentItems);
            }
        }
        // Separate minimized windows remain available even with live previews off.
        var winItems = [], liveWins = [];
        {
            for (var w = 0; w < tls.length; w++) {
                var tl = tls[w];
                if (!tl.appId || isSettingApp(appOf(tl)) || internalWindow(tl)) continue;
                var minAddr = winAddr(tl);
                var minimized = root.minimize && root.minimize.isMinimized(minAddr);
                if (minimized ? desktopPrefs.minimizeIntoApp : !showThumbs) continue;
                // live capture off: a preview cell is only an app icon, so a pinned app (its icon is already in the Dock) gets none; unpinned apps keep theirs
                if (!minimized && !windowCapture && hasPin(keyOf(appOf(tl)))) continue;
                var e3 = lookup(appOf(tl));
                // Register every window before checking its age. A valid Hyprland
                // address must not skip registration, or winAge stays zero forever.
                var registeredId = winIdFor(tl);
                var wid = minAddr || registeredId;
                liveWins.push(tl);
                if (winAge(tl) < 200) { if (!youngWin.running) youngWin.start(); continue; }     // no preview (= no capture) for brand-new windows
                var record = root.minimize && root.minimize.records[minAddr];
                winItems.push({ kind: "win", key: "win:" + wid, tl: tl,
                                minimized: minimized, shot: minimized && record ? record.shot : "",
                                name: e3 ? e3.name : tl.appId,
                                icon: e3 ? e3.icon : tl.appId.toLowerCase(),
                                entry: null, running: false, pinned: false });
            }
        }
        var keep = [];
        for (var wi = 0; wi < winIdList.length; wi++) if (liveWins.indexOf(winIdList[wi].tl) >= 0) keep.push(winIdList[wi]);
        winIdList = keep;

        if (showTrash || winItems.length > 0) {
            list.push({ kind: "sep", key: "sep:win" });
            for (var wj = 0; wj < winItems.length; wj++) list.push(winItems[wj]);
        }
        if (showTrash && winItems.length > 0) list.push({ kind: "sep", key: "sep:trash" });
        if (showTrash) {
            list.push({ kind: "app", key: "__trash", name: "Trash", icon: "user-trash",
                        entry: null, running: false, pinned: true, special: "trash" });
        }

        var firstBuild = (lastSig === "");
        // closed apps / windows don't vanish: they stay for a moment as "leaving" cells that shrink and fade out —
        // the opening animation played backwards — then are dropped by leaveTimer's rebuild
        var liveKeys = {};
        for (var lq = 0; lq < list.length; lq++) if (list[lq].key) liveKeys[list[lq].key] = true;
        var LV = {};
        for (var lk2 in leaving) if (!liveKeys[lk2] && now - leaving[lk2] < leaveMs) LV[lk2] = leaving[lk2];
        if (!firstBuild) {
            var prev = items || [];
            for (var pv = 0; pv < prev.length; pv++) {
                var po = prev[pv];
                if (!po.key || liveKeys[po.key]) continue;
                if (LV[po.key] === undefined) { if (po.leaving) continue; LV[po.key] = now; }
                // put it back after the item that preceded it last time
                var at = 0;
                for (var pb = pv - 1; pb >= 0; pb--) {
                    var ix = -1;
                    for (var q = 0; q < list.length; q++) if (list[q].key === prev[pb].key) { ix = q; break; }
                    if (ix >= 0) { at = ix + 1; break; }
                }
                var cp = {};
                for (var f in po) cp[f] = po[f];
                cp.leaving = true; cp.leaveAt = LV[po.key]; cp.fresh = false;
                cp.tl = null;          // the window is gone: never capture a destroyed toplevel (that crashed the shell)
                list.splice(at, 0, cp);
            }
        }
        leaving = LV;
        var anyLeaving = false;
        for (var lk3 in LV) { anyLeaving = true; break; }
        if (anyLeaving) leaveTimer.restart();

        var nowKeys = {}, nA = 0, nS = 0, sig = [];
        for (var n = 0; n < list.length; n++) {
            var it = list[n];
            it.nA = nA; it.nS = nS;
            if (it.kind === "sep") nS++; else nA++;
            if (it.key && !it.leaving) {
                it.fresh = !firstBuild && !knownKeys[it.key];
                nowKeys[it.key] = true;
            }
            sig.push(it.kind + ":" + (it.key || "") + ":" + it.running + ":" + (it.shot || "") + ":" + it.minimized + ":" + (it.icon || "") + (it.leaving ? ":L" : ""));
        }
        appCount = nA;
        sepCount = nS;
        knownKeys = nowKeys;

        var s = sig.join("|");
        if (s !== lastSig) {
            lastSig = s;
            var map = {};
            for (var mi = 0; mi < list.length; mi++) map[list[mi].key] = list[mi];
            itemMap = map;
            items = list;
            syncModel(list);
        }
    }

    // ═════════════ LIQUID GLASS BACKEND ═════════════
    // glassState: "idle" → "building" (qsb running) → "ready" | "failed". "failed" falls back to Normal Blur.
    property string glassState: "idle"
    readonly property bool liquidActive: dockStyle === "liquid" && glassState === "ready" && !(bar && bar.gaming)
    readonly property string glassShaderSrc: decodeURIComponent(Qt.resolvedUrl("liquidglass.frag").toString().replace("file://", ""))
    // Use a distinct URL so Qt cannot reuse the previous glowing glass shader.
    readonly property string glassShaderOut: configDir + "/dock-light-milk-v1.frag.qsb"
    readonly property url glassShaderUrl: "file://" + glassShaderOut

    onDockStyleChanged: if (dockStyle === "liquid") startGlass()
    onGlassStateChanged: console.log("[macdock-glass] state:", glassState)
    function startGlass() {
        if (glassState === "ready" || glassState === "building") return;
        glassState = "building";
        qsbProc.running = true;
        hub.refreshWallpaper();
        refreshBusy();                 // monitor geometry for the window compositor
    }
    Process {
        id: qsbProc
        command: ["sh", "-c",
            "mkdir -p \"$(dirname \"$2\")\"; "
            + "for q in qsb qsb6 qsb-qt6 /usr/lib/qt6/bin/qsb /usr/lib64/qt6/bin/qsb /usr/lib/qt/bin/qsb; do "
            + "  if command -v \"$q\" >/dev/null 2>&1; then \"$q\" --qt6 -D DOCK_THIN_BORDER -o \"$2\" \"$1\" && exit 0; fi; "
            + "done; "
            + "[ -f \"$1.dock.qsb\" ] && cp \"$1.dock.qsb\" \"$2\" && exit 0; "
            + "exit 1",
            "sh", root.glassShaderSrc, root.glassShaderOut]
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.log("[macdock-glass] qsb:", text.trim()) }
        onExited: (code, status) => root.glassState = (code === 0 ? "ready" : "failed")
    }

    // wallpaper the glass refracts. Sources, in order: wallpaperPath override, Noctalia's settings.toml
    // ([wallpaper.monitors.<name>] → [wallpaper.last] → [wallpaper.default]), then awww/swww/hyprpaper.
    readonly property var wallpaperMap: hub ? hub.wallpaperMap : ({})
    Binding { target: root.hub; property: "dockWantsWallpaper"; value: root.liquidActive }
    onWallpaperMapChanged: console.log("[macdock-glass] wallpaper sources:", JSON.stringify(wallpaperMap))
    function wallpaperFor(screenName) {
        var p = wallpaperPath !== "" ? wallpaperPath
              : (wallpaperMap["wallpaper.monitors." + screenName] || wallpaperMap["wallpaper.last"]
                 || wallpaperMap["wallpaper.default"] || "");
        if (p.indexOf("~/") === 0) p = Quickshell.env("HOME") + p.substring(1);
        return p;
    }
    function fileUrl(p) {
        if (p === "") return "";
        if (p.indexOf("file://") === 0) return p;
        return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    // live window geometry for the backdrop compositor (polled only while Liquid Glass is on)
    readonly property var glassClients: hub ? hub.glassClients : []
    Binding { target: root.hub; property: "dockWantsGeo"; value: root.liquidActive && (root.dockEnabled || prefsWindow.visible) }
    // window captures are admitted by the shared gate in shell.qml (hub.tlFor): 0.2 s after a window appears, one every 110 ms

    // Smart hide includes tiled, fullscreen, independent Zoom and floating Fill windows.
    property var busyMonitors: ({})
    property var monData: []
    property bool refreshPending: false

    function refreshBusy() {
        if (monProc.running || clientProc.running) { refreshPending = true; return; }
        monProc.running = true;
    }

    function computeBusy(clients) {
        busyMonitors = DockVisibility.busyMonitors(monData, clients);
    }

    Process {
        id: monProc
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.monData = JSON.parse(text); } catch (err) { }
                clientProc.running = true;
            }
        }
    }
    Process {
        id: clientProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.computeBusy(JSON.parse(text)); } catch (err) { }
                if (root.refreshPending) { root.refreshPending = false; monProc.running = true; }
            }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { busyDebounce.restart(); tickDebounce.restart(); }
    }
    Timer { id: busyDebounce; interval: 120; onTriggered: root.refreshBusy() }

    Component.onCompleted: {
        console.log("[corner-settings] loaded settings with Continuous Corner control v3");
        Quickshell.execDetached(["mkdir", "-p", configDir]);
        rebuild();
        refreshBusy();
        trashCheck();
    }

    FileView {
        id: store
        path: root.configDir + "/pinned.json"
        watchChanges: true
        onFileChanged: reload()
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onSaveFailed: console.warn("[macdock] could not save Dock pins")
        onLoaded: {
            try {
                var a = JSON.parse(text());
                if (Array.isArray(a)) { root.pinned = a; root.rebuild(); }
            } catch (err) { }
        }
    }

    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { root.rebuild(); settle.restart(); tickDebounce.restart(); }
    }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.rebuild(); }
    }
    Timer { id: settle; interval: 350; onTriggered: root.rebuild() }
    Timer { id: pruneTimer; interval: 8200; onTriggered: root.rebuild() }

    // ───────────── UI ─────────────
    Variants {
        model: (root.settingsReady && root.dockEnabled) ? Quickshell.screens : []

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.position === "bottom" && !root.launchpadHidesDock && (root.monitor === "" || modelData.name === root.monitor)

            anchors { left: true; right: true; bottom: true }
            implicitHeight: root.windowHeight
            color: "transparent"

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.hideMode === "never" ? root.bgHeight + root.margin : 0

            WlrLayershell.namespace: "macdock"
            WlrLayershell.layer: WlrLayer.Top

            mask: Region { item: maskItem }

            // the lifted item lives in its own full-screen, click-through overlay so it can go anywhere on the screen
            // (the Dock's own surface only covers the bottom of the screen — it used to be cut off half way up)
            PanelWindow {
                id: tearWin
                screen: win.modelData
                visible: ui.tearing || tearLaunch.running || tearHome.running || ghostFade.running || oldOut.running
                anchors { left: true; right: true; top: true; bottom: true }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                mask: Region {}
                WlrLayershell.namespace: "macdock-drag"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                // the window where it WAS: a still copy that takes its place the instant the real window jumps to the
                // pointer, then fades and sinks away — so the old spot never just blinks empty
                Item {
                    id: oldSnap
                    property bool shown: false
                    visible: shown && opacity > 0.01
                    opacity: 0
                    transformOrigin: Item.Center
                    Corners.ContinuousRectangle { anchors.fill: parent; radius: 10; color: Qt.rgba(0.09, 0.08, 0.09, 0.88) }
                    ScreencopyView {
                        id: oldSv
                        anchors.fill: parent
                        live: false
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: oldMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                    }
                    Item { id: oldMask; anchors.fill: parent; visible: false; layer.enabled: true; Corners.ContinuousRectangle { anchors.fill: parent; radius: 10; color: "black" } }
                    ParallelAnimation {
                        id: oldOut
                        NumberAnimation { target: oldSnap; property: "opacity"; from: 1; to: 0; duration: 340; easing.type: Easing.OutCubic }
                        NumberAnimation { target: oldSnap; property: "scale"; from: 1; to: 0.94; duration: 420; easing.type: Easing.OutQuint }
                        onFinished: { oldSnap.shown = false; oldSv.captureSource = null; }
                    }
                }
                Item {
                    id: tearGhost
                    property real zoom: 1
                    property real wob: 0
                    readonly property bool isWin: ui.tearItem !== null && ui.tearItem.kind === "win"
                    // a window preview is picked up like the window itself: the higher it's pulled out of the Dock the
                    // closer it gets to the window's real size, held near its title bar (no wiggle — it's a window)
                    readonly property real liftRaw: isWin ? Math.max(0, Math.min(1, (ui.activeTop - ui.tearY) / 240)) : 0
                    property real lift: 1 - Math.pow(1 - liftRaw, 3)
                    Behavior on lift { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    readonly property real thumbW: 170
                    readonly property real liftW: thumbW + (ui.tearW - thumbW) * lift
                    readonly property real grabFy: 0.5 + (0.035 - 0.5) * lift
                    readonly property real offY: tearWin.height - win.height   // Dock surface → screen coordinates
                    visible: opacity > 0.01
                    width: isWin ? liftW : root.iconSize * 1.12
                    height: isWin ? liftW * ui.tearH / ui.tearW : width
                    x: ui.tearX - width / 2
                    y: offY + ui.tearY - height * (isWin ? grabFy : 0.5)
                    scale: zoom
                    rotation: isWin ? 0 : wob
                    Image {
                        visible: !tearGhost.isWin
                        anchors.fill: parent
                        source: ui.tearSrc
                        sourceSize: Qt.size(256, 256)
                        smooth: true; mipmap: true
                    }
                    // translucent windows (terminals) get Hyprland's blur behind them; the lifted copy can't, so it gets a
                    // dark backing instead — otherwise it reads as a faint see-through ghost, not the window
                    Corners.ContinuousRectangle {
                        visible: tearGhost.isWin
                        anchors.fill: parent; radius: 10
                        color: Qt.rgba(0.09, 0.08, 0.09, 0.88)
                    }
                    ScreencopyView {
                        id: gsv
                        visible: tearGhost.isWin
                        anchors.fill: parent
                        captureSource: tearGhost.isWin && tearWin.visible ? ui.tearItem.tl : null
                        live: tearGhost.isWin && tearWin.visible && tearGhost.visible
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: gsvMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                    }
                    Item { id: gsvMask; anchors.fill: parent; visible: false; layer.enabled: true; Corners.ContinuousRectangle { anchors.fill: parent; radius: 10; color: "black" } }
                    Corners.ContinuousRectangle {
                        visible: tearGhost.isWin
                        anchors.fill: parent; radius: 10; color: "transparent"
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.25)
                    }
                    // light wiggle while held
                    SequentialAnimation on wob {
                        running: ui.tearing
                        loops: Animation.Infinite
                        NumberAnimation { to: 2.5; duration: 90; easing.type: Easing.InOutSine }
                        NumberAnimation { to: -2.5; duration: 180; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 90; easing.type: Easing.InOutSine }
                    }
                }
            }

            Item {
                id: ui
                anchors.fill: parent

                property real mx: 0
                Behavior on mx { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }
                property bool revealed: false
                property var menuItem: null
                property var menuModel: []
                property string armed: ""            // label of a confirm-type entry that was clicked once (e.g. Empty Trash)
                onMenuItemChanged: armed = ""
                property real menuCx: 0
                readonly property bool menuOpen: menuItem !== null
                readonly property bool wantsHide: root.hideMode === "always"
                    || (root.hideMode === "smart" && root.busyMonitors[win.modelData.name] === true)
                property bool dragging: false
                property int dragIndex: -1
                property int dragTarget: -1
                property string dragKey: ""
                property real dragPressX: 0
                property real dragDelta: 0
                property real dragShiftW: 0
                property bool justDragged: false
                // tear-off: an icon dragged up out of the Dock follows the pointer (wiggling); dropped over the desktop it
                // zooms up and fades while the app opens / comes to the front, dropped back on the Dock it flies home
                property bool tearing: false
                property var tearItem: null
                property string tearSrc: ""
                property real tearX: 0
                property real tearY: 0
                property real tearHomeX: 0
                property real tearHomeY: 0
                // window being dragged: its real size (capped) and Hyprland address
                property real tearW: 900
                property real tearH: 600
                property string tearAddr: ""
                // the real window: once its preview (pulled out of the Dock) has grown to the window's size, the real window
                // takes over under the pointer and follows it (like Super + drag) until the button is let go; a still copy
                // fades away where it used to be
                property bool following: false
                property bool oldVisible: false
                NumberAnimation { id: ghostFade; target: tearGhost; property: "opacity"; to: 0; duration: 180; easing.type: Easing.OutCubic }
                onTearXChanged: if (following) Qt.callLater(moveReal)
                onTearYChanged: {
                    if (following) Qt.callLater(moveReal);
                    else if (tearing && tearAddr && tearGhost.liftRaw >= 1) handoff();
                }
                function wsel() { return 'window = "address:' + tearAddr + '"'; }
                function realPos() {
                    return { x: Math.round(win.modelData.x + tearX - tearW / 2),
                             y: Math.round(win.modelData.y + tearGhost.offY + tearY - tearH * 0.035) };
                }
                function moveReal() {
                    if (!following || !tearAddr) return;
                    var p = realPos();
                    Hyprland.dispatch('hl.dsp.window.move({ x = ' + p.x + ', y = ' + p.y + ', "exact", ' + wsel() + ' })');
                }
                function handoff() {
                    if (following || !tearAddr) return;
                    following = true;
                    var mon = Hyprland.monitorFor(win.modelData);
                    var ws = (mon && mon.activeWorkspace) ? String(mon.activeWorkspace.name) : "";
                    var p = realPos(), sel = wsel();
                    if (ws) Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + ws + '", follow = false, ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.fullscreen_state({ internal = 0, client = 0, ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "1", ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.resize({ x = ' + Math.round(tearW) + ', y = ' + Math.round(tearH) + ', "exact", ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.move({ x = ' + p.x + ', y = ' + p.y + ', "exact", ' + sel + ' })');
                    if (tearItem && tearItem.tl) tearItem.tl.activate();
                    if (oldVisible) { oldSnap.scale = 1; oldSnap.opacity = 1; oldSnap.shown = true; oldOut.restart(); }
                    // the real window appears exactly where its preview is, the preview fades off it
                    ghostFade.restart();
                }
                function finishFollow() {
                    following = false;
                    tearing = false;
                    if (tearAddr) Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "0", ' + wsel() + ' })');
                    tearAddr = "";
                    if (!ghostFade.running) tearItem = null;
                    else ghostFade.finished.connect(function () { if (!ui.tearing) ui.tearItem = null; });
                }
                function hyprOf(tl) {
                    var v = Hyprland.toplevels.values;
                    for (var i = 0; i < v.length; i++) if (v[i].wayland === tl) return v[i];
                    return null;
                }
                function beginTear(item, src, homeX, homeY) {
                    if (dragging) { dragTarget = dragIndex; endDrag(); }
                    menuItem = null;
                    tearItem = item; tearSrc = src; tearHomeX = homeX; tearHomeY = homeY;
                    tearGhost.opacity = 1; tearGhost.zoom = 1;
                    following = false; ghostFade.stop();
                    tearAddr = "";
                    if (item.kind === "win") {
                        var h = hyprOf(item.tl), o = h ? h.lastIpcObject : null;
                        tearAddr = h ? ("0x" + h.address.replace(/^0x/, "")) : "";
                        var sw = win.modelData.width, sh = win.modelData.height;
                        var w = (o && o.size) ? o.size[0] : (gsv.implicitWidth || 900);
                        var hh = (o && o.size) ? o.size[1] : (gsv.implicitHeight || 600);
                        // a fullscreen / huge window comes off as a comfortable floating size, like macOS restoring it
                        var k = Math.min(1, (sw * 0.78) / w, (sh * 0.78) / hh);
                        tearW = Math.round(w * k); tearH = Math.round(hh * k);
                        // where it is now: if that's on screen here, a still copy will stand in for it at the hand-off
                        var mon0 = Hyprland.monitorFor(win.modelData);
                        oldSnap.shown = false; oldOut.stop();
                        oldVisible = !!(o && o.at && o.workspace && mon0 && mon0.activeWorkspace && o.workspace.id === mon0.activeWorkspace.id);
                        if (oldVisible) {
                            oldSnap.x = o.at[0] - win.modelData.x; oldSnap.y = o.at[1] - win.modelData.y;
                            oldSnap.width = o.size[0]; oldSnap.height = o.size[1];
                            oldSv.captureSource = item.tl;          // one still frame (live: false)
                        }
                    }
                    tearing = true;
                }
                function endTear() {
                    if (!tearing) return;
                    // a window: let go wherever the pointer is — it simply stays there
                    if (tearAddr && (following || tearY < activeTop - 30)) {
                        if (!following) handoff();
                        finishFollow();
                        justDragged = true;
                        Qt.callLater(function () { ui.justDragged = false; });
                        return;
                    }
                    tearing = false;
                    justDragged = true;
                    Qt.callLater(function () { ui.justDragged = false; });
                    if (tearY < activeTop - 30) {
                        tearLaunch.item = tearItem;
                        tearLaunch.restart();               // enlarge + fade, then open / focus
                    } else {
                        // back on the Dock: the preview flies home and the window fades back in where it was
                        tearHome.restart();                 // back to its place
                    }
                }

                function pinnedCount() {
                    var n = 0;
                    for (var i = 0; i < root.items.length; i++) {
                        var it = root.items[i];
                        if (it.kind === "app" && it.pinned && !it.special) n++;
                        else break;
                    }
                    return n;
                }
                function naturalCenter(i) {
                    var c = rep.itemAt(i);
                    return c ? row.mapToItem(ui, c.x + c.width / 2, 0).x : 0;
                }
                function beginDrag(index, key, pressX, shiftW) {
                    menuItem = null;
                    dragIndex = index;
                    dragTarget = index;
                    dragKey = key;
                    dragPressX = pressX;
                    dragDelta = 0;
                    dragShiftW = shiftW;
                    dragging = true;
                }
                function dragUpdate(absX) {
                    dragDelta = absX - dragPressX;
                    var center = naturalCenter(dragIndex) + dragDelta;
                    var P = pinnedCount(), t = 0;
                    for (var j = 0; j < P; j++) {
                        if (j === dragIndex) continue;
                        if (naturalCenter(j) < center) t++;
                    }
                    dragTarget = t;
                }
                function shiftFor(i) {
                    if (dragIndex < i && i <= dragTarget) return -dragShiftW;
                    if (dragTarget <= i && i < dragIndex) return dragShiftW;
                    return 0;
                }
                function endDrag() {
                    var from = dragIndex, to = dragTarget;
                    dragging = false;
                    dragKey = "";
                    dragIndex = -1;
                    dragTarget = -1;
                    dragDelta = 0;
                    justDragged = true;
                    Qt.callLater(function () { ui.justDragged = false; });
                    if (to !== from) root.reorderPinned(from, to);
                }

                SequentialAnimation {
                    id: tearLaunch
                    property var item: null
                    ParallelAnimation {
                        NumberAnimation { target: tearGhost; property: "zoom"; to: tearGhost.isWin ? 2.0 : 2.6; duration: 460; easing.type: Easing.OutQuint }
                        NumberAnimation { target: tearGhost; property: "opacity"; to: 0; duration: 460; easing.type: Easing.OutCubic }
                        NumberAnimation { target: tearGhost; property: "wob"; to: 0; duration: 200 }
                    }
                    ScriptAction { script: { if (tearLaunch.item) root.activate(tearLaunch.item, false); ui.tearItem = null; } }
                }
                ParallelAnimation {
                    id: tearHome
                    NumberAnimation { target: ui; property: "tearX"; to: ui.tearHomeX; duration: 420; easing.type: Easing.OutQuint }
                    NumberAnimation { target: ui; property: "tearY"; to: ui.tearHomeY; duration: 420; easing.type: Easing.OutQuint }
                    NumberAnimation { target: tearGhost; property: "wob"; to: 0; duration: 200 }
                    onFinished: { ui.tearItem = null; ui.tearAddr = ""; }
                }

                readonly property bool tucked: wantsHide && !revealed && !menuOpen && !dragging && !tearing
                readonly property real refLeft: (width - root.totalW0) / 2
                readonly property real activeTop: height - root.margin - root.bgHeight
                                                  - root.iconSize * (root.effMag - 1) - 12
                readonly property bool active: dragging || (hh.hovered && hh.point.position.y > activeTop && !tucked)
                property real strength: active ? 1 : 0
                Behavior on strength { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                HoverHandler {
                    id: hh
                    onPointChanged: if (hovered && !ui.dragging) ui.mx = point.position.x
                    onHoveredChanged: {
                        if (hovered) { hideTimer.stop(); ui.revealed = true; }
                        else hideTimer.restart();
                    }
                }
                Timer { id: hideTimer; interval: root.hideDelay; onTriggered: if (!ui.dragging) ui.revealed = false }

                // ── Liquid Glass backdrop: wallpaper + the live windows behind the Dock, in screen coordinates ──
                // Built from per-window captures (not a screen capture) so the Dock never ends up refracting itself.
                Loader {
                    id: glassBackdrop
                    active: root.liquidActive
                    sourceComponent: Item {
                        id: bd
                        x: 0
                        y: -(win.modelData.height - ui.height)
                        width: win.modelData.width
                        height: win.modelData.height

                        Loader {
                            anchors.fill: parent
                            z: 10000
                            active: Corners.LaunchpadGlassState.covers(win.modelData.name)
                            sourceComponent: Corners.LaunchpadBackground { screenName: win.modelData.name }
                        }
                        // placeholder until a wallpaper loads: deliberately colourful so a missing wallpaper is obvious
                        Corners.ContinuousRectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#2f6bff" }
                                GradientStop { position: 0.5; color: "#b44cff" }
                                GradientStop { position: 1.0; color: "#ff8a3d" }
                            }
                        }
                        Image {
                            anchors.fill: parent
                            visible: status === Image.Ready
                            onStatusChanged: console.log("[macdock-glass] wallpaper image status:", status, "(1 = ready, 2 = loading, 3 = error)", source)
                            source: root.fileUrl(root.wallpaperFor(win.modelData.name))
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: bd.width
                            smooth: true
                        }

                        ListModel { id: wm }
                        Repeater {
                            model: wm
                            delegate: Item {
                                id: gw
                                required property string addr
                                required property real wx
                                required property real wy
                                required property real ww
                                required property real wh
                                required property real wz
                                required property bool gone      // window closed: capture is released first, the item is swept shortly after
                                x: wx; y: wy; width: ww; height: wh; z: wz
                                readonly property var tl: { if (!root.hub || gone) return null; var t = root.hub.tlTick; return root.hub.tlFor(addr); }
                                // only keep capturing windows that actually reach the Dock (+ refraction margin)
                                // real-time: EVERY visible window stays captured (also while the Dock is tucked and for windows far from the Dock), so a window
                                // dragged over the Dock or a revealed Dock never starts from the bare wallpaper
                                readonly property bool nearNow: root.glassRT || (!ui.tucked
                                    && x < dock.x + dock.width + 48 && x + width > dock.x - 48
                                    && y < dock.y + bd.height - ui.height + dock.height + 48
                                    && y + height > dock.y + bd.height - ui.height - 48)
                                // a capture is only torn down 2.5 s after the window left the dock area: creating / destroying
                                // live window captures every time a window brushes past the dock is what the compositor can choke on
                                property bool near: false
                                onNearNowChanged: { if (nearNow) { nearHold.stop(); near = true; } else nearHold.restart(); }
                                Component.onCompleted: near = nearNow
                                Timer { id: nearHold; interval: 2500; onTriggered: gw.near = gw.nearNow }
                                Loader {
                                    anchors.fill: parent
                                    active: gw.near && !gw.gone
                                    sourceComponent: ScreencopyView {
                                        id: sc
                                        captureSource: gw.tl
                                        // 15 fps, not the window's own rate: the glass only shows a blurred, refracted copy, and
                                        // copying every frame of a busy window (a terminal, a video) cost several % CPU
                                        live: false
                                        readonly property bool wantFrames: !root.glassHold && (root.glassRT || !ui.tucked)
                                        Timer {
                                            interval: 66; repeat: true
                                            running: sc.wantFrames && sc.captureSource !== null
                                            onTriggered: if (typeof sc.captureFrame === "function") sc.captureFrame()
                                        }
                                        onCaptureSourceChanged: { if (captureSource !== null && !root.glassHold) firstShot.restart(); }
                                        Timer {
                                            id: firstShot
                                            interval: 90
                                            onTriggered: { if (sc.captureSource !== null && !sc.live && !root.glassHold && typeof sc.captureFrame === "function") sc.captureFrame(); }
                                        }
                                    }
                                }
                            }
                        }

                        function sync() {
                            var mon = null;
                            for (var i = 0; i < root.monData.length; i++)
                                if (root.monData[i].name === win.modelData.name) mon = root.monData[i];
                            if (!mon) return;
                            var ws = [mon.activeWorkspace ? mon.activeWorkspace.id : -999];
                            if (mon.specialWorkspace && mon.specialWorkspace.id !== 0) ws.push(mon.specialWorkspace.id);
                            var zoneTop = bd.height - win.height;
                            var want = {};
                            var cs = root.glassClients;
                            for (var c = 0; c < cs.length; c++) {
                                var cl = cs[c];
                                if (!cl.mapped || cl.hidden || cl.monitor !== mon.id || ws.indexOf(cl.workspace.id) < 0) continue;
                                var x = cl.at[0] - mon.x, y = cl.at[1] - mon.y, w = cl.size[0], h = cl.size[1];
                                if (x + w <= 0 || x >= bd.width || y + h <= zoneTop || y >= bd.height) continue;
                                var z = cl.floating ? 100 - Math.min(cl.focusHistoryID, 90) : 0;   // floating on top, most recently focused highest
                                want[cl.address] = { addr: cl.address, wx: x, wy: y, ww: w, wh: h, wz: z, gone: false };
                            }
                            for (var j = wm.count - 1; j >= 0; j--) {
                                var a = wm.get(j).addr;
                                if (want[a] === undefined) { if (!wm.get(j).gone) { wm.setProperty(j, "gone", true); sweep.restart(); } }
                                else { wm.set(j, want[a]); delete want[a]; }
                            }
                            for (var k in want) wm.append(want[k]);
                            bd.lastCount = wm.count;
                        }
                        Timer {
                            id: sweep
                            interval: 600
                            onTriggered: { for (var q = wm.count - 1; q >= 0; q--) if (wm.get(q).gone) wm.remove(q); bd.lastCount = wm.count; }
                        }
                        property int lastCount: -1
                        Connections {
                            target: root
                            function onGlassClientsChanged() { bd.sync(); }
                            function onMonDataChanged() { bd.sync(); }
                        }
                        Component.onCompleted: sync()
                    }
                }

                Item {
                    id: maskItem
                    x: ui.menuOpen ? 0 : dock.x
                    width: ui.menuOpen ? ui.width : dock.width
                    y: ui.menuOpen ? 0 : (ui.tucked ? ui.height - 3 : (hh.hovered ? ui.activeTop : dock.y))
                    height: ui.height - y
                }

                Item {
                    id: dock
                    width: row.width + root.hPad * 2
                    height: root.bgHeight
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: ui.height - root.margin - height + (ui.tucked ? height + root.margin + 6 : 0)
                    Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                    // ── Apple Liquid Glass: real-time refraction of the backdrop (see liquidglass.frag) ──
                    Loader {
                        id: glassLayer
                        anchors.fill: parent
                        active: root.liquidActive
                        sourceComponent: Item {
                            id: dg
                            // blurring at half resolution is visually identical for radii >= 8 px and costs a quarter of the GPU work
                            readonly property real ds: root.materialBlur >= 8 ? 0.5 : 1.0
                            readonly property real bn: root.materialBlur * 1.4 * ds / 64.0
                            readonly property real margin: 72      // extra backdrop captured around the Dock (refraction + blur reach)
                            readonly property real padPx: 10       // shader item padding (drop shadow)
                            ShaderEffectSource {
                                id: bsrc
                                sourceItem: glassBackdrop.item
                                hideSource: true
                                live: !ui.tucked
                                visible: false
                                sourceRect: Qt.rect(dock.x - parent.padPx - parent.margin,
                                                    dock.y + (win.modelData.height - ui.height) - parent.padPx - parent.margin,
                                                    dock.width + 2 * (parent.padPx + parent.margin),
                                                    dock.height + 2 * (parent.padPx + parent.margin))
                                textureSize: Qt.size(Math.max(1, Math.round(sourceRect.width * dg.ds)), Math.max(1, Math.round(sourceRect.height * dg.ds)))
                            }
                            MultiEffect {
                                id: bblurFx
                                source: bsrc
                                width: bsrc.sourceRect.width * dg.ds; height: bsrc.sourceRect.height * dg.ds
                                blurEnabled: true
                                blurMax: 64
                                blur: Math.min(1.0, dg.bn)
                                autoPaddingEnabled: false
                                visible: false
                            }
                            // real Gaussian pre-blur of the backdrop (Qt MultiEffect): the glass shader refracts THIS texture,
                            // so there are no sampled copies of the background any more
                            ShaderEffectSource {
                                id: bblur
                                sourceItem: bblurFx
                                live: !ui.tucked
                                visible: false
                            }
                            MultiEffect {
                                id: bblur2Fx
                                source: bblur
                                width: bsrc.sourceRect.width * dg.ds; height: bsrc.sourceRect.height * dg.ds
                                blurEnabled: dg.bn > 1.0
                                blurMax: 64
                                blur: Math.max(0.0, Math.min(1.0, dg.bn - 1.0))
                                autoPaddingEnabled: false
                                visible: false
                            }
                            // second Gaussian pass: only active when the slider goes past a single pass's 64 px limit
                            ShaderEffectSource {
                                id: bblur2
                                // the 2nd pass is a pure copy unless the blur radius exceeds one pass: skip it then (same pixels, one GPU pass less)
                                sourceItem: dg.bn > 1.0 ? bblur2Fx : null
                                live: !ui.tucked
                                visible: false
                            }
                            ShaderEffect {
                                id: glassFx
                                x: -padPx; y: -padPx
                                width: dock.width + 2 * padPx
                                height: dock.height + 2 * padPx
                                fragmentShader: root.glassShaderUrl
                                onStatusChanged: {
                                    console.log("[macdock-glass] shader status:", status, "(0 = compiled, 1 = uncompiled, 2 = error)", fragmentShader, log);
                                    if (status === ShaderEffect.Error) root.glassState = "failed";
                                }

                                property variant src: dg.bn > 1.0 ? bblur2 : bblur
                                property real padPx: parent.padPx
                                property vector2d itemSize: Qt.vector2d(width, height)
                                property vector2d glassSize: Qt.vector2d(dock.width, dock.height)
                                property vector2d srcSize: Qt.vector2d(bsrc.sourceRect.width, bsrc.sourceRect.height)
                                property vector2d srcOffset: Qt.vector2d(parent.margin, parent.margin)
                                property real pad: padPx
                                property real radius: root.cornerRadius
                                property real squircle: root.cornerSquircle
                                property real bezel: Math.min(dock.height * 0.36, 26)
                                property real thickness: 30 * root.glassLiquid
                                property real dispersion: 0.06 * root.glassLiquid
                                property real magnify: 0.08 * root.glassLiquid
                                property real rim: root.glassRim
                                property real grain: root.glassGrain
                                property real blurPx: 1.5            // tiny residual smoothing; the real blur is the MultiEffect pre-pass
                                property real tintMix: root.glassOpacity * 0.55
                                property real saturation: 1.25
                                property real dark: root.dockDark ? 1 : 0
                                property real debug: root.glassDebug ? 1 : 0
                                property real shadowAmt: 0
                                property real flatInner: 0
                                property real rimTint: 0
                                property real ringW: 0
                            }
                        }
                    }

                    // Normal Blur fallback: same continuous-corner silhouette as the glass shader.
                    // A Rectangle can only do circular radii, so the squircle is drawn as a path.
                    Shape {
                        id: dockFallback
                        visible: !root.liquidActive
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            fillColor: root.dockDark ? Qt.rgba(0.10, 0.10, 0.11, root.glassOpacity)
                                                     : Qt.rgba(1, 1, 1, root.glassOpacity * 0.55)
                            strokeColor: root.dockDark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.12)
                            strokeWidth: 1
                            PathPolyline {
                                path: root.squirclePoints(dockFallback.width, dockFallback.height,
                                                          root.cornerRadius, root.cornerSquircle, 0.5)
                            }
                        }

                        ShapePath {
                            fillColor: "transparent"
                            strokeColor: root.dockDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.45)
                            strokeWidth: 1
                            PathPolyline {
                                path: root.squirclePoints(dockFallback.width, dockFallback.height,
                                                          root.cornerRadius, root.cornerSquircle, 1.5)
                            }
                        }
                    }

                    Row {
                        id: row
                        spacing: root.spacing
                        height: root.iconSize
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: root.bottomPad

                        Repeater {
                            id: rep
                            model: dockModel

                            delegate: Item {
                                id: cell
                                required property string key
                                required property int index
                                readonly property var modelData: root.itemMap[key] || ({ kind: "sep", key: key, nA: 0, nS: 0 })
                                readonly property bool isSep: modelData.kind === "sep"
                                readonly property bool canDrag: !isSep && modelData.pinned === true && !modelData.special
                                readonly property bool torn: ui.tearing && ui.tearItem && !isSep && ui.tearItem.key === modelData.key
                                opacity: (torn ? 0.3 : (isDragged ? 0.92 : 1)) * (leavingCell ? appear : 1)
                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                readonly property bool isDragged: ui.dragging && modelData.key === ui.dragKey

                                // app cells always show their plain icon; only window cells show a live preview
                                // (with the app's icon as a badge), grouped next to the Trash
                                readonly property var thumbWin: (!isSep && modelData.kind === "win") ? modelData.tl : null
                                // the capture only restarts when the window itself changes — refreshed Dock data hands the cell
                                // the same window again, and re-binding it used to blank the live preview for ~2 s
                                property var heldTl: null
                                readonly property string winAddr: { if (!thumbWin) return ""; var h = ui.hyprOf(thumbWin); return h ? String(h.address).replace(/^0x/, "") : ""; }
                                readonly property bool closingWin: winAddr !== "" && root.hub && root.hub.closingWins[winAddr] === true
                                onThumbWinChanged: if (thumbWin !== heldTl) heldTl = thumbWin
                                readonly property bool useThumb: root.windowCapture && thumbWin !== null
                                // Minimized windows keep their live source. Use the saved
                                // minimize frame only until the compositor supplies pixels.
                                readonly property bool liveThumbReady: useThumb && (sv.hasContent === undefined || sv.hasContent === true)
                                readonly property bool snapshotReady: useThumb && !liveThumbReady && modelData.minimized === true && savedShot.status === Image.Ready
                                readonly property bool thumbReady: liveThumbReady || snapshotReady

                                property real dx: {
                                    if (!ui.dragging || isSep) return 0;
                                    if (isDragged) return ui.dragDelta;
                                    return ui.shiftFor(index);
                                }
                                Behavior on dx {
                                    enabled: !cell.isDragged
                                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                }
                                transform: Translate { x: cell.dx }
                                z: isDragged ? 100 : 0

                                readonly property bool leavingCell: modelData.leaving === true
                                property real appear: modelData.fresh ? 0 : 1
                                Behavior on appear { NumberAnimation { duration: cell.leavingCell ? root.leaveMs : 320; easing.type: cell.leavingCell ? Easing.InOutCubic : Easing.OutCubic } }
                                Component.onCompleted: { heldTl = thumbWin; Qt.callLater(function () { cell.appear = cell.leavingCell ? 0 : 1; if (typeof cell.bounceStep === "function") cell.bounceStep(); }); }
                                onLeavingCellChanged: appear = leavingCell ? 0 : 1
                                enabled: !leavingCell

                                readonly property real c0: modelData.nA * (root.iconSize + root.spacing)
                                                           + modelData.nS * (root.sepWidth + root.spacing)
                                                           + (isSep ? root.sepWidth : root.iconSize) / 2
                                readonly property real s: {
                                    if (isSep) return 1;
                                    var dist = Math.abs(ui.mx - ui.refLeft - cell.c0);
                                    var R = root.magRadius;
                                    var f = dist < R ? 0.5 * (1 + Math.cos(Math.PI * dist / R)) : 0;
                                    return 1 + (root.effMag - 1) * f * ui.strength;
                                }

                                width: isSep ? root.sepWidth * appear : root.iconSize * s * appear
                                height: root.iconSize

                                Corners.ContinuousRectangle {
                                    visible: cell.isSep
                                    width: 1
                                    height: root.iconSize * 0.85
                                    anchors.centerIn: parent
                                    color: root.dockDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.22)
                                }

                                Image {
                                    id: img
                                    visible: !cell.isSep && !cell.thumbReady
                                    opacity: ma.pressed ? 0.65 : 1
                                    property real lift: 0
                                    width: root.iconSize * cell.s * cell.appear
                                    height: width
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: lift
                                    source: cell.isSep ? "" : root.cellIconSrc(cell.modelData)
                                    sourceSize: Qt.size(Math.ceil(root.iconSize * root.magnification * 1.25),
                                                        Math.ceil(root.iconSize * root.magnification * 1.25))
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    asynchronous: true
                                    // Default stays on the native renderer; other appearances
                                    // share one fixed-size material pass across shell surfaces.
                                    layer.enabled: Corners.IconStyle.effectMode !== 0 && img.visible
                                    layer.textureSize: img.sourceSize
                                    layer.smooth: true
                                    layer.effect: Corners.IconStyleEffect {}
                                }

                                // ── window thumbnail (same box as the icon, so magnification just works) ──
                                Item {
                                    id: th
                                    anchors.fill: img
                                    // kept (almost) opaque while loading so the capture isn't paused by the renderer
                                    visible: cell.useThumb
                                    opacity: cell.thumbReady ? 1 : 0.01

                                    Image {
                                        id: savedShot
                                        anchors.fill: parent
                                        source: cell.modelData.shot ? root.fileUrl(cell.modelData.shot) : ""
                                        visible: cell.snapshotReady
                                        fillMode: Image.PreserveAspectFit; asynchronous: true; cache: false
                                    }
                                    ScreencopyView {
                                        visible: cell.useThumb
                                        opacity: cell.liveThumbReady ? 1 : 0.01
                                        id: sv
                                        anchors.centerIn: parent
                                        captureSource: root.windowCapture ? cell.heldTl : null
                                        // live only while the pointer is on the Dock (where you look at them); otherwise one fresh
                                        // frame every 2 s — live previews of every window were ~8% CPU at idle
                                        live: !ui.tucked && !root.previewHold && !cell.closingWin && hh.hovered
                                        Timer {
                                            interval: 2000; repeat: true; triggeredOnStart: true
                                            running: !sv.live && !ui.tucked && !root.previewHold && !cell.closingWin && sv.captureSource !== null
                                            onTriggered: if (typeof sv.captureFrame === "function") sv.captureFrame()
                                        }
                                        readonly property real ar: (implicitWidth > 0 && implicitHeight > 0)
                                                                   ? implicitWidth / implicitHeight : 4 / 3
                                        width: Math.min(th.width, th.height * ar)
                                        height: width / ar
                                    }
                                    Corners.ContinuousRectangle {      // thin frame + pressed dimming
                                        anchors.fill: sv
                                        radius: 3
                                        color: ma.pressed ? Qt.rgba(0, 0, 0, 0.3) : "transparent"
                                        border.width: 1
                                        border.color: root.dockDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.28)
                                    }
                                }
                                // small app icon in the corner, so you can tell which app the window belongs to
                                Image {
                                    id: badge
                                    visible: cell.thumbReady
                                    width: img.width * 0.46
                                    height: width
                                    x: img.x + img.width - width + 3
                                    y: img.y + img.height - height + 3
                                    source: img.source
                                    sourceSize: Qt.size(Math.ceil(root.iconSize * root.magnification * 0.6),
                                                        Math.ceil(root.iconSize * root.magnification * 0.6))
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }

                                Corners.ContinuousRectangle {
                                    visible: !cell.isSep && cell.modelData.running && root.showIndicators
                                    width: 4; height: 4; radius: 2
                                    color: root.dockDark ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(0, 0, 0, 0.6)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: cell.height + 3
                                }

                                // ── launch bounce ──
                                // Bounces while the app launches. When the app opens, the bounce in progress finishes its landing, then a
                                // couple of smaller bounces settle it back onto the Dock. Nothing plays while the Dock is tucked away.
                                readonly property bool wantBounce: !cell.isSep && root.bounceOnLaunch && root.launching[cell.modelData.key] !== undefined
                                property bool bounceShown: false          // a bounce was actually visible, so it deserves a settle
                                function bounceStep() {
                                    if (ui.tucked) return;
                                    if (cell.wantBounce) { cell.bounceShown = true; if (!bounceAnim.running && !settleAnim.running) bounceAnim.start(); }
                                    else if (cell.bounceShown && !bounceAnim.running && !settleAnim.running) { cell.bounceShown = false; settleAnim.start(); }
                                }
                                onWantBounceChanged: bounceStep()
                                Connections {
                                    target: ui
                                    function onTuckedChanged() {
                                        if (ui.tucked) {                       // dock slid away: drop the bounce, it must not poke out
                                            bounceAnim.stop(); settleAnim.stop(); img.lift = 0; cell.bounceShown = false;
                                        } else cell.bounceStep();
                                    }
                                }
                                SequentialAnimation {
                                    id: bounceAnim
                                    NumberAnimation { target: img; property: "lift"; to: root.iconSize * 0.42
                                                      duration: 280; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: img; property: "lift"; to: 0
                                                      duration: 280; easing.type: Easing.InCubic }
                                    onFinished: cell.bounceStep()              // goes again while still launching, otherwise settles
                                }
                                SequentialAnimation {
                                    id: settleAnim
                                    NumberAnimation { target: img; property: "lift"; to: root.iconSize * 0.16
                                                      duration: 170; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: img; property: "lift"; to: 0
                                                      duration: 170; easing.type: Easing.InQuad }
                                    NumberAnimation { target: img; property: "lift"; to: root.iconSize * 0.06
                                                      duration: 120; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: img; property: "lift"; to: 0
                                                      duration: 120; easing.type: Easing.InQuad }
                                    onFinished: cell.bounceStep()              // relaunched while settling: bounce again
                                }

                                DockTooltip {
                                    id: tip
                                    visible: opacity > 0
                                    opacity: (root.showLabels && !cell.isSep && ma.containsMouse && !ma.pressed && !ui.menuOpen && !ui.dragging && !ui.tearing && !ui.tucked) ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    z: 10
                                    maxWidth: Math.min(360, ui.width - 24)
                                    // Clamp long window titles to the screen; the tail still points at the icon.
                                    readonly property real cellLeft: dock.x + row.x + cell.x + cell.dx
                                    x: Math.max(12 - cellLeft, Math.min(ui.width - width - 12 - cellLeft, (cell.width - width) / 2))
                                    pointerX: cell.width / 2 - x
                                    y: cell.height - img.height - img.lift - height - 10
                                    text: cell.isSep ? "" : ((cell.modelData.kind === "win" && cell.modelData.tl && cell.modelData.tl.title) ? cell.modelData.tl.title : cell.modelData.name)
                                    fontFamily: root.fontFamily
                                    liquid: root.liquidActive
                                    dark: root.dockDark
                                    surfaceOpacity: root.glassOpacity
                                    glassBlur: root.glassBlur
                                    glassLiquid: root.glassLiquid
                                    glassRim: root.glassRim
                                    glassGrain: root.glassGrain
                                    backdrop: glassBackdrop.item
                                    backdropOrigin: {
                                        // Explicit dependencies keep captures aligned during magnification and bounce.
                                        cellLeft; row.y; dock.y; tip.x; tip.y;
                                        const p = tip.mapToItem(ui, 0, 0);
                                        return Qt.point(p.x, p.y + win.modelData.height - ui.height);
                                    }
                                }

                                MouseArea {
                                    id: ma
                                    visible: !cell.isSep
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: -root.bottomPad
                                    width: cell.width
                                    height: img.height + root.bottomPad
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                    property real pressX: 0

                                    property real pressY: 0
                                    onPressed: mouse => {
                                        if (mouse.button === Qt.LeftButton) {
                                            var pp = ma.mapToItem(ui, mouse.x, mouse.y);
                                            pressX = pp.x; pressY = pp.y;
                                        }
                                    }
                                    onPositionChanged: mouse => {
                                        if (!(pressedButtons & Qt.LeftButton) || cell.isSep) return;
                                        var ap = ma.mapToItem(ui, mouse.x, mouse.y);
                                        // pulled up out of the Dock → tear the icon off (any app icon, pinned or running)
                                        if (ui.tearing) { ui.tearX = ap.x; ui.tearY = ap.y; return; }
                                        if (pressY - ap.y > 56 && (cell.modelData.kind === "app" || cell.modelData.kind === "win") && !cell.modelData.special) {
                                            var home = img.mapToItem(ui, img.width / 2, img.height / 2);
                                            ui.tearX = ap.x; ui.tearY = ap.y;
                                            ui.beginTear(cell.modelData, root.cellIconSrc(cell.modelData), home.x, home.y);
                                            return;
                                        }
                                        if (!cell.canDrag) return;
                                        var ax = ap.x;
                                        if (!ui.dragging) {
                                            if (Math.abs(ax - pressX) < 8) return;
                                            ui.beginDrag(cell.index, cell.modelData.key, pressX, cell.width + root.spacing);
                                        }
                                        if (cell.isDragged) ui.dragUpdate(ax);
                                    }
                                    onReleased: mouse => {
                                        if (ui.tearing) { ui.endTear(); return; }
                                        if (ui.dragging && cell.isDragged) ui.endDrag();
                                    }
                                    onClicked: mouse => {
                                        if (ui.justDragged) return;
                                        if (mouse.button === Qt.RightButton) {
                                            ui.menuCx = cell.mapToItem(ui, cell.width / 2, 0).x;
                                            ui.menuModel = root.menuFor(cell.modelData);
                                            ui.menuItem = cell.modelData;
                                        } else {
                                            root.activate(cell.modelData, mouse.button === Qt.MiddleButton);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: 50
                    visible: ui.menuOpen
                    enabled: ui.menuOpen
                    acceptedButtons: Qt.AllButtons
                    onPressed: ui.menuItem = null
                }

                Item {
                    id: menu
                    z: 60
                    visible: opacity > 0
                    opacity: ui.menuOpen ? 1 : 0
                    scale: ui.menuOpen ? 1 : 0.96
                    transformOrigin: Item.Bottom
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    width: 230
                    // The slab is the menu body plus a small rounded tail at the
                    // bottom (like the Dock tooltip), pointing at the Dock.
                    readonly property real menuRadius: Corners.CornerTheme.menuRadius
                    readonly property real tailHeight: 7
                    readonly property real tailHalfWidth: 9
                    readonly property real bodyHeight: menuCol.height + 2 * Corners.CornerTheme.menuInset
                    height: bodyHeight + tailHeight
                    x: Math.max(8, Math.min(ui.width - width - 8, ui.menuCx - width / 2))
                    y: ui.height - root.margin - root.bgHeight - root.iconSize * (root.effMag - 1) - 6 - height

                    // one-piece glass outline: rounded-rect body + rounded tail
                    // (same curve recipe as DockTooltip, rectangular body flavour)
                    function outline(inset) {
                        return Curve.tailPath(width,bodyHeight,menuRadius,tailHeight,width/2,tailHalfWidth,Corners.CornerTheme.smoothing,inset);
                    }

                    // Normal Blur / flat fallback: the same one-piece outline
                    // (body + tail), tinted with the Dock's own scheme so the
                    // menu follows the Dock style (light/dark, opacity).
                    Shape {
                        anchors.fill: parent
                        visible: !root.liquidActive
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: root.dockDark ? Qt.rgba(0.10, 0.10, 0.11, root.glassOpacity)
                                                     : Qt.rgba(1, 1, 1, root.glassOpacity * 0.55)
                            strokeWidth: 1
                            strokeColor: root.dockDark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.12)
                            PathSvg { path: menu.outline(0.5) }
                        }
                        ShapePath {
                            fillColor: "transparent"
                            strokeWidth: 1
                            strokeColor: root.dockDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.45)
                            PathSvg { path: menu.outline(1.5) }
                        }
                    }

                    // ── Apple Liquid Glass slab for the menu — the same pipeline
                    // as the Dock slab above (backdrop capture → Gaussian
                    // pre-blur → liquidglass.frag), framed on the menu geometry.
                    Corners.ActivityLoader {
                        id: menuGlass
                        anchors.fill: parent
                        requested: root.liquidActive && menu.visible
                        sourceComponent: Item {
                            id: mg
                            // blurring at half resolution is visually identical for radii >= 8 px and costs a quarter of the GPU work
                            readonly property real ds: root.materialBlur >= 8 ? 0.5 : 1.0
                            readonly property real bn: root.materialBlur * 1.4 * ds / 64.0
                            readonly property real margin: 72      // extra backdrop captured around the menu (refraction + blur reach)
                            readonly property real padPx: 10       // shader item padding (drop shadow)
                            ShaderEffectSource {
                                id: msrc
                                sourceItem: glassBackdrop.item
                                hideSource: true
                                live: ui.menuOpen
                                visible: false
                                sourceRect: Qt.rect(menu.x - mg.padPx - mg.margin,
                                                    menu.y + (win.modelData.height - ui.height) - mg.padPx - mg.margin,
                                                    menu.width + 2 * (mg.padPx + mg.margin),
                                                    menu.height + 2 * (mg.padPx + mg.margin))
                                textureSize: Qt.size(Math.max(1, Math.round(msrc.sourceRect.width * mg.ds)),
                                                     Math.max(1, Math.round(msrc.sourceRect.height * mg.ds)))
                            }
                            MultiEffect {
                                id: mblurFx
                                source: msrc
                                width: msrc.sourceRect.width * mg.ds; height: msrc.sourceRect.height * mg.ds
                                blurEnabled: true
                                blurMax: 64
                                blur: Math.min(1.0, mg.bn)
                                autoPaddingEnabled: false
                                visible: false
                            }
                            ShaderEffectSource {
                                id: mblur
                                sourceItem: mblurFx
                                live: ui.menuOpen
                                visible: false
                            }
                            MultiEffect {
                                id: mblur2Fx
                                source: mblur
                                width: msrc.sourceRect.width * mg.ds; height: msrc.sourceRect.height * mg.ds
                                blurEnabled: mg.bn > 1.0
                                blurMax: 64
                                blur: Math.max(0.0, Math.min(1.0, mg.bn - 1.0))
                                autoPaddingEnabled: false
                                visible: false
                            }
                            ShaderEffectSource {
                                id: mblur2
                                sourceItem: mg.bn > 1.0 ? mblur2Fx : null
                                live: ui.menuOpen
                                visible: false
                            }
                            ShaderEffect {
                                id: menuGlassFx
                                x: -mg.padPx; y: -mg.padPx
                                width: menu.width + 2 * mg.padPx
                                height: menu.height + 2 * mg.padPx
                                // dedicated menu variant of the tooltip shader:
                                // rounded-rect body (radius uniform) + rounded
                                // tail instead of the capsule silhouette
                                fragmentShader: Qt.resolvedUrl("dockmenu-light-milk-v1.frag.qsb")
                                onStatusChanged: {
                                    console.log("[macdock-glass] menu shader status:", status, "(0 = compiled, 1 = uncompiled, 2 = error)", log);
                                    if (status === ShaderEffect.Error) root.glassState = "failed";
                                }

                                property variant src: mg.bn > 1.0 ? mblur2 : mblur
                                property real padPx: mg.padPx
                                property vector2d itemSize: Qt.vector2d(width, height)
                                property vector2d glassSize: Qt.vector2d(menu.width, menu.height)
                                property vector2d srcSize: Qt.vector2d(msrc.sourceRect.width, msrc.sourceRect.height)
                                property vector2d srcOffset: Qt.vector2d(mg.margin, mg.margin)
                                property real pad: mg.padPx
                                property real radius: menu.menuRadius
                                property real squircle: Corners.CornerTheme.smoothing
                                property real bezel: Math.min(menu.bodyHeight * 0.36, 26)
                                property real thickness: 30 * root.glassLiquid
                                property real dispersion: 0.06 * root.glassLiquid
                                property real magnify: 0.08 * root.glassLiquid
                                property real rim: root.glassRim
                                property real grain: root.glassGrain
                                property real blurPx: 1.5           // tiny residual smoothing; the real blur is the MultiEffect pre-pass
                                property real tintMix: root.glassOpacity * 0.55
                                property real saturation: 1.25
                                property real dark: root.dockDark ? 1 : 0  // glass tint follows the Dock theme (light/dark)
                                property real debug: root.glassDebug ? 1 : 0
                                // no drop shadow: like the Dock slab and tooltips, the
                                // glass gets its depth from the rim + refraction, not
                                // from a dark halo behind it
                                property real shadowAmt: 0
                                property real rimTint: 0
                                property real ringW: 0
                                property real flatInner: 0
                                // the tail: bottom of the slab, under the clicked icon
                                // (menu is centred on the icon, so this lands at the menu's centre —
                                // when the menu is clamped near a screen edge it follows the icon instead)
                                property real bodyHeight: menu.bodyHeight
                                property real tailHeight: menu.tailHeight
                                property real tailWidth: menu.tailHalfWidth
                                property real tailX: Math.max(menu.tailHalfWidth + 15,
                                    Math.min(menu.width - menu.tailHalfWidth - 15, ui.menuCx - menu.x))
                            }
                        }
                    }

                    Column {
                        id: menuCol
                        x: Corners.CornerTheme.menuInset
                        y: x
                        width: parent.width - 2 * x

                        Repeater {
                            model: ui.menuModel

                            delegate: Item {
                                id: mi
                                required property var modelData
                                readonly property bool isSep: modelData.kind === "sep"
                                readonly property bool off: !isSep && modelData.disabled === true
                                readonly property bool armedNow: !isSep && modelData.confirm === true && ui.armed === modelData.label
                                width: menuCol.width
                                height: isSep ? 9 : 26

                                Corners.ContinuousRectangle {
                                    visible: mi.isSep
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 6
                                    width: parent.width - 12
                                    height: 1
                                    color: root.dockDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.14)
                                }
                                Corners.MenuHighlight {
                                    visible: !mi.isSep && !mi.off && mia.containsMouse
                                    anchors.fill: parent
                                    panelRadius: menu.menuRadius
                                    color: mi.armedNow ? "#FF453A" : root.accent
                                }
                                Text {
                                    visible: !mi.isSep
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 20
                                    elide: Text.ElideRight
                                    text: mi.isSep ? "" : (mi.armedNow ? "Click again to confirm" : mi.modelData.label)
                                    // rows with an accent fill always get white text;
                                    // otherwise the text follows the Dock theme (white on dark glass, ink on light glass)
                                    color: !mi.off && mia.containsMouse ? "white"
                                          : mi.off ? (root.dockDark ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(0, 0, 0, 0.35))
                                          : (root.dockDark ? "white" : "#1d1d1f")
                                    font.pixelSize: 13
                                    font.family: root.fontFamily
                                }
                                MouseArea {
                                    id: mia
                                    anchors.fill: parent
                                    enabled: !mi.isSep && !mi.off
                                    hoverEnabled: true
                                    onContainsMouseChanged: if (!containsMouse && ui.armed === mi.modelData.label) ui.armed = ""
                                    onClicked: {
                                        if (mi.modelData.confirm === true && ui.armed !== mi.modelData.label) { ui.armed = mi.modelData.label; return; }
                                        var run = mi.modelData.run;
                                        ui.menuItem = null;
                                        if (run) run();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
