.pragma library

// Parallel nested contours: outer radius = inner radius + edge padding.
var panelRadius = 36;
var padding = 16;
var contentRadius = panelRadius - padding;
var controlRadius = 10;
var controlPadding = 6;
var menuPadding = 16;
var menuRadius = controlRadius + menuPadding;
var railPadding = 4;
var railWidth = 32;
var navigationGutter = 24;
var header = 16;

function radius(value, width, height) {
    return Math.max(0, Math.min(value, width / 2, height / 2));
}
function innerRadius(outer, inset, width, height) {
    return radius(outer - inset, width, height);
}
function wing(mode, progress, wide) {
    return mode === "attached" ? 10 + (wide ? 14 : 0) * progress : 0;
}
function inset(mode, wide) { return wing(mode, 1, wide) + padding; }

// The rail's end caps and the first/last selection share a center. Compress
// its width with the cells when height is limited, preserving the 4 px inset.
function rail(height, count) {
    var n = Math.max(1, count);
    var cell = Math.max(12, Math.min(32, (height - 2 * panelRadius) / Math.max(1, n - 1)));
    if (cell >= railWidth - 2 * railPadding)
        cell = Math.max(12, Math.min(32, (height - 2 * (panelRadius - railWidth / 2) - 2 * railPadding) / n));
    var width = Math.min(railWidth, cell + 2 * railPadding);
    return { cell: cell, width: width, radius: width / 2,
        height: n * cell + 2 * railPadding, edge: panelRadius - width / 2 };
}
