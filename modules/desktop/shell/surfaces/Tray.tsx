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
      <popover cssClasses={["pop"]}>
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
      <popover cssClasses={["pop"]}>
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
                  <label cssClasses={["dim", "sm"]} label={createBinding(d, "connecting")((c) => (c ? "connecting…" : ""))} />
                  <label cssClasses={["dim"]} label={createBinding(d, "batteryPercentage")((b) => (b > 0 ? `${Math.round(b * 100)}%` : ""))} />
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
                    <label cssClasses={["dim", "sm"]} label={createBinding(d, "rssi")((r) => (r ? `${r} dBm` : ""))} />
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
  const icon = createComputed([vol, mute], (v, m) => (m ? "\u{f075f}" : v > 0.66 ? "\u{f057e}" : v > 0.33 ? "\u{f0580}" : "\u{f057f}"))
  const cls = mute((m) => ["item", "vol", ...(m ? ["dim"] : [])])
  // wheel over the icon: 2 % a notch, capped at 100 % (the keys go to 150 %; the wheel is for
  // nudging). The OSD shows it — the popover is closed while you scroll.
  const scroll = new Gtk.EventControllerScroll({ flags: Gtk.EventControllerScrollFlags.VERTICAL })
  scroll.connect("scroll", (_, __, dy) => {
    speaker.set_volume(Math.max(0, Math.min(1, speaker.volume + (dy > 0 ? -0.02 : 0.02))))
    return true
  })
  return (
    <menubutton cssClasses={cls} direction={Gtk.ArrowType.RIGHT} $={(self) => { hoverPopover(self, "rail"); self.add_controller(scroll) }}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={icon} />
        <label cssClasses={["sm"]} label={createComputed([vol, mute], (v, m) => (m ? "mute" : pct(v)))} />
      </box>
      <popover cssClasses={["pop"]}><Audio /></popover>
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
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={"\u{f00a}"} />
        <label cssClasses={["sm"]} label={items((l) => String(l.length))} />
      </box>
      <popover cssClasses={["pop"]}>
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
      <popover cssClasses={["pop"]}>
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
  return (
    <menubutton cssClasses={recording((r) => ["item", "cap", ...(r ? ["live"] : [])])} direction={Gtk.ArrowType.RIGHT} $={(self) => { pop = hoverPopover(self, "rail") }}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={recording((r) => (r ? "\u{f03d}" : "\u{f030}"))} />
        <label cssClasses={["sm"]} label={recording((r) => (r ? "rec" : "shot"))} />
      </box>
      <popover cssClasses={["pop"]}>
        <Panel title={"\u{f030}  CAPTURE"} cssClasses={["card", "card-capture"]}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
            <Row glyph={"\u{f065}"} label="shot region" on={() => screenshot("region")} />
            <Row glyph={"\u{f108}"} label="shot monitor" on={() => screenshot("monitor")} />
            <Row glyph={"\u{f2d0}"} label="shot window" on={() => screenshot("window")} />
            <Row glyph={"\u{f040}"} label="shot region → edit" on={() => screenshot("region", true)} />
            <RuleH />
            <box orientation={Gtk.Orientation.VERTICAL} spacing={2} visible={recording((r) => !r)}>
              <Row glyph={"\u{f03d}"} label="record region" on={() => startRecording("region")} />
              <Row glyph={"\u{f03d}"} label="record monitor" on={() => startRecording("monitor")} />
            </box>
            <button cssClasses={["row", "cap-row", "stop"]} visible={recording((r) => !!r)} onClicked={() => { stopRecording(); pop?.close() }}>
              <box spacing={8}><label cssClasses={["cap-glyph", "red"]} label="■" widthChars={2} /><label label={recording((r) => `stop recording (${r ?? ""})`)} xalign={0} hexpand /></box>
            </button>
            <label cssClasses={["dim", "sm"]} label="shots → ~/Pictures/Screenshots + clipboard · recordings → ~/Videos/Recordings" xalign={0} wrap maxWidthChars={40} />
          </box>
        </Panel>
      </popover>
    </menubutton>
  )
}

export default function TrayPane() {
  return (
    <box cssClasses={["sys"]} orientation={Gtk.Orientation.VERTICAL} spacing={2}>
      <Sni />
      <CaptureItem />
      <ClipItem />
      <Net />
      <Bt />
      <Vol />
    </box>
  )
}
