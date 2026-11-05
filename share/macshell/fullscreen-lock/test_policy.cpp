#include "policy.hpp"
#include <cassert>
#include <iostream>

int main() {
    using MacShell::lockInteractiveDrag;
    using MacShell::restoreNativeZoom;
    assert(restoreNativeZoom(true,true,true,true,0,1,true,false));
    assert(!restoreNativeZoom(true,true,true,true,0,0,true,false)); // first click enters
    assert(!restoreNativeZoom(true,true,true,true,1,1,true,false)); // native maximize
    assert(!restoreNativeZoom(true,true,true,true,2,2,true,false)); // F11
    assert(!restoreNativeZoom(true,true,true,true,0,1,true,true)); // fullscreen request
    assert(!restoreNativeZoom(true,true,true,true,0,1,false,false)); // minimize/other
    assert(!restoreNativeZoom(true,false,true,true,0,1,true,false)); // X11 semantics
    assert(!restoreNativeZoom(true,true,false,true,0,1,true,false)); // explicit foreign request
    assert(!restoreNativeZoom(true,true,true,false,0,1,true,false)); // unmanaged client
    assert(!restoreNativeZoom(false,true,true,true,0,1,true,false)); // hidden/unmapped
    assert(MacShell::normalBorderCursor(true, true)); // locked edge/corner
    assert(!MacShell::normalBorderCursor(false, true)); // restored/resizable window
    assert(!MacShell::normalBorderCursor(true, false)); // text, links, DnD, special actions
    assert(!MacShell::normalBorderCursor(false, false));
    const MacShell::Bounds work{0, 28, 1280, 772}, normal{120, 150, 800, 500};
    assert(!lockInteractiveDrag(true, 0, 0, true, normal, work));
    assert(lockInteractiveDrag(true, 2, 2, true, normal, work)); // F11 before configure completes
    assert(lockInteractiveDrag(true, 1, 1, true, work, work));  // native maximize
    assert(lockInteractiveDrag(true, 0, 1, true, work, work));  // independent Zoom
    assert(lockInteractiveDrag(true, 0, 0, true, work, work));  // Fill
    assert(!lockInteractiveDrag(true, 0, 0, false, work, work)); // tiled layout
    assert(!lockInteractiveDrag(false, 2, 2, true, work, work)); // hidden/pinned/minimized
    assert(!lockInteractiveDrag(true, 0, 0, true, normal, work)); // restored normal window
    const MacShell::Bounds secondary{-1600, -900, 1600, 872};
    assert(lockInteractiveDrag(true, 0, 0, true, secondary, secondary));
    assert(!lockInteractiveDrag(true, 0, 0, true, work, secondary)); // different monitor
    assert(!lockInteractiveDrag(true, 0, 0, true, normal, {})); // monitor removed
    const MacShell::Bounds half{0, 28, 640, 772};
    assert(!lockInteractiveDrag(true, 0, 0, true, half, work)); // snapped half window
    const MacShell::Bounds dockWork{0, 28, 1280, 708};
    assert(lockInteractiveDrag(true, 0, 0, true, dockWork, dockWork, true, true)); // Fill resize locked
    assert(lockInteractiveDrag(true, 0, 1, true, dockWork, dockWork, true, true)); // Zoom resize locked
    assert(lockInteractiveDrag(true, 1, 1, true, dockWork, dockWork, true, true)); // maximize resize locked
    assert(lockInteractiveDrag(true, 0, 1, true, dockWork, dockWork, false, true)); // move stays locked
    assert(lockInteractiveDrag(true, 0, 1, true, work, work, true, false)); // Smart/Always policy
    assert(lockInteractiveDrag(true, 2, 2, true, dockWork, dockWork, true, true)); // stale tag during F11
    assert(lockInteractiveDrag(true, 0, 2, true, dockWork, dockWork, true, true)); // pending fullscreen
    assert(lockInteractiveDrag(true, 3, 3, true, dockWork, dockWork, true, true)); // combined fullscreen
    assert(lockInteractiveDrag(true, 1, 1, false, dockWork, dockWork, true, true)); // tiled maximize
    assert(lockInteractiveDrag(true, 0, 1, true, normal, dockWork, true, true)); // maximize flag before configure
    assert(!lockInteractiveDrag(true, 0, 0, true, normal, dockWork, true, true)); // restored with stale tag
    assert(!lockInteractiveDrag(true, 0, 0, true, half, dockWork, true, true, true)); // half tile
    assert(lockInteractiveDrag(true, 0, 0, true, dockWork, dockWork, true, true, true)); // Never-hide tiled Fill
    const MacShell::Bounds fillWithMargins{8, 36, 1264, 692};
    assert(lockInteractiveDrag(true, 0, 0, true, fillWithMargins, dockWork, true, true, true));
    assert(!lockInteractiveDrag(true, 0, 0, true, fillWithMargins, dockWork, false, true, true)); // tile tear-off
    assert(!lockInteractiveDrag(true, 0, 0, true, dockWork, dockWork, true, false, true)); // ordinary desktop tile
    assert(lockInteractiveDrag(true, 2, 2, true, normal, work, true, false, true)); // fullscreen tile
    const MacShell::Bounds sideWork{80, 28, 1200, 772};
    assert(lockInteractiveDrag(true, 0, 0, true, sideWork, sideWork, true, true, true)); // side Dock
    assert(lockInteractiveDrag(true, 0, 0, true, secondary, secondary, true, true, true)); // other monitor
    std::cout << "Fullscreen, native maximize, independent Zoom, Fill, restore, overlays, tiled, multi-monitor: passed\n";
}
