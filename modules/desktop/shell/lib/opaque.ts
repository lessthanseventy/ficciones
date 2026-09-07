// Windows with video playing are opaque under glass (Andrew, 2026-09-06). Hyprland has no
// "playing video" state, so it is inferred every 2 s: an idle inhibitor (players ask for one),
// a playing Mpris player from the window's process (matched by pid; a multi-window app like
// the browser also needs a video-ish title, or every window of it would go opaque), a player
// class, or fullscreen. `setprop opaque` per window; `unset` when it stops.
import Mpris from "gi://AstalMpris"
import { execAsync } from "ags/process"
import { L, dispatch } from "./hyprlua"
import { interval } from "ags/time"
import { query } from "./hyprsock"

type Client = { address: string; pid: number; class: string; title: string; mapped: boolean; inhibitingIdle?: boolean; fullscreen: number }

const PLAYERS = /^(mpv|vlc|io\.github\.celluloid|com\.github\.rafostar\.Clapper|org\.gnome\.Totem|haruna|jellyfinmediaplayer|plex)/i
const VIDEO_TITLE = /youtube|cineby|netflix|plex|jellyfin|twitch|vimeo|hulu|disney|prime video|crunchyroll|watch|video|stream|episode|\bS\d+ ?E\d+\b|dropout|max\b|peacock|paramount/i

const opaque = new Set<string>()

// Which processes are playing: the Mpris players that say PLAYING, their pids through the
// bus (cached per bus name). AstalWp's stream state never leaves CREATING here, so it is not
// the signal (2026-09-07).
const mpris = Mpris.get_default()
const pidOf = new Map<string, number>()
function resolvePids() {
  for (const p of mpris.get_players()) {
    const bus = p.busName
    if (!bus || pidOf.has(bus)) continue
    pidOf.set(bus, 0)
    execAsync(["busctl", "--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", bus])
      .then((out) => pidOf.set(bus, Number(out.trim().split(/\s+/).pop() ?? 0)))
      .catch(() => pidOf.set(bus, -1))
  }
}
function playingPids(): Set<number> {
  resolvePids()
  const out = new Set<number>()
  for (const p of mpris.get_players()) {
    if (p.playbackStatus !== Mpris.PlaybackStatus.PLAYING) continue
    const pid = pidOf.get(p.busName ?? "") ?? 0
    if (pid > 0) out.add(pid)
  }
  return out
}

function tick() {
  let clients: Client[]
  try { clients = JSON.parse(query("j/clients")) } catch { return }
  const pids = playingPids()
  const perPid = new Map<number, number>()
  for (const c of clients) if (c.mapped) perPid.set(c.pid, (perPid.get(c.pid) ?? 0) + 1)
  const want = new Set<string>()
  for (const c of clients) {
    if (!c.mapped) continue
    const sound = pids.has(c.pid) && ((perPid.get(c.pid) ?? 0) === 1 || VIDEO_TITLE.test(c.title))
    if (c.inhibitingIdle || c.fullscreen > 0 || PLAYERS.test(c.class) || sound) want.add(c.address)
  }
  const cmds: string[] = []
  for (const a of want) if (!opaque.has(a)) { opaque.add(a); cmds.push(L.setProp(`address:${a}`, "opaque", "1")) }
  for (const a of [...opaque]) if (!want.has(a)) {
    opaque.delete(a)
    if (clients.some((c) => c.address === a)) cmds.push(L.setProp(`address:${a}`, "opaque", "unset"))
  }
  if (cmds.length) dispatch(...cmds)
}

interval(2000, tick)
