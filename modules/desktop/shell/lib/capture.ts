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

// Every shot is flameshot's (Andrew, 2026-09-07: "I like flameshot"): it saves into the
// screenshots dir and copies. `monitor` is its `screen -n` on the focused monitor's index (Qt
// orders screens as Hyprland lists them), no UI. `region` is its gui — which asks for the
// monitor first on a two-monitor Wayland session (flameshot's own doing: "capture the monitor
// where the cursor is … is not supported on Wayland"); `window` is the gui with the window
// preselected. `edit` is what the gui already is.
export type Sink = "file" | "clip" | "both"
/** A window's geometry as flameshot's --region wants it (WxH+X+Y); the focused one by default. */
const windowRegion = (address?: string) => {
  const c = address ? hypr.get_client(address.replace(/^0x/, "")) ?? hypr.get_client(address) : hypr.focusedClient
  return c ? `${c.width}x${c.height}+${c.x}+${c.y}` : null
}
export async function screenshot(what: "region" | "monitor" | "window", sink: Sink = "both", address?: string) {
  GLib.mkdir_with_parents(shotsDir(), 0o755)
  // where it lands: -p saves into the dir, -c copies; the gui applies them on accept
  const out = [...(sink !== "clip" ? ["-p", shotsDir()] : []), ...(sink !== "file" ? ["-c"] : [])]
  const where = sink === "both" ? "file + clipboard" : sink === "file" ? shotsDir().replace(GLib.get_home_dir(), "~") : "clipboard"
  try {
    if (what === "monitor") {
      const m = hypr.focusedMonitor
      if (!m) return
      await execAsync(["flameshot", "screen", "-n", String(m.id), ...out])
      logEvent("shell", `screenshot (monitor ${m.name}) → ${where}`)
      return
    }
    const args = ["flameshot", "gui", ...out]
    if (what === "window") {
      const r = windowRegion(address)
      if (!r) return
      args.push("--region", r)
    }
    await execAsync(args)
    logEvent("shell", `screenshot (${what}) → ${where}`)
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
