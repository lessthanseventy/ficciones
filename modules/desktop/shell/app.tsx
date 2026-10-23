import GObject from "gi://GObject?version=2.0"
import GLib from "gi://GLib?version=2.0"
import Gio from "gi://Gio?version=2.0"
import Gdk from "gi://Gdk?version=4.0"
import { exit, programArgs } from "system"
import app from "ags/gtk4/app"
import { createBinding, For, This } from "ags"
import style from "./style/main.scss"
import Rail, { toggleCalendarPop, toggleWeatherPop, popWorkspace } from "./surfaces/Rail"
import Bar from "./surfaces/Bar"
import Notifications from "./surfaces/Notifications"
import { DecisionBanner, Alarms } from "./surfaces/Alerts"
import DocReader from "./surfaces/DocReader"
import { startAlerts } from "./lib/alerts"
import Hub, { startHotEdge, toggleHub } from "./surfaces/Hub"
import Deck, { DeckRow, toggleDeck } from "./surfaces/Deck"
import { logEvent } from "./lib/log"
import { setSuperHeld } from "./lib/hypr"
import { initAwake } from "./lib/awake"
import "./lib/zoomfix"
import { screenshot, startRecording, stopRecording } from "./lib/capture"
import Launcher, { toggleLauncher } from "./surfaces/Launcher"
import Cheatsheet, { toggleCheatsheet } from "./surfaces/Cheatsheet"
import Settings, { toggleSettings } from "./surfaces/Settings"
import { sendToOtherScreen } from "./lib/display"
import { setCrt, cycleCrt, MODES, type Crt } from "./lib/crt"
import Backdrop, { setBackdrop, MODE_NAMES, type BackdropMode } from "./surfaces/Backdrop"
import { popAgents } from "./surfaces/Deck"
import Office, { toggleOffice } from "./surfaces/Office"
import Dashboard, { toggleDashboard } from "./surfaces/Dashboard"
import Osd from "./surfaces/Osd"
import { setTheme, THEMES, applyShellTheme, type Theme } from "./lib/theme"
import { sidecarVerb, colresize, focusDir, adoptSidecars } from "./lib/sidecar"
import { toggleQuake } from "./lib/quake"
import { setGlass, toggleGlass } from "./lib/glass"
import { cards } from "./lib/hover"
import { getCli, setCli, setting } from "./lib/settings"
import "./lib/night"
import "./lib/opaque"

// One process, every surface. Bars per monitor (exclusive, windows reflow around them); the
// drawer once, floating. `astal-shell toggle drawer` from a keybind reaches requestHandler.
// The unit starts it with NO arguments; a verb reaches the instance that unit is running. Either
// mismatch would degrade quietly, so both refuse:
//   - a verb with no shell up would become the shell itself, outside the unit and its
//     restart-on-failure (2026-09-11)
//   - a bare start with a shell already up becomes a CLIENT of the stray, answers its own empty
//     argv with the usage string and exits 0 — which Restart=on-failure ignores, so the unit sits
//     dead while the stray paints the screen and `machine:update` still goes green (2026-09-24,
//     found after a flake bump: the pre-bump shell held the name and the new build never came up)
const [up] = Gio.DBus.session.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner",
  new GLib.Variant("(s)", ["io.Astal.astal-shell"]), null, Gio.DBusCallFlags.NONE, -1, null).deepUnpack() as [boolean]
if (programArgs.length > 0 && !up) {
  printerr("astal-shell is not running: systemctl --user start astal-shell"); exit(1)
}
if (programArgs.length === 0 && up) {
  printerr("astal-shell is already running outside this unit — the name io.Astal.astal-shell is taken.\nStop the stray, then start the unit: pkill -x gjs; systemctl --user reset-failed astal-shell; systemctl --user start astal-shell")
  exit(1)
}
app.start({
  css: style,
  instanceName: "astal-shell",
  gtkTheme: "Adwaita",
  requestHandler(argv, res) {
    const [verb, what, tab] = argv
    // the command log: what you asked for (focus/colresize are keys, not events)
    if (verb && !["focus", "colresize", "super"].includes(verb)) logEvent("shell", argv.join(" "))
    if (verb === "super") { setSuperHeld(what === "down"); return res("ok") }
    // `astal-shell capture shot region|last|monitor|window [file|clip] [address]` / `capture rec region|monitor` / `capture stop`
    if (verb === "capture") {
      if (what === "shot" && (tab === "region" || tab === "last" || tab === "monitor" || tab === "window")) screenshot(tab, argv[3] === "file" || argv[3] === "clip" ? argv[3] : "both", argv[4])
      else if (what === "rec" && (tab === "region" || tab === "monitor")) startRecording(tab)
      else if (what === "stop") stopRecording()
      else return res("usage: astal-shell capture shot region|monitor|window [file|clip] [address] | rec region|monitor | stop")
      return res("ok")
    }
    if (verb === "toggle" && what === "deck") {
      toggleDeck()
      return res("ok")
    }
    // the drawer and the weather surface are popovers off the rail now (2026-09-05); the
    // verbs still land
    if (verb === "toggle" && (what === "drawer" || what === "calendar")) {
      toggleCalendarPop()
      return res("ok")
    }
    if (verb === "toggle" && what === "office") {
      toggleOffice()
      return res("ok")
    }
    if (verb === "toggle" && what === "launcher") {
      toggleLauncher(null)
      return res("ok")
    }
    if (verb === "toggle" && what === "clipboard") {
      toggleLauncher("clip")
      return res("ok")
    }
    if (verb === "toggle" && what === "settings") {
      toggleSettings(tab)
      return res("ok")
    }
    if (verb === "toggle" && what === "cheatsheet") {
      toggleCheatsheet()
      return res("ok")
    }
    if (verb === "glass") {
      what === "on" ? setGlass(true) : what === "off" ? setGlass(false) : toggleGlass()
      return res("ok")
    }
    if (verb === "backdrop") {
      // no argument cycles (Super+Shift+Z); `toggle` is the old on/off; a mode name holds it
      const names: string[] = ["zen", "photo", "toggle", "cycle", "random", ...MODE_NAMES, "rule30"]
      setBackdrop(!what ? "cycle" : names.includes(what) ? (what === "rule30" ? "rule 30" : what) as any : "cycle")
      return res("ok")
    }
    if (verb === "crt") {
      if (what && (MODES as readonly string[]).includes(what)) setCrt(what as Crt)
      else cycleCrt()
      return res("ok")
    }
    if (verb === "toggle" && what === "weather") {
      toggleWeatherPop()
      return res("ok")
    }
    if (verb === "toggle" && what === "dashboard") {
      toggleDashboard()
      return res("ok")
    }
    if (verb === "pop" && what === "ws") {
      popWorkspace(Number(tab))
      return res("ok")
    }
    if (verb === "pop" && what === "card") {
      const c = cards.get(tab)
      if (!c) return res(`no card ${tab}: ${[...cards.keys()].join(" ")}`)
      c.toggle()
      return res("ok")
    }
    if (verb === "focus" && (what === "l" || what === "r")) {
      focusDir(what)
      return res("ok")
    }
    if (verb === "colresize") {
      colresize(what ?? "wider")
      return res("ok")
    }
    if (verb === "quake") {
      void toggleQuake()
      return res("ok")
    }
    if (verb === "sidecar") {
      sidecarVerb(what, tab)
      return res("ok")
    }
    if (verb === "display" && what === "send") {
      void sendToOtherScreen()
      return res("ok")
    }
    if (verb === "theme") {
      setTheme(what && (THEMES as readonly string[]).includes(what) ? (what as Theme) : "toggle")
      return res("ok")
    }
    if (verb === "toggle" && what === "hub") {
      toggleHub()
      return res("ok")
    }
    if (verb === "show" && what === "drawer") {
      // agents left the info surface for the rail (2026-09-05); the old verb still lands there
      if (tab === "agents") popAgents()
      else toggleCalendarPop()
      return res("ok")
    }
    if (verb === "get") return res(getCli(what))
    if (verb === "set") return res(setCli(what, argv.slice(2).join(" ")))
    res("usage: astal-shell get [KEY] | set KEY VALUE | capture … | toggle drawer|hub|deck|office|dashboard|settings [backdrop|look|notifications|feel]|launcher|clipboard|cheatsheet|weather | crt [off|subtle|full] | backdrop [cycle|toggle|zen|photo|random|lorenz|babel|life|boids|rule30|pipes|bonsai|maze|stars|flow|ant|rain] | glass [on|off] | display send | theme [uqbar|zahir] | sidecar [toggle|pin|unpin] | colresize narrower|wider | focus l|r | show drawer [calendar|agents] | pop ws N | pop card NAME | quake | super down|up")
  },
  main() {
    // ags's `app` is typed against its own copy of GObject, not gnim's (ags 3.1 under TS 5.9;
    // a stock `ags init` project fails the same way), so it is seen through gnim's here
    const gapp = app as unknown as GObject.Object & { monitors: Gdk.Monitor[] }
    const monitors = createBinding(gapp, "monitors")
    // gnim cannot nest a <For> inside a fragment, so the drawer is created outright and the
    // per-monitor bars come back as the tree.
    Notifications()
    DecisionBanner()
    DocReader()
    startAlerts()
    Hub()
    Deck()
    Office()
    startHotEdge()
    // the live theme's stylesheet over the bundled default (the same css when they agree); from
    // source (shell:dev) the bundled css is the working tree's, and the installed one would hide
    // every style change until a home:switch
    if (!GLib.getenv("ASTAL_SHELL_DEV")) applyShellTheme()
    const start = setting("backdrop.startup").peek()
    setBackdrop(start === "photo" || (MODE_NAMES as readonly string[]).includes(start) ? (start as BackdropMode) : "random")
    initAwake()
    adoptSidecars()
    Launcher()
    Cheatsheet()
    Settings()
    Dashboard()
    Osd()
    return (
      <For each={monitors}>
        {(monitor: Gdk.Monitor) => (
          <This this={gapp}>
            {/* in this order: layer-shell arranges by mapping order, so the rail keeps the full
                height and the bar and the deck's row both start after it */}
            <Rail gdkmonitor={monitor} />
            <Bar gdkmonitor={monitor} />
            <DeckRow gdkmonitor={monitor} />
            <Backdrop gdkmonitor={monitor} />
            <Alarms gdkmonitor={monitor} />
          </This>
        )}
      </For>
    )
  },
})
