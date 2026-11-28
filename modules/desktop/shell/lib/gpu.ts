// The NVIDIA half of the hybrid GPU via nvidia-smi. ~1.8s per call on this box, so it polls
// every 5s and never blocks the loop; when the card is off (EnvyControl integrated, a VM)
// the poll fails and the cell hides itself. A failure waits 5 min before the next call: a driver
// whose kernel module and userspace differ logs an NVRM line to the kernel journal on every call.
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"
import GLib from "gi://GLib?version=2.0"

export type Gpu = {
  ok: boolean
  util: number      // 0..1
  memUsed: number   // MiB
  memTotal: number
  temp: number      // °C
  watts: number
  clock: number     // MHz, graphics
  hist: number[]
}

const HIST = 120
const hist: number[] = []
const RETRY_MS = 300_000
let failedAt = -Infinity
// nvidia-smi wakes a runtime-suspended card and holds it awake for its autosuspend delay, so a
// poll every 5 s would keep the dGPU on; a sleeping card is read as off, from sysfs alone
const PM = "/sys/bus/pci/devices/0000:01:00.0/power/runtime_status"
const asleep = () => {
  try {
    const [ok, bytes] = GLib.file_get_contents(PM)
    return ok && new TextDecoder().decode(bytes).trim() === "suspended"
  } catch { return false }
}

export const gpu = createPoll<Gpu>(
  { ok: false, util: 0, memUsed: 0, memTotal: 0, temp: 0, watts: 0, clock: 0, hist },
  5000,
  async () => {
    if (Date.now() - failedAt < RETRY_MS || asleep()) return { ok: false, util: 0, memUsed: 0, memTotal: 0, temp: 0, watts: 0, clock: 0, hist }
    try {
      const out = await execAsync([
        "nvidia-smi",
        "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,clocks.gr",
        "--format=csv,noheader,nounits",
      ])
      // a field the card does not report reads "[N/A]"
      const [u, mu, mt, t, w, ck] = out.trim().split(",").map((x) => Number(x.trim()) || 0)
      const util = Math.max(0, Math.min(1, u / 100))
      hist.push(util); if (hist.length > HIST) hist.shift()
      return { ok: true, util, memUsed: mu, memTotal: mt, temp: t, watts: w, clock: ck || 0, hist }
    } catch {
      failedAt = Date.now()
      return { ok: false, util: 0, memUsed: 0, memTotal: 0, temp: 0, watts: 0, clock: 0, hist }
    }
  },
)
