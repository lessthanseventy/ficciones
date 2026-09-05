// The perf metrics: one definition each, shared by the bar cells and their dropdowns.
import Gtk from "gi://Gtk?version=4.0"
import type { Accessor } from "ags"
import { Panel } from "../lib/tui"
import { pct, spark } from "../lib/format"
import { perf, tier, rate } from "../lib/perf"
import { gpu } from "../lib/gpu"

type Metric = {
  key: string
  frac: Accessor<number>
  num: Accessor<string>
  hist: Accessor<number[]>
  detail: Accessor<string>
  ok?: Accessor<boolean>
}

export const METRICS: Metric[] = [
  { key: "CPU", frac: perf((p) => p.cpu), num: perf((p) => pct(p.cpu)), hist: perf((p) => p.cpuHist), detail: perf((p) => `load ${p.load1.toFixed(2)}`) },
  { key: "RAM", frac: perf((p) => p.mem), num: perf((p) => pct(p.mem)), hist: perf((p) => p.memHist), detail: perf((p) => `${p.memUsedGb.toFixed(1)} of ${p.memTotalGb.toFixed(0)} GB`) },
  { key: "GPU", frac: gpu((g) => g.util), num: gpu((g) => (g.ok ? pct(g.util) : "off")), hist: gpu((g) => g.hist.flatMap((x) => [x, x, x, x, x])), detail: gpu((g) => (g.ok ? `${g.temp}°C   ${g.watts.toFixed(0)} W   ${g.memUsed} of ${g.memTotal} MiB` : "nvidia is off")), ok: gpu((g) => g.ok) },
  { key: "NET", frac: perf((p) => Math.min(1, p.netHist.at(-1) ?? 0)), num: perf((p) => rate(p.rx + p.tx)), hist: perf((p) => p.netHist), detail: perf((p) => `↓ ${rate(p.rx)}/s   ↑ ${rate(p.tx)}/s`) },
]

/** The dropdown off a bar cell: the metric large, two minutes of history, the detail line. */
export function MetricDetail({ m }: { m: Metric }) {
  return (
    <box orientation={Gtk.Orientation.VERTICAL} cssClasses={m.frac((f) => ["metric", tier(f)])} spacing={6} widthRequest={560}>
      <box spacing={16}>
        <label cssClasses={["huge"]} label={m.num} xalign={0} />
        <label cssClasses={["dim"]} label={m.detail} xalign={0} valign={Gtk.Align.END} />
      </box>
      <label cssClasses={["spark", "wide"]} label={m.hist((h) => spark(h, 60))} xalign={0} halign={Gtk.Align.START} />
      <label cssClasses={["dim", "sm"]} label="last two minutes · one glyph = two seconds" xalign={0} />
    </box>
  )
}
