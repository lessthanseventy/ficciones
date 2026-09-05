// PERF: the three metrics with the full two-minute history.
import Gtk from "gi://Gtk?version=4.0"
import { Panel } from "../lib/tui"
import { pct, spark } from "../lib/format"
import { perf, tier, rate } from "../lib/perf"
import { gpu } from "../lib/gpu"

const W = 60 // glyphs = 120 samples = the whole history

function Metric({ title, num, hist, detail, frac, visible }: any) {
  return (
    <Panel title={title} cssClasses={frac((f: number) => [tier(f)])} spacing={4} visible={visible}>
      <box spacing={12}>
        <label cssClasses={["big"]} label={num} widthChars={5} xalign={1} />
        <label cssClasses={["dim"]} label={detail} xalign={0} hexpand />
      </box>
      <label cssClasses={["spark", "wide"]} label={hist((h: number[]) => spark(h, W))} xalign={0} halign={Gtk.Align.START} />
    </Panel>
  )
}

export default function Perf() {
  return (
    <box orientation={Gtk.Orientation.VERTICAL}>
      <Metric title="CPU" frac={perf((p) => p.cpu)} num={perf((p) => pct(p.cpu))} hist={perf((p) => p.cpuHist)} detail={perf((p) => `load ${p.load1.toFixed(2)}`)} />
      <Metric title="RAM" frac={perf((p) => p.mem)} num={perf((p) => pct(p.mem))} hist={perf((p) => p.memHist)} detail={perf((p) => `${p.memUsedGb.toFixed(1)} of ${p.memTotalGb.toFixed(0)} GB`)} />
      <Metric title="GPU" visible={gpu((g) => g.ok)} frac={gpu((g) => g.util)} num={gpu((g) => pct(g.util))} hist={gpu((g) => g.hist)} detail={gpu((g) => `${g.temp}°C   ${g.watts.toFixed(0)} W   ${g.memUsed} of ${g.memTotal} MiB`)} />
      <Metric title="NET" frac={perf((p) => Math.min(1, p.netHist.at(-1) ?? 0))} num={perf((p) => rate(p.rx + p.tx))} hist={perf((p) => p.netHist)} detail={perf((p) => `↓ ${rate(p.rx)}/s   ↑ ${rate(p.tx)}/s`)} />
    </box>
  )
}
