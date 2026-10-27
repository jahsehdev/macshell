pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: state
    property var activity: ({})
    property var preferences: ({})
    property var desktop: ({})
    property real now: Date.now()
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/launchpad"
    function covers(screenName) {
        return activity.active === true && activity.screen === screenName
            && now - Number(activity.updated || 0) < 3500;
    }
    function imageFor(screenName) {
        var kind = preferences.backgroundType || "desktop";
        if (kind === "custom") return preferences.customImage || "";
        if (kind === "wallpaper") return "file://" + Quickshell.env("HOME") + "/Pictures/Wallpapers/macos-tahoe-26-5120x2880-22674.jpg";
        var path = desktop.wallpaperPath || "";
        return path && path.indexOf(":") < 0 ? "file://" + path : path;
    }
    property FileView activityFile: FileView {
        path: state.stateDir + "/glass-backdrop.json"
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { state.activity = JSON.parse(text()); state.now = Date.now(); }
            catch (error) { /* Keep the last complete update until its lease expires. */ }
        }
        onLoadFailed: state.activity = ({})
    }
    property FileView preferencesFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/launchpad/settings.json"
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { state.preferences = JSON.parse(text()); } catch (error) {} }
    }
    property FileView desktopFile: FileView {
        path: Quickshell.env("HOME") + "/.config/macdock/settings.json"
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { state.desktop = JSON.parse(text()); } catch (error) {} }
    }
    property Timer leaseTimer: Timer {
        interval: 500
        running: state.activity.active === true
        repeat: true
        onTriggered: state.now = Date.now()
    }
}
