-- This is an example Hyprland Lua config file.
-- Refer to the wiki for more information.
-- https://wiki.hypr.land/Configuring/Start/

-- Please note not all available settings / options are set here.
-- For a full list, see the wiki

-- You can (and should!!) split this configuration into multiple files
-- Create your files separately and then require them like this:
-- require("myColors")

-- Native windows use a fixed continuous curve, independent of the Dock slider.
local continuousCornerPower = 2.7


------------------
---- MONITORS ----
------------------

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})



---------------------
---- MY PROGRAMS ----
---------------------

-- Set programs that you use
local terminal    = "@BIN_DIR@/macshell-terminal"
local fileManager = "$HOME/.local/bin/macshell-files"
local menu        = "hyprlauncher"


-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:
--
-- hl.on("hyprland.start", function () 
--   hl.exec_cmd(terminal)
--   hl.exec_cmd("nm-applet")
--   hl.exec_cmd("waybar & hyprpaper & firefox")
-- end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "MacTahoe-cursors")   -- macOS cursors (MacTahoe-icon-theme, light)
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")       -- >> qt6ct (widgets = Kvantum/MacTahoe, icons = MacTahoe-dark)


-----------------------
----- PERMISSIONS -----
-----------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
-- Please note permission changes here require a Hyprland restart and are not applied on-the-fly
-- for security reasons

-- hl.config({
--   ecosystem = {
--     enforce_permissions = true,
--   },
-- })

-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")


-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 20,

        -- Tanpa border di semua window (macOS-like)
        border_size = 0,

        col = {
            active_border   = "rgba(00000000)",
            inactive_border = "rgba(00000000)",
        },

        -- Resize window dengan drag di tepi/border (tanpa modifier)
        resize_on_border = true,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },

    decoration = {
        -- Toolbar windows use 26px; compact/titlebar windows override below.
        -- Values above 20 belong here, not in Lua window_rule.rounding.
        rounding       = 26,
        rounding_power = continuousCornerPower,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = false,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled   = true,
            -- Launchpad asks for a deep backdrop blur; this also makes the
            -- bar / dock / spotlight glass a little softer (same system blur).
            size      = 8,
            passes    = 3,
            vibrancy  = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

-- Default springs
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
    dwindle = {
        preserve_split = true, -- You probably want this
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/ for more
hl.config({
    scrolling = {
        fullscreen_on_one_column = true,
    },
})

----------------
----  MISC  ----
----------------

hl.config({
    misc = {
        force_default_wallpaper = -1,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = false, -- If true disables the random hyprland logo / anime girl background. :(
    },
})


---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        -- Pointer focus follows the cursor; keyboard focus changes on click.
        -- Mode 0 redirects pointer events to the active window during focus
        -- changes, which can leave floating apps needing another click to type.
        follow_mouse = 2,
        -- Keep floating windows from taking keyboard focus on hover.
        float_switch_override_focus = 0,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})


---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
local closeWindowBind = hl.bind(mainMod .. " + C", hl.dsp.window.close())
-- closeWindowBind:set_enabled(false)
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle only

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

-- NOTE: the stock example rule "suppress-maximize-events" (suppress_event = "maximize")
-- is intentionally removed here. It made the clients' own maximize requests a no-op,
-- which silently broke the green traffic light in CSD apps such as Firefox.

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})



-- >>> macOS-style floating windows >>>
-- Semua window dibuat floating (tidak di-tile/grid). Posisi bebas dipindah dan
-- tidak akan snap balik ke posisi awal seperti layout dwindle.
hl.window_rule({
    name  = "macos-float-all",
    match = { class = ".*" },
    float = true,
})
-- Zoom uses independent floating geometry with client maximize state, rather
-- than taking the workspace's one native fullscreen/maximize slot.
hl.window_rule({name = "macshell-independent-zoom", match = {tag = "macshell-zoomed"}, sync_fullscreen = false})
local windowZoom = dofile((os.getenv("HOME") or "~") .. "/.config/hypr/macshell_zoom.lua")
-- Focus and render order are separate in Hyprland 0.56: a floating window
-- previously raised over maximize/fullscreen keeps allowed_over_fullscreen=true.
-- Raising the fullscreen target alone does not clear that separate render pass.
local syncingWindowStack = false
local function syncWindowStack(win)
    if syncingWindowStack or not win or not win.active or not win.mapped or win.hidden then return end
    local workspace = win.workspace
    if not workspace or workspace.name == "special:minimized" then return end
    if not win.floating and win.fullscreen == 0 then return end

    syncingWindowStack = true
    if win.fullscreen ~= 0 then
        local windows = hl.get_windows()
        -- Reverse traversal preserves the other windows' relative stacking order.
        for i = #windows, 1, -1 do
            local other = windows[i]
            local ws = other.workspace
            if other ~= win and other.mapped and not other.hidden and other.floating
                and not other.pinned and other.fullscreen == 0 and other.allowed_over_fullscreen
                and ws and ws.id == workspace.id then
                hl.dispatch(hl.dsp.window.alter_zorder({window = other, mode = "bottom"}))
            end
        end
    end
    hl.dispatch(hl.dsp.window.alter_zorder({window = win, mode = "top"}))
    syncingWindowStack = false
end
hl.on("window.active", syncWindowStack)
-- Maximize can change while focus stays on the same window. Resolve the current
-- target after the fullscreen transition, rather than retaining an old window.
local function syncCurrentWindowStack()
    hl.timer(function() syncWindowStack(hl.get_active_window()) end, {timeout = 1, type = "oneshot"})
end
hl.on("window.fullscreen", syncCurrentWindowStack)
-- <<< macOS-style floating windows <<<

-- Window baru yang kebuka kekecilan (contoh Firefox ~552x304) dibesarkan ke 75%
-- layar dan disusun bertingkat. Dialog kecil (<30%) atau window besar (>50%)
-- dibiarkan apa adanya.
local cascadeIndex = 0

local function sizeAxis(v, axis)
    if type(v) ~= "table" then return nil end
    return v[axis] or v[axis == "x" and 1 or 2]
end

hl.on("window.open", function(win)
    local addr = win.address
    hl.timer(function()
        local w = hl.get_window("address:" .. addr)
        if not w or not w.floating or w.fullscreen ~= 0 then return end
        local m = w.monitor
        if not m then return end

        local sw, sh = sizeAxis(w.size, "x"), sizeAxis(w.size, "y")
        if not sw or not sh then return end

        -- hanya window yang ukurannya 30-50% dari layar (default kecil)
        local rw, rh = sw / m.width, sh / m.height
        if rw < 0.30 or rw > 0.50 or rh < 0.30 or rh > 0.50 then return end

        local nw = math.floor(m.width  * 0.75)
        local nh = math.floor(m.height * 0.75)
        local step = 28
        local idx  = cascadeIndex % 5
        cascadeIndex = cascadeIndex + 1

        local nx = math.floor((m.width  - nw) / 2) + (idx - 2) * step
        local ny = math.floor((m.height - nh) / 2) + (idx - 2) * step
        nx = math.max(20, math.min(nx, m.width  - nw - 20))
        ny = math.max(40, math.min(ny, m.height - nh - 20))

        hl.dispatch(hl.dsp.window.resize({ window = "address:" .. addr, x = nw, y = nh, exact = true }))
        hl.dispatch(hl.dsp.window.move({ window = "address:" .. addr, x = nx, y = ny }))
    end, { timeout = 150, type = "oneshot" })
end)

-- ── Top-bar window guard ──────────────────────────────────────────────
-- Layer-shell exclusive zones keep tiled/maximized windows below the menu
-- bar, but floating windows can still be dragged up over it. Clamp the top
-- edge of every mapped floating window to the monitor's reserved top area
-- (the bar height, 0 when the bar is off), so app windows never punch
-- through the top bar. Fullscreen windows are left alone on purpose.
local topBarGuard = true
local topBarGuardBusy = {}

local function clampWindowBelowBar(w)
    if not w.floating or not w.mapped or w.hidden or w.fullscreen ~= 0 then return end
    -- pinned windows are deliberately placed overlays (e.g. the full-screen
    -- Launchpad backdrop), not normal app windows: leave them where they are
    if w.pinned or w.title == "qs-launchpad-backdrop" then return end
    local m = w.monitor
    local top = m and m.reserved and m.reserved.top or 0
    if top <= 0 or not w.at then return end
    if w.at.y >= top - 0.5 then return end

    local addr = w.address
    if topBarGuardBusy[addr] then return end
    topBarGuardBusy[addr] = true
    hl.dispatch(hl.dsp.window.move({ window = "address:" .. addr, x = w.at.x, y = top }))
    -- short cooldown so a clamped window is not dispatched on every tick
    hl.timer(function() topBarGuardBusy[addr] = nil end, { timeout = 120, type = "oneshot" })
end

if topBarGuard then
    hl.timer(function()
        for _, w in ipairs(hl.get_windows()) do clampWindowBelowBar(w) end
    end, { timeout = 100, type = "repeat" })
end

-- Start the Launchpad layer before MacShell. Both live on WlrLayer.Top, and
-- Hyprland stacks a newly mapped Top surface above the older ones: mapping the
-- Launchpad first keeps the real menu bar and Dock (and their popups) above it.
hl.on("hyprland.start", function()
    hl.exec_cmd("$HOME/.local/bin/launchpad-start --login")
end)

-- >>> MacShell (added by install.sh) >>>
-- autostart: waits for the compositor, restarts MacShell if it crashes (remove this block to undo)
hl.on("hyprland.start", function()
    hl.exec_cmd("sh @BIN_DIR@/macshell-start")
end)
-- Liquid Glass: blur behind the shell surfaces
hl.layer_rule({ name = "macdock",  match = { namespace = "macdock"  }, blur = true, ignore_alpha = 0.2,  no_anim = true })
hl.layer_rule({ name = "macspot",  match = { namespace = "macspot"  }, blur = true, ignore_alpha = 0.05, no_anim = true })
hl.layer_rule({ name = "macbarbg", match = { namespace = "macbarbg" }, blur = true, ignore_alpha = 0.05, no_anim = true })
hl.layer_rule({ name = "macshot",  match = { namespace = "macshot"  }, no_anim = true })
hl.layer_rule({ name = "macwidgets", match = { namespace = "macwidgets" }, no_anim = true })
hl.layer_rule({ name = "macwidgets-gallery", match = { namespace = "macwidgets-gallery" }, blur = true, ignore_alpha = 0.05, no_anim = true })
-- <<< MacShell <<<

-- >>> MacShell keybinds (from README) >>>
local qs = "qs -c MacShell ipc call "

hl.bind("SUPER + V",       hl.dsp.exec_cmd(qs .. "spotlight clipboard"))
hl.bind("SUPER + period",  hl.dsp.exec_cmd(qs .. "spotlight emoji"))
hl.bind("SUPER + Space",   hl.dsp.exec_cmd(qs .. "spotlight toggle"))
hl.bind("ALT + TAB",       hl.dsp.exec_cmd(qs .. "switcher next"))
hl.bind("CTRL + ALT + W",  hl.dsp.exec_cmd(qs .. "wallpapers toggle"))
hl.bind("PRINT",           hl.dsp.exec_cmd(qs .. "screenshot region"))
-- Screenshot: pilih area (drag) -> disimpan ke ~/Pictures/Screenshots + langsung dicopy ke clipboard
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd(qs .. "screenshot region"))

-- MacLock (lock screen)
hl.bind("SUPER + L",       hl.dsp.exec_cmd("sh ~/.config/quickshell/MacLock/lock-via-ipc.sh"))
-- <<< MacShell keybinds <<<

-- >>> Quickshell Launchpad >>>
-- Kept as its own Quickshell process; the helper starts it if it is not running yet.
hl.bind("SUPER + A", hl.dsp.exec_cmd("$HOME/.local/bin/launchpad-toggle"))
-- (started before MacShell above, so the bar/dock stack above this layer)
-- The backdrop is a normal window, so it blurs the desktop full-screen while
-- the top bar and dock (layer-shell) stay above it. No borders, no focus.
hl.window_rule({
    name = "qs-launchpad-backdrop",
    match = { title = "^qs-launchpad-backdrop$" },
    float = true,
    move = "0 0",
    size = "monitor_w monitor_h",
    decorate = false,
    border_size = 0,
    no_shadow = true,
    no_anim = true,
    no_focus = true,
    no_initial_focus = true,
    pin = true,
    -- blur only the wallpaper, not the windows behind the Launchpad
    xray = true,
})
-- The content layer deliberately has no blur of its own: the backdrop window
-- already blurs the desktop, and blurring it a second time would double the
-- background (very visible through the transparent content area).
hl.layer_rule({ name = "qs-launchpad", match = { namespace = "qs-launchpad" }, no_anim = true })
-- <<< Quickshell Launchpad <<<

-- Use application-owned titlebars only. Do not load compositor titlebar plugins.
-- Reference window styles: toolbar 26px, compact toolbar 20px, titlebar 16px.
-- Unknown applications inherit the toolbar radius; match installed applications
-- explicitly because Wayland does not expose a universal toolbar-style hint.
hl.window_rule({
    name = "macshell-compact-toolbar-corners",
    match = { class = "^(firefox|Firefox|zen|zen-browser|chromium|Chromium|google-chrome|Google-chrome|brave-browser|Brave-browser|spotify|Spotify|code|Code|Antigravity|discord|Discord|obsidian|Obsidian)$" },
    rounding = 20,
})
hl.window_rule({
    name = "macshell-clock-corners",
    match = { title = "^Clock$" },
    rounding = 20,
})
hl.window_rule({
    name = "macshell-titlebar-corners",
    match = { class = "^(org.gnome.Console|org.gnome.Terminal|kgx|kitty|Alacritty|alacritty|foot|footclient|com.mitchellh.ghostty|ghostty|tabby|Tabby|org.macshell.PhotoBooth|Photo Booth|tahoe-photobooth)$" },
    rounding = 16,
})

-- Window yang di-minimize lewat tombol kuning ada di special:minimized.
hl.workspace_rule({
    workspace = "special:minimized",
    gaps_in   = 10,
    gaps_out  = 30,
})

hl.bind("SUPER + SHIFT + M", hl.dsp.workspace.toggle_special("minimized"))
hl.bind("SUPER + M", hl.dsp.exec_cmd("sh ~/.config/hypr/minimize.sh minimize"))
hl.bind("SUPER + SHIFT + mouse:272", hl.dsp.exec_cmd("sh ~/.config/hypr/minimize.sh restore"), { mouse = true })

-- Clamp interactive window geometry before it is painted; no correction timer.
hl.plugin.load((os.getenv("HOME") or "~") .. "/.local/share/macshell/top-boundary/top-boundary.so")
-- Fullscreen lock v1.2: Never-hide Dock work-area windows allow manual resize.
-- Fullscreen and expanded-window movement remain locked during dragging.
-- Restoring a window re-enables movement; programmatic placement stays intact.
hl.plugin.load((os.getenv("HOME") or "~") .. "/.local/share/macshell/fullscreen-lock/fullscreen-lock.so")
-- Recover keyboard focus when the cached active app survives a layer/popup
-- transition. Explicit clicks only; no focus-on-hover or focus polling.
hl.plugin.load((os.getenv("HOME") or "~") .. "/.local/share/macshell/click-focus/click-focus.so")
-- Supported GNOME apps use MacShell's existing Dock for native GTK minimize buttons
-- animation/restore path, including windows that were already open.
hl.plugin.load((os.getenv("HOME") or "~") .. "/.local/share/macshell/native-minimize/native-minimize.so")


-- Square corners follow actual screen-filling geometry, not client fullscreen
-- flags: F11/HTML fullscreen may change client state on a smaller floating window.
-- The controller removes this tag as soon as the window is restored or resized.
-- Keep this after application-specific normal rounding overrides.
hl.window_rule({name = "macshell-expanded-geometry",
    match = {tag = "macshell-square-window"}, rounding = 0})
-- Never-hide Dock: the controller clears the square tag so Zoom/Fill inherits
-- its toolbar/titlebar radius. Lua window_rule.rounding remains limited to 20.
