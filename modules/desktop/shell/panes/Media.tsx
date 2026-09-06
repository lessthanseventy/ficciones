// MEDIA: the selected player large with transport; other players as rows below (j/k, click).
import Gtk from "gi://Gtk?version=4.0"
import Mpris from "gi://AstalMpris"
import { For, createBinding, createComputed } from "ags"
import { meter } from "../lib/format"
import { createState } from "ags"
const [curSel, setCurSel] = createState(0)

const players = createBinding(Mpris.get_default(), "players")

function Player({ p }: { p: Mpris.Player }) {
  const playing = createBinding(p, "playbackStatus")((s) => s === Mpris.PlaybackStatus.PLAYING)
  const t = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`
  const pos = createComputed([createBinding(p, "position"), createBinding(p, "length")], (a, b) => (b > 0 ? meter(a / b, 26) : ""))
  const time = createComputed([createBinding(p, "position"), createBinding(p, "length")], (a, b) => (b > 0 ? `${t(a)} / ${t(b)}` : ""))
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={4}>
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
