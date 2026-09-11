// The CRT toggle: a screen shader on the whole composited output, switched by path. Off by
// default — it costs GPU on a hybrid laptop — and orthogonal to the backdrop (design §6).
import GLib from "gi://GLib?version=2.0"
import { createState } from "ags"
import { keyword } from "./hyprlua"

export const MODES = ["off", "subtle", "full"] as const
export type Crt = (typeof MODES)[number]
export const [crt, setCrtState] = createState<Crt>("off")

const dir = `${GLib.get_user_config_dir()}/hypr/shaders`
export function setCrt(m: Crt) {
  const arg = m === "off" ? "[[EMPTY]]" : `${dir}/crt-${m}.glsl`
  keyword("decoration:screen_shader", arg).then(() => setCrtState(m)).catch(console.error)
}
export function cycleCrt() {
  setCrt(MODES[(MODES.indexOf(crt.peek()) + 1) % MODES.length])
}
