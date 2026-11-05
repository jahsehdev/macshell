.pragma library

// Pure activity arbitration: temporary hardware feedback, then urgent/running tasks.
function activities(recording, timerActive, player, charging) {
    var out = [];
    if (recording) out.push("recording");
    if (timerActive) out.push("timer");
    if (player) out.push("music");
    if (charging) out.push("charging");
    return out;
}

function selectActivity(items, requested, feedback, ringing) {
    if (feedback) return feedback;
    if (ringing) return "timer";
    if (items.indexOf(requested) >= 0) return requested;
    return items.length ? items[0] : "idle";
}

function dimensions(mode, expanded, active, barHeight, screenWidth, size, music, lyrics, page, pomodoroLayout, mediaLyrics, recordingStage, calendarExpanded) {
    var scale = Math.max(0.85, Math.min(1.2, Number(size) || 1));
    var dashboard = ["pomodoro", "water", "shelf", "todo", "calendar", "weather", "stats"].indexOf(page) >= 0;
    var summary = page === "bluetooth" || page === "charging";
    var device = page === "bluetooth";
    var calendar = page === "calendar";
    var weather = page === "weather";
    var calendarWidth = calendarExpanded ? 760 : 560;
    var pomodoro = page === "pomodoro";
    var pomodoroWidth = pomodoroLayout === "decision" ? 640 : pomodoroLayout === "active" ? 480 : 520;
    var downloads = page === "downloads";
    var recording = page === "recording";
    var recordingWidth = recordingStage === "result" ? 580 : 520;
    var mediaWidth = screenWidth < 620 * scale ? 440 : lyrics ? 740 : 640;
    var panelScale = dashboard || summary || music || recording || downloads ? Math.min(scale, Math.max(0, screenWidth-24)/(downloads ? 520 : recording ? recordingWidth : calendar ? calendarWidth : summary ? (device ? 520 : 440) : pomodoro ? pomodoroWidth : music ? mediaWidth : 560)) : scale;
    var width = (expanded ? (downloads ? 520 : recording ? recordingWidth : pomodoro ? pomodoroWidth : calendar ? calendarWidth : dashboard ? 560 : summary ? (device ? 520 : 440) : music ? mediaWidth : 360) : active ? (pomodoro ? 324 : music || recording || downloads || device ? 324 : 238) : 172) * scale;
    return {
        scale: panelScale,
        width: Math.max(0, Math.min(width, screenWidth - 24)),
        height: expanded ? (downloads ? 120 : recording ? (recordingStage === "result" ? 184 : recordingStage === "error" ? 160 : 120) : summary ? (device ? 136 : 104) : pomodoro ? (pomodoroLayout === "active" ? 96 : 216) : music ? 160 + (mediaLyrics ? (screenWidth < 620 * scale ? 80 : 40) : 0) : page === "stats" ? 256 : weather ? 256 : calendar ? (calendarExpanded ? 340 : 256) : dashboard ? 232 : 206) * panelScale : mode === "attached" ? barHeight : Math.max(barHeight, (active ? 40 : 32) * scale),
        top: mode === "floating" ? 7 : 0
    };
}

function lyricIndex(lines, position, synced) {
    if (!synced || !lines || !lines.length) return -1;
    var lo = 0, hi = lines.length - 1, result = -1;
    while (lo <= hi) {
        var mid = (lo + hi) >> 1;
        if (lines[mid].t <= position + 0.15) { result = mid; lo = mid + 1; }
        else hi = mid - 1;
    }
    return result;
}

function fullscreen(clients, monitor) {
    var ws = monitor.activeWorkspace ? monitor.activeWorkspace.id : -999;
    var special = monitor.specialWorkspace ? monitor.specialWorkspace.id : 0;
    return clients.some(function (c) {
        return c.mapped && !c.hidden && c.monitor === monitor.id
            && c.workspace && (c.workspace.id === ws || (special !== 0 && c.workspace.id === special))
            && (c.fullscreen === true || Number(c.fullscreen) === 2);
    });
}
