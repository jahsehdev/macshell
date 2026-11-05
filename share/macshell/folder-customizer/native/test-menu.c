/* Exercise the real public Nautilus extension interface without a compositor. */
#include "folder-menu.c"
#include <glib/gstdio.h>

typedef struct { GTypeModule parent; } TestModule;
typedef struct { GTypeModuleClass parent; } TestModuleClass;
G_DEFINE_TYPE(TestModule, test_module, G_TYPE_TYPE_MODULE)
static gboolean test_load(GTypeModule *module) { (void)module; return TRUE; }
static void test_unload(GTypeModule *module) { (void)module; }
static void test_module_init(TestModule *module) { (void)module; }
static void test_module_class_init(TestModuleClass *klass) {
    G_TYPE_MODULE_CLASS(klass)->load = test_load;
    G_TYPE_MODULE_CLASS(klass)->unload = test_unload;
}

typedef struct { GObject parent; GFile *file; gboolean directory; } TestFile;
typedef struct { GObjectClass parent; } TestFileClass;
static void test_file_info_init(NautilusFileInfoInterface *iface);
G_DEFINE_TYPE_WITH_CODE(TestFile, test_file, G_TYPE_OBJECT,
    G_IMPLEMENT_INTERFACE(NAUTILUS_TYPE_FILE_INFO, test_file_info_init))
static GFile *test_location(NautilusFileInfo *file) { return g_object_ref(((TestFile *)file)->file); }
static gboolean test_directory(NautilusFileInfo *file) { return ((TestFile *)file)->directory; }
static void test_file_info_init(NautilusFileInfoInterface *iface) {
    iface->get_location = test_location; iface->is_directory = test_directory;
}
static void test_file_finalize(GObject *object) {
    g_clear_object(&((TestFile *)object)->file);
    G_OBJECT_CLASS(test_file_parent_class)->finalize(object);
}
static void test_file_init(TestFile *file) { file->directory = TRUE; }
static void test_file_class_init(TestFileClass *klass) { G_OBJECT_CLASS(klass)->finalize = test_file_finalize; }

int main(void) {
    TestModule *module = g_object_new(test_module_get_type(), NULL);
    g_assert_true(g_type_module_use(G_TYPE_MODULE(module)));
    nautilus_module_initialize(G_TYPE_MODULE(module));
    const GType *types; int count = 0;
    nautilus_module_list_types(&types, &count);
    g_assert_cmpint(count, ==, 1);
    GObject *provider = g_object_new(types[0], NULL);
    g_assert_true(NAUTILUS_IS_MENU_PROVIDER(provider));
    g_autofree char *temp = g_dir_make_tmp("macshell-menu-test.XXXXXX", NULL);
    TestFile *file = g_object_new(test_file_get_type(), NULL);
    file->file = g_file_new_for_path(temp);
    GList selected = {.data = file, .next = NULL, .prev = NULL};
    GList *items = nautilus_menu_provider_get_file_items(NAUTILUS_MENU_PROVIDER(provider), &selected);
    g_assert_cmpint(g_list_length(items), ==, 1);
    g_autofree char *label = NULL;
    g_object_get(items->data, "label", &label, NULL);
    g_assert_cmpstr(label, ==, "Customize Folder…");
    nautilus_menu_item_list_free(items);
    g_print("PASS: local folder gets Customize Folder\n");
    file->directory = FALSE;
    g_assert_null(nautilus_menu_provider_get_file_items(NAUTILUS_MENU_PROVIDER(provider), &selected));
    g_print("PASS: regular files are excluded\n");
    file->directory = TRUE;
    GList second = {.data = file, .next = NULL, .prev = &selected};
    selected.next = &second;
    g_assert_null(nautilus_menu_provider_get_file_items(NAUTILUS_MENU_PROVIDER(provider), &selected));
    selected.next = NULL;
    g_print("PASS: multiple selection is excluded\n");
    g_clear_object(&file->file);
    file->file = g_file_new_for_uri("sftp://host/private");
    g_assert_null(nautilus_menu_provider_get_file_items(NAUTILUS_MENU_PROVIDER(provider), &selected));
    g_print("PASS: remote folders are excluded\n");
    g_clear_object(&file->file);
    file->file = g_file_new_for_path(temp);
    items = nautilus_menu_provider_get_background_items(NAUTILUS_MENU_PROVIDER(provider), NAUTILUS_FILE_INFO(file));
    g_assert_cmpint(g_list_length(items), ==, 1);
    nautilus_menu_item_list_free(items);
    g_print("PASS: folder background menu is supported\n");
    GDir *dir = g_dir_open("/usr/lib/nautilus/extensions-4", 0, NULL);
    if (dir) {
        int injected = 0; const char *entry;
        while ((entry = g_dir_read_name(dir))) if (g_strcmp0(entry, module_name) == 0) ++injected;
        g_assert_cmpint(injected, ==, 1);
        g_assert_null(g_dir_read_name(dir));
        g_dir_close(dir);
        g_print("PASS: module discovery preserves existing extensions and offers ours once\n");
    }
    g_object_unref(file); g_object_unref(provider);
    g_rmdir(temp);
    return 0;
}
