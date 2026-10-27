.pragma library

// Hyprland's independent Zoom and MacShell Fill keep windows floating.
// Floating alone therefore cannot tell us whether the Dock has free space.
function workArea(monitor) {
    var scale = Number(monitor.scale) || 1;
    var width = Number(monitor.width), height = Number(monitor.height);
    if (Number(monitor.transform || 0) % 2) {
        var swap = width; width = height; height = swap;
    }
    var reserved = monitor.reserved || [0, 0, 0, 0];
    var left = Number(reserved[0]) || 0, top = Number(reserved[1]) || 0;
    var right = Number(reserved[2]) || 0, bottom = Number(reserved[3]) || 0;
    return { x: Number(monitor.x || 0) + left, y: Number(monitor.y || 0) + top,
        width: width / scale - left - right, height: height / scale - top - bottom };
}

function fillsWorkArea(client, monitor) {
    if (!client.at || !client.size) return false;
    var area = workArea(monitor), tolerance = 8;
    if (!(area.width > 0 && area.height > 0)) return false;
    return client.at[0] <= area.x + tolerance && client.at[1] <= area.y + tolerance
        && client.at[0] + client.size[0] >= area.x + area.width - tolerance
        && client.at[1] + client.size[1] >= area.y + area.height - tolerance;
}

function busyMonitors(monitors, clients) {
    var busy = {};
    for (var m = 0; m < monitors.length; m++) {
        var mon = monitors[m];
        var ids = [mon.activeWorkspace ? mon.activeWorkspace.id : -999];
        if (mon.specialWorkspace && mon.specialWorkspace.id !== 0) ids.push(mon.specialWorkspace.id);
        for (var c = 0; c < clients.length; c++) {
            var client = clients[c];
            if (!client.mapped || client.hidden || client.monitor !== mon.id || !client.workspace
                || ids.indexOf(client.workspace.id) < 0) continue;
            if (!client.floating || Number(client.fullscreen) > 0 || Number(client.fullscreenClient) > 0
                || Number(client.fullscreen_client) > 0 || fillsWorkArea(client, mon)) {
                busy[mon.name] = true;
                break;
            }
        }
    }
    return busy;
}
