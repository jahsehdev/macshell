#include "pty.hpp"
#include <glib-unix.h>
#include <algorithm>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <limits.h>
#include <pty.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

PtySession::PtySession(Output output, Exit exit): output_(std::move(output)), exit_(std::move(exit)) {}
PtySession::~PtySession() {
    close();
    if (childSource_) g_source_remove(childSource_);
    if (pid_ > 0) waitpid(pid_, nullptr, WNOHANG);
}

bool PtySession::start(const std::vector<std::string>& argv, const std::string& cwd, int columns, int rows, std::string& error) {
    if (argv.empty() || argv[0].empty() || argv[0][0] != '/' || access(argv[0].c_str(), X_OK)) {
        error = "The shell must be an executable absolute path.";
        return false;
    }
    initialCwd_ = cwd;
    std::vector<char*> arguments;
    for (const auto& arg : argv) arguments.push_back(const_cast<char*>(arg.c_str()));
    arguments.push_back(nullptr);
    gchar** env = g_get_environ();
    env = g_environ_setenv(env, "TERM", "xterm-256color", TRUE);
    env = g_environ_setenv(env, "COLORTERM", "truecolor", TRUE);
    env = g_environ_setenv(env, "TERM_PROGRAM", "TahoeTerminal", TRUE);
    env = g_environ_setenv(env, "TERM_PROGRAM_VERSION", "0.1.0", TRUE);
    env = g_environ_unsetenv(env, "COLUMNS");
    env = g_environ_unsetenv(env, "LINES");
    winsize size{};
    size.ws_col = std::clamp(columns, 2, 500);
    size.ws_row = std::clamp(rows, 1, 300);
    int slave = -1;
    if (openpty(&fd_, &slave, nullptr, nullptr, &size) < 0) {
        error = std::strerror(errno);
        g_strfreev(env);
        return false;
    }
    fcntl(fd_, F_SETFD, FD_CLOEXEC);
    fcntl(slave, F_SETFD, FD_CLOEXEC);
    // Prepare all allocations before fork. The child uses only async-signal-safe
    // system calls before exec, even when WebKit has already started threads.
    pid_ = fork();
    if (pid_ == 0) {
        ::close(fd_);
        if (setsid() < 0 || ioctl(slave, TIOCSCTTY, 0) < 0 || chdir(cwd.c_str()) < 0) _exit(126);
        for (int target = 0; target < 3; ++target) if (dup2(slave, target) < 0) _exit(126);
        if (slave > 2) ::close(slave);
        // GLib and WebKit may ignore SIGPIPE; interactive shells need defaults.
        struct sigaction action{};
        action.sa_handler = SIG_DFL;
        sigemptyset(&action.sa_mask);
        for (int s : {SIGPIPE, SIGINT, SIGQUIT, SIGTERM, SIGHUP, SIGCHLD}) sigaction(s, &action, nullptr);
        sigset_t signals;
        sigemptyset(&signals);
        sigprocmask(SIG_SETMASK, &signals, nullptr);
        execve(argv[0].c_str(), arguments.data(), env);
        const char message[] = "tahoe-terminal: cannot start the requested shell\r\n";
        ::write(STDERR_FILENO, message, sizeof(message) - 1);
        _exit(127);
    }
    ::close(slave);
    g_strfreev(env);
    if (pid_ < 0) {
        error = std::strerror(errno);
        ::close(fd_); fd_ = -1; pid_ = 0;
        return false;
    }
    fcntl(fd_, F_SETFL, fcntl(fd_, F_GETFL) | O_NONBLOCK);
    childSource_ = g_child_watch_add(pid_, onExit, this);
    watchRead();
    return true;
}

void PtySession::watchRead() {
    if (!closed_ && !eof_ && fd_ >= 0 && !readSource_ && unacknowledged_ < 128 * 1024)
        readSource_ = g_unix_fd_add(fd_, GIOCondition(G_IO_IN | G_IO_HUP | G_IO_ERR), onRead, this);
}
gboolean PtySession::onRead(gint, GIOCondition, gpointer data) {
    auto* self = static_cast<PtySession*>(data);
    if (self->readReady()) return G_SOURCE_CONTINUE;
    self->readSource_ = 0;
    return G_SOURCE_REMOVE;
}
bool PtySession::readReady() {
    char buffer[16384];
    for (int i = 0; i < 8; ++i) {
        const auto count = ::read(fd_, buffer, sizeof(buffer));
        if (count > 0) {
            unacknowledged_ += static_cast<size_t>(count);
            output_(std::string(buffer, count));
            if (closed_ || unacknowledged_ >= 128 * 1024) return false;
        } else if (count == 0 || (count < 0 && errno == EIO)) {
            eof_ = true;
            finish();
            return false;
        } else if (errno == EINTR) continue;
        else if (errno == EAGAIN || errno == EWOULDBLOCK) return true;
        else {
            eof_ = true;
            finish();
            return false;
        }
    }
    return true;
}
void PtySession::acknowledge(size_t bytes) {
    unacknowledged_ -= std::min(bytes, unacknowledged_);
    if (unacknowledged_ < 32 * 1024) watchRead();
}
bool PtySession::write(const std::string& bytes) {
    if (closed_ || fd_ < 0 || pending_.size() + bytes.size() > 4 * 1024 * 1024) return false;
    pending_ += bytes;
    drainWrite();
    return true;
}
void PtySession::drainWrite() {
    while (!pending_.empty() && fd_ >= 0) {
        auto count = ::write(fd_, pending_.data(), pending_.size());
        if (count > 0) pending_.erase(0, count);
        else if (count < 0 && errno == EINTR) continue;
        else break;
    }
    if (!pending_.empty() && !writeSource_ && fd_ >= 0)
        writeSource_ = g_unix_fd_add(fd_, GIOCondition(G_IO_OUT | G_IO_HUP | G_IO_ERR), onWrite, this);
}
gboolean PtySession::onWrite(gint, GIOCondition condition, gpointer data) {
    auto* self = static_cast<PtySession*>(data);
    self->writeSource_ = 0;
    if (!(condition & (G_IO_HUP | G_IO_ERR))) self->drainWrite();
    else self->pending_.clear();
    return G_SOURCE_REMOVE;
}
void PtySession::resize(int columns, int rows) {
    if (fd_ < 0) return;
    winsize size{};
    size.ws_col = std::clamp(columns, 2, 500);
    size.ws_row = std::clamp(rows, 1, 300);
    ioctl(fd_, TIOCSWINSZ, &size);
}
void PtySession::onExit(GPid, gint status, gpointer data) {
    auto* self = static_cast<PtySession*>(data);
    self->pid_ = 0;
    self->childSource_ = 0;
    self->exited_ = true;
    self->exitCode_ = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + (WIFSIGNALED(status) ? WTERMSIG(status) : 0);
    self->finish();
}
void PtySession::finish() {
    if (exited_ && (eof_ || closed_) && !notified_) {
        notified_ = true;
        exit_(exitCode_);
    }
}
bool PtySession::busy() const {
    if (fd_ < 0 || pid_ <= 0) return false;
    const auto foreground = tcgetpgrp(fd_);
    return foreground > 0 && foreground != pid_;
}
std::string PtySession::cwd() const {
    if (pid_ <= 0) return initialCwd_;
    char buffer[PATH_MAX];
    const auto path = "/proc/" + std::to_string(pid_) + "/cwd";
    const auto length = readlink(path.c_str(), buffer, sizeof(buffer));
    return length > 0 ? std::string(buffer, length) : initialCwd_;
}
void PtySession::close() {
    if (closed_) return;
    closed_ = true;
    if (readSource_) { g_source_remove(readSource_); readSource_ = 0; }
    if (writeSource_) { g_source_remove(writeSource_); writeSource_ = 0; }
    if (pid_ > 0) {
        const auto foreground = fd_ >= 0 ? tcgetpgrp(fd_) : -1;
        if (foreground > 0 && foreground != pid_) kill(-foreground, SIGHUP);
        kill(-pid_, SIGHUP);
    }
    if (fd_ >= 0) { ::close(fd_); fd_ = -1; }
    pending_.clear();
    finish();
}
