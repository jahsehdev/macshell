#include "pty.hpp"
#include <glib.h>
#include <iostream>
#include <memory>
#include <string>

int main() {
    auto* loop = g_main_loop_new(nullptr, FALSE);
    std::string output, error;
    bool timedOut = false, resized = false;
    int code = -1;
    PtySession* pointer = nullptr;
    auto session = std::make_unique<PtySession>([&](const std::string& bytes) {
        output += bytes;
        pointer->acknowledge(bytes.size());
        if (!resized && output.find("READY") != std::string::npos) {
            resized = true;
            pointer->resize(101, 37);
            pointer->write("continue\n");
        }
    }, [&](int status) { code = status; g_main_loop_quit(loop); });
    pointer = session.get();
    // A real controlling TTY, shell input, UTF-8 output and a terminal resize.
    const std::string script = "test -t 0 && test -t 1 || exit 9; printf 'READY\\n'; read answer; stty size; printf 'utf8: café 日本語\\n'; printf 'TERM=%s COLOR=%s\\n' \"$TERM\" \"$COLORTERM\"; exit 7";
    if (!session->start({"/bin/bash", "--noprofile", "--norc", "-c", script}, "/tmp", 80, 24, error)) {
        std::cerr << "PTY setup failed: " << error << '\n'; return 1;
    }
    std::pair<GMainLoop*,bool*> timerData{loop, &timedOut};
    auto timeout = g_timeout_add_seconds(10, +[](gpointer data) -> gboolean {
        auto* pair = static_cast<std::pair<GMainLoop*,bool*>*>(data);
        *pair->second = true; g_main_loop_quit(pair->first); return G_SOURCE_REMOVE;
    }, &timerData);
    g_main_loop_run(loop);
    if (!timedOut) g_source_remove(timeout);
    session.reset();
    g_main_loop_unref(loop);
    const bool ok = !timedOut && resized && code == 7 && output.find("37 101") != std::string::npos
        && output.find("café 日本語") != std::string::npos && output.find("TERM=xterm-256color COLOR=truecolor") != std::string::npos;
    std::cout << output << "\nExit: " << code << "\n";
    if (!ok) std::cerr << "Real PTY integration test failed\n";
    return ok ? 0 : 1;
}
