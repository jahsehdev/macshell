.pragma library

function normalize(mode) {
    return mode === "tinted" ? "tinted" : "clear";
}

function intensity(value, fallback) {
    return typeof value === "number" && isFinite(value)
        ? Math.max(0, Math.min(1, value)) : (fallback === "tinted" ? 1 : 0);
}

function fromSaved(saved) {
    return intensity(saved.intensity, saved.mode);
}

function blurAt(amount, clearRadius) {
    var start = blurRadius("clear", clearRadius);
    return start + (80 - start) * intensity(amount);
}

function opacityAt(amount, base) {
    // Retain the user's translucency tuning at Clear; gently approach a dense
    // theme-coloured material at the other end, without dimming the backdrop.
    var t = intensity(amount);
    if (t === 0) return base;
    if (t === 1) return Math.max(base, 0.92);
    return base + (Math.max(base, 0.92) - base) * t;
}

function blurRadius(mode, clearRadius) {
    // Tinted replaces the old Blur slider's maximum (80 px). No extra colour
    // tint or darkening: only the backdrop is blurred, never the text/icons.
    if (normalize(mode) === "tinted") return 80;
    var value = Number(clearRadius);
    return isFinite(value) ? Math.max(0, Math.min(80, value)) : 5;
}
