#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#if __has_include(<hyprland/src/desktop/view/window/Window.hpp>)
#define MACSHELL_WINDOW_BACKEND_API 1
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowMetadata.hpp>
#else
#include <hyprland/src/desktop/view/Window.hpp>
#endif
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
static size_t capabilityUpdates = 0;

static SP<CXDGSurfaceResource> xdgSurface(PHLWINDOW window) {
    if (!window) return nullptr;
#ifdef MACSHELL_WINDOW_BACKEND_API
    const auto surface = window->backend().surface();
    if (!surface || !surface->m_role || surface->m_role->role() != SURFACE_ROLE_XDG_SHELL) return nullptr;
    return static_cast<CXDGSurfaceRole*>(surface->m_role.get())->m_xdgSurface.lock();
#else
    return window->m_xdgSurface;
#endif
}

static bool isMapped(PHLWINDOW window) {
#ifdef MACSHELL_WINDOW_BACKEND_API
    return window && window->mapped();
#else
    return window && window->m_isMapped;
#endif
}

static std::string appID(PHLWINDOW window) {
#ifdef MACSHELL_WINDOW_BACKEND_API
    return window->metadata().appID();
#else
    return window->m_class;
#endif
}

static void status() {
    if (const auto home = std::getenv("HOME")) {
        std::ofstream out(std::string(home) + "/.cache/macshell/native-minimize.status");
        out << "active " << __hyprland_api_get_hash() << "\nattached " << entries.size()
            << "\nforwarded " << forwarded << "\ncapability-updates " << capabilityUpdates << "\nversion 1.5\n";
    }
}

struct CapabilityUpdate { PHLWINDOW window; bool enabled; };
static wl_iterator_result updateResource(wl_resource* resource, void* data) {
    auto& update = *static_cast<CapabilityUpdate*>(data);
    if (std::strcmp(wl_resource_get_class(resource), "xdg_toplevel") != 0
        || wl_resource_get_version(resource) < 5)
        return WL_ITERATOR_CONTINUE;
    const auto top = CXDGToplevelResource::fromResource(resource);
    const auto owner = xdgSurface(update.window);
    // The backend owns the association in 0.57. Compare the actual XDG role;
    // the legacy toplevel m_window back-reference need not be populated.
    if (!top || !owner || top != owner->m_toplevel)
        return WL_ITERATOR_CONTINUE;
    // Hyprland supports maximize/fullscreen; MacShell supplies minimize.
    uint32_t values[] = {XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE,
                         XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN,
                         XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE};
    wl_array caps{.size = sizeof(uint32_t) * (update.enabled ? 3u : 2u),
                  .alloc = sizeof(values), .data = values};
    static_cast<CXdgToplevel*>(wl_resource_get_user_data(resource))->sendWmCapabilities(&caps);
    ++capabilityUpdates;
    if (const auto surface = xdgSurface(update.window)) surface->scheduleConfigure();
    return WL_ITERATOR_STOP;
}

static void advertise(PHLWINDOW window, bool enabled) {
    if (!window || !xdgSurface(window) || !window->wlSurface()->resource()) return;
    CapabilityUpdate update{window, enabled};
    wl_client_for_each_resource(window->wlSurface()->resource()->client(), updateResource, &update);
}

static void forwardMinimize(PHLWINDOW w) {
    if (!isMapped(w) || w->isHidden() || !xdgSurface(w)) return;
    // Address the requesting window, independent of which app has focus by
    // the time the async command runs. Reuse Genie/Scale and Dock snapshots.
    Config::Supplementary::executor()->spawnRaw(
        std::format("qs -c MacShell ipc call minimize addr 0x{:x}", reinterpret_cast<uintptr_t>(w.get())));
    ++forwarded;
    status();
}

static void attach(PHLWINDOW window) {
    if (!isMapped(window) || !xdgSurface(window) || entries.contains(window.get())) return;
    const auto id = appID(window);
    if (id != "org.gnome.Console" && id != "kgx"
        && id != "org.gnome.Calculator" && id != "gnome-calculator"
        && id != "org.gnome.TextEditor" && id != "gnome-text-editor"
        && id != "org.gnome.Calendar" && id != "gnome-calendar"
        && id != "org.gnome.clocks" && id != "org.gnome.Clocks" && id != "gnome-clocks"
        && id != "org.gnome.Contacts" && id != "gnome-contacts"
        && id != "org.gnome.Maps" && id != "gnome-maps"
        && id != "org.gnome.Loupe" && id != "loupe"
        && id != "org.gnome.Weather" && id != "gnome-weather") return;
    PHLWINDOWREF weak = window;
    Entry entry{.window = weak};
#ifdef MACSHELL_WINDOW_BACKEND_API
    // Hyprland 0.57 forwards client state requests through the window backend.
    entry.state = window->backend().m_events.stateRequest.listen([weak](Desktop::View::SBackendStateRequest request) {
        if (request.minimized.value_or(false)) forwardMinimize(weak.lock());
    });
#else
    entry.state = xdgSurface(window)->m_toplevel->m_events.stateChanged.listen([weak] {
        const auto w = weak.lock();
        const auto surface = xdgSurface(w);
        if (surface && surface->m_toplevel->m_state.requestsMinimize.value_or(false)) forwardMinimize(w);
    });
#endif
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
    return {"macshell-native-minimize", "Connect native GNOME minimize buttons to MacShell", "MacShell", "1.5"};
}
APICALL EXPORT void PLUGIN_EXIT() {
    opened.reset(); closed.reset(); changedClass.reset();
    for (const auto& [_, entry] : entries) advertise(entry.window.lock(), false);
    entries.clear();
}
