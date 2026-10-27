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
            local n = {}; for i=2,10 do n[i]=tonumber(fields[i]) end
            if n[2] and n[3] and n[4] and n[5] and n[6] and n[7] and n[8] and n[9] and n[10] then
                records[fields[1]]={sid=n[2],normal={x=n[3],y=n[4],w=n[5],h=n[6]},inset={l=n[7],t=n[8],r=n[9],b=n[10]}}
            end
        end
    end
    f:close()
end
local function record(w)
    local r=records[w.address]
    if r and r.sid ~= w.stable_id then records[w.address]=nil; return nil end
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
    return w and w.mapped and not w.hidden and w.monitor and w.workspace and w.workspace.name ~= 'special:minimized'
end
local function sameRect(a,b)
    return b and math.abs(a.x-b.x)<4 and math.abs(a.y-b.y)<4 and math.abs(a.w-b.w)<4 and math.abs(a.h-b.h)<4
end
function M.restore(w, keepGeometry)
    local r=record(w); if not r then return end
    local addr=w.address; busy[addr]=true; records[addr]=nil
    hl.dispatch(hl.dsp.window.fullscreen_state({window=w,internal=0,client=0}))
    hl.dispatch(hl.dsp.window.tag({window=w,tag='-' .. tag}))
    if not keepGeometry then place(w,r.normal) end
    busy[addr]=nil; save()
end
function M.enter(w)
    if not valid(w) or not w.floating then return end
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
    local b=bounds(w,old); if b then place(w,b) end
    busy[addr]=nil; save()
end
local function reconcile(w, intent)
    if not valid(w) or busy[w.address] then return end
    local r=record(w)
    if intent == 'restore' and r then M.restore(w); return end
    if intent == 'enter' and r then M.enter(w); return end
    if w.fullscreen == 1 then M.enter(w); return end
    if not r then
        if w.fullscreen_client == 1 then M.enter(w) end
        return
    end
    -- A client can request exit while the compositor is still in fullscreen.
    -- Process that request before reconciling an entry into genuine fullscreen.
    if w.fullscreen_client == 0 then
        if r.inFullScreen then
            r.inFullScreen=nil; M.enter(w)
        else
            -- A Dock tear-off may already have supplied a new floating rectangle.
            M.restore(w, not sameRect(rect(w), bounds(w,r)))
        end
        return
    end
    -- Genuine fullscreen remains native. Returning from F11 resumes Zoom.
    if w.fullscreen == 2 or w.fullscreen_client == 2 then
        r.inFullScreen=true
        if w.fullscreen ~= 2 or w.fullscreen_client ~= 2 then hl.dispatch(hl.dsp.window.fullscreen_state({window=w,internal=2,client=2})) end
        return
    end
    local b=bounds(w,r)
    if b and not sameRect(rect(w),b) then
        -- A native title-row drag (or compositor move/resize) has changed the
        -- floating rectangle. Release Zoom without undoing the user's move.
        M.restore(w,true)
    end
end
local function queue(w,intent)
    if not w or busy[w.address] then return end
    local addr=w.address
    if pending[addr] then if intent then pending[addr].intent=intent end; return end
    pending[addr]={intent=intent}
    hl.timer(function()
        local job=pending[addr]; pending[addr]=nil
        local current=hl.get_window('address:' .. addr)
        if current then reconcile(current, job and job.intent) end
    end,{timeout=1,type='oneshot'})
end
hl.on('window.fullscreen',function(w)
    if not w or busy[w.address] then return end
    queue(w,w.fullscreen == 1 and record(w) and 'restore' or nil)
end)
hl.on('window.update_rules',function(w)
    if w and (w.fullscreen == 1 or w.fullscreen_client == 1 or record(w)) then queue(w) end
end)
hl.on('window.active',function(w) if w and (w.fullscreen == 1 or w.fullscreen_client == 1 or record(w)) then queue(w) end end)
hl.on('window.move_to_workspace',function(w) if w and record(w) then queue(w,'enter') end end)
hl.on('monitor.layout_changed',function()
    for _,w in ipairs(hl.get_windows()) do if record(w) then queue(w,'enter') end end
end)
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
function M.isZoomed(w) return record(w) ~= nil end
return M
