// Popovers off the cells of the rail, bar and deck. A CLICK opens (Andrew, 2026-09-07: no
// hover-and-show to get there); once one is open in a GROUP, sliding to the next trigger swaps
// at once (menu-bar feel: click the cpu, move over to the ram); leaving both the trigger and
// the surface starts a grace timer that closes. `hover: true` keeps the old dwell-to-open —
// the rail's workspace strips only.
import Gtk from "gi://Gtk?version=4.0"
import { timeout, type Timer } from "ags/time"
import { setting } from "./settings"


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
 * A menubutton whose popover opens on click (or on hover, with `hover`). `onClick` runs on
 * the click as well — the window cells focus, the workspace numbers switch — and then the
 * popover opens too unless the cell is hover-driven (there a click means "do it and close") or
 * `onClick` returns false (the click did all it should).
 */
export function hoverPopover(mb: Gtk.MenuButton, group: string, onClick?: () => unknown, opts: { dwell?: number; hover?: boolean | (() => boolean); onShow?: () => void } = {}) {
  // `hover` may be a predicate: the workspace strips open on hover only while Super is held
  const hoverOn = () => (typeof opts.hover === "function" ? opts.hover() : !!opts.hover)
  const pop = mb.popover as Gtk.Popover
  pop.autohide = false // a grab would send the trigger a synthetic leave the moment it opened
  let dwell: Timer | null = null
  let grace: Timer | null = null
  // no tooltip over an open popover: every tooltip under the trigger is off while it is up.
  // Setting tooltip-text turns has-tooltip back on (the gauges re-set theirs every second),
  // so each is watched and pinned off until the close.
  let tipped: { w: Gtk.Widget; id: number }[] = []
  const tipsOff = () => {
    tipsOn()
    const pin = (w: Gtk.Widget) => {
      w.hasTooltip = false
      tipped.push({ w, id: w.connect("notify::has-tooltip", () => { if (w.hasTooltip) w.hasTooltip = false }) })
    }
    const walk = (w: Gtk.Widget | null) => { for (let c = w?.get_first_child() ?? null; c; c = c.get_next_sibling()) { if (c === pop) continue; if (c.hasTooltip) pin(c); walk(c) } }
    if (mb.hasTooltip) pin(mb)
    walk(mb)
  }
  const tipsOn = () => { for (const { w, id } of tipped) { w.disconnect(id); w.hasTooltip = true }; tipped = [] }
  const me: Entry = { close: () => { mb.popdown(); untrack(group, me); tipsOn() } }
  const show = () => { track(group, me); opts.onShow?.(); tipsOff(); mb.popup() }
  let inTrigger = () => false
  let inPop = () => false
  const armClose = () => {
    grace?.cancel()
    grace = timeout(setting("feel.hoverGraceMs").peek(), () => { if (!inTrigger() && !inPop()) me.close() })
  }
  inTrigger = watch(mb, () => {
    grace?.cancel(); dwell?.cancel()
    const cur = open.get(group)
    // one is open in this group: sliding to the next swaps at once — unless this one is
    // hover-driven with its own long dwell (the workspace strips)
    if (cur && cur !== me && !opts.hover) show()
    else if (opts.hover && hoverOn()) dwell = timeout(opts.dwell ?? setting("feel.hoverDwellMs").peek(), () => { if (inTrigger() && hoverOn()) show() })
  }, () => { dwell?.cancel(); armClose() })
  inPop = watch(pop, () => grace?.cancel(), armClose)
  // CAPTURE + claimed: the menubutton never sees the press, so this is the one click path
  const click = new Gtk.GestureClick({ propagationPhase: Gtk.PropagationPhase.CAPTURE })
  click.connect("pressed", () => {
    click.set_state(Gtk.EventSequenceState.CLAIMED)
    const more = onClick?.()
    if (opts.hover && onClick) me.close()
    else if (mb.popover?.visible || more === false) me.close()
    else show()
  })
  mb.add_controller(click)
  // a keybind opens without the pointer: it closes on the next toggle, or once the pointer
  // has visited and left
  return {
    toggle: () => (mb.popover?.visible ? me.close() : show()),
    close: me.close,
    open: () => !!mb.popover?.visible,
  }
}
export type HoverPop = ReturnType<typeof hoverPopover>

/** Cards by name, for `astal-shell pop card <name>` (a driven pass screenshots a card it cannot hover). */
export const cards = new Map<string, HoverPop>()
