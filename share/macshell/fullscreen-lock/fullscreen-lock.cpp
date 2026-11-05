#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#if __has_include(<hyprland/src/desktop/view/window/Window.hpp>)
#define MACSHELL_WINDOW_BACKEND_API 1
#include <hyprland/src/desktop/view/window/Window.hpp>
#else
#include <hyprland/src/desktop/view/Window.hpp>
#endif
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/pointer/cursor/CursorShapeOverrideController.hpp>
#include <cstdlib>
#include <fstream>
#include <stdexcept>
#include "policy.hpp"

using DragController = Layout::Supplementary::CDragStateController;
using BeginDrag = void (*)(DragController*, SP<Layout::ITarget>, eMouseBindMode,
                          std::optional<Layout::eRectCorner>, bool);
static CFunctionHook* beginHook = nullptr;
using BorderCursor = void (*)(CInputManager*, PHLWINDOW);
using CursorOverride = void (*)(Pointer::Cursor::CShapeOverrideController*, const std::string&,
                               Pointer::Cursor::eCursorShapeOverrideGroup);
static CFunctionHook* borderCursorHook = nullptr;
static CFunctionHook* cursorOverrideHook = nullptr;
static bool lockedBorderCursor = false;
static size_t nativeZoomRestores = 0;
static void status() {
    if (const auto home = std::getenv("HOME")) {
        std::ofstream output(std::string(home) + "/.cache/macshell/fullscreen-lock.status");
        output << "active " << __hyprland_api_get_hash() << "\nversion 1.6\nnative-zoom-restores " << nativeZoomRestores << '\n';
    }
}
#ifdef MACSHELL_WINDOW_BACKEND_API
using ClientStateRequest = void (*)(Desktop::View::CWindow*, const Desktop::View::SClientFullscreenRequest&);
static CFunctionHook* stateRequestHook = nullptr;

static void clientStateRequest(Desktop::View::CWindow* self, const Desktop::View::SClientFullscreenRequest& request) {
    const auto original = reinterpret_cast<ClientStateRequest>(stateRequestHook->m_original);
    const auto window = self->m_self.lock();
    if (window && request.maximized.value_or(false)) {
        const auto modes = Fullscreen::controller()->getFullscreenModes(window);
        const bool eligible = window->mapped() && !window->isHidden() && window->isFloating()
            && window->m_workspace && window->m_workspace->addressableName() != "special:minimized";
        if (MacShell::restoreNativeZoom(eligible, !window->backend().isX11(),
                request.origin == Desktop::View::SClientFullscreenRequest::ORIGIN_BACKEND,
                window->m_ruleApplicator->m_tagKeeper.isTagged("macshell-zoomed"),
                modes.internal, modes.client, true, request.fullscreen.has_value())) {
            auto corrected = request;
            corrected.maximized = false;
            original(self, corrected);
            ++nativeZoomRestores;
            status();
            return;
        }
    }
    original(self, request);
}
#endif

static bool locked(const SP<Layout::ITarget>& target, bool resizing) {
    if (!target) return false;
    const auto window = target->window();
    if (!window ||
#ifdef MACSHELL_WINDOW_BACKEND_API
        !window->mapped() || (window->m_state & Desktop::View::WINDOW_STATE_PINNED) ||
#else
        !window->m_isMapped || window->m_pinned ||
#endif
        window->isHidden()
        || !window->m_workspace
#ifdef MACSHELL_WINDOW_BACKEND_API
        || window->m_workspace->addressableName() == "special:minimized")
#else
        || window->m_workspace->m_name == "special:minimized")
#endif
        return false;
    const auto modes = Fullscreen::controller()->getFullscreenModes(window);
    const bool desktopTiled = window->m_ruleApplicator->m_tagKeeper.isTagged("macshell-tiled");
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
                                        resizing, dockRounded, desktopTiled);
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

static void borderCursor(CInputManager* self, PHLWINDOW window) {
    const bool previous = lockedBorderCursor;
    lockedBorderCursor = window && locked(window->layoutTarget(), true);
    // Keep Hyprland's edge/corner hit testing and its cached direction intact.
    // Only cursor requests made inside this synchronous call are transformed.
    reinterpret_cast<BorderCursor>(borderCursorHook->m_original)(self, window);
    lockedBorderCursor = previous;
}

static void cursorOverride(Pointer::Cursor::CShapeOverrideController* self, const std::string& name,
                           Pointer::Cursor::eCursorShapeOverrideGroup group) {
    static const std::string arrow = "left_ptr";
    const bool edge = group == Pointer::Cursor::CURSOR_OVERRIDE_WINDOW_EDGE;
    reinterpret_cast<CursorOverride>(cursorOverrideHook->m_original)(
        self, MacShell::normalBorderCursor(lockedBorderCursor, edge) ? arrow : name, group);
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
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "setCursorIconOnBorder")) {
        if (!match.demangled.starts_with("CInputManager::setCursorIconOnBorder(")) continue;
        borderCursorHook = HyprlandAPI::createFunctionHook(handle, match.address, reinterpret_cast<void*>(&borderCursor));
        break;
    }
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "setOverride")) {
        if (!match.demangled.starts_with("Pointer::Cursor::CShapeOverrideController::setOverride(")) continue;
        cursorOverrideHook = HyprlandAPI::createFunctionHook(handle, match.address, reinterpret_cast<void*>(&cursorOverride));
        break;
    }
#ifdef MACSHELL_WINDOW_BACKEND_API
    // Hook the shared non-inlined request entry. onUpdateState itself is
    // inlined into the backend signal listener in release compositor builds.
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "requestClientFullscreen")) {
        if (!match.demangled.starts_with("Desktop::View::CWindow::requestClientFullscreen(")) continue;
        stateRequestHook = HyprlandAPI::createFunctionHook(handle, match.address, reinterpret_cast<void*>(&clientStateRequest));
        break;
    }
    if (!stateRequestHook)
        throw std::runtime_error("MacShell fullscreen lock: client request hook unavailable");
#endif
    if (!beginHook || !borderCursorHook || !cursorOverrideHook)
        throw std::runtime_error("MacShell fullscreen lock: drag/cursor hook unavailable");
    if (!beginHook->hook() || !borderCursorHook->hook() || !cursorOverrideHook->hook()) {
        beginHook->unhook(); borderCursorHook->unhook(); cursorOverrideHook->unhook();
        throw std::runtime_error("MacShell fullscreen lock: cannot install drag/cursor hooks");
    }
#ifdef MACSHELL_WINDOW_BACKEND_API
    if (!stateRequestHook->hook()) {
        beginHook->unhook(); borderCursorHook->unhook(); cursorOverrideHook->unhook();
        throw std::runtime_error("MacShell fullscreen lock: cannot install client request hook");
    }
#endif
    // Remove any resize cursor that was already active when this plugin loaded.
    Pointer::Cursor::overrideController->unsetOverride(Pointer::Cursor::CURSOR_OVERRIDE_WINDOW_EDGE);
    status();
    return {"macshell-fullscreen-lock", "Lock expanded windows and restore native Zoom controls", "MacShell", "1.6"};
}
APICALL EXPORT void PLUGIN_EXIT() {}
