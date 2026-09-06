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

export default function Clickaway({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  let win: Astal.Window
  onCleanup(() => win.destroy())
  return (
    <window
      $={(self) => {
        win = self
        const g = new Gtk.GestureClick()
        g.connect("pressed", () => { const c = closer; disarmClickaway(); c?.() })
        self.add_controller(g)
      }}
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
      <box />
    </window>
  )
}
