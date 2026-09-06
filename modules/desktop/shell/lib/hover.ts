// Hover-to-open, for every popover and panel the rail and bar hang off a cell (Andrew,
// 2026-09-05: "like the window ones"). A short dwell opens; leaving both the trigger and the
// surface starts a grace timer that closes. Within a GROUP only one surface is open at a time,
// and sliding from one trigger to the next swaps at once (menu-bar feel, no double fade).
import Gtk from "gi://Gtk?version=4.0"
import { timeout, type Timer } from "ags/time"

const DWELL_MS = 250
const GRACE_MS = 350

type Entry = { close: () => void }
const open = new Map<string, Entry>() // group → the open one

function track(group: string, me: Entry) {
  const cur = open.get(group)
  if (cur && cur !== me) cur.close()
  open.set(group, me)
}
function untrack(group: string, me: Entry) {
  if (open.get(group) === me) open.delete(group)
}

/** Motion tracking over a widget: `inside()` is the live answer. */
function watch(w: Gtk.Widget, onEnter: () => void, onLeave: () => void) {
  const m = new Gtk.EventControllerMotion()
  m.connect("enter", onEnter)
  m.connect("leave", onLeave)
  w.add_controller(m)
  return () => m.containsPointer
}

/**
 * A menubutton whose popover opens on hover. `onClick` replaces the click-to-toggle (the
 * window cells use it to focus); without it a click still toggles as before.
 */
export function hoverPopover(mb: Gtk.MenuButton, group: string, onClick?: () => void) {
  const pop = mb.popover as Gtk.Popover
  pop.autohide = false // a grab would send the trigger a synthetic leave the moment it opened
  let dwell: Timer | null = null
  let grace: Timer | null = null
  const me: Entry = { close: () => { mb.popdown(); untrack(group, me) } }
  const show = () => { track(group, me); mb.popup() }
  let inTrigger = () => false
  let inPop = () => false
  const armClose = () => {
    grace?.cancel()
    grace = timeout(GRACE_MS, () => { if (!inTrigger() && !inPop()) me.close() })
  }
  inTrigger = watch(mb, () => {
    grace?.cancel(); dwell?.cancel()
    const cur = open.get(group)
    if (cur && cur !== me) show() // sliding along the bar: swap now
    else dwell = timeout(DWELL_MS, () => { if (inTrigger()) show() })
  }, () => { dwell?.cancel(); armClose() })
  inPop = watch(pop, () => grace?.cancel(), armClose)
  if (onClick) {
    // CAPTURE + claimed: the menubutton never sees the press, so it does not toggle.
    const click = new Gtk.GestureClick({ propagationPhase: Gtk.PropagationPhase.CAPTURE })
    click.connect("pressed", () => { click.set_state(Gtk.EventSequenceState.CLAIMED); onClick(); me.close() })
    mb.add_controller(click)
  }
  return () => { dwell?.cancel(); grace?.cancel() }
}

/**
 * A plain trigger (a button on the rail) that opens a separate window (the info panel, the
 * weather surface). The window is watched too, so moving into it keeps it open.
 */
export function hoverPanel(
  trigger: Gtk.Widget,
  group: string,
  panel: { show: () => void; hide: () => void; isOpen: () => boolean; window: () => Gtk.Widget | null },
) {
  let dwell: Timer | null = null
  let grace: Timer | null = null
  const me: Entry = { close: () => { panel.hide(); untrack(group, me) } }
  const show = () => { track(group, me); panel.show() }
  let inTrigger = () => false
  let inPanel = () => false
  let watched = false
  const armClose = () => {
    grace?.cancel()
    grace = timeout(GRACE_MS, () => { if (panel.isOpen() && !inTrigger() && !inPanel()) me.close() })
  }
  const watchPanel = () => {
    if (watched) return
    const w = panel.window()
    if (!w) return
    watched = true
    inPanel = watch(w, () => grace?.cancel(), armClose)
  }
  inTrigger = watch(trigger, () => {
    grace?.cancel(); dwell?.cancel()
    const cur = open.get(group)
    if (cur && cur !== me) { show(); watchPanel() }
    else dwell = timeout(DWELL_MS, () => { if (inTrigger()) { show(); watchPanel() } })
  }, () => { dwell?.cancel(); armClose() })
}
