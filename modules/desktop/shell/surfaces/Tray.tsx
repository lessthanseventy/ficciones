// The rail's foot: network and bluetooth as text items with detail popovers, then the
// StatusNotifier tray (Steam, Slack, wgtray…) as an icon grid. Popovers are the "detail on
// demand" surface — click opens, Escape or click-away closes.
import Gtk from "gi://Gtk?version=4.0"
import Network from "gi://AstalNetwork"
import Bluetooth from "gi://AstalBluetooth"
import Tray from "gi://AstalTray"
import Wp from "gi://AstalWp"
import Audio from "./Audio"
import { For, With, createBinding, createComputed } from "ags"
import { execAsync } from "ags/process"
import { meter, pct } from "../lib/format"
import { Panel, RuleH } from "../lib/tui"

function Net() {
  const net = Network.get_default()
  const wifi = createBinding(net, "wifi")
  const primary = createBinding(net, "primary")

  const icon = createComputed([primary, wifi], (p, w) =>
    p === Network.Primary.WIRED ? "\u{f0200}" : w?.ssid ? "\u{f05a9}" : "\u{f092d}",
  )
  const label = createComputed([primary, wifi], (p, w) =>
    p === Network.Primary.WIRED ? "eth" : w?.ssid ? meter((w.strength ?? 0) / 100) : "down",
  )
  const cls = createComputed([primary, wifi], (p, w) => [
    "item", "net",
    ...(p === Network.Primary.WIRED || w?.ssid ? [] : ["dim"]),
  ])

  const sorted = (aps: Network.AccessPoint[]) => {
    const seen = new Set<string>()
    return aps
      .filter((a) => a.ssid && !seen.has(a.ssid) && seen.add(a.ssid))
      .sort((a, b) => b.strength - a.strength)
      .slice(0, 12)
  }

  return (
    <menubutton cssClasses={cls} direction={Gtk.ArrowType.RIGHT}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={icon} />
        <label cssClasses={["sm"]} label={label} />
      </box>
      <popover cssClasses={["pop"]}>
        <With value={wifi}>
          {(w) =>
            w ? (
              <Panel title="WIFI" spacing={2}>
                <box cssClasses={["row", "head"]} spacing={8}>
                  <label label={createBinding(w, "ssid")((s) => s || "not connected")} hexpand xalign={0} />
                  <button cssClasses={["act"]} onClicked={() => w.scan()}><label label="scan" /></button>
                </box>
                <RuleH />
                <For each={createBinding(w, "accessPoints")(sorted)}>
                  {(ap: Network.AccessPoint) => {
                    const active = createBinding(w, "activeAccessPoint")((a) => a?.ssid === ap.ssid)
                    return (
                      <button
                        cssClasses={active((a) => ["row", ...(a ? ["chip"] : [])])}
                        onClicked={() =>
                          execAsync(["nmcli", "device", "wifi", "connect", ap.ssid!]).catch(console.error)
                        }
                      >
                        <box spacing={8}>
                          <label label={meter(ap.strength / 100)} />
                          <label label={ap.ssid!} hexpand xalign={0} />
                          <label cssClasses={["dim"]} label={ap.frequency > 5000 ? "5G" : "2.4"} />
                        </box>
                      </button>
                    )
                  }}
                </For>
              </Panel>
            ) : (
              <Panel title="NET"><label label="no wifi device" /></Panel>
            )
          }
        </With>
      </popover>
    </menubutton>
  )
}

function Bt() {
  const bt = Bluetooth.get_default()
  const powered = createBinding(bt, "isPowered")
  const connected = createBinding(bt, "isConnected")
  const devices = createBinding(bt, "devices")((ds) =>
    ds.filter((d) => d.paired || d.connected).sort((a, b) => Number(b.connected) - Number(a.connected)),
  )
  const cls = createComputed([powered, connected], (p, c) => ["item", "bt", ...(c ? ["live"] : p ? [] : ["dim"])])
  const label = createComputed([powered, connected], (p, c) => (c ? "on" : p ? "idle" : "off"))

  return (
    <menubutton cssClasses={cls} direction={Gtk.ArrowType.RIGHT}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={"\u{f00af}"} />
        <label cssClasses={["sm"]} label={label} />
      </box>
      <popover cssClasses={["pop"]}>
        <Panel title="BLUETOOTH" spacing={2}>
          <box cssClasses={["row", "head"]} spacing={8}>
            <label label={powered((p) => (p ? "powered" : "off"))} hexpand xalign={0} />
            <button cssClasses={["act"]} onClicked={() => bt.toggle()}>
              <label label={powered((p) => (p ? "off" : "on"))} />
            </button>
          </box>
          <RuleH />
          <For each={devices}>
            {(d: Bluetooth.Device) => (
              <button
                cssClasses={createBinding(d, "connected")((c) => ["row", ...(c ? ["chip"] : [])])}
                onClicked={() =>
                  (d.connected ? d.disconnect_device() : d.connect_device()).catch(console.error)
                }
              >
                <box spacing={8}>
                  <label label={createBinding(d, "alias")} hexpand xalign={0} />
                  <label
                    cssClasses={["dim"]}
                    label={createBinding(d, "batteryPercentage")((b) => (b > 0 ? `${Math.round(b * 100)}%` : ""))}
                  />
                </box>
              </button>
            )}
          </For>
        </Panel>
      </popover>
    </menubutton>
  )
}

/** Volume as a rail item: icon over percent, the audio switcher off it. */
function Vol() {
  const wp = Wp.get_default()
  const speaker = wp?.defaultSpeaker
  if (!speaker) return <box />
  const vol = createBinding(speaker, "volume")
  const mute = createBinding(speaker, "mute")
  const icon = createComputed([vol, mute], (v, m) => (m ? "\u{f075f}" : v > 0.66 ? "\u{f057e}" : v > 0.33 ? "\u{f0580}" : "\u{f057f}"))
  const cls = mute((m) => ["item", "vol", ...(m ? ["dim"] : [])])
  return (
    <menubutton cssClasses={cls} direction={Gtk.ArrowType.RIGHT}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={icon} />
        <label cssClasses={["sm"]} label={createComputed([vol, mute], (v, m) => (m ? "mute" : pct(v)))} />
      </box>
      <popover cssClasses={["pop"]}><Audio /></popover>
    </menubutton>
  )
}

function Sni() {
  const tray = Tray.get_default()
  const items = createBinding(tray, "items")
  const init = (btn: Gtk.MenuButton, item: Tray.TrayItem) => {
    btn.menuModel = item.menuModel
    btn.insert_action_group("dbusmenu", item.actionGroup)
    item.connect("notify::action-group", () => btn.insert_action_group("dbusmenu", item.actionGroup))
  }
  return (
    <box cssClasses={["sni"]} orientation={Gtk.Orientation.VERTICAL} halign={Gtk.Align.CENTER}>
      <For each={items}>
        {(item) => (
          <menubutton cssClasses={["sni-item"]} $={(self) => init(self, item)} tooltipText={createBinding(item, "tooltipMarkup")}>
            <image gicon={createBinding(item, "gicon")} pixelSize={18} />
          </menubutton>
        )}
      </For>
    </box>
  )
}

export default function TrayPane() {
  return (
    <box cssClasses={["sys"]} orientation={Gtk.Orientation.VERTICAL} spacing={4}>
      <Sni />
      <Net />
      <Bt />
      <Vol />
    </box>
  )
}
