// Top processes and network addresses for the perf popovers. Polled every 3s — `ps` is cheap,
// and the popovers are the only readers.
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"

export type Proc = { pid: number; cpu: number; mem: number; comm: string }

/** ROWS rows: the popovers show six, the dashboard's list all of them. */
export const ROWS = 10

async function ps(sort: string): Promise<Proc[]> {
  try {
    const out = await execAsync(["ps", "-eo", "pid,pcpu,pmem,comm", "--sort", sort, "--no-headers"])
    return out.trim().split("\n").slice(0, ROWS).map((l) => {
      const [pid, cpu, mem, ...comm] = l.trim().split(/\s+/)
      return { pid: Number(pid), cpu: Number(cpu), mem: Number(mem), comm: comm.join(" ") }
    })
  } catch {
    return []
  }
}

export const topCpu = createPoll<Proc[]>([], 3000, () => ps("-pcpu"))
export const topMem = createPoll<Proc[]>([], 3000, () => ps("-rss"))

/** SIGTERM; the row goes on its own when the next `ps` tick no longer lists it. */
export const kill = (pid: number) => execAsync(["kill", String(pid)]).catch(console.error)

/** `iface: addr` for every interface with an IPv4, from `ip -j -4 addr`. */
export const addrs = createPoll<Record<string, string>>({}, 15_000, async () => {
  try {
    const j = JSON.parse(await execAsync(["ip", "-j", "-4", "addr"]))
    const out: Record<string, string> = {}
    for (const i of j) for (const a of i.addr_info ?? []) if (a.family === "inet") out[i.ifname] = a.local
    return out
  } catch {
    return {}
  }
})
