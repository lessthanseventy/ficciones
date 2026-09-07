// Zoom's share toolbar ("You are screen sharing · Stop share") and annotation bar are X11
// override-redirect windows typed _NET_WM_WINDOW_TYPE_TOOLTIP — and Hyprland gives a tooltip
// no pointer input, so Stop share could not be clicked (2026-09-07; found by rewriting the
// property on the live window). A window rule cannot change an X11 property, so this does:
// on every such window, set the type to NORMAL through xprop, and move it below the bar,
// where Zoom parks it at y=0 under our exclusive strip. The WM_TRANSIENT_FOR hint goes too:
// with it, the toolbar only took clicks on the workspace of the main Zoom window.
import { execAsync } from "ags/process"
import { timeout } from "ags/time"
import { hypr } from "./hypr"
import { L, dispatch } from "./hyprlua"
import { logEvent } from "./log"

const TITLES = /^(as_toolbar|annotate_toolbar)$/
const BAR = 37

async function fix(title: string, address: string) {
  try {
    const tree = await execAsync(["xwininfo", "-root", "-tree"])
    const line = tree.split("\n").find((l) => l.includes(`"${title}"`))
    const id = line?.trim().split(/\s+/)[0]
    if (!id) return
    await execAsync(["xprop", "-id", id, "-f", "_NET_WM_WINDOW_TYPE", "32a", "-set", "_NET_WM_WINDOW_TYPE", "_NET_WM_WINDOW_TYPE_NORMAL"])
    // and not a transient: Hyprland gives an X11 transient pointer input only while its
    // parent is on a visible workspace — the toolbar went dead on every other workspace
    await execAsync(["xprop", "-id", id, "-remove", "WM_TRANSIENT_FOR"]).catch(() => {})
    const c = hypr.get_clients().find((x) => x.address === address)
    const m = c && hypr.get_monitors().find((mm) => mm.name === c.monitor?.name)
    if (c && m && c.y < m.y + BAR + 3) await dispatch(L.moveExact(`address:0x${address.replace(/^0x/, "")}`, c.x, m.y + BAR + 3))
    logEvent("shell", `zoom ${title}: clickable, below the bar`, "dim")
  } catch (e) { logEvent("shell", `zoom toolbar fix: ${String(e).split("\n")[0]}`, "warn") }
}

hypr.connect("client-added", (_, c) => {
  if (c.class !== "zoom" || !TITLES.test(c.title ?? "")) return
  // the X11 tree lists it a moment after Hyprland maps it
  timeout(150, () => fix(c.title, c.address))
})
// the ones already up at start
for (const c of hypr.get_clients()) if (c.class === "zoom" && TITLES.test(c.title ?? "")) fix(c.title, c.address)
