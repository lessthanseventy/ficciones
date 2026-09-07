// What is actually making sound: PipeWire's output streams in state "running", polled every
// 2 s (pw-dump). Mpris says PLAYING/Paused as the page feels like it — Floorp on a streaming
// site sat on Paused with the audio live (2026-09-07) — and AstalWp's stream state never
// leaves CREATING here, so this is the one honest signal. Per process, so a player can be
// matched to its stream (its Mpris bus name → pid, through the bus).
import { createState } from "ags"
import { execAsync } from "ags/process"
import { interval } from "ags/time"

/** pids with a running output stream */
export const [soundPids, setSoundPids] = createState<Set<number>>(new Set())
export const soundRunning = soundPids((s) => s.size > 0)

type Node = { info?: { state?: string; props?: Record<string, string | number> } }
function poll() {
  execAsync(["env", "PIPEWIRE_DEBUG=0", "pw-dump"]).then((out) => {
    const pids = new Set<number>()
    for (const n of JSON.parse(out) as Node[]) {
      const p = n.info?.props
      if (p?.["media.class"] === "Stream/Output/Audio" && n.info?.state === "running") pids.add(Number(p["application.process.id"] ?? 0))
    }
    const cur = soundPids.peek()
    if (cur.size !== pids.size || [...pids].some((x) => !cur.has(x))) setSoundPids(pids)
  }).catch(() => {})
}
interval(2000, poll)
poll()

// an Mpris bus name → its process, cached; 0 while unresolved, -1 when the bus has no answer
const pidOf = new Map<string, number>()
export function playerPid(busName: string | null | undefined): number {
  if (!busName) return -1
  const known = pidOf.get(busName)
  if (known !== undefined) return known
  pidOf.set(busName, 0)
  execAsync(["busctl", "--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", busName])
    .then((out) => pidOf.set(busName, Number(out.trim().split(/\s+/).pop() ?? 0)))
    .catch(() => pidOf.set(busName, -1))
  return 0
}
/** the player's process has a running output stream */
export const playerSounding = (busName: string | null | undefined, pids: Set<number>) => pids.has(playerPid(busName))
