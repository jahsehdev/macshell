import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: app
    property bool dark: false
    property string fontFamily: "sans-serif"
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/macbar/settings.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const settings = JSON.parse(text());
                app.dark = settings.appearanceMode === "dark" || (settings.appearanceMode !== "light" && settings.darkMode === true);
                if (typeof settings.fontFamily === "string") app.fontFamily = settings.fontFamily;
            } catch (e) {}
        }
    }
    Window {
        id: window
        title: "MacShell Customize Folder"
        width: 432; height: Screen.height > 0 ? Math.min(662, Screen.height - 140) : 662
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint
        visible: true
        onClosing: Qt.quit()
        FolderCustomizer {
            x: 20; y: 20
            height: Math.min(620, window.height - 40)
            folderPath: Quickshell.env("MACSHELL_CUSTOMIZE_FOLDER")
            dark: app.dark
            fontFamily: app.fontFamily
            onDismissed: window.close()
        }
        Shortcut { sequences: ["Ctrl+W"]; onActivated: window.close() }
        Timer {
            interval: 120; running: true; repeat: true
            property int attempts: 0
            onTriggered: {
                if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
                    const selector = 'window = "title:^(MacShell Customize Folder)$"';
                    Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + selector + ' })');
                    if (attempts === 1) Hyprland.dispatch('hl.dsp.window.center({ ' + selector + ' })');
                }
                if (++attempts >= 3) stop();
            }
        }
    }
}
