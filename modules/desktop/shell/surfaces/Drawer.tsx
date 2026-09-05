// The info pane: a floating top sheet, five tabs, lazygit navigation. 1-5 jump, Tab cycles,
// Escape closes. Toggled by the rail clock, `astal-shell toggle drawer`, and Super+I.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import { createState, For } from "ags"
import { RuleH } from "../lib/tui"
import Dash from "../panes/Dash"
import Perf from "../panes/Perf"
import Media from "../panes/Media"
import Weather from "../panes/Weather"
import Agents from "../panes/Agents"

const TABS = ["DASH", "PERF", "MEDIA", "WEATHER", "AGENTS"] as const
export type Tab = (typeof TABS)[number]

let goTo: ((t: Tab) => void) | null = null
/** Open the drawer on a pane, from anywhere (a perf cell, a keybind with an argument). */
export function showDrawer(tab?: Tab) {
  const w = app.get_window("drawer")
  if (!w) return
  if (tab) goTo?.(tab)
  w.visible = true
}

export default function Drawer() {
  let win: Astal.Window
  let stack: Gtk.Stack
  const [tab, setTab] = createState<Tab>("DASH")

  const go = (t: Tab) => {
    setTab(t)
    stack.visibleChildName = t
  }
  goTo = go
  const onKey = (_: Gtk.EventControllerKey, keyval: number) => {
    const n = keyval - Gdk.KEY_1
    if (n >= 0 && n < TABS.length) return go(TABS[n]), true
    if (keyval === Gdk.KEY_Tab) return go(TABS[(TABS.indexOf(tab.get()) + 1) % TABS.length]), true
    if (keyval === Gdk.KEY_ISO_Left_Tab) return go(TABS[(TABS.indexOf(tab.get()) + TABS.length - 1) % TABS.length]), true
    if (keyval === Gdk.KEY_Escape) return (win.visible = false), true
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
      anchor={Astal.WindowAnchor.TOP}
      marginTop={44} // under the bar (36) + a gap; both sit on the TOP layer
      application={app}
    >
      <box cssClasses={["sheet"]} orientation={Gtk.Orientation.VERTICAL} widthRequest={1100}>
        <box cssClasses={["tabs"]} spacing={4}>
          {TABS.map((t, i) => (
            <button
              cssClasses={tab((cur) => ["tabbtn", ...(cur === t ? ["tab"] : [])])}
              onClicked={() => go(t)}
            >
              <label label={`${i + 1} ${t}`} />
            </button>
          ))}
          <box hexpand />
          <label cssClasses={["dim", "sm"]} label="Esc close" />
        </box>
        <RuleH />
        <stack
          $={(self) => (stack = self)}
          cssClasses={["body"]}
          transitionType={Gtk.StackTransitionType.CROSSFADE}
          transitionDuration={80}
          vhomogeneous={false}
        >
          <box $type="named" name="DASH"><Dash /></box>
          <box $type="named" name="PERF"><Perf /></box>
          <box $type="named" name="MEDIA"><Media /></box>
          <box $type="named" name="WEATHER"><Weather /></box>
          <box $type="named" name="AGENTS"><Agents /></box>
        </stack>
        <RuleH />
        <box cssClasses={["keys"]} spacing={16}>
          <label label="1-5 pane" /><label label="Tab next" /><label label="Esc close" />
        </box>
      </box>
    </window>
  )
}
