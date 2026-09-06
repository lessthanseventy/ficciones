// The clickaway: while a panel is up, a transparent surface covers each monitor under it,
// on the TOP layer, so a click anywhere else closes the panel instead of reaching a window.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import { createState, onCleanup } from "ags"

const [active, setActive] = createState(false)
let closer: (() => void) | null = null

/** Arm the clickaway; `close` runs on the first outside click. */
export function armClickaway(close: () => void) { closer = close; setActive(true) }
export function disarmClickaway() { closer = null; setActive(false) }

/**
 * The rail and bar sit above the clickaway on the same layer, so they get this instead: a
 * capture-phase gesture that closes an open panel and claims the press, so the clock cannot
 * close and reopen in one click.
 */
export function closeOnPress(widget: Gtk.Widget) {
  const g = new Gtk.GestureClick({ button: 0, propagationPhase: Gtk.PropagationPhase.CAPTURE })
  g.connect("pressed", () => {
    if (!closer) return
    const c = closer
    disarmClickaway()
    c()
    g.set_state(Gtk.EventSequenceState.CLAIMED)
  })
  widget.add_controller(g)
}

export default function Clickaway({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  let win: Astal.Window
  onCleanup(() => win.destroy())
  return (
    <window
      $={(self) => (win = self)}
      visible={active}
      cssClasses={["clickaway"]}
      namespace="astal-shell-clickaway"
      name={`clickaway-${gdkmonitor.connector}`}
      gdkmonitor={gdkmonitor}
      layer={Astal.Layer.TOP}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM}
      application={app}
    >
      <box
        hexpand
        vexpand
        $={(self) => {
          // the box IS the surface: a full-size target, or there is nothing under the pointer
          const g = new Gtk.GestureClick({ button: 0 })
          g.connect("pressed", () => { const c = closer; disarmClickaway(); c?.() })
          self.add_controller(g)
        }}
      />
    </window>
  )
}
