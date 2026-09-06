// The perf metrics: one definition each, shared by the bar cells and their dropdowns.
import Gtk from "gi://Gtk?version=4.0"
import type { Accessor } from "ags"
import { pct, spark } from "../lib/format"
import { perf, tier, rate, stats, NET_HOT } from "../lib/perf"
import { topCpu, topMem, addrs, type Proc } from "../lib/top"
import { RuleH } from "../lib/tui"
import { createComputed } from "ags"
import { gpu } from "../lib/gpu"

type Metric = {
  key: string
  frac: Accessor<number>
  num: Accessor<string>
  hist: Accessor<number[]>
  detail: Accessor<string>
  fmt: (x: number) => string   // how a history value reads (percent, or a rate)
  ok?: Accessor<boolean>
}

export const METRICS: Metric[] = [
  { key: "CPU", frac: perf((p) => p.cpu), num: perf((p) => pct(p.cpu)), hist: perf((p) => p.cpuHist), detail: perf((p) => `load ${p.load1.toFixed(2)}`), fmt: pct },
  { key: "RAM", frac: perf((p) => p.mem), num: perf((p) => pct(p.mem)), hist: perf((p) => p.memHist), detail: perf((p) => `${p.memUsedGb.toFixed(1)} of ${p.memTotalGb.toFixed(0)} GB`), fmt: pct },
  { key: "GPU", frac: gpu((g) => g.util), num: gpu((g) => (g.ok ? pct(g.util) : "off")), hist: gpu((g) => g.hist.flatMap((x) => [x, x, x, x, x])), detail: gpu((g) => (g.ok ? `${g.temp}°C   ${g.watts.toFixed(0)} W` : "nvidia is off")), fmt: pct, ok: gpu((g) => g.ok) },
  { key: "NET", frac: perf((p) => Math.min(1, p.netHist.at(-1) ?? 0)), num: perf((p) => rate(p.rx + p.tx)), hist: perf((p) => p.netHist), detail: perf((p) => `↓ ${rate(p.rx)}/s   ↑ ${rate(p.tx)}/s`), fmt: (x) => rate(x * NET_HOT) + "/s" },
]

/** A dim key with a body value, inline. */
const KV = ({ k, v, cls = [] }: { k: string; v: any; cls?: string[] }) => (
  <box spacing={4}>
    <label cssClasses={["k", "sm"]} label={k} />
    <label cssClasses={["sm", ...cls]} label={v} />
  </box>
)

/** Top processes as rows: name, then the number that matters for this metric. */
export function Top({ list, col }: { list: Accessor<Proc[]>; col: "cpu" | "mem" }) {
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={1}>
      <label cssClasses={["k", "sm"]} label={col === "cpu" ? "top by cpu" : "top by memory"} xalign={0} />
      {Array.from({ length: 6 }, (_, i) => (
        <box spacing={8} visible={list((l) => i < l.length)}>
          <label cssClasses={["sm"]} label={list((l) => l[i]?.comm ?? "")} widthChars={22} xalign={0} ellipsize={3} />
          <label cssClasses={["dim", "sm"]} label={list((l) => (l[i] ? String(l[i].pid) : ""))} widthChars={7} xalign={1} />
          <label cssClasses={["amber", "sm"]} label={list((l) => (l[i] ? `${l[i][col].toFixed(1)}%` : ""))} widthChars={6} xalign={1} />
        </box>
      ))}
    </box>
  )
}

/** Per-core bars: one block column per core. */
export function Cores() {
  const cores = perf((p) => p.cores)
  const V = "▁▂▃▄▅▆▇█"
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
      <label cssClasses={["k", "sm"]} label={cores((c) => `${c.length} cores`)} xalign={0} />
      <label cssClasses={["cores"]} label={cores((c) => c.map((x) => V[Math.min(7, Math.round(x * 7))]).join(" "))} xalign={0} />
    </box>
  )
}

function Header({ m }: { m: Metric }) {
  const st = m.hist((h) => stats(h))
  return (
    <box spacing={16}>
      <label cssClasses={["huge"]} label={m.num} xalign={0} />
      <box orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.END} spacing={1}>
        <label cssClasses={["dim"]} label={m.detail} xalign={0} />
        <label cssClasses={["dim", "sm"]} label={st((s) => `2 min · mean ${m.fmt(s.mean)} · peak ${m.fmt(s.peak)}`)} xalign={0} />
      </box>
    </box>
  )
}

/** The dropdown off a bar cell: the metric large, two minutes of history, then the depth. */
export function MetricDetail({ m }: { m: Metric }) {
  return (
    <box orientation={Gtk.Orientation.VERTICAL} cssClasses={m.frac((f) => ["metric", tier(f)])} spacing={8} widthRequest={560}>
      <Header m={m} />
      <label cssClasses={["spark", "wide"]} label={m.hist((h) => spark(h, 60))} xalign={0} halign={Gtk.Align.START} />
      <RuleH />
      {m.key === "CPU" && (
        <box orientation={Gtk.Orientation.VERTICAL} spacing={8}>
          <box spacing={16}>
            <KV k="load 1/5/15" v={perf((p) => `${p.load1.toFixed(2)}  ${p.load5.toFixed(2)}  ${p.load15.toFixed(2)}`)} cls={["amber"]} />
          </box>
          <Cores />
          <Top list={topCpu} col="cpu" />
        </box>
      )}
      {m.key === "RAM" && (
        <box orientation={Gtk.Orientation.VERTICAL} spacing={8}>
          <box spacing={16}>
            <KV k="used" v={perf((p) => `${p.memUsedGb.toFixed(1)} GB`)} cls={["amber"]} />
            <KV k="cached" v={perf((p) => `${p.cached.toFixed(1)} GB`)} />
            <KV k="free" v={perf((p) => `${(p.memTotalGb - p.memUsedGb).toFixed(1)} GB`)} cls={["green"]} />
            <KV k="swap" v={perf((p) => (p.swapTotal > 0 ? `${p.swapUsed.toFixed(1)} / ${p.swapTotal.toFixed(0)} GB` : "none"))} />
          </box>
          <Top list={topMem} col="mem" />
        </box>
      )}
      {m.key === "GPU" && (
        <box spacing={16}>
          <KV k="temp" v={gpu((g) => `${g.temp}°C`)} cls={["amber"]} />
          <KV k="draw" v={gpu((g) => `${g.watts.toFixed(0)} W`)} />
          <KV k="vram" v={gpu((g) => `${(g.memUsed / 1024).toFixed(1)} / ${(g.memTotal / 1024).toFixed(0)} GB`)} />
          <KV k="clock" v={gpu((g) => (g.clock ? `${g.clock} MHz` : "—"))} />
        </box>
      )}
      {m.key === "NET" && (
        <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
          <label cssClasses={["k", "sm"]} label="interfaces" xalign={0} />
          {Array.from({ length: 4 }, (_, i) => (
            <box spacing={10} visible={perf((p) => i < p.ifaces.length)}>
              <label cssClasses={["cyan", "sm"]} label={perf((p) => p.ifaces[i]?.name ?? "")} widthChars={10} xalign={0} />
              <label cssClasses={["dim", "sm"]} label={createComputed([perf, addrs], (p, a) => a[p.ifaces[i]?.name ?? ""] ?? "")} widthChars={16} xalign={0} />
              <label cssClasses={["sm"]} label={perf((p) => (p.ifaces[i] ? `↓ ${rate(p.ifaces[i].rx)}/s` : ""))} widthChars={11} xalign={1} />
              <label cssClasses={["sm"]} label={perf((p) => (p.ifaces[i] ? `↑ ${rate(p.ifaces[i].tx)}/s` : ""))} widthChars={11} xalign={1} />
            </box>
          ))}
        </box>
      )}
    </box>
  )
}
