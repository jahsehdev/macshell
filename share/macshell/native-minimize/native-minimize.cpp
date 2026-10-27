#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/config/supplementary/executor/Executor.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <format>
#include <unordered_map>
#include <stdexcept>

struct Entry {
    PHLWINDOWREF window;
    CHyprSignalListener state;
};
static std::unordered_map<Desktop::View::CWindow*, Entry> entries;
static CHyprSignalListener opened, closed, changedClass;
static size_t forwarded = 0;

static void status() {
    if (const auto home = std::getenv("HOME")) {
        std::ofstream out(std::string(home) + "/.cache/macshell/native-minimize.status");
        out << "active " << __hyprland_api_get_hash() << "\nattached " << entries.size()
            << "\nforwarded " << forwarded << '\n';
    }
}

struct CapabilityUpdate { PHLWINDOW window; bool enabled; };
static wl_iterator_result updateResource(wl_resource* resource, void* data) {
    auto& update = *static_cast<CapabilityUpdate*>(data);
    if (std::strcmp(wl_resource_get_class(resource), "xdg_toplevel") != 0
        || wl_resource_get_version(resource) < 5)
        return WL_ITERATOR_CONTINUE;
    const auto top = CXDGToplevelResource::fromResource(resource);
    if (!top || top->m_window != update.window)
        return WL_ITERATOR_CONTINUE;
    // Hyprland supports maximize/fullscreen; MacShell supplies minimize.
    uint32_t values[] = {XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE,
                         XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN,
                         XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE};
    wl_array caps{.size = sizeof(uint32_t) * (update.enabled ? 3u : 2u),
                  .alloc = sizeof(values), .data = values};
    static_cast<CXdgToplevel*>(wl_resource_get_user_data(resource))->sendWmCapabilities(&caps);
    update.window->m_xdgSurface->scheduleConfigure();
    return WL_ITERATOR_STOP;
}

static void advertise(PHLWINDOW window, bool enabled) {
    if (!window || !window->m_xdgSurface || !window->wlSurface()->resource()) return;
    CapabilityUpdate update{window, enabled};
    wl_client_for_each_resource(window->wlSurface()->resource()->client(), updateResource, &update);
}

static void attach(PHLWINDOW window) {
    if (!window || !window->m_isMapped || !window->m_xdgSurface
        || (window->m_class != "org.gnome.Console" && window->m_class != "kgx"
            && window->m_class != "org.gnome.Calculator" && window->m_class != "gnome-calculator"
            && window->m_class != "org.gnome.TextEditor" && window->m_class != "gnome-text-editor"
            && window->m_class != "org.gnome.Calendar" && window->m_class != "gnome-calendar"
            && window->m_class != "org.gnome.clocks" && window->m_class != "org.gnome.Clocks" && window->m_class != "gnome-clocks"
            && window->m_class != "org.gnome.Contacts" && window->m_class != "gnome-contacts"
            && window->m_class != "org.gnome.Maps" && window->m_class != "gnome-maps"
            && window->m_class != "org.gnome.Loupe" && window->m_class != "loupe"
            && window->m_class != "org.gnome.Weather" && window->m_class != "gnome-weather")
        || entries.contains(window.get()))
        return;
    PHLWINDOWREF weak = window;
    Entry entry{.window = weak};
    entry.state = window->m_xdgSurface->m_toplevel->m_events.stateChanged.listen([weak] {
        const auto w = weak.lock();
        if (!w || !w->m_isMapped || w->isHidden() || !w->m_xdgSurface
            || !w->m_xdgSurface->m_toplevel->m_state.requestsMinimize.value_or(false))
            return;
        // Address the requesting window, independent of which app has focus by
        // the time the async command runs. Reuse Genie/Scale and Dock snapshots.
        Config::Supplementary::executor()->spawnRaw(
            std::format("qs -c MacShell ipc call minimize addr 0x{:x}", reinterpret_cast<uintptr_t>(w.get())));
        ++forwarded;
        status();
    });
    entries.emplace(window.get(), std::move(entry));
    advertise(window, true);
    status();
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("MacShell native minimize: rebuild for this Hyprland version");
    opened = Event::bus()->m_events.window.open.listen(attach);
    changedClass = Event::bus()->m_events.window.class_.listen(attach);
    closed = Event::bus()->m_events.window.close.listen([](PHLWINDOW w) {
        entries.erase(w.get()); status();
    });
    for (const auto& window : Desktop::viewState()->windows()) attach(window);
    status();
    return {"macshell-native-minimize", "Connect native GNOME minimize buttons to MacShell", "MacShell", "1.3"};
}
APICALL EXPORT void PLUGIN_EXIT() {
    opened.reset(); closed.reset(); changedClass.reset();
    for (const auto& [_, entry] : entries) advertise(entry.window.lock(), false);
    entries.clear();
}
