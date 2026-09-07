import Hyprland from "gi://AstalHyprland"
import { createBinding, createState, type Accessor } from "ags"
import { execAsync } from "ags/process"
import { timeout, interval, type Timer } from "ags/time"

export const hypr = Hyprland.get_default()

export const focusedWorkspace = createBinding(hypr, "focusedWorkspace")
export const focusedClient = createBinding(hypr, "focusedClient")

/** Workspaces 1..N sorted by id; special (negative) ones are hidden from the rail. */
export const workspaces: Accessor<Hyprland.Workspace[]> = createBinding(hypr, "workspaces")(
  (ws) => ws.filter((w) => w.id > 0).sort((a, b) => a.id - b.id),
)

/** The `address:0x…` selector for a dispatcher — AstalHyprland's client.address has no 0x. */
export const addr = (c: { address: string }) => `address:0x${c.address.replace(/^0x/, "")}`

/**
 * Monitors showing a fullscreen window right now, by connector name. A film on a monitor
 * turns its toasts and hot edge off (Andrew, 2026-09-06); maximised does not count. Refreshed
 * on the raw `fullscreen` event, which is how Hyprland announces both ways of the toggle.
 */
const fullscreenOf = () => {
  const out = new Set<string>()
  for (const m of hypr.get_monitors()) {
    const ws = m.activeWorkspace?.id
    if (hypr.get_clients().some((c) => c.monitor?.name === m.name && c.workspace?.id === ws && c.fullscreen === Hyprland.Fullscreen.FULLSCREEN)) out.add(m.name)
  }
  return out
}
export const [fullscreenMonitors, setFullscreenMonitors] = createState<Set<string>>(fullscreenOf())
const refresh = () => setFullscreenMonitors(fullscreenOf())
hypr.connect("event", (_, ev: string) => { if (ev === "fullscreen" || ev === "workspace" || ev === "focusedmon" || ev === "closewindow") refresh() })
export const isFullscreen = (monitor: string | undefined) => !!monitor && fullscreenMonitors.peek().has(monitor)

/**
 * Screen sharing / recording: Hyprland's `screencast` event — `STATE,OWNER` (1 starting /
 * 0 stopping; owner 0 = a monitor, 1 = a window). Counted, since two shares can overlap.
 * `since` is the first start; `who` is the portal consumer when there is one (a browser, OBS:
 * a PipeWire video stream carries its application.name), else what is being captured — a
 * direct screencopy client (wf-recorder) is anonymous to the compositor.
 */
export type Capture = { count: number; since: number; who: string }
export const [capture, setCapture] = createState<Capture>({ count: 0, since: 0, who: "" })
async function whoCaptures(owner: string): Promise<string> {
  try {
    const out = await execAsync(["pw-dump"])
    const names = new Set<string>()
    for (const n of JSON.parse(out) as any[]) {
      const p = n?.info?.props
      if (!p || n.type !== "PipeWire:Interface:Node") continue
      if (String(p["media.class"] ?? "").startsWith("Stream/Input/Video") && p["application.name"]) names.add(String(p["application.name"]))
    }
    if (names.size) return [...names].join(", ")
  } catch { /* no pipewire tools */ }
  return owner === "1" ? "a window" : "a monitor"
}
hypr.connect("event", (_, ev: string, args: string) => {
  if (ev !== "screencast") return
  const [state, owner] = args.split(",")
  const cur = capture.peek()
  if (state === "1") {
    const next = { count: cur.count + 1, since: cur.count ? cur.since : Date.now(), who: cur.who }
    setCapture(next)
    // the consumer's stream is up a moment after the event
    timeout(600, () => whoCaptures(owner).then((w) => setCapture((c) => (c.count ? { ...c, who: w } : c))))
  } else {
    const count = Math.max(0, cur.count - 1)
    setCapture(count ? { ...cur, count } : { count: 0, since: 0, who: "" })
  }
})

/**
 * Super is held: the rail's workspace cells show their numbers (hyprland.lua pings down/up).
 * A missed release (the shell restarting under it) would stick, so while held the key is
 * re-checked every half second through the compositor's own hl.is_key_down.
 */
export const [superHeld, setSuperHeldRaw] = createState(false)
let superCheck: Timer | null = null
export function setSuperHeld(on: boolean) {
  setSuperHeldRaw(on)
  superCheck?.cancel(); superCheck = null
  if (on) superCheck = interval(500, () => {
    execAsync(["hyprctl", "repl", 'return tostring(hl.is_key_down("Super_L"))']).then((out) => {
      if (!out.includes("true")) { setSuperHeldRaw(false); superCheck?.cancel(); superCheck = null }
    }).catch(() => {})
  })
}

/** The window last focused on each workspace, for the rail's cells; falls back to any window. */
const lastOn = new Map<number, string>()
hypr.connect("notify::focused-client", () => {
  const c = hypr.focusedClient
  if (c?.workspace) lastOn.set(c.workspace.id, c.address)
})
export const clients = createBinding(hypr, "clients")
export function lastClientOn(ws: Hyprland.Workspace): Hyprland.Client | null {
  const cs = hypr.get_clients().filter((c) => c.workspace?.id === ws.id && c.mapped)
  const a = lastOn.get(ws.id)
  return cs.find((c) => c.address === a) ?? cs[0] ?? null
}
