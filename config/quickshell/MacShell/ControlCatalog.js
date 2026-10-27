.pragma library

// One catalog for the gallery, panel layout and menu bar pins.
var categories = [
    {id: "all", label: "All Controls", icon: "grid", color: "#8e8e93"},
    {id: "clock", label: "Clock", icon: "timer", color: "#f39a26"},
    {id: "connectivity", label: "Connectivity", icon: "wifi", color: "#008aff"},
    {id: "desktop", label: "Desktop & Finder", icon: "desktop", color: "#30343a"},
    {id: "display", label: "Display & Brightness", icon: "sun", color: "#00aaff"},
    {id: "focus", label: "Focus", icon: "moon", color: "#7856ff"},
    {id: "lock", label: "Lock Screen", icon: "lock", color: "#30343a"},
    {id: "media", label: "Now Playing", icon: "play", color: "#f14e84"},
    {id: "capture", label: "Screenshot & Recording", icon: "camera", color: "#f6a925"},
    {id: "sound", label: "Sounds", icon: "speaker", color: "#ed587b"},
    {id: "utilities", label: "Utilities", icon: "coffee", color: "#8e8e93"}
];

var controls = [
    {id: "wifi", label: "Wi-Fi", glyph: "wifi", category: "connectivity", w: 2, h: 1},
    {id: "bluetooth", label: "Bluetooth", glyph: "bluetooth", category: "connectivity", w: 2, h: 1},
    {id: "airplane", label: "Airplane Mode", glyph: "airplane", category: "connectivity", w: 1, h: 1},
    {id: "focus", label: "Focus", glyph: "moon", category: "focus", w: 2, h: 1},
    {id: "nightshift", label: "Night Shift", glyph: "nightshift", category: "display", w: 1, h: 1},
    {id: "keepawake", label: "Keep Awake", glyph: "coffee", category: "utilities", w: 1, h: 1},
    {id: "darkmode", label: "Dark Mode", glyph: "contrast", category: "display", w: 1, h: 1},
    {id: "gaming", label: "Game Mode", glyph: "gamepad", category: "utilities", w: 2, h: 1},
    {id: "record", label: "Screen Recording", glyph: "record", category: "capture", w: 2, h: 1},
    {id: "nowplaying", label: "Now Playing", glyph: "note", category: "media", w: 2, h: 2, sizes: ["medium", "large"]},
    {id: "display", label: "Display", glyph: "sun", category: "display", w: 4, h: 1, sizes: ["medium", "large"]},
    {id: "sound", label: "Sound", glyph: "speaker", category: "sound", w: 4, h: 1, sizes: ["medium", "large"]},
    {id: "alarm", label: "Alarm", glyph: "alarm", category: "clock", w: 1, h: 1, sizes: ["small", "medium", "large"]},
    {id: "stopwatch", label: "Stopwatch", glyph: "stopwatch", category: "clock", w: 1, h: 1, sizes: ["small", "medium", "large"]},
    {id: "timer", label: "Timer", glyph: "timer", category: "clock", w: 1, h: 1, sizes: ["small", "medium", "large"]},
    {id: "desktop", label: "Show Desktop", glyph: "desktop", category: "desktop", w: 1, h: 1, sizes: ["small", "medium", "large"]},
    {id: "screenshot", label: "Capture Screen", glyph: "camera", category: "capture", w: 1, h: 1, sizes: ["small", "medium", "large"]},
    {id: "lock", label: "Lock Screen", glyph: "lock", category: "lock", w: 1, h: 1, sizes: ["small", "medium", "large"]}
];
var suggestions = ["desktop", "stopwatch", "timer", "focus", "screenshot", "nightshift", "keepawake"];

function find(id) {
    for (var i = 0; i < controls.length; i++) if (controls[i].id === id) return controls[i];
    return null;
}
function definition(id, sizes) {
    var d = find(id);
    if (!d) return null;
    var result = Object.assign({}, d), size = sizes && sizes[id];
    if (d.sizes && d.sizes.indexOf(size) >= 0) {
        result.w = size === "small" ? 1 : size === "medium" ? 2 : (id === "nowplaying" || id === "display" || id === "sound" ? 4 : 2);
        result.h = id === "nowplaying" || (size === "large" && id !== "display" && id !== "sound") ? 2 : 1;
    }
    return result;
}
function sizeName(id, sizes) {
    if (sizes && sizes[id]) return sizes[id];
    var d = find(id);
    return d && d.w === 4 ? "large" : d && d.w === 2 ? "medium" : "small";
}
function sections(category, query) {
    var q = String(query || "").trim().toLowerCase();
    var matches = controls.filter(function(d) {
        var c = categories.filter(function(x) { return x.id === d.category; })[0];
        return (category === "all" || category === d.category) && (!q || (d.label + " " + d.id + " " + c.label).toLowerCase().indexOf(q) >= 0);
    });
    var result = [];
    if (category === "all" && !q) result.push({id: "suggestions", label: "Suggestions", controls: suggestions.map(find)});
    categories.forEach(function(c) {
        var items = matches.filter(function(d) { return d.category === c.id; });
        if (items.length) result.push({id: c.id, label: c.label, controls: items});
    });
    return result;
}
function normalized(ids) {
    var seen = {};
    return (Array.isArray(ids) ? ids : []).filter(function(id) {
        if (!find(id) || seen[id]) return false;
        seen[id] = true;
        return true;
    });
}
function moved(ids, id, index) {
    var next = normalized(ids).filter(function(x) { return x !== id; });
    if (!find(id)) return next;
    next.splice(Math.max(0, Math.min(next.length, index)), 0, id);
    return next;
}
