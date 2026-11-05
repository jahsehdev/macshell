-- Native cursor magnification; this module is loaded by hyprland.lua.
local data = os.getenv("XDG_DATA_HOME") or ((os.getenv("HOME") or "~") .. "/.local/share")
hl.plugin.load(data .. "/macshell/shake-to-find/shake-to-find.so")
-- Defaults: enabled, maximum 4x. Configure after the plugin has loaded:
-- hl.config({plugin = {macshell_shake = {enabled = 1, max_scale = 4.0}}})
