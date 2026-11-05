.pragma library

// Anchor the tip to the actual 64px folder image, independent of where the
// context menu was clamped to fit the screen.
function beside(icon, screenWidth, screenHeight, panelWidth, panelHeight) {
    const margin = 12, tail = 10, gap = 8;
    const left = icon.x - gap - tail - panelWidth;
    const right = icon.x + icon.width + gap + tail;
    const onLeft = left < margin && screenWidth - right > icon.x - margin;
    const x = Math.max(margin, Math.min(screenWidth - panelWidth - margin, onLeft ? right : left));
    const centerY = icon.y + icon.height / 2;
    const y = Math.max(margin, Math.min(screenHeight - panelHeight - margin, centerY - 124));
    return { x: x, y: y, pointerY: centerY - y, tailOnLeft: onLeft };
}
