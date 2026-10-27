.pragma library

// lastIpcObject is cached: an unmapped toplevel can keep an old mapped=true
// record after its Wayland handle is gone. It is not a current capture source.
function hasLiveClient(client, hasWaylandHandle) {
    return !!hasWaylandHandle && !!client && client.address !== undefined;
}

// Launchpad covers application windows with its own desktop backdrop. Window
// screencopy cannot reproduce that compositor blur, and can export its clear
// surface as black. Use wallpaper on that monitor until Launchpad closes.
function clientsForGlass(clients) {
    var coveredMonitors = {};
    var result = [];
    for (var i = 0; i < clients.length; i++) {
        var client = clients[i];
        if (client.title === "qs-launchpad-backdrop" && client.mapped && !client.hidden)
            coveredMonitors[client.monitor] = true;
    }
    for (var j = 0; j < clients.length; j++) {
        var window = clients[j];
        if (window.title !== "qs-launchpad-backdrop" && !coveredMonitors[window.monitor])
            result.push(window);
    }
    return result;
}
