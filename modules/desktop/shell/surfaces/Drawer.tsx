// The info panel: a single column of cards beside the rail. Each card is a pane with an icon
// in its title; the focused card is framed amber. 1-4 focus, Tab/Shift-Tab cycle, j/k move
// the cursor inside a card, Escape or q closes. Opens on the monitor the pointer is on.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import { Panel } from "../lib/tui"
import { timeout } from "ags/time"
import { PANES, type Pane, focus, setFocus, move } from "../lib/nav"
import { CalendarCard } from "../panes/Calendar"
import { AgentsCard } from "../panes/Agents"
import { agents } from "../lib/agents"
import { armClickaway, disarmClickaway } from "./Clickaway"

const cards: Record<Pane, { icon: string; body: () => JSX.Element; rows: () => number }> = {
  CALENDAR: { icon: "\u{f00ed}", body: CalendarCard, rows: () => 0 },
  AGENTS:   { icon: "\u{f06a9}", body: AgentsCard, rows: () => agents.get().roster.length },
}

let sheet: Gtk.Widget | null = null
/** The card column — what hover-open watches (the window itself spans the monitor). */
export const drawerSheet = () => sheet
export const drawerOpen = () => !!app.get_window("drawer")?.visible

/**
 * Open the panel (on a card, from anywhere) on the monitor the pointer is on. `keyboard`
 * false = a hover open: no focus taken from what Andrew is typing into.
 */
export function showDrawer(pane?: Pane, keyboard = true) {
  const w = app.get_window("drawer") as Astal.Window | undefined
  if (!w) return
  if (pane) setFocus(pane)
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = app.get_monitors().find((m) => m.connector === name)
  if (mon) w.gdkmonitor = mon
  w.keymode = keyboard ? Astal.Keymode.ON_DEMAND : Astal.Keymode.NONE
  w.visible = true
  armClickaway(() => hideDrawer())
}
export function hideDrawer() {
  const w = app.get_window("drawer") as Astal.Window | undefined
  if (!w) return
  w.visible = false
  w.keymode = Astal.Keymode.NONE
  disarmClickaway()
}
export function toggleDrawer() {
  const w = app.get_window("drawer")
  if (w?.visible) hideDrawer()
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
      case Gdk.KEY_Escape: case Gdk.KEY_q: return hideDrawer(), true
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
        // on-demand keyboard: Hyprland focuses the panel on map, and a click anywhere else
        // takes the focus back — that is the click-away
        self.connect("notify::is-active", () => {
          if (self.visible && !self.isActive) timeout(120, () => { if (self.visible && !self.isActive) hideDrawer() })
        })
      }}
      visible={false}
      cssClasses={["drawer"]}
      namespace="astal-shell-drawer"
      name="drawer"
      layer={Astal.Layer.OVERLAY} // above the clickaway, which sits on TOP
      keymode={Astal.Keymode.NONE}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.RIGHT}
      marginTop={36} // under the bar
      marginLeft={54} // beside the rail with a gap, never over it
      application={app}
    >
      {/* the surface spans the monitor: the column at the left, and the rest is the click-away */}
      <box>
      <box cssClasses={["sheet"]} orientation={Gtk.Orientation.VERTICAL} widthRequest={420} hexpand={false} halign={Gtk.Align.START} $={(self) => { sheet = self }}>
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
          <label label="1-2 card" /><label label="Tab next" /><label label="j/k row" /><label label="Esc close" />
        </box>
      </box>
      <box
        cssClasses={["clickaway-field"]}
        hexpand
        vexpand
        $={(self) => {
          const g = new Gtk.GestureClick({ button: 0 })
          g.connect("pressed", () => hideDrawer())
          self.add_controller(g)
        }}
      />
      </box>
    </window>
  )
}
