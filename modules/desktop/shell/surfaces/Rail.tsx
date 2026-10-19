import { L, dispatch } from "../lib/hyprlua"
import { iconFor } from "../lib/icons"
import app from "ags/gtk4/app"
import { closeOnPress } from "./Clickaway"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import GLib from "gi://GLib?version=2.0"
import { For, onCleanup, createComputed, type Accessor } from "ags"
import { createPoll } from "ags/time"
import { hypr, workspaces, focusedWorkspace, focusedClient, clients, superHeld, lastClientOn } from "../lib/hypr"
import { RuleH, Panel } from "../lib/tui"
import { WeatherCard } from "../panes/Weather"
import { CalendarCard } from "../panes/Calendar"
import { hoverPopover } from "../lib/hover"
import TrayPane from "./Tray"
import { toggleDashboard } from "./Dashboard"
import { toggleSettings } from "./Settings"
import { type HoverPop } from "../lib/hover"
import { weather, glyph } from "../lib/weather"
import { Channel } from "../lib/cava"
import { WorkspacePop } from "../panes/Workspaces"
import { captureShowing, watchThumbs } from "../lib/thumbs"

/** Debug: `astal-shell pop ws <id>` opens that number's strip without a hover. */
const wsPops = new Map<number, HoverPop>()
export const popWorkspace = (id: number) => wsPops.get(id)?.toggle()

/** This monitor's workspaces only, its active one chipped — two monitors, two rails. */
function Workspaces({ connector }: { connector: string }) {
  const mine = createComputed(() => {
    focusedWorkspace() // a trigger: w.monitor is not tracked
    return workspaces().filter((w) => w.monitor?.name === connector)
  })
  const active = () => hypr.get_monitors().find((m) => m.name === connector)?.activeWorkspace
  // Wheel over the pane walks this monitor's workspaces in id order and stops at the ends —
  // Hyprland's m+1/m-1 wrap around, which Andrew does not want (2026-09-05).
  const scroll = new Gtk.EventControllerScroll({ flags: Gtk.EventControllerScrollFlags.VERTICAL })
  scroll.connect("scroll", (_, __, dy) => {
    const cur = active()
    const ids = mine.peek().map((w) => w.id).filter((id) => id > 0).sort((a, b) => a - b)
    const i = cur ? ids.indexOf(cur.id) : -1
    const next = ids[i + (dy > 0 ? 1 : -1)]
    if (i >= 0 && next !== undefined) dispatch(L.workspace(String(next)))
    return true
  })
  return (
    <box cssClasses={["workspaces"]} orientation={Gtk.Orientation.VERTICAL} spacing={2} $={(self) => self.add_controller(scroll)}>
      <For each={mine}>
        {(ws) => {
          const classes = focusedWorkspace(() => [
            "ws",
            ...(active()?.id === ws.id ? ["focused"] : []),
            ...(ws.get_clients().length > 0 ? ["occupied"] : []),
          ])
          // Super held + hover shows the workspace's windows off to the right; a click goes there
          return (
            <menubutton
              cssClasses={classes}
              direction={Gtk.ArrowType.RIGHT}
              halign={Gtk.Align.CENTER}
              // a long dwell (Andrew: "only on hover for a while"); the showing workspace's thumbs refresh first
              $={(self) => { watchThumbs(self.popover as Gtk.Popover); wsPops.set(ws.id, hoverPopover(self, "rail", () => dispatch(L.workspace(String(ws.id))), { hover: () => superHeld.peek(), dwell: 250, onShow: () => captureShowing() })) }}
            >
              {/* the last active window's icon; the number when empty, or while Super is held */}
              {(() => {
                const last = createComputed(() => {
                  clients(); focusedClient() // triggers: lastClientOn reads hypr directly
                  return superHeld() ? null : lastClientOn(ws)
                })
                return (
                  <box halign={Gtk.Align.CENTER}>
                    <image iconName={last((c) => (c ? iconFor(c) : "application-x-executable"))} pixelSize={18} visible={last((c) => !!c)} />
                    <label label={String(ws.id)} visible={last((c) => !c)} />
                  </box>
                )
              })()}
              <popover cssClasses={["pop", "pop-workspaces"]}>
                <Panel title={focusedWorkspace(() => `\u{f0e18}  WS ${ws.id} · ${ws.monitor?.name ?? ""}`)} cssClasses={["card", "card-workspaces"]}><WorkspacePop ws={ws} /></Panel>
              </popover>
            </menubutton>
          )
        }}
      </For>
    </box>
  )
}

/**
 * The corner where the rail meets the bar: a hrön of the Aleph. In Tlön an object looked for
 * is found twice; here the second aleph is the double a pair of XLRS eyes would see anyway, a
 * few pixels off and dimmer — until you look straight at it, when the two resolve into one.
 * Click = the dashboard (the point that holds every other point).
 */
function Corner() {
  return (
    // toggles on the PRESS, not GTK's clicked: once the dashboard is up and holds the keyboard
    // the rail loses its pointer crossing state, and a second click on the same spot without a
    // move never completes as a click (Andrew, 2026-09-07)
    <button cssClasses={["corner"]} $={(self) => { const g = new Gtk.GestureClick({ button: 1, propagationPhase: Gtk.PropagationPhase.CAPTURE }); g.connect("pressed", () => {
      // Super+Shift+click opens settings (plain Super+click is Hyprland's window drag)
      const m = g.get_current_event_state(), want = Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.SHIFT_MASK
      ;(m & want) === want ? toggleSettings() : toggleDashboard()
      g.set_state(Gtk.EventSequenceState.CLAIMED)
    }); self.add_controller(g) }}>
      <overlay>
        <label cssClasses={["aleph"]} label={"\u2135"} />
        <label $type="overlay" cssClasses={["hron"]} label={"\u2135"} canTarget={false} />
      </overlay>
    </button>
  )
}

// The clock and weather popovers, per monitor, so a keybind can pop the one on the focused
// monitor's rail (`astal-shell toggle drawer|weather`, Super+I / Super+Shift+W).
const clockPops = new Map<string, HoverPop>()
const weatherPops = new Map<string, HoverPop>()
function onFocused(pops: Map<string, HoverPop>) {
  const name = hypr.focusedMonitor?.name
  return pops.get(name ?? "") ?? [...pops.values()][0]
}
export const toggleCalendarPop = () => onFocused(clockPops)?.toggle()
export const toggleWeatherPop = () => onFocused(weatherPops)?.toggle()

/** Stacked clock: the calendar and agenda hang off it, like every other popover. */
function Clock({ connector }: { connector: string }) {
  const now = createPoll(GLib.DateTime.new_now_local(), 1000, () => GLib.DateTime.new_now_local())
  return (
    <menubutton cssClasses={["clock", "keep-open"]} direction={Gtk.ArrowType.RIGHT} $={(self) => clockPops.set(connector, hoverPopover(self, "rail"))}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["hh"]} label={now((d) => d.format("%H")!)} />
        <label cssClasses={["mm"]} label={now((d) => d.format("%M")!)} />
        <label cssClasses={["dow"]} label={now((d) => d.format("%a")!)} />
        <label cssClasses={["day"]} label={now((d) => d.format("%d")!)} />
        <label cssClasses={["mon"]} label={now((d) => d.format("%b")!)} />
      </box>
      <popover cssClasses={["pop", "pop-calendar"]}>
        <Panel title={"\u{f00ed}  CALENDAR"} cssClasses={["card", "card-calendar"]}><box widthRequest={420}><CalendarCard /></box></Panel>
      </popover>
    </menubutton>
  )
}

/** Under the clock: the sky and the temperature; the whole forecast hangs off it. */
function Weather({ connector }: { connector: string }) {
  const g = weather((w) => (w.ok ? glyph(w.code) : "\u{f0590}"))
  const t = weather((w) => (w.ok ? `${Math.round(w.temp!)}°` : "—"))
  const cls = weather((w) => ["item", "wx", "keep-open", ...(w.ok ? [] : ["dim"])])
  return (
    <menubutton cssClasses={cls} direction={Gtk.ArrowType.RIGHT} $={(self) => weatherPops.set(connector, hoverPopover(self, "rail"))}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["g"]} label={g} />
        <label cssClasses={["t"]} label={t} />
      </box>
      <popover cssClasses={["pop", "pop-weather"]}>
        <Panel title={"\u{f0590}  WEATHER"} cssClasses={["card", "card-weather"]}><box widthRequest={460}><WeatherCard /></box></Panel>
      </popover>
    </menubutton>
  )
}

export default function Rail({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  const connector = gdkmonitor.connector ?? ""
  let win: Astal.Window
  const { TOP, LEFT, BOTTOM } = Astal.WindowAnchor

  onCleanup(() => win.destroy())

  return (
    <window
      $={(self) => { win = self; closeOnPress(self)}}
      visible
      defaultWidth={1} // shrink to content; a GtkWindow otherwise pads its default size
      cssClasses={["rail"]}
      namespace="astal-shell-rail"
      name={`rail-${connector}`}
      gdkmonitor={gdkmonitor}
      exclusivity={Astal.Exclusivity.EXCLUSIVE}
      anchor={TOP | LEFT | BOTTOM}
      application={app}
    >
      <centerbox orientation={Gtk.Orientation.VERTICAL}>
        <box $type="start" orientation={Gtk.Orientation.VERTICAL}>
          <Corner />
          <Workspaces connector={connector} />
          <RuleH />
        </box>
        <box $type="center" orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.CENTER}>
          <Channel side="left" />
          <Clock connector={connector} />
          <Weather connector={connector} />
          <Channel side="right" />
        </box>
        <box $type="end" orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.END}>
          <RuleH />
          <TrayPane />
        </box>
      </centerbox>
    </window>
  )
}
