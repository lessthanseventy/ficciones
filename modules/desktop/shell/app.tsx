import app from "ags/gtk4/app"
import { createBinding, For, This } from "ags"
import style from "./style/main.scss"
import Rail from "./surfaces/Rail"
import Bar from "./surfaces/Bar"
import Drawer from "./surfaces/Drawer"

// One process, every surface. Bars per monitor (exclusive, windows reflow around them); the
// drawer once, floating. `astal-shell toggle drawer` from a keybind reaches requestHandler.
app.start({
  css: style,
  instanceName: "astal-shell",
  gtkTheme: "Adwaita",
  requestHandler(argv, res) {
    const [verb, what] = argv
    if (verb === "toggle" && what) {
      try { app.toggle_window(what); res("ok") } catch (e) { res(String(e)) }
      return
    }
    res("usage: astal-shell toggle <drawer>")
  },
  main() {
    const monitors = createBinding(app, "monitors")
    // gnim cannot nest a <For> inside a fragment, so the drawer is created outright and the
    // per-monitor bars come back as the tree.
    Drawer()
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
