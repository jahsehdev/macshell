pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: corners
    // Soft continuous UI corners (20–32 px). Dock keeps its separate preference.
    readonly property real smoothing: 0.35
    readonly property real exponent: 2 + 2 * smoothing
    readonly property real minimumPanelRadius: 20
    readonly property real maximumPanelRadius: 32
    // Nested menu corners: the highlight follows the panel with a uniform inset.
    readonly property real menuRadius: 20
    readonly property real menuInset: 7
    function menuItemRadius(outerRadius, inset, rowHeight) {
        return Math.max(0, Math.min(outerRadius - inset, rowHeight / 2));
    }
    function panelRadius(w,h,requested,smoothness) {
        // Preserve circular controls and small details; short items scale down
        // smoothly when there is not enough space for a 20 px corner.
        if (smoothness <= 0 || requested < 3) return requested;
        var minimum=Math.max(0,Math.min(minimumPanelRadius,w/4,h/4));
        return Math.max(minimum,Math.min(maximumPanelRadius,requested));
    }
    property bool owner: false
    // Native surfaces receive the fixed default once, without a watcher.
    Process {
        command: ["python3", "-u", Quickshell.env("HOME") + "/.config/quickshell/Common/sync_apps.py", "--once"]
        running: corners.owner
        stdout: SplitParser { onRead: data => console.log("[corner-settings] native defaults:",data) }
        stderr: SplitParser { onRead: data => console.warn("[corner-settings] native defaults:",data) }
    }
}
