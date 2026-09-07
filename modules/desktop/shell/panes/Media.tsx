// MEDIA: the selected player large with transport; other players as rows below (j/k, click).
import Gtk from "gi://Gtk?version=4.0"
import Mpris from "gi://AstalMpris"
import { For, createBinding, createComputed } from "ags"
import { meter } from "../lib/format"
import { createState } from "ags"
import Gdk from "gi://Gdk?version=4.0"
import GdkPixbuf from "gi://GdkPixbuf?version=2.0"
import GLib from "gi://GLib?version=2.0"
import { execAsync } from "ags/process"
import { interval, type Timer } from "ags/time"
import { hypr } from "../lib/hypr"
import { mediaShown } from "../surfaces/Deck"
const [curSel, setCurSel] = createState(0)

const players = createBinding(Mpris.get_default(), "players")

/**
 * The picture of what plays: a live capture of the player's window while the media popover is
 * up (the window is found through the player's D-Bus pid — a film in Floorp, mpv), else the
 * track's cover art, else nothing. grim every 2 s, scaled to the pane on load.
 */
const ART_H = 150
function Art({ p }: { p: Mpris.Player }) {
  const [tex, setTex] = createState<Gdk.Texture | null>(null)
  let pid = 0
  let live: Timer | null = null
  const cover = () => {
    const f = p.coverArt
    if (!f) return setTex(null)
    try { setTex(Gdk.Texture.new_for_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(f, -1, ART_H, true))) } catch { setTex(null) }
  }
  const findPid = async () => {
    if (pid || !p.busName) return
    try {
      const out = await execAsync(["busctl", "--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", p.busName])
      pid = Number(out.trim().split(/\s+/).pop() ?? 0)
    } catch (e) { console.error("media pid:", String(e)); pid = -1 }
  }
  const shot = async () => {
    await findPid()
    const c = pid > 0 ? hypr.get_clients().find((x) => x.pid === pid && x.mapped) : null
    const m = c && hypr.get_monitors().find((mm) => mm.activeWorkspace?.id === c.workspace?.id)
    if (!c || !m) return cover()
    // clipped to the monitor: a scrolling layout leaves columns partly off screen
    const x0 = Math.max(c.x, m.x), y0 = Math.max(c.y, m.y), x1 = Math.min(c.x + c.width, m.x + m.width), y1 = Math.min(c.y + c.height, m.y + m.height)
    if (x1 - x0 < 40 || y1 - y0 < 40) return cover()
    const f = `${GLib.get_user_cache_dir()}/astal-shell/media-${pid}.jpg`
    try {
      await execAsync(["grim", "-t", "jpeg", "-q", "60", "-g", `${x0},${y0} ${x1 - x0}x${y1 - y0}`, f])
      setTex(Gdk.Texture.new_for_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(f, -1, ART_H, true)))
    } catch (e) { console.error("media art:", String(e)); cover() }
  }
  p.connect("notify::cover-art", () => { if (!live) cover() })
  cover()
  // live only while the media popover shows it
  mediaShown.subscribe(() => {
    if (mediaShown.peek()) { shot(); live ??= interval(2000, shot) }
    else { live?.cancel(); live = null }
  })
  return (
    <box cssClasses={["art"]} heightRequest={ART_H} widthRequest={tex((t) => (t ? t.get_width() : 0))} visible={tex((t) => !!t)}>
      <Gtk.Picture paintable={tex} canShrink={false} contentFit={Gtk.ContentFit.CONTAIN} halign={Gtk.Align.CENTER} valign={Gtk.Align.CENTER} />
    </box>
  )
}

function Player({ p }: { p: Mpris.Player }) {
  const playing = createBinding(p, "playbackStatus")((s) => s === Mpris.PlaybackStatus.PLAYING)
  const t = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`
  const pos = createComputed([createBinding(p, "position"), createBinding(p, "length")], (a, b) => (b > 0 ? meter(a / b, 26) : ""))
  const time = createComputed([createBinding(p, "position"), createBinding(p, "length")], (a, b) => (b > 0 ? `${t(a)} / ${t(b)}` : ""))
  return (
    <box spacing={12}>
    <Art p={p} />
    <box orientation={Gtk.Orientation.VERTICAL} spacing={4} hexpand>
      <label cssClasses={["big"]} label={createBinding(p, "title")((t) => t || "—")} xalign={0} ellipsize={3} maxWidthChars={34} />
      <label cssClasses={["dim"]} label={createComputed([createBinding(p, "artist"), createBinding(p, "album")], (a, b) => [a, b].filter(Boolean).join(" · ") || p.identity)} xalign={0} ellipsize={3} maxWidthChars={40} />
      <box spacing={10}>
        <button cssClasses={["act"]} onClicked={() => p.previous()} visible={createBinding(p, "canGoPrevious")}><label label="⏮" /></button>
        <button cssClasses={["act", "play"]} onClicked={() => p.play_pause()}><label label={playing((x) => (x ? "⏸" : "▶"))} /></button>
        <button cssClasses={["act"]} onClicked={() => p.next()} visible={createBinding(p, "canGoNext")}><label label="⏭" /></button>
        <label cssClasses={["spark"]} label={pos} hexpand xalign={0} />
        <label cssClasses={["dim", "sm"]} label={time} />
      </box>
    </box>
    </box>
  )
}

export function MediaCard() {
  const cur = curSel
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      <For each={players}>{(p, i) => <box visible={createComputed([cur, i], (c, idx) => c === idx)}><Player p={p} /></box>}</For>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={2} visible={players((ps) => ps.length > 1)}>
        <For each={players}>
          {(p, i) => (
            <button cssClasses={createComputed([cur, i], (c, idx) => ["row", ...(c === idx ? ["chip"] : [])])} onClicked={() => setCurSel(i.get())}>
              <box spacing={8}>
                <label label={createBinding(p, "playbackStatus")((s) => (s === Mpris.PlaybackStatus.PLAYING ? "▶" : "⏸"))} />
                <label label={createBinding(p, "identity")} hexpand xalign={0} />
              </box>
            </button>
          )}
        </For>
      </box>
      <label cssClasses={["dim"]} label="nothing playing" visible={players((ps) => ps.length === 0)} xalign={0} />
    </box>
  )
}
