// Screenshots and recordings, off the rail's capture item. Shots go to ~/Pictures/Screenshots
// and the clipboard; a notice says where. Recordings (wf-recorder) go to ~/Videos/Recordings;
// the bar's REC cell shows one running, and the card offers stop. slurp for a region.
import GLib from "gi://GLib?version=2.0"
import { createState } from "ags"
import { execAsync, subprocess, type Process } from "ags/process"
import { logEvent } from "./log"
import { hypr } from "./hypr"

const stamp = () => GLib.DateTime.new_now_local().format("%Y-%m-%d_%H.%M.%S")
const shotsDir = () => `${GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES) ?? `${GLib.get_home_dir()}/Pictures`}/Screenshots`
const recsDir = () => `${GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_VIDEOS) ?? `${GLib.get_home_dir()}/Videos`}/Recordings`

const notify = (summary: string, body: string, icon = "camera-photo-symbolic") =>
  execAsync(["notify-send", "-a", "capture", "-i", icon, summary, body]).catch(() => {})

/** `x,y wxh` for a region (slurp), the focused monitor, or the active window; null if cancelled */
async function geometry(what: "region" | "monitor" | "window"): Promise<string | null> {
  if (what === "region") {
    try { return (await execAsync(["slurp"])).trim() || null } catch { return null }
  }
  if (what === "window") {
    const c = hypr.focusedClient
    return c ? `${c.x},${c.y} ${c.width}x${c.height}` : null
  }
  const m = hypr.focusedMonitor
  return m ? `${m.x},${m.y} ${m.width}x${m.height}` : null
}

export async function screenshot(what: "region" | "monitor" | "window", edit = false) {
  const g = await geometry(what)
  if (!g) return
  GLib.mkdir_with_parents(shotsDir(), 0o755)
  const file = `${shotsDir()}/${stamp()}_${what}.png`
  try {
    if (edit) {
      // flameshot over the geometry (its --region is WxH+X+Y; ours is `x,y wxh`); it copies/saves itself
      const [xy, wh] = g.split(" ")
      await execAsync(["flameshot", "gui", "--region", `${wh}+${xy.replace(",", "+")}`])
      logEvent("shell", `screenshot (${what}) → flameshot`)
      return
    }
    await execAsync(["grim", "-g", g, file])
    await execAsync(["sh", "-c", `wl-copy < '${file}'`])
    logEvent("shell", `screenshot (${what}) → ${file.replace(GLib.get_home_dir(), "~")}`)
    notify("screenshot", `${what} · copied · ${file.replace(GLib.get_home_dir(), "~")}`)
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
