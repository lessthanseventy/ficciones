import app from "ags/gtk4/app"
import { createBinding, For, This } from "ags"
import style from "./style/main.scss"
import Rail from "./surfaces/Rail"
import WeatherPop, { toggleWeather } from "./surfaces/WeatherPop"
import Bar from "./surfaces/Bar"
import Drawer, { showDrawer, toggleDrawer } from "./surfaces/Drawer"
import Notifications from "./surfaces/Notifications"
import Hub, { startHotEdge, toggleHub } from "./surfaces/Hub"
import Launcher, { toggleLauncher } from "./surfaces/Launcher"
import Cheatsheet, { toggleCheatsheet } from "./surfaces/Cheatsheet"
import { setCrt, cycleCrt, MODES, type Crt } from "./lib/crt"
import Backdrop, { setBackdrop } from "./surfaces/Backdrop"
import { setGlass, toggleGlass } from "./lib/glass"
import "./lib/night"
import type { Pane } from "./lib/nav"

// One process, every surface. Bars per monitor (exclusive, windows reflow around them); the
// drawer once, floating. `astal-shell toggle drawer` from a keybind reaches requestHandler.
app.start({
  css: style,
  instanceName: "astal-shell",
  gtkTheme: "Adwaita",
  requestHandler(argv, res) {
    const [verb, what, tab] = argv
    if (verb === "toggle" && what === "drawer") {
      toggleDrawer()
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
    if (verb === "toggle" && what === "cheatsheet") {
      toggleCheatsheet()
      return res("ok")
    }
    if (verb === "glass") {
      what === "on" ? setGlass(true) : what === "off" ? setGlass(false) : toggleGlass()
      return res("ok")
    }
    if (verb === "backdrop") {
      setBackdrop(what === "zen" || what === "photo" ? what : "toggle")
      return res("ok")
    }
    if (verb === "crt") {
      if (what && (MODES as readonly string[]).includes(what)) setCrt(what as Crt)
      else cycleCrt()
      return res("ok")
    }
    if (verb === "toggle" && what === "weather") {
      toggleWeather()
      return res("ok")
    }
    if (verb === "toggle" && what === "dashboard") {
      toggleDashboard()
      return res("ok")
    }
    if (verb === "toggle" && what === "hub") {
      toggleHub()
      return res("ok")
    }
    if (verb === "show" && what === "drawer") {
      // agents left the info surface for the rail (2026-09-05); the old verb still lands there
      if (tab === "agents") popAgents()
      else showDrawer(tab?.toUpperCase() as Pane | undefined)
      return res("ok")
    }
    res("usage: astal-shell toggle drawer|hub|dashboard|launcher|clipboard|cheatsheet|weather | crt [off|subtle|full] | backdrop [zen|photo] | glass [on|off] | show drawer [calendar|agents]")
  },
  main() {
    const monitors = createBinding(app, "monitors")
    // gnim cannot nest a <For> inside a fragment, so the drawer is created outright and the
    // per-monitor bars come back as the tree.
    Drawer()
    WeatherPop()
    Notifications()
    Hub()
    startHotEdge()
    // Andrew's defaults: glass and the zen backdrop on from login
    setGlass(true)
    setBackdrop("zen")
    Launcher()
    Cheatsheet()
    Dashboard()
    return (
      <For each={monitors}>
        {(monitor) => (
          <This this={app}>
            <Rail gdkmonitor={monitor} />
            <Bar gdkmonitor={monitor} />
            <Backdrop gdkmonitor={monitor} />
          </This>
        )}
      </For>
    )
  },
})
