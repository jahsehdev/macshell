#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/view/window/WindowMetadata.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/decorations/IHyprWindowDecoration.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/config/supplementary/executor/Executor.hpp>
#include <linux/input-event-codes.h>
#include <array>
#include <cstdlib>
#include <fstream>
#include <format>
#include <stdexcept>
#include <unordered_map>
#include "policy.hpp"

namespace Policy = MacShell::WindowPolicy;
static HANDLE pluginHandle;
static unsigned cascadeIndex = 0;
static bool dark = false;
static std::string assets;
static std::array<std::array<SP<Render::ITexture>, 3>, 3> textures;
static CHyprSignalListener opened, closed, rulesChanged, classChanged, reloaded, pointerMoved, fullscreenChanged;

static bool normalWindow(PHLWINDOW w) {
    return Policy::normalWindow(w, w && (w->m_state & Desktop::View::WINDOW_STATE_PINNED));
}

static bool needsFrame(PHLWINDOW w) {
    if (!normalWindow(w)) return false;
    const auto& tags = w->m_ruleApplicator->m_tagKeeper;
    return !Policy::nativeControls(w->metadata().appID(), w->metadata().title(),
        tags.isTagged("macshell-native-controls"), tags.isTagged("macshell-force-controls"));
}

static void readTheme() {
    const std::string home = std::getenv("HOME") ? std::getenv("HOME") : "";
    const std::string config = std::getenv("XDG_CONFIG_HOME") ? std::getenv("XDG_CONFIG_HOME") : home + "/.config";
    assets = config + "/macshell/window-controls/";
    std::ifstream settings(config + "/gtk-3.0/settings.ini");
    dark = false;
    for (std::string line; std::getline(settings, line);)
        if (line == "gtk-application-prefer-dark-theme=1" || line.find("gtk-theme-name=MacTahoe-Dark") == 0) dark = true;
    for (auto& states : textures) for (auto& texture : states) texture.reset();
}

class CWindowFrame : public IHyprWindowDecoration {
  public:
    explicit CWindowFrame(PHLWINDOW w) : IHyprWindowDecoration(w) {}
    int height() {
        const auto w = owningWindow();
        if (!w) return 0;
        const auto modes = Fullscreen::controller()->getFullscreenModes(w);
        return modes.internal == Fullscreen::FSMODE_FULLSCREEN || modes.client == Fullscreen::FSMODE_FULLSCREEN ? 0 : 34;
    }
    SDecorationPositioningInfo getPositioningInfo() override {
        return {.policy = DECORATION_POSITION_STICKY, .edges = DECORATION_EDGE_TOP,
                .priority = 100, .desiredExtents = {{0, height()}, {0, 0}}, .reserved = true};
    }
    void onPositioningReply(const SDecorationPositioningReply& reply) override { assigned = reply.assignedGeometry; }
    eDecorationType getDecorationType() override { return DECORATION_CUSTOM; }
    eDecorationLayer getDecorationLayer() override { return DECORATION_LAYER_UNDER; }
    uint64_t getDecorationFlags() override { return DECORATION_ALLOWS_MOUSE_INPUT | DECORATION_PART_OF_MAIN_WINDOW; }
    std::string getDisplayName() override { return "MacShell traffic lights"; }
    void updateWindow(PHLWINDOW) override {
        const int next = height();
        if (lastHeight != next) { lastHeight = next; g_pDecorationPositioner->repositionDeco(this); }
        damageEntire();
    }
    void damageEntire() override { if (auto w = owningWindow()) g_pHyprRenderer->damageWindow(w); }

    CBox box() {
        const auto w = owningWindow();
        if (!w) return {};
        auto result = assigned;
        result.translate(g_pDecorationPositioner->getEdgeDefinedPoint(DECORATION_EDGE_TOP, w));
        return result;
    }

    bool visible() {
        const auto w = owningWindow();
        if (!w || !needsFrame(w) || w->isHidden()) return false;
        const auto modes = Fullscreen::controller()->getFullscreenModes(w);
        return modes.internal != Fullscreen::FSMODE_FULLSCREEN && modes.client != Fullscreen::FSMODE_FULLSCREEN;
    }

    void draw(Render::CRenderContext& ctx, PHLMONITOR monitor, float const& alpha,
              const Render::SWindowRenderPresentation& presentation) override {
        if (!visible()) return;
        const auto w = owningWindow();
        auto bar = box();
        bar.translate(presentation.workspaceOffset + presentation.floatingOffset - monitor->m_position);
        bar.scale(monitor->m_scale);
        auto background = bar;
        const int rounding = std::round(w->presentation().rounding() * monitor->m_scale);
        // Fill underneath the client's rounded top corners so the reserved
        // title row joins the app without transparent notches at the seam.
        background.h += 2 * rounding;
        CRectPassElement::SRectData data;
        data.box = background;
        data.clipBox = bar;
        data.clipBox.h += rounding;
        data.color = CHyprColor(dark ? 0xff252527 : 0xffefeff0);
        data.color.a *= alpha;
        data.round = rounding;
        data.roundingPower = w->presentation().roundingPower();
        data.workspacePresentation = presentation;
        g_pHyprRenderer->addPassElement(ctx, makeUnique<CRectPassElement>(data));
        const bool active = Desktop::focusState()->isWindowActive(w);
        const std::array<std::string, 3> kinds = {"close", "minimize", "maximize"};
        for (int i = 0; i < 3; ++i) {
            const int state = hovered == i ? 1 : active ? 0 : 2;
            auto& texture = textures[i][state];
            if (!texture) texture = g_pHyprRenderer->loadAsset(assets + (dark ? "dark/" : "light/")
                + "titlebutton-" + kinds[i] + (state == 1 ? "-hover" : state == 2 ? "-backdrop" : "")
                + (dark ? "-dark" : "") + "@2.png");
            if (!texture) continue;
            CTexPassElement::SRenderData image;
            image.tex = texture;
            image.box = {bar.x + (13 + i * 24) * monitor->m_scale, bar.y + 9 * monitor->m_scale,
                         16 * monitor->m_scale, 16 * monitor->m_scale};
            image.a = alpha;
            image.workspacePresentation = presentation;
            g_pHyprRenderer->addPassElement(ctx, makeUnique<CTexPassElement>(image));
        }
    }

    void pointerLeave(const Vector2D& point) {
        if (hovered >= 0 && !box().containsPoint(point)) { hovered = -1; pressed = -1; damageEntire(); }
    }

    bool onInputOnDeco(eInputType type, const Vector2D& point, std::any payload) override {
        if (!visible()) return false;
        const auto bounds = box();
        if (!bounds.containsPoint(point)) { hovered = -1; pressed = -1; damageEntire(); return false; }
        const int hit = Policy::buttonAt(point.x - bounds.x, point.y - bounds.y, bounds.h);
        if (type == INPUT_TYPE_MOTION) { if (hovered != hit) { hovered = hit; damageEntire(); } return true; }
        if (type != INPUT_TYPE_BUTTON || payload.type() != typeid(IPointer::SButtonEvent)) return false;
        const auto event = std::any_cast<IPointer::SButtonEvent>(payload);
        if (event.button != BTN_LEFT) return false;
        const auto w = owningWindow();
        if (!w) return false;
        if (event.state == WL_POINTER_BUTTON_STATE_PRESSED) {
            pressed = hit;
            Desktop::focusState()->fullWindowFocus(w, Desktop::FOCUS_REASON_CLICK_DOWN);
            if (hit < 0) g_layoutManager->dragController()->dragBegin(w->layoutTarget(), MBIND_MOVE, std::nullopt, true);
        } else {
            const int action = pressed;
            pressed = -1;
            if (action < 0 || action != hit) return true;
            if (action == 0) w->backend().close();
            else if (action == 1) Config::Supplementary::executor()->spawn(
                std::format("qs -c MacShell ipc call minimize addr 0x{:x}", reinterpret_cast<uintptr_t>(w.get())));
            else {
                const auto modes = Fullscreen::controller()->getFullscreenModes(w);
                const auto mode = modes.internal == Fullscreen::FSMODE_MAXIMIZED || modes.client == Fullscreen::FSMODE_MAXIMIZED
                    ? Fullscreen::FSMODE_NONE : Fullscreen::FSMODE_MAXIMIZED;
                Fullscreen::controller()->setFullscreenMode(w, mode, mode);
            }
        }
        return true;
    }
  private:
    CBox assigned;
    int hovered = -1, pressed = -1, lastHeight = -1;
};

struct Entry { PHLWINDOWREF window; SP<CWindowFrame> frame; SP<CEventLoopTimer> initial; };
static std::unordered_map<Desktop::View::CWindow*, Entry> entries;

static void reconcile(PHLWINDOW w) {
    if (!w) return;
    auto found = entries.find(w.get());
    const bool wanted = needsFrame(w);
    if (!wanted && found != entries.end() && found->second.frame) {
        HyprlandAPI::removeWindowDecoration(pluginHandle, found->second.frame.get());
        found->second.frame.reset();
    } else if (wanted && (found == entries.end() || !found->second.frame)) {
        auto& entry = entries[w.get()]; entry.window = w;
        entry.frame = makeShared<CWindowFrame>(w);
        HyprlandAPI::addWindowDecoration(pluginHandle, w, entry.frame);
    }
}

static void initialSize(PHLWINDOW w) {
    if (!normalWindow(w) || w->isHidden() || !w->m_monitor || !w->layoutTarget() || !w->layoutTarget()->floating()) return;
    const auto traits = w->backend().traits();
    const auto hints = w->backend().geometryHints(Desktop::View::eBackendState::BACKEND_STATE_CURRENT);
    if (w->backend().parent() || traits.transient || traits.modal) return;
    if (hints.minSize && hints.maxSize && hints.minSize == hints.maxSize) return;
    auto modes = Fullscreen::controller()->getFullscreenModes(w);
    if (modes.internal == Fullscreen::FSMODE_FULLSCREEN || modes.client == Fullscreen::FSMODE_FULLSCREEN) return;
    // The initial placement happens once. Subsequent user moves, Zoom, restore,
    // focus changes and rule refreshes must never reset a window's geometry.
    if (modes.internal != Fullscreen::FSMODE_NONE || modes.client != Fullscreen::FSMODE_NONE)
        Fullscreen::controller()->setFullscreenMode(w, Fullscreen::FSMODE_NONE, Fullscreen::FSMODE_NONE);
    const auto area = w->m_monitor->logicalBoxMinusReserved();
    const auto extents = w->getWindowExtentsUnified(Desktop::View::RESERVED_EXTENTS);
    const auto min = w->layoutTarget()->minSize().value_or(Vector2D{});
    const auto max = w->layoutTarget()->maxSize().value_or(Vector2D{});
    const auto rect = Policy::initialBounds({area.x, area.y, area.w, area.h},
        {extents.topLeft.x, extents.topLeft.y, extents.bottomRight.x, extents.bottomRight.y},
        {0, 0, min.x, min.y}, {0, 0, max.x, max.y}, cascadeIndex++);
    w->layoutTarget()->setPositionGlobal(CBox{rect.x, rect.y, rect.w, rect.h});
    w->layoutTarget()->rememberFloatingSize({rect.w, rect.h});
}

static void onOpen(PHLWINDOW w) {
    reconcile(w);
    if (!normalWindow(w)) return;
    auto& entry = entries[w.get()]; entry.window = w;
    const PHLWINDOWREF weak = w;
    entry.initial = makeShared<CEventLoopTimer>(std::chrono::milliseconds(150),
        [weak](SP<CEventLoopTimer>, void*) { if (const auto current = weak.lock()) initialSize(current); }, nullptr);
    g_pEventLoopManager->addTimer(entry.initial);
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("MacShell window policy: rebuild for this Hyprland version");
    pluginHandle = handle;
    readTheme();
    opened = Event::bus()->m_events.window.openLate.listen(onOpen);
    rulesChanged = Event::bus()->m_events.window.updateRules.listen(reconcile);
    classChanged = Event::bus()->m_events.window.class_.listen(reconcile);
    pointerMoved = Event::bus()->m_events.input.mouse.move.listen([](Vector2D point, Event::SCallbackInfo&) {
        for (auto& [_, entry] : entries) if (entry.frame) entry.frame->pointerLeave(point);
    });
    fullscreenChanged = Event::bus()->m_events.window.fullscreen.listen([](PHLWINDOW w) {
        const auto it = entries.find(w.get());
        if (it != entries.end() && it->second.frame) it->second.frame->updateWindow(w);
    });
    closed = Event::bus()->m_events.window.close.listen([](PHLWINDOW w) {
        const auto it = entries.find(w.get());
        if (it != entries.end() && it->second.initial) g_pEventLoopManager->removeTimer(it->second.initial);
        entries.erase(w.get());
    });
    reloaded = Event::bus()->m_events.config.reloaded.listen([] {
        readTheme();
        for (const auto& w : Desktop::viewState()->windows()) { reconcile(w); g_pHyprRenderer->damageWindow(w); }
    });
    // Loading/reloading decorates existing clients without moving their work.
    for (const auto& w : Desktop::viewState()->windows()) reconcile(w);
    // Hyprland 0.57 retains addDispatcherV2 as a no-op compatibility stub.
    // Plugin actions must use the Lua callback API and hyprctl eval instead.
    if (!HyprlandAPI::addLuaFunction(handle, "macshell_window_policy", "normalize", [](lua_State*) -> int {
        for (const auto& w : Desktop::viewState()->windows()) initialSize(w);
        return 0;
    })) throw std::runtime_error("MacShell window policy: could not register Lua normalization callback");
    return {"macshell-window-policy", "Default app geometry and fallback MacShell traffic lights", "MacShell", "1.3"};
}
APICALL EXPORT void PLUGIN_EXIT() {
    opened.reset(); closed.reset(); rulesChanged.reset(); classChanged.reset(); reloaded.reset();
    pointerMoved.reset(); fullscreenChanged.reset();
    for (auto& [_, entry] : entries) {
        if (entry.initial) g_pEventLoopManager->removeTimer(entry.initial);
        if (entry.frame) HyprlandAPI::removeWindowDecoration(pluginHandle, entry.frame.get());
    }
    entries.clear();
    for (auto& states : textures) for (auto& texture : states) texture.reset();
}
