// Hyprland under a .lua config takes LUA on the control socket: `hyprctl dispatch <expr>` is
// `hl.dispatch(<expr>)`, `hyprctl keyword` is gone ("use eval"), and AstalHyprland's
// Client.focus()/Workspace.focus()/hypr.dispatch() — which still send the legacy words — do
// nothing (2026-09-07, the morning after the .conf → .lua switch: no focus keys, no rail
// clicks, no sidecar). Everything the shell asks of the compositor goes through here.
import { execAsync } from "ags/process"

const q = (s: string) => JSON.stringify(s) // a lua string literal; the escapes coincide
/** `address:0x…` for a client — AstalHyprland's address has no 0x. */
export const sel = (c: { address: string }) => `address:0x${c.address.replace(/^0x/, "")}`

/** Dispatcher expressions. Window selectors are the legacy strings (`address:0x…`). */
export const L = {
  focusWindow: (w: string) => `hl.dsp.focus({ window = ${q(w)} })`,
  workspace: (ws: string) => `hl.dsp.focus({ workspace = ${q(ws)} })`,
  layout: (msg: string) => `hl.dsp.layout(${q(msg)})`,
  setProp: (w: string, prop: string, value: string) => `hl.dsp.window.set_prop({ prop = ${q(prop)}, value = ${q(value)}, window = ${q(w)} })`,
  float: (w: string, action: "set" | "unset" | "toggle" = "toggle") => `hl.dsp.window.float({ action = ${q(action)}, window = ${q(w)} })`,
  pin: (w: string) => `hl.dsp.window.pin({ window = ${q(w)} })`,
  fullscreen: (w: string, mode: "fullscreen" | "maximize") => `hl.dsp.window.fullscreen({ mode = ${q(mode)}, window = ${q(w)} })`,
  fullscreenState: (w: string, internal: number, client: number) => `hl.dsp.window.fullscreen_state({ internal = ${internal}, client = ${client}, window = ${q(w)} })`,
  moveExact: (w: string, x: number, y: number) => `hl.dsp.window.move({ x = ${x}, y = ${y}, relative = false, window = ${q(w)} })`,
  resizeExact: (w: string, x: number, y: number) => `hl.dsp.window.resize({ x = ${x}, y = ${y}, relative = false, window = ${q(w)} })`,
  moveToWorkspace: (w: string, ws: string, follow: boolean) => `hl.dsp.window.move({ workspace = ${q(ws)}, follow = ${follow}, window = ${q(w)} })`,
  close: (w: string) => `hl.dsp.window.close({ window = ${q(w)} })`,
  exit: () => `hl.dsp.exit()`,
}

/** Dispatch in order as one batch; anything but "ok" is logged. */
export async function dispatch(...exprs: string[]) {
  if (!exprs.length) return
  try {
    const out = await execAsync(["hyprctl", "--batch", exprs.map((e) => `dispatch ${e}`).join("; ")])
    const bad = out.split("\n").filter((l) => l.trim() && l.trim() !== "ok")
    if (bad.length) console.error("hypr dispatch:", bad.join(" | "))
  } catch (e) { console.error("hypr dispatch:", String(e)) }
}

/** `hyprctl keyword section:key value` → `hl.config({ section = { key = value } })`. */
export function keyword(path: string, value: string | number) {
  const [section, key] = path.split(":")
  const v = typeof value === "number" || /^-?\d+(\.\d+)?$/.test(value) ? String(value) : q(String(value))
  return execAsync(["hyprctl", "eval", `hl.config({ ${section} = { [${q(key)}] = ${v} } })`])
}

/** Run a lua statement (a plugin's own action, say). */
export const evalLua = (code: string) => execAsync(["hyprctl", "eval", code])
