pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "ThemeColors.js" as Colors

Scope {
    id: theme
    property var settings: Colors.normalize({})
    readonly property bool multicolor: settings.mode === "multicolor"
    readonly property string highlight: settings.highlight
    readonly property var colorChoices: [{ id: "multicolor", name: "Multicolor", c: "multicolor" }].concat(Colors.colors)
    readonly property var highlightChoices: [{ id: "automatic", name: "Automatic" }].concat(Colors.colors).concat([{ id: "custom", name: "Other…" }])
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    property bool preferenceLoaded: false

    function accentFor(context) { return Colors.accentFor(settings, context); }
    function selectionFor(context, dark) { return Colors.selectionFor(settings, context, dark); }
    function selectedTextFor(context, dark) { return Colors.selectedTextFor(settings, context, dark); }
    function highlightBase(context) { return Colors.highlightBase(settings, context); }
    function save(value) {
        preferenceLoaded = true;
        settings = Colors.normalize(value);
        preference.setText(JSON.stringify(settings, null, 2));
    }
    function setAccent(mode, color) {
        if (mode !== "single" && mode !== "multicolor") return;
        if (mode === "single" && !Colors.validColor(color)) return;
        save({ mode: mode, accent: mode === "single" ? color : settings.accent,
               highlight: settings.highlight, customHighlight: settings.customHighlight });
    }
    function setHighlight(value, customColor) {
        if (!highlightChoices.some(function(c) { return c.id === value; })) return;
        if (value === "custom" && !Colors.validColor(customColor)) return;
        save({ mode: settings.mode, accent: settings.accent, highlight: value,
               customHighlight: value === "custom" ? customColor : settings.customHighlight });
    }
    function reset() { save(Colors.normalize({})); }

    FileView {
        id: preference
        path: theme.configHome + "/macshell/colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                if (!saved || typeof saved !== "object" || Array.isArray(saved)) return;
                theme.settings = Colors.normalize(saved);
                theme.preferenceLoaded = true;
            } catch (e) { /* Retain the last valid theme during partial writes. */ }
        }
    }
    FileView {
        path: theme.configHome + "/macdock/settings.json"
        printErrors: false
        onLoaded: {
            if (theme.preferenceLoaded) return;
            try { theme.settings = Colors.fromLegacy(JSON.parse(text())); } catch (e) { }
        }
    }
}
