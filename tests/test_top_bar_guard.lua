-- Exercise the actual guard block without starting the compositor/session.
local source=assert(arg[1], 'Pass hyprland.lua')
local file=assert(io.open(source,'r'));local text=file:read('*a');file:close()
local block=assert(text:match('(local topBarGuard = true.-)\n%-%- Start the Launchpad layer'))
local windows,operations,tick={},{},nil
local zoomed={}
local env={math=math,ipairs=ipairs,windowZoom={isZoomed=function(w) return zoomed[w.address] end}}
env.hl={
    get_windows=function() return windows end,
    timer=function(fn,options) if options.type=='repeat' then tick=fn end end,
    dsp={window={move=function(args) return args end}},
    dispatch=function(args) operations[#operations+1]=args end,
}
assert(load(block,'top-bar guard','t',env))()
local function window(address,internal,client)
    return {address=address,floating=true,mapped=true,hidden=false,fullscreen=internal,
        fullscreen_client=client,at={x=120,y=10},monitor={y=100,reserved={top=28}}}
end
local normal=window('normal',0,0)
local clientZoom=window('zoom',0,1)
local recovering=window('recovering',0,0);zoomed.recovering=true
local fullscreen=window('fullscreen',2,2)
local clientFullscreen=window('client-fullscreen',0,2)
local pinned=window('pinned',0,0);pinned.pinned=true
windows={normal,clientZoom,recovering,fullscreen,clientFullscreen,pinned}
tick()
assert(#operations==1,'bar guard must leave Zoom, fullscreen, recovery and overlays alone')
assert(operations[1].window=='address:normal' and operations[1].y==128,
    'normal windows must use the reserved top plus the monitor origin')
assert(operations[1].exact==true,'bar guard must use absolute screen coordinates')
print('Top-bar guard: Zoom/fullscreen ownership and absolute monitor coordinates passed.')
