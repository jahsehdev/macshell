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
