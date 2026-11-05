#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/config/values/types/FloatValue.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <optional>
#include <stdexcept>
#include <type_traits>
#include "shake.hpp"

using Manager = Pointer::CPointerManager;
using Image = Manager::SCursorImageData;
using ImageForMonitor = Image& (*)(Manager*, PHLMONITOR);
using RenderCursor = void (*)(Manager*, Render::CRenderContext&, PHLMONITOR, const Time::steady_tp&,
                              CRegion&, std::optional<Vector2D>, bool, bool);
using RenderMethod = void (Manager::*)(Render::CRenderContext&, PHLMONITOR, const Time::steady_tp&,
                                      CRegion&, std::optional<Vector2D>, bool, bool);
static_assert(std::is_same_v<decltype(&Manager::renderSoftwareCursorsFor), RenderMethod>);

static CFunctionHook* renderHook = nullptr;
static ImageForMonitor imageForMonitor = nullptr;
static CHyprSignalListener moved, button, reloaded;
static SP<CEventLoopTimer> timer;
static SP<Config::Values::CIntValue> enabled;
static SP<Config::Values::CFloatValue> maximum;
static MacShell::Shake::Detector detector;
static double magnification = 1.0, lastShake = -1, lastTick = 0;
static std::vector<PHLMONITORREF> softwareLocks;
static std::vector<CBox> previousBoxes;

static double seconds() {
    return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

static bool blocked() {
    return !enabled->value() || g_pInputManager->isLocked() || g_pInputManager->isConstrained()
        || g_pInputManager->hasHeldButtons();
}

static void lockMonitors() {
    for (const auto& monitor : State::monitorState()->monitors()) {
        if (monitor->isMirror() || !monitor->m_enabled) continue;
        if (std::ranges::any_of(softwareLocks, [&](const auto& weak) { return weak.lock() == monitor; })) continue;
        Pointer::mgr()->lockSoftwareForMonitor(monitor);
        softwareLocks.emplace_back(monitor);
    }
}

static void unlockMonitors() {
    for (const auto& weak : softwareLocks)
        if (const auto monitor = weak.lock())
            Pointer::mgr()->unlockSoftwareForMonitor(monitor);
    softwareLocks.clear();
}

// Damage both the former and new enlarged bounds, including after a warp or
// shape change. No full-screen repaint and no polling while the effect is idle.
static void damage() {
    for (const auto& box : previousBoxes) g_pHyprRenderer->damageBox(box);
    previousBoxes.clear();
    if (magnification <= 1.0) return;
    const auto pointer = Pointer::mgr()->position();
    for (const auto& monitor : State::monitorState()->monitors()) {
        if (!monitor->m_enabled || monitor->isMirror()) continue;
        const auto& image = imageForMonitor(Pointer::mgr().get(), monitor);
        const auto size = image.logicalSize();
        const auto box = MacShell::Shake::geometry({pointer.x, pointer.y}, {image.hotspot.x, image.hotspot.y},
                                                   {size.x, size.y}, magnification);
        CBox bounds{box.position.x, box.position.y, box.size.x, box.size.y};
        bounds.expand(4);
        g_pHyprRenderer->damageBox(bounds);
        previousBoxes.push_back(bounds);
    }
}

static void resetEffect() {
    detector.reset();
    lastShake = -1;
    magnification = 1.0;
    damage();
    unlockMonitors();
    if (timer) timer->updateTimeout(std::nullopt);
}

// Let Hyprland draw the actual themed/client cursor, with its original hiding,
// surface feedback, screen capture and texture lifetime rules. Only the image's
// geometry is temporarily enlarged; the scale used to select a HiDPI asset stays
// intact. Supplying monitor-local position avoids the normal-size cached box.
static void renderCursor(Manager* manager, Render::CRenderContext& ctx, PHLMONITOR monitor,
                         const Time::steady_tp& now, CRegion& region, std::optional<Vector2D> position,
                         bool screencopy, bool forceRender) {
    const auto original = reinterpret_cast<RenderCursor>(renderHook->m_original);
    if (magnification <= 1.0 || blocked()) {
        original(manager, ctx, monitor, now, region, position, screencopy, forceRender);
        return;
    }
    auto& image = imageForMonitor(manager, monitor);
    const auto size = image.size, hotspot = image.hotspot;
    const Hyprutils::Utils::CScopeGuard restore([&] { image.size = size; image.hotspot = hotspot; });
    image.size = size * magnification;
    image.hotspot = hotspot * magnification;
    original(manager, ctx, monitor, now, region,
             position.value_or(manager->position() - monitor->m_position), screencopy, forceRender);
}

static void animate(SP<CEventLoopTimer> self, void*) {
    if (blocked()) { resetEffect(); return; }
    const double now = seconds();
    magnification = MacShell::Shake::animate(magnification, now - lastTick, now - lastShake < 0.10, maximum->value());
    lastTick = now;
    if (magnification > 1.0) lockMonitors();
    damage();
    if (magnification == 1.0) { unlockMonitors(); return; }
    self->updateTimeout(std::chrono::milliseconds(16));
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("MacShell shake to find: rebuild for the running Hyprland version");

    // Hyprland searches raw mangled symbols, so the query must be an unqualified
    // method name. Then match the complete ABI to reject unrelated overloads.
    const std::string renderSymbol = "_ZN7Pointer15CPointerManager24renderSoftwareCursorsForERN6Render14CRenderContextEN9Hyprutils6Memory14CSharedPointerIN7Monitor8CMonitorEEERKNSt6chrono10time_pointINSA_3_V212steady_clockENSA_8durationIlSt5ratioILl1ELl1000000000EEEEEERNS4_4Math7CRegionESt8optionalINSL_8Vector2DEEbb";
    const std::string imageSymbol = "_ZN7Pointer15CPointerManager21cursorImageForMonitorEN9Hyprutils6Memory14CSharedPointerIN7Monitor8CMonitorEEE";
    void* renderAddress = nullptr;
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "renderSoftwareCursorsFor"))
        if (match.signature == renderSymbol) renderAddress = match.address;
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "cursorImageForMonitor"))
        if (match.signature == imageSymbol) imageForMonitor = reinterpret_cast<ImageForMonitor>(match.address);
    if (!renderAddress || !imageForMonitor)
        throw std::runtime_error("MacShell shake to find: compatible cursor rendering API unavailable");

    enabled = makeShared<Config::Values::CIntValue>("plugin:macshell_shake:enabled", "Shake pointer to locate", 1,
                Config::Values::SIntValueOptions{.min = 0, .max = 1});
    maximum = makeShared<Config::Values::CFloatValue>("plugin:macshell_shake:max_scale", "Maximum pointer magnification", 4.F,
                Config::Values::SFloatValueOptions{.min = 1.F, .max = 8.F});
    HyprlandAPI::addConfigValueV2(handle, enabled);
    HyprlandAPI::addConfigValueV2(handle, maximum);
    renderHook = HyprlandAPI::createFunctionHook(handle, renderAddress, reinterpret_cast<void*>(&renderCursor));
    if (!renderHook || !renderHook->hook())
        throw std::runtime_error("MacShell shake to find: cursor hook unavailable (requires x86_64)");

    timer = makeShared<CEventLoopTimer>(std::nullopt, animate, nullptr);
    g_pEventLoopManager->addTimer(timer);
    moved = Event::bus()->m_events.input.mouse.move.listen([](Vector2D point, Event::SCallbackInfo& info) {
        if (info.cancelled || blocked()) { resetEffect(); return; }
        const double now = seconds();
        if (detector.move(now, {point.x, point.y})) {
            lastShake = now;
            if (!timer->armed()) {
                lastTick = now;
                timer->updateTimeout(std::chrono::milliseconds(1));
            }
        }
        if (magnification > 1.0) damage();
    });
    button = Event::bus()->m_events.input.mouse.button.listen([](const IPointer::SButtonEvent& event, Event::SCallbackInfo&) {
        if (event.state == WL_POINTER_BUTTON_STATE_PRESSED) resetEffect();
    });
    reloaded = Event::bus()->m_events.config.reloaded.listen([] { resetEffect(); });
    if (const auto home = std::getenv("HOME")) {
        const auto directory = std::filesystem::path(home) / ".cache/macshell";
        std::error_code error;
        std::filesystem::create_directories(directory, error);
        std::ofstream(directory / "shake-to-find.status") << "active " << __hyprland_api_get_hash() << "\nversion 1.1\n";
    }
    return {"macshell-shake-to-find", "Enlarge the actual cursor when shaken, then smoothly restore it", "MacShell", "1.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    moved.reset(); button.reset(); reloaded.reset();
    resetEffect();
    if (timer) { timer->cancel(); g_pEventLoopManager->removeTimer(timer); timer.reset(); }
    if (const auto home = std::getenv("HOME"))
        std::ofstream(std::string(home) + "/.cache/macshell/shake-to-find.status") << "inactive\n";
}
