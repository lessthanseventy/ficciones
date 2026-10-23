// Mirror or separate screens. Mirror is decided once a session, by the host's Hyprland config
// (hypr/hosts/<host>.lua): it writes "mirror" or "separate" to SCREENS at the session's first load
// and every reload reads that back, because turning a mirror on in a running session crashed
// Hyprland 0.56.2. Breaking one is safe live (a monitor arriving), so that is all the shell does.
import GLib from "gi://GLib"
import { execAsync } from "ags/process"
import { timeout } from "ags/time"
import { setting } from "./settings"
import { dispatch } from "./hyprlua"

const SCREENS = `${GLib.get_user_runtime_dir()}/hypr/${GLib.getenv("HYPRLAND_INSTANCE_SIGNATURE")}/ficciones-screens`

const mirrored = () => {
  try { return new TextDecoder().decode(GLib.file_get_contents(SCREENS)[1]).trim() === "mirror" } catch { return false }
}

async function separate() {
  if (!mirrored()) return
  GLib.file_set_contents(SCREENS, "separate\n")
  await execAsync(["hyprctl", "reload"]).catch((e) => console.error("display: reload:", String(e)))
}
setting("display.mirror").subscribe(() => { if (!setting("display.mirror").peek()) void separate() })

type Mon = { name: string; focused: boolean; mirrorOf: string }
const monitors = async () => JSON.parse(await execAsync(["hyprctl", "monitors", "-j"])) as Mon[]

/** The focused window to the other screen, breaking a mirror first; the screen that frees can
 * take a moment to come up, so it is looked for a few times. */
export async function sendToOtherScreen() {
  await separate()
  for (let left = 12; left > 0; left--) {
    const other = (await monitors().catch(() => [] as Mon[])).find((m) => !m.focused && m.mirrorOf === "none")
    if (other) return dispatch(`hl.dsp.window.move({ monitor = ${JSON.stringify(other.name)} })`)
    await new Promise((r) => timeout(250, () => r(null)))
  }
  console.error("display: no other screen to send the window to")
}
