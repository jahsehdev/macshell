pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "DesktopPreferences.js" as Values
Scope {
    id: prefs
    property var settings: Values.normalize({})
    property bool loaded: false
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"

    // ── Accessibility (shared by the bar, Dock, widgets and settings) ──
    // Reduce Transparency raises the glass tint to an almost solid fill and
    // switches the refraction off. Increase Contrast strengthens glass rims and
    // menu borders. Reduce Motion makes the shell's transitions instant and
    // stops decorative repeating animations.
    readonly property bool reduceTransparency: settings.reduceTransparency
    readonly property bool increaseContrast: settings.increaseContrast
    readonly property bool showBorders: settings.showBorders
    readonly property bool reduceMotion: settings.reduceMotion
    function anim(ms) { return reduceMotion ? 0 : ms }
    function glassOpacity(value) { return reduceTransparency ? Math.max(value, 0.94) : GlassMaterial.opacity(value) }
    // Light-mode glass usually uses a lighter tint (opacity * 0.55); with
    // Reduce Transparency that multiplier must not reintroduce see-through.
    function glassTint(value, factor) { return reduceTransparency ? 0.94 : value * factor }
    function glassLiquid(value) { return reduceTransparency ? 0 : value * (1 - GlassMaterial.intensity * 0.65) }
    function glassBlur(value) { return reduceTransparency ? 0 : value }
    function glassGrain(value) { return reduceTransparency ? 0 : value }
    function glassRim(value) { return increaseContrast || showBorders ? Math.max(value, 0.85) : value }

    function setValue(key, value) {
        if (!Object.prototype.hasOwnProperty.call(settings, key)) return;
        var next = Object.assign({}, settings); next[key] = value;
        settings = Values.normalize(next);
        store.setText(JSON.stringify(settings, null, 2));
    }
    function reset() { settings = Values.normalize({}); store.setText(JSON.stringify(settings, null, 2)); }
    FileView {
        id: store
        path: prefs.configHome + "/macshell/desktop-dock.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { prefs.settings = Values.normalize(JSON.parse(text())); } catch (e) {} prefs.loaded = true; }
        onLoadFailed: prefs.loaded = true
    }
}
