#include "pty.hpp"
#include <gtk/gtk.h>
#include <webkit2/webkit2.h>
#include <json-glib/json-glib.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <map>
#include <memory>
#include <pwd.h>
#include <regex>
#include <string>
#include <unistd.h>

namespace fs = std::filesystem;
static std::string stringValue(JsonObject* object, const char* key, const std::string& fallback = "") {
    auto* node = json_object_get_member(object, key);
    return node && JSON_NODE_HOLDS_VALUE(node) && json_node_get_value_type(node) == G_TYPE_STRING
        ? json_node_get_string(node) : fallback;
}
static double numberValue(JsonObject* object, const char* key, double fallback) {
    auto* node = json_object_get_member(object, key);
    if (!node || !JSON_NODE_HOLDS_VALUE(node)) return fallback;
    auto type = json_node_get_value_type(node);
    if (type != G_TYPE_INT64 && type != G_TYPE_DOUBLE) return fallback;
    auto value = json_node_get_double(node);
    return std::isfinite(value) ? value : fallback;
}
static bool boolValue(JsonObject* object, const char* key, bool fallback) {
    auto* node = json_object_get_member(object, key);
    return node && JSON_NODE_HOLDS_VALUE(node) && json_node_get_value_type(node) == G_TYPE_BOOLEAN
        ? json_node_get_boolean(node) : fallback;
}
static JsonObject* parseObject(const std::string& text) {
    auto* parser = json_parser_new();
    JsonObject* result = nullptr;
    if (json_parser_load_from_data(parser, text.data(), text.size(), nullptr)) {
        auto* node = json_parser_get_root(parser);
        if (node && JSON_NODE_HOLDS_OBJECT(node)) result = json_object_ref(json_node_get_object(node));
    }
    g_object_unref(parser);
    return result;
}
static std::string json(JsonObject* object, bool pretty = false) {
    auto* node = json_node_new(JSON_NODE_OBJECT);
    json_node_set_object(node, object);
    auto* generator = json_generator_new();
    json_generator_set_root(generator, node);
    json_generator_set_pretty(generator, pretty);
    gchar* text = json_generator_to_data(generator, nullptr);
    std::string result(text);
    g_free(text); g_object_unref(generator); json_node_free(node);
    return result;
}
static std::string readFile(const fs::path& path) {
    gchar* contents = nullptr; gsize length = 0;
    if (!g_file_get_contents(path.c_str(), &contents, &length, nullptr)) return "";
    std::string result(contents, length); g_free(contents);
    return result;
}
static std::string loginShell() {
    auto* entry = getpwuid(getuid());
    return entry && entry->pw_shell && *entry->pw_shell ? entry->pw_shell : "/bin/bash";
}
static JsonObject* sanitizeConfig(JsonObject* input) {
    auto* output = json_object_new();
    const std::map<std::string, std::pair<double, std::pair<double,double>>> numbers = {
        {"fontSize", {13, {9, 28}}}, {"lineHeight", {1.15, {1, 1.8}}},
        {"opacity", {1, {0.65, 1}}}, {"padding", {4, {4, 40}}},
        {"radius", {5, {0, 28}}}, {"scrollback", {10000, {1000, 100000}}},
    };
    for (const auto& [key, value] : numbers)
        json_object_set_double_member(output, key.c_str(), std::clamp(numberValue(input, key.c_str(), value.first), value.second.first, value.second.second));
    const std::map<std::string, std::vector<std::string>> enums = {
        {"theme", {"dark", "light", "auto"}},
        {"palette", {"classic", "tahoe", "ocean", "forest", "rose", "amber"}},
        {"cursorStyle", {"block", "bar", "underline"}},
    };
    for (const auto& [key, values] : enums) {
        auto value = stringValue(input, key.c_str(), values[0]);
        if (std::find(values.begin(), values.end(), value) == values.end()) value = values[0];
        json_object_set_string_member(output, key.c_str(), value.c_str());
    }
    auto font = stringValue(input, "fontFamily", "SF Mono");
    if (font.empty() || font.size() > 100 || font.find_first_of("\r\n") != std::string::npos) font = "SF Mono";
    json_object_set_string_member(output, "fontFamily", font.c_str());
    auto shell = stringValue(input, "shell", loginShell());
    if (shell.empty() || shell[0] != '/' || shell.size() > 4096 || access(shell.c_str(), X_OK)) shell = loginShell();
    json_object_set_string_member(output, "shell", shell.c_str());
    json_object_set_boolean_member(output, "cursorBlink", boolValue(input, "cursorBlink", true));
    json_object_set_boolean_member(output, "showStatusBar", boolValue(input, "showStatusBar", false));
    return output;
}

class Application {
public:
    Application(fs::path web, fs::path executable, std::string cwd, std::vector<std::string> command, bool dev)
        : web_(std::move(web)), executable_(std::move(executable)), initialCwd_(std::move(cwd)), command_(std::move(command)) {
        configDir_ = fs::path(g_get_user_config_dir()) / "tahoe-terminal";
        g_mkdir_with_parents(configDir_.c_str(), 0700);
        config_ = nullptr;
        loadConfig();
        if (!fs::exists(configDir_ / "settings.json")) saveConfig();
        if (!fs::exists(configDir_ / "custom.css")) {
            const char* example = "/* Tahoe Terminal: your live UI stylesheet. Save to apply.\n"
                "   Examples:\n   :root { --accent: #5f91ff; }\n"
                "   .titlebar { height: 58px; }\n   .tab { border-radius: 12px; }\n"
                "   .statusbar { display: none; }\n*/\n";
            g_file_set_contents((configDir_ / "custom.css").c_str(), example, -1, nullptr);
        }
        window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
        gtk_window_set_title(GTK_WINDOW(window_), "Tahoe Terminal");
        gtk_window_set_default_size(GTK_WINDOW(window_), 800, 540);
        gtk_window_set_decorated(GTK_WINDOW(window_), FALSE);
        gtk_widget_set_app_paintable(window_, TRUE);
        if (auto* visual = gdk_screen_get_rgba_visual(gtk_widget_get_screen(window_))) gtk_widget_set_visual(window_, visual);
        GdkGeometry geometry{}; geometry.min_width = 520; geometry.min_height = 320;
        gtk_window_set_geometry_hints(GTK_WINDOW(window_), nullptr, &geometry, GDK_HINT_MIN_SIZE);
        auto* css = gtk_css_provider_new();
        gtk_css_provider_load_from_data(css, "window.tahoe-native { background: transparent; }", -1, nullptr);
        gtk_style_context_add_class(gtk_widget_get_style_context(window_), "tahoe-native");
        gtk_style_context_add_provider_for_screen(gtk_widget_get_screen(window_), GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
        g_object_unref(css);
        auto* context = webkit_web_context_new_ephemeral();
        auto* manager = webkit_user_content_manager_new();
        webkit_user_content_manager_register_script_message_handler(manager, "tahoe");
        g_signal_connect(manager, "script-message-received::tahoe", G_CALLBACK(onMessage), this);
        view_ = WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW, "web-context", context, "user-content-manager", manager, nullptr));
        g_object_unref(manager); g_object_unref(context);
        auto* settings = webkit_web_view_get_settings(view_);
        webkit_settings_set_enable_developer_extras(settings, dev);
        webkit_settings_set_enable_html5_database(settings, FALSE);
        webkit_settings_set_enable_html5_local_storage(settings, FALSE);
        webkit_settings_set_allow_file_access_from_file_urls(settings, FALSE);
        webkit_settings_set_allow_universal_access_from_file_urls(settings, FALSE);
        GdkRGBA transparent{0, 0, 0, 0};
        webkit_web_view_set_background_color(view_, &transparent);
        gtk_container_add(GTK_CONTAINER(window_), GTK_WIDGET(view_));
        gtk_widget_add_events(GTK_WIDGET(view_), GDK_BUTTON_PRESS_MASK | GDK_FOCUS_CHANGE_MASK);
        g_signal_connect(view_, "button-press-event", G_CALLBACK(onButton), this);
        g_signal_connect(view_, "decide-policy", G_CALLBACK(onPolicy), this);
        g_signal_connect(view_, "web-process-terminated", G_CALLBACK(onWebTerminated), this);
        g_signal_connect(window_, "delete-event", G_CALLBACK(onDelete), this);
        g_signal_connect(window_, "focus-in-event", G_CALLBACK(onFocus), this);
        g_signal_connect(window_, "window-state-event", G_CALLBACK(onState), this);
        watchDirectory(configDir_);
        const auto macbar = fs::path(g_get_user_config_dir()) / "macbar";
        if (fs::exists(macbar)) watchDirectory(macbar);
        pollSource_ = g_timeout_add(1000, onPoll, this);
        gchar* uri = g_filename_to_uri((web_ / "index.html").c_str(), nullptr, nullptr);
        startUri_ = uri;
        webkit_web_view_load_uri(view_, uri); g_free(uri);
        gtk_widget_show_all(window_);
        gtk_widget_grab_focus(GTK_WIDGET(view_));
    }
    ~Application() {
        shuttingDown_ = true;
        if (pollSource_) g_source_remove(pollSource_);
        if (reloadSource_) g_source_remove(reloadSource_);
        for (auto* monitor : monitors_) { g_file_monitor_cancel(monitor); g_object_unref(monitor); }
        sessions_.clear();
        json_object_unref(config_);
    }
private:
    fs::path web_, executable_, configDir_;
    std::string initialCwd_, startUri_;
    std::vector<std::string> command_;
    GtkWidget* window_ = nullptr;
    WebKitWebView* view_ = nullptr;
    JsonObject* config_ = nullptr;
    std::map<std::string, std::unique_ptr<PtySession>> sessions_;
    std::map<std::string, std::string> paths_;
    std::vector<GFileMonitor*> monitors_;
    guint pollSource_ = 0, reloadSource_ = 0;
    bool ready_ = false, shuttingDown_ = false, fullscreen_ = false;
    GdkEventButton lastButton_{};

    void emit(JsonObject* event) {
        if (ready_ && !shuttingDown_) {
            auto script = "window.hostEvent(" + json(event) + ");";
            webkit_web_view_evaluate_javascript(view_, script.c_str(), script.size(), nullptr, nullptr, nullptr, nullptr, nullptr);
        }
        json_object_unref(event);
    }
    JsonObject* event(const char* type, const std::string& id = "") {
        auto* object = json_object_new();
        json_object_set_string_member(object, "type", type);
        if (!id.empty()) json_object_set_string_member(object, "id", id.c_str());
        return object;
    }
    void error(const std::string& message, const std::string& id = "") {
        auto* e = event("error", id); json_object_set_string_member(e, "message", message.c_str()); emit(e);
    }
    void loadConfig() {
        auto* input = parseObject(readFile(configDir_ / "settings.json"));
        if (!input && config_) { error("settings.json is invalid. Your last working settings are still active."); return; }
        if (!input) input = json_object_new();
        auto* next = sanitizeConfig(input); json_object_unref(input);
        if (config_) json_object_unref(config_);
        config_ = next;
    }
    void saveConfig() {
        auto data = json(config_, true) + "\n";
        GError* failure = nullptr;
        if (!g_file_set_contents((configDir_ / "settings.json").c_str(), data.data(), data.size(), &failure)) {
            error(failure->message); g_error_free(failure);
        }
    }
    bool systemDark() {
        auto* object = parseObject(readFile(fs::path(g_get_user_config_dir()) / "macbar/settings.json"));
        if (!object) return false;
        bool result = boolValue(object, "darkMode", false); json_object_unref(object); return result;
    }
    void sendConfig(const char* type = "config") {
        auto* e = event(type);
        json_object_set_object_member(e, "config", json_object_ref(config_));
        json_object_set_boolean_member(e, "systemDark", systemDark());
        json_object_set_string_member(e, "customCSS", readFile(configDir_ / "custom.css").c_str());
        json_object_set_string_member(e, "configDir", configDir_.c_str());
        json_object_set_string_member(e, "home", g_get_home_dir());
        json_object_set_string_member(e, "cwd", initialCwd_.c_str());
        emit(e);
    }
    void watchDirectory(const fs::path& path) {
        auto* file = g_file_new_for_path(path.c_str());
        auto* monitor = g_file_monitor_directory(file, G_FILE_MONITOR_WATCH_MOVES, nullptr, nullptr);
        g_object_unref(file);
        if (!monitor) return;
        monitors_.push_back(monitor);
        g_signal_connect(monitor, "changed", G_CALLBACK(+[](GFileMonitor*, GFile*, GFile*, GFileMonitorEvent, gpointer data) {
            auto* app = static_cast<Application*>(data);
            if (app->reloadSource_) g_source_remove(app->reloadSource_);
            app->reloadSource_ = g_timeout_add(150, +[](gpointer d) -> gboolean {
                auto* self = static_cast<Application*>(d); self->reloadSource_ = 0;
                self->loadConfig(); self->sendConfig(); return G_SOURCE_REMOVE;
            }, app);
        }), this);
    }
    bool confirm(const char* title, const char* message) {
        auto* dialog = gtk_message_dialog_new(GTK_WINDOW(window_), GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION, GTK_BUTTONS_NONE, "%s", title);
        gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog), "%s", message);
        gtk_dialog_add_buttons(GTK_DIALOG(dialog), "Cancel", GTK_RESPONSE_CANCEL, "Close", GTK_RESPONSE_ACCEPT, nullptr);
        gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_CANCEL);
        bool result = gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT;
        gtk_widget_destroy(dialog); return result;
    }
    void spawn(JsonObject* request, const std::string& id) {
        if (sessions_.contains(id) || id.size() > 32 || !std::regex_match(id, std::regex("[a-zA-Z0-9-]+"))) return;
        for (auto i = sessions_.begin(); i != sessions_.end();) {
            if (!i->second->alive()) { paths_.erase(i->first); i = sessions_.erase(i); } else ++i;
        }
        if (sessions_.size() >= 32) { error("This window supports up to 32 terminal tabs.", id); return; }
        auto cwd = stringValue(request, "cwd", initialCwd_);
        if (!fs::is_directory(cwd)) cwd = g_get_home_dir();
        auto argv = command_.empty() ? std::vector<std::string>{stringValue(config_, "shell", loginShell()), "-l"} : command_;
        command_.clear();
        auto session = std::make_unique<PtySession>([this,id](const std::string& bytes) {
            gchar* encoded = g_base64_encode(reinterpret_cast<const guchar*>(bytes.data()), bytes.size());
            auto* e = event("output", id); json_object_set_string_member(e, "data", encoded); g_free(encoded); emit(e);
        }, [this,id](int code) {
            auto* e = event("exit", id); json_object_set_int_member(e, "code", code); emit(e);
        });
        std::string failure;
        if (!session->start(argv, cwd, numberValue(request, "cols", 100), numberValue(request, "rows", 28), failure)) {
            error("Cannot start a terminal: " + failure, id); return;
        }
        paths_[id] = cwd; sessions_[id] = std::move(session);
        auto* e = event("opened", id); json_object_set_string_member(e, "cwd", cwd.c_str()); emit(e);
    }
    void handle(JsonObject* request) {
        const auto type = stringValue(request, "type"), id = stringValue(request, "id");
        if (type == "ready") { ready_ = true; sendConfig("init"); return; }
        if (!ready_) return;
        auto found = sessions_.find(id);
        auto* session = found == sessions_.end() ? nullptr : found->second.get();
        if (type == "spawn") spawn(request, id);
        else if (type == "input" && session) {
            auto text = stringValue(request, "data");
            if (text.size() > 6 * 1024 * 1024) return;
            gsize length = 0; guchar* bytes = g_base64_decode(text.c_str(), &length);
            bool accepted = session->write(std::string(reinterpret_cast<char*>(bytes), length)); g_free(bytes);
            if (!accepted) error("The terminal input buffer is full; please paste a smaller amount.", id);
        } else if (type == "ack" && session) session->acknowledge(std::clamp(numberValue(request, "bytes", 0), 0.0, 1024.0 * 1024));
        else if (type == "resize" && session) session->resize(numberValue(request, "cols", 100), numberValue(request, "rows", 28));
        else if (type == "close-tab") {
            if (session && session->busy() && !confirm("Close this terminal?", "A process is still running in this tab. Closing it will end the session.")) return;
            if (session) session->close();
            auto* e = event("closed", id); emit(e);
        } else if (type == "close-window") gtk_window_close(GTK_WINDOW(window_));
        else if (type == "minimize") {
            bool delegated = false;
            if (g_getenv("HYPRLAND_INSTANCE_SIGNATURE") && fs::exists(fs::path(g_get_user_config_dir()) / "quickshell/MacShell/shell.qml")) {
                // Hyprland has no conventional minimized-window list. Use this
                // desktop's existing Dock animation and restore implementation.
                auto* process = g_subprocess_new(GSubprocessFlags(G_SUBPROCESS_FLAGS_STDOUT_SILENCE | G_SUBPROCESS_FLAGS_STDERR_SILENCE),
                    nullptr, "qs", "-c", "MacShell", "ipc", "call", "minimize", "focused", nullptr);
                if (process) { delegated = true; g_object_unref(process); }
            }
            if (!delegated) gtk_window_iconify(GTK_WINDOW(window_));
        }
        else if (type == "maximize") {
            if (gtk_window_is_maximized(GTK_WINDOW(window_))) gtk_window_unmaximize(GTK_WINDOW(window_));
            else gtk_window_maximize(GTK_WINDOW(window_));
        } else if (type == "fullscreen") {
            fullscreen_ = !fullscreen_;
            if (fullscreen_) gtk_window_fullscreen(GTK_WINDOW(window_)); else gtk_window_unfullscreen(GTK_WINDOW(window_));
        } else if (type == "drag" && lastButton_.button == 1) {
            gtk_window_begin_move_drag(GTK_WINDOW(window_), 1, lastButton_.x_root, lastButton_.y_root, lastButton_.time);
        } else if (type == "appearance") {
            g_object_set(gtk_settings_get_default(), "gtk-application-prefer-dark-theme", boolValue(request, "dark", false), nullptr);
        } else if (type == "settings" && json_object_has_member(request, "config")) {
            auto* node = json_object_get_member(request, "config");
            if (JSON_NODE_HOLDS_OBJECT(node)) {
                auto* next = sanitizeConfig(json_node_get_object(node));
                json_object_unref(config_); config_ = next; saveConfig();
            }
        } else if (type == "copy") {
            auto text = stringValue(request, "text");
            gtk_clipboard_set_text(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD), text.data(), text.size());
        } else if (type == "paste") {
            gchar* text = gtk_clipboard_wait_for_text(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD));
            if (text) { auto* e = event("paste", id); json_object_set_string_member(e, "text", text); emit(e); g_free(text); }
        } else if (type == "open-config" || type == "edit-css") {
            auto path = type == "edit-css" ? configDir_ / "custom.css" : configDir_;
            gchar* uri = g_filename_to_uri(path.c_str(), nullptr, nullptr);
            g_app_info_launch_default_for_uri(uri, nullptr, nullptr); g_free(uri);
        } else if (type == "open-link") {
            auto uri = stringValue(request, "uri");
            auto* scheme = g_uri_parse_scheme(uri.c_str());
            if (scheme && (!g_ascii_strcasecmp(scheme, "https") || !g_ascii_strcasecmp(scheme, "http")))
                g_app_info_launch_default_for_uri(uri.c_str(), nullptr, nullptr);
            g_free(scheme);
        } else if (type == "new-window") {
            auto cwd = session ? session->cwd() : initialCwd_;
            gchar* args[] = {const_cast<char*>(executable_.c_str()), const_cast<char*>("--working-directory"), cwd.data(), nullptr};
            g_spawn_async(nullptr, args, nullptr, G_SPAWN_DEFAULT, nullptr, nullptr, nullptr, nullptr);
        }
    }
    static void onMessage(WebKitUserContentManager*, WebKitJavascriptResult* result, gpointer data) {
        gchar* message = jsc_value_to_string(webkit_javascript_result_get_js_value(result));
        if (!message) return;
        if (strlen(message) <= 8 * 1024 * 1024) {
            auto* request = parseObject(message);
            if (request) { static_cast<Application*>(data)->handle(request); json_object_unref(request); }
        }
        g_free(message);
    }
    static gboolean onDelete(GtkWidget*, GdkEvent*, gpointer data) {
        auto* app = static_cast<Application*>(data);
        for (const auto& [id, session] : app->sessions_) {
            if (session->busy() && !app->confirm("Close Tahoe Terminal?", "There are running processes in your terminal tabs. Closing the window will end those sessions.")) return TRUE;
            if (session->busy()) break;
        }
        app->shuttingDown_ = true;
        for (auto& [id, session] : app->sessions_) session->close();
        gtk_main_quit(); return FALSE;
    }
    static gboolean onFocus(GtkWidget*, GdkEventFocus*, gpointer data) {
        auto* app = static_cast<Application*>(data); app->emit(app->event("focus")); return FALSE;
    }
    static gboolean onState(GtkWidget*, GdkEventWindowState* state, gpointer data) {
        auto* app = static_cast<Application*>(data); auto* e = app->event("window-state");
        json_object_set_boolean_member(e, "maximized", state->new_window_state & (GDK_WINDOW_STATE_MAXIMIZED | GDK_WINDOW_STATE_FULLSCREEN));
        app->emit(e); return FALSE;
    }
    static gboolean onButton(GtkWidget*, GdkEventButton* event, gpointer data) {
        auto* app = static_cast<Application*>(data); app->lastButton_ = *event;
        if (event->button != 1 || gtk_window_is_maximized(GTK_WINDOW(app->window_)) || app->fullscreen_) return FALSE;
        int w, h; gtk_window_get_size(GTK_WINDOW(app->window_), &w, &h);
        const bool left=event->x < 5, right=event->x > w-5, top=event->y < 5, bottom=event->y > h-5;
        if (!left && !right && !top && !bottom) return FALSE;
        auto edge = top ? (left ? GDK_WINDOW_EDGE_NORTH_WEST : right ? GDK_WINDOW_EDGE_NORTH_EAST : GDK_WINDOW_EDGE_NORTH)
                  : bottom ? (left ? GDK_WINDOW_EDGE_SOUTH_WEST : right ? GDK_WINDOW_EDGE_SOUTH_EAST : GDK_WINDOW_EDGE_SOUTH)
                  : left ? GDK_WINDOW_EDGE_WEST : GDK_WINDOW_EDGE_EAST;
        gtk_window_begin_resize_drag(GTK_WINDOW(app->window_), edge, 1, event->x_root, event->y_root, event->time); return TRUE;
    }
    static gboolean onPolicy(WebKitWebView*, WebKitPolicyDecision* decision, WebKitPolicyDecisionType type, gpointer data) {
        if (type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION || type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
            auto* navigation = WEBKIT_NAVIGATION_POLICY_DECISION(decision);
            auto* action = webkit_navigation_policy_decision_get_navigation_action(navigation);
            const char* uri = webkit_uri_request_get_uri(webkit_navigation_action_get_request(action));
            auto* app = static_cast<Application*>(data);
            if (!uri || app->startUri_ != uri || type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
                webkit_policy_decision_ignore(decision); return TRUE;
            }
        }
        return FALSE;
    }
    static void onWebTerminated(WebKitWebView*, WebKitWebProcessTerminationReason, gpointer data) {
        auto* app = static_cast<Application*>(data);
        app->ready_ = false;
        auto* dialog = gtk_message_dialog_new(GTK_WINDOW(app->window_), GTK_DIALOG_MODAL, GTK_MESSAGE_ERROR, GTK_BUTTONS_CLOSE,
            "The terminal display process stopped.");
        gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog), "The window will close and end its sessions. You can reopen Tahoe Terminal from the launcher.");
        gtk_dialog_run(GTK_DIALOG(dialog)); gtk_widget_destroy(dialog);
        gtk_window_close(GTK_WINDOW(app->window_));
    }
    static gboolean onPoll(gpointer data) {
        auto* app = static_cast<Application*>(data);
        for (const auto& [id, session] : app->sessions_) {
            if (!session->alive()) continue;
            auto cwd = session->cwd();
            if (cwd == app->paths_[id]) continue;
            app->paths_[id] = cwd;
            auto* e = app->event("cwd", id); json_object_set_string_member(e, "cwd", cwd.c_str()); app->emit(e);
        }
        return G_SOURCE_CONTINUE;
    }
};

int main(int argc, char** argv) {
    g_set_prgname("tahoe-terminal"); g_set_application_name("Tahoe Terminal");
    std::string cwd = fs::current_path();
    std::vector<std::string> command;
    bool dev = false, check = false;
    for (int i = 1; i < argc; ++i) {
        std::string arg(argv[i]);
        if (arg == "--version") { std::cout << "Tahoe Terminal 0.1.0\n"; return 0; }
        if (arg == "--help" || arg == "-h") {
            std::cout << "Usage: tahoe-terminal [--working-directory PATH] [-e COMMAND ARGS...] [--dev] [--check]\n"; return 0;
        }
        if ((arg == "--working-directory" || arg == "--dir") && i+1 < argc) cwd = argv[++i];
        else if ((arg == "-e" || arg == "--") && i+1 < argc) { while (++i < argc) command.emplace_back(argv[i]); break; }
        else if (arg == "--dev") dev = true;
        else if (arg == "--check") check = true;
        else { std::cerr << "Unknown or incomplete option: " << arg << '\n'; return 2; }
    }
    std::error_code failure;
    auto executable = fs::read_symlink("/proc/self/exe", failure);
    if (failure) { std::cerr << "Cannot determine executable path\n"; return 1; }
    auto web = executable.parent_path().parent_path() / "share/tahoe-terminal/web";
    if (const char* overridePath = g_getenv("TAHOE_TERMINAL_WEB")) web = overridePath;
    if (!fs::exists(web / "index.html")) web = TAHOE_SOURCE_WEB;
    for (const auto* file : {"index.html", "app.css", "app.js", "vendor/xterm.js", "vendor/xterm.css", "vendor/addon-search.js", "vendor/addon-unicode11.js"}) {
        if (!fs::is_regular_file(web / file)) { std::cerr << "Missing application asset: " << web / file << '\n'; return 1; }
    }
    if (!fs::is_directory(cwd)) { std::cerr << "Working directory does not exist: " << cwd << '\n'; return 2; }
    if (!command.empty() && command[0][0] != '/') {
        gchar* path = g_find_program_in_path(command[0].c_str());
        if (!path) { std::cerr << "Command not found: " << command[0] << '\n'; return 2; }
        command[0] = path; g_free(path);
    }
    if (check) { std::cout << "Application assets OK: " << web << "\nDefault shell: " << loginShell() << '\n'; return 0; }
    if (!gtk_init_check(&argc, &argv)) { std::cerr << "A graphical Wayland or X11 session is required.\n"; return 1; }
    Application application(web, executable, fs::absolute(cwd).string(), command, dev);
    gtk_main();
    return 0;
}
