// The old xscreensaver hacks in the backdrop's rotation: `xss-host` (modules/desktop/default.nix)
// draws one as a monitor's background layer — a rootful Xwayland made a layer surface — and this
// starts, stops and freezes it per monitor. The backdrop (surfaces/Backdrop.tsx) hides its own
// window while a hack has the monitor, and asks for a pause while a film covers it. The settings
// picker's preview is a hack on a headless Xvfb instead, its screen read back as frames.
import GLib from "gi://GLib"
import Gdk from "gi://Gdk?version=4.0"
import { execAsync, subprocess, type Process } from "ags/process"
import { setting } from "./settings"
import { xwdFrame } from "./xwd-core"

let hacks: string[] = []
const running = new Map<string, { p: Process; display: number; paused?: boolean }>() // monitor connector → its xss-host
let display = 40 // an X display per start, so a stopping server never holds the next one's socket

/** The hacks there are, once (empty when xss-host is missing). */
export async function loadHacks() {
  try { hacks = (await execAsync(["xss-host", "--list"])).split("\n").map((s) => s.trim()).filter(Boolean) } catch { hacks = [] }
  return hacks
}
/** Every hack there is (after loadHacks), switched off or not. */
export const hackNames = () => hacks

/** Start `hack` as `connector`'s background; the one already there stops first. `w`×`h` is the
 * monitor; the hack draws at backdrop.hackScale of it, stretched to fit. False when it won't start. */
export function startHack(connector: string, w: number, h: number, hack: string): boolean {
  stopHack(connector)
  display = display >= 99 ? 40 : display + 1
  const scale = Math.min(1, Math.max(0.25, setting("backdrop.hackScale").peek()))
  const size = (n: number) => String(Math.round(n * scale))
  try {
    // in backdrop.slice (default.nix): CPU is shared between cgroups before processes, so the
    // hack's nice only counts inside the shell's own; --scope execs, so the pid is xss-host's
    const argv = ["systemd-run", "--user", "--scope", "--quiet", "--slice=backdrop.slice", "--", "xss-host", connector, String(display), size(w), size(h), hack]
    running.set(connector, { p: subprocess(argv, () => {}, () => {}), display })
    return true
  } catch (e) { console.error("xss-host:", String(e)); return false }
}

export function stopHack(connector: string) {
  const r = running.get(connector)
  if (!r) return
  running.delete(connector)
  // a stopped process holds a TERM until it is continued
  if (r.paused) void signalChildren(connector, r.display, false).finally(() => r.p.signal(15))
  else r.p.signal(15)
}

// the host by its own arguments (connector and display are unique to it), then its children
const signalChildren = (connector: string, display: number, stop: boolean) =>
  execAsync(["sh", "-c", `pkill ${stop ? "-STOP" : "-CONT"} -P "$(pgrep -f "xss-host $1 $2 " | head -1)"`, "_", connector, String(display)]).catch(() => {})

/** Freeze or thaw the hack on `connector` (its host's children: the X server and the hack). */
export function pauseHack(connector: string, paused: boolean) {
  const r = running.get(connector)
  if (!r) return
  r.paused = paused
  void signalChildren(connector, r.display, paused)
}

export const stopAll = () => [...running.keys()].forEach(stopHack)

let preview: { p: Process; dir: string; timer: number } | null = null

/** Run `hack` on a headless X server of its own at `w`×`h` and hand `onFrame` its screen ~15 times
 * a second, until stopPreview; the one already running stops first. */
export function startPreview(hack: string, w: number, h: number, onFrame: (t: Gdk.Texture) => void) {
  stopPreview()
  display = display >= 99 ? 40 : display + 1
  const dir = GLib.dir_make_tmp("xss-preview-XXXXXX")
  const screen = `${dir}/Xvfb_screen0`
  try {
    const p = subprocess(["xss-host", "--preview", String(display), dir, String(w), String(h), hack], () => {}, () => {})
    const timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 66, () => {
      try {
        const [, b] = GLib.file_get_contents(screen)
        const f = xwdFrame(b)
        if (f) onFrame(Gdk.MemoryTexture.new(f.width, f.height, Gdk.MemoryFormat.B8G8R8X8, new GLib.Bytes(b.subarray(f.offset, f.offset + f.stride * f.height)), f.stride))
      } catch { /* not there yet: the X server is still starting */ }
      return GLib.SOURCE_CONTINUE
    })
    preview = { p, dir, timer }
  } catch (e) { console.error("xss-host --preview:", String(e)); GLib.rmdir(dir) }
}

export function stopPreview() {
  if (!preview) return
  const { p, dir, timer } = preview
  preview = null
  GLib.source_remove(timer)
  p.signal(15)
  // after the X server is gone, so it cannot write the file back
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 2000, () => { GLib.unlink(`${dir}/Xvfb_screen0`); GLib.rmdir(dir); return GLib.SOURCE_REMOVE })
}
