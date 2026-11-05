#pragma once

namespace MacShell {
// Hyprland's Wayland backend turns either native maximize request into
// !internalMaximized. Independent Zoom deliberately has internal=0/client=1,
// so the second native click otherwise becomes another unchanged client=1.
inline bool restoreNativeZoom(bool eligible, bool waylandBackend, bool backendRequest,
                              bool zoomTagged, int internalMode, int clientMode,
                              bool maximizeRequested, bool fullscreenRequested) {
    return eligible && waylandBackend && backendRequest && zoomTagged
        && internalMode == 0 && clientMode == 1 && maximizeRequested && !fullscreenRequested;
}

struct Bounds {
    double x, y, width, height;
};

inline bool normalBorderCursor(bool resizeLocked, bool windowEdgeOverride) {
    return resizeLocked && windowEdgeOverride;
}

// Fill has no fullscreen flags. Include decoration extents in the caller's
// rectangle, and allow only the small rounding error of logical screen pixels.
inline bool coversWorkArea(const Bounds& window, const Bounds& work, double tolerance = 4) {
    return work.width > 0 && work.height > 0 && window.width > 0 && window.height > 0
        && window.x <= work.x + tolerance && window.y <= work.y + tolerance
        && window.x + window.width >= work.x + work.width - tolerance
        && window.y + window.height >= work.y + work.height - tolerance;
}

inline bool lockInteractiveDrag(bool eligible, int internalMode, int clientMode,
                                bool floating, const Bounds& window, const Bounds& work,
                                bool resizing = false, bool dockRounded = false,
                                bool desktopTiled = false) {
    if (!eligible) return false;
    // Native fullscreen/maximize and independent MacShell Zoom both express
    // expansion through fullscreen state. Restoring clears it immediately.
    if (internalMode != 0 || clientMode != 0) return true;
    // Never-hide Fill has no fullscreen flags and may also be a desktop tile.
    // Use the same 8px logical tolerance as window_corners.py, including tile
    // margins, but recheck geometry so a stale rounding tag cannot lock restore.
    if (resizing && dockRounded && floating && coversWorkArea(window, work, 8)) return true;
    // Half/quarter tiles and ordinary tile tear-off keep their existing behavior.
    if (desktopTiled) return false;
    return floating && coversWorkArea(window, work);
}
}
