/* User-local Nautilus menu provider and palette. Uses only public GTK/GIO APIs.
 * The launcher preloads this bridge into Nautilus. The directory shim offers
 * this single module to its normal loader without modifying /usr/lib or hiding
 * any installed extensions. It never changes extension discovery in children.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <gtk/gtk.h>
#include <gmodule.h>
#include <nautilus-extension.h>
#include <json-glib/json-glib.h>
#include <string.h>
#include <unistd.h>

static GDir *extension_dir;
static gboolean offered;
static char *selected_path;
static const char *module_name = "libmacshell-folder-customize.so";
static const char *colors[] = {"#ff453a", "#ff9f0a", "#ffd43b", "#30c85a", "#0a84ff", "#bf5af2", "#929296"};
static const char *color_names[] = {"Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"};

GDir *g_dir_open(const gchar *path, guint flags, GError **error) {
    GDir *(*real_open)(const gchar *, guint, GError **) = dlsym(RTLD_NEXT, "g_dir_open");
    GDir *dir = real_open(path, flags, error);
    if (dir && g_str_has_suffix(path, "/nautilus/extensions-4")) {
        extension_dir = dir;
        offered = FALSE;
    }
    return dir;
}

const gchar *g_dir_read_name(GDir *dir) {
    const gchar *(*real_read)(GDir *) = dlsym(RTLD_NEXT, "g_dir_read_name");
    const gchar *name = real_read(dir);
    if (!name && dir == extension_dir && !offered) { offered = TRUE; return module_name; }
    return name;
}

void g_dir_close(GDir *dir) {
    void (*real_close)(GDir *) = dlsym(RTLD_NEXT, "g_dir_close");
    if (dir == extension_dir) extension_dir = NULL;
    real_close(dir);
}

GModule *g_module_open(const gchar *path, GModuleFlags flags) {
    GModule *(*real_open)(const gchar *, GModuleFlags) = dlsym(RTLD_NEXT, "g_module_open");
    if (path && g_str_has_suffix(path, "/libmacshell-folder-customize.so")) {
        g_autofree char *local = g_build_filename(g_get_user_data_dir(), "macshell/folder-customizer/native/folder-menu.so", NULL);
        return real_open(local, flags);
    }
    return real_open(path, flags);
}

static void remove_preload(void) {
    const char *preload = g_getenv("LD_PRELOAD");
    if (!preload) return;
    Dl_info own;
    if (!dladdr((void *)remove_preload, &own) || !own.dli_fname) return;
    g_auto(GStrv) parts = g_strsplit_set(preload, ": ", -1);
    GString *remaining = g_string_new(NULL);
    for (guint i = 0; parts[i]; ++i) {
        if (!parts[i][0] || g_strcmp0(parts[i], own.dli_fname) == 0) continue;
        if (remaining->len) g_string_append_c(remaining, ':');
        g_string_append(remaining, parts[i]);
    }
    if (remaining->len) g_setenv("LD_PRELOAD", remaining->str, TRUE);
    else g_unsetenv("LD_PRELOAD");
    g_string_free(remaining, TRUE);
}

int g_application_run(GApplication *application, int argc, char **argv) {
    int (*real_run)(GApplication *, int, char **) = dlsym(RTLD_NEXT, "g_application_run");
    remove_preload();
    return real_run(application, argc, argv);
}

typedef struct { GObject parent; } MacShellFolderMenu;
typedef struct { GObjectClass parent; } MacShellFolderMenuClass;
static void menu_provider_init(NautilusMenuProviderInterface *iface);
G_DEFINE_DYNAMIC_TYPE_EXTENDED(MacShellFolderMenu, macshell_folder_menu, G_TYPE_OBJECT, 0,
    G_IMPLEMENT_INTERFACE_DYNAMIC(NAUTILUS_TYPE_MENU_PROVIDER, menu_provider_init))

static GList *folder_items(NautilusFileInfo *file) {
    g_clear_pointer(&selected_path, g_free);
    if (!file || !nautilus_file_info_is_directory(file)) return NULL;
    g_autoptr(GFile) location = nautilus_file_info_get_location(file);
    g_autofree char *path = g_file_get_path(location);
    if (!path || g_file_test(path, G_FILE_TEST_IS_SYMLINK) || access(path, W_OK) != 0) return NULL;
    selected_path = g_strdup(path);
    NautilusMenuItem *item = nautilus_menu_item_new("MacShell::CustomizeFolder", "Customize Folder…",
        "Change this folder’s color, symbol or emoji", "tag-symbolic");
    return g_list_append(NULL, item);
}

static GList *get_file_items(NautilusMenuProvider *provider, GList *files) {
    (void)provider;
    return folder_items(files && !files->next ? NAUTILUS_FILE_INFO(files->data) : NULL);
}
static GList *get_background_items(NautilusMenuProvider *provider, NautilusFileInfo *folder) {
    (void)provider;
    return folder_items(folder);
}
static void menu_provider_init(NautilusMenuProviderInterface *iface) {
    iface->get_file_items = get_file_items;
    iface->get_background_items = get_background_items;
}
static void macshell_folder_menu_init(MacShellFolderMenu *self) { (void)self; }
static void macshell_folder_menu_class_init(MacShellFolderMenuClass *klass) { (void)klass; }
static void macshell_folder_menu_class_finalize(MacShellFolderMenuClass *klass) { (void)klass; }

G_MODULE_EXPORT void nautilus_module_initialize(GTypeModule *module) { macshell_folder_menu_register_type(module); }
G_MODULE_EXPORT void nautilus_module_shutdown(void) {}
G_MODULE_EXPORT void nautilus_module_list_types(const GType **types, int *count) {
    static GType list[1]; list[0] = macshell_folder_menu_get_type(); *types = list; *count = 1;
}

typedef struct { char *path; char *color; } FolderAction;
static void free_action(gpointer data, GClosure *closure) {
    (void)closure;
    FolderAction *action = data;
    g_free(action->path); g_free(action->color); g_free(action);
}

static void color_finished(GObject *source, GAsyncResult *result, gpointer data) {
    (void)data;
    g_autofree char *output = NULL;
    g_autofree char *errors = NULL;
    g_autoptr(GError) error = NULL;
    gboolean ok = g_subprocess_communicate_utf8_finish(G_SUBPROCESS(source), result, &output, &errors, &error);
    if (!ok || !g_subprocess_get_successful(G_SUBPROCESS(source))) {
        GApplication *app = g_application_get_default();
        if (app) {
            g_autoptr(GNotification) notice = g_notification_new("Could not customize folder");
            g_autoptr(JsonParser) parser = json_parser_new();
            const char *message = error ? error->message : "Check that the folder is writable and GVfs metadata is available.";
            if (output && json_parser_load_from_data(parser, output, -1, NULL)) {
                JsonNode *root = json_parser_get_root(parser);
                if (JSON_NODE_HOLDS_OBJECT(root))
                    message = json_object_get_string_member_with_default(json_node_get_object(root), "message", message);
            }
            g_notification_set_body(notice, message);
            g_application_send_notification(app, "macshell-folder-customize-error", notice);
        }
    }
    g_object_unref(source);
}

static void apply_color(GtkButton *button, gpointer data) {
    FolderAction *action = data;
    GtkWidget *popover = gtk_widget_get_ancestor(GTK_WIDGET(button), GTK_TYPE_POPOVER);
    g_autofree char *helper = g_build_filename(g_get_user_config_dir(), "quickshell/folder-customizer/bin/folder_customizer.py", NULL);
    g_autoptr(GError) error = NULL;
    GSubprocess *process = g_subprocess_new(G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_PIPE,
        &error, "python3", helper, "--folder", action->path, "--color", action->color, NULL);
    if (process) g_subprocess_communicate_utf8_async(process, NULL, NULL, color_finished, NULL);
    else g_warning("macshell-folder-customize: %s", error->message);
    if (popover) gtk_popover_popdown(GTK_POPOVER(popover));
}

static void draw_swatch(GtkDrawingArea *area, cairo_t *cr, int width, int height, gpointer data) {
    (void)area;
    GdkRGBA color;
    gdk_rgba_parse(&color, data);
    cairo_set_source_rgba(cr, color.red, color.green, color.blue, 1);
    cairo_arc(cr, width/2., height/2., 7, 0, 2 * G_PI); cairo_fill_preserve(cr);
    cairo_set_source_rgba(cr, 0, 0, 0, .12); cairo_set_line_width(cr, 1); cairo_stroke(cr);
}

static GtkWidget *find_customize_label(GtkWidget *widget) {
    if (GTK_IS_LABEL(widget) && g_strcmp0(gtk_label_get_text(GTK_LABEL(widget)), "Customize Folder…") == 0) return widget;
    for (GtkWidget *child = gtk_widget_get_first_child(widget); child; child = gtk_widget_get_next_sibling(child)) {
        GtkWidget *found = find_customize_label(child);
        if (found) return found;
    }
    return NULL;
}

#include "folder-popover.h"

static void add_palette(GtkPopover *popover) {
    if (!selected_path || g_object_get_data(G_OBJECT(popover), "macshell-folder-palette")) return;
    GtkWidget *label = find_customize_label(GTK_WIDGET(popover));
    if (!label) return;
    GtkWidget *row = label;
    while (gtk_widget_get_parent(row) && g_strcmp0(G_OBJECT_TYPE_NAME(row), "GtkModelButton") != 0)
        row = gtk_widget_get_parent(row);
    GtkWidget *box = gtk_widget_get_parent(row);
    if (!GTK_IS_BOX(box)) return;
    GtkWidget *palette = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 3);
    gtk_widget_add_css_class(palette, "macshell-folder-palette");
    gtk_widget_set_halign(palette, GTK_ALIGN_CENTER);
    static GtkCssProvider *style;
    if (!style) {
        style = gtk_css_provider_new();
        gtk_css_provider_load_from_string(style,
            ".macshell-folder-palette button { min-width: 15px; min-height: 17px; padding: 3px; margin: 0; }");
        gtk_style_context_add_provider_for_display(gtk_widget_get_display(palette), GTK_STYLE_PROVIDER(style),
            GTK_STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
    }
    gtk_widget_set_margin_start(palette, 12); gtk_widget_set_margin_end(palette, 12);
    gtk_widget_set_margin_top(palette, 4); gtk_widget_set_margin_bottom(palette, 4);
    for (guint i = 0; i < G_N_ELEMENTS(colors); ++i) {
        GtkWidget *button = gtk_button_new();
        gtk_widget_add_css_class(button, "flat");
        gtk_widget_add_css_class(button, "circular");
        gtk_widget_set_tooltip_text(button, color_names[i]);
        gtk_widget_set_size_request(button, 23, 25);
        GtkWidget *art = gtk_drawing_area_new();
        gtk_drawing_area_set_content_width(GTK_DRAWING_AREA(art), 15);
        gtk_drawing_area_set_content_height(GTK_DRAWING_AREA(art), 17);
        gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(art), draw_swatch, (gpointer)colors[i], NULL);
        gtk_button_set_child(GTK_BUTTON(button), art);
        FolderAction *action = g_new0(FolderAction, 1);
        action->path = g_strdup(selected_path); action->color = g_strdup(colors[i]);
        g_signal_connect_data(button, "clicked", G_CALLBACK(apply_color), action, free_action, 0);
        gtk_box_append(GTK_BOX(palette), button);
    }
    gtk_box_insert_child_after(GTK_BOX(box), palette, gtk_widget_get_prev_sibling(row));
    /* Replace the launcher action with a real submenu owned by this Nautilus
     * popover. No toplevel/customizer process is created. */
    GtkWidget *customize = folder_popover_button(selected_path);
    gtk_box_insert_child_after(GTK_BOX(box), customize, row);
    gtk_widget_set_visible(row, FALSE);
    g_object_set_data_full(G_OBJECT(popover), "macshell-folder-submenu", g_object_ref(customize), g_object_unref);
    g_object_set_data_full(G_OBJECT(popover), "macshell-folder-palette", g_object_ref(palette), g_object_unref);
}

void gtk_popover_menu_set_menu_model(GtkPopoverMenu *popover, GMenuModel *model) {
    void (*real_set)(GtkPopoverMenu *, GMenuModel *) = dlsym(RTLD_NEXT, "gtk_popover_menu_set_menu_model");
    GtkWidget *palette = g_object_get_data(G_OBJECT(popover), "macshell-folder-palette");
    GtkWidget *submenu = g_object_get_data(G_OBJECT(popover), "macshell-folder-submenu");
    if (submenu) {
        GtkWidget *parent = gtk_widget_get_parent(submenu);
        if (GTK_IS_BOX(parent)) gtk_box_remove(GTK_BOX(parent), submenu);
        g_object_set_data(G_OBJECT(popover), "macshell-folder-submenu", NULL);
    }
    if (palette) {
        GtkWidget *parent = gtk_widget_get_parent(palette);
        if (GTK_IS_BOX(parent)) gtk_box_remove(GTK_BOX(parent), palette);
        g_object_set_data(G_OBJECT(popover), "macshell-folder-palette", NULL);
    }
    real_set(popover, model);
}

void gtk_popover_popup(GtkPopover *popover) {
    void (*real_popup)(GtkPopover *) = dlsym(RTLD_NEXT, "gtk_popover_popup");
    add_palette(popover);
    real_popup(popover);
}
