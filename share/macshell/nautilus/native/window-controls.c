/* Nautilus-only GTK bridge: route its native minimize button to MacShell.
 * Hyprland does not advertise native minimize, so GTK disables window.minimize.
 * The existing yellow button instead uses MacShell's established minimize action.
 */
#define _GNU_SOURCE
#include <gtk/gtk.h>
#include <adwaita.h>
#include <json-glib/json-glib.h>
#include <dlfcn.h>
#include <string.h>

static GtkCssProvider *fresh_style;
static GFileMonitor *appearance_monitor;
static GFileMonitor *css_monitor;
static GSettings *interface_settings;
static guint appearance_update;
static gboolean have_appearance;
static gboolean active_dark;
static gboolean refresh_stylesheet = TRUE;

/* MacShell persists the resolved mode, including the result of Auto mode. */
static gboolean read_appearance(const char *path, gboolean *dark) {
    g_autoptr(JsonParser) parser = json_parser_new();
    if (!json_parser_load_from_file(parser, path, NULL)) return FALSE;
    JsonNode *node = json_parser_get_root(parser);
    if (!node || !JSON_NODE_HOLDS_OBJECT(node)) return FALSE;
    JsonObject *object = json_node_get_object(node);
    node = json_object_get_member(object, "appearanceMode");
    if (node && json_node_get_value_type(node) == G_TYPE_STRING) {
        const char *mode = json_node_get_string(node);
        if (g_strcmp0(mode, "light") == 0 || g_strcmp0(mode, "dark") == 0) {
            *dark = g_strcmp0(mode, "dark") == 0;
            return TRUE;
        }
    }
    node = json_object_get_member(object, "darkMode");
    if (!node || json_node_get_value_type(node) != G_TYPE_BOOLEAN) return FALSE;
    *dark = json_node_get_boolean(node);
    return TRUE;
}

static gboolean reload_appearance(gpointer data) {
    (void)data;
    appearance_update = 0;
    if (!fresh_style) return G_SOURCE_REMOVE;
    gboolean dark = FALSE;
    g_autofree char *appearance = g_build_filename(g_get_user_config_dir(), "macbar/settings.json", NULL);
    if (!read_appearance(appearance, &dark)) {
        /* Keep the last valid style during an incomplete settings write. */
        if (g_file_test(appearance, G_FILE_TEST_EXISTS)) return G_SOURCE_REMOVE;
        if (interface_settings) {
            g_autofree char *scheme = g_settings_get_string(interface_settings, "color-scheme");
            dark = g_strcmp0(scheme, "prefer-dark") == 0;
        }
    }
    if (have_appearance && active_dark == dark && !refresh_stylesheet)
        return G_SOURCE_REMOVE;
    g_autofree char *theme = g_build_filename(g_get_user_data_dir(), "macshell/nautilus/themes",
        dark ? "MacTahoe-Dark" : "MacTahoe-Light", "gtk-4.0/gtk.css", NULL);
    g_autofree char *compat = g_build_filename(g_get_user_config_dir(), "macshell/nautilus/compat.css", NULL);
    if (!g_file_test(theme, G_FILE_TEST_IS_REGULAR) || !g_file_test(compat, G_FILE_TEST_IS_REGULAR))
        return G_SOURCE_REMOVE;
    g_autofree char *theme_uri = g_filename_to_uri(theme, NULL, NULL);
    g_autofree char *compat_uri = g_filename_to_uri(compat, NULL, NULL);
    g_autofree char *css = g_strdup_printf("@import url(\"%s\");\n@import url(\"%s\");\n", theme_uri, compat_uri);
    adw_style_manager_set_color_scheme(adw_style_manager_get_default(),
        dark ? ADW_COLOR_SCHEME_FORCE_DARK : ADW_COLOR_SCHEME_FORCE_LIGHT);
    gtk_css_provider_load_from_string(fresh_style, css);
    active_dark = dark;
    have_appearance = TRUE;
    refresh_stylesheet = FALSE;
    return G_SOURCE_REMOVE;
}

static void queue_appearance_update(void) {
    if (appearance_update) g_source_remove(appearance_update);
    appearance_update = g_timeout_add(150, reload_appearance, NULL);
}

static void appearance_file_changed(GFileMonitor *monitor, GFile *file, GFile *other,
                                    GFileMonitorEvent event, gpointer data) {
    (void)monitor;
    (void)event;
    (void)data;
    g_autofree char *name = g_file_get_basename(file);
    g_autofree char *destination = other ? g_file_get_basename(other) : NULL;
    gboolean css_changed = g_strcmp0(name, "compat.css") == 0 || g_strcmp0(name, "theme-import.css") == 0 ||
        g_strcmp0(destination, "compat.css") == 0 || g_strcmp0(destination, "theme-import.css") == 0;
    if (css_changed) refresh_stylesheet = TRUE;
    if (css_changed || g_strcmp0(name, "settings.json") == 0 || g_strcmp0(destination, "settings.json") == 0)
        queue_appearance_update();
}

static GFileMonitor *watch_appearance_directory(const char *relative) {
    g_autofree char *path = g_build_filename(g_get_user_config_dir(), relative, NULL);
    g_autoptr(GFile) directory = g_file_new_for_path(path);
    GFileMonitor *monitor = g_file_monitor_directory(directory, G_FILE_MONITOR_NONE, NULL, NULL);
    if (monitor) g_signal_connect(monitor, "changed", G_CALLBACK(appearance_file_changed), NULL);
    return monitor;
}

static void system_appearance_changed(GSettings *settings, const char *key, gpointer data) {
    (void)settings;
    (void)key;
    (void)data;
    queue_appearance_update();
}

static void minimize_window(GSimpleAction *action, GVariant *parameter, GtkWindow *window) {
    (void)action;
    (void)parameter;
    if (!gtk_widget_get_mapped(GTK_WIDGET(window))) return;
    char *helper = g_build_filename(g_get_home_dir(), ".config/hypr/minimize.sh", NULL);
    char *argv[] = {"/bin/sh", helper, "minimize", NULL};
    GError *error = NULL;
    if (!g_spawn_async(NULL, argv, NULL, G_SPAWN_DEFAULT, NULL, NULL, NULL, &error)) {
        g_warning("macshell-nautilus: cannot start minimize helper: %s", error->message);
        g_clear_error(&error);
    }
    g_free(helper);
}

static void repair_controls(GtkWidget *widget) {
    if (GTK_IS_WINDOW_CONTROLS(widget)) {
        GtkWindowControls *controls = GTK_WINDOW_CONTROLS(widget);
        if (g_strcmp0(gtk_window_controls_get_decoration_layout(controls), "close,minimize,maximize:") != 0)
            gtk_window_controls_set_decoration_layout(controls, "close,minimize,maximize:");
    }
    if (GTK_IS_BUTTON(widget) && gtk_widget_has_css_class(widget, "minimize")) {
        /* Enable the native button via a real action, not a visual dummy. */
        gtk_actionable_set_action_name(GTK_ACTIONABLE(widget), "macshell.minimize");
        gtk_widget_set_sensitive(widget, TRUE);
    }
    for (GtkWidget *child = gtk_widget_get_first_child(widget); child;) {
        GtkWidget *next = gtk_widget_get_next_sibling(child);
        repair_controls(child);
        child = next;
    }
}

static gboolean update_window(gpointer data) {
    GtkWindow *window = GTK_WINDOW(data);
    g_object_set_data(G_OBJECT(window), "macshell-controls-pending", NULL);
    if (!gtk_widget_get_mapped(GTK_WIDGET(window)) || gtk_window_get_modal(window) ||
        gtk_window_get_transient_for(window)) return G_SOURCE_REMOVE;
    if (!g_object_get_data(G_OBJECT(window), "macshell-minimize-action")) {
        GSimpleActionGroup *group = g_simple_action_group_new();
        GSimpleAction *action = g_simple_action_new("minimize", NULL);
        g_signal_connect_object(action, "activate", G_CALLBACK(minimize_window), window, 0);
        g_action_map_add_action(G_ACTION_MAP(group), G_ACTION(action));
        gtk_widget_insert_action_group(GTK_WIDGET(window), "macshell", G_ACTION_GROUP(group));
        g_object_set_data(G_OBJECT(window), "macshell-minimize-action", GINT_TO_POINTER(1));
        g_object_unref(action);
        g_object_unref(group);
    }
    repair_controls(GTK_WIDGET(window));
    return G_SOURCE_REMOVE;
}

static void schedule_update(GtkWindow *window) {
    if (g_object_get_data(G_OBJECT(window), "macshell-controls-pending")) return;
    g_object_set_data(G_OBJECT(window), "macshell-controls-pending", GINT_TO_POINTER(1));
    g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, update_window, g_object_ref(window), g_object_unref);
}

static void mapped(GtkWidget *widget, gpointer data) {
    (void)data;
    schedule_update(GTK_WINDOW(widget));
}

static void changed(GObject *object, GParamSpec *parameter, gpointer data) {
    (void)parameter;
    (void)data;
    schedule_update(GTK_WINDOW(object));
}

static void window_added(GtkApplication *application, GtkWindow *window, gpointer data) {
    (void)application;
    (void)data;
    if (g_object_get_data(G_OBJECT(window), "macshell-controls-bound")) return;
    g_object_set_data(G_OBJECT(window), "macshell-controls-bound", GINT_TO_POINTER(1));
    g_signal_connect(window, "map", G_CALLBACK(mapped), NULL);
    /* GTK rebuilds its window-control children after these state changes. */
    g_signal_connect(window, "notify::maximized", G_CALLBACK(changed), NULL);
    g_signal_connect(window, "notify::resizable", G_CALLBACK(changed), NULL);
    g_signal_connect(window, "notify::modal", G_CALLBACK(changed), NULL);
    g_signal_connect(window, "notify::transient-for", G_CALLBACK(changed), NULL);
    g_signal_connect(window, "notify::deletable", G_CALLBACK(changed), NULL);
    g_signal_connect(window, "notify::icon-name", G_CALLBACK(changed), NULL);
    schedule_update(window);
}

static void layout_changed(GObject *settings, GParamSpec *parameter, gpointer data) {
    (void)settings;
    (void)parameter;
    for (GList *entry = gtk_application_get_windows(GTK_APPLICATION(data)); entry; entry = entry->next)
        schedule_update(GTK_WINDOW(entry->data));
}

static void startup(GApplication *application, gpointer data) {
    (void)data;
    GtkSettings *settings = gtk_settings_get_default();
    if (settings) {
        g_object_set(settings, "gtk-decoration-layout", "close,minimize,maximize:", NULL);
        g_signal_connect_object(settings, "notify::gtk-decoration-layout", G_CALLBACK(layout_changed), application, 0);
    }
    GdkDisplay *display = gdk_display_get_default();
    char *css = g_build_filename(g_get_user_config_dir(), "gtk-4.0/gtk.css", NULL);
    if (display && g_file_test(css, G_FILE_TEST_IS_REGULAR)) {
        fresh_style = gtk_css_provider_new();
        gtk_css_provider_load_from_path(fresh_style, css);
        gtk_style_context_add_provider_for_display(display, GTK_STYLE_PROVIDER(fresh_style), GTK_STYLE_PROVIDER_PRIORITY_USER + 1);
        GSettingsSchemaSource *schemas = g_settings_schema_source_get_default();
        g_autoptr(GSettingsSchema) schema = schemas ? g_settings_schema_source_lookup(schemas, "org.gnome.desktop.interface", TRUE) : NULL;
        if (schema && g_settings_schema_has_key(schema, "color-scheme")) {
            interface_settings = g_settings_new_full(schema, NULL, NULL);
            g_signal_connect(interface_settings, "changed::color-scheme", G_CALLBACK(system_appearance_changed), NULL);
        }
        appearance_monitor = watch_appearance_directory("macbar");
        css_monitor = watch_appearance_directory("macshell/nautilus");
        reload_appearance(NULL);
    }
    g_free(css);
}

static void shutdown_app(GApplication *application, gpointer data) {
    (void)application;
    (void)data;
    if (appearance_update) {
        g_source_remove(appearance_update);
        appearance_update = 0;
    }
    g_clear_object(&appearance_monitor);
    g_clear_object(&css_monitor);
    g_clear_object(&interface_settings);
    have_appearance = FALSE;
    refresh_stylesheet = TRUE;
    GdkDisplay *display = gdk_display_get_default();
    if (fresh_style && display)
        gtk_style_context_remove_provider_for_display(display, GTK_STYLE_PROVIDER(fresh_style));
    g_clear_object(&fresh_style);
}

static void remove_own_preload(void) {
    /* Applications opened from Files must not inherit this application-local bridge. */
    Dl_info location;
    if (!dladdr((void *)remove_own_preload, &location) || !location.dli_fname) return;
    const char *preload = g_getenv("LD_PRELOAD");
    if (!preload) return;
    char **parts = g_strsplit_set(preload, ": ", -1);
    GString *remaining = g_string_new(NULL);
    for (guint i = 0; parts[i]; ++i) {
        if (!parts[i][0] || g_strcmp0(parts[i], location.dli_fname) == 0) continue;
        if (remaining->len) g_string_append_c(remaining, ':');
        g_string_append(remaining, parts[i]);
    }
    if (remaining->len) g_setenv("LD_PRELOAD", remaining->str, TRUE);
    else g_unsetenv("LD_PRELOAD");
    g_string_free(remaining, TRUE);
    g_strfreev(parts);
}

int g_application_run(GApplication *application, int argc, char **argv) {
    typedef int (*RunFunction)(GApplication *, int, char **);
    RunFunction real_run = (RunFunction)dlsym(RTLD_NEXT, "g_application_run");
    if (!real_run) { g_warning("macshell-nautilus: cannot resolve GApplication entry point"); return 1; }
    remove_own_preload();
    if (GTK_IS_APPLICATION(application) &&
        g_strcmp0(g_application_get_application_id(application), "org.gnome.Nautilus") == 0) {
        g_signal_connect_after(application, "startup", G_CALLBACK(startup), NULL);
        g_signal_connect(application, "shutdown", G_CALLBACK(shutdown_app), NULL);
        g_signal_connect(application, "window-added", G_CALLBACK(window_added), NULL);
        for (GList *entry = gtk_application_get_windows(GTK_APPLICATION(application)); entry; entry = entry->next)
            window_added(GTK_APPLICATION(application), GTK_WINDOW(entry->data), NULL);
    }
    return real_run(application, argc, argv);
}
