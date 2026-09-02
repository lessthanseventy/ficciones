# Astal shell — a TUI-native desktop, and the end of caelestia

The desktop is the last part of this machine still wearing someone else's taste. `caelestia` is a
competent Quickshell rice; it is also pastel, rounded, blurred, and Material — the exact opposite of
the surface Aleph presents. This document designs the replacement: a shell built on **Astal**, styled
from `Console.Style`, so the cockpit and the desktop stop being two different computers.

The complaint that started it was "I want my computer to be a GUI, obviously, but to *feel* like a
TUI." That is not a theming request. It is a request for a different design language, which means a
framework you author rather than a shell you configure.

---

## 1 · Why Astal, and why not the others

Quickshell was never the problem — it is a rendering engine, and caelestia's taste is what grates.
But every prebuilt shell ships an opinion baked in: DankMaterialShell is *literally* Material Design,
Noctalia has its own strong look. Adopting one trades a rice you dislike for a rice you haven't
learned to dislike yet.

The split that matters is **data layer** (battery, network, bluetooth, mpris, tray, notifications,
audio) versus **presentation**. Astal ships the first as libraries and leaves the second entirely to
GTK4 + CSS. That is the whole requirement: every widget's data, none of anyone's design system.

Three supporting facts:

- The full `libastal` suite is already installed on this box — battery, bluetooth, cava, greetd,
  hyprland, io, mpris, network, notifd, powerprofiles, tray, wireplumber, wl. Zero acquisition cost.
- It is TypeScript, already a primary language here.
- `Aylur/astal` is the most actively developed of the candidates.

`eww` was the serious alternative and was rejected on ergonomics, not health — it is alive
(12.6k stars, pushed 2026-07-17, in nixpkgs). It is *configured* in `yuck`; Astal is *programmed*.
A person who wrote a whole Elixir TUI rather than configuring one wants the second.

**Nix**: `astal` enters as a flake input. nixpkgs carries only `ags` 2.3.0 — the v2 scaffolding CLI —
while upstream is v3, and `Aylur/astal` ships its own flake.

---

## 2 · The palette contract

`Console.Style` already declares itself "the one palette… so the whole cockpit reads as one surface
and a re-theme is one edit here." The shell adopts that contract rather than inventing a second one.
`_tokens.scss` mirrors it name-for-name; **no component may write a raw hex value**, exactly as no
Aleph panel may.

```
--bg      #000000     --green   #33FF00  body      --amber  #FFB000  chrome
--sel     #5B00AE     --accent  #E0218A  pink      --dim    #9A803F
--red     #FF5555     --cyan    #33C7FF            --sep    #B5651D
--chip    #FFD000  on --ink     #0A0A0A
```

Both semantic tiers come across intact: **status** (`working blocked await open done idle`) and
**identity** (`surveyor builder reviewer planner assistant`). Hyprland's `col.active_border` is
already `#FFB000`, so the desktop is partly wearing this palette before we start.

**Accent source is toggleable.** `_tokens.scss` is the phosphor floor and always loads. A second
sheet, generated from the wallpaper, redefines `--accent` and `--sel` only, and loads only when
`theme.accent = "wallpaper"`. GTK4 re-applies CSS at runtime, so the toggle needs no restart and
`rotate-wallpaper` regenerates the sheet whether or not anything reads it. Default is phosphor: a
terminal does not recolour itself because the wallpaper changed.

---

## 3 · Architecture

AGS v3 (gnim — JSX-flavoured TypeScript) on Astal, GTK4 through gtk4-layer-shell, SCSS.

One process publishes every layer-shell surface, so the Tlön client and the Hyprland IPC socket are
opened once rather than per widget.

```
modules/desktop/
  default.nix          # exists — the hypr symlinks
  shell/
    default.nix        # ags package + systemd --user service
    app.ts             # entry; instantiates surfaces per monitor
    style/
      _tokens.scss     # Console.Style, semantic names only
      _tui.scss        # panel / inset-label / meter primitives
      main.scss
    lib/
      tui.tsx          # <Panel title> <Meter> <Chip> <Dot> <CharGrid>
      hypr.ts  tlon.ts # IPC clients
    surfaces/          # Rail Drawer Notifications Launcher
                       # Clipboard Osd Cheatsheet Backdrop
    panes/             # Dash Perf Media Weather Agents
```

`<Panel title>` is the load-bearing primitive: a 1px border with its label inset into the top edge —
the `fieldset`/`legend` pattern in CSS, and the single visual move that makes a GTK surface read as a
TUI. `<CharGrid>` is a `Gtk.DrawingArea` rendering a monospace matrix; braille (`⠀-⣿`) packs a 2×4
dot matrix per cell for 8× effective resolution, which is how btop and gping draw smooth curves.

Source is symlinked out-of-store like the hypr config, so an edit reloads without a `home:switch`.

---

## 4 · Surfaces

**Rail** — 80px, widened from caelestia's 64px so status can be *read* as text (`BAT 87%`) rather
than iconified. Top to bottom: workspaces (occupied green, focused amber chip, empty dim — the
existing `st_open`/`selected`/`dim` semantics); the **scrolling-tape minimap**, showing which column
you occupy out of N; the active window title rotated vertical; a rule-30 automaton strip whose row
cadence follows CPU load; stacked clock; status as text; power.

The minimap is the one affordance a scrolling WM actually needs and no bar provides.

**Drawer** — a top sheet over ~40% of the screen, floating (no reserved space, nothing reflows).
Tabs `DASH · PERF · MEDIA · WEATHER · AGENTS` rendered in the existing `tab` style, white on violet,
inverse-video like Aleph's status line. **Navigation is lazygit's**: `1-5` jump to a pane, `Tab`
cycles, the focused pane takes the amber border while the rest sit on `separator`. A keybind rail
runs along the bottom. This is what separates a GTK panel that looks like a TUI from one that
behaves like one.

`DASH` aggregates one headline line from each of the other four, answering "what is happening"
without tabbing anywhere. `AGENTS` reads the Tlön roster and open/stalled/done counts — the pane no
other shell in the world could render, and it degrades to "channel down" when the server is not up.

**Notifications** — toasts as bordered panels with the app name inset; urgency maps to
`st_blocked` / `st_open` / `dim`. The centre is history grouped by app.

**Launcher** (retires anyrun) — a centred box with a `>` prompt and a block cursor, results below,
selection in inverse video. Prefixes switch mode: `>` apps, `=` calc, `/` files, `:` shell.
**Clipboard** is the same list widget on a different source; `cliphist` stays the storage daemon and
only loses its face.

**OSD** — bordered meters, fading after ~1.5s. **Cheatsheet** (`Super+/`) parses `hyprctl binds -j`
live, so it cannot drift from the config.

---

## 5 · Control surfaces

The drawer is for reading. Controls are for acting — they must be fast and dismissible — so they live
in a **control popover** anchored to the rail's status block (`Super+B`, or click; Escape dismisses),
not as another drawer tab.

- **Tray** (`astal-tray`, StatusNotifierItem). Not optional: `wgtray` is in `exec-once` today, and
  Steam/Discord-class apps assume a tray exists. Icons sit in the rail, overflow into the popover.
- **Clock → calendar.** Clicking the rail clock opens a month grid — monospace, today as an inverse
  chip, no chrome.
- **Network** — SSID list, signal as a text meter, connect/disconnect. VPN state is read from
  wgtray's tray item rather than reimplementing WireGuard.
- **Bluetooth** — paired devices, connect/disconnect, device battery where reported.
- **Audio** — sink/source switcher and per-app volume. Retires pavucontrol from `Ctrl+Super+V`.
- **Power profile** — performance/balanced/saver via `powerprofiles`.
- **Brightness**, **DND**, and an **idle inhibitor** toggle (hypridle keeps running; the toggle only
  inhibits).
- **Power menu** — the rail's `⏻` opens lock/logout/suspend/reboot/shutdown. Lock delegates to
  hyprlock; this shell never draws one.

Media transport (play/pause/prev/next, seek) lives in the Media pane and mirrors into the popover.

**Weather has no Astal library.** It needs an external source: open-meteo — no API key, free, JSON,
lat/lon in config. Cached to disk so a dead network shows stale data rather than an empty pane.

---

## 6 · Ambient, backdrop, CRT

Ambient animations are **driven by real signal, not a timer** — decoration goes stale in a week, a
display you learn to read at a glance does not. Rule 30 down the rail paced by CPU load; boids in
Dash whose flock size is open agent threads and whose cohesion tightens when work stalls; Game of
Life seeded from memory pressure; a Lorenz attractor in braille that earns its place purely by
looking incredible; a bongo cat in Media drumming to cava.

Wayland will not hand a shell global keystrokes without a keylogger, so the cat follows audio. This
is the better input anyway.

**Backdrop** has two modes, switched by keybind and IPC:

- `photo` — hyprpaper and `rotate-wallpaper` over the 1089 images in `Wallpapers/` and
  `aesthetic-wallpapers/`, unchanged. This is why `hyprpaper.conf` is deliberately *not* nix-managed:
  rotation rewrites it at runtime, and a store symlink would fight that on every switch.
- `zen` — a bottom-layer `CharGrid` cycling the ambient set with a slow crossfade.

**CRT is a separate, orthogonal toggle**: a fragment shader at `decoration:screen_shader` doing
scanlines, mild barrel distortion, phosphor bloom, vignette, and slight chromatic fringing. It
applies to the entire composited output — terminals, Aleph, the browser, the shell — which is a
categorically larger effect than styling widgets. Shipped as three files (`subtle`, `full`, `off`),
switched by path.

`render:direct_scanout = 1` **stays on permanently and the toggles stay uncoupled.** Fullscreen apps
bypass compositing and therefore escape the shader — which is correct: a game should get the GPU, not
a filter. The shader also costs GPU on this hybrid Intel/NVIDIA laptop, so CRT defaults off on
battery.

---

## 7 · Shipping

Six phases. Every one ends somewhere usable, and every one runs **alongside caelestia** — separate
layer namespaces, no conflict — so the desktop is never half-broken.

1. Scaffold, style system, rail. Riskiest visual work first, immediately useful.
2. Drawer and the five panes.
3. Notifications → disable caelestia's.
4. Launcher and clipboard → unbind anyrun.
5. OSDs, cheatsheet, ambient backdrop, CRT.
6. Cutover: one line out of `exec-once`.

`hyprlock` and `hypridle` are never touched. A lock screen is the one component where a bug costs
you the session, and hyprlock's PAM handling is not worth reimplementing for aesthetics.

**Dev loop as mise tasks**, since the loop is the shared API: `shell:dev` (run from source, hot CSS
reload), `shell:check` (tsc + eslint), `shell:restart`, `shell:logs`.

---

## 8 · Deferred, on purpose

- **A lock screen.** See above. hyprlock is not a stopgap, it is the decision.
- **Replacing hyprpaper.** `photo` mode works; rewriting a wallpaper daemon buys nothing.
- **The second monitor's rail behaving differently.** Both get the same rail until a reason appears.
- **Umbriel.** The Noctalia compositor is the only thing that does scrolling *and* per-workspace
  dwindle, which is the one layout feature Hyprland lacks. It is also young and breaks config between
  releases on purpose. Revisit after the Nix migration settles, not during two large changes at once.
- **Draggable/rearrangeable panes.** lazygit's panes do not move; neither do these.
