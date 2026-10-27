.pragma library
function mode(value) { return value === "windows" ? "windows" : "icons"; }
function layout(count, width, height, preview) {
    count = Math.max(0, count);
    var padding = 14, available = Math.max(1, width - 64 - 2 * padding);
    if (!preview) {
        var cw = Math.min(92, Math.max(1, (width - 160) / Math.max(count, 1)));
        return {columns: Math.max(count,1), cellWidth: cw, cellHeight: Math.round(cw * 0.8),
            gap: 0, viewHeight: Math.round(cw * 0.8), contentHeight: Math.round(cw * 0.8),
            width: count * cw + 2 * padding};
    }
    var columns = Math.max(1, Math.min(Math.max(count,1), 4, Math.floor(available / 230)));
    var cellWidth = Math.min(250, available / columns);
    var cellHeight = Math.round(cellWidth * 0.65) + 36;
    var rows = Math.max(1, Math.ceil(count / columns)), gap = 8;
    var contentHeight = rows * (cellHeight + gap) - gap;
    return {columns:columns, cellWidth:cellWidth, cellHeight:cellHeight, gap:gap,
        viewHeight: Math.min(contentHeight, Math.max(cellHeight, height * 0.64)),
        contentHeight:contentHeight, width:columns * cellWidth + 2 * padding};
}
