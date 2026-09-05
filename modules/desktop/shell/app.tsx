import app from "ags/gtk4/app"
import { createBinding, For, This } from "ags"
import style from "./style/main.scss"
import Rail from "./surfaces/Rail"
import Bar from "./surfaces/Bar"

// One process, every surface, per monitor. Both bars are exclusive so windows reflow around
// them; everything later (drawer, launcher, OSD) floats.
app.start({
  css: style,
  instanceName: "astal-shell",
  gtkTheme: "Adwaita",
  main() {
    const monitors = createBinding(app, "monitors")
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
