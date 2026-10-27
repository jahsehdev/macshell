#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <cstdlib>
#include <fstream>
#include <stdexcept>

static CHyprSignalListener buttonListener;

// Hyprland's click path only refocuses when its cached window changes. After
// layer-shell/popups, that window can remain active while keyboard focus belongs
// to another surface. Repair that specific mismatch before delivering the click.
static void repairClickFocus(const IPointer::SButtonEvent& event, Event::SCallbackInfo&) {
    static const auto FOLLOW = CConfigValue<Config::INTEGER>("input:follow_mouse");
    // Hyprbars consumes titlebar presses before the ordinary input path runs;
    // those clicks still need to repair focus on the already-active window.
    if (event.state != WL_POINTER_BUTTON_STATE_PRESSED || *FOLLOW == 3
        || g_pInputManager->isLocked() || g_pInputManager->isConstrained()
        || !g_pInputManager->m_exclusiveLSes.empty() || g_pSeatManager->m_seatGrab)
        return;

    const auto pointer = g_pSeatManager->m_state.pointerFocus.lock();
    const auto surface = Desktop::View::CWLSurface::fromResource(pointer);
    const auto window = surface ? Desktop::View::CWindow::fromView(surface->view()) : nullptr;
    if (!window || !window->m_isMapped || window->isHidden()
        || window != Desktop::focusState()->window())
        return;

    const auto keyboard = g_pSeatManager->m_state.keyboardFocus.lock();
    const auto keyboardSurface = Desktop::View::CWLSurface::fromResource(keyboard);
    // Popups/subsurfaces belonging to this app already have legitimate focus.
    if (keyboard == pointer || (keyboardSurface && keyboardSurface->view() == window))
        return;

    const auto hit = Desktop::viewState()->hitTest().windowAt(g_pInputManager->getMouseCoordsInternal(),
        Desktop::View::ALLOW_FLOATING | Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS);
    if (hit != window)
        return; // Pointer focus may still describe a window that moved away.

    Desktop::focusState()->rawSurfaceFocus(pointer, window);
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("MacShell click focus: rebuild for this Hyprland version");
    buttonListener = Event::bus()->m_events.input.mouse.button.listen(repairClickFocus);
    if (const auto home = std::getenv("HOME")) {
        std::ofstream status(std::string(home) + "/.cache/macshell/click-focus.status");
        status << "active " << __hyprland_api_get_hash() << '\n';
    }
    return {"macshell-click-focus", "Restore stale keyboard surface focus on an explicit app click", "MacShell", "1.0"};
}
APICALL EXPORT void PLUGIN_EXIT() { buttonListener.reset(); }
