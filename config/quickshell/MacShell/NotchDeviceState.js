.pragma library

function key(device) { return String(device.mac || device.name || "").toLowerCase(); }
function battery(device) {
    var value = device ? device.bat : undefined;
    if (typeof value !== "number" && typeof value !== "string") return -1;
    if (String(value).trim() === "" || !/^\d+(\.\d+)?$/.test(String(value).trim())) return -1;
    var n = Number(value);
    return isFinite(n) && n >= 0 && n <= 100 ? Math.round(n) : -1;
}
function kind(device) {
    var name = String(device && device.name || "").toLowerCase();
    var icon = String(device && (device.systemIcon || device.icon) || "").toLowerCase();
    if (/airpod|earbud|\bbuds|freebuds/.test(name)) return "earbuds";
    if (/keyboard|keychron/.test(name) || /keyboard/.test(icon)) return "keyboard";
    if (/mouse|trackpad|mx master|mx anywhere/.test(name) || /mouse/.test(icon)) return "mouse";
    if (/headphone|headset|\bwh-|\bwf-/.test(name) || /headphone|headset/.test(icon)) return "headphones";
    if (/controller|gamepad|xbox|dualshock|dualsense|8bitdo/.test(name) || /gaming|gamepad|joystick/.test(icon)) return "gamepad";
    if (/speaker|soundbar|homepod/.test(name) || /speaker/.test(icon)) return "speaker";
    if (/iphone|phone|galaxy|pixel/.test(name) || /phone/.test(icon)) return "phone";
    return "bluetooth";
}
// Keep only connected devices. Unknown readings never become zero-percent alerts.
function observe(prior, devices, primed) {
    var history = {}, events = [], keys = [];
    (devices || []).filter(function(d) { return d.connected; }).slice(0, 128).forEach(function(d) {
        var id = key(d); if (!id || history[id]) return;
        var p = battery(d), old = prior[id], low = old ? old.low : p >= 0 && p <= 20;
        var critical = old ? old.critical : p >= 0 && p <= 10;
        if (primed && !old) events.push({device:d, reason:"connected"});
        if (old && primed && p >= 0) {
            if (p >= 25) low = false;
            if (p >= 15) critical = false;
            if (p <= 10 && !critical) { events.push({device:d, reason:"low"}); critical = true; low = true; }
            else if (p <= 20 && !low) { events.push({device:d, reason:"low"}); low = true; }
        }
        history[id] = {low:low, critical:critical, battery:p}; keys.push(id);
    });
    return {history:history, events:events, keys:keys};
}
