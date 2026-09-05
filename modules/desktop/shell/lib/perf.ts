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
}

/** 10 MB/s reads as fully hot on the net meter. */
export const NET_HOT = 10 * 1048576
const HIST = 120
const cpuHist: number[] = [], memHist: number[] = [], netHist: number[] = []
const push = (a: number[], x: number) => { a.push(x); if (a.length > HIST) a.shift() }

let prevCpu: [number, number] | null = null   // [idle, total]
let prevNet: [number, number, number] | null = null // [rx, tx, tMs]

function readCpu(): number {
  const line = readFile("/proc/stat").split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
  const idle = line[3] + line[4]
  const total = line.reduce((a, b) => a + b, 0)
  let busy = 0
  if (prevCpu) {
    const dIdle = idle - prevCpu[0]
    const dTotal = total - prevCpu[1]
    busy = dTotal > 0 ? 1 - dIdle / dTotal : 0
  }
  prevCpu = [idle, total]
  return Math.max(0, Math.min(1, busy))
}

function readMem(): [number, number, number] {
  const kv: Record<string, number> = {}
  for (const l of readFile("/proc/meminfo").split("\n")) {
    const m = l.match(/^(\w+):\s+(\d+)/)
    if (m) kv[m[1]] = Number(m[2])
  }
  const total = kv.MemTotal ?? 1
  const used = total - (kv.MemAvailable ?? 0)
  return [used / total, used / 1048576, total / 1048576]
}

function readNet(): [number, number] {
  let rx = 0, tx = 0
  for (const l of readFile("/proc/net/dev").split("\n").slice(2)) {
    const [name, rest] = l.split(":")
    if (!rest || name.trim() === "lo") continue
    const f = rest.trim().split(/\s+/).map(Number)
    rx += f[0]; tx += f[8]
  }
  const now = Date.now()
  let rrx = 0, rtx = 0
  if (prevNet) {
    const dt = (now - prevNet[2]) / 1000
    if (dt > 0) { rrx = (rx - prevNet[0]) / dt; rtx = (tx - prevNet[1]) / dt }
  }
  prevNet = [rx, tx, now]
  return [Math.max(0, rrx), Math.max(0, rtx)]
}

function sample(): Perf {
  const cpu = readCpu()
  const [mem, memUsedGb, memTotalGb] = readMem()
  const [rx, tx] = readNet()
  const load1 = Number(readFile("/proc/loadavg").split(" ")[0]) || 0
  push(cpuHist, cpu); push(memHist, mem); push(netHist, Math.min(1, (rx + tx) / NET_HOT))
  return { cpu, mem, memUsedGb, memTotalGb, rx, tx, load1, cpuHist, memHist, netHist }
}

export const perf = createPoll<Perf>(
  { cpu: 0, mem: 0, memUsedGb: 0, memTotalGb: 0, rx: 0, tx: 0, load1: 0, cpuHist, memHist, netHist },
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
