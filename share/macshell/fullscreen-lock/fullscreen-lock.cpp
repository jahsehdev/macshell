#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <cstdlib>
#include <fstream>
#include <stdexcept>
#include "policy.hpp"

using DragController = Layout::Supplementary::CDragStateController;
using BeginDrag = void (*)(DragController*, SP<Layout::ITarget>, eMouseBindMode,
                          std::optional<Layout::eRectCorner>, bool);
static CFunctionHook* beginHook = nullptr;

static bool locked(const SP<Layout::ITarget>& target, bool resizing) {
    if (!target) return false;
    const auto window = target->window();
    if (!window || !window->m_isMapped || window->isHidden() || window->m_pinned
        || !window->m_workspace || window->m_workspace->m_name == "special:minimized")
        return false;
    const auto modes = Fullscreen::controller()->getFullscreenModes(window);
    const auto monitor = window->m_monitor.lock();
    MacShell::Bounds bounds{}, work{};
    if (monitor) {
        const auto box = target->position();
        const auto extents = window->getWindowExtentsUnified(Desktop::View::RESERVED_EXTENTS);
        bounds = {box.x - extents.topLeft.x, box.y - extents.topLeft.y,
                  box.w + extents.topLeft.x + extents.bottomRight.x,
                  box.h + extents.topLeft.y + extents.bottomRight.y};
        const auto area = monitor->logicalBoxMinusReserved();
        work = {area.x, area.y, area.w, area.h};
    }
    const bool dockRounded = window->m_ruleApplicator->m_tagKeeper.isTagged("macshell-dock-rounded-window");
    return MacShell::lockInteractiveDrag(true, modes.internal, modes.client, target->floating(), bounds, work,
                                        resizing, dockRounded);
}

static void beginDrag(DragController* self, SP<Layout::ITarget> target, eMouseBindMode mode,
                      std::optional<Layout::eRectCorner> forcedEdge, bool exclusiveDeviceGrab) {
    const bool resizing = mode == MBIND_RESIZE || mode == MBIND_RESIZE_FORCE_RATIO || mode == MBIND_RESIZE_BLOCK_RATIO;
    const bool interactive = mode == MBIND_MOVE || resizing;
    // Reject before Hyprland initializes a drag or clears fullscreen state.
    // Native titlebars, hyprbars, border resize and Super+mouse share this path.
    if (interactive && locked(target, resizing)) return;
    reinterpret_cast<BeginDrag>(beginHook->m_original)(self, target, mode, forcedEdge, exclusiveDeviceGrab);
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("MacShell fullscreen lock: rebuild for this Hyprland version");
    // Hyprland searches the mangled nm symbol, which contains "dragBegin"
    // but never "CDragStateController::dragBegin". Filter its demangled name
    // afterwards so we hook only the intended class and overload.
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "dragBegin")) {
        if (!match.demangled.starts_with("Layout::Supplementary::CDragStateController::dragBegin(")) continue;
        if (match.demangled.find("std::optional<Layout::eRectCorner>") == std::string::npos) continue;
        beginHook = HyprlandAPI::createFunctionHook(handle, match.address, reinterpret_cast<void*>(&beginDrag));
        break;
    }
    if (!beginHook || !beginHook->hook())
        throw std::runtime_error("MacShell fullscreen lock: drag hook unavailable");
    if (const auto home = std::getenv("HOME")) {
        std::ofstream status(std::string(home) + "/.cache/macshell/fullscreen-lock.status");
        status << "active " << __hyprland_api_get_hash() << "\nversion 1.2\n";
    }
    return {"macshell-fullscreen-lock", "Lock expanded window movement; allow Never-hide Dock work-area resizing", "MacShell", "1.2"};
}
APICALL EXPORT void PLUGIN_EXIT() {}
