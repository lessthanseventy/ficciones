// Hover-to-open, for every popover and panel the rail and bar hang off a cell (Andrew,
// 2026-09-05: "like the window ones"). A short dwell opens; leaving both the trigger and the
// surface starts a grace timer that closes. Within a GROUP only one surface is open at a time,
// and sliding from one trigger to the next swaps at once (menu-bar feel, no double fade).
import Gtk from "gi://Gtk?version=4.0"
import { timeout, type Timer } from "ags/time"

const DWELL_MS = 500 // a glance across a cell should not open it (Andrew, 2026-09-06: "a slight delay everywhere")
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
export function hoverPopover(mb: Gtk.MenuButton, group: string, onClick?: () => void, opts: { dwell?: number; onShow?: () => void } = {}) {
  const pop = mb.popover as Gtk.Popover
  const dwellMs = opts.dwell ?? DWELL_MS
  pop.autohide = false // a grab would send the trigger a synthetic leave the moment it opened
  let dwell: Timer | null = null
  let grace: Timer | null = null
  const me: Entry = { close: () => { mb.popdown(); untrack(group, me) } }
  const show = () => { track(group, me); opts.onShow?.(); mb.popup() }
  let inTrigger = () => false
  let inPop = () => false
  const armClose = () => {
    grace?.cancel()
    grace = timeout(GRACE_MS, () => { if (!inTrigger() && !inPop()) me.close() })
  }
  inTrigger = watch(mb, () => {
    grace?.cancel(); dwell?.cancel()
    const cur = open.get(group)
    // sliding along the bar swaps at once — unless this one asked for a long dwell (the
    // workspace strips: a glance at the numbers should not throw thumbnails up)
    if (cur && cur !== me && !opts.dwell) show()
    else dwell = timeout(dwellMs, () => { if (inTrigger()) show() })
  }, () => { dwell?.cancel(); armClose() })
  inPop = watch(pop, () => grace?.cancel(), armClose)
  if (onClick) {
    // CAPTURE + claimed: the menubutton never sees the press, so it does not toggle.
    const click = new Gtk.GestureClick({ propagationPhase: Gtk.PropagationPhase.CAPTURE })
    click.connect("pressed", () => { click.set_state(Gtk.EventSequenceState.CLAIMED); onClick(); me.close() })
    mb.add_controller(click)
  }
  // a keybind opens without the pointer: it closes on the next toggle, or once the pointer
  // has visited and left
  return {
    toggle: () => (mb.popover?.visible ? me.close() : show()),
    close: me.close,
    open: () => !!mb.popover?.visible,
  }
}
export type HoverPop = ReturnType<typeof hoverPopover>
