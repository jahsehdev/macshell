.pragma library

function normalize(mode) {
    return mode === "tinted" ? "tinted" : "clear";
}

function blurRadius(mode, clearRadius) {
    // Tinted replaces the old Blur slider's maximum (80 px). No extra colour
    // tint or darkening: only the backdrop is blurred, never the text/icons.
    if (normalize(mode) === "tinted") return 80;
    var value = Number(clearRadius);
    return isFinite(value) ? Math.max(0, Math.min(80, value)) : 5;
}
