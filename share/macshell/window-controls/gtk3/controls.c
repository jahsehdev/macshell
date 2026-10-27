/* GTK 3 module, scoped to Network Connections' existing inline toolbar. */
#include <gtk/gtk.h>
#include <string.h>
#include <unistd.h>

static GtkWidget *find_toolbar(GtkWidget *widget) {
    if (GTK_IS_TOOLBAR(widget)) return widget;
    if (!GTK_IS_CONTAINER(widget)) return NULL;
    GList *children = gtk_container_get_children(GTK_CONTAINER(widget));
    GtkWidget *result = NULL;
    for (GList *child = children; child && !result; child = child->next)
        result = find_toolbar(GTK_WIDGET(child->data));
    g_list_free(children);
    return result;
}

static void update_image(GtkWidget *button, const char *suffix) {
    const char *kind = g_object_get_data(G_OBJECT(button), "macshell-kind");
    GtkWidget *window = gtk_widget_get_toplevel(button);
    if (g_strcmp0(kind, "maximize") == 0 && GTK_IS_WINDOW(window) && gtk_window_is_maximized(GTK_WINDOW(window)))
        kind = "restore";
    GtkSettings *settings = gtk_settings_get_default();
    char *theme = NULL;
    if (settings) g_object_get(settings, "gtk-theme-name", &theme, NULL);
    gboolean dark = !theme || !g_str_has_suffix(theme, "Light");
    g_free(theme);
    g_autofree char *name = g_strdup_printf("titlebutton-%s%s%s@2.png", kind, suffix, dark ? "-dark" : "");
    g_autofree char *path = g_build_filename(g_get_user_config_dir(), "macshell/window-controls", dark ? "dark" : "light", name, NULL);
    GdkPixbuf *image = gdk_pixbuf_new_from_file_at_scale(path, 16, 16, TRUE, NULL);
    if (image) {
        gtk_image_set_from_pixbuf(GTK_IMAGE(gtk_button_get_image(GTK_BUTTON(button))), image);
        g_object_unref(image);
    }
}

static gboolean enter_button(GtkWidget *button, GdkEventCrossing *event, gpointer data) {
    (void)event; (void)data; update_image(button, "-hover"); return FALSE;
}
static gboolean leave_button(GtkWidget *button, GdkEventCrossing *event, gpointer data) {
    (void)event; (void)data; update_image(button, ""); return FALSE;
}

static gboolean drag_row(GtkWidget *toolbar, GdkEventButton *event, gpointer data) {
    (void)toolbar;
    if (event->button != GDK_BUTTON_PRIMARY) return FALSE;
    GtkWidget *source = gtk_get_event_widget((GdkEvent *)event);
    // Button events can propagate to the toolbar; never turn those into moves.
    for (GtkWidget *widget = source; widget && widget != toolbar; widget = gtk_widget_get_parent(widget))
        if (GTK_IS_BUTTON(widget) || GTK_IS_ENTRY(widget) || GTK_IS_TOOL_BUTTON(widget)) return FALSE;
    GtkWindow *window = GTK_WINDOW(data);
    if (event->type == GDK_2BUTTON_PRESS) {
        gchar *helper = g_build_filename(g_get_user_config_dir(), "quickshell", "MacShell", "bin", "titlebar_action.py", NULL);
        gchar *pid = g_strdup_printf("%d", (int)getpid());
        gchar *argv[] = {"python3", helper, "--pid", pid, NULL};
        g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL);
        g_free(pid); g_free(helper);
        return TRUE;
    }
    if (event->type != GDK_BUTTON_PRESS) return FALSE;
    gtk_window_begin_move_drag(window, event->button, event->x_root, event->y_root, event->time);
    return TRUE;
}

static void clicked(GtkButton *button, gpointer data) {
    GtkWindow *window = GTK_WINDOW(data);
    const char *kind = g_object_get_data(G_OBJECT(button), "macshell-kind");
    if (g_strcmp0(kind, "close") == 0) gtk_window_close(window);
    else if (g_strcmp0(kind, "maximize") == 0) {
        if (gtk_window_is_maximized(window)) gtk_window_unmaximize(window);
        else gtk_window_maximize(window);
        update_image(GTK_WIDGET(button), "-hover");
    } else {
        g_autofree char *helper = g_build_filename(g_get_user_config_dir(), "hypr/minimize.sh", NULL);
        char *arguments[] = {"/bin/sh", helper, "minimize", NULL};
        g_spawn_async(NULL, arguments, NULL, G_SPAWN_DEFAULT, NULL, NULL, NULL, NULL);
    }
}

static gboolean integrate(gpointer data) {
    GtkWindow *window = GTK_WINDOW(data);
    if (!gtk_widget_get_mapped(GTK_WIDGET(window)) || gtk_window_get_modal(window)
        || g_object_get_data(G_OBJECT(window), "macshell-native-controls")) return G_SOURCE_REMOVE;
    GtkWidget *toolbar = find_toolbar(GTK_WIDGET(window));
    if (!toolbar) return G_SOURCE_REMOVE;
    GtkWidget *parent = gtk_widget_get_parent(toolbar);
    if (!GTK_IS_BOX(parent)) return G_SOURCE_REMOVE;
    // Reuse the actual Add/Edit/Delete toolbar, placing its existing row above
    // the list. This adds no titlebar, panel, overlay, or extra toolbar.
    gtk_box_reorder_child(GTK_BOX(parent), toolbar, 0);
    GtkToolItem *item = gtk_tool_item_new();
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_style_context_add_class(gtk_widget_get_style_context(box), "macshell-inline-controls");
    GtkCssProvider *css = gtk_css_provider_new();
    gtk_css_provider_load_from_data(css, ".macshell-inline-controls button {min-width:18px;min-height:24px;padding:0;border:0;background:none;box-shadow:none;}", -1, NULL);
    gtk_style_context_add_provider_for_screen(gtk_widget_get_screen(GTK_WIDGET(window)), GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
    g_object_unref(css);
    gtk_widget_set_margin_start(box, 6);
    gtk_widget_set_margin_end(box, 10);
    const char *kinds[] = {"close", "minimize", "maximize"};
    const char *labels[] = {"Close window", "Minimize window", "Maximize or restore window"};
    for (guint i = 0; i < G_N_ELEMENTS(kinds); ++i) {
        GtkWidget *button = gtk_button_new();
        gtk_button_set_image(GTK_BUTTON(button), gtk_image_new());
        gtk_button_set_always_show_image(GTK_BUTTON(button), TRUE);
        gtk_button_set_relief(GTK_BUTTON(button), GTK_RELIEF_NONE);
        gtk_widget_set_size_request(button, 18, 24);
        gtk_widget_set_tooltip_text(button, labels[i]);
        atk_object_set_name(gtk_widget_get_accessible(button), labels[i]);
        g_object_set_data(G_OBJECT(button), "macshell-kind", (gpointer)kinds[i]);
        g_signal_connect_object(button, "clicked", G_CALLBACK(clicked), window, 0);
        g_signal_connect(button, "enter-notify-event", G_CALLBACK(enter_button), NULL);
        g_signal_connect(button, "leave-notify-event", G_CALLBACK(leave_button), NULL);
        gtk_box_pack_start(GTK_BOX(box), button, FALSE, FALSE, 0);
        update_image(button, "");
    }
    gtk_container_add(GTK_CONTAINER(item), box);
    gtk_toolbar_insert(GTK_TOOLBAR(toolbar), item, 0);
    gtk_widget_add_events(toolbar, GDK_BUTTON_PRESS_MASK);
    g_signal_connect_object(toolbar, "button-press-event", G_CALLBACK(drag_row), window, 0);
    gtk_widget_show_all(GTK_WIDGET(item));
    g_object_set_data(G_OBJECT(window), "macshell-native-controls", GINT_TO_POINTER(1));
    g_autofree char *helper = g_build_filename(g_get_user_data_dir(), "macshell/window-controls/window_action.py", NULL);
    g_autofree char *pid = g_strdup_printf("%d", (int)getpid());
    char *arguments[] = {"python3", helper, "ready", "nm-connection-editor", "--pid", pid, NULL};
    g_spawn_async(NULL, arguments, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL);
    return G_SOURCE_REMOVE;
}

static gboolean mapped(GSignalInvocationHint *hint, guint count, const GValue *values, gpointer data) {
    (void)hint; (void)data;
    if (count > 0) {
        GtkWidget *widget = g_value_get_object(&values[0]);
        if (widget && g_strcmp0(G_OBJECT_TYPE_NAME(widget), "NMConnectionList") == 0)
            g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, integrate, g_object_ref(widget), g_object_unref);
    }
    return TRUE;
}

G_MODULE_EXPORT void gtk_module_init(gint *argc, gchar ***argv) {
    (void)argc; (void)argv;
    if (g_strcmp0(g_get_prgname(), "nm-connection-editor") != 0) return;
    static gboolean installed;
    if (installed) return;
    installed = TRUE;
    gpointer widget_class = g_type_class_ref(GTK_TYPE_WIDGET);
    g_signal_add_emission_hook(g_signal_lookup("map", GTK_TYPE_WIDGET), 0, mapped, NULL, NULL);
    g_type_class_unref(widget_class);
}
