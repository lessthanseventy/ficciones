// NET: the SSID and its signal (a minute of history), the addresses, per-interface rates.
import Gtk from "gi://Gtk?version=4.0"
import Network from "gi://AstalNetwork"
import { createBinding, createComputed } from "ags"
import { wifiHist } from "../lib/wifi"
import { addrs } from "../lib/top"
import { perf, rate } from "../lib/perf"
import { spark, meter } from "../lib/format"
import { RuleH } from "../lib/tui"

export function NetCard() {
  const net = Network.get_default()
  const wifi = createBinding(net, "wifi")
  const ssid = wifi((w) => w?.ssid || "no wifi")
  const strength = wifiHist((h) => h.at(-1) ?? 0)
  const wired = createBinding(net, "primary")((p) => p === Network.Primary.WIRED)
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={4}>
      <box spacing={10}>
        <label cssClasses={["amber", "lg"]} label={ssid} xalign={0} hexpand ellipsize={3} maxWidthChars={22} />
        <label cssClasses={["dim", "sm"]} label={wired((w) => (w ? "wired primary" : ""))} />
        <label cssClasses={strength((s) => [s > 0.6 ? "green" : s > 0.3 ? "amber" : "red"])} label={strength((s) => meter(s, 8))} />
        <label cssClasses={["dim", "sm"]} label={strength((s) => `${Math.round(s * 100)}%`)} widthChars={4} xalign={1} />
      </box>
      <label cssClasses={["spark", "green"]} label={wifiHist((h) => spark(h, 30))} xalign={0} />
      <label cssClasses={["dim", "sm"]} label={wifi((w) => (w?.activeAccessPoint ? `${w.activeAccessPoint.frequency > 5000 ? "5 GHz" : "2.4 GHz"} · ${w.activeAccessPoint.bssid ?? ""}` : "signal · last two minutes"))} xalign={0} />
      <RuleH />
      {Array.from({ length: 4 }, (_, i) => (
        <box spacing={10} visible={perf((p) => i < p.ifaces.length)}>
          <label cssClasses={["cyan", "sm"]} label={perf((p) => p.ifaces[i]?.name ?? "")} widthChars={9} xalign={0} />
          <label cssClasses={["amber", "sm"]} label={createComputed(() => { const p = perf(), a = addrs(); return a[p.ifaces[i]?.name ?? ""] ?? "—" })} widthChars={15} xalign={0} />
          <label cssClasses={["dim", "sm"]} label={perf((p) => (p.ifaces[i] ? `↓ ${rate(p.ifaces[i].rx)}/s` : ""))} widthChars={10} xalign={1} />
          <label cssClasses={["dim", "sm"]} label={perf((p) => (p.ifaces[i] ? `↑ ${rate(p.ifaces[i].tx)}/s` : ""))} widthChars={10} xalign={1} />
        </box>
      ))}
      <label cssClasses={["dim", "sm"]} label="no interface up" visible={perf((p) => p.ifaces.length === 0)} xalign={0} />
    </box>
  )
}
