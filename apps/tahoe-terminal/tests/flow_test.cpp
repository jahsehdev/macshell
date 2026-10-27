#include "pty.hpp"
#include <glib.h>
#include <iostream>
#include <memory>
#include <string>

struct State {
    GMainLoop* loop = g_main_loop_new(nullptr, FALSE);
    PtySession* session = nullptr;
    size_t received = 0, pending = 0;
    int code = -1;
    bool interrupted = false, timedOut = false;
};
int main() {
    State state;
    std::string error;
    auto session = std::make_unique<PtySession>([&](const std::string& bytes) {
        state.received += bytes.size(); state.pending += bytes.size();
        if (state.received >= 256 * 1024 && !state.interrupted) {
            state.interrupted = true;
            state.session->write("\x03");
        }
    }, [&](int status) { state.code = status; g_main_loop_quit(state.loop); });
    state.session = session.get();
    if (!session->start({"/usr/bin/yes", "stream"}, "/tmp", 80, 24, error)) {
        std::cerr << error << '\n'; return 1;
    }
    // A slow renderer acknowledges batches later, exercising pause/resume
    // across the high watermark instead of immediately acknowledging reads.
    auto ack = g_timeout_add(25, +[](gpointer data) -> gboolean {
        auto& s = *static_cast<State*>(data);
        s.session->acknowledge(s.pending); s.pending = 0;
        return G_SOURCE_CONTINUE;
    }, &state);
    auto timeout = g_timeout_add_seconds(8, +[](gpointer data) -> gboolean {
        auto& s = *static_cast<State*>(data); s.timedOut = true;
        g_main_loop_quit(s.loop); return G_SOURCE_REMOVE;
    }, &state);
    g_main_loop_run(state.loop);
    g_source_remove(ack);
    if (!state.timedOut) g_source_remove(timeout);
    session.reset(); g_main_loop_unref(state.loop);
    std::cout << "Streamed " << state.received << " bytes; Ctrl+C exit=" << state.code << '\n';
    return state.timedOut || !state.interrupted || state.code != 130;
}
