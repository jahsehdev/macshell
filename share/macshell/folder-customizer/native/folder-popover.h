/* Native GTK submenu; reuse the existing JSON worker, never a Qt window.
 * Async reads keep artwork generation and GVfs off Nautilus' main thread. */
typedef struct {
    GSubprocess *worker;
    GDataInputStream *input;
    GCancellable *cancel;
    GtkWidget *content, *preview, *message, *symbols, *emoji;
    JsonNode *settings;
    gboolean populated;
} FolderPanel;

static void panel_free(gpointer data) {
    FolderPanel *panel = data;
    g_cancellable_cancel(panel->cancel);
    if (panel->worker) g_subprocess_force_exit(panel->worker);
    g_clear_object(&panel->worker);
    g_clear_object(&panel->input);
    g_clear_object(&panel->cancel);
    g_clear_pointer(&panel->settings, json_node_unref);
    g_free(panel);
}

static void panel_send(FolderPanel *panel, const char *action, const char *key, const char *value) {
    if (!panel->worker || !panel->settings) return;
    g_autoptr(JsonBuilder) builder = json_builder_new();
    json_builder_begin_object(builder);
    json_builder_set_member_name(builder, "action");
    json_builder_add_string_value(builder, action);
    json_builder_set_member_name(builder, "settings");
    json_builder_add_value(builder, json_node_copy(panel->settings));
    if (key) {
        json_builder_set_member_name(builder, key);
        json_builder_add_string_value(builder, value);
    }
    json_builder_end_object(builder);
    g_autoptr(JsonNode) root = json_builder_get_root(builder);
    g_autofree char *json = json_to_string(root, FALSE);
    g_autofree char *line = g_strconcat(json, "\n", NULL);
    g_autoptr(GError) error = NULL;
    if (!g_output_stream_write_all(g_subprocess_get_stdin_pipe(panel->worker), line, strlen(line), NULL, NULL, &error)) {
        gtk_label_set_text(GTK_LABEL(panel->message), error->message);
        return;
    }
    gtk_widget_set_sensitive(panel->content, FALSE);
    gtk_label_set_text(GTK_LABEL(panel->message), "Updating folder…");
}

static void panel_choice(GtkButton *button, gpointer data) {
    FolderPanel *panel = data;
    if (!panel->settings) return;
    const char *key = g_object_get_data(G_OBJECT(button), "setting-key");
    const char *value = g_object_get_data(G_OBJECT(button), "setting-value");
    JsonObject *settings = json_node_get_object(panel->settings);
    json_object_set_string_member(settings, key, value);
    if (g_str_equal(key, "symbol") || g_str_equal(key, "emoji")) {
        json_object_remove_member(settings, "mask");
        json_object_set_string_member(settings, g_str_equal(key, "symbol") ? "emoji" : "symbol", "");
    }
    panel_send(panel, "apply", NULL, NULL);
}

static GtkWidget *panel_button(FolderPanel *panel, const char *label, const char *key, const char *value) {
    GtkWidget *button = gtk_button_new_with_label(label);
    g_object_set_data_full(G_OBJECT(button), "setting-key", g_strdup(key), g_free);
    g_object_set_data_full(G_OBJECT(button), "setting-value", g_strdup(value), g_free);
    g_signal_connect(button, "clicked", G_CALLBACK(panel_choice), panel);
    return button;
}

static void panel_clear(GtkButton *button, gpointer data) {
    (void)button;
    panel_send(data, "clear", NULL, NULL);
}

static void panel_emoji(GtkEntry *entry, gpointer data) {
    FolderPanel *panel = data;
    if (!panel->settings) return;
    JsonObject *settings = json_node_get_object(panel->settings);
    json_object_set_string_member(settings, "emoji", gtk_editable_get_text(GTK_EDITABLE(entry)));
    json_object_set_string_member(settings, "symbol", "");
    json_object_remove_member(settings, "mask");
    panel_send(panel, "apply", NULL, NULL);
}

static void panel_file_response(GtkNativeDialog *dialog, int response, gpointer data) {
    GtkWidget *owner = data; /* Keep the panel alive while a chooser is open. */
    FolderPanel *panel = g_object_get_data(G_OBJECT(owner), "folder-panel");
    if (response == GTK_RESPONSE_ACCEPT) {
        g_autoptr(GFile) file = gtk_file_chooser_get_file(GTK_FILE_CHOOSER(dialog));
        g_autofree char *path = file ? g_file_get_path(file) : NULL;
        if (path) {
            gboolean exporting = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(dialog), "export"));
            g_autofree char *target = exporting ? g_build_filename(path, "Folder.iconset", NULL) : g_strdup(path);
            panel_send(panel, exporting ? "export-iconset" : "import-mask", exporting ? "directory" : "path", target);
        }
    }
    gtk_native_dialog_destroy(dialog);
    g_object_unref(dialog);
    g_object_unref(owner);
}

static void panel_file(GtkButton *button, gpointer data) {
    GtkWidget *owner = data;
    gboolean exporting = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "export"));
    GtkRoot *root = gtk_widget_get_root(owner);
    GtkFileChooserNative *chooser = gtk_file_chooser_native_new(exporting ? "Export Folder.iconset to…" : "Import transparent PNG",
        GTK_IS_WINDOW(root) ? GTK_WINDOW(root) : NULL,
        exporting ? GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER : GTK_FILE_CHOOSER_ACTION_OPEN,
        exporting ? "Export" : "Import", "Cancel");
    if (!exporting) {
        GtkFileFilter *filter = gtk_file_filter_new();
        gtk_file_filter_add_mime_type(filter, "image/png");
        gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(chooser), filter);
        g_object_unref(filter);
    }
    g_object_set_data(G_OBJECT(chooser), "export", GINT_TO_POINTER(exporting));
    g_signal_connect(chooser, "response", G_CALLBACK(panel_file_response), g_object_ref(owner));
    gtk_native_dialog_show(GTK_NATIVE_DIALOG(chooser));
}

static void panel_read(GObject *source, GAsyncResult *result, gpointer data) {
    GtkWidget *owner = data;
    FolderPanel *panel = g_object_get_data(G_OBJECT(owner), "folder-panel");
    g_autoptr(GError) error = NULL;
    g_autofree char *line = g_data_input_stream_read_line_finish(G_DATA_INPUT_STREAM(source), result, NULL, &error);
    gtk_widget_set_sensitive(panel->content, TRUE);
    if (!line) {
        gtk_label_set_text(GTK_LABEL(panel->message), "Folder helper stopped. Close this menu and try again.");
        g_object_unref(owner);
        return;
    }
    g_autoptr(JsonParser) parser = json_parser_new();
    if (json_parser_load_from_data(parser, line, -1, NULL) && JSON_NODE_HOLDS_OBJECT(json_parser_get_root(parser))) {
        JsonObject *state = json_node_get_object(json_parser_get_root(parser));
        const char *event = json_object_get_string_member_with_default(state, "event", "");
        gtk_label_set_text(GTK_LABEL(panel->message), "");
        if (g_str_equal(event, "error"))
            gtk_label_set_text(GTK_LABEL(panel->message), json_object_get_string_member_with_default(state, "message", "Could not update folder."));
        if (g_str_equal(event, "exported")) gtk_label_set_text(GTK_LABEL(panel->message), "Exported Folder.iconset.");
        if (g_str_equal(event, "state")) {
            g_clear_pointer(&panel->settings, json_node_unref);
            panel->settings = json_node_copy(json_object_get_member(state, "settings"));
            g_autoptr(GFile) icon = g_file_new_for_uri(json_object_get_string_member(state, "icon"));
            g_autofree char *path = g_file_get_path(icon);
            gtk_picture_set_filename(GTK_PICTURE(panel->preview), path);
            gtk_label_set_text(GTK_LABEL(panel->message), json_object_get_string_member_with_default(state, "warning", ""));
            if (!panel->populated) {
                JsonArray *symbols = json_object_get_array_member(state, "symbols");
                const char *category = "";
                GtkWidget *grid = NULL;
                guint column = 0;
                for (guint i = 0; i < json_array_get_length(symbols); ++i) {
                    JsonObject *symbol = json_array_get_object_element(symbols, i);
                    const char *group = json_object_get_string_member(symbol, "category");
                    if (g_strcmp0(category, group) != 0) {
                        category = group;
                        GtkWidget *heading = gtk_label_new(group);
                        gtk_label_set_xalign(GTK_LABEL(heading), 0);
                        gtk_widget_set_margin_top(heading, 12);
                        gtk_box_append(GTK_BOX(panel->symbols), heading);
                        grid = gtk_grid_new(); column = 0;
                        gtk_grid_set_column_homogeneous(GTK_GRID(grid), TRUE);
                        gtk_box_append(GTK_BOX(panel->symbols), grid);
                    }
                    const char *id = json_object_get_string_member(symbol, "id");
                    GtkWidget *button = panel_button(panel, "", "symbol", id);
                    gtk_widget_set_tooltip_text(button, json_object_get_string_member_with_default(symbol, "name", id));
                    const char *svg = json_object_get_string_member(symbol, "svg");
                    g_autoptr(GBytes) bytes = g_bytes_new(svg, strlen(svg));
                    g_autoptr(GInputStream) stream = g_memory_input_stream_new_from_bytes(bytes);
                    g_autoptr(GdkPixbuf) pixbuf = gdk_pixbuf_new_from_stream_at_scale(stream, 24, 24, TRUE, NULL, NULL);
                    if (pixbuf) {
                        g_autoptr(GdkTexture) texture = gdk_texture_new_for_pixbuf(pixbuf);
                        gtk_button_set_child(GTK_BUTTON(button), gtk_image_new_from_paintable(GDK_PAINTABLE(texture)));
                    }
                    gtk_grid_attach(GTK_GRID(grid), button, column % 7, column / 7, 1, 1);
                    ++column;
                }
                panel->populated = TRUE;
            }
        }
    }
    /* A pending read must not keep a dismissed popover/worker alive forever. */
    if (gtk_widget_get_mapped(owner))
        g_data_input_stream_read_line_async(panel->input, G_PRIORITY_DEFAULT, panel->cancel, panel_read, g_object_ref(owner));
    g_object_unref(owner);
}

static void panel_closed(GtkPopover *popover, gpointer data) {
    (void)popover;
    FolderPanel *panel = data;
    g_cancellable_cancel(panel->cancel);
    if (panel->worker) g_subprocess_force_exit(panel->worker);
}

static void panel_open(GtkWidget *owner, gpointer data) {
    FolderPanel *panel = data;
    if (panel->worker) return;
    const char *path = g_object_get_data(G_OBJECT(owner), "folder-path");
    g_autofree char *helper = g_build_filename(g_get_user_config_dir(), "quickshell/folder-customizer/bin/folder_customizer.py", NULL);
    g_autoptr(GError) error = NULL;
    panel->worker = g_subprocess_new(G_SUBPROCESS_FLAGS_STDIN_PIPE | G_SUBPROCESS_FLAGS_STDOUT_PIPE,
        &error, "python3", helper, "--folder", path, "--serve", NULL);
    if (!panel->worker) {
        gtk_label_set_text(GTK_LABEL(panel->message), error->message);
        return;
    }
    panel->input = g_data_input_stream_new(g_subprocess_get_stdout_pipe(panel->worker));
    g_data_input_stream_read_line_async(panel->input, G_PRIORITY_DEFAULT, panel->cancel, panel_read, g_object_ref(owner));
}

static GtkWidget *folder_popover_button(const char *path) {
    GtkWidget *button = gtk_menu_button_new();
    gtk_menu_button_set_label(GTK_MENU_BUTTON(button), "Customize Folder…");
    gtk_widget_add_css_class(button, "flat");
    GtkWidget *popover = gtk_popover_new();
    gtk_popover_set_position(GTK_POPOVER(popover), GTK_POS_RIGHT);
    gtk_menu_button_set_popover(GTK_MENU_BUTTON(button), popover);
    FolderPanel *panel = g_new0(FolderPanel, 1);
    panel->cancel = g_cancellable_new();
    g_object_set_data_full(G_OBJECT(popover), "folder-panel", panel, panel_free);
    g_object_set_data_full(G_OBJECT(popover), "folder-path", g_strdup(path), g_free);
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_set_size_request(box, 330, -1);
    gtk_popover_set_child(GTK_POPOVER(popover), box);
    panel->preview = gtk_picture_new();
    gtk_widget_set_size_request(panel->preview, 96, 96);
    gtk_picture_set_can_shrink(GTK_PICTURE(panel->preview), TRUE);
    gtk_box_append(GTK_BOX(box), panel->preview);
    g_autofree char *name = g_filename_display_basename(path);
    GtkWidget *label = gtk_label_new(name);
    gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_MIDDLE);
    gtk_box_append(GTK_BOX(box), label);
    panel->content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_box_append(GTK_BOX(box), panel->content);
    GtkWidget *palette = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 3);
    gtk_widget_set_halign(palette, GTK_ALIGN_CENTER);
    for (guint i = 0; i < G_N_ELEMENTS(colors); ++i) {
        GtkWidget *swatch = panel_button(panel, "", "color", colors[i]);
        gtk_widget_set_tooltip_text(swatch, color_names[i]);
        GtkWidget *art = gtk_drawing_area_new();
        gtk_drawing_area_set_content_width(GTK_DRAWING_AREA(art), 18);
        gtk_drawing_area_set_content_height(GTK_DRAWING_AREA(art), 20);
        gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(art), draw_swatch, (gpointer)colors[i], NULL);
        gtk_button_set_child(GTK_BUTTON(swatch), art);
        gtk_box_append(GTK_BOX(palette), swatch);
    }
    gtk_box_append(GTK_BOX(panel->content), palette);
    GtkWidget *tools = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    gtk_box_append(GTK_BOX(tools), panel_button(panel, "Standard", "style", "standard"));
    gtk_box_append(GTK_BOX(tools), panel_button(panel, "Engraved", "style", "engraved"));
    gtk_box_append(GTK_BOX(panel->content), tools);
    GtkWidget *files = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    GtkWidget *import = gtk_button_new_with_label("Import PNG…");
    GtkWidget *export = gtk_button_new_with_label("Export…");
    g_object_set_data(G_OBJECT(export), "export", GINT_TO_POINTER(TRUE));
    g_signal_connect(import, "clicked", G_CALLBACK(panel_file), popover);
    g_signal_connect(export, "clicked", G_CALLBACK(panel_file), popover);
    gtk_box_append(GTK_BOX(files), import); gtk_box_append(GTK_BOX(files), export);
    gtk_box_append(GTK_BOX(panel->content), files);
    GtkWidget *scroll = gtk_scrolled_window_new();
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_widget_set_size_request(scroll, -1, 200);
    panel->symbols = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), panel->symbols);
    gtk_box_append(GTK_BOX(panel->content), scroll);
    panel->emoji = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(panel->emoji), "Emoji — type or paste, then Enter");
    gtk_entry_set_input_hints(GTK_ENTRY(panel->emoji), GTK_INPUT_HINT_EMOJI);
    g_signal_connect(panel->emoji, "activate", G_CALLBACK(panel_emoji), panel);
    gtk_box_append(GTK_BOX(panel->content), panel->emoji);
    GtkWidget *clear = gtk_button_new_with_label("Clear customization");
    g_signal_connect(clear, "clicked", G_CALLBACK(panel_clear), panel);
    gtk_box_append(GTK_BOX(panel->content), clear);
    panel->message = gtk_label_new("Loading…");
    gtk_label_set_wrap(GTK_LABEL(panel->message), TRUE);
    gtk_label_set_max_width_chars(GTK_LABEL(panel->message), 38);
    gtk_box_append(GTK_BOX(box), panel->message);
    gtk_widget_set_sensitive(panel->content, FALSE);
    g_signal_connect(popover, "map", G_CALLBACK(panel_open), panel);
    g_signal_connect(popover, "closed", G_CALLBACK(panel_closed), panel);
    return button;
}
