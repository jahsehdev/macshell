-- The Launchpad wallpaper is a normal window so the menu bar and Dock stay
-- above it. Static size rules can be clamped to the Dock's exclusive work area;
-- restore monitor coordinates after mapping and layout/rule changes instead.
local M = {}
local pending = {}
local statusPath = (os.getenv('XDG_CACHE_HOME') or (os.getenv('HOME') .. '/.cache'))
    .. '/macshell/launchpad-geometry.status'
local function status(text)
    local file = io.open(statusPath, 'w')
    if file then file:write(text .. '\n'); file:close() end
end
local function backdrop(w)
    return w and w.title == 'qs-launchpad-backdrop' and w.mapped and not w.hidden and w.monitor
end
function M.bounds(w)
    if not backdrop(w) then return nil end
    local m = w.monitor
    local width, height = m.width, m.height
    if (m.transform or 0) % 2 == 1 then width, height = height, width end
    local scale = m.scale or 1
    return {x=m.x, y=m.y, w=math.floor(width/scale), h=math.floor(height/scale)}
end
function M.fit(w)
    local b = M.bounds(w)
    if not b or not w.at or not w.size then return end
    local selector = 'address:' .. w.address
    -- Resize first: a resize can recenter a floating window. Move last, using
    -- exact global coordinates, including nonzero monitor origins.
    local resized = math.abs(w.size.x-b.w) > 0.5 or math.abs(w.size.y-b.h) > 0.5
    if resized then
        hl.dispatch(hl.dsp.window.resize({window=selector, x=b.w, y=b.h, exact=true}))
    end
    if resized or math.abs(w.at.x-b.x) > 0.5 or math.abs(w.at.y-b.y) > 0.5 then
        hl.dispatch(hl.dsp.window.move({window=selector, x=b.x, y=b.y, exact=true}))
    end
    status(string.format('active\nactual %.0f %.0f %.0f %.0f\nmonitor %.0f %.0f %.0f %.0f',
        w.at.x, w.at.y, w.size.x, w.size.y, b.x, b.y, b.w, b.h))
end
local function queue(w)
    if not backdrop(w) or pending[w.address] then return end
    local addr = w.address
    pending[addr] = true
    hl.timer(function()
        local current = hl.get_window('address:' .. addr)
        M.fit(current)
        pending[addr] = nil
    end, {timeout=50, type='oneshot'})
end
local function fitAll()
    for _, w in ipairs(hl.get_windows()) do queue(w) end
end
hl.on('window.open', queue)
hl.on('window.update_rules', queue)
hl.on('window.move_to_workspace', queue)
hl.on('monitor.layout_changed', fitAll)
hl.on('layer.opened', fitAll)
hl.on('layer.closed', fitAll)
hl.on('config.reloaded', fitAll)
-- Standalone verification has no compositor event loop.
local cmdline = io.open('/proc/self/cmdline', 'r')
local verifying = false
if cmdline then
    verifying = cmdline:read('*a'):find('--verify-config', 1, true) ~= nil
    cmdline:close()
end
if not verifying then status('ready'); fitAll() end
return M
