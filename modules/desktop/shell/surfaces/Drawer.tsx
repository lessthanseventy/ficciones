// The info panel: a single column of cards beside the rail. Each card is a pane with an icon
// in its title; the focused card is framed amber. 1-4 focus, Tab/Shift-Tab cycle, j/k move
// the cursor inside a card, Escape or q closes. Opens on the monitor the pointer is on.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import Mpris from "gi://AstalMpris"
import { Panel } from "../lib/tui"
import { PANES, type Pane, focus, setFocus, move } from "../lib/nav"
import { CalendarCard } from "../panes/Calendar"
import { MediaCard } from "../panes/Media"
import { WeatherCard } from "../panes/Weather"
import { AgentsCard } from "../panes/Agents"
import { agents } from "../lib/agents"

const cards: Record<Pane, { icon: string; body: () => JSX.Element; rows: () => number }> = {
  CALENDAR: { icon: "\u{f00ed}", body: CalendarCard, rows: () => 0 },
  MEDIA:    { icon: "\u{f075a}", body: MediaCard, rows: () => Mpris.get_default().get_players().length },
  WEATHER:  { icon: "\u{f0590}", body: WeatherCard, rows: () => 0 },
  AGENTS:   { icon: "\u{f06a9}", body: AgentsCard, rows: () => agents.get().roster.length },
}

/** Open the panel (on a card, from anywhere) on the monitor the pointer is on. */
export function showDrawer(pane?: Pane) {
  const w = app.get_window("drawer") as Astal.Window | undefined
  if (!w) return
  if (pane) setFocus(pane)
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = app.get_monitors().find((m) => m.connector === name)
  if (mon) w.gdkmonitor = mon
  w.visible = true
}
export function toggleDrawer() {
  const w = app.get_window("drawer")
  if (w?.visible) w.visible = false
  else showDrawer()
}

export default function Drawer() {
  let win: Astal.Window
  const cycle = (d: number) => setFocus(PANES[(PANES.indexOf(focus.get()) + d + PANES.length) % PANES.length])
  const onKey = (_: Gtk.EventControllerKey, keyval: number) => {
    const n = keyval - Gdk.KEY_1
    if (n >= 0 && n < PANES.length) return setFocus(PANES[n]), true
    switch (keyval) {
      case Gdk.KEY_Tab: return cycle(1), true
      case Gdk.KEY_ISO_Left_Tab: return cycle(-1), true
      case Gdk.KEY_j: case Gdk.KEY_Down: return move(1, cards[focus.get()].rows()), true
      case Gdk.KEY_k: case Gdk.KEY_Up: return move(-1, cards[focus.get()].rows()), true
      case Gdk.KEY_Escape: case Gdk.KEY_q: return (win.visible = false), true
    }
    return false
  }

  return (
    <window
      $={(self) => {
        win = self
        const k = new Gtk.EventControllerKey()
        k.connect("key-pressed", onKey)
        self.add_controller(k)
      }}
      visible={false}
      cssClasses={["drawer"]}
      namespace="astal-shell-drawer"
      name="drawer"
      layer={Astal.Layer.TOP}
      keymode={Astal.Keymode.ON_DEMAND}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.BOTTOM}
      marginTop={36} // under the bar; both sit on the TOP layer
      marginLeft={54} // beside the rail with a gap, never over it
      application={app}
    >
      <box cssClasses={["sheet"]} orientation={Gtk.Orientation.VERTICAL} widthRequest={420}>
        {PANES.map((p, i) => (
          <Panel
            title={`${cards[p].icon}  ${i + 1} ${p}`}
            cssClasses={focus((f) => ["card", `card-${p.toLowerCase()}`, ...(f === p ? ["focused"] : [])])}
          >
            <box
              $={(self) => {
                // focus the card on any click inside it, without stealing the click from the
                // buttons within — a capture-phase gesture that never claims
                const g = new Gtk.GestureClick({ propagationPhase: Gtk.PropagationPhase.CAPTURE })
                g.connect("pressed", () => setFocus(p))
                self.add_controller(g)
              }}
            >
              {cards[p].body()}
            </box>
          </Panel>
        ))}
        <box vexpand />
        <box cssClasses={["keys"]} spacing={12}>
          <label label="1-4 card" /><label label="Tab next" /><label label="j/k row" /><label label="Esc close" />
        </box>
      </box>
    </window>
  )
}
