// The weather surface: the full forecast card beside the rail, from the rail's weather item
// or Super+Shift+W. A popover cannot be opened from a keybind (GTK refuses a grabbing popup
// without a top-most parent), so it is a small panel with a click-away field, like the others.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import { Panel } from "../lib/tui"
import { WeatherCard } from "../panes/Weather"

let win: Astal.Window | null = null

export function hideWeather() { if (win) { win.visible = false; win.keymode = Astal.Keymode.NONE } }
export function toggleWeather() {
  if (!win) return
  if (win.visible) return hideWeather()
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = app.get_monitors().find((m) => m.connector === name)
  if (mon) win.gdkmonitor = mon
  win.keymode = Astal.Keymode.ON_DEMAND
  win.visible = true
}

export default function WeatherPop() {
  return (
    <window
      $={(self) => {
        win = self
        const k = new Gtk.EventControllerKey()
        k.connect("key-pressed", (_, kv) => (kv === Gdk.KEY_Escape || kv === Gdk.KEY_q ? (hideWeather(), true) : false))
        self.add_controller(k)
      }}
      visible={false}
      cssClasses={["drawer", "weatherpop"]}
      namespace="astal-shell-weather"
      name="weather"
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.NONE}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.RIGHT}
      marginTop={36}
      marginLeft={54}
      application={app}
    >
      <box>
        <box cssClasses={["sheet"]} orientation={Gtk.Orientation.VERTICAL} widthRequest={460} hexpand={false} halign={Gtk.Align.START} valign={Gtk.Align.START}>
          <Panel title={"\u{f0590}  WEATHER"} cssClasses={["card", "card-weather"]}><WeatherCard /></Panel>
        </box>
        <box
          cssClasses={["clickaway-field"]}
          hexpand
          vexpand
          $={(self) => {
            const g = new Gtk.GestureClick({ button: 0 })
            g.connect("pressed", () => hideWeather())
            self.add_controller(g)
          }}
        />
      </box>
    </window>
  )
}
