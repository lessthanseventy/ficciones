-- ivysaur — the laptop. Hybrid Intel/NVIDIA, eDP-1 + a Samsung 27" on the dock.
-- GPU selection (Intel first for battery, NVIDIA fallback)
-- cardN, not by-path: aquamarine splits this list on ":" and by-path names contain them (the
-- 2026-09-06 crash on login). But cardN is not stable either — it depends on whether simpledrm
-- claimed a node this boot, so it differs across Arch, NixOS, and (observed 2026-09-12) two boots
-- of the same Arch install. The PCI addresses ARE stable, so resolve those to whatever cardN they
-- are right now. If resolution fails we set nothing: aquamarine choosing its own order is
-- recoverable, a wrong list is a compositor that never starts (hyprland.lua:49).
local function card_at(pci)
    local pipe = io.popen("readlink -f /dev/dri/by-path/pci-" .. pci .. "-card 2>/dev/null")
    if not pipe then return nil end
    local dev = pipe:read("*l")
    pipe:close()
    -- the exact "-card" suffix, so simpledrm's pci-<addr>-platform-simple-framebuffer.0-card
    -- cannot match; and a cardN path has no ":" for aquamarine to split on
    return dev and dev:match("^/dev/dri/card%d+$") or nil
end
local intel = card_at("0000:00:02.0") -- Iris Xe
local nvidia = card_at("0000:01:00.0") -- RTX 4060 Max-Q
if intel and nvidia then
    hl.env("AQ_DRM_DEVICES", intel .. ":" .. nvidia)
end

-- Hybrid GPU workarounds — uncomment if stable Hyprland still hangs on page-flip.
-- hl.env("AQ_NO_MODIFIERS", "1")
-- hl.env("AQ_MGPU_NO_EXPLICIT", "1")

local external = "desc:Samsung Electric Company LS27D36xG"

-- Mirror is decided once a session: the first load reads display.mirror from the shell's settings
-- (on unless false) and writes the answer to this instance's runtime dir; reloads read it back.
-- Turning a mirror on in a running session crashed Hyprland 0.56.2; the shell only ever breaks
-- one, by writing "separate" there and reloading (shell/lib/display.ts).
local function screens()
    local path = os.getenv("XDG_RUNTIME_DIR") .. "/hypr/" .. os.getenv("HYPRLAND_INSTANCE_SIGNATURE") .. "/ficciones-screens"
    local f = io.open(path)
    if f then
        local v = f:read("*l")
        f:close()
        return v
    end
    local s = io.open(os.getenv("HOME") .. "/.config/ficciones/shell.json")
    local text = s and s:read("*a") or ""
    if s then s:close() end
    -- a string match, not a JSON parse: the file is the shell's own one-key-a-line dump
    local v = text:match('"display%.mirror"%s*:%s*false') and "separate" or "mirror"
    f = io.open(path, "w")
    if f then
        f:write(v, "\n")
        f:close()
    end
    return v
end

hl.monitor({ output = "eDP-1", mode = "1920x1200@59.95", position = "0x0", scale = 1 })
hl.monitor({ output = external, mode = "preferred", position = "auto", scale = "auto", mirror = screens() == "mirror" and "eDP-1" or nil })

-- Persistent workspaces (eDP-1 owns 1, external owns 2-10)
hl.workspace_rule({ workspace = "1", monitor = "eDP-1", persistent = true, default = true })
hl.workspace_rule({ workspace = "2", monitor = external, persistent = true, default = true })
for i = 3, 10 do
    hl.workspace_rule({ workspace = tostring(i), monitor = external, persistent = true })
end
