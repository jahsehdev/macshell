.pragma library

function color(value) { return typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value); }
function normalize(value) {
    var o = value && typeof value === "object" ? value : {};
    return {
        style: ["default", "dark", "clear", "tinted"].indexOf(o.style) >= 0 ? o.style : "default",
        darkAppearance: o.darkAppearance === "auto" ? "auto" : "always",
        clearAppearance: ["light", "dark", "auto"].indexOf(o.clearAppearance) >= 0 ? o.clearAppearance : "auto",
        folderColor: color(o.folderColor) ? o.folderColor.toLowerCase() : "automatic",
        tintColor: color(o.tintColor) ? o.tintColor.toLowerCase() : "automatic"
    };
}
function resolvedDark(config, systemDark) {
    var o = normalize(config);
    if (o.style === "tinted") return true;
    if (o.style === "dark") return o.darkAppearance === "always" || !!systemDark;
    if (o.style === "clear") return o.clearAppearance === "dark" || (o.clearAppearance === "auto" && !!systemDark);
    return false;
}
function effectiveStyle(config, systemDark) {
    var o = normalize(config);
    return o.style === "dark" && !resolvedDark(o, systemDark) ? "default" : o.style;
}
function tint(config, accent) {
    var o = normalize(config);
    return o.tintColor === "automatic" ? (color(accent) ? accent : "#0a84ff") : o.tintColor;
}
function folder(config, accent) {
    var o = normalize(config);
    if (o.style === "tinted") return tint(o, accent);
    return o.folderColor === "automatic" ? "#0a84ff" : o.folderColor;
}
function foreground(value) {
    var c = color(value) ? value : "#0a84ff";
    var channels = [1, 3, 5].map(function(i) { return parseInt(c.slice(i, i + 2), 16); });
    var result;
    for (var white = 0.34; white <= 0.92; white += 0.04) {
        result = channels.map(function(v) { return Math.round(v * (1 - white) + 255 * white); });
        var linear = result.map(function(v) { v /= 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
        if (linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722 >= 0.40) break;
    }
    return "#" + result.map(function(v) { return ("0" + v.toString(16)).slice(-2); }).join("");
}
function widgetStyle(config, type, systemDark) {
    if (type === "image") return "normal";
    var style = effectiveStyle(config, systemDark);
    if (style === "clear") return "liquid";
    if (style === "tinted") return "tinted";
    if (style === "dark") return type === "calendar" ? "normal" : "dark";
    return type === "weather" || type === "calendar" ? "normal" : "light";
}
