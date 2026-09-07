// The rail's foot: network and bluetooth as text items with detail popovers, then the
// StatusNotifier tray (Steam, Slack, wgtray…) as an icon grid. Popovers are the "detail on
// demand" surface — click opens, Escape or click-away closes.
import Gtk from "gi://Gtk?version=4.0"
import Network from "gi://AstalNetwork"
import Bluetooth from "gi://AstalBluetooth"
import Gio from "gi://Gio?version=2.0"
import Tray from "gi://AstalTray"
import Wp from "gi://AstalWp"
import Audio from "./Audio"
import { For, With, createBinding, createComputed, createState } from "ags"
import { execAsync } from "ags/process"
import { meter, pct } from "../lib/format"
import { Panel, RuleH } from "../lib/tui"
import { hoverPopover, type HoverPop } from "../lib/hover"
import { volumeGlyph, iconFor } from "../lib/icons"
import { hypr, focusedWorkspace } from "../lib/hypr"
import Pango from "gi://Pango?version=1.0"
import { vpn, mullvad, mullvadToggle, wgConfigs, wgToggle } from "../lib/vpn"
import { createPoll, timeout } from "ags/time"
import { toggleLauncher } from "./Launcher"
import { screenshot, startRecording, stopRecording, recording } from "../lib/capture"

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
    <menubutton cssClasses={cls} direction={Gtk.ArrowType.RIGHT} $={(self) => hoverPopover(self, "rail")}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={icon} />
        <label cssClasses={["sm"]} label={label} />
      </box>
      <popover cssClasses={["pop", "pop-net"]}>
        <With value={wifi}>
          {(w) =>
            w ? (
              <Panel title={"\u{f05a9}  WIFI"} cssClasses={["card", "card-net"]} spacing={2}>
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
                          {/* signal in tiers (green strong / amber fair / red weak), the band as a cyan tag */}
                          <label cssClasses={["sig", ap.strength >= 60 ? "strong" : ap.strength >= 35 ? "fair" : "weak"]} label={meter(ap.strength / 100)} />
                          <label label={ap.ssid!} hexpand xalign={0} />
                          <label cssClasses={["k", "sm"]} label={ap.frequency > 5000 ? "5G" : "2.4"} />
                          <label cssClasses={["k", "sm"]} label={ap.flags || ap.wpaFlags || ap.rsnFlags ? "\u{f033e}" : "\u{f0fc6}"} />
                        </box>
                      </button>
                    )
                  }}
                </For>
              </Panel>
            ) : (
              <Panel title={"\u{f05a9}  NET"} cssClasses={["card", "card-net"]}><label label="no wifi device" /></Panel>
            )
          }
        </With>
      </popover>
    </menubutton>
  )
}

// Vala async methods reach GJS as callback-style; promisify once so they can be awaited.
Gio._promisify(Bluetooth.Device.prototype, "connect_device", "connect_device_finish")
Gio._promisify(Bluetooth.Device.prototype, "disconnect_device", "disconnect_device_finish")

function Bt() {
  const bt = Bluetooth.get_default()
  const powered = createBinding(bt, "isPowered")
  const connected = createBinding(bt, "isConnected")
  const adapter = createBinding(bt, "adapter")
  const discovering = createBinding(bt, "adapter")((a) => !!a?.discovering)
  const all = createBinding(bt, "devices")
  const known = all((ds) => ds.filter((d) => d.paired || d.connected).sort((a, b) => Number(b.connected) - Number(a.connected)))
  const found = all((ds) => ds.filter((d) => !d.paired && !d.connected && (d.alias || d.name)).slice(0, 10))
  const cls = createComputed([powered, connected], (p, c) => ["item", "bt", ...(c ? ["live"] : p ? [] : ["dim"])])
  const label = createComputed([powered, connected], (p, c) => (c ? "on" : p ? "idle" : "off"))
  const act = async (d: Bluetooth.Device) => {
    try {
      if (d.connected) await (d as any).disconnect_device()
      else await (d as any).connect_device()
    } catch (e) { console.error("bluetooth:", String(e)) }
  }
  const scan = () => {
    const a = bt.adapter
    if (!a) return
    try { a.discovering ? a.stop_discovery() : a.start_discovery() } catch (e) { console.error("bluetooth:", String(e)) }
  }
  const pair = (d: Bluetooth.Device) => {
    try { d.pair(); d.trusted = true } catch (e) { console.error("bluetooth:", String(e)) }
  }

  return (
    <menubutton cssClasses={cls} direction={Gtk.ArrowType.RIGHT} $={(self) => hoverPopover(self, "rail")}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={"\u{f00af}"} />
        <label cssClasses={["sm"]} label={label} />
      </box>
      <popover cssClasses={["pop", "pop-bt"]}>
        <Panel title={"\u{f00af}  BLUETOOTH"} cssClasses={["card", "card-bt"]} spacing={2}>
          <box cssClasses={["row", "head"]} spacing={8}>
            <label label={powered((p) => (p ? "powered" : "off"))} hexpand xalign={0} />
            <button cssClasses={discovering((d) => ["act", ...(d ? ["green"] : [])])} onClicked={scan} visible={powered}>
              <label label={discovering((d) => (d ? "scanning…" : "scan"))} />
            </button>
            <button cssClasses={["act"]} onClicked={() => bt.toggle()}>
              <label label={powered((p) => (p ? "off" : "on"))} />
            </button>
          </box>
          <RuleH />
          <For each={known}>
            {(d: Bluetooth.Device) => (
              <button cssClasses={createBinding(d, "connected")((c) => ["row", ...(c ? ["chip"] : [])])} onClicked={() => act(d)}>
                <box spacing={8}>
                  <label label={createBinding(d, "alias")} hexpand xalign={0} />
                  <label cssClasses={["pink", "sm"]} label={createBinding(d, "connecting")((c) => (c ? "connecting…" : ""))} />
                  <label cssClasses={createBinding(d, "batteryPercentage")((b) => ["sm", b <= 0 ? "dim" : b < 0.2 ? "red" : b < 0.5 ? "amber" : "green"])} label={createBinding(d, "batteryPercentage")((b) => (b > 0 ? `\u{f0079} ${Math.round(b * 100)}%` : ""))} />
                </box>
              </button>
            )}
          </For>
          <label cssClasses={["dim", "sm"]} label="no paired devices" visible={known((k) => k.length === 0)} xalign={0} />
          <box orientation={Gtk.Orientation.VERTICAL} spacing={2} visible={found((f) => f.length > 0)}>
            <RuleH />
            <label cssClasses={["k", "sm"]} label="nearby · click to pair" xalign={0} />
            <For each={found}>
              {(d: Bluetooth.Device) => (
                <button cssClasses={["row"]} onClicked={() => pair(d)}>
                  <box spacing={8}>
                    <label label={createBinding(d, "alias")((a) => a || d.name || d.address)} hexpand xalign={0} />
                    <label cssClasses={createBinding(d, "rssi")((r) => ["sm", !r ? "dim" : r > -60 ? "green" : r > -75 ? "amber" : "red"])} label={createBinding(d, "rssi")((r) => (r ? `${r} dBm` : ""))} />
                  </box>
                </button>
              )}
            </For>
          </box>
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
  const icon = createComputed([vol, mute], (v, m) => volumeGlyph(v, m))
  const cls = mute((m) => ["item", "vol", ...(m ? ["dim"] : [])])
  // wheel over the icon: 2 % a notch, capped at 100 % (the keys go to 150 %; the wheel is for
  // nudging). The OSD shows it — the popover is closed while you scroll.
  const scroll = new Gtk.EventControllerScroll({ flags: Gtk.EventControllerScrollFlags.VERTICAL })
  scroll.connect("scroll", (_, __, dy) => {
    speaker.set_volume(Math.max(0, Math.min(1, speaker.volume + (dy > 0 ? -0.02 : 0.02))))
    return true
  })
  return (
    <menubutton cssClasses={cls} direction={Gtk.ArrowType.RIGHT} tooltipText={createComputed([vol, mute], (v, m) => (m ? "muted" : pct(v)))} $={(self) => { hoverPopover(self, "rail"); self.add_controller(scroll) }}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={icon} />
        {/* a five-block meter like the wifi item's; the percentage is the tooltip and the OSD */}
        <label cssClasses={["sm"]} label={createComputed([vol, mute], (v, m) => (m ? "mute" : meter(v, 5)))} />
      </box>
      <popover cssClasses={["pop", "pop-audio"]}><Audio /></popover>
    </menubutton>
  )
}

/**
 * The system tray as one rail item (icon + how many), its card a row per app: the app's icon
 * and title, a click activates it (what a left click on the tray icon did), ≡ opens the app's
 * own menu. Absent when nothing sits in the tray.
 */
/** "discord_status_icon_1" → "discord": the SNI id is what some apps hand over as a title */
const pretty = (t: string) => t.replace(/[_-]?status[_-]?icon[_-]?\d*$/i, "").replace(/[_-]\d+$/, "").replace(/[_-]+/g, " ").trim() || t
function Sni() {
  const tray = Tray.get_default()
  const items = createBinding(tray, "items")
  const menu = (btn: Gtk.MenuButton, item: Tray.TrayItem) => {
    btn.menuModel = item.menuModel
    btn.insert_action_group("dbusmenu", item.actionGroup)
    item.connect("notify::action-group", () => btn.insert_action_group("dbusmenu", item.actionGroup))
  }
  return (
    <menubutton cssClasses={["item", "sni"]} direction={Gtk.ArrowType.RIGHT} visible={items((l) => l.length > 0)} $={(self) => hoverPopover(self, "rail")}>
      <box orientation={Gtk.Orientation.VERTICAL} halign={Gtk.Align.CENTER}>
        <label cssClasses={["icon"]} label={"\u{f00a}"} halign={Gtk.Align.CENTER} xalign={0.5} />
        <label cssClasses={["sm"]} label={items((l) => String(l.length))} halign={Gtk.Align.CENTER} xalign={0.5} />
      </box>
      <popover cssClasses={["pop", "pop-tray"]}>
        <Panel title={"\u{f00a}  TRAY"} cssClasses={["card", "card-tray"]}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
            <For each={items} id={(it) => it.itemId}>
              {(item) => (
                <box cssClasses={["row", "tray-row"]} spacing={8}>
                  <button cssClasses={["tray-hit"]} hexpand onClicked={() => item.activate(0, 0)} tooltipText={createBinding(item, "tooltipMarkup")}>
                    <box spacing={8}>
                      <image gicon={createBinding(item, "gicon")} pixelSize={18} />
                      <label label={createBinding(item, "title")((t) => pretty(t || item.id))} xalign={0} hexpand ellipsize={3} maxWidthChars={28} />
                    </box>
                  </button>
                  <menubutton cssClasses={["act", "tray-menu"]} $={(self) => menu(self, item)} tooltipText="menu"><label label="≡" /></menubutton>
                </box>
              )}
            </For>
          </box>
        </Panel>
      </popover>
    </menubutton>
  )
}

/**
 * The clipboard: how many clips cliphist holds; a click pops the last few — click one to copy
 * it back to the top — with a line to the full picker (the launcher in clip mode).
 */
type Clip = { id: string; text: string }
const [recentClips, setRecentClips] = createState<Clip[]>([])
const clipCount = createPoll("0", 15_000, async () => {
  try { return (await execAsync(["sh", "-c", "cliphist list | wc -l"])).trim() } catch { return "0" }
})
async function refreshClips() {
  try {
    const out = await execAsync(["sh", "-c", "cliphist list | head -n 5"])
    setRecentClips(out.split("\n").filter(Boolean).map((l) => { const [id, ...rest] = l.split("\t"); return { id, text: rest.join("\t").replace(/\s+/g, " ").trim() } }))
  } catch { setRecentClips([]) }
}
const copyClip = (c: Clip) => execAsync(["sh", "-c", `cliphist list | grep -m1 '^${c.id}\t' | cliphist decode | wl-copy`]).then(refreshClips).catch(console.error)
function ClipItem() {
  let pop: HoverPop | null = null
  return (
    <menubutton cssClasses={["item", "clip"]} direction={Gtk.ArrowType.RIGHT} $={(self) => { pop = hoverPopover(self, "rail", undefined, { onShow: refreshClips }) }}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={"\u{f0ea}"} />
        <label cssClasses={["sm"]} label={clipCount} />
      </box>
      <popover cssClasses={["pop", "pop-clip"]}>
        <Panel title={"\u{f0ea}  CLIPBOARD"} cssClasses={["card", "card-clip"]}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
            <For each={recentClips} id={(c) => c.id}>
              {(c, i) => (
                <button cssClasses={["row", "clip-row"]} onClicked={() => { copyClip(c); pop?.close() }} tooltipText={c.text.slice(0, 400)}>
                  <box spacing={8}>
                    <label cssClasses={i((n) => (n === 0 ? ["amber"] : ["dim"]))} label={i((n) => (n === 0 ? "\u{f012c}" : " "))} widthChars={2} />
                    <label label={c.text} xalign={0} hexpand ellipsize={3} maxWidthChars={44} />
                  </box>
                </button>
              )}
            </For>
            <label cssClasses={["dim"]} label="empty" visible={recentClips((l) => l.length === 0)} xalign={0} />
            <button cssClasses={["act"]} onClicked={() => { pop?.close(); toggleLauncher("clip") }}><label label={clipCount((n) => `all ${n} …`)} /></button>
          </box>
        </Panel>
      </popover>
    </menubutton>
  )
}

/** Screenshots and recordings: the card closes first, so slurp's overlay is not under it. */
function CaptureItem() {
  let pop: HoverPop | null = null
  const go = (fn: () => void) => { pop?.close(); timeout(180, fn) }
  const Row = ({ glyph, label, on }: { glyph: string; label: string; on: () => void }) => (
    <button cssClasses={["row", "cap-row"]} onClicked={() => go(on)}>
      <box spacing={8}><label cssClasses={["cap-glyph"]} label={glyph} widthChars={2} /><label label={label} xalign={0} hexpand /></box>
    </button>
  )
  // a shot row: the target, then where it goes — disk or clipboard (Andrew, 2026-09-07)
  const Shot = ({ glyph, label, what }: { glyph: string; label: string; what: "region" | "monitor" | "window" }) => (
    <box cssClasses={["cap-row", "cap-shot"]} spacing={8}>
      <label cssClasses={["cap-glyph"]} label={glyph} widthChars={2} />
      <label label={label} xalign={0} hexpand />
      <button cssClasses={["act"]} tooltipText="save to ~/Pictures/Screenshots" onClicked={() => go(() => screenshot(what, "file"))}><label label={"\u{f0193}  disk"} /></button>
      <button cssClasses={["act"]} tooltipText="copy to the clipboard" onClicked={() => go(() => screenshot(what, "clip"))}><label label={"\u{f018f}  copy"} /></button>
    </box>
  )
  // any window, not just the focused one: a fold-out list of the workspace's windows, each with
  // the two sinks (Andrew, 2026-09-07: "screenshot a window easily")
  const [listOpen, setListOpen] = createState(false)
  // every window on every workspace, this workspace's first (Andrew, 2026-09-07: "like all
  // windows"); a background window is shot on its own workspace — flameshot's --region is in
  // screen coordinates, so the workspace is switched to first (capture.ts)
  const wins = createComputed([focusedWorkspace, createBinding(hypr, "clients")], (ws, cs) =>
    cs.filter((c) => c.mapped && (c.workspace?.id ?? 0) > 0)
      .sort((a, b) => ((a.workspace?.id === ws?.id ? 0 : 1) - (b.workspace?.id === ws?.id ? 0 : 1)) || (a.workspace?.id ?? 0) - (b.workspace?.id ?? 0) || a.x - b.x))
  const Windows = () => (
    <box orientation={Gtk.Orientation.VERTICAL}>
      <button cssClasses={["row", "cap-row"]} onClicked={() => setListOpen(!listOpen.get())}>
        <box spacing={8}><label cssClasses={["cap-glyph"]} label={listOpen((o) => (o ? "\u{f0d7}" : "\u{f0da}"))} widthChars={2} /><label label="a window…" xalign={0} hexpand /></box>
      </button>
      <revealer revealChild={listOpen} transitionType={Gtk.RevealerTransitionType.SLIDE_DOWN}>
        <box orientation={Gtk.Orientation.VERTICAL} cssClasses={["cap-wins"]}>
          <For each={wins}>
            {(c) => (
              <box cssClasses={["cap-row", "cap-shot"]} spacing={8}>
                <label cssClasses={["dim", "sm"]} label={createBinding(c, "workspace")((w) => String(w?.id ?? ""))} widthChars={2} xalign={1} />
                <image iconName={iconFor(c)} pixelSize={16} />
                <label label={createBinding(c, "title")} xalign={0} hexpand ellipsize={Pango.EllipsizeMode.END} maxWidthChars={26} />
                <button cssClasses={["act"]} tooltipText="save to ~/Pictures/Screenshots" onClicked={() => go(() => screenshot("window", "file", c.address))}><label label={"\u{f0193}"} /></button>
                <button cssClasses={["act"]} tooltipText="copy to the clipboard" onClicked={() => go(() => screenshot("window", "clip", c.address))}><label label={"\u{f018f}"} /></button>
              </box>
            )}
          </For>
        </box>
      </revealer>
    </box>
  )
  return (
    <menubutton cssClasses={recording((r) => ["item", "cap", ...(r ? ["live"] : [])])} direction={Gtk.ArrowType.RIGHT} $={(self) => { pop = hoverPopover(self, "rail") }}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={recording((r) => (r ? "\u{f03d}" : "\u{f030}"))} />
        <label cssClasses={["sm"]} label={recording((r) => (r ? "rec" : "shot"))} />
      </box>
      <popover cssClasses={["pop", "pop-capture"]}>
        <Panel title={"\u{f030}  CAPTURE"} cssClasses={["card", "card-capture"]}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
            <Shot glyph={"\u{f065}"} label="region" what="region" />
            <Shot glyph={"\u{f108}"} label="monitor" what="monitor" />
            <Shot glyph={"\u{f2d0}"} label="window" what="window" />
            <Windows />
            <RuleH />
            <box orientation={Gtk.Orientation.VERTICAL} spacing={2} visible={recording((r) => !r)}>
              <Row glyph={"\u{f03d}"} label="record region" on={() => startRecording("region")} />
              <Row glyph={"\u{f03d}"} label="record monitor" on={() => startRecording("monitor")} />
            </box>
            <button cssClasses={["row", "cap-row", "stop"]} visible={recording((r) => !!r)} onClicked={() => { stopRecording(); pop?.close() }}>
              <box spacing={8}><label cssClasses={["cap-glyph", "red"]} label="■" widthChars={2} /><label label={recording((r) => `stop recording (${r ?? ""})`)} xalign={0} hexpand /></box>
            </button>
            <label cssClasses={["dim", "sm"]} label="shots are flameshot's (region/window: its selector) · recordings → ~/Videos/Recordings" xalign={0} wrap maxWidthChars={40} />
          </box>
        </Panel>
      </popover>
    </menubutton>
  )
}

const items = createBinding(Tray.get_default(), "items")
/**
 * VPN: on/off under the glyph, always there; the card is Mullvad (connect/disconnect, the
 * relay, the account's expiry) and a row per wg-quick config, up/down through polkit.
 */
function VpnItem() {
  let pop: HoverPop | null = null
  const cls = vpn((v) => ["item", "vpn", ...(v.length ? ["live"] : ["dim"])])
  const configs = wgConfigs()
  return (
    <menubutton cssClasses={cls} direction={Gtk.ArrowType.RIGHT} tooltipText={vpn((v) => (v.length ? `vpn up: ${v.join(", ")}` : "no tunnel up"))} $={(self) => { pop = hoverPopover(self, "rail") }}>
      <box orientation={Gtk.Orientation.VERTICAL} halign={Gtk.Align.CENTER}>
        <label cssClasses={["icon"]} label={"\u{f0582}"} />
        <label cssClasses={["sm"]} label={vpn((v) => (v.length ? "on" : "off"))} />
      </box>
      <popover cssClasses={["pop", "pop-vpn"]}>
        <Panel title={"\u{f0582}  VPN"} cssClasses={["card", "card-vpn"]} spacing={2}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={2} visible={mullvad((m) => m.present)}>
            <button cssClasses={mullvad((m) => ["row", ...(m.connected ? ["chip"] : [])])} onClicked={() => { mullvadToggle(); pop?.close() }}>
              <box spacing={8}>
                <label cssClasses={mullvad((m) => (m.connected ? ["st-working"] : ["dim"]))} label={mullvad((m) => (m.connected ? "●" : "○"))} />
                <label label="mullvad" widthChars={10} xalign={0} />
                <label cssClasses={["dim", "sm"]} label={mullvad((m) => (m.connected ? m.location || m.state : `off · ${m.relay}`))} hexpand xalign={0} ellipsize={3} maxWidthChars={26} />
                <label cssClasses={["act"]} label={mullvad((m) => (m.connected ? "disconnect" : "connect"))} />
              </box>
            </button>
            <label cssClasses={["dim", "sm"]} label={mullvad((m) => (m.expires ? `account to ${m.expires}` : ""))} xalign={0} />
          </box>
          <RuleH visible={mullvad((m) => m.present && configs.length > 0)} />
          {configs.map((name) => (
            <button cssClasses={vpn((v) => ["row", ...(v.includes(name) ? ["chip"] : [])])} onClicked={() => { wgToggle(name, !vpn.peek().includes(name)); pop?.close() }}>
              <box spacing={8}>
                <label cssClasses={vpn((v) => (v.includes(name) ? ["st-working"] : ["dim"]))} label={vpn((v) => (v.includes(name) ? "●" : "○"))} />
                <label label={name} hexpand xalign={0} />
                <label cssClasses={["dim", "sm"]} label="wg-quick" />
              </box>
            </button>
          ))}
          <label cssClasses={["dim", "sm"]} label="no tunnels configured — mullvad, or a .conf in /etc/wireguard" xalign={0} visible={mullvad((m) => !m.present && configs.length === 0)} />
        </Panel>
      </popover>
    </menubutton>
  )
}

export default function TrayPane() {
  return (
    <box cssClasses={["sys"]} orientation={Gtk.Orientation.VERTICAL} spacing={2}>
      <Sni />
      <RuleH visible={items((l) => l.length > 0)} />
      <CaptureItem />
      <ClipItem />
      <Net />
      <VpnItem />
      <Bt />
      <Vol />
    </box>
  )
}
