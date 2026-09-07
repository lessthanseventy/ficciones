// The live theme: uqbar (dark) or zahir (light). home-manager renders every surface for both
// under ~/.config/ficciones/themes/<name>/ and each app's fixed path is a link through
// ~/.config/ficciones/theme — the one mutable link. `astal-shell theme [uqbar|zahir|toggle]`
// (Super+Shift+P, the toggles card) repoints it, swaps the shell's own stylesheet and Pango
// palette in place, reloads Hyprland, and asks GTK for the matching light/dark scheme. Under a
// second, no nix. Apps that only read their config at start (GTK apps already open, Qt, Floorp)
// follow on their next launch.
import GLib from "gi://GLib?version=2.0"
import Gio from "gi://Gio?version=2.0"
import app from "ags/gtk4/app"
import { createState } from "ags"
import { execAsync } from "ags/process"
import { PALETTE } from "./palette"

export const THEMES = ["uqbar", "zahir"] as const
export type Theme = (typeof THEMES)[number]
const DIR = `${GLib.get_user_config_dir()}/ficciones`
const LINK = `${DIR}/theme`

export function currentTheme(): Theme {
  try {
    const t = GLib.path_get_basename(Gio.File.new_for_path(LINK).query_info("standard::symlink-target", Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null).get_symlink_target() ?? "")
    return (THEMES as readonly string[]).includes(t) ? (t as Theme) : "uqbar"
  } catch { return "uqbar" }
}

export const [theme, setThemeState] = createState<Theme>(currentTheme())
export const [switching, setSwitching] = createState(false)

/** The shell's own surfaces take the theme now: the stylesheet, then the markup palette. */
export function applyShellTheme() {
  try {
    const [ok, css] = GLib.file_get_contents(`${LINK}/shell.css`)
    if (ok) app.apply_css(new TextDecoder().decode(css), true)
  } catch (e) { console.error("theme css:", String(e)) }
  // GTK read ~/.config/gtk-4.0/gtk.css once, at start: its named colours (card_bg_color,
  // popover_bg_color — every field the shell's own css leaves to GTK) stayed on the login
  // theme after a switch (2026-09-07: light shell, black cards and popovers). The theme's
  // copy goes on as a second provider; the reset above drops both on the next switch.
  try {
    const [ok, css] = GLib.file_get_contents(`${LINK}/gtk.css`)
    if (ok) app.apply_css(new TextDecoder().decode(css), false)
  } catch (e) { console.error("theme gtk.css:", String(e)) }
  try {
    const [ok, json] = GLib.file_get_contents(`${LINK}/shell-palette.json`)
    if (ok) Object.assign(PALETTE as Record<string, string>, JSON.parse(new TextDecoder().decode(json)))
  } catch (e) { console.error("theme palette:", String(e)) }
}

export function setTheme(t: Theme | "toggle") {
  const next: Theme = t === "toggle" ? (currentTheme() === "uqbar" ? "zahir" : "uqbar") : t
  if (!Gio.File.new_for_path(`${DIR}/themes/${next}`).query_exists(null)) {
    execAsync(["notify-send", "-u", "critical", "-a", "astal-shell", `theme ${next}`, `${DIR}/themes/${next} is not there — home:switch first`]).catch(console.error)
    return
  }
  setSwitching(true)
  try {
    // repoint atomically: a fresh link, then rename over the old one
    const tmp = `${LINK}.next`
    try { Gio.File.new_for_path(tmp).delete(null) } catch { /* none */ }
    Gio.File.new_for_path(tmp).make_symbolic_link(`themes/${next}`, null)
    Gio.File.new_for_path(tmp).move(Gio.File.new_for_path(LINK), Gio.FileCopyFlags.OVERWRITE | Gio.FileCopyFlags.NOFOLLOW_SYMLINKS, null, null)
  } catch (e) {
    console.error("theme link:", String(e))
    setSwitching(false)
    return
  }
  setThemeState(next)
  applyShellTheme()
  const scheme = next === "zahir" ? "prefer-light" : "prefer-dark"
  Promise.allSettled([
    execAsync(["hyprctl", "reload"]),
    execAsync(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", scheme]),
    // Claude Code: its theme per palette is ~/.claude/themes/<name>.json (home-manager writes
    // them from the palette); `theme` in ~/.claude/settings.json picks one, re-read live
    Promise.resolve().then(() => {
      const f = `${GLib.get_home_dir()}/.claude/settings.json`
      const [ok, bytes] = GLib.file_get_contents(f)
      if (!ok) return
      const j = JSON.parse(new TextDecoder().decode(bytes))
      j.theme = `custom:${next}`
      GLib.file_set_contents(f, JSON.stringify(j, null, 2) + "\n")
    }),
    // ghostty re-reads its config on SIGUSR2 but leaves open surfaces alone (1.3), so they are
    // recoloured through OSC 10/11/4 on their ptys; every other app follows on its next launch
    execAsync(["pkill", "-USR2", "-x", "ghostty"]).then(() => execAsync([`${GLib.get_home_dir()}/.local/bin/ficciones-recolor`])),
  ]).finally(() => setSwitching(false))
}
