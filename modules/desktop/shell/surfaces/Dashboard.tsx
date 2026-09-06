// The dashboard: most of the screen, off the Aleph in the corner (Super+D, `astal-shell toggle
// dashboard`). Everything that is about the machine rather than a window: the toggles (from
// the hub), power (from the rail), the shell's own knobs, and a keys hint. Esc or a click on
// the field closes it.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import { execAsync } from "ags/process"
import { Panel } from "../lib/tui"
import { Toggles } from "../panes/Toggles"
import { toggleCheatsheet } from "./Cheatsheet"
import { CalendarCard } from "../panes/Calendar"

let win: Astal.Window | null = null
export const dashboardOpen = () => !!win?.visible
export function hideDashboard() { if (win) win.visible = false }
export function showDashboard() {
  if (!win) return
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = app.get_monitors().find((m) => m.connector === name)
  if (mon) win.gdkmonitor = mon
  win.visible = true
}
export const toggleDashboard = () => (dashboardOpen() ? hideDashboard() : showDashboard())

const run = (cmd: string[]) => { hideDashboard(); execAsync(cmd).catch(console.error) }

/** A big square action: icon over a word. */
function Action({ icon, label, cls = [], onClick }: { icon: string; label: string; cls?: string[]; onClick: () => void }) {
  return (
    <button cssClasses={["action", ...cls]} onClicked={onClick}>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={4}>
        <label cssClasses={["icon"]} label={icon} />
        <label cssClasses={["sm"]} label={label} />
      </box>
    </button>
  )
}

function Power() {
  return (
    <box spacing={8} homogeneous>
      <Action icon={"\u{f033e}"} label="lock" onClick={() => run(["hyprlock"])} />
      <Action icon={"\u{f04b2}"} label="suspend" onClick={() => run(["systemctl", "suspend"])} />
      <Action icon={"\u{f0343}"} label="logout" cls={["red"]} onClick={() => run(["hyprctl", "dispatch", "exit"])} />
      <Action icon={"\u{f0709}"} label="reboot" cls={["red"]} onClick={() => run(["systemctl", "reboot"])} />
      <Action icon={"\u{f0425}"} label="shutdown" cls={["red"]} onClick={() => run(["systemctl", "poweroff"])} />
    </box>
  )
}

function Shell() {
  return (
    <box spacing={8} homogeneous>
      <Action icon={"\u{f030c}"} label="keys" onClick={() => { hideDashboard(); toggleCheatsheet() }} />
      <Action icon={"\u{f0450}"} label="restart shell" onClick={() => run(["bash", "-c", "sleep 0.2; pkill -x gjs; sleep 0.3; astal-shell"])} />
      <Action icon={"\u{f0453}"} label="reload hypr" onClick={() => run(["hyprctl", "reload"])} />
    </box>
  )
}

export default function Dashboard() {
  return (
    <window
      $={(self) => {
        win = self
        const k = new Gtk.EventControllerKey()
        k.connect("key-pressed", (_, kv) => (kv === Gdk.KEY_Escape || kv === Gdk.KEY_q ? (hideDashboard(), true) : false))
        self.add_controller(k)
      }}
      cssClasses={["dashboard"]}
      namespace="astal-shell-dashboard"
      name="dashboard"
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.ON_DEMAND}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.RIGHT}
      marginTop={36}
      marginLeft={54}
      application={app}
      visible={false}
    >
      {/* the field is the click-away; the board sits in it with a margin on every side — most of the screen, not all */}
      <overlay>
        <box
          cssClasses={["clickaway-field"]}
          hexpand
          vexpand
          $={(self) => {
            const g = new Gtk.GestureClick({ button: 0 })
            g.connect("pressed", () => hideDashboard())
            self.add_controller(g)
          }}
        />
        <box $type="overlay" cssClasses={["board"]} orientation={Gtk.Orientation.VERTICAL} spacing={12} halign={Gtk.Align.FILL} valign={Gtk.Align.FILL} marginTop={48} marginBottom={64} marginStart={48} marginEnd={96}>
          <box spacing={12}>
            <Panel title={"\u{f0493}  TOGGLES"} cssClasses={["card", "card-toggles"]} hexpand><Toggles perRow={5} /></Panel>
            <Panel title={"\u{f00ed}  CALENDAR"} cssClasses={["card", "card-calendar"]}><CalendarCard /></Panel>
          </box>
          <box spacing={12}>
            <Panel title={"\u{f0425}  POWER"} cssClasses={["card", "card-power"]} hexpand><Power /></Panel>
            <Panel title={"ℵ  SHELL"} cssClasses={["card", "card-shell"]} hexpand><Shell /></Panel>
          </box>
          <box vexpand />
          <box cssClasses={["keys"]} spacing={12}>
            <label label="Esc close" /><label label="Super+D toggle" />
          </box>
        </box>
      </overlay>
    </window>
  )
}
