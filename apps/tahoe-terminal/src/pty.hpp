#pragma once
#include <glib.h>
#include <functional>
#include <string>
#include <vector>
#include <sys/types.h>

class PtySession {
public:
    using Output = std::function<void(const std::string&)>;
    using Exit = std::function<void(int)>;
    PtySession(Output output, Exit exit);
    ~PtySession();
    PtySession(const PtySession&) = delete;
    PtySession& operator=(const PtySession&) = delete;
    bool start(const std::vector<std::string>& argv, const std::string& cwd, int columns, int rows, std::string& error);
    bool write(const std::string& bytes);
    void resize(int columns, int rows);
    void acknowledge(size_t bytes);
    void close();
    bool busy() const;
    bool alive() const { return pid_ > 0; }
    std::string cwd() const;
private:
    void watchRead();
    void drainWrite();
    bool readReady();
    void finish();
    static gboolean onRead(gint, GIOCondition, gpointer);
    static gboolean onWrite(gint, GIOCondition, gpointer);
    static void onExit(GPid, gint, gpointer);
    Output output_;
    Exit exit_;
    int fd_ = -1;
    pid_t pid_ = 0;
    guint readSource_ = 0, writeSource_ = 0, childSource_ = 0;
    std::string pending_, initialCwd_;
    size_t unacknowledged_ = 0;
    bool closed_ = false, eof_ = false, exited_ = false, notified_ = false;
    int exitCode_ = 0;
};
