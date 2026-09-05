// DASH: one headline from each other pane plus the month, so "what is happening" needs no tab.
import Gtk from "gi://Gtk?version=4.0"
import GLib from "gi://GLib?version=2.0"
import Mpris from "gi://AstalMpris"
import { createBinding, createComputed } from "ags"
import { Panel } from "../lib/tui"
import { pct } from "../lib/format"
import { perf, rate } from "../lib/perf"
import { weather, glyph } from "../lib/weather"
import { agents } from "../lib/agents"

function Calendar() {
  const now = GLib.DateTime.new_now_local()
  const first = GLib.DateTime.new_local(now.get_year(), now.get_month(), 1, 0, 0, 0)!
  const lead = (first.get_day_of_week() + 6) % 7 // Monday = 0
  const days = first.add_months(1)!.add_days(-1)!.get_day_of_month()
  const today = now.get_day_of_month()
  const cells: (number | null)[] = [...Array(lead).fill(null), ...Array.from({ length: days }, (_, i) => i + 1)]
  while (cells.length % 7) cells.push(null)
  const rows: (number | null)[][] = []
  for (let i = 0; i < cells.length; i += 7) rows.push(cells.slice(i, i + 7))
  return (
    <Panel title={now.format("%B %Y")!} spacing={2}>
      <box cssClasses={["cal-head"]} homogeneous>
        {["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"].map((d) => <label label={d} />)}
      </box>
      {rows.map((r) => (
        <box homogeneous>
          {r.map((d) => (
            <label cssClasses={["cal-day", ...(d === today ? ["chip"] : []), ...(d === null ? ["dim"] : [])]} label={d === null ? "" : String(d)} />
          ))}
        </box>
      ))}
    </Panel>
  )
}

function Headline({ k, v, cls = [] }: { k: string; v: any; cls?: any }) {
  return (
    <box cssClasses={["headline"]} spacing={12}>
      <label cssClasses={["k"]} label={k} widthChars={8} xalign={0} />
      <label cssClasses={cls} label={v} xalign={0} hexpand />
    </box>
  )
}

export default function Dash() {
  const mpris = Mpris.get_default()
  const players = createBinding(mpris, "players")
  const media = players((ps) => {
    const p = ps.find((x) => x.playbackStatus === Mpris.PlaybackStatus.PLAYING) ?? ps[0]
    return p ? `${p.playbackStatus === Mpris.PlaybackStatus.PLAYING ? "▶" : "⏸"} ${p.title ?? ""} — ${p.artist ?? ""}` : "nothing playing"
  })
  const w = weather((w) => (w.ok ? `${glyph(w.code)} ${Math.round(w.temp!)}°  ${Math.round(w.low!)}–${Math.round(w.high!)}  wind ${Math.round(w.wind!)} mph` : w.note ?? ""))
  const a = agents((a) => (a.ok ? `${a.roster.length} on the clock · ${a.counts.open ?? 0} open · ${a.awaiting} awaiting you` : a.note ?? ""))
  const aCls = agents((a) => (a.awaiting > 0 ? ["pink"] : a.ok ? [] : ["dim"]))
  const p = perf((p) => `cpu ${pct(p.cpu)}  ram ${pct(p.mem)}  net ${rate(p.rx + p.tx)}  load ${p.load1.toFixed(1)}`)

  return (
    <box spacing={12}>
      <box orientation={Gtk.Orientation.VERTICAL} hexpand>
        <Panel title="NOW" spacing={4}>
          <Headline k="PERF" v={p} />
          <Headline k="MEDIA" v={media} />
          <Headline k="WEATHER" v={w} />
          <Headline k="AGENTS" v={a} cls={aCls} />
        </Panel>
      </box>
      <Calendar />
    </box>
  )
}
