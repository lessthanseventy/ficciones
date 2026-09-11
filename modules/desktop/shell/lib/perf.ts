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
  disk: number        // bytes/s read+written on the root disk
  diskHist: number[]  // / DISK_HOT
  temp: number        // °C, the CPU package
  tempHist: number[]  // / 100
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
  const d = diskRate(); push(diskHist, Math.min(1, d / DISK_HOT))
  const temp = pkgTemp(); push(tempHist, Math.min(1, temp / 100))   // °/100, so mean/peak read true; sparks map it through tempFrac
  cores.forEach((c, i) => { coreHist[i] ??= []; push(coreHist[i], c, CORE_HIST) })
  return { cpu, ...m, ...n, load1: load1 || 0, load5: load5 || 0, load15: load15 || 0, cpuHist, memHist, netHist, cores, coreHist, disk: d, diskHist, temp, tempHist }
}

// ── the root disk's i/o and the package temperature ────────────────────────────────────
export const DISK_HOT = 200 * 1048576 // 200 MB/s reads as a full spark
const diskHist: number[] = []
const tempHist: number[] = []
let lastSectors = -1, lastDiskT = 0
/** /proc/diskstats for the whole device under / (nvme0n1 for nvme0n1p2): sectors read + written */
function diskRate(): number {
  try {
    const stats = readFile("/proc/diskstats")
    const dev = rootDevice()
    const line = stats.split("\n").find((l) => l.trim().split(/\s+/)[2] === dev)
    if (!line) return 0
    const f = line.trim().split(/\s+/)
    const sectors = Number(f[5]) + Number(f[9])
    const now = Date.now()
    const rate = lastSectors < 0 ? 0 : ((sectors - lastSectors) * 512) / Math.max(0.001, (now - lastDiskT) / 1000)
    lastSectors = sectors; lastDiskT = now
    return Math.max(0, rate)
  } catch { return 0 }
}
let rootDev = ""
/** the whole device under /: nvme0n1 for /dev/nvme0n1p2, sda for /dev/sda3 */
function rootDevice(): string {
  if (rootDev) return rootDev
  try {
    const m = readFile("/proc/self/mountinfo").split("\n").find((l) => l.split(" ")[4] === "/")
    const src = (m?.split(" - ")[1]?.split(" ")[1] ?? "").replace(/^\/dev\//, "")
    rootDev = /^nvme/.test(src) ? src.replace(/p\d+$/, "") : src.replace(/\d+$/, "")
  } catch { rootDev = "" }
  return rootDev
}
let tempZone = ""
/** the x86_pkg_temp zone (or TCPU), in °C */
function pkgTemp(): number {
  try {
    if (!tempZone) {
      for (let i = 0; i < 32; i++) {
        let t = ""
        try { t = readFile(`/sys/class/thermal/thermal_zone${i}/type`).trim() } catch { break }
        if (t === "x86_pkg_temp" || (t === "TCPU" && !tempZone)) { tempZone = `/sys/class/thermal/thermal_zone${i}/temp`; if (t === "x86_pkg_temp") break }
      }
    }
    return tempZone ? Number(readFile(tempZone).trim()) / 1000 : 0
  } catch { return 0 }
}

export const perf = createPoll<Perf>(
  { cpu: 0, mem: 0, memUsedGb: 0, memTotalGb: 0, rx: 0, tx: 0, load1: 0, load5: 0, load15: 0, cpuHist, memHist, netHist, cores: [], coreHist, swapUsed: 0, swapTotal: 0, cached: 0, ifaces: [], disk: 0, diskHist, temp: 0, tempHist },
  1000,
  sample,
)

export type Tier = "idle" | "busy" | "hot"
/** Where a gauge turns amber and then red is a DIFFERENT question per metric, and one pair of
 *  breaks for all of them was lying: a CPU at a quarter is genuinely working, a machine with
 *  64 GB at a quarter has not started, and a disk at three quarters is not yet a problem. Pairs
 *  are [warm, hot] as fractions; a metric that does not name one gets the CPU's. */
export const BREAKS = {
  cpu: [0.25, 0.75],
  /** RAM you paid for is not a problem until it is nearly gone (Andrew, 2026-09-10). */
  mem: [0.5, 0.75],
  /** A throughput gauge is scaled against its own hot mark already, so it reads like a CPU. */
  rate: [0.25, 0.75],
  /** 65..105 °C maps to 0..1, so these are 75 ° and 95 ° on a Tjmax-100 part. */
  temp: [0.25, 0.75],
} as const satisfies Record<string, readonly [number, number]>
/** °C onto 0..1 over 65..105: the colour tier, and the spark, so a spark row is a tier step
 *  (°/100 put every reading from 50° to 99° in the top two rows) */
export const tempFrac = (c: number) => Math.max(0, Math.min(1, (c - 65) / 40))

export function tier(frac: number, breaks: readonly [number, number] = BREAKS.cpu): Tier {
  return frac < breaks[0] ? "idle" : frac < breaks[1] ? "busy" : "hot"
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
