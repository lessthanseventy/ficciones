-- ivysaur — the laptop. Hybrid Intel/NVIDIA, eDP-1 + a Samsung 27" on the dock.
-- GPU selection (Intel first for battery, NVIDIA fallback)
-- cardN, not by-path: aquamarine splits this list on ":" and by-path names contain them (the
-- 2026-09-06 crash on login). Arch numbers simpledrm as card0 (Intel=card2, NVIDIA=card1);
-- NixOS will number them differently — re-check on the first ivysaur boot.
hl.env("AQ_DRM_DEVICES", "/dev/dri/card2:/dev/dri/card1")

-- Hybrid GPU workarounds — uncomment if stable Hyprland still hangs on page-flip.
-- hl.env("AQ_NO_MODIFIERS", "1")
-- hl.env("AQ_MGPU_NO_EXPLICIT", "1")

local external = "desc:Samsung Electric Company LS27D36xG"

hl.monitor({ output = "eDP-1", mode = "1920x1200@59.95", position = "0x0", scale = 1 })
hl.monitor({ output = external, mode = "preferred", position = "auto", scale = "auto" })

-- Persistent workspaces (eDP-1 owns 1, external owns 2-10)
hl.workspace_rule({ workspace = "1", monitor = "eDP-1", persistent = true, default = true })
hl.workspace_rule({ workspace = "2", monitor = external, persistent = true, default = true })
for i = 3, 10 do
    hl.workspace_rule({ workspace = tostring(i), monitor = external, persistent = true })
end
