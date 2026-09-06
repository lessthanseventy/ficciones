import app from "ags/gtk4/app"
import { closeOnPress } from "./Clickaway"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import GLib from "gi://GLib?version=2.0"
import { For, onCleanup, createComputed, type Accessor } from "ags"
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"
import { hypr, workspaces, focusedWorkspace } from "../lib/hypr"
import { RuleH, Panel } from "../lib/tui"
import { toggleWeather, showWeather, hideWeather, weatherOpen, weatherCard } from "./WeatherPop"
import { hoverPopover, hoverPanel } from "../lib/hover"
import TrayPane from "./Tray"
import { toggleDashboard } from "./Dashboard"
import { toggleDrawer, showDrawer, hideDrawer, drawerOpen, drawerSheet } from "./Drawer"
import { weather, glyph } from "../lib/weather"
import { Channel } from "../lib/cava"
import { WorkspacePop } from "../panes/Workspaces"

/** This monitor's workspaces only, its active one chipped — two monitors, two rails. */
function Workspaces({ connector }: { connector: string }) {
  const mine = createComputed([workspaces, focusedWorkspace], (all) =>
    all.filter((w) => w.monitor?.name === connector),
  )
  const active = () => hypr.get_monitors().find((m) => m.name === connector)?.activeWorkspace
  // Wheel over the pane walks this monitor's workspaces in id order and stops at the ends —
  // Hyprland's m+1/m-1 wrap around, which Andrew does not want (2026-09-05).
  const scroll = new Gtk.EventControllerScroll({ flags: Gtk.EventControllerScrollFlags.VERTICAL })
  scroll.connect("scroll", (_, __, dy) => {
    const cur = active()
    const ids = mine.get().map((w) => w.id).filter((id) => id > 0).sort((a, b) => a - b)
    const i = cur ? ids.indexOf(cur.id) : -1
    const next = ids[i + (dy > 0 ? 1 : -1)]
    if (i >= 0 && next !== undefined) hypr.dispatch("workspace", String(next))
    return true
  })
  return (
    <box cssClasses={["workspaces"]} orientation={Gtk.Orientation.VERTICAL} spacing={2} $={(self) => self.add_controller(scroll)}>
      <For each={mine}>
        {(ws) => {
          const classes = createComputed([focusedWorkspace], () => [
            "ws",
            ...(active()?.id === ws.id ? ["focused"] : []),
            ...(ws.get_clients().length > 0 ? ["occupied"] : []),
          ])
          // hover shows the workspace's windows off to the right; a click still goes there
          return (
            <menubutton cssClasses={classes} direction={Gtk.ArrowType.RIGHT} halign={Gtk.Align.CENTER} $={(self) => hoverPopover(self, "rail", () => ws.focus())}>
              <label label={String(ws.id)} />
              <popover cssClasses={["pop"]}>
                <Panel title={createComputed([focusedWorkspace], () => `WS ${ws.id} · ${ws.monitor?.name ?? ""}`)}><WorkspacePop ws={ws} /></Panel>
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
    <button cssClasses={["corner"]} onClicked={() => toggleDashboard()}>
      <overlay>
        <label cssClasses={["aleph"]} label={"\u2135"} />
        <label $type="overlay" cssClasses={["hron"]} label={"\u2135"} canTarget={false} />
      </overlay>
    </button>
  )
}

/** Stacked clock: click opens the info panel. */
function Clock() {
  const now = createPoll(GLib.DateTime.new_now_local(), 1000, () => GLib.DateTime.new_now_local())
  return (
    <button
      cssClasses={["clock"]}
      onClicked={() => toggleDrawer()}
      $={(self) => hoverPanel(self, "rail", { show: () => showDrawer(undefined, false), hide: hideDrawer, isOpen: drawerOpen, window: drawerSheet })}
    >
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["hh"]} label={now((d) => d.format("%H")!)} />
        <label cssClasses={["mm"]} label={now((d) => d.format("%M")!)} />
        <label cssClasses={["dow"]} label={now((d) => d.format("%a")!)} />
        <label cssClasses={["day"]} label={now((d) => d.format("%d")!)} />
        <label cssClasses={["mon"]} label={now((d) => d.format("%b")!)} />
      </box>
    </button>
  )
}

/** Under the clock: the sky and the temperature; click for the whole forecast. */
function Weather() {
  const g = weather((w) => (w.ok ? glyph(w.code) : "\u{f0590}"))
  const t = weather((w) => (w.ok ? `${Math.round(w.temp!)}°` : "—"))
  const cls = weather((w) => ["item", "wx", ...(w.ok ? [] : ["dim"])])
  return (
    <button
      cssClasses={cls}
      onClicked={() => toggleWeather()}
      $={(self) => hoverPanel(self, "rail", { show: () => showWeather(false), hide: hideWeather, isOpen: weatherOpen, window: weatherCard })}
    >
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["g"]} label={g} />
        <label cssClasses={["t"]} label={t} />
      </box>
    </button>
  )
}

export default function Rail({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  let win: Astal.Window
  const { TOP, LEFT, BOTTOM } = Astal.WindowAnchor

  onCleanup(() => win.destroy())

  return (
    <window
      $={(self) => { win = self; closeOnPress(self) }}
      visible
      defaultWidth={1} // shrink to content; a GtkWindow otherwise pads its default size
      cssClasses={["rail"]}
      namespace="astal-shell-rail"
      name={`rail-${gdkmonitor.connector}`}
      gdkmonitor={gdkmonitor}
      exclusivity={Astal.Exclusivity.EXCLUSIVE}
      anchor={TOP | LEFT | BOTTOM}
      application={app}
    >
      <centerbox orientation={Gtk.Orientation.VERTICAL}>
        <box $type="start" orientation={Gtk.Orientation.VERTICAL}>
          <Corner />
          <Workspaces connector={gdkmonitor.connector} />
          <RuleH />
        </box>
        <box $type="center" orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.CENTER}>
          <Channel side="left" />
          <Clock />
          <Weather />
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
