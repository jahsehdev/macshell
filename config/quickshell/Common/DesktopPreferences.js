// Values shared by Settings, Dock, desktop and the window controller.
function normalize(o) {
    o = o && typeof o === 'object' ? o : {};
    function choice(k, values, fallback) { return values.indexOf(o[k]) >= 0 ? o[k] : fallback; }
    function flag(k, fallback) { return typeof o[k] === 'boolean' ? o[k] : fallback; }
    return {
        position: choice('position', ['left', 'bottom', 'right'], 'bottom'),
        minimizeEffect: choice('minimizeEffect', ['genie', 'scale'], 'genie'),
        titlebarAction: choice('titlebarAction', ['fill', 'zoom', 'minimize', 'none'], 'fill'),
        minimizeIntoApp: flag('minimizeIntoApp', false),
        showRecentApps: flag('showRecentApps', true),
        recentLimit: 3,
        desktopItems: flag('desktopItems', true),
        stageItems: flag('stageItems', false),
        desktopWidgets: flag('desktopWidgets', true),
        stageWidgets: flag('stageWidgets', true),
        wallpaperClick: choice('wallpaperClick', ['always', 'stage'], 'stage'),
        stageManager: flag('stageManager', false),
        stageRecent: flag('stageRecent', true),
        stageWindows: choice('stageWindows', ['all', 'one'], 'all')
    };
}
function recent(list, id) {
    var result = [], seen = {};
    [id].concat(Array.isArray(list) ? list : []).forEach(function(value) {
        if (typeof value !== 'string' || !value || seen[value] || result.length >= 20) return;
        seen[value] = true; result.push(value);
    });
    return result;
}
if (typeof module !== 'undefined') module.exports = { normalize: normalize, recent: recent };
