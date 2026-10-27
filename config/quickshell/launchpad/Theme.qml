pragma Singleton

import "Common" as Corners
import QtQuick
import Quickshell
import Quickshell.Io

// ─────────────────────────────────────────────────────────────────────────────
//  Theme — every number, colour and duration of the Launchpad lives here.
//
//  Everything is derived from ONE knob: iconSize. The ratios are the ones
//  measured off the macOS reference (1134 x 736 logical, icon 62.5 px,
//  pitch 108 px). Change iconSize and the whole layout follows.
//
//  Optional user config: ~/.config/quickshell/launchpad/config.json
// ─────────────────────────────────────────────────────────────────────────────
Scope {
    id: theme

    // Shared Appearance accent, saved by MacShell System Settings.
    readonly property color accent: Corners.ThemeColors.accentFor("launchpad")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    property bool darkMode: true
    property bool appearanceLoaded: false
    Binding { target: Corners.IconStyle; property: "systemDark"; value: theme.darkMode }
    function applyAppearance(appearance) {
        if (!appearance || typeof appearance !== "object" || Array.isArray(appearance)) return false;
        if (appearance.appearanceMode === "light" || appearance.appearanceMode === "dark")
            theme.darkMode = appearance.appearanceMode === "dark";
        else if (typeof appearance.darkMode === "boolean")
            theme.darkMode = appearance.darkMode;
        else return false;
        return true;
    }
    FileView {
        // Compatibility fallback until the main Appearance settings load.
        path: theme.configHome + "/macdock/settings.json"
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (theme.appearanceLoaded) return;
            try {
                theme.applyAppearance(JSON.parse(text()));
            } catch (e) {
                // Retain the last valid appearance during partial writes.
            }
        }
    }

    property int configuredColumns: 8
    property int configuredRows: 5
    property real viewportWidth: 0
    property real viewportHeight: 0
    property string savedSettingsText: ""
    property bool reloadPreferencesBeforeSave: false
    property bool settingsSaving: false
    property string settingsError: ""
    property bool showDock: true
    property bool startAtLogin: true
    property bool resetSearch: true
    property real dropDelay: 400
    property real scrollDebounce: 260
    property real scrollThreshold: 60
    property real backgroundOpacity: 0.04
    property real backgroundBlur: 0.35
    property real folderBackgroundBlur: 1.0
    property string folderBackgroundStyle: "blur"
    property bool dissolveSingleItemFolders: false
    property bool closeAfterRemove: true
    property bool debugDrag: Quickshell.env("LAUNCHPAD_DEBUG_DRAG") === "1"
    property string backgroundType: "desktop"
    property string customImage: ""
    readonly property string tahoeWallpaper: Quickshell.env("HOME") + "/Pictures/Wallpapers/macos-tahoe-26-5120x2880-22674.jpg"
    readonly property var settingsDefaults: ({
        autoLayout: true, columns: 8, rows: 5, folderCols: 5, folderRows: 3,
        iconSize: 64, backgroundOpacity: 0.04, showDock: true, startAtLogin: true,
        resetSearch: true, animationsEnabled: true, dropDelay: 400,
        scrollDebounce: 260, scrollThreshold: 60, backgroundType: "desktop",
        backgroundBlur: 0.35, customImage: "",
        folderBackgroundBlur: 1.0, folderBackgroundStyle: "blur",
        dissolveSingleItemFolders: false, closeAfterRemove: true
    })
    function settingsSnapshot() {
        const out = {};
        for (const key of Object.keys(settingsDefaults)) out[key] = theme[key];
        out.columns = configuredColumns;
        out.rows = configuredRows;
        return out;
    }
    function normalizeSettings(values) {
        const out = settingsSnapshot();
        const ranges = {
            columns: [1, 20], rows: [1, 12], folderCols: [1, 8], folderRows: [1, 7],
            iconSize: [40, 112], backgroundOpacity: [0, 1], backgroundBlur: [0, 1], folderBackgroundBlur: [0, 1],
            dropDelay: [0, 3000], scrollDebounce: [0, 3000], scrollThreshold: [10, 200]
        };
        for (const key of Object.keys(settingsDefaults)) {
            const value = values[key];
            if (value === undefined) continue;
            if (ranges[key]) {
                if (typeof value !== "number" || !Number.isFinite(value)) continue;
                let n = Math.max(ranges[key][0], Math.min(ranges[key][1], value));
                out[key] = key === "backgroundOpacity" || key === "backgroundBlur" || key === "folderBackgroundBlur" ? n : Math.round(n);
            } else if (typeof settingsDefaults[key] === "boolean") {
                if (typeof value === "boolean") out[key] = value;
            } else if (key === "backgroundType") {
                if (["desktop", "wallpaper", "custom"].indexOf(value) >= 0) out[key] = value;
            } else if (key === "folderBackgroundStyle") {
                if (["blur", "liquid"].indexOf(value) >= 0) out[key] = value;
            } else if (key === "customImage" && typeof value === "string") {
                out[key] = value;
            }
        }
        return out;
    }
    function layoutGeometry(w, h, values) {
        values = Object.assign({}, settingsSnapshot(), values);
        const size = values.iconSize;
        const pitch = size * pitchRatio;
        const gap = size * gapRatio;
        const label = Math.max(9, size * labelFontRatio);
        // The search pill has a fixed size, so the bottom of the search area
        // no longer depends on iconSize.
        const searchBottom = searchTop + searchHeight;
        const dotsY = h - 16;
        const availableWidth = Math.max(size, w - Math.max(48, w * 0.24));
        const availableHeight = Math.max(size, dotsY - 24 - searchBottom - 40 - size * labelOffsetRatio - label);
        const fitCols = Math.max(1, Math.floor(((values.autoLayout ? availableWidth : w - 32) + gap) / pitch));
        const fitRows = Math.max(1, Math.floor((availableHeight + gap) / pitch));
        const cols = values.autoLayout ? fitCols : Math.min(values.columns, fitCols);
        const rowCount = values.autoLayout ? fitRows : Math.min(values.rows, fitRows);
        const gridW = cols * pitch - gap;
        const gridH = rowCount * pitch - gap;
        return { columns: cols, rows: rowCount, gridWidth: gridW, gridHeight: gridH,
            x: (w - gridW) / 2,
            y: searchBottom + Math.max(20, (dotsY - 24 - searchBottom - gridH - size * labelOffsetRatio - label) / 2),
            fits: values.autoLayout || (cols === values.columns && rowCount === values.rows) };
    }
    function updateLayout(w, h) {
        if (w <= 0 || h <= 0) return;
        viewportWidth = w;
        viewportHeight = h;
        const geometry = layoutGeometry(w, h, settingsSnapshot());
        columns = geometry.columns;
        rows = geometry.rows;
    }
    function setSettings(values) {
        const normalized = normalizeSettings(values);
        configuredColumns = normalized.columns;
        configuredRows = normalized.rows;
        for (const key of Object.keys(settingsDefaults)) {
            if (key !== "columns" && key !== "rows") theme[key] = normalized[key];
        }
        if (viewportWidth > 0 && viewportHeight > 0) updateLayout(viewportWidth, viewportHeight);
        else { columns = configuredColumns; rows = configuredRows; }
    }
    property var pendingSettings: null
    signal settingsSaved()
    function saveSettings(values) {
        if (settingsSaving) return;
        settingsError = "";
        pendingSettings = normalizeSettings(values);
        if (reloadPreferencesBeforeSave) {
            preferences.reload();
            preferences.waitForJob();
            reloadPreferencesBeforeSave = false;
        }
        settingsSaving = true;
        const serialized = JSON.stringify(pendingSettings, null, 2);
        // FileView does not emit saved when the text is already identical.
        if (serialized === savedSettingsText) {
            Qt.callLater(function () {
                theme.setSettings(theme.pendingSettings);
                theme.settingsSaving = false;
                theme.settingsSaved();
            });
        } else {
            preferences.setText(serialized);
        }
    }
    FileView {
        id: preferences
        path: Quickshell.shellPath("settings.json")
        preload: true
        blockLoading: true
        atomicWrites: true
        printErrors: false
        onSaved: {
            if (!theme.settingsSaving) return;
            theme.savedSettingsText = JSON.stringify(theme.pendingSettings, null, 2);
            theme.setSettings(theme.pendingSettings);
            theme.settingsSaving = false;
            theme.settingsSaved();
        }
        onSaveFailed: {
            theme.reloadPreferencesBeforeSave = true;
            theme.settingsSaving = false;
            theme.settingsError = "Could not save settings. Please try again.";
        }
    }

    // ── master knob ───────────────────────────────────────────────────────────
    property real iconSize: 64
    property int columns: 8
    property int rows: 5
    property bool autoLayout: true
    property bool autoFolders: true
    property bool forceSquircleMask: true
    property bool mockMode: false
    property bool animationsEnabled: true
    property string fontFamily: "SF Pro Text"
    property string layerLevel: "top"

    // the user's top bar / dock are kept out of the tint + input region
    property real topInset: 33
    property real bottomInset: 70

    // ── geometry ratios (× iconSize) ──────────────────────────────────────────
    readonly property real pitchRatio: 1.728
    readonly property real gapRatio: 0.728
    readonly property real iconRadiusRatio: 0.28
    readonly property real labelFontRatio: 0.182
    readonly property real labelOffsetRatio: 0.232
    readonly property real plateSizeRatio: 1.32
    readonly property real plateRadiusRatio: 0.32
    readonly property real gridTopRatio: 0.97
    readonly property real dotDiameterRatio: 0.104
    readonly property real dotSpacingRatio: 0.24
    readonly property real folderMiniIconRatio: 0.26
    readonly property real folderMiniGapRatio: 0.045
    readonly property real folderInnerPaddingRatio: 0.12

    // ── derived geometry ──────────────────────────────────────────────────────
    readonly property real pitch: iconSize * pitchRatio
    readonly property real gap: iconSize * gapRatio
    readonly property real iconRadius: iconSize * iconRadiusRatio
    readonly property real labelFontSize: Math.max(9, iconSize * labelFontRatio)
    readonly property real labelOffset: iconSize * labelOffsetRatio
    readonly property real plateSize: iconSize + 2
    readonly property real plateRadius: iconRadius + 1
    // ── search pill (fixed size — NOT tied to iconSize) ──────────────────────
    // The icon-size slider in the settings panel only resizes the app icons;
    // the search pill keeps a fixed size, like macOS's search field.
    readonly property real searchWidth: 216
    readonly property real searchHeight: 38
    readonly property real searchTop: 18
    readonly property real dotDiameter: Math.max(4, iconSize * dotDiameterRatio)
    readonly property real dotSpacing: Math.max(10, iconSize * dotSpacingRatio)
    readonly property real folderMiniIcon: iconSize * folderMiniIconRatio
    readonly property real folderMiniGap: iconSize * folderMiniGapRatio
    readonly property real folderInnerPadding: iconSize * folderInnerPaddingRatio
    readonly property real pageDotsY: 0 // resolved by the window (needs screen height)

    readonly property real gridWidth: columns * pitch - gap
    readonly property real gridHeight: rows * pitch - gap
    readonly property int pageSize: Math.max(1, columns * rows)

    // ── squircle ──────────────────────────────────────────────────────────────
    readonly property real squircleExponent: Corners.CornerTheme.exponent
    property int squircleSegments: 40

    // ── colours: overlay ──────────────────────────────────────────────────────
    // Kept deliberately dark: the user's Hyprland blur is soft (size 3/passes 1),
    // so the tint carries most of the macOS depth.
    // No colour wash: the wallpaper stays recognisable and only Hyprland's
    // blur is applied, like macOS Launchpad / the reference screenshot.
    property color tintTop: Qt.rgba(0, 0, 0, 0.10)
    property color tintBottom: Qt.rgba(0, 0, 0, 0.03)
    property color vignette: Qt.rgba(0, 0, 0, 0.0)

    // ── colours: selection plate ──────────────────────────────────────────────
    property color plateFill: Qt.rgba(1, 1, 1, 0.11)
    property color plateRim: Qt.rgba(1, 1, 1, 0.22)

    // ── colours: labels ───────────────────────────────────────────────────────
    property color labelColor: Qt.rgba(1, 1, 1, 0.96)
    property color labelShadow: Qt.rgba(0, 0, 40 / 255, 0.55)
    property color folderLabelColor: Qt.rgba(1, 1, 1, 0.98)

    // ── colours: search pill ──────────────────────────────────────────────────
    property color searchFillTop: darkMode ? Qt.rgba(0.12,0.12,0.14,0.60) : Qt.rgba(1,1,1,0.40)
    property color searchFillBottom: darkMode ? Qt.rgba(0.16,0.16,0.18,0.70) : Qt.rgba(1,1,1,0.60)
    property color searchBorderBright: Qt.rgba(1, 1, 1, 0.30)
    property color searchBorderMid: darkMode ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.16)
    property color searchBorderDim: Qt.rgba(1, 1, 1, 0.18)
    property color searchSheen: Qt.rgba(1, 1, 1, 0.035)
    property color searchPlaceholder: darkMode ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.68)
    property color searchText: darkMode ? Qt.rgba(1,1,1,0.97) : Qt.rgba(0.10,0.10,0.12,0.97)

    // ── colours: folder glass ─────────────────────────────────────────────────
    // Launchpad groups are glass surfaces, separate from native folder icons.
    property color folderFillTop: darkMode ? Qt.rgba(0.18, 0.18, 0.20, 0.24 + menuGlassOpacity * 0.5)
                                           : Qt.rgba(1, 1, 1, 0.34 + menuGlassOpacity * 0.5)
    property color folderFillBottom: darkMode ? Qt.rgba(0.10, 0.10, 0.12, 0.34 + menuGlassOpacity * 0.5)
                                              : Qt.rgba(0.94, 0.94, 0.96, 0.44 + menuGlassOpacity * 0.5)
    property color folderBorder: darkMode ? Qt.rgba(1, 1, 1, menuGlassRim * 0.5)
                                         : Qt.rgba(0, 0, 0, menuGlassRim * 0.3)
    property color folderGlow: Qt.rgba(1, 1, 1, menuGlassRim * 0.7)

    // ── large folder (the hover-open panel) ───────────────────────────────────
    // macOS opens a folder into a big centred pane that zooms out of its tile:
    // a white translucent glass, a hairline border that is brightest at the
    // top-left and the bottom-right corner, a 6 x 5 grid of extra-large icons
    // and — when the folder holds more than one page — scrolling.
    property real folderIconSize: 80
    property int folderCols: 5
    property int folderRows: 3
    property real folderPitchX: folderIconSize * 1.35
    property real folderPitchY: folderIconSize * 1.40
    property real folderLabelFont: 13
    property real folderLabelGap: folderIconSize * 0.14
    property real folderPanelRadius: 32
    property real folderPanelPadding: folderIconSize * 0.50
    property real folderTitleHeight: folderIconSize * 0.55
    property real folderTitleFont: Math.max(15, folderIconSize * 0.22)
    property int folderHoverDelay: 250
    property int folderCloseDelay: 220
    property real dragThreshold: 8
    property int longPressDelay: 600
    property real revealGridOpacity: 0.85
    property real panelDragOutsideOpacity: 0.30
    property color dropIndicatorFill: Qt.rgba(1, 1, 1, 0.16)
    property color dropIndicatorStroke: Qt.rgba(1, 1, 1, 0.55)
    property real dropIndicatorStrokeWidth: 1.5
    property int animDropIndicator: animationsEnabled ? 80 : 0
    property int animDropPop: animationsEnabled ? 160 : 0

    // panel glass: neutral white fill, white→gray hairline border
    // (diagonal gradient), very faint top sheen
    property color folderPanelFill: darkMode ? Qt.rgba(0.10,0.10,0.12,0.40) : Qt.rgba(1,1,1,0.35)
    property color folderPanelEdge: Qt.rgba(1, 1, 1, 0.90)
    property color folderPanelEdgeMid: Qt.rgba(0.62, 0.64, 0.68, 0.30)
    property color folderPanelSheen: Qt.rgba(1, 1, 1, 0.07)

    // ── colours: context menu ─────────────────────────────────────────────────
    // Match the shell's resolved appearance, never a separate panel preference.
    property real menuWidth: 260
    property real menuRadius: Corners.CornerTheme.menuRadius
    readonly property real menuRowRadius: Corners.CornerTheme.menuItemRadius(menuRadius, Math.max(menuInsetX, menuInsetY), menuRowHeight)
    property real menuRowHeight: 26
    property real menuInsetX: Corners.CornerTheme.menuInset
    property real menuInsetY: Corners.CornerTheme.menuInset
    property real menuTextInset: 12
    property real menuSeparatorHeight: 11
    property real menuFontSize: 13
    readonly property bool menuDark: darkMode
    property real menuGlassOpacity: 0.42
    property real menuGlassLiquid: 1
    property real menuGlassRim: 0.45
    property real menuGlassGrain: 0.015
    // Glass samples wallpaper even at zero tint. Keep Light controls readable
    // on dark wallpaper while preserving the user's global opacity preference.
    readonly property real searchTintMix: darkMode ? menuGlassOpacity * 0.55 : Math.max(0.64, menuGlassOpacity * 0.55)
    readonly property real menuTintMix: menuDark ? menuGlassOpacity * 0.55 : Math.max(0.72, menuGlassOpacity * 0.55)
    property string menuPreferredFont: "SF Pro Text"
    readonly property string menuFontFamily: menuPreferredFont
    property color menuBackground: menuDark ? Qt.rgba(0.12, 0.12, 0.13, 0.96) : Qt.rgba(0.98, 0.98, 0.99, 0.97)
    property color menuRim: menuDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
    property color menuText: menuDark ? "#ffffff" : "#1d1d1f"
    property color menuDanger: "#ff453a"
    property color menuHover: accent
    property color menuSeparator: menuDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
    FileView {
        id: systemAppearance
        path: theme.configHome + "/macbar/settings.json"
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const appearance = JSON.parse(text());
                if (!appearance || typeof appearance !== "object" || Array.isArray(appearance)) return;
                if (theme.applyAppearance(appearance)) theme.appearanceLoaded = true;
                if (typeof appearance.fontFamily === "string" && appearance.fontFamily.length)
                    theme.menuPreferredFont = appearance.fontFamily.indexOf("Inter") === 0 ? "SF Pro Text" : appearance.fontFamily;
                for (const key of ["Opacity", "Liquid", "Rim", "Grain"]) {
                    const value = appearance["glass" + key];
                    if (typeof value === "number" && Number.isFinite(value))
                        theme["menuGlass" + key] = Math.max(0, Math.min(key === "Liquid" ? 2 : 1, value));
                }
            } catch (e) {
                // Keep the last appearance during an incomplete settings write.
            }
        }
    }

    // ── colours: misc ─────────────────────────────────────────────────────────
    property color editBadgeFill: Qt.rgba(0.10, 0.10, 0.14, 0.88)
    property color editBadgeRim: Qt.rgba(1, 1, 1, 0.35)
    property color doneFill: Qt.rgba(1, 1, 1, 0.16)
    property color doneText: Qt.rgba(1, 1, 1, 0.96)
    property color emptyText: Qt.rgba(1, 1, 1, 0.60)

    // colours used by generated placeholder icons
    property var fallbackPalette: [
        "#2F7BF6", "#34C759", "#FF9F0A", "#FF375F", "#AF52DE",
        "#5AC8FA", "#FFD60A", "#30D158", "#FF6482", "#BF5AF2",
        "#0A84FF", "#64D2FF", "#FFD60A", "#FF453A", "#5E5CE6"
    ]

    // ── motion ────────────────────────────────────────────────────────────────
    property int animOpen: animationsEnabled ? 260 : 0
    property int animClose: animationsEnabled ? 190 : 0
    property int animPlate: animationsEnabled ? 140 : 0
    property int animPage: animationsEnabled ? 320 : 0
    property int animFast: animationsEnabled ? 120 : 0
    property int animMenu: animationsEnabled ? 130 : 0
    property int animFolder: animationsEnabled ? 240 : 0
    property int closeDelay: animationsEnabled ? 240 : 0

    // ── icon shadow texture (one shared PNG, not one MultiEffect per icon) ────
    readonly property string shadowTexture: Qt.resolvedUrl("assets/icon-shadow.png")

    // ── paths ─────────────────────────────────────────────────────────────────
    // The layout deliberately lives directly under ~/.local/state/quickshell/
    // (Quickshell.statePath() would add an extra per-shell-ID directory).
    readonly property string stateHome: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        const base = (xdg && xdg.length > 0) ? xdg : (Quickshell.env("HOME") + "/.local/state");
        return base + "/quickshell/launchpad";
    }
    readonly property string stateDir: stateHome

    // ── optional config.json ──────────────────────────────────────────────────
    property bool configLoaded: false

    function applyConfig() {
        const txt = config.text();
        if (!txt || txt.trim() === "") {
            configLoaded = true;
            return;
        }
        try {
            const o = JSON.parse(txt);
            if (o.iconSize !== undefined) iconSize = Number(o.iconSize);
            if (o.columns !== undefined) columns = Math.max(4, Math.min(10, Number(o.columns)));
            if (o.rows !== undefined) rows = Math.max(3, Math.min(7, Number(o.rows)));
            if (o.autoLayout !== undefined) autoLayout = !!o.autoLayout;
            if (o.autoFolders !== undefined) autoFolders = !!o.autoFolders;
            if (o.forceSquircleMask !== undefined) forceSquircleMask = !!o.forceSquircleMask;
            if (o.mockMode !== undefined) mockMode = !!o.mockMode;
            if (o.animationsEnabled !== undefined) animationsEnabled = !!o.animationsEnabled;
            if (o.fontFamily) fontFamily = String(o.fontFamily);
            if (o.layerLevel) layerLevel = String(o.layerLevel);
            if (o.topInset !== undefined) topInset = Number(o.topInset);
            if (o.bottomInset !== undefined) bottomInset = Number(o.bottomInset);
            if (o.folderIconSize !== undefined) folderIconSize = Number(o.folderIconSize);
            if (o.folderCols !== undefined) folderCols = Math.max(3, Math.min(8, Number(o.folderCols)));
            if (o.folderRows !== undefined) folderRows = Math.max(3, Math.min(7, Number(o.folderRows)));
            if (o.folderHoverDelay !== undefined) folderHoverDelay = Math.max(0, Number(o.folderHoverDelay));
        } catch (e) {
            console.warn("launchpad: config.json is not valid JSON:", e);
        }
        configLoaded = true;
    }

    FileView {
        id: config
        path: Quickshell.shellPath("config.json")
        preload: true
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        applyConfig();
        configuredColumns = columns;
        configuredRows = rows;
        try {
            const txt = preferences.text();
            if (txt.trim()) setSettings(JSON.parse(txt));
            savedSettingsText = txt;
        } catch (e) { console.warn("launchpad: invalid settings:", e); }
    }
}
