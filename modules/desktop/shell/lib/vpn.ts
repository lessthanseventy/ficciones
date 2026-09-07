// A VPN tunnel that is up: wireguard or tun interfaces from `ip -j link`, polled every 5 s.
// The rail shows the first one's name; nothing when none.
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"

export const vpn = createPoll<string[]>([], 5000, async () => {
  try {
    const links = JSON.parse(await execAsync(["ip", "-j", "link"])) as { ifname: string; link_type?: string; operstate?: string; flags?: string[] }[]
    return links
      .filter((l) => (l.link_type === "none" || /^(wg|tun|tap|proton|nord|mullvad)/.test(l.ifname)) && l.flags?.includes("UP") && !/^lo$/.test(l.ifname))
      .map((l) => l.ifname)
  } catch { return [] }
})
