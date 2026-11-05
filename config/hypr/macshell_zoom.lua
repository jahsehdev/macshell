-- Independent macOS-style Zoom. The client stays maximized; the compositor
-- keeps a normal floating window, so other Zoom windows retain their size.
local M = {}
local records, busy, pending = {}, {}, {}
local tag = 'macshell-zoomed'
local statePath = (os.getenv('XDG_RUNTIME_DIR') or '/tmp') .. '/macshell-zoom-state.tsv'
local function selector(w) return 'address:' .. w.address end
local function rect(w)
    return {x=w.at.x, y=w.at.y, w=w.size.x, h=w.size.y}
end
-- Keep a small local trace of mode transitions, without titles or app content.
local traceLines={}
local function trace(event,w)
    traceLines[#traceLines+1]=table.concat({os.date('!%FT%TZ'),event,w.address,
        tostring(w.fullscreen),tostring(w.fullscreen_client),
        w.at.x,w.at.y,w.size.x,w.size.y},'\t')
    if #traceLines>48 then table.remove(traceLines,1) end
    local output=io.open((os.getenv('XDG_RUNTIME_DIR') or '/tmp') .. '/macshell-zoom-trace.log','w')
    if output then output:write(table.concat(traceLines,'\n')..'\n');output:close() end
end
local function save()
    local f = io.open(statePath, 'w')
    if not f then print('macshell: could not save independent Zoom state'); return end
    for addr, r in pairs(records) do
        f:write(table.concat({addr,r.sid,r.normal.x,r.normal.y,r.normal.w,r.normal.h,
            r.inset.l,r.inset.t,r.inset.r,r.inset.b}, '\t') .. '\n')
    end
    f:close()
end
local f = io.open(statePath, 'r')
if f then
    for line in f:lines() do
        local fields = {}; for v in line:gmatch('[^\t]+') do fields[#fields+1]=v end
        if #fields == 10 and fields[1]:match('^0x%x+$') then
            -- Hyprland stable_id is a hexadecimal string, not a Lua number.
            -- Keep it verbatim, including IDs made entirely of decimal digits.
            local n = {}; for i=3,10 do n[i]=tonumber(fields[i]) end
            if fields[2] ~= '' and n[3] and n[4] and n[5] and n[6] and n[7] and n[8] and n[9] and n[10] then
                records[fields[1]]={sid=fields[2],normal={x=n[3],y=n[4],w=n[5],h=n[6]},inset={l=n[7],t=n[8],r=n[9],b=n[10]}}
            end
        end
    end
    f:close()
end
local function record(w)
    local r=records[w.address]
    if r and tostring(r.sid) ~= tostring(w.stable_id) then records[w.address]=nil; return nil end
    return r
end
local function workArea(w)
    local m=w.monitor
    if not m then return nil end
    local reserved=m.reserved
    local rw,rh=m.width,m.height
    if m.transform % 2 == 1 then rw,rh=rh,rw end
    return {x=m.x+reserved.left,y=m.y+reserved.top,
        w=math.floor(rw/m.scale-reserved.left-reserved.right),
        h=math.floor(rh/m.scale-reserved.top-reserved.bottom)}
end
local function bounds(w,r)
    local a=workArea(w); if not a then return nil end
    local i=r.inset
    return {x=a.x+i.l,y=a.y+i.t,w=math.max(1,a.w-i.l-i.r),h=math.max(1,a.h-i.t-i.b)}
end
local function place(w, b)
    hl.dispatch(hl.dsp.window.resize({window=w,x=math.floor(b.w),y=math.floor(b.h),exact=true}))
    hl.dispatch(hl.dsp.window.move({window=w,x=math.floor(b.x),y=math.floor(b.y),exact=true}))
end
local function valid(w)
    return w and w.title ~= 'qs-launchpad-backdrop' and w.mapped and not w.hidden and w.monitor and w.workspace and w.workspace.name ~= 'special:minimized'
end
local function sameRect(a,b)
    return b and math.abs(a.x-b.x)<4 and math.abs(a.y-b.y)<4 and math.abs(a.w-b.w)<4 and math.abs(a.h-b.h)<4
end
local function atZoomBounds(w,r)
    local current=rect(w)
    -- Move dispatchers can apply decoration extents to the requested rectangle.
    -- Keep both the intended bounds and actual result of our own placement;
    -- neither is a user drag. Real moved/resized rectangles still release Zoom.
    return sameRect(current,bounds(w,r)) or sameRect(current,r.placed)
end
local function restoreBounds(w,r)
    local a=workArea(w)
    local expanded=bounds(w,r)
    local fullSize=expanded and math.abs(r.normal.w-expanded.w)<4 and math.abs(r.normal.h-expanded.h)<4
    if not fullSize then return r.normal end
    -- A lost pre-reload record can leave the expanded rectangle saved as
    -- "normal". The original is unrecoverable; use a centered normal window
    -- within the current menu-bar/Dock work area when the user requests restore.
    if not a then return r.normal end
    local width,height=math.max(1,math.floor(a.w*0.75)),math.max(1,math.floor(a.h*0.75))
    return {x=a.x+math.floor((a.w-width)/2),y=a.y+math.floor((a.h-height)/2),w=width,h=height}
end
function M.restore(w, keepGeometry)
    local r=record(w); if not r then return end
    trace(keepGeometry and 'restore-moved' or 'restore',w)
    local addr=w.address; busy[addr]=true; records[addr]=nil
    hl.dispatch(hl.dsp.window.fullscreen_state({window=w,internal=0,client=0}))
    hl.dispatch(hl.dsp.window.tag({window=w,tag='-' .. tag}))
    if not keepGeometry then place(w,restoreBounds(w,r)) end
    busy[addr]=nil; save()
    trace('restored',w)
end
function M.enter(w)
    if not valid(w) or not w.floating then return end
    trace('enter',w)
    local addr=w.address; busy[addr]=true
    local nativeRect = w.fullscreen == 1 and rect(w) or nil
    local old=record(w)
    hl.dispatch(hl.dsp.window.tag({window=w,tag='+' .. tag}))
    hl.exec_scheduled_prop_refresh_immediately()
    -- The tag's rule decouples client/compositor state before releasing the
    -- workspace's single native maximize slot. Hyprland restores normal geometry.
    hl.dispatch(hl.dsp.window.fullscreen_state({window=w,internal=0,client=1}))
    if not old then
        local a=workArea(w)
        local z=nativeRect or a
        old={sid=w.stable_id,normal=rect(w),inset={l=z.x-a.x,t=z.y-a.y,r=a.x+a.w-z.x-z.w,b=a.y+a.h-z.y-z.h}}
        records[addr]=old
    end
    old.inFullScreen=nil
    old.observedInternal=w.fullscreen
    old.observedClient=w.fullscreen_client
    local b=bounds(w,old); if b then place(w,b) end
    old.placed=rect(w)
    old.workArea=workArea(w)
    busy[addr]=nil; save()
    trace('zoomed',w)
end
local function reconcile(w, intent)
    if not valid(w) or busy[w.address] then return end
    local r=record(w)
    if intent == 'restore' and r then M.restore(w); return end
    -- A client can request exit while the compositor is still in fullscreen.
    -- Handle that before both native maximize and genuine fullscreen entries.
    if r and w.fullscreen_client == 0 then
        if r.inFullScreen then
            r.inFullScreen=nil; M.enter(w)
        else
            -- A Dock tear-off may already have supplied a new floating rectangle.
            M.restore(w, not atZoomBounds(w,r))
        end
        return
    end
    -- Shell layers and monitor changes may request reflow while F11 is active.
    -- Preserve native fullscreen before considering a return to floating Zoom.
    if r and (w.fullscreen == 2 or w.fullscreen_client == 2) then
        r.inFullScreen=true
        if w.fullscreen ~= 2 or w.fullscreen_client ~= 2 then hl.dispatch(hl.dsp.window.fullscreen_state({window=w,internal=2,client=2})) end
        return
    end
    if intent == 'enter' and r then M.enter(w); return end
    if w.fullscreen == 1 then M.enter(w); return end
    if not r then
        if w.fullscreen_client == 1 then M.enter(w) end
        return
    end
    -- A layer reservation is not a user drag. Rules/focus events may arrive
    -- before the layer event, so check the work area before releasing Zoom.
    if r.workArea and not sameRect(r.workArea,workArea(w)) then
        M.enter(w)
        return
    end
    local b=bounds(w,r)
    if b and not atZoomBounds(w,r) then
        -- A native title-row drag (or compositor move/resize) has changed the
        -- floating rectangle. Release Zoom without undoing the user's move.
        M.restore(w,true)
    end
end
local function queue(w,intent)
    if not w or busy[w.address] then return end
    local addr=w.address
    if pending[addr] then
        -- A shell layer remap must not overwrite an explicit green-button restore.
        if intent and pending[addr].intent ~= 'restore' then pending[addr].intent=intent end
        return
    end
    pending[addr]={intent=intent}
    hl.timer(function()
        local job=pending[addr]; pending[addr]=nil
        local current=hl.get_window('address:' .. addr)
        if current then reconcile(current, job and job.intent) end
    end,{timeout=1,type='oneshot'})
end
hl.on('window.fullscreen',function(w)
    if not w or busy[w.address] then return end
    trace('fullscreen-event',w)
    local r=record(w)
    -- F11 can exit back into native maximized state. Resume the existing Zoom
    -- rather than confusing that transition with a second green-button click.
    queue(w,w.fullscreen == 1 and r and not r.inFullScreen and 'restore' or nil)
end)
hl.on('window.update_rules',function(w)
    if w and (w.fullscreen == 1 or w.fullscreen_client == 1 or record(w)) then queue(w) end
end)
hl.on('window.active',function(w) if w and (w.fullscreen == 1 or w.fullscreen_client == 1 or record(w)) then queue(w) end end)
hl.on('window.move_to_workspace',function(w) if w and record(w) then queue(w,'enter') end end)
local function reflowZoom()
    for _,w in ipairs(hl.get_windows()) do if record(w) then queue(w,'enter') end end
end
hl.on('monitor.layout_changed',reflowZoom)
hl.on('layer.opened',reflowZoom)
hl.on('layer.closed',reflowZoom)
hl.on('window.destroy',function(w)
    if w and records[w.address] then records[w.address]=nil; pending[w.address]=nil; save() end
end)
-- Recover saved intent after rule refresh. Hyprland 0.56's standalone config
-- verifier has no event loop, so creating timers there crashes the verifier.
local verifying=false
local commandLine=io.open('/proc/self/cmdline','r')
if commandLine then
    verifying=commandLine:read('*a'):find('--verify-config',1,true) ~= nil
    commandLine:close()
end
-- With sync_fullscreen=false, a client-only unmaximize changes 1 -> 0 while
-- internal fullscreen stays 0. Hyprland emits no window.fullscreen event in
-- that case. Observe mode changes only on the windows we already own; stable
-- modes with unchanged work areas do not interfere with dragging.
if not verifying then
    M.stateWatcher=hl.timer(function()
        for addr in pairs(records) do
            local w=hl.get_window('address:' .. addr)
            local r=w and record(w)
            if r and valid(w) and not busy[addr] then
                local internal,client=w.fullscreen,w.fullscreen_client
                if r.observedInternal~=internal or r.observedClient~=client then
                    trace('mode-changed',w)
                    r.observedInternal=internal; r.observedClient=client
                    queue(w)
                elseif r.workArea and not sameRect(r.workArea,workArea(w)) then
                    -- Exclusive zones can commit after layer.opened without a
                    -- monitor-layout event. Reflow only when that area changes.
                    queue(w,'enter')
                end
            end
        end
    end,{timeout=80,type='repeat'})
end
local recoveryQueued=false
local function recoverSavedZoom()
    if verifying or recoveryQueued or not next(records) then return end
    recoveryQueued=true
    hl.timer(function()
        recoveryQueued=false
        for addr in pairs(records) do
            local w=hl.get_window('address:' .. addr)
            if w and record(w) then
                queue(w,(w.fullscreen==2 or w.fullscreen_client==2) and nil or 'enter')
            else records[addr]=nil end
        end
    end,{timeout=150,type='oneshot'})
end
hl.on('config.reloaded',recoverSavedZoom)
recoverSavedZoom()
if not verifying then
    local status=io.open((os.getenv('XDG_RUNTIME_DIR') or '/tmp') .. '/macshell-zoom.status','w')
    if status then status:write('restore-v6\n'); status:close() end
end
function M.isZoomed(w) return record(w) ~= nil end
return M
