-- Run with an isolated XDG_RUNTIME_DIR to avoid reading/writing desktop state.
assert((os.getenv('XDG_RUNTIME_DIR') or ''):match('^/tmp/macshell%-drag'), 'Use an isolated /tmp/macshell-drag* runtime directory')
local events, timers, windows, operations = {}, {}, {}, {}
hl = {
    on=function(name, fn) events[name]=fn end,
    timer=function(fn) timers[#timers+1]=fn end,
    get_window=function(selector) return windows[selector] end,
    get_windows=function() return {windows['address:0xtest']} end,
    exec_scheduled_prop_refresh_immediately=function() end,
    dsp={window={}},
}
for _,kind in ipairs({'resize','move','fullscreen_state','tag'}) do
    hl.dsp.window[kind]=function(args) return {kind=kind,args=args} end
end
hl.dispatch=function(op)
    operations[#operations+1]=op.kind
    local w,a=op.args.window,op.args
    if op.kind=='move' then w.at={x=a.x,y=a.y}
    elseif op.kind=='resize' then w.size={x=a.x,y=a.y}
    elseif op.kind=='fullscreen_state' then w.fullscreen=a.internal;w.fullscreen_client=a.client end
end
local function flush()
    while #timers>0 do local pending=timers;timers={};for _,fn in ipairs(pending) do fn() end end
end
local w={address='0xtest',stable_id=1,mapped=true,hidden=false,floating=true,
    at={x=100,y=100},size={x=800,y=600},fullscreen=0,fullscreen_client=0,
    workspace={name='1'},monitor={x=0,y=0,width=1920,height=1080,scale=1,transform=0,
    reserved={left=0,right=0,top=30,bottom=0}}}
windows['address:0xtest']=w
local zoom=dofile(os.getenv('HOME')..'/.config/hypr/macshell_zoom.lua')
zoom.enter(w)
assert(zoom.isZoomed(w) and w.size.x==1920)
w.at={x=230,y=100}
operations={}
events['window.active'](w);flush()
assert(not zoom.isZoomed(w) and w.at.x==230 and w.at.y==100, 'Dragged geometry must survive focus/rule reconciliation')
for _,op in ipairs(operations) do assert(op~='move' and op~='resize', 'Reconciliation must not snap a dragged window back') end
zoom.enter(w)
w.monitor.width=1600
events['monitor.layout_changed']();flush()
assert(zoom.isZoomed(w) and w.size.x==1600, 'Monitor changes must still update Zoom bounds')
zoom.restore(w)
assert(w.at.x==230 and w.at.y==100, 'Normal restore must retain the last dragged position')
-- Never-hide Dock: shrinking a maximized window must leave Zoom without
-- restoring its old size or snapping it back to the reserved work area.
w.monitor.reserved.bottom=70
zoom.enter(w)
assert(w.size.y==980 and w.at.y==30, 'Zoom must reserve the Dock and menu bar')
w.size={x=1150,y=720}
operations={}
events['window.update_rules'](w);flush()
assert(not zoom.isZoomed(w) and w.fullscreen_client==0, 'Manual resize must leave client maximize state')
assert(w.size.x==1150 and w.size.y==720, 'Manual resize dimensions must survive reconciliation')
for _,op in ipairs(operations) do assert(op~='move' and op~='resize', 'Resize reconciliation must not replace the dragged rectangle') end
zoom.enter(w);zoom.restore(w)
assert(w.size.x==1150 and w.size.y==720, 'The next Zoom/restore must return to the manually resized rectangle')
print('Zoom: moved geometry retained, no snap-back, monitor reflow and normal restore passed.')
