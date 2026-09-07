// Click-away for the panels. A covering layer surface turned out to swallow clicks at the
// compositor without GTK ever seeing them, so there is none: a click on a window takes the
// keyboard focus and the panel closes on focus loss (see Drawer/Hub); a press on the rail or
// bar — which never take focus — closes it through closeOnPress.
import Gtk from "gi://Gtk?version=4.0"

let closer: (() => void) | null = null

/** Arm the clickaway; `close` runs on the first outside click. */
export function armClickaway(close: () => void) { closer = close }
export function disarmClickaway() { closer = null }
/** Close whatever panel is open, if one is. */
export function closeAny() { const c = closer; closer = null; c?.() }

/**
 * The rail and bar sit above the clickaway on the same layer, so they get this instead: a
 * capture-phase gesture that closes an open panel and claims the press, so the clock cannot
 * close and reopen in one click.
 */
export function closeOnPress(widget: Gtk.Widget) {
  const g = new Gtk.GestureClick({ button: 0, propagationPhase: Gtk.PropagationPhase.CAPTURE })
  g.connect("pressed", (_, n, x, y) => {
    if (!closer) return
    // the clock toggles on its own; closing here too would close-then-reopen
    for (let t = widget.pick(x, y, Gtk.PickFlags.DEFAULT); t; t = t.get_parent()) if (t.cssClasses.includes("clock") || t.cssClasses.includes("wx") || t.cssClasses.includes("deck-log")) return
    const c = closer
    disarmClickaway()
    c()
    g.set_state(Gtk.EventSequenceState.CLAIMED)
  })
  widget.add_controller(g)
}
