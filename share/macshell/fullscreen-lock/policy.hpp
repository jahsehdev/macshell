#pragma once

namespace MacShell {
struct Bounds {
    double x, y, width, height;
};

// Fill has no fullscreen flags. Include decoration extents in the caller's
// rectangle, and allow only the small rounding error of logical screen pixels.
inline bool coversWorkArea(const Bounds& window, const Bounds& work) {
    constexpr double tolerance = 4;
    return work.width > 0 && work.height > 0 && window.width > 0 && window.height > 0
        && window.x <= work.x + tolerance && window.y <= work.y + tolerance
        && window.x + window.width >= work.x + work.width - tolerance
        && window.y + window.height >= work.y + work.height - tolerance;
}

inline bool lockInteractiveDrag(bool eligible, int internalMode, int clientMode,
                                bool floating, const Bounds& window, const Bounds& work,
                                bool resizing = false, bool dockRounded = false) {
    if (!eligible) return false;
    // A work-area window beside the Never-hide Dock must remain resizable.
    // Fullscreen bits take precedence over a geometry tag from an older poll.
    if (resizing && dockRounded && floating && !(internalMode & 2) && !(clientMode & 2))
        return false;
    // Native fullscreen/maximize and independent MacShell Zoom both express
    // expansion through fullscreen state. Restoring clears it immediately.
    if (internalMode != 0 || clientMode != 0) return true;
    return floating && coversWorkArea(window, work);
}
}
