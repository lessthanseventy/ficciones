import app from "ags/gtk4/app"
import { closeOnPress } from "./Clickaway"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import GLib from "gi://GLib?version=2.0"
import { For, onCleanup, createComputed } from "ags"
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"
import { hypr, workspaces, focusedWorkspace } from "../lib/hypr"
import { RuleH, Panel } from "../lib/tui"
import { toggleWeather, showWeather, hideWeather, weatherOpen, weatherCard } from "./WeatherPop"
import { hoverPopover, hoverPanel } from "../lib/hover"
import TrayPane from "./Tray"
import { toggleLauncher } from "./Launcher"
import { toggleDrawer, showDrawer, hideDrawer, drawerOpen, drawerSheet } from "./Drawer"
import { weather, glyph } from "../lib/weather"
import { Channel } from "../lib/cava"

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
          return (
            <button cssClasses={classes} onClicked={() => ws.focus()} halign={Gtk.Align.CENTER}>
              <label label={String(ws.id)} />
            </button>
          )
        }}
      </For>
    </box>
  )
}

/** The corner where the rail meets the bar: the Aleph, the point that holds every other point —
 *  which is what a launcher is. Click = launcher. */
function Corner() {
  return (
    <button cssClasses={["corner"]} onClicked={() => toggleLauncher()}>
      <label label={"\u2135"} />
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

/** The power menu. Lock delegates to hyprlock; this shell never draws one (design §5).
 *  Click only — a menu with shutdown in it must never open by brushing past it. */
function Power() {
  const run = (cmd: string[]) => execAsync(cmd).catch(console.error)
  const items: [string, string, string[], string[]][] = [
    ["\u{f033e}", "lock", ["hyprlock"], []],
    ["\u{f0343}", "logout", ["hyprctl", "dispatch", "exit"], ["red"]],
    ["\u{f04b2}", "suspend", ["systemctl", "suspend"], []],
    ["\u{f0709}", "reboot", ["systemctl", "reboot"], ["red"]],
    ["\u{f0425}", "shutdown", ["systemctl", "poweroff"], ["red"]],
  ]
  return (
    <menubutton cssClasses={["item", "power"]} direction={Gtk.ArrowType.RIGHT}>
      <label cssClasses={["icon"]} label={"\u{f0425}"} />
      <popover cssClasses={["pop"]}>
        <Panel title="POWER" spacing={2}>
          {items.map(([icon, label, cmd, cls]) => (
            <button cssClasses={["row", "powerrow", ...cls]} onClicked={() => run(cmd)}>
              <box spacing={10}>
                <label cssClasses={["icon"]} label={icon} widthChars={2} />
                <label label={label} xalign={0} hexpand />
              </box>
            </button>
          ))}
        </Panel>
      </popover>
    </menubutton>
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
          <Power />
        </box>
      </centerbox>
    </window>
  )
}
