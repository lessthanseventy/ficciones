// The NVIDIA half of the hybrid GPU via nvidia-smi. ~1.8s per call on this box, so it polls
// every 5s and never blocks the loop; when the card is off (EnvyControl integrated, a VM)
// the poll fails and the cell hides itself.
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"

export type Gpu = {
  ok: boolean
  util: number      // 0..1
  memUsed: number   // MiB
  memTotal: number
  temp: number      // °C
  watts: number
  hist: number[]
}

const HIST = 120
const hist: number[] = []

export const gpu = createPoll<Gpu>(
  { ok: false, util: 0, memUsed: 0, memTotal: 0, temp: 0, watts: 0, hist },
  5000,
  async () => {
    try {
      const out = await execAsync([
        "nvidia-smi",
        "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
        "--format=csv,noheader,nounits",
      ])
      const [u, mu, mt, t, w] = out.trim().split(",").map((x) => Number(x.trim()))
      const util = Math.max(0, Math.min(1, u / 100))
      hist.push(util); if (hist.length > HIST) hist.shift()
      return { ok: true, util, memUsed: mu, memTotal: mt, temp: t, watts: w, hist }
    } catch {
      return { ok: false, util: 0, memUsed: 0, memTotal: 0, temp: 0, watts: 0, hist }
    }
  },
)
