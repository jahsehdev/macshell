// Start Spotify toolbar gestures through Hyprland's actual drag controller.
// A successful XSendEvent only queues a message; it does not start a WM drag.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowBackend.hpp>
#include <hyprland/src/desktop/view/window/WindowMetadata.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <lua.hpp>
#include <stdexcept>

static bool leftHeld = false;
static CHyprSignalListener buttonListener;

static int moveSpotify(lua_State* lua) {
    int valid = 0;
    const auto pid = lua_tointegerx(lua, 1, &valid);
    const auto window = Desktop::focusState()->window();
    const bool held = leftHeld && g_pInputManager && g_pInputManager->hasHeldButtons();
    if (!valid || pid <= 0 || !window || !window->mapped() || window->isHidden()
        || window->backend().pid() != pid
        || (window->metadata().appID() != "spotify" && window->metadata().appID() != "Spotify")
        || !held || g_pInputManager->isLocked() || g_pInputManager->isConstrained()
        || !g_pInputManager->m_exclusiveKeyboardLSes.empty()
        || g_pInputManager->getClickMode() != CLICKMODE_DEFAULT || !window->layoutTarget()) {
        lua_pushboolean(lua, false);
        return 1;
    }
    const auto& controller = g_layoutManager->dragController();
    if (controller->target()) {
        lua_pushboolean(lua, false);
        return 1;
    }
    // Reuse the native path and existing fullscreen-lock policy. The exclusive
    // device grab keeps motion and release working after the pointer exits CEF.
    g_layoutManager->beginDragTarget(window->layoutTarget(), MBIND_MOVE, std::nullopt, true);
    lua_pushboolean(lua, controller->target() == window->layoutTarget());
    return 1;
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("Spotify toolbar drag: rebuild for this Hyprland version");
    if (!HyprlandAPI::addLuaFunction(handle, "macshell_spotify", "move", moveSpotify))
        throw std::runtime_error("Spotify toolbar drag: cannot register move callback");
    buttonListener = Event::bus()->m_events.input.mouse.button.listen(
        [](const IPointer::SButtonEvent& event, Event::SCallbackInfo& info) {
            if (event.button == 272)
                leftHeld = event.state == WL_POINTER_BUTTON_STATE_PRESSED && !info.cancelled;
        });
    return {"macshell-spotify-drag", "Native Spotify toolbar dragging", "MacShell", "1.0"};
}
APICALL EXPORT void PLUGIN_EXIT() { buttonListener.reset(); }
