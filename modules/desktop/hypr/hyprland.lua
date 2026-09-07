-- =============================================================================
--  Hyprland configuration (Lua — the .conf format is gone in 0.57)
--  Ported 1:1 from hyprland.conf on 2026-09-05; that file lives in git history only.
--  Reload with: hyprctl reload
--
--  Split: ~/.config/hypr/host.lua is hosts/<host>.lua (monitors, persistent workspaces,
--  AQ_DRM_DEVICES — home-manager picks it by ficciones.desktop.host) and
--  ~/.config/hypr/theme.lua is generated from modules/desktop/theme/palette.nix (colours,
--  fonts, GTK/Qt theme env). Both are plain Lua files loaded with dofile below.
-- =============================================================================

local home = os.getenv("HOME")
-- FICCIONES_HYPRDIR: scripts/hypr-lua-check.sh points a nested test instance at a scratch copy.
local hyprdir = os.getenv("FICCIONES_HYPRDIR") or (home .. "/.config/hypr")

-- -----------------------------------------------------------------------------
-- ENVIRONMENT VARIABLES
-- -----------------------------------------------------------------------------
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")

hl.env("XDG_MENU_PREFIX", "plasma-")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("MOZ_ENABLE_WAYLAND", "1")

hl.env("TERMINAL", "ghostty")
hl.env("BROWSER", "floorp")
hl.env("ZDOTDIR", home)
hl.env("GHOSTTY_ZSH_ZDOTDIR", home)

hl.env("XDG_DATA_DIRS", home .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share")

-- Cursor
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("HYPRCURSOR_SIZE", "24")

hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", "~/.local/state/quickshell/.venv")

-- Per-host lines (monitors, persistent workspaces, AQ_DRM_DEVICES): a monitor that does not
-- exist is harmless, but a wrong AQ_DRM_DEVICES is a compositor that never starts.
dofile(hyprdir .. "/host.lua")
-- Colours + the GTK/Qt theme env: generated from modules/desktop/theme/palette.nix.
dofile(hyprdir .. "/theme.lua")

-- -----------------------------------------------------------------------------
-- AUTOSTART — fires once at start, never on reload (the exec-once semantics).
-- -----------------------------------------------------------------------------
-- FICCIONES_HYPR_NO_AUTOSTART: set when this file is loaded by a nested test instance
-- (scripts/hypr-lua-check.sh) so it does not spawn a second shell, idle daemon, etc.
if not os.getenv("FICCIONES_HYPR_NO_AUTOSTART") then
    hl.on("hyprland.start", function()
        -- Under uwsm (NixOS) this exports the env and activates graphical-session.target,
        -- which is what the shell's user unit waits on. On Arch there is no uwsm: a no-op.
        hl.exec_cmd("command -v uwsm >/dev/null && uwsm finalize")
        -- The astal shell (modules/desktop/shell). On NixOS the user unit owns it (this line
        -- would win the race and leave the unit a dead client); on Arch there is no uwsm
        -- session, so this does. `astal-shell` is a client when one is running, so a reload
        -- never doubles it.
        hl.exec_cmd("test -e /etc/NIXOS || astal-shell")
        -- night light daemon; the shell's hub toggles it (hyprctl hyprsunset temperature / identity)
        hl.exec_cmd("hyprsunset")
        hl.exec_cmd("easyeffects --hide-window --service-mode")
        hl.exec_cmd("hypridle")
        -- hyprexpo: on NixOS modules/os puts the .so here; on Arch hyprpm owns it, and nothing
        -- loads hyprpm's plugins at start unless asked — without this the plugin.hyprexpo.*
        -- keys in theme.lua are "unknown" until someone runs `hyprpm reload` (2026-09-07)
        hl.exec_cmd("test -f /etc/hypr/plugins/hyprexpo.so && hyprctl plugin load /etc/hypr/plugins/hyprexpo.so")
        hl.exec_cmd("test -e /etc/NIXOS || hyprpm reload -n")
        hl.exec_cmd("bash -c 'wl-paste --type text  --watch cliphist store'")
        hl.exec_cmd("bash -c 'wl-paste --type image --watch cliphist store'")
        -- A Hyprland restart takes the socket away: the agent exits, Restart=on-failure respawns
        -- it against no display ~5 times in 2 s, and the unit trips its start limit — a plain
        -- `start` within the next 10 s is refused ("repeated too quickly", 2026-09-07).
        hl.exec_cmd("systemctl --user reset-failed hyprpolkitagent; systemctl --user start hyprpolkitagent")
        hl.exec_cmd("wgtray")
    end)
end

-- -----------------------------------------------------------------------------
-- LOOK AND FEEL
-- -----------------------------------------------------------------------------
hl.config({
    general = {
        gaps_in = 12,
        gaps_out = 12,
        border_size = 2,
        -- col.active_border / col.inactive_border: theme.lua
        resize_on_border = false,
        allow_tearing = false,
        layout = "scrolling",
    },

    decoration = {
        rounding = 8,
        rounding_power = 2,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        dim_inactive = true,
        dim_strength = 0.15, -- subtle darkening of unfocused window contents

        shadow = {
            enabled = true,
            range = 30,
            render_power = 3,
            offset = { 0, 2 },
            color = "0x40000000",
        },

        blur = {
            enabled = false,
        },
    },

    animations = { enabled = true },

    -- SCROLLING LAYOUT (niri-like)
    scrolling = {
        -- A lone column ignores column_width and takes the full usable width.
        fullscreen_on_one_column = true,
        -- 0.8 of 1844px usable (1920 - 64 rail - 12 margin) = ~1475px focused, leaving the
        -- neighbour ~369px of deliberate peek. Two columns no longer tile flush.
        column_width = 0.8,
        -- colresize +conf/-conf (Super+R / Super+Shift+R) steps this ladder; it must contain
        -- column_width or the first press jumps straight to the smallest entry.
        explicit_column_widths = "0.33333,0.5,0.66667,0.8,1.0",
        -- 0 centres the focused column. 1 scrolls the minimum needed to reveal it, which parks
        -- a newly-revealed column flush against the screen edge as a sliver.
        focus_fit_method = 0,
        follow_focus = true,
        wrap_focus = false,
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        focus_on_activate = false,
        -- fullscreen-only VRR (was 1 = always-on); avoids desktop flicker on the mixed-refresh
        -- dual-monitor setup
        vrr = 2,
    },

    -- Let fullscreen apps (video, games) bypass compositing and go straight to the display
    -- plane — skips the i915 composite+flip path. Added 2026-07-02.
    render = { direct_scanout = 1 },

    -- Never warp the pointer: a focus change (movefocus, the bar's window cells, a new window)
    -- leaves the mouse where the hand left it (Andrew, 2026-09-05).
    cursor = { no_warps = true, warp_on_change_workspace = false },

    binds = {
        allow_workspace_cycles = false,
        workspace_back_and_forth = false,
        movefocus_cycles_fullscreen = false,
        movefocus_cycles_groupfirst = false,
    },

    input = {
        kb_layout = "us",
        repeat_delay = 250,
        repeat_rate = 35,
        numlock_by_default = true,
        follow_mouse = 0,
        sensitivity = 0,
        touchpad = {
            natural_scroll = false,
            tap_to_click = true,
            disable_while_typing = true,
            clickfinger_behavior = true,
        },
    },
})

-- Bezier curves (gentle, not flashy)
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })
-- 'easy' was a spring in the original Lua; the .conf approximated it as a bezier with a slight
-- overshoot for spring-feel, and that is what the desktop has felt like since — kept as is.
hl.curve("easy", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easy" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easy", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })

-- 3-finger swipe gestures (up/down = workspaces, left/right = focus)
local function dispatch(d)
    return function() hl.dispatch(d) end
end
hl.gesture({ fingers = 3, direction = "up", action = dispatch(hl.dsp.focus({ workspace = "r-1" })) })
hl.gesture({ fingers = 3, direction = "down", action = dispatch(hl.dsp.focus({ workspace = "r+1" })) })
hl.gesture({ fingers = 3, direction = "left", action = dispatch(hl.dsp.layout("focus l")) })
hl.gesture({ fingers = 3, direction = "right", action = dispatch(hl.dsp.layout("focus r")) })

-- -----------------------------------------------------------------------------
-- WINDOW RULES
-- -----------------------------------------------------------------------------
-- Suppress maximize events
hl.window_rule({ name = "suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })

-- Fix XWayland phantom drag windows
hl.window_rule({
    name = "no-focus-phantom",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-- Default opacity (every window starts at 1.0)
hl.window_rule({ name = "default-opacity", match = { class = ".*" }, opacity = "1" })

-- Floating utilities
hl.window_rule({
    name = "float-utils",
    match = { class = "^(blueberry\\.py|guifetch|pavucontrol|org\\.pulseaudio\\.pavucontrol|nm-connection-editor|blueman-manager|org\\.freedesktop\\.impl\\.portal\\.desktop\\.kde)$" },
    float = true,
})

-- File dialogs
hl.window_rule({
    name = "float-dialogs",
    match = { title = "^(Open File|Select a File|Choose wallpaper|Open Folder|Save As|Library|File Upload).*" },
    float = true,
})

-- Picture-in-picture
hl.window_rule({
    name = "pip-float-pin",
    match = { title = "^[Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture" },
    float = true,
    pin = true,
})

-- flameshot's capture overlay arrives with an EMPTY class and a "flameshot" title; tiled, it is
-- a shrunken desktop in a column (2026-09-07). It sizes itself to its --region (the focused
-- monitor, shot-region.sh), so: float, pin, no chrome, and no animation into place.
hl.window_rule({
    name = "flameshot-overlay",
    match = { class = "^(flameshot)?$", title = "^(flameshot)$" },
    float = true,
    pin = true,
    no_anim = true,
    border_size = 0,
    rounding = 0,
})

-- fzf-picker
hl.window_rule({ name = "fzf-picker", match = { class = "^(fzf-picker)$" }, float = true, size = { 800, 600 } })

-- Quake dropdown terminal: ghostty (class com.ghostty.quake) on the special:quake workspace,
-- toggled globally by F12. quake-toggle.sh sizes/positions it as a full-width top band on the
-- focused monitor (dual-monitor safe), so only float here.
hl.window_rule({ name = "quake-term", match = { class = "^(com\\.ghostty\\.quake)$" }, float = true, no_anim = true })

-- Bitwarden popups
hl.window_rule({
    name = "bitwarden-popup",
    match = { title = ".*([Bb]itwarden).*" },
    float = true,
    size = { 500, 700 },
    center = true,
})

-- Zoom (XWayland, v7.x; every window is class=zoom, told apart by title). A NORMAL app
-- (Andrew, 2026-09-07): the home window, the meeting, the chat, the settings — all TILE like
-- anything else. Only the genuine transients float: menus and dropdowns (at the cursor, no
-- focus), the share toolbar / annotation bar / share preview strip (no focus, no chrome, NOT
-- pinned — they stay on the meeting's workspace instead of following you around), the
-- mini video ("zoom_linux_float_video_window"), and the share picker (a centred dialog).
-- Reference: github.com/hyprwm/Hyprland/issues/4809.
hl.window_rule({
    name = "zoom-popups",
    match = { class = "^(zoom|Zoom)$", title = "^(menu window|Toolbar Menu|Meeting security|Meeting info|confirm window)$" },
    float = true,
    no_initial_focus = true,
    move = "onscreen cursor",
})
-- the share toolbar ("You are screen sharing · Stop share") and the annotation bar: pinned
-- after all — Zoom re-creates them constantly and an unpinned one sank under the tiled
-- meeting, where Stop share could not be clicked (2026-09-07); pinned they stay on top and
-- follow the share, which is what they are for
hl.window_rule({
    name = "zoom-toolbars",
    match = { class = "^(zoom|Zoom)$", title = "^(annotate_toolbar|as_toolbar)$" },
    float = true,
    pin = true,
    no_initial_focus = true,
    border_size = 0,
    rounding = 0,
    no_shadow = true,
    -- native Wayland Zoom (xwayland=false in zoomus.conf, 2026-09-07): its toolbar is a plain
    -- toplevel that asks for no position, so it goes top-centre under the bar
    move = "50%-50% 40",
})
-- the share preview strip (a 1px green frame): float, no focus, no chrome, not pinned
hl.window_rule({
    name = "zoom-share-preview",
    match = { class = "^(zoom|Zoom)$", title = "^as_preview$" },
    float = true,
    no_initial_focus = true,
    border_size = 0,
    rounding = 0,
    no_shadow = true,
})
-- the portal's "which monitor / window" picker (xdg-desktop-portal-hyprland's own app): a
-- centred floating dialog, not a tile
hl.window_rule({
    name = "share-picker",
    match = { class = "^(hyprland-share-picker)$" },
    float = true,
    center = true,
})
hl.window_rule({
    name = "zoom-mini-video",
    match = { class = "^(zoom|Zoom)$", title = "^zoom_linux_float_video_window$" },
    float = true,
    no_initial_focus = true,
})
hl.window_rule({
    name = "zoom-share-picker",
    match = { class = "^(zoom|Zoom)$", title = "^Select a window or an application.*" },
    float = true,
    center = true,
})

-- EmulationStation fullscreen
hl.window_rule({
    name = "es-fullscreen",
    match = { class = "^(emulationstation|EmulationStation|es-de|emulationstation-de)$" },
    fullscreen = true,
    opacity = "1.0",
})

-- Immediate (no vsync) for games / wine .exe windows
hl.window_rule({ name = "wine-no-vsync", match = { title = ".*\\.exe" }, immediate = true })

-- -----------------------------------------------------------------------------
-- KEYBINDINGS
-- -----------------------------------------------------------------------------
local M = "SUPER"
local function bind(keys, d, opts) hl.bind(keys, d, opts) end
local function exec(cmd) return hl.dsp.exec_cmd(cmd) end
local function layout(msg) return hl.dsp.layout(msg) end
local function ws(w) return hl.dsp.focus({ workspace = w }) end
local function to_ws(w) return hl.dsp.window.move({ workspace = w, follow = false }) end -- movetoworkspacesilent
local function follow_ws(w) return hl.dsp.window.move({ workspace = w, follow = true }) end -- movetoworkspace
local function move(dir) return hl.dsp.window.move({ direction = dir }) end
local function move_mon(dir) return hl.dsp.window.move({ monitor = dir }) end
local function resize(x, y) return hl.dsp.window.resize({ x = x, y = y, relative = true }) end
local shell = hyprdir .. "/scripts"

-- ----- App launchers -----
bind(M .. " + Return", exec("ghostty"))
bind(M .. " + SHIFT + Return", exec("ghostty --title=AgentDeck --class=com.ghostty.agent-deck -e agent-deck"))
bind(M .. " + E", exec("dolphin"))
bind(M .. " + W", exec("floorp"))
bind(M .. " + X", exec("kate"))
bind("CTRL + " .. M .. " + V", exec("pavucontrol"))
bind("CTRL + SHIFT + Escape", exec("ghostty -e btop"))
bind("F12", exec(shell .. "/quake-toggle.sh"))

bind(M .. " + Space", exec("astal-shell toggle launcher"))
-- The astal shell's info panel (caelestia is gone — cutover 2026-09-05).
bind(M .. " + I", exec("astal-shell toggle drawer"))
bind(M .. " + SHIFT + I", exec("astal-shell toggle drawer"))
bind(M .. " + N", exec("astal-shell toggle hub"))
bind(M .. " + C", exec(shell .. "/shell-req.sh toggle deck"))
-- Super alone, down and up: the rail's workspace cells show numbers while it is held (the
-- shell). non_consuming: every Super+key bind still fires
hl.bind("SUPER_L", function() hl.exec_cmd(shell .. "/shell-req.sh super down") end, { non_consuming = true })
hl.bind("SUPER_L", function() hl.exec_cmd(shell .. "/shell-req.sh super up") end, { non_consuming = true, release = true })   -- the bottom deck: log, media, agents, timer
bind(M .. " + U", exec("astal-shell show drawer agents"))
bind(M .. " + B", exec("astal-shell show drawer calendar"))
bind("ALT + Space", exec("astal-shell toggle launcher"))

-- Clipboard history: cliphist keeps the store, the shell is its face
bind(M .. " + V", exec("astal-shell toggle clipboard"))

-- Help / hotkey overlay
bind(M .. " + Slash", exec("astal-shell toggle launcher"))
bind(M .. " + SHIFT + Slash", exec("astal-shell toggle cheatsheet"))
bind(M .. " + SHIFT + C", exec("astal-shell crt"))
bind(M .. " + SHIFT + Z", exec("astal-shell backdrop"))
-- light/dark: zahir / uqbar, live — ~/.config/ficciones/theme repoints, the shell restyles itself
bind(M .. " + SHIFT + P", exec("astal-shell theme"))
bind(M .. " + SHIFT + T", exec("astal-shell glass"))
bind(M .. " + SHIFT + W", exec("astal-shell toggle weather"))
bind(M .. " + D", exec("astal-shell toggle dashboard"))

-- Edit configs
bind("CTRL + " .. M .. " + Slash", exec("xdg-open " .. hyprdir .. "/hyprland.lua"))

-- ----- Focus (vim H/L = column, J/K = workspace; arrows = column/window) -----
-- through the shell (scripts/shell-req.sh, ~15 ms): the sidecar is a floating window the
-- layout's focus skips, so the shell stitches it in at the start of the row
bind(M .. " + H", exec(shell .. "/shell-req.sh focus l"))
bind(M .. " + L", exec(shell .. "/shell-req.sh focus r"))
bind(M .. " + J", ws("r+1"))
bind(M .. " + K", ws("r-1"))

bind(M .. " + Left", exec(shell .. "/shell-req.sh focus l"))
bind(M .. " + Right", exec(shell .. "/shell-req.sh focus r"))
bind(M .. " + Up", layout("focus u"))
bind(M .. " + Down", layout("focus d"))

bind(M .. " + bracketleft", layout("move -col"))
bind(M .. " + bracketright", layout("move +col"))

-- Focus window within column
bind("CTRL + " .. M .. " + J", layout("focus d"))
bind("CTRL + " .. M .. " + K", layout("focus u"))

-- Focus the other monitor (CTRL = monitor scope; +SHIFT below moves instead)
bind("CTRL + " .. M .. " + H", hl.dsp.focus({ monitor = "l" }))
bind("CTRL + " .. M .. " + L", hl.dsp.focus({ monitor = "r" }))

-- ----- Move (Shift+H/L = column left/right; Shift+J/K = workspace) -----
bind(M .. " + SHIFT + H", move("l"))
bind(M .. " + SHIFT + L", move("r"))
bind(M .. " + SHIFT + J", to_ws("r+1"))
bind(M .. " + SHIFT + K", to_ws("r-1"))

bind(M .. " + SHIFT + Left", move("l"))
bind(M .. " + SHIFT + Right", move("r"))
bind(M .. " + SHIFT + Up", move("u"))
bind(M .. " + SHIFT + Down", move("d"))

-- Move column to monitor
bind("CTRL + " .. M .. " + SHIFT + H", move_mon("l"))
bind("CTRL + " .. M .. " + SHIFT + L", move_mon("r"))
bind("CTRL + " .. M .. " + SHIFT + J", follow_ws("r+1"))
bind("CTRL + " .. M .. " + SHIFT + K", follow_ws("r-1"))

-- Swap column with neighbor
bind("ALT + " .. M .. " + H", layout("swapcol l"))
bind("ALT + " .. M .. " + L", layout("swapcol r"))

-- ----- Workspaces by number -----
for i = 1, 10 do
    local key = tostring(i % 10)
    bind(M .. " + " .. key, ws(i))
    bind(M .. " + SHIFT + " .. key, to_ws(i))
    -- ...and with CTRL, follow the window over
    bind("CTRL + " .. M .. " + SHIFT + " .. key, follow_ws(i))
end

-- Workspace navigation (Page / wheel / overview)
bind(M .. " + Page_Up", ws("r-1"))
bind(M .. " + Page_Down", ws("r+1"))
bind(M .. " + SHIFT + Page_Up", to_ws("r-1"))
bind(M .. " + SHIFT + Page_Down", to_ws("r+1"))

bind(M .. " + mouse_down", ws("r+1"))
bind(M .. " + mouse_up", ws("r-1"))
bind(M .. " + SHIFT + mouse_down", to_ws("r+1"))
bind(M .. " + SHIFT + mouse_up", to_ws("r-1"))

-- Overview
bind(M .. " + Tab", ws("previous"))
bind("ALT + Tab", hl.dsp.focus({ last = true }))
-- the workspace overview with LIVE window thumbnails: hyprexpo (github.com/sandwichfarm/hyprexpo),
-- a compositor plugin. NixOS: modules/os puts the .so under /etc/hypr/plugins. Arch: once, by hand —
--   hyprpm update && hyprpm add https://github.com/sandwichfarm/hyprexpo && hyprpm enable hyprexpo
-- (hyprpm installs matching headers under /usr, so it asks for sudo). Until it is loaded the
-- dispatcher is unknown and the bind does nothing.
-- the plugin's own lua action, not a dispatcher: `hyprctl dispatch hyprexpo:expo` is legacy
-- syntax and a lua config no longer parses it (2026-09-07)
bind(M .. " + O", function() hl.plugin.hyprexpo.expo("toggle") end)

-- ----- Window state -----
bind(M .. " + Q", hl.dsp.window.close())
bind("ALT + F4", hl.dsp.window.close())
bind("CTRL + " .. M .. " + SHIFT + Q", hl.dsp.window.kill())
-- pin = the shell's sidecar: a floating pinned column on the left of every workspace on the
-- monitor, the tiled columns re-fit beside it (modules/desktop/shell/lib/sidecar.ts)
bind("CTRL + " .. M .. " + P", exec(shell .. "/shell-req.sh sidecar toggle"))

-- Toggle windowed-fullscreen (internal=0 windowed, client=3 fullscreen client-side)
bind("ALT + " .. M .. " + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 3 }))
bind("ALT + " .. M .. " + Space", hl.dsp.window.float())
bind(M .. " + SHIFT + V", hl.dsp.window.float())

-- ----- Column width / resize -----
-- through the shell: a focused sidecar resizes (colresize ignores floating windows), anything
-- else falls through to colresize
bind(M .. " + Semicolon", exec(shell .. "/shell-req.sh colresize narrower"))
bind(M .. " + Apostrophe", exec(shell .. "/shell-req.sh colresize wider"))
bind(M .. " + Minus", exec(shell .. "/shell-req.sh colresize narrower"))
bind(M .. " + Equal", exec(shell .. "/shell-req.sh colresize wider"))
bind(M .. " + F", layout("fit active"))
bind(M .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
bind("CTRL + " .. M .. " + C", layout("center"))

-- Window height
bind(M .. " + SHIFT + Semicolon", resize(0, -100))
bind(M .. " + SHIFT + Apostrophe", resize(0, 100))
bind(M .. " + SHIFT + Minus", resize(0, -100))
bind(M .. " + SHIFT + Equal", resize(0, 100))

-- ----- Scrolling: columns (stack / unstack / width / fit) -----
-- consume_or_expel: >1 window in the column expels the focused one toward prev/next; a lone
-- window gets absorbed into the adjacent column.
bind(M .. " + SHIFT + comma", layout("consume_or_expel prev"))
bind(M .. " + SHIFT + period", layout("consume_or_expel next"))
bind("CTRL + " .. M .. " + comma", layout("consume"))
bind("CTRL + " .. M .. " + period", layout("promote"))

-- cycles scrolling.explicit_column_widths
bind(M .. " + R", layout("colresize +conf"))
bind(M .. " + SHIFT + R", layout("colresize -conf"))

bind(M .. " + A", layout("fit expand"))
bind(M .. " + SHIFT + A", layout("fit all"))
bind(M .. " + T", layout("fit visible"))
bind(M .. " + G", layout("fit_into_view"))

-- ----- Mouse drag / resize -----
bind(M .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
bind(M .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ----- Screenshots -----
bind(M .. " + SHIFT + S", exec(shell .. "/shot-region.sh"))
bind("CTRL + " .. M .. " + S", exec(shell .. "/shot-region.sh repeat"))
bind(M .. " + SHIFT + CTRL + S", exec([[bash -c 'grim -o "$(hyprctl monitors -j | jq -r ".[] | select(.focused) | .name")" - | swappy -f -']]))
-- the shell's capture (the rail's camera item): file + clipboard + a notice, one path for all
bind("ALT + Print", exec(shell .. "/shell-req.sh capture shot window"))
bind("Print", exec(shell .. "/shell-req.sh capture shot monitor"))
bind("CTRL + Print", exec(shell .. "/shell-req.sh capture shot region"))
bind("SHIFT + Print", exec(shell .. "/shell-req.sh capture rec monitor"))
bind("CTRL + SHIFT + Print", exec(shell .. "/shell-req.sh capture stop"))

-- ----- Color picker / OCR -----
bind(M .. " + P", exec("hyprpicker -a"))
bind(M .. " + SHIFT + X", exec([[bash -c 'grim -g "$(slurp)" /tmp/ocr.png && tesseract /tmp/ocr.png - | wl-copy && rm /tmp/ocr.png']]))

-- ----- Audio (locked + repeating = the old bindle; locked = bindl) -----
bind("XF86AudioRaiseVolume", exec("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 2%+"), { locked = true, repeating = true })
bind("XF86AudioLowerVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"), { locked = true, repeating = true })
bind("XF86AudioMute", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
bind("XF86AudioMicMute", exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
bind(M .. " + SHIFT + M", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
bind("ALT + " .. M .. " + M", exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))

-- ----- Brightness -----
bind("XF86MonBrightnessUp", exec("brightnessctl set 5%+"), { locked = true, repeating = true })
bind("XF86MonBrightnessDown", exec("brightnessctl set 5%-"), { locked = true, repeating = true })

-- ----- Media -----
bind("XF86AudioPlay", exec("playerctl play-pause"), { locked = true })
bind("XF86AudioPause", exec("playerctl play-pause"), { locked = true })
bind("XF86AudioNext", exec("playerctl next"), { locked = true })
bind("XF86AudioPrev", exec("playerctl previous"), { locked = true })

-- ----- System -----
bind("CTRL + ALT + L", exec("hyprlock"))
bind("CTRL + " .. M .. " + R", exec("bash -c 'pkill -x gjs; sleep 0.3; astal-shell &'"))
bind("CTRL + ALT + Delete", hl.dsp.exit())
bind("CTRL + SHIFT + ALT + " .. M .. " + Delete", exec("systemctl poweroff"))
bind("CTRL + " .. M .. " + SHIFT + P", hl.dsp.dpms({ action = "off" }))
