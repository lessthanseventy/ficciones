// MEDIA: every MPRIS player, transport, position.
import Gtk from "gi://Gtk?version=4.0"
import Mpris from "gi://AstalMpris"
import { For, createBinding, createComputed } from "ags"
import { Panel } from "../lib/tui"
import { meter } from "../lib/format"

function Player({ p }: { p: Mpris.Player }) {
  const playing = createBinding(p, "playbackStatus")((s) => s === Mpris.PlaybackStatus.PLAYING)
  const pos = createComputed([createBinding(p, "position"), createBinding(p, "length")], (a, b) => (b > 0 ? meter(a / b, 24) : ""))
  const t = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`
  return (
    <Panel title={createBinding(p, "identity")((i) => i || p.busName)} spacing={4}>
      <label cssClasses={["big"]} label={createBinding(p, "title")((t) => t || "—")} xalign={0} />
      <label cssClasses={["dim"]} label={createComputed([createBinding(p, "artist"), createBinding(p, "album")], (a, b) => [a, b].filter(Boolean).join(" · "))} xalign={0} />
      <box spacing={12}>
        <button cssClasses={["act"]} onClicked={() => p.previous()} visible={createBinding(p, "canGoPrevious")}><label label="⏮" /></button>
        <button cssClasses={["act"]} onClicked={() => p.play_pause()}><label label={playing((x) => (x ? "⏸" : "▶"))} /></button>
        <button cssClasses={["act"]} onClicked={() => p.next()} visible={createBinding(p, "canGoNext")}><label label="⏭" /></button>
        <label cssClasses={["spark"]} label={pos} />
        <label cssClasses={["dim"]} label={createComputed([createBinding(p, "position"), createBinding(p, "length")], (a, b) => (b > 0 ? `${t(a)} / ${t(b)}` : ""))} />
      </box>
    </Panel>
  )
}

export default function Media() {
  const players = createBinding(Mpris.get_default(), "players")
  return (
    <box orientation={Gtk.Orientation.VERTICAL}>
      <For each={players}>{(p) => <Player p={p} />}</For>
      <label cssClasses={["dim"]} label="nothing playing" visible={players((ps) => ps.length === 0)} />
    </box>
  )
}
