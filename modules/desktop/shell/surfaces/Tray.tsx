import Gdk from "gi://Gdk?version=4.0"
import GdkPixbuf from "gi://GdkPixbuf?version=2.0"
import GLib from "gi://GLib?version=2.0"
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
import { For, With, createBinding, createComputed, createState, type Accessor } from "ags"
import { execAsync } from "ags/process"
import { meter, pct } from "../lib/format"
import { Panel, RuleH } from "../lib/tui"
import { hoverPopover, cards, type HoverPop } from "../lib/hover"
import { volumeGlyph, iconFor } from "../lib/icons"
import { volumeWheel } from "../lib/sound"
import { hypr, focusedWorkspace } from "../lib/hypr"
import Pango from "gi://Pango?version=1.0"
import { vpn, mullvad, mullvadToggle, wgConfigs, wgToggle } from "../lib/vpn"
import { createPoll, timeout } from "ags/time"
import { toggleLauncher } from "./Launcher"
import { screenshot, annotate, startRecording, stopRecording, recording, lastRegion, type Target } from "../lib/capture"

function Net() {
  const net = Network.get_default()
  const wifi = createBinding(net, "wifi")
  const primary = createBinding(net, "primary")

  const icon = createComputed(() => { const p = primary(), w = wifi(); return p === Network.Primary.WIRED ? "\u{f0200}" : w?.ssid ? "\u{f05a9}" : "\u{f092d}" })
  const label = createComputed(() => { const p = primary(), w = wifi(); return p === Network.Primary.WIRED ? "eth" : w?.ssid ? meter((w.strength ?? 0) / 100) : "down" })
  const cls = createComputed(() => { const p = primary(), w = wifi(); return [
    "item", "net",
    ...(p === Network.Primary.WIRED || w?.ssid ? [] : ["dim"]),
  ] })

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
  const discovering = createBinding(bt, "adapter")((a) => !!a?.discovering)
  const all = createBinding(bt, "devices")
  const known = all((ds) => ds.filter((d) => d.paired || d.connected).sort((a, b) => Number(b.connected) - Number(a.connected)))
  const found = all((ds) => ds.filter((d) => !d.paired && !d.connected && (d.alias || d.name)).slice(0, 10))
  const cls = createComputed(() => { const p = powered(), c = connected(); return ["item", "bt", ...(c ? ["live"] : p ? [] : ["dim"])] })
  const label = createComputed(() => { const p = powered(), c = connected(); return (c ? "on" : p ? "idle" : "off") })
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
  const icon = createComputed(() => { const v = vol(), m = mute(); return volumeGlyph(v, m) })
  const cls = mute((m) => ["item", "vol", ...(m ? ["dim"] : [])])
  return (
    <menubutton cssClasses={cls} direction={Gtk.ArrowType.RIGHT} tooltipText={createComputed(() => { const v = vol(), m = mute(); return (m ? "muted" : pct(v)) })} $={(self) => { hoverPopover(self, "rail"); self.add_controller(volumeWheel()) }}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={icon} />
        {/* a five-block meter like the wifi item's; the percentage is the tooltip and the OSD */}
        <label cssClasses={["sm"]} label={createComputed(() => { const v = vol(), m = mute(); return (m ? "mute" : meter(v, 5)) })} />
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
    <menubutton cssClasses={items((l) => ["item", "sni", ...(l.length ? ["live"] : [])])} direction={Gtk.ArrowType.RIGHT} hexpand tooltipText={items((l) => (l.length ? `${l.length} in the tray` : "tray: empty"))} $={(self) => hoverPopover(self, "rail")}>
      {/* no count: the glyph is dim with nothing in the tray, amber with something (Andrew, 2026-09-07) */}
      <label cssClasses={["icon"]} label={"\u{f00a}"} halign={Gtk.Align.CENTER} xalign={0.5} />
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
 * The clipboard: the last few clips cliphist holds — an image clip is a thumbnail (decoded once
 * into the cache), a text clip its first line with its length — click one to copy it back to
 * the top, with a line to the full picker (the launcher in clip mode). The bar cell names the
 * newest clip's kind: cliphist's count sits at its cap and says nothing (Andrew, 2026-09-08).
 */
type Clip = { id: string; kind: "text" | "image"; text: string; meta: string; file?: string }
const CLIP_DIR = `${GLib.get_user_cache_dir()}/astal-shell/clips`
const parseClip = (line: string): Clip | null => {
  const [id, ...rest] = line.split("\t")
  if (!id) return null
  const raw = rest.join("\t")
  const img = raw.match(/^\[\[ binary data (\S+ \S+) (\w+) (\d+x\d+) \]\]$/)
  if (img) return { id, kind: "image", text: img[2], meta: `${img[3]} · ${img[1]}`, file: `${CLIP_DIR}/${id}.${img[2]}` }
  const text = raw.replace(/\s+/g, " ").trim()
  return { id, kind: "text", text, meta: `${raw.length}c` }
}
const [recentClips, setRecentClips] = createState<Clip[]>([])
const THUMB_H = 48
// scaled at load: a Gtk.Picture grows to the row's width otherwise (GTK4 CSS has no max-height)
const thumb = (file: string): Gdk.Texture | null => {
  try { return Gdk.Texture.new_for_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(file, 160, THUMB_H, true)) } catch { return null }
}
const newestKind = createPoll("—", 15_000, async () => {
  try { const c = parseClip((await execAsync(["sh", "-c", "cliphist list | head -n 1"])).trim()); return c ? (c.kind === "image" ? "img" : "txt") : "—" } catch { return "—" }
})
async function refreshClips() {
  try {
    const out = await execAsync(["sh", "-c", "cliphist list | head -n 6"])
    const clips = out.split("\n").filter(Boolean).map(parseClip).filter((c): c is Clip => !!c)
    GLib.mkdir_with_parents(CLIP_DIR, 0o755)
    // decode each image once; the id is stable for the clip's life
    await Promise.all(clips.filter((c) => c.file && !GLib.file_test(c.file, GLib.FileTest.EXISTS))
      .map((c) => execAsync(["sh", "-c", `cliphist list | grep -m1 '^${c.id}\t' | cliphist decode > "$1"`, "_", c.file!]).catch(() => {})))
    setRecentClips(clips)
  } catch { setRecentClips([]) }
}
const copyClip = (c: Clip) => execAsync(["sh", "-c", `cliphist list | grep -m1 '^${c.id}\t' | cliphist decode | wl-copy`]).then(refreshClips).catch(console.error)
function ClipItem() {
  let pop: HoverPop | null = null
  return (
    <menubutton cssClasses={["item", "clip"]} direction={Gtk.ArrowType.RIGHT} $={(self) => { pop = hoverPopover(self, "rail", undefined, { onShow: refreshClips }); cards.set("clipboard", pop) }}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={"\u{f0ea}"} />
        <label cssClasses={["sm"]} label={newestKind} />
      </box>
      <popover cssClasses={["pop", "pop-clip"]}>
        <Panel title={"\u{f0ea}  CLIPBOARD"} cssClasses={["card", "card-clip"]}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
            {/* the list in its own box: For appends as clips arrive, and the history button must stay last */}
            <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
            <For each={recentClips} id={(c) => c.id}>
              {(c, i) => (
                <button cssClasses={i((n) => ["row", "clip-row", ...(n === 0 ? ["top"] : [])])} onClicked={() => { copyClip(c); pop?.close() }} tooltipText={c.kind === "text" ? c.text.slice(0, 400) : c.meta}>
                  <box spacing={8}>
                    <label cssClasses={["clip-kind", c.kind === "image" ? "green" : "amber"]} label={c.kind === "image" ? "\u{f02e9}" : "\u{f09a8}"} widthChars={2} />
                    {c.kind === "image"
                      ? <box hexpand spacing={0}><Gtk.Picture cssClasses={["clip-thumb"]} paintable={thumb(c.file!)} halign={Gtk.Align.START} valign={Gtk.Align.CENTER} canShrink={false} /><box hexpand /></box>
                      : <label label={c.text} xalign={0} hexpand ellipsize={3} maxWidthChars={40} />}
                    <label cssClasses={["dim", "sm", "clip-meta"]} label={c.meta} xalign={1} />
                  </box>
                </button>
              )}
            </For>
            </box>
            <label cssClasses={["dim"]} label="empty" visible={recentClips((l) => l.length === 0)} xalign={0} />
            <button cssClasses={["act"]} onClicked={() => { pop?.close(); toggleLauncher("clip") }}><label label={"\u{f0349}  history …"} /></button>
          </box>
        </Panel>
      </popover>
    </menubutton>
  )
}

/** Screenshots and recordings: the card closes first, so slurp's overlay is not under it. */
function CaptureItem() {
  let pop: HoverPop | null = null
  // the card fades out as a layer (hyprland.lua's layersOut: 150 ms, linear) after GTK unmaps it: a
  // shot taken inside that took the half-faded card into the picture, so it waits the fade out and more
  const go = (fn: () => void) => { pop?.close(); timeout(400, fn) }
  const Row = ({ glyph, label, on }: { glyph: string; label: string; on: () => void }) => (
    <button cssClasses={["row", "cap-row"]} onClicked={() => go(on)}>
      <box spacing={8}><label cssClasses={["cap-glyph"]} label={glyph} widthChars={2} /><label label={label} xalign={0} hexpand /></box>
    </button>
  )
  const Head = ({ label }: { label: string }) => <label cssClasses={["cap-head"]} label={label} xalign={0} />
  // help lines sit with their section (Andrew, 2026-09-08): a key column, then the value
  const Help = ({ rows }: { rows: string[][] }) => (
    <box orientation={Gtk.Orientation.VERTICAL} cssClasses={["cap-help"]}>
      {rows.map(([k, v]) => (
        <box spacing={8}><label cssClasses={["dim", "sm"]} label={k} widthChars={9} xalign={0} /><label cssClasses={["sm"]} label={v} xalign={0} hexpand /></box>
      ))}
    </box>
  )
  // a shot row: the target, then where it goes — disk or clipboard (Andrew, 2026-09-07)
  const Shot = ({ glyph, label, what, visible }: { glyph: string; label: string; what: Target; visible?: Accessor<boolean> }) => (
    <box cssClasses={["cap-row", "cap-shot"]} spacing={8} visible={visible ?? true}>
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
  // windows"); a background window is shot on its own workspace — grim's -g is in
  // screen coordinates, so the workspace is switched to first (capture.ts)
  // the focused window first (Andrew, 2026-09-08: the "window" row went; pick it from the list)
  const hyprClients = createBinding(hypr, "clients"), hyprFocused = createBinding(hypr, "focusedClient")
  const wins = createComputed(() => {
    const ws = focusedWorkspace(), cs = hyprClients(), fc = hyprFocused()
    return cs.filter((c) => c.mapped && (c.workspace?.id ?? 0) > 0)
      .sort((a, b) => ((a === fc ? 0 : 1) - (b === fc ? 0 : 1)) || ((a.workspace?.id === ws?.id ? 0 : 1) - (b.workspace?.id === ws?.id ? 0 : 1)) || (a.workspace?.id ?? 0) - (b.workspace?.id ?? 0) || a.x - b.x)
  })
  const Windows = () => (
    <box orientation={Gtk.Orientation.VERTICAL}>
      <button cssClasses={["row", "cap-row"]} onClicked={() => setListOpen(!listOpen.peek())}>
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
    <menubutton cssClasses={recording((r) => ["item", "cap", ...(r ? ["live"] : [])])} direction={Gtk.ArrowType.RIGHT} $={(self) => { pop = hoverPopover(self, "rail"); cards.set("capture", pop) }}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["icon"]} label={recording((r) => (r ? "\u{f03d}" : "\u{f030}"))} />
        <label cssClasses={["sm"]} label={recording((r) => (r ? "rec" : "shot"))} />
      </box>
      <popover cssClasses={["pop", "pop-capture"]} onClosed={() => setListOpen(false)}>
        <Panel title={"\u{f030}  CAPTURE"} cssClasses={["card", "card-capture"]}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
            <Head label="SCREENSHOT" />
            <Shot glyph={"\u{f065}"} label="region" what="region" />
            <Shot glyph={"\u{f0e2}"} label="last region" what="last" visible={lastRegion((r) => r !== null)} />
            <Row glyph={"\u{f040}"} label="annotate region (arrows, boxes, text)" on={() => annotate("region")} />
            <Shot glyph={"\u{f108}"} label="monitor" what="monitor" />
            <Windows />
            <Help rows={[["saved to", "~/Pictures/Screenshots"], ["region", "slurp picks it"]]} />
            <RuleH />
            <Head label="RECORD" />
            <box orientation={Gtk.Orientation.VERTICAL} spacing={2} visible={recording((r) => !r)}>
              <Row glyph={"\u{f03d}"} label="record region" on={() => startRecording("region")} />
              <Row glyph={"\u{f03d}"} label="record monitor" on={() => startRecording("monitor")} />
            </box>
            <button cssClasses={["row", "cap-row", "stop"]} visible={recording((r) => !!r)} onClicked={() => { stopRecording(); pop?.close() }}>
              <box spacing={8}><label cssClasses={["cap-glyph", "red"]} label="■" widthChars={2} /><label label={recording((r) => `stop recording (${r ?? ""})`)} xalign={0} hexpand /></box>
            </button>
            <Help rows={[["saved to", "~/Videos/Recordings"]]} />
            <RuleH />
            <Help rows={[["flameshot", "Super+Shift+S · its own selector + editor"]]} />
          </box>
        </Panel>
      </popover>
    </menubutton>
  )
}

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
      <CaptureItem />
      <ClipItem />
      <Net />
      <VpnItem />
      <Bt />
      <Vol />
      {/* the foot: the tray in a square that mirrors the corner at the top (Andrew, 2026-09-07) */}
      <box cssClasses={["foot"]} halign={Gtk.Align.FILL}><Sni /></box>
    </box>
  )
}
