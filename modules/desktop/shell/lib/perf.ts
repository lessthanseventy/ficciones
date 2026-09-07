// System load from /proc, polled once a second and shared by every consumer (bar cells, the
// cat, later the PERF pane). One reader, many accessors: /proc is cheap but not free.
import { createPoll } from "ags/time"
import { readFile } from "ags/file"

export type Perf = {
  cpu: number        // 0..1 busy fraction over the last tick
  mem: number        // 0..1 used fraction (MemTotal - MemAvailable)
  memUsedGb: number
  memTotalGb: number
  rx: number         // bytes/s, all non-lo interfaces
  tx: number
  load1: number
  cpuHist: number[]   // last 120 samples, oldest first
  memHist: number[]
  netHist: number[]   // (rx+tx) / NET_HOT
  cores: number[]     // per-core busy fraction
  coreHist: number[][] // per core, last CORE_HIST samples, oldest first
  load5: number
  load15: number
  swapUsed: number    // GB
  swapTotal: number
  cached: number      // GB (Cached + Buffers)
  ifaces: { name: string; rx: number; tx: number }[]  // bytes/s per interface
}

/** 10 MB/s reads as fully hot on the net meter. */
export const NET_HOT = 10 * 1048576
const HIST = 120
/** per-core history is shorter: twenty sparklines of two minutes would be noise */
export const CORE_HIST = 40
const cpuHist: number[] = [], memHist: number[] = [], netHist: number[] = []
const coreHist: number[][] = []
const push = (a: number[], x: number, max = HIST) => { a.push(x); if (a.length > max) a.shift() }

let prevCpu: [number, number][] = []          // per line: [idle, total]; index 0 = all
let prevNet: Map<string, [number, number]> = new Map()
let prevNetT = 0

/** [all, ...cores] busy fractions over the last tick. */
function readCpu(): number[] {
  const lines = readFile("/proc/stat").split("\n").filter((l) => /^cpu\d* /.test(l))
  const out = lines.map((l, i) => {
    const f = l.trim().split(/\s+/).slice(1).map(Number)
    const idle = f[3] + f[4]
    const total = f.reduce((a, b) => a + b, 0)
    let busy = 0
    const p = prevCpu[i]
    if (p) {
      const dIdle = idle - p[0], dTotal = total - p[1]
      busy = dTotal > 0 ? 1 - dIdle / dTotal : 0
    }
    prevCpu[i] = [idle, total]
    return Math.max(0, Math.min(1, busy))
  })
  return out
}

function readMem() {
  const kv: Record<string, number> = {}
  for (const l of readFile("/proc/meminfo").split("\n")) {
    const m = l.match(/^(\w+):\s+(\d+)/)
    if (m) kv[m[1]] = Number(m[2])
  }
  const GB = 1048576
  const total = kv.MemTotal ?? 1
  const used = total - (kv.MemAvailable ?? 0)
  return {
    mem: used / total, memUsedGb: used / GB, memTotalGb: total / GB,
    cached: ((kv.Cached ?? 0) + (kv.Buffers ?? 0)) / GB,
    swapUsed: ((kv.SwapTotal ?? 0) - (kv.SwapFree ?? 0)) / GB, swapTotal: (kv.SwapTotal ?? 0) / GB,
  }
}

function readNet() {
  const now = Date.now()
  const dt = prevNetT ? (now - prevNetT) / 1000 : 0
  const ifaces: { name: string; rx: number; tx: number }[] = []
  let rx = 0, tx = 0
  for (const l of readFile("/proc/net/dev").split("\n").slice(2)) {
    const [name, rest] = l.split(":")
    if (!rest) continue
    const n = name.trim()
    if (n === "lo") continue
    const f = rest.trim().split(/\s+/).map(Number)
    const p = prevNet.get(n)
    let rrx = 0, rtx = 0
    if (p && dt > 0) { rrx = Math.max(0, (f[0] - p[0]) / dt); rtx = Math.max(0, (f[8] - p[1]) / dt) }
    prevNet.set(n, [f[0], f[8]])
    if (f[0] > 0 || f[8] > 0) ifaces.push({ name: n, rx: rrx, tx: rtx })
    rx += rrx; tx += rtx
  }
  prevNetT = now
  return { rx, tx, ifaces: ifaces.sort((a, b) => b.rx + b.tx - a.rx - a.tx) }
}

function sample(): Perf {
  const [cpu, ...cores] = readCpu()
  const m = readMem()
  const n = readNet()
  const [load1, load5, load15] = readFile("/proc/loadavg").split(" ").slice(0, 3).map(Number)
  push(cpuHist, cpu); push(memHist, m.mem); push(netHist, Math.min(1, (n.rx + n.tx) / NET_HOT))
  cores.forEach((c, i) => { coreHist[i] ??= []; push(coreHist[i], c, CORE_HIST) })
  return { cpu, ...m, ...n, load1: load1 || 0, load5: load5 || 0, load15: load15 || 0, cpuHist, memHist, netHist, cores, coreHist }
}

export const perf = createPoll<Perf>(
  { cpu: 0, mem: 0, memUsedGb: 0, memTotalGb: 0, rx: 0, tx: 0, load1: 0, load5: 0, load15: 0, cpuHist, memHist, netHist, cores: [], coreHist, swapUsed: 0, swapTotal: 0, cached: 0, ifaces: [] },
  1000,
  sample,
)

/** Load tiers drive colour: body amber → green when idle-ish? No: idle dim, busy amber, hot red. */
export function tier(frac: number): "idle" | "busy" | "hot" {
  return frac < 0.25 ? "idle" : frac < 0.75 ? "busy" : "hot"
}

export function rate(bytesPerSec: number): string {
  if (bytesPerSec < 1024) return `${Math.round(bytesPerSec)}B`
  if (bytesPerSec < 1048576) return `${(bytesPerSec / 1024).toFixed(0)}K`
  return `${(bytesPerSec / 1048576).toFixed(1)}M`
}

/** Mean and peak of a history window, for the "last two minutes" lines. */
export function stats(h: number[]): { mean: number; peak: number } {
  if (!h.length) return { mean: 0, peak: 0 }
  return { mean: h.reduce((a, b) => a + b, 0) / h.length, peak: Math.max(...h) }
}
