#include "policy.hpp"
#include <cassert>
#include <iostream>

int main() {
    using MacShell::lockInteractiveDrag;
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
    assert(!lockInteractiveDrag(true, 0, 0, true, dockWork, dockWork, true, true)); // Fill resize
    assert(!lockInteractiveDrag(true, 0, 1, true, dockWork, dockWork, true, true)); // Zoom resize
    assert(!lockInteractiveDrag(true, 1, 1, true, dockWork, dockWork, true, true)); // maximize resize
    assert(lockInteractiveDrag(true, 0, 1, true, dockWork, dockWork, false, true)); // move stays locked
    assert(lockInteractiveDrag(true, 0, 1, true, work, work, true, false)); // Smart/Always policy
    assert(lockInteractiveDrag(true, 2, 2, true, dockWork, dockWork, true, true)); // stale tag during F11
    assert(lockInteractiveDrag(true, 0, 2, true, dockWork, dockWork, true, true)); // pending fullscreen
    assert(lockInteractiveDrag(true, 3, 3, true, dockWork, dockWork, true, true)); // combined fullscreen
    assert(lockInteractiveDrag(true, 1, 1, false, dockWork, dockWork, true, true)); // tiled maximize
    assert(!lockInteractiveDrag(true, 0, 1, true, normal, dockWork, true, true)); // in-progress resize
    std::cout << "Fullscreen, native maximize, independent Zoom, Fill, restore, overlays, tiled, multi-monitor: passed\n";
}
