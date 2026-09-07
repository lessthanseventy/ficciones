import Hyprland from "gi://AstalHyprland"
import { createBinding, createState, type Accessor } from "ags"

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
 */
export const [screencasts, setScreencasts] = createState(0)
hypr.connect("event", (_, ev: string, args: string) => {
  if (ev !== "screencast") return
  const [state] = args.split(",")
  setScreencasts((n) => Math.max(0, n + (state === "1" ? 1 : -1)))
})
