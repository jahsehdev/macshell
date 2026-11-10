#include "policy.hpp"
#include <cassert>
#include <iostream>

using namespace MacShell::WindowPolicy;

// Model the Hyprland 0.57 window API, including the scene-membership flag
// that is true for ordinary app windows as well as other desktop components.
struct TestWindow {
    bool isMapped = true;
    std::string_view titleText = "New Tab — Mozilla Firefox";
    struct Traits { bool overrideRedirect = false, preventsFocus = false; } traitsValue;
    bool desktopComponent() const { return true; }
    bool mapped() const { return isMapped; }
    const TestWindow& metadata() const { return *this; }
    std::string_view title() const { return titleText; }
    const TestWindow& backend() const { return *this; }
    Traits traits() const { return traitsValue; }
};

int main() {
    TestWindow window;
    assert(window.desktopComponent());
    assert(normalWindow(&window, false));
    assert(!normalWindow(static_cast<TestWindow*>(nullptr), false));
    assert(!normalWindow(&window, true));
    window.isMapped = false;
    assert(!normalWindow(&window, false));
    window.isMapped = true;
    window.titleText = "qs-launchpad-backdrop";
    assert(!normalWindow(&window, false));
    window.titleText = "Unknown application";
    assert(normalWindow(&window, false));
    window.traitsValue.overrideRedirect = true;
    assert(!normalWindow(&window, false));
    window.traitsValue = {.preventsFocus = true};
    assert(!normalWindow(&window, false));

    // A 1280x800 monitor with menu bar and Dock: the entire decorated frame
    // occupies 75% of the remaining area, not 75% of physical pixels.
    auto r = initialBounds({0, 28, 1280, 708}, {0, 34, 0, 0}, {}, {}, 2);
    assert(r.w == 960 && r.h == 497 && r.x == 160 && r.y == 150);
    // Logical work area on a scaled secondary display with a negative origin.
    r = initialBounds({-1920, 128, 1920, 980}, {0, 34, 0, 0}, {}, {}, 2);
    assert(r.w == 1440 && r.h == 701 && r.x == -1680 && r.y == 284);
    // Every cascade slot stays on this monitor, even when minimum sizes fill it.
    for (unsigned i = 0; i < 10; ++i) {
        r = initialBounds({-1280, -772, 1280, 708}, {0, 34, 0, 0}, {0, 0, 1200, 650}, {}, i);
        assert(r.x >= -1280 && r.y - 34 >= -772);
        assert(r.x + r.w <= 0 && r.y + r.h <= -64);
        assert(r.w >= 1200 && r.h >= 650);
    }
    r = initialBounds({0, 28, 1280, 708}, {}, {}, {0, 0, 700, 400}, 2);
    assert(r.w == 700 && r.h == 400);
    r = initialBounds({0, 0, 200, 100}, {0, 34, 0, 0}, {0, 0, 600, 440}, {}, 2);
    assert(r.w == 200 && r.h == 66 && r.y == 34);
    assert(!nativeControls("com.opencode.desktop", "OpenCode", false, false));
    assert(!nativeControls("tayang-studio", "Tayang Studio", false, false));
    assert(!nativeControls("new-client", "New client", false, false));
    assert(nativeControls("firefox", "Browser", false, false));
    assert(nativeControls("spotify", "Spotify", true, false));
    assert(!nativeControls("firefox", "Browser", true, true));
    assert(nativeControls("org.quickshell", "Clock", false, false));
    // MacDock.qml's preferences window is titled "Setting" and already owns
    // its traffic lights. Keep legacy titles covered without exempting other apps.
    for (const auto title : {"Setting", "Settings", "System Settings"}) {
        assert(nativeControls("org.quickshell", title, false, false));
        assert(!nativeControls("unknown", title, false, false));
        assert(!nativeControls("org.quickshell", title, false, true));
    }
    assert(!nativeControls("org.quickshell", "Unknown window", false, false));
    assert(!nativeControls("unknown", "Clock", false, false));
    assert(shellSurface("qs-launchpad-backdrop"));
    assert(!shellSurface("Tayang Studio"));
    assert(buttonAt(12, 0, 34) == 0);
    assert(buttonAt(29.9, 33.9, 34) == 0);
    assert(buttonAt(30, 17, 34) == -1);
    assert(buttonAt(36, 17, 34) == 1);
    assert(buttonAt(60, 17, 34) == 2);
    assert(buttonAt(78, 17, 34) == -1);
    assert(buttonAt(12, -1, 34) == -1);
    assert(buttonAt(12, 34, 34) == -1);
    std::cout << "Window policy: app eligibility, work areas, constraints, cascade, native controls and hit targets passed.\n";
}
