// Screenshots and recordings, off the rail's capture item. Shots go to ~/Pictures/Screenshots
// and the clipboard; a notice says where. Recordings (wf-recorder) go to ~/Videos/Recordings;
// the bar's REC cell shows one running, and the card offers stop. slurp for a region.
import GLib from "gi://GLib?version=2.0"
import { createState } from "ags"
import { execAsync, subprocess, type Process } from "ags/process"
import { logEvent } from "./log"
import { hypr } from "./hypr"
import { L, dispatch } from "./hyprlua"

const stamp = () => GLib.DateTime.new_now_local().format("%Y-%m-%d_%H.%M.%S")
const shotsDir = () => `${GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES) ?? `${GLib.get_home_dir()}/Pictures`}/Screenshots`
const recsDir = () => `${GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_VIDEOS) ?? `${GLib.get_home_dir()}/Videos`}/Recordings`

const notify = (summary: string, body: string, icon = "camera-photo-symbolic") =>
  execAsync(["notify-send", "-a", "capture", "-i", icon, summary, body]).catch(() => {})

/** The last slurp pick (`x,y wxh`), for a repeat shot of the same region; null until one lands. */
export const [lastRegion, setLastRegion] = createState<string | null>(null)

/** `x,y wxh` for a region (slurp), the last one, the focused monitor, or the active window; null if cancelled */
async function geometry(what: Target): Promise<string | null> {
  if (what === "region") {
    try {
      const g = (await execAsync(["slurp"])).trim() || null
      if (g) setLastRegion(g)
      return g
    } catch { return null }
  }
  if (what === "last") return lastRegion.peek()
  if (what === "window") {
    const c = hypr.focusedClient
    return c ? `${c.x},${c.y} ${c.width}x${c.height}` : null
  }
  const m = hypr.focusedMonitor
  return m ? `${m.x},${m.y} ${m.width}x${m.height}` : null
}

// The card's shots are grim's (Andrew, 2026-09-08): flameshot's gui is Super+Shift+S (the UI he
// likes, hypr/scripts/shot-region.sh), but every card button went through it and its Wayland
// two-monitor picker got in the way of each click. slurp picks a region; a window is its
// geometry; a monitor is its whole box. The clipboard is wl-copy's — it forks and holds the
// selection, where a capture tool that exits on copy loses it (Qt6 flameshot did).
export type Sink = "file" | "clip" | "both"
export type Target = "region" | "last" | "monitor" | "window"
const clientOf = (address?: string) =>
  address ? hypr.get_client(address.replace(/^0x/, "")) ?? hypr.get_client(address) : hypr.focusedClient
export async function screenshot(what: Target, sink: Sink = "both", address?: string) {
  GLib.mkdir_with_parents(shotsDir(), 0o755)
  const where = sink === "both" ? "file + clipboard" : sink === "file" ? shotsDir().replace(GLib.get_home_dir(), "~") : "clipboard"
  try {
    let g: string | null
    if (what === "window") {
      // a window on another workspace: go there first (grim's -g is in screen coordinates)
      const c = clientOf(address)
      const ws = c?.workspace
      if (c && ws && ws.id !== hypr.focusedMonitor?.activeWorkspace?.id && ws.id > 0) {
        await dispatch(L.workspace(String(ws.id)))
        await new Promise((r) => setTimeout(r, 400))
      }
      g = c ? `${c.x},${c.y} ${c.width}x${c.height}` : null
    } else {
      g = await geometry(what)
    }
    if (!g) return
    // one grim to a file (a temp one when only the clipboard wants it), wl-copy from that
    const file = sink === "clip" ? `${GLib.get_tmp_dir()}/shot-${stamp()}.png` : `${shotsDir()}/${stamp()}.png`
    await execAsync(["grim", "-g", g, file])
    if (sink !== "file") await execAsync(["sh", "-c", `wl-copy --type image/png < "$1"${sink === "clip" ? ' && rm -f "$1"' : ""}`, "_", file])
    logEvent("shell", `screenshot (${what}) → ${where}`)
    notify("screenshot", where)
  } catch (e) { notify("screenshot failed", String(e), "dialog-error-symbolic") }
}

let rec: Process | null = null
let recFile = ""
export const [recording, setRecording] = createState<string | null>(null)

export async function startRecording(what: "region" | "monitor") {
  if (rec) return
  const g = await geometry(what)
  if (!g) return
  GLib.mkdir_with_parents(recsDir(), 0o755)
  recFile = `${recsDir()}/${stamp()}_${what}.mp4`
  try {
    rec = subprocess(["wf-recorder", "-g", g, "-f", recFile], () => {}, () => {})
    rec.connect("exit", () => {
      rec = null
      setRecording(null)
      logEvent("shell", `recording saved → ${recFile.replace(GLib.get_home_dir(), "~")}`)
      notify("recording saved", recFile.replace(GLib.get_home_dir(), "~"), "camera-video-symbolic")
    })
    setRecording(what)
    logEvent("shell", `recording ${what}…`, "warn")
  } catch (e) { rec = null; notify("recording failed", String(e), "dialog-error-symbolic") }
}
/** SIGINT: wf-recorder finalises the file on it; `exit` above does the rest. */
export function stopRecording() { rec?.signal(2) }
