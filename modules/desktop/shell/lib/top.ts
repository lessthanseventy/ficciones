// Top processes and network addresses for the perf popovers. The process lists poll every 3 s
// only while one is on screen (watchTop): popover content is built at startup, so an always-on
// poll ran `ps` twice every 3 s for nobody.
import type Gtk from "gi://Gtk?version=4.0"
import { createState } from "ags"
import { createPoll, interval, type Timer } from "ags/time"
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

const [topCpu, setTopCpu] = createState<Proc[]>([])
const [topMem, setTopMem] = createState<Proc[]>([])
export { topCpu, topMem }
let watchers = 0, timer: Timer | null = null
const refresh = () => { ps("-pcpu").then(setTopCpu); ps("-rss").then(setTopMem) }
/** `$={watchTop}` on a widget showing a list: the lists poll while any such widget is mapped */
export function watchTop(w: Gtk.Widget) {
  w.connect("map", () => { if (watchers++ === 0) { refresh(); timer = interval(3000, refresh) } })
  w.connect("unmap", () => { if (--watchers === 0) { timer?.cancel(); timer = null } })
}

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
