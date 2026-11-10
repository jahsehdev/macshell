pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "GlassMaterial.js" as Preset

Scope {
    id: material
    // Shared continuous material. The old mode-only preference maps to the
    // two endpoints; keep that API for existing IPC callers.
    property real intensity: 0
    // One optical profile for every glass surface. Legacy Dock controls remain
    // the tuning input; components must not invent their own material values.
    property var tuning: ({})
    function value(key, fallback, maximum) {
        var number = tuning[key];
        return typeof number === "number" && isFinite(number)
            ? Math.max(0, Math.min(maximum, number)) : fallback;
    }
    readonly property real baseOpacity: value("glassOpacity", 0, 1)
    readonly property real baseLiquid: value("glassLiquid", 0.5, 2)
    readonly property real baseBlur: value("glassBlur", 0, 80)
    readonly property real baseRim: value("glassRim", 0.55, 2)
    readonly property real baseGrain: value("glassGrain", 0, 1)
    readonly property real surfaceBlur: blurRadius(baseBlur)
    readonly property url shaderUrl: Qt.resolvedUrl("LiquidGlass.frag.dock.qsb")
    function profile(amount) {
        var level = Preset.intensity(amount);
        var liquid = baseLiquid * (1 - level * 0.65);
        return {
            thickness: 30 * liquid, dispersion: 0.06 * liquid,
            magnify: 0.08 * liquid, rim: baseRim, grain: baseGrain,
            opacity: Preset.opacityAt(level, baseOpacity),
            tint: Preset.opacityAt(level, baseOpacity) * 0.55,
            blur: Preset.blurAt(level, baseBlur), blurPx: 1.5,
            saturation: 1.25, flatInner: 0, rimTint: 0, ringW: 0
        };
    }
    readonly property string mode: intensity >= 0.5 ? "tinted" : "clear"
    readonly property bool tinted: intensity >= 1
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/macshell"

    function blurRadius(clearRadius) { return Preset.blurAt(intensity, clearRadius); }
    function opacity(base) { return Preset.opacityAt(intensity, base); }

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/macdock/settings.json"
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                var saved = JSON.parse(text());
                if (saved && typeof saved === "object" && !Array.isArray(saved)) material.tuning = saved;
            } catch (error) { /* Retain the last complete material update. */ }
        }
    }

    function setIntensity(value) {
        intensity = Preset.intensity(value);
        saveTimer.restart();
    }

    function setMode(value) {
        if (value !== "clear" && value !== "tinted") return;
        setIntensity(value === "tinted" ? 1 : 0);
    }

    // Apply every drag frame in memory; coalesce disk writes after movement.
    Timer {
        id: saveTimer
        interval: 160
        onTriggered: preference.setText(JSON.stringify({ mode: material.mode, intensity: material.intensity }, null, 2))
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", configDir])
    FileView {
        id: preference
        path: material.configDir + "/liquidglass.json"
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                if (!saveTimer.running) material.intensity = Preset.fromSaved(saved);
            } catch (error) { /* Keep the last valid material during partial writes. */ }
        }
        onLoadFailed: material.intensity = 0
    }
}
