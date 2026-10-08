// The old xscreensaver hacks in the backdrop's rotation: `xss-host` (modules/desktop/default.nix)
// draws one as a monitor's background layer — a rootful Xwayland made a layer surface — and this
// starts, stops and freezes it per monitor. The backdrop (surfaces/Backdrop.tsx) hides its own
// window while a hack has the monitor, and asks for a pause while a film covers it.
import { execAsync, subprocess, type Process } from "ags/process"
import { setting } from "./settings"

let hacks: string[] = []
const running = new Map<string, { p: Process; display: number }>() // monitor connector → its xss-host
let display = 40 // an X display per start, so a stopping server never holds the next one's socket

/** The hacks there are, once (empty when xss-host is missing). */
export async function loadHacks() {
  try { hacks = (await execAsync(["xss-host", "--list"])).split("\n").map((s) => s.trim()).filter(Boolean) } catch { hacks = [] }
  return hacks
}
export const haveHacks = () => hacks.length > 0

/** Start a random hack (one not switched off) as `connector`'s background; the one already there
 * stops first. Its name, or null when there is none to start. */
export function startHack(connector: string, w: number, h: number): string | null {
  stopHack(connector)
  const off = setting("backdrop.hacksOff").peek()
  const pool = hacks.filter((x) => !off.includes(x))
  if (!pool.length) return null
  const hack = pool[Math.floor(Math.random() * pool.length)]
  display = display >= 99 ? 40 : display + 1
  try {
    running.set(connector, { p: subprocess(["xss-host", connector, String(display), String(w), String(h), hack], () => {}, () => {}), display })
    return hack
  } catch (e) { console.error("xss-host:", String(e)); return null }
}

export function stopHack(connector: string) {
  const r = running.get(connector)
  running.delete(connector)
  r?.p.signal(15)
}

/** Freeze or thaw the hack on `connector` (its host's children: the X server and the hack). */
export function pauseHack(connector: string, paused: boolean) {
  const r = running.get(connector)
  // the host by its own arguments (connector and display are unique to it), then its children
  if (r) void execAsync(["sh", "-c", `pkill ${paused ? "-STOP" : "-CONT"} -P "$(pgrep -f "xss-host $1 $2 " | head -1)"`, "_", connector, String(r.display)]).catch(() => {})
}

export const stopAll = () => [...running.keys()].forEach(stopHack)
