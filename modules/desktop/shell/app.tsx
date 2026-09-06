import app from "ags/gtk4/app"
import { createBinding, For, This } from "ags"
import style from "./style/main.scss"
import Rail from "./surfaces/Rail"
import Bar from "./surfaces/Bar"
import Drawer, { showDrawer, toggleDrawer } from "./surfaces/Drawer"
import Notifications from "./surfaces/Notifications"
import Hub, { HotEdge, toggleHub } from "./surfaces/Hub"
import Launcher, { toggleLauncher } from "./surfaces/Launcher"
import Cheatsheet, { toggleCheatsheet } from "./surfaces/Cheatsheet"
import { setCrt, cycleCrt, MODES, type Crt } from "./lib/crt"
import Backdrop, { setBackdrop } from "./surfaces/Backdrop"
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
    if (verb === "backdrop") {
      setBackdrop(what === "zen" || what === "photo" ? what : "toggle")
      return res("ok")
    }
    if (verb === "crt") {
      if (what && (MODES as readonly string[]).includes(what)) setCrt(what as Crt)
      else cycleCrt()
      return res("ok")
    }
    if (verb === "toggle" && what === "hub") {
      toggleHub()
      return res("ok")
    }
    if (verb === "show" && what === "drawer") {
      showDrawer(tab?.toUpperCase() as Pane | undefined)
      return res("ok")
    }
    res("usage: astal-shell toggle drawer|hub|launcher|clipboard|cheatsheet | crt [off|subtle|full] | backdrop [zen|photo] | show drawer [agents|media|weather|calendar]")
  },
  main() {
    const monitors = createBinding(app, "monitors")
    // gnim cannot nest a <For> inside a fragment, so the drawer is created outright and the
    // per-monitor bars come back as the tree.
    Drawer()
    Notifications()
    Hub()
    HotEdge()
    Launcher()
    Cheatsheet()
    Backdrop()
    return (
      <For each={monitors}>
        {(monitor) => (
          <This this={app}>
            <Rail gdkmonitor={monitor} />
            <Bar gdkmonitor={monitor} />
          </This>
        )}
      </For>
    )
  },
})
