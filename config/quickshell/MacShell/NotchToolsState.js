.pragma library

var pageIds = ["music", "pomodoro", "water", "shelf", "todo", "calendar", "weather", "stats"];
var statsIds = ["cpu","ram","gpu","disk","battery","network","temperature"];
function copy(value) { return JSON.parse(JSON.stringify(value)); }
function number(value, fallback, min, max) {
    var n = Number(value);
    return isFinite(n) ? Math.max(min, Math.min(max, Math.round(n))) : fallback;
}
function day(at) {
    var d = new Date(at);
    return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
}
function defaults(now) {
    return { version: 5, page: "music", menus: pageIds.slice(),
        stats: { view:"overview", primary:"cpu", secondary:"network" },
        settings: { focus: 25, short: 5, long: 15, quick: 5, custom: 30, cycles: 4, pomodoroSound: true, goal: 1500, glass: 250, reminder: 60, remind: true },
        pomodoro: { mode: "focus", state: "idle", total: 1500000, left: 1500000, endAt: 0, completed: 0, targetId: "", targetsOpen: false, sessions: [] },
        focus: { contexts: pageIds.slice(), rotate: false, seconds: 5 },
        water: { entries: [], lastReminder: now }, tasks: [], shelf: [] };
}
function settings(input) {
    var s = input || {};
    return { focus: number(s.focus, 25, 1, 180), short: number(s.short, 5, 1, 60),
        long: number(s.long, 15, 1, 120), quick: number(s.quick, 5, 1, 180), custom: number(s.custom, 30, 1, 180), cycles: number(s.cycles, 4, 2, 12),
        pomodoroSound: s.pomodoroSound !== false,
        goal: number(s.goal, 1500, 100, 10000), glass: number(s.glass, 250, 25, 2000),
        reminder: number(s.reminder, 60, 5, 240), remind: s.remind !== false };
}
function restore(raw, now) {
    var o = raw && typeof raw === "object" ? raw : {}, s = defaults(now);
    s.settings = settings(o.settings);
    if (Array.isArray(o.menus)) {
        s.menus = pageIds.filter(function (id) { return o.menus.indexOf(id) >= 0; });
        if (!s.menus.length) s.menus = ["music"];
    }
    if ((!o.version || o.version < 3) && s.menus.indexOf("calendar") < 0) s.menus.push("calendar");
    if ((!o.version || o.version < 4) && s.menus.indexOf("weather") < 0) s.menus.push("weather");
    if ((!o.version || o.version < 5) && s.menus.indexOf("stats") < 0) s.menus.push("stats");
    var stats = o.stats || {};
    s.stats.view = stats.view === "detail" ? "detail" : "overview";
    s.stats.primary = statsIds.indexOf(stats.primary) >= 0 ? stats.primary : "cpu";
    s.stats.secondary = statsIds.indexOf(stats.secondary) >= 0 && stats.secondary !== s.stats.primary ? stats.secondary : s.stats.primary === "network" ? "cpu" : "network";
    s.page = s.menus.indexOf(o.page) >= 0 ? o.page : s.menus[0];
    var p = o.pomodoro || {}, mode = ["focus", "short", "long", "quick", "custom"].indexOf(p.mode) >= 0 ? p.mode : "focus";
    var total = number(p.total, s.settings[mode] * 60000, 60000, 10800000);
    var phase = ["idle", "running", "paused", "finished"].indexOf(p.state) >= 0 ? p.state : "idle";
    s.pomodoro = { mode: mode, state: phase, total: total, left: number(p.left, total, 0, total),
        endAt: number(p.endAt, 0, 0, now + 10800000), completed: number(p.completed, 0, 0, 1000000),
        targetId: typeof p.targetId === "string" ? p.targetId.slice(0,100) : "", targetsOpen: p.targetsOpen === true,
        sessions: (Array.isArray(p.sessions) ? p.sessions : []).filter(function(e) {
            return e && isFinite(e.at) && e.at >= now - 90 * 86400000 && e.at <= now && (e.mode === "focus" || e.mode === "custom");
        }).slice(-2000).map(function(e) { return { at: Number(e.at), mode: e.mode, minutes: number(e.minutes,25,1,180), targetId: typeof e.targetId === "string" ? e.targetId.slice(0,100) : "" }; }) };
    if (phase === "running" && !s.pomodoro.endAt) s.pomodoro.state = "paused";
    var water = o.water || {};
    s.water.lastReminder = number(water.lastReminder, now, 0, now);
    s.water.entries = (Array.isArray(water.entries) ? water.entries : []).filter(function (e) {
        return e && isFinite(e.at) && e.at >= now - 30 * 86400000 && e.at <= now + 300000 && Number(e.ml) > 0;
    }).slice(-4000).map(function (e) { return { at: Number(e.at), ml: number(e.ml, 250, 1, 10000) }; });
    s.tasks = (Array.isArray(o.tasks) ? o.tasks : []).filter(function (t) {
        return t && typeof t.id === "string" && typeof t.text === "string" && t.text.trim();
    }).slice(0, 500).map(function (t) {
        return { id: t.id.slice(0, 100), text: t.text.trim().slice(0, 300), done: !!t.done,
            createdAt: number(t.createdAt, now, 0, now), doneAt: t.done ? number(t.doneAt, now, 0, now) : 0 };
    });
    if (!s.tasks.some(function(t) { return t.id === s.pomodoro.targetId; })) s.pomodoro.targetId = "";
    var focus = o.focus || {};
    s.focus.contexts = (Array.isArray(focus.contexts) ? focus.contexts : s.menus).filter(function(id,i,a) { return s.menus.indexOf(id)>=0 && a.indexOf(id)===i; });
    if (!s.focus.contexts.length) s.focus.contexts = [s.menus[0]];
    s.focus.rotate = focus.rotate === true;
    s.focus.seconds = number(focus.seconds,5,3,30);
    s.shelf = (Array.isArray(o.shelf) ? o.shelf : []).filter(function (e) {
        return e && typeof e.url === "string" && e.url.indexOf("file:///") === 0 && typeof e.name === "string";
    }).slice(0, 100);
    return s;
}
function waterTotal(state, now) {
    var today = day(now);
    return state.water.entries.reduce(function (sum, e) { return sum + (day(e.at) === today ? e.ml : 0); }, 0);
}
function waterHours(state, now) {
    var values = [], today = day(now);
    for (var i = 0; i < 24; i++) values.push(0);
    state.water.entries.forEach(function (e) { if (day(e.at) === today) values[new Date(e.at).getHours()] += e.ml; });
    return values;
}
function doneToday(state, now) {
    return state.tasks.filter(function (t) { return t.done && day(t.doneAt) === day(now); }).length;
}
function remaining(p, now) { return p.state === "running" ? Math.max(0, p.endAt - now) : p.left; }
function sessionsToday(state, now) {
    return (state.pomodoro.sessions || []).filter(function(e) { return day(e.at) === day(now); }).length;
}
function nextMode(state) {
    if (state.pomodoro.mode === "quick") return "quick";
    return state.pomodoro.mode === "focus" || state.pomodoro.mode === "custom"
        ? (state.pomodoro.completed > 0 && state.pomodoro.completed % state.settings.cycles === 0 ? "long" : "short") : "focus";
}
function tick(state, now, allowReminder) {
    var out = state;
    if (state.pomodoro.state === "running" && state.pomodoro.endAt <= now) {
        out = copy(out); out.pomodoro.state = "finished"; out.pomodoro.left = 0; out.pomodoro.endAt = 0;
        if (out.pomodoro.mode === "focus" || out.pomodoro.mode === "custom") {
            out.pomodoro.completed++;
            out.pomodoro.sessions = (out.pomodoro.sessions || []).filter(function(e) { return e.at >= now - 90 * 86400000; });
            out.pomodoro.sessions.push({ at: state.pomodoro.endAt, mode: out.pomodoro.mode, minutes: Math.round(out.pomodoro.total/60000), targetId: out.pomodoro.targetId || "" });
            out.pomodoro.sessions = out.pomodoro.sessions.slice(-2000);
        }
    }
    var lastDrink = out.water.entries.reduce(function (at, e) { return Math.max(at, e.at); }, 0);
    var interval = out.settings.reminder * 60000;
    if (allowReminder && out.settings.remind && waterTotal(out, now) < out.settings.goal
        && now - Math.max(lastDrink, out.water.lastReminder) >= interval) {
        if (out === state) out = copy(out);
        out.water.lastReminder = now;
    }
    return out;
}
