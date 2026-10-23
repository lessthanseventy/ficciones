# Keys

Generated from `modules/desktop/hypr/hyprland.lua` by `mise run manual:gen` — edit THAT, never this file.
128 binds. `SUPER` is the main modifier. The shell draws the live sheet too (`astal-shell toggle cheatsheet`, bound under launch).

## launch

| keys | does |
|---|---|
| `SUPER+Return` | `ghostty` |
| `SUPER+SHIFT+Return` | `ghostty --title=AgentDeck --class=com.ghostty.agent-deck -e ` |
| `SUPER+E` | `dolphin` |
| `SUPER+W` | `floorp` |
| `SUPER+X` | `kate` |
| `CTRL+SUPER+V` | `pavucontrol` |
| `CTRL+SHIFT+Escape` | `ghostty -e btop` |
| `F12` | `shell/shell-req.sh quake` |
| `SUPER+Space` | `astal-shell toggle launcher` |
| `SUPER+I` | `astal-shell toggle drawer` |
| `SUPER+SHIFT+I` | `astal-shell toggle drawer` |
| `SUPER+N` | `astal-shell toggle hub` |
| `SUPER+C` | `shell/shell-req.sh toggle deck` |
| `SUPER+U` | `astal-shell show drawer agents` |
| `SUPER+B` | `astal-shell show drawer calendar` |
| `ALT+Space` | `astal-shell toggle launcher` |
| `SUPER+V` | `astal-shell toggle clipboard` |
| `SUPER+Slash` | `astal-shell toggle launcher` |
| `SUPER+SHIFT+Slash` | `astal-shell toggle cheatsheet` |
| `SUPER+SHIFT+C` | `astal-shell crt` |
| `SUPER+SHIFT+Z` | `astal-shell backdrop` |
| `SUPER+SHIFT+P` | `astal-shell theme` |
| `SUPER+SHIFT+T` | `astal-shell glass` |
| `SUPER+SHIFT+W` | `astal-shell toggle weather` |
| `SUPER+D` | `astal-shell toggle dashboard` |
| `SUPER+comma` | `astal-shell toggle settings` |
| `CTRL+SUPER+Slash` | `xdg-open " .. hyprdir .. "/hyprland.lua` |
| `SUPER+H` | `shell/shell-req.sh focus l` |
| `SUPER+L` | `shell/shell-req.sh focus r` |
| `SUPER+Left` | `shell/shell-req.sh focus l` |
| `SUPER+Right` | `shell/shell-req.sh focus r` |
| `CTRL+SUPER+SHIFT+O` | `shell/shell-req.sh display send` |
| `CTRL+SUPER+P` | `shell/shell-req.sh sidecar toggle` |
| `SUPER+Semicolon` | `shell/shell-req.sh colresize narrower` |
| `SUPER+Apostrophe` | `shell/shell-req.sh colresize wider` |
| `SUPER+SUPERinus` | `shell/shell-req.sh colresize narrower` |
| `SUPER+Equal` | `shell/shell-req.sh colresize wider` |
| `SUPER+SHIFT+S` | `shell/shot-region.sh` |
| `CTRL+SUPER+S` | `shell/shot-region.sh repeat` |
| `SUPER+SHIFT+CTRL+S` | `shell/shell-req.sh capture shot monitor` |
| `ALT+Print` | `shell/shell-req.sh capture shot window` |
| `Print` | `shell/shell-req.sh capture shot monitor` |
| `CTRL+Print` | `shell/shell-req.sh capture shot region` |
| `SHIFT+Print` | `shell/shell-req.sh capture rec monitor` |
| `CTRL+SHIFT+Print` | `shell/shell-req.sh capture stop` |
| `SUPER+P` | `hyprpicker -a` |
| `SUPER+SHIFT+X` | `[[bash -c 'grim -g "$(slurp)" /tmp/ocr.png && tesseract /tmp` |
| `XF86AudioRaiseVolume` | `exec("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 2%+"), { ` |
| `XF86AudioLowerVolume` | `exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"), { locked ` |
| `XF86AudioSUPERute` | `exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked` |
| `XF86AudioSUPERicSUPERute` | `exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { lock` |
| `SUPER+SHIFT+SUPER` | `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle` |
| `CTRL+SUPER+SUPER` | `mpv-stream` |
| `ALT+SUPER+SUPER` | `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle` |
| `XF86SUPERonBrightnessUp` | `exec("brightnessctl set 5%+"), { locked = true, repeating = ` |
| `XF86SUPERonBrightnessDown` | `exec("brightnessctl set 5%-"), { locked = true, repeating = ` |
| `XF86AudioPlay` | `exec("playerctl play-pause"), { locked = true }` |
| `XF86AudioPause` | `exec("playerctl play-pause"), { locked = true }` |
| `XF86AudioNext` | `exec("playerctl next"), { locked = true }` |
| `XF86AudioPrev` | `exec("playerctl previous"), { locked = true }` |
| `CTRL+ALT+L` | `hyprlock` |
| `CTRL+SUPER+R` | `sh -c 'pkill -x gjs; systemctl --user reset-failed astal-she` |
| `CTRL+SHIFT+ALT+SUPER+Delete` | `systemctl poweroff` |

## focus

| keys | does |
|---|---|
| `CTRL+SUPER+H` | `hl.dsp.focus({ monitor = "l" })` |
| `CTRL+SUPER+L` | `hl.dsp.focus({ monitor = "r" })` |
| `ALT+Tab` | `hl.dsp.focus({ last = true })` |

## move & size

| keys | does |
|---|---|
| `SUPER+SHIFT+H` | `move("l")` |
| `SUPER+SHIFT+L` | `move("r")` |
| `SUPER+SHIFT+Left` | `move("l")` |
| `SUPER+SHIFT+Right` | `move("r")` |
| `SUPER+SHIFT+Up` | `move("u")` |
| `SUPER+SHIFT+Down` | `move("d")` |
| `CTRL+SUPER+SHIFT+H` | `move_mon("l")` |
| `CTRL+SUPER+SHIFT+L` | `move_mon("r")` |
| `SUPER+SHIFT+Semicolon` | `resize(0, -100)` |
| `SUPER+SHIFT+Apostrophe` | `resize(0, 100)` |
| `SUPER+SHIFT+SUPERinus` | `resize(0, -100)` |
| `SUPER+SHIFT+Equal` | `resize(0, 100)` |
| `SUPER+R` | `layout("colresize +conf")` |
| `SUPER+SHIFT+R` | `layout("colresize -conf")` |

## layout

| keys | does |
|---|---|
| `SUPER+Up` | `layout("focus u")` |
| `SUPER+Down` | `layout("focus d")` |
| `SUPER+bracketleft` | `layout("move -col")` |
| `SUPER+bracketright` | `layout("move +col")` |
| `CTRL+SUPER+J` | `layout("focus d")` |
| `CTRL+SUPER+K` | `layout("focus u")` |
| `ALT+SUPER+H` | `layout("swapcol l")` |
| `ALT+SUPER+L` | `layout("swapcol r")` |
| `SUPER+F` | `layout("fit active")` |
| `CTRL+SUPER+C` | `layout("center")` |
| `SUPER+SHIFT+comma` | `layout("consume_or_expel prev")` |
| `SUPER+SHIFT+period` | `layout("consume_or_expel next")` |
| `CTRL+SUPER+comma` | `layout("consume")` |
| `CTRL+SUPER+period` | `layout("promote")` |
| `SUPER+A` | `layout("fit expand")` |
| `SUPER+SHIFT+A` | `layout("fit all")` |
| `SUPER+T` | `layout("fit visible")` |
| `SUPER+G` | `layout("fit_into_view")` |

## workspaces

| keys | does |
|---|---|
| `SUPER+J` | `ws("r+1")` |
| `SUPER+K` | `ws("r-1")` |
| `SUPER+SHIFT+J` | `to_ws("r+1")` |
| `SUPER+SHIFT+K` | `to_ws("r-1")` |
| `CTRL+SUPER+SHIFT+J` | `follow_ws("r+1")` |
| `CTRL+SUPER+SHIFT+K` | `follow_ws("r-1")` |
| `SUPER+key` | `ws(i)` |
| `SUPER+SHIFT+key` | `to_ws(i)` |
| `CTRL+SUPER+SHIFT+key` | `follow_ws(i)` |
| `SUPER+Page_Up` | `ws("r-1")` |
| `SUPER+Page_Down` | `ws("r+1")` |
| `SUPER+SHIFT+Page_Up` | `to_ws("r-1")` |
| `SUPER+SHIFT+Page_Down` | `to_ws("r+1")` |
| `SUPER+mouse_down` | `ws("r+1")` |
| `SUPER+mouse_up` | `ws("r-1")` |
| `SUPER+SHIFT+mouse_down` | `to_ws("r+1")` |
| `SUPER+SHIFT+mouse_up` | `to_ws("r-1")` |
| `SUPER+Tab` | `ws("previous")` |

## window

| keys | does |
|---|---|
| `SUPER+Q` | `hl.dsp.window.close()` |
| `ALT+F4` | `hl.dsp.window.close()` |
| `CTRL+SUPER+SHIFT+Q` | `hl.dsp.window.kill()` |
| `ALT+SUPER+F` | `hl.dsp.window.fullscreen_state({ internal = 0, client = 3 })` |
| `ALT+SUPER+Space` | `hl.dsp.window.float()` |
| `SUPER+SHIFT+V` | `hl.dsp.window.float()` |
| `SUPER+SHIFT+F` | `hl.dsp.window.fullscreen({ mode = "fullscreen" })` |

## mouse

| keys | does |
|---|---|
| `SUPER+mouse:272` | `hl.dsp.window.drag()` |
| `SUPER+mouse:273` | `hl.dsp.window.resize()` |

## other

| keys | does |
|---|---|
| `SUPER+O` | `function() hl.plugin.hyprexpo.expo("toggle") end` |
| `CTRL+ALT+Delete` | `hl.dsp.exit()` |
| `CTRL+SUPER+SHIFT+P` | `hl.dsp.dpms({ action = "off" })` |

