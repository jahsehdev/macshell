#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#if __has_include(<hyprland/src/desktop/view/window/Window.hpp>)
#define MACSHELL_WINDOW_BACKEND_API 1
#include <hyprland/src/desktop/view/window/Window.hpp>
#else
#include <hyprland/src/desktop/view/Window.hpp>
#endif
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <cstdlib>
#include <fstream>
#include <stdexcept>

static CHyprSignalListener buttonListener;

static bool exclusiveKeyboardLayer() {
#ifdef MACSHELL_WINDOW_BACKEND_API
    return !g_pInputManager->m_exclusiveKeyboardLSes.empty();
#else
    return !g_pInputManager->m_exclusiveLSes.empty();
#endif
}

static bool isMapped(PHLWINDOW window) {
#ifdef MACSHELL_WINDOW_BACKEND_API
    return window && window->mapped();
#else
    return window && window->m_isMapped;
#endif
}

// Hyprland's click path only refocuses when its cached window changes. After
// layer-shell/popups, keyboard focus can belong to another surface. Repair both
// an inactive clicked window and a stale surface on the already-active window.
static void repairClickFocus(const IPointer::SButtonEvent& event, Event::SCallbackInfo& info) {
    static const auto FOLLOW = CConfigValue<Config::INTEGER>("input:follow_mouse");
    // Hyprbars consumes titlebar presses before the ordinary input path runs;
    // those clicks still need to repair focus on the already-active window.
    if (info.cancelled || event.state != WL_POINTER_BUTTON_STATE_PRESSED || *FOLLOW == 3
        || g_pInputManager->getClickMode() != CLICKMODE_DEFAULT
        || g_pInputManager->isLocked() || g_pInputManager->isConstrained()
        || exclusiveKeyboardLayer() || g_pSeatManager->m_seatGrab)
        return;

    const auto pointer = g_pSeatManager->m_state.pointerFocus.lock();
    const auto surface = Desktop::View::CWLSurface::fromResource(pointer);
    const auto window = surface ? Desktop::View::CWindow::fromView(surface->view()) : nullptr;
    if (!isMapped(window) || window->isHidden())
        return;

    const auto keyboard = g_pSeatManager->m_state.keyboardFocus.lock();
    const auto keyboardSurface = Desktop::View::CWLSurface::fromResource(keyboard);
    // Popups/subsurfaces belonging to this app already have legitimate focus.
    const bool active = window == Desktop::focusState()->window();
    if (active && (keyboard == pointer || (keyboardSurface && keyboardSurface->view() == window)))
        return;

    const auto hit = Desktop::viewState()->hitTest().windowAt(g_pInputManager->getMouseCoordsInternal(),
        Desktop::View::ALLOW_FLOATING | Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS);
    if (hit != window)
        return; // Pointer focus may still describe a window that moved away.

    if (active)
        Desktop::focusState()->rawSurfaceFocus(pointer, window);
    else
        Desktop::focusState()->fullWindowFocus(window, Desktop::FOCUS_REASON_CLICK_DOWN, pointer);
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("MacShell click focus: rebuild for this Hyprland version");
    buttonListener = Event::bus()->m_events.input.mouse.button.listen(repairClickFocus);
    if (const auto home = std::getenv("HOME")) {
        std::ofstream status(std::string(home) + "/.cache/macshell/click-focus.status");
        status << "active " << __hyprland_api_get_hash() << "\nversion 1.2\n";
    }
    return {"macshell-click-focus", "Restore keyboard focus on an explicit app click", "MacShell", "1.2"};
}
APICALL EXPORT void PLUGIN_EXIT() { buttonListener.reset(); }
