// The sound's spectrum along the foot of the desktop. A window of its own on BOTTOM, not a child
// of the backdrop: a screensaver hack is another process's BACKGROUND layer and the backdrop
// hides its window while one runs, and BOTTOM is over both and under every window.
import app from "ags/gtk4/app"
import { Astal, type Gdk } from "ags/gtk4"
import Cairo from "cairo"
import { createComputed, onCleanup } from "ags"
import { SpectrumBars } from "../lib/cava"
import { fullscreenMonitors } from "../lib/hypr"
import { setting } from "../lib/settings"
import { soundRunning } from "../lib/sound"

export default function Spectrum({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  const on = setting("backdrop.spectrum"), height = setting("backdrop.spectrumHeight")
  const shown = createComputed(() => on() && soundRunning() && !fullscreenMonitors().has(gdkmonitor.connector ?? ""))
  return (
    <window
      cssClasses={["spectrum-win"]}
      namespace="astal-shell-spectrum"
      name={`spectrum-${gdkmonitor.connector}`}
      gdkmonitor={gdkmonitor}
      layer={Astal.Layer.BOTTOM}
      anchor={Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM}
      application={app}
      visible={shown}
      $={(self) => {
        // both: a size request alone is a minimum, and GTK never shrinks the surface back
        const size = () => {
          const h = Math.round(gdkmonitor.geometry.height * Math.min(1, Math.max(0.05, height.peek())))
          self.set_size_request(-1, h); self.set_default_size(-1, h)
        }
        size()
        onCleanup(height.subscribe(size))
        // on every map, as hiding drops the surface: clicks fall through to the desktop
        self.connect("map", () => self.get_surface()?.set_input_region(new Cairo.Region()))
      }}
    >
      <SpectrumBars shown={shown} />
    </window>
  )
}
