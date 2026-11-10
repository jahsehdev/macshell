-- Exercise the actual focus handler. Other apps must never be demoted as a
-- side effect of focus or a delayed fullscreen transition.
local source = assert(arg[1], 'Pass hyprland.lua')
local file = assert(io.open(source, 'r'))
local text = file:read('*a'); file:close()
local block = assert(text:match('(local syncingWindowStack = false.-)\n%-%- <<< macOS%-style floating windows <<<'))
local handlers, operations = {}, {}
local env = {hl = {
    on = function(name, fn) handlers[name] = fn end,
    dsp = {window = {alter_zorder = function(args) return args end}},
    dispatch = function(args) operations[#operations + 1] = args end,
    get_windows = function() error('Focus must not rearrange other app windows') end,
    timer = function() error('Focus must not schedule a later fullscreen raise') end,
}}
assert(load(block, 'window focus stack', 't', env))()
local focus = assert(handlers['window.active'])
assert(not handlers['window.fullscreen'], 'Fullscreen changes must not passively raise another app')
local function window(mode)
    return {active=true, mapped=true, hidden=false, floating=true, fullscreen=mode,
        workspace={id=1,name='1'}}
end
for _, mode in ipairs({0, 1, 2}) do
    local clicked = window(mode)
    operations = {}; focus(clicked)
    assert(#operations == 1, 'Focus must affect exactly the selected app')
    assert(operations[1].window == clicked and operations[1].mode == 'top',
        'Focus must raise the selected app without lowering any other app')
end
operations = {}
focus(nil)
local stale = window(0); stale.active=false; focus(stale)
local hidden = window(0); hidden.hidden=true; focus(hidden)
local closed = window(0); closed.mapped=false; focus(closed)
local minimized = window(0); minimized.workspace.name='special:minimized'; focus(minimized)
assert(#operations == 0, 'Stale, hidden and minimized windows must never be raised')
print('Focus stack: selected app only; no background demotion or delayed fullscreen raise passed.')
