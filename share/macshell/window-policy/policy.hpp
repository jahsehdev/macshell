#pragma once
#include <algorithm>
#include <cmath>
#include <string_view>

namespace MacShell::WindowPolicy {
struct Rect { double x, y, w, h; };
struct Insets { double left = 0, top = 0, right = 0, bottom = 0; };

// Work areas are already in logical coordinates, including monitor scale,
// rotation, origin, menu-bar reservation and Dock reservation.
inline Rect initialBounds(Rect area, Insets frame, Rect minimum, Rect maximum, unsigned index) {
    const auto axis = [](double desired, double available, double minimum, double maximum) {
        double result = std::max(desired, minimum);
        if (maximum > 0) result = std::min(result, maximum);
        return std::max(1.0, std::min(result, std::max(1.0, available)));
    };
    const double width = axis(std::floor(area.w * .75) - frame.left - frame.right,
                              area.w - frame.left - frame.right, minimum.w, maximum.w);
    const double height = axis(std::floor(area.h * .75) - frame.top - frame.bottom,
                               area.h - frame.top - frame.bottom, minimum.h, maximum.h);
    const double outerW = width + frame.left + frame.right;
    const double outerH = height + frame.top + frame.bottom;
    const double offset = (static_cast<int>(index % 5) - 2) * 28;
    const double dx = std::clamp(std::floor((area.w - outerW) / 2) + offset, 0.0, std::max(0.0, area.w - outerW));
    const double dy = std::clamp(std::floor((area.h - outerH) / 2) + offset, 0.0, std::max(0.0, area.h - outerH));
    return {area.x + dx + frame.left, area.y + dy + frame.top, width, height};
}

inline bool shellSurface(std::string_view title) {
    return title == "qs-launchpad-backdrop" || title.starts_with("qs-launchpad-");
}

template <typename Window>
inline bool normalWindow(const Window& window, bool pinned) {
    // CWindow::desktopComponent() is true for every app window in Hyprland
    // 0.57. It describes scene membership, not a desktop/background surface.
    if (!window || !window->mapped() || pinned || shellSurface(window->metadata().title())) return false;
    const auto traits = window->backend().traits();
    return !traits.overrideRedirect && !traits.preventsFocus;
}

inline bool nativeControls(std::string_view app, std::string_view title, bool ready, bool force) {
    if (force) return false;
    if (ready) return true;
    // Only applications whose MacShell integration already supplies all three
    // controls belong here. Unknown clients receive a server-side fallback.
    return app == "firefox" || app == "Firefox" || app == "zen" || app == "zen-browser"
        || app == "org.gnome.Nautilus" || app == "org.gnome.Console" || app == "kgx"
        || app == "org.gnome.TextEditor" || app == "org.gnome.Calculator"
        || app == "gnome-text-editor" || app == "gnome-calculator" || app == "org.gnome.Terminal"
        || app == "org.gnome.Calendar" || app == "org.gnome.clocks" || app == "org.gnome.Clocks"
        || app == "org.gnome.Contacts" || app == "org.gnome.Maps" || app == "org.gnome.Loupe"
        || app == "org.gnome.Weather"
        || app == "org.macshell.PhotoBooth" || app == "tahoe-photobooth"
        || (app == "org.quickshell" && (title == "Clock" || title == "System Settings"
            || title == "Setting" || title == "Settings" || title == "Luma AI" || title == "About This Linux"));
}

inline int buttonAt(double x, double y, double height) {
    if (y < 0 || y >= height || x < 12) return -1;
    const int index = static_cast<int>((x - 12) / 24);
    return index < 3 && x < 12 + index * 24 + 18 ? index : -1;
}
}
