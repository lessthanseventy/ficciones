import Gdk from "gi://Gdk?version=4.0"
import { createState, type Accessor } from "ags"

/**
 * The monitors a surface can be built on. GTK lists a plugged-in monitor a moment before the
 * compositor has named it, and every per-monitor surface reads the connector once to find its
 * workspaces and windows — so a monitor is held back until it has its name.
 */
export function namedMonitors(plugged: Accessor<Gdk.Monitor[]>): Accessor<Gdk.Monitor[]> {
  const awaited = new WeakSet<Gdk.Monitor>()
  const named = () => plugged.peek().filter((m) => {
    if (!m.connector && !awaited.has(m)) { awaited.add(m); m.connect("notify::connector", () => setMonitors(named())) }
    return !!m.connector
  })
  const [monitors, setMonitors] = createState(named())
  plugged.subscribe(() => setMonitors(named()))
  return monitors
}
