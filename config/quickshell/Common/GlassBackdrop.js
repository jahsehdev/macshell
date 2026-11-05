.pragma library

// lastIpcObject is cached: an unmapped toplevel can keep an old mapped=true
// record after its Wayland handle is gone. It is not a current capture source.
function hasLiveClient(client, hasWaylandHandle) {
    return !!hasWaylandHandle && !!client && client.address !== undefined;
}

// Launchpad covers application windows with its own desktop backdrop. Window
// screencopy cannot reproduce that compositor blur, and can export its clear
// surface as black. Use wallpaper on that monitor until Launchpad closes.
function clientsForGlass(clients, minimized) {
    clients = clients || [];
    minimized = minimized || {};
    var coveredMonitors = {};
    var result = [];
    for (var i = 0; i < clients.length; i++) {
        var client = clients[i];
        if (client.title === "qs-launchpad-backdrop" && client.mapped && !client.hidden)
            coveredMonitors[client.monitor] = true;
    }
    for (var j = 0; j < clients.length; j++) {
        var window = clients[j];
        var address = String(window.address || "").replace(/^0x/, "");
        var record = minimized[address] || minimized["0x" + address];
        // A minimize record is authoritative before Hyprland's cached client
        // data catches up with the workspace move. Check PID for reused addresses.
        var parked = record && (!record.pid || !window.pid || record.pid === window.pid);
        if (window.mapped && !window.hidden && !window.minimized && !parked
            && (!window.workspace || window.workspace.name !== "special:minimized")
            && window.title !== "qs-launchpad-backdrop" && !coveredMonitors[window.monitor])
            result.push(window);
    }
    return result;
}
