// The quake dropdown terminal (F12): a ghostty (class com.ghostty.quake) parked on special:quake
// while hidden. Shown, it moves to the focused monitor's active workspace, PINNED — Hyprland draws
// pinned windows above the rest, the sidecar among them — as a band at the top of the work area:
// from the rail (and a sidecar, the monitor's reserved left) to the notifications column, which it
// leaves clear. The compositor never animates it (window rule no_anim: a workspace move nudged it);
// the slide is ours, each step one dispatch over the request socket, never a hyprctl process.
// It closes like any panel: a click on another window (focus moves), the rail, the bar or the
// bare desktop (the clickaway).
import { armClickaway, disarmClickaway } from "../surfaces/Clickaway"
import { hypr } from "./hypr"
import { L, dispatchNow } from "./hyprlua"
import { query } from "./hyprsock"
import { sidecarVerb } from "./sidecar"
import { glass, GLASS } from "./glass"

const CLASS = "com.ghostty.quake"
const HEIGHT = 0.55 // of the monitor
const GAP = 12 // general:gaps_out
const NOTES_W = 428 // the notifications column: 420 wide + 8 margin (surfaces/Notifications.tsx)
const STEPS = 14, STEP_MS = 12

type Client = { address: string; at: [number, number]; size: [number, number]; pinned: boolean; workspace: { name: string } }
type Monitor = { x: number; y: number; width: number; height: number; reserved: number[]; focused: boolean; activeWorkspace: { id: number } }

const json = <T,>(what: string): T => JSON.parse(query(`j/${what}`)) as T
const term = () => json<(Client & { class: string })[]>("clients").find((c) => c.class === CLASS) ?? null
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const easeOut = (t: number) => 1 - (1 - t) * (1 - t)

let busy = false
let prev: string | null = null // the window that had focus, for when it hides

/** F12: show it if hidden, hide it if shown; a press mid-slide is dropped. */
export async function toggleQuake() {
  if (busy) return
  busy = true
  try {
    let c = term()
    if (!c) {
      dispatchNow(`hl.dsp.exec_cmd(${JSON.stringify(`[workspace special:quake silent] ghostty --class=${CLASS}`)})`)
      for (let i = 0; i < 30 && !(c = term()); i++) await sleep(100)
      if (!c) return
    }
    if (c.workspace.name === "special:quake") await show(c)
    else await hide(c)
  } finally { busy = false }
}

async function show(c: Client) {
  const w = `address:${c.address}`
  const m = json<Monitor[]>("monitors").find((x) => x.focused)
  if (!m) return
  const [rl, rt, rr] = m.reserved
  const width = m.width - rl - rr - NOTES_W - 2 * GAP, height = Math.round(m.height * HEIGHT)
  const x = m.x + rl + GAP, y1 = m.y + rt + GAP, y0 = y1 - height - 60
  const active = json<{ address?: string }>("activewindow").address
  prev = active && active !== c.address ? active : null
  sidecarVerb("ring", "off")
  // invisible across the workspace move: Hyprland clamps a floating window onto the monitor when
  // it changes workspace, so the one parked above the screen would show for a frame
  dispatchNow(
    L.setProp(w, "opacity_override", "1"), L.setProp(w, "opacity", "0"),
    L.float(w, "on"), L.resizeExact(w, width, height), L.moveExact(w, x, y0),
    L.moveToWorkspace(w, String(m.activeWorkspace.id), true), L.moveExact(w, x, y0),
    ...(c.pinned ? [] : [L.pin(w)]), L.focusWindow(w), `hl.dsp.window.alter_zorder({ mode = "top", window = ${JSON.stringify(w)} })`,
    L.setProp(w, "opacity", glass.peek() ? GLASS : "1"), // a terminal: glass whenever glass is on (lib/glass.ts)
  )
  await slide(w, x, y0, y1)
  dispatchNow(L.focusWindow(w)) // asked while it hung above the screen, focus did not stick
  armClickaway(() => void toggleQuake())
}

async function hide(c: Client) {
  const w = `address:${c.address}`
  disarmClickaway()
  await slide(w, c.at[0], c.at[1], c.at[1] - c.size[1] - 60)
  dispatchNow(
    ...(c.pinned ? [L.pin(w)] : []),
    L.moveToWorkspace(w, "special:quake", false),
    L.setProp(w, "opacity", "1"), L.setProp(w, "opacity_override", "unset"),
  )
  // focus back where it was, if that window is still about off the special workspaces: focusing
  // the quake itself would open special:quake again
  if (prev && json<Client[]>("clients").some((x) => x.address === prev && !x.workspace.name.startsWith("special"))) dispatchNow(L.focusWindow(`address:${prev}`))
  prev = null
  sidecarVerb("ring", "on")
}

async function slide(w: string, x: number, from: number, to: number) {
  for (let i = 1; i <= STEPS; i++) {
    dispatchNow(L.moveExact(w, x, Math.round(from + (to - from) * easeOut(i / STEPS))))
    await sleep(STEP_MS)
  }
}

// a click on another window takes the focus: that is a click away
hypr.connect("notify::focused-client", () => {
  if (busy) return
  const f = hypr.focusedClient
  if (!f || f.class === CLASS) return
  const c = term()
  if (c && c.workspace.name !== "special:quake") void toggleQuake()
})
