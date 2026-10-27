.pragma library

var colors = [
    { id: "blue", name: "Blue", c: "#0a84ff" },
    { id: "purple", name: "Purple", c: "#bf5af2" },
    { id: "pink", name: "Pink", c: "#ff375f" },
    { id: "red", name: "Red", c: "#ff453a" },
    { id: "orange", name: "Orange", c: "#ff9f0a" },
    { id: "yellow", name: "Yellow", c: "#ffd60a" },
    { id: "green", name: "Green", c: "#30d158" },
    { id: "graphite", name: "Graphite", c: "#8e8e93" }
];

function validColor(value) {
    return typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value);
}

function normalize(value) {
    var o = value && typeof value === "object" ? value : {};
    var highlight = o.highlight === "custom" || colors.some(function(c) { return c.id === o.highlight; })
        ? o.highlight : "automatic";
    return {
        mode: o.mode === "single" ? "single" : "multicolor",
        accent: validColor(o.accent) ? o.accent.toLowerCase() : "#0a84ff",
        highlight: highlight,
        customHighlight: validColor(o.customHighlight) ? o.customHighlight.toLowerCase() : "#a8caff"
    };
}

function fromLegacy(value) {
    return normalize({ mode: validColor(value && value.accent) ? "single" : "multicolor",
                       accent: value && value.accent });
}

function accentFor(config, context) {
    var settings = normalize(config);
    if (settings.mode === "single") return settings.accent;
    // Multicolor respects the preferred accent of each shell application.
    return context === "clock" ? "#ff9f0a" : "#0a84ff";
}

function highlightBase(config, context) {
    var settings = normalize(config);
    if (settings.highlight === "automatic") return accentFor(settings, context);
    if (settings.highlight === "custom") return settings.customHighlight;
    return colors.filter(function(c) { return c.id === settings.highlight; })[0].c;
}

function rgb(color) {
    return [parseInt(color.slice(1, 3), 16), parseInt(color.slice(3, 5), 16), parseInt(color.slice(5, 7), 16)];
}

function selectionFor(config, context, dark) {
    var base = rgb(highlightBase(config, context));
    // Pale selection in Light, deeper selection in Dark. Controls retain their accent.
    return "#" + base.map(function(c) {
        var value = dark ? c * 0.62 : c * 0.30 + 255 * 0.70;
        return ("0" + Math.round(value).toString(16)).slice(-2);
    }).join("");
}

function luminance(color) {
    var c = rgb(color).map(function(v) {
        v /= 255;
        return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    });
    return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722;
}

function selectedTextFor(config, context, dark) {
    var l = luminance(selectionFor(config, context, dark));
    // Choose the stronger black/white contrast, including Yellow and custom colours.
    return (l + 0.05) / 0.05 >= 1.05 / (l + 0.05) ? "#000000" : "#ffffff";
}
