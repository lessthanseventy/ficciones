// Click-away for the panels. A panel's own window covers its output, with a `clickaway-field`
// under the pane: a press there closes it (clickawayField). The rail and bar lie outside those
// windows, so a press on them closes the open panel through closeOnPress.
import Gtk from "gi://Gtk?version=4.0"

let closer: (() => void) | null = null

/** Arm the clickaway; `close` runs on the first outside click. */
export function armClickaway(close: () => void) { closer = close }
export function disarmClickaway() { closer = null }
/** Close whatever panel is open, if one is. */
export function closeAny() { const c = closer; closer = null; c?.() }

/** Make `widget` a click-away field: a primary press on it runs `close`. */
export function clickawayField(widget: Gtk.Widget, close: () => void) {
  const g = new Gtk.GestureClick({ button: 1 })
  g.connect("pressed", () => close())
  widget.add_controller(g)
}

/**
 * The rail and bar sit above the clickaway on the same layer, so they get this instead: a
 * capture-phase gesture that closes an open panel and claims the press, so the clock cannot
 * close and reopen in one click.
 */
export function closeOnPress(widget: Gtk.Widget) {
  const g = new Gtk.GestureClick({ button: 1, propagationPhase: Gtk.PropagationPhase.CAPTURE })
  g.connect("pressed", (_, _n, x, y) => {
    if (!closer) return
    // cells with the keep-open class toggle on their own; closing here too would close-then-reopen
    for (let t = widget.pick(x, y, Gtk.PickFlags.DEFAULT); t; t = t.get_parent()) if (t.cssClasses.includes("keep-open")) return
    const c = closer
    disarmClickaway()
    c()
    g.set_state(Gtk.EventSequenceState.CLAIMED)
  })
  widget.add_controller(g)
}
