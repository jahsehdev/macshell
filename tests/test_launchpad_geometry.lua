local callbacks, timers, calls, windows = {}, {}, {}, {}
local actualOpen = io.open
local lastStatus
io.open = function(path, mode)
    if path:match('/macshell/launchpad%-geometry%.status$') then
        return {write=function(_, value) lastStatus=value end, close=function() end}
    end
    return actualOpen(path, mode)
end
hl = {
    dsp = {window = {
        resize = function(p) return {kind='resize', args=p} end,
        move = function(p) return {kind='move', args=p} end,
    }},
    on = function(event, fn) callbacks[event] = fn end,
    timer = function(fn) table.insert(timers, fn) end,
    get_windows = function() return windows end,
    get_window = function(selector)
        for _,w in ipairs(windows) do
            if selector == 'address:' .. w.address then return w end
        end
    end,
    dispatch = function(command)
        table.insert(calls, command)
        assert(command.args.exact == true)
        local w = hl.get_window(command.args.window)
        if command.kind == 'resize' then
            w.size = {x=command.args.x, y=command.args.y}
            -- A resize can recenter the normal window. The final move must win.
            w.at = {x=w.at.x+20, y=w.at.y+20}
        else
            w.at = {x=command.args.x, y=command.args.y}
        end
    end,
}
local geometry = dofile(arg[1] or 'config/hypr/macshell_launchpad.lua')
local function flush()
    local queue=timers; timers={}
    for _,fn in ipairs(queue) do fn() end
end
local function reset(monitor)
    calls, timers = {}, {}
    local w = {address='0xaa',title='qs-launchpad-backdrop',mapped=true,hidden=false,
        at={x=0,y=0},size={x=1280,y=743},
        monitor=monitor or {x=0,y=0,width=1280,height=800,scale=1,
                               reserved={left=0,top=28,right=0,bottom=57}}}
    windows={w}; return w
end
local w = reset()
callbacks['window.open'](w); callbacks['window.update_rules'](w)
assert(#timers == 1, 'coalesce concurrent window events')
flush()
assert(w.size.y == 800 and w.at.y == 0, 'ignore Never Hide exclusive zone')
assert(lastStatus:find('actual 0 0 1280 800', 1, true), 'report observed compositor bounds')
assert(#calls == 2 and calls[1].kind == 'resize' and calls[2].kind == 'move')
geometry.fit(w)
assert(#calls == 2, 'do not keep dispatching when the backdrop already fits')

w = reset({x=1280,y=-100,width=1600,height=2560,scale=2,transform=1,
           reserved={left=64,top=28,right=0,bottom=0}})
geometry.fit(w)
assert(w.size.x == 1280 and w.size.y == 800)
assert(w.at.x == 1280 and w.at.y == -100, 'global scaled/rotated monitor bounds')

w = reset(); w.title='Console'
geometry.fit(w)
assert(#calls == 0, 'application geometry must be untouched')
for _,flag in ipairs({'hidden','mapped'}) do
    w = reset(); w[flag] = flag == 'hidden'
    geometry.fit(w); assert(#calls == 0, 'ignore closed/hidden backdrops')
end

w = reset()
callbacks['config.reloaded'](); flush()
assert(w.size.y == 800, 'repair an existing backdrop after config reload')
w.size.y=743
callbacks['layer.opened'](); flush()
assert(w.size.y == 800, 'repair after a Dock layer/workarea change')
w.size.y=743
callbacks['window.open'](w); windows={}; flush()
assert(#timers == 0, 'closing before a queued correction is harmless')
print('Launchpad geometry: 8 scenarios passed')
