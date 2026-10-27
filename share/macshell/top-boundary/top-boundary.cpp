#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/layout/target/WindowTarget.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <stdexcept>
#include <fstream>
#include <cstdlib>
#include "clamp.hpp"

static CFunctionHook* positionHook = nullptr;
using SetPosition = void (*)(Layout::CWindowTarget*, const Layout::STargetBox&, uint8_t);

static void setPosition(Layout::CWindowTarget* target, const Layout::STargetBox& requested, uint8_t flags) {
    const auto original = reinterpret_cast<SetPosition>(positionHook->m_original);
    const auto window = target->window();
    const auto& drag = g_layoutManager->dragController();
    // Clamp the active drag itself. Programmatic placement, Zoom, workspace
    // transitions and window animations keep their original geometry path.
    if (drag->target().get() != target) {
        original(target, requested, flags);
        return;
    }
    if (!window || !window->m_isMapped || !target->floating() || window->isHidden()
        || !window->m_workspace || window->m_workspace->m_name == "special:minimized") {
        original(target, requested, flags);
        return;
    }
    const auto modes = Fullscreen::controller()->getFullscreenModes(window);
    const auto monitor = window->m_monitor.lock();
    if (!monitor || modes.internal != Fullscreen::FSMODE_NONE || modes.client == Fullscreen::FSMODE_FULLSCREEN
        || monitor->m_reservedArea.top() <= 0) {
        original(target, requested, flags);
        return;
    }
    const auto extents = window->getWindowExtentsUnified(Desktop::View::RESERVED_EXTENTS);
    const double top = monitor->logicalBox().y + monitor->m_reservedArea.top() + extents.topLeft.y;
    if (requested.logicalBox.y >= top) {
        original(target, requested, flags);
        return;
    }
    const auto mode = drag->mode();
    const bool resizing = drag->target().get() == target
        && (mode == MBIND_RESIZE || mode == MBIND_RESIZE_FORCE_RATIO || mode == MBIND_RESIZE_BLOCK_RATIO);
    const auto minimum = target->minSize().value_or(Vector2D{1, 1});
    const auto& box = requested.logicalBox;
    const auto geometry = MacShell::clampTop({box.x, box.y, box.w, box.h}, top, resizing, minimum.y);
    auto constrained = requested;
    constrained.logicalBox = {geometry.x, geometry.y, geometry.width, geometry.height};
    if (constrained.visualBox.w > 0 && constrained.visualBox.h > 0)
        constrained.visualBox.y += geometry.y - box.y;
    // Commit only the constrained position. Hyprland's drag path warps this box
    // directly, so there is no rejected frame, correction timer, or return animation.
    original(target, constrained, flags);
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("MacShell top boundary: rebuild for this Hyprland version");
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "CWindowTarget::setPositionGlobal")) {
        if (match.demangled.find("Layout::STargetBox const&") == std::string::npos) continue;
        positionHook = HyprlandAPI::createFunctionHook(handle, match.address, reinterpret_cast<void*>(&setPosition));
        break;
    }
    if (!positionHook || !positionHook->hook())
        throw std::runtime_error("MacShell top boundary: geometry hook unavailable");
    if (const auto home = std::getenv("HOME")) {
        std::ofstream status(std::string(home) + "/.cache/macshell/top-boundary.status");
        status << "active " << __hyprland_api_get_hash() << '\n';
    }
    return {"macshell-top-boundary", "Keep floating windows below the top bar before committing their geometry", "MacShell", "1.0"};
}
APICALL EXPORT void PLUGIN_EXIT() {}
