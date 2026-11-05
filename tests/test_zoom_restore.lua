-- Use a temporary runtime; never read or modify the live desktop Zoom state.
local runtime = os.getenv('XDG_RUNTIME_DIR') or ''
assert(runtime:match('^/tmp/macshell%-zoom%-'), 'Use an isolated /tmp/macshell-zoom-* runtime')
local source = assert(arg[1], 'Pass the Zoom module path')
local state = runtime .. '/macshell-zoom-state.tsv'
local events, timers, repeatTimers, windows, nativeRects
local function copy(r) return {x=r.x,y=r.y,w=r.w,h=r.h} end
local function rect(w) return {x=w.at.x,y=w.at.y,w=w.size.x,h=w.size.y} end
local function place(w,r) w.at={x=r.x,y=r.y};w.size={x=r.w,y=r.h} end
local function emit(name,w)
    for _,fn in ipairs(events[name] or {}) do fn(w) end
end
local function flush()
    local attempts=0
    while #timers>0 do
        attempts=attempts+1;assert(attempts<50,'fullscreen event loop did not settle')
        local pending=timers;timers={};for _,fn in ipairs(pending) do fn() end
    end
end
local function loadModule()
    events={};timers={};repeatTimers={}
    hl={
        on=function(name,fn) events[name]=events[name] or {};table.insert(events[name],fn) end,
        timer=function(fn,options)
            if options.type=='repeat' then repeatTimers[#repeatTimers+1]=fn else timers[#timers+1]=fn end
        end,
        get_window=function(selector) return windows[selector] end,
        get_windows=function() local out={};for _,w in pairs(windows) do out[#out+1]=w end;return out end,
        exec_scheduled_prop_refresh_immediately=function() end,dsp={window={}}
    }
    for _,kind in ipairs({'resize','move','fullscreen_state','tag'}) do
        hl.dsp.window[kind]=function(args) return {kind=kind,args=args} end
    end
    hl.dispatch=function(op)
        local w,a=op.args.window,op.args
        if op.kind=='move' then
            local offset=w.zoomPlacementOffset and w.fullscreen_client==1 and w.size.x==1280 and w.zoomPlacementOffset or 0
            w.at={x=a.x,y=a.y+offset}
        elseif op.kind=='resize' then w.size={x=a.x,y=a.y}
        elseif op.kind=='fullscreen_state' then
            local old=w.fullscreen
            w.fullscreen=a.internal;w.fullscreen_client=a.client
            if old~=0 and a.internal==0 and nativeRects[w.address] then
                place(w,nativeRects[w.address]);nativeRects[w.address]=nil
            end
            if old~=w.fullscreen then emit('window.fullscreen',w) end
        end
    end
    return dofile(source)
end
local function setup(sid)
    os.remove(state);windows={};nativeRects={}
    local w={address='0xab12',stable_id=sid or 'a17f',mapped=true,hidden=false,floating=true,
        at={x=130,y=120},size={x=850,y=600},fullscreen=0,fullscreen_client=0,workspace={name='1'},
        monitor={x=0,y=0,width=1280,height=800,scale=1,transform=0,
                 reserved={left=0,right=0,top=28,bottom=64}}}
    windows['address:'..w.address]=w
    return w,loadModule()
end
local function nativeMaximize(w)
    nativeRects[w.address]=rect(w)
    w.fullscreen=1;w.fullscreen_client=1
    place(w,{x=0,y=28,w=1280,h=708})
    emit('window.fullscreen',w);flush()
end
local function assertNormal(w,label)
    assert(w.at.x==130 and w.at.y==120 and w.size.x==850 and w.size.y==600,label)
    assert(w.fullscreen==0 and w.fullscreen_client==0,label..': fullscreen states not cleared')
end

-- Real Hyprland stable IDs are hexadecimal strings, including all-digit IDs.
for _,sid in ipairs({'a17f','1234'}) do
    local w,zoom=setup(sid)
    nativeMaximize(w)
    assert(zoom.isZoomed(w),'native maximize should become independent Zoom')
    zoom=loadModule();flush()
    assert(zoom.isZoomed(w),'config reload lost the saved Zoom record for stable ID '..sid)
    zoom.restore(w);flush()
    assertNormal(w,'restore after config reload for '..sid)
end

do
    local w,zoom=setup()
    -- A server decoration can offset the actual floating client rectangle
    -- from the placement request. A rules/focus refresh must not treat the
    -- compositor's own placement as a user drag and throw away normal size.
    w.zoomPlacementOffset=28
    nativeMaximize(w)
    emit('window.update_rules',w);flush()
    assert(zoom.isZoomed(w),'decoration placement offset must retain Zoom state')
    zoom=loadModule();flush()
    emit('window.active',w);flush()
    assert(zoom.isZoomed(w),'decoration placement offset after reload must retain Zoom state')
    nativeMaximize(w)
    assert(not zoom.isZoomed(w),'green traffic light must restore after decorated placement')
    assertNormal(w,'green restore with decoration offset')
end

do
    local w,zoom=setup()
    for _=1,4 do
        nativeMaximize(w)
        -- The green control toggles compositor maximize from client-only Zoom.
        nativeMaximize(w)
        assert(not zoom.isZoomed(w),'a second green-button request must restore')
        assertNormal(w,'repeated green-button maximize/restore')
    end
end

do
    local w,zoom=setup()
    zoom.enter(w)
    nativeRects[w.address]=rect(w)
    w.fullscreen=2;w.fullscreen_client=2
    place(w,{x=0,y=0,w=1280,h=800});emit('window.fullscreen',w);flush()
    w.fullscreen=0;w.fullscreen_client=0
    emit('window.fullscreen',w);flush()
    assert(zoom.isZoomed(w) and w.fullscreen_client==1,'F11 exit should resume preceding Zoom')
    zoom.restore(w);flush();assertNormal(w,'green-button restore after F11')
end

do
    local w,zoom=setup();zoom.enter(w)
    -- Client unmaximize can arrive before the compositor clears its own state.
    nativeRects[w.address]=rect(w)
    w.fullscreen=1;w.fullscreen_client=0
    emit('window.update_rules',w);flush()
    assert(not zoom.isZoomed(w),'client unmaximize must not be interpreted as a fresh maximize')
    assertNormal(w,'client unmaximize before compositor state catches up')
end

do
    local w,zoom=setup();zoom.enter(w)
    -- Hyprland only emits window.fullscreen for internal-mode changes. A
    -- client-only unmaximize with sync_fullscreen=false emits no such event.
    w.fullscreen_client=0
    for _,fn in ipairs(repeatTimers) do fn() end
    flush()
    assert(not zoom.isZoomed(w),'client-only restore without an event must still be handled')
    assertNormal(w,'client-only unmaximize without a compositor event')
end

do
    local w,zoom=setup();zoom.enter(w)
    -- Unchanged mode observations must leave a moved window untouched until
    -- its normal move/rules event arrives, preserving existing drag behavior.
    w.at.x=140
    for _=1,5 do
        for _,fn in ipairs(repeatTimers) do fn() end
        flush()
    end
    assert(zoom.isZoomed(w) and w.at.x==140,'stable-mode polling must not reconcile geometry')
end

do
    local w,zoom=setup();zoom.enter(w)
    nativeRects[w.address]=rect(w)
    w.fullscreen=2;w.fullscreen_client=2
    place(w,{x=0,y=0,w=1280,h=800})
    for _,fn in ipairs(repeatTimers) do fn() end
    flush()
    w.fullscreen=0;w.fullscreen_client=0
    for _,fn in ipairs(repeatTimers) do fn() end
    flush()
    assert(zoom.isZoomed(w) and w.fullscreen_client==1,'observed F11 exit should resume preceding Zoom')
    zoom.restore(w);flush();assertNormal(w,'restore after observed fullscreen round trip')
end

do
    local w,zoom=setup();zoom.enter(w)
    nativeRects[w.address]=rect(w)
    w.fullscreen=2;w.fullscreen_client=2
    place(w,{x=0,y=0,w=1280,h=800});emit('window.fullscreen',w);flush()
    -- Some clients return from F11 to native maximized rather than state 0.
    w.fullscreen=1;w.fullscreen_client=1
    place(w,{x=0,y=28,w=1280,h=708});emit('window.fullscreen',w);flush()
    assert(zoom.isZoomed(w),'F11 exit to native maximized must preserve the previous Zoom')
    nativeMaximize(w)
    assert(not zoom.isZoomed(w),'the next green-button click must restore after leaving F11')
    assertNormal(w,'restore after F11 exits to maximized')
end

do
    local w,zoom=setup();zoom.enter(w)
    w.stable_id='new-window'
    zoom=loadModule();flush()
    assert(not zoom.isZoomed(w),'a reused address must not inherit another window\'s rectangle')
end

do
    local w,zoom=setup();zoom.enter(w)
    -- Shell layer surfaces disappear and remap independently of config reload.
    -- The work area can change before a rules event or after layer.opened.
    w.monitor.reserved.top=0;w.monitor.reserved.bottom=0
    emit('window.update_rules',w);flush()
    assert(zoom.isZoomed(w) and w.at.y==0 and w.size.y==800,
        'work-area changes must reflow Zoom instead of releasing its lock')
    emit('layer.closed');flush()
    emit('layer.opened');flush()
    w.monitor.reserved.top=28;w.monitor.reserved.bottom=64
    for _,fn in ipairs(repeatTimers) do fn() end
    flush()
    assert(zoom.isZoomed(w) and w.at.y==28 and w.size.y==708,
        'late layer reservation must restore Zoom bounds after shell reload')
    -- A remap can also change geometry with the final work area unchanged.
    w.at.y=56
    emit('layer.opened');flush()
    assert(zoom.isZoomed(w) and w.at.y==28,'layer remap must not leave Zoom shifted down')
    zoom.restore(w);flush();assertNormal(w,'normal restore after shell reload')
end

do
    local w,zoom=setup();zoom.enter(w)
    w.fullscreen=2;w.fullscreen_client=2
    place(w,{x=0,y=0,w=1280,h=800});emit('window.fullscreen',w);flush()
    emit('monitor.layout_changed');emit('layer.closed');emit('layer.opened');flush()
    assert(w.fullscreen==2 and w.fullscreen_client==2 and w.at.y==0 and w.size.y==800,
        'shell/monitor reflow must leave genuine fullscreen in native screen bounds')
end

do
    local w,zoom=setup();zoom.enter(w)
    nativeRects[w.address]=rect(w)
    w.fullscreen=1;w.fullscreen_client=1
    emit('window.fullscreen',w)
    emit('layer.opened');flush()
    assert(not zoom.isZoomed(w),'layer remap must not cancel a pending green-button restore')
    assertNormal(w,'green-button restore racing shell reload')
end

for _,top in ipairs({28,56}) do
    local w,zoom=setup()
    -- Older reloads could lose the original record and then remember the
    -- expanded rectangle as "normal" on the next maximize request.
    place(w,{x=0,y=top,w=1280,h=708});zoom.enter(w)
    zoom=loadModule();flush();zoom.restore(w);flush()
    assert(w.size.x<1280 and w.size.y<708,'a damaged full-size restore rectangle must not leave the window expanded')
    assert(w.fullscreen==0 and w.fullscreen_client==0 and not zoom.isZoomed(w))
end
os.remove(state)
print('Zoom restore: IDs, config/shell reload, layer reservations, green-toggle races, F11 and address reuse passed.')
