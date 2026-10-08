// The photo under the zen grid: a random image per monitor from the wallpaper directory,
// rotated every wallpaper.rotateMinutes (a setting). Drawn by the shell's own background layer (Backdrop.tsx), so no
// hyprpaper — the one wallpaper path that works nix-built on Arch and on NixOS alike.
// Directory: "wallpapers" in ~/.config/astal-shell/config.json (home-manager writes it),
// default ~/Pictures/Wallpapers.
import GLib from "gi://GLib"
import Gio from "gi://Gio"
import { createState } from "ags"
import { timeout, type Timer } from "ags/time"
import { setting } from "./settings"

const EXT = /\.(jpe?g|png|webp|avif)$/i

function dir(): string {
  try {
    const [ok, bytes] = GLib.file_get_contents(`${GLib.get_user_config_dir()}/astal-shell/config.json`)
    const cfg = ok ? JSON.parse(new TextDecoder().decode(bytes)) : {}
    if (typeof cfg.wallpapers === "string") return cfg.wallpapers.replace(/^~/, GLib.get_home_dir())
  } catch {}
  return `${GLib.get_home_dir()}/Pictures/Wallpapers`
}

let pool: string[] | null = null
function files(): string[] {
  if (pool) return pool
  pool = []
  try {
    const d = Gio.File.new_for_path(dir())
    const en = d.enumerate_children("standard::name,standard::type", Gio.FileQueryInfoFlags.NONE, null)
    let info: Gio.FileInfo | null
    while ((info = en.next_file(null))) {
      if (info.get_file_type() === Gio.FileType.REGULAR && EXT.test(info.get_name())) pool.push(`${dir()}/${info.get_name()}`)
    }
  } catch {}
  return pool
}

const inUse = new Set<string>()
function pick(current: string | null): string | null {
  const all = files()
  if (!all.length) return null
  // avoid what the other monitors show, and what this one shows now
  const fresh = all.filter((f) => f !== current && !inUse.has(f))
  const from = fresh.length ? fresh : all
  return from[Math.floor(Math.random() * from.length)]
}

/** A per-monitor wallpaper accessor that rotates on its own. */
export function wallpaper() {
  const [file, setFile] = createState<string | null>(null)
  const next = () => {
    const cur = file.peek()
    const n = pick(cur)
    if (cur) inUse.delete(cur)
    if (n) inUse.add(n)
    setFile(n)
  }
  next()
  // re-armed from the setting each time, so a new interval applies from now
  let t: Timer | null = null
  const arm = () => { t?.cancel(); t = timeout(Math.max(1, setting("wallpaper.rotateMinutes").peek()) * 60_000, () => { next(); arm() }) }
  arm()
  setting("wallpaper.rotateMinutes").subscribe(arm)
  return { file, next }
}
