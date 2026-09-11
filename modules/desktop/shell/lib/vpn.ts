// VPN: what is up (wireguard / tun / tailscale interfaces from `ip -j link`), Mullvad's own
// state through its CLI (installed and logged in here), and the wg-quick configs under
// /etc/wireguard. The rail's item shows on/off; its card lists them, click to toggle.
// Nothing here is exercised by tests — a tunnel change is Andrew's to make (2026-09-07).
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"
import Gio from "gi://Gio?version=2.0"
import { logEvent } from "./log"

export const vpn = createPoll<string[]>([], 5000, async () => {
  try {
    const links = JSON.parse(await execAsync(["ip", "-j", "link"])) as { ifname: string; link_type?: string; flags?: string[] }[]
    return links
      .filter((l) => (l.link_type === "none" || /^(wg|tun|tap|proton|nord|mullvad)/.test(l.ifname)) && l.flags?.includes("UP") && !/^lo$/.test(l.ifname))
      .map((l) => l.ifname)
  } catch { return [] }
})

export type Mullvad = { present: boolean; connected: boolean; state: string; location: string; relay: string; expires: string }
const NONE: Mullvad = { present: false, connected: false, state: "", location: "", relay: "", expires: "" }
// the relay and the account's expiry barely change: fetched every 5 min, the status every poll
let relay = "", expires = "", slowAt = 0
export const mullvad = createPoll<Mullvad>(NONE, 5000, async () => {
  try {
    const st = (await execAsync(["mullvad", "status"])).trim().split("\n")
    const state = st[0]?.trim() ?? ""
    const location = st.find((l) => /location/i.test(l))?.split(":").slice(1).join(":").replace(/\s*IPv[46].*$/, "").trim() ?? ""
    if (Date.now() - slowAt > 300_000) {
      slowAt = Date.now()
      relay = (await execAsync(["mullvad", "relay", "get"]).catch(() => "")).split("\n").find((l) => /Location/.test(l))?.split(":")[1]?.trim() ?? ""
      expires = (await execAsync(["mullvad", "account", "get"]).catch(() => "")).split("\n").find((l) => /Expires/.test(l))?.split(/:\s+/)[1]?.slice(0, 10) ?? ""
    }
    return { present: true, connected: /^connected/i.test(state), state, location, relay, expires }
  } catch { return NONE }
})
export const mullvadToggle = async () => {
  const on = mullvad.peek().connected
  logEvent("shell", `mullvad ${on ? "disconnect" : "connect"}`)
  try { await execAsync(["mullvad", on ? "disconnect" : "connect"]) } catch (e) { logEvent("shell", `mullvad: ${e}`, "warn") }
}

/** the wg-quick configs: /etc/wireguard/<name>.conf — up/down through polkit (pkexec) */
export function wgConfigs(): string[] {
  try {
    const e = Gio.File.new_for_path("/etc/wireguard").enumerate_children("standard::name", 0, null)
    const out: string[] = []
    let i: Gio.FileInfo | null
    while ((i = e.next_file(null))) if (i.get_name().endsWith(".conf")) out.push(i.get_name().replace(/\.conf$/, ""))
    return out.sort()
  } catch { return [] }
}
export const wgToggle = async (name: string, up: boolean) => {
  logEvent("shell", `wg-quick ${up ? "up" : "down"} ${name}`)
  try { await execAsync(["pkexec", "wg-quick", up ? "up" : "down", name]) } catch (e) { logEvent("shell", `wg-quick: ${String(e).split("\n")[0]}`, "warn") }
}
