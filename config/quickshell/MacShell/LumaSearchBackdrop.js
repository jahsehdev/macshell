.pragma library

function windowsForRegion(clients, monitor, region) {
    if (!monitor) return [];
    const workspaces = [monitor.activeWorkspace ? monitor.activeWorkspace.id : -999];
    if (monitor.specialWorkspace && monitor.specialWorkspace.id !== 0) workspaces.push(monitor.specialWorkspace.id);
    return clients.filter(function(client) {
        if (!client.mapped || client.hidden || client.monitor !== monitor.id || !client.workspace || workspaces.indexOf(client.workspace.id) < 0) return false;
        const x = client.at[0] - monitor.x, y = client.at[1] - monitor.y;
        return x < region.x + region.width && x + client.size[0] > region.x
            && y < region.y + region.height && y + client.size[1] > region.y;
    }).map(function(client) {
        return {addr: client.address, wx: client.at[0] - monitor.x, wy: client.at[1] - monitor.y,
            ww: client.size[0], wh: client.size[1], wz: (client.floating ? 1000 : 0) - Math.min(client.focusHistoryID || 0, 999), gone: false};
    });
}
