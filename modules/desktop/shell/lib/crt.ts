// The CRT toggle: a screen shader on the whole composited output, switched by path. Off by
// default — it costs GPU on a hybrid laptop — and orthogonal to the backdrop (design §6). The mode
// is a setting (look.crt), so a shell restart puts back the shader it had rather than claiming off.
import GLib from "gi://GLib?version=2.0"
import type { Accessor } from "ags"
import { keyword } from "./hyprlua"
import { setting, setSetting } from "./settings"

export const MODES = ["off", "subtle", "full"] as const
export type Crt = (typeof MODES)[number]
const valid = (m: string): Crt => ((MODES as readonly string[]).includes(m) ? (m as Crt) : "off")
export const crt: Accessor<Crt> = setting("look.crt")(valid)

const dir = `${GLib.get_user_config_dir()}/hypr/shaders`
function apply() {
  const m = valid(setting("look.crt").peek())
  keyword("decoration:screen_shader", m === "off" ? "[[EMPTY]]" : `${dir}/crt-${m}.glsl`).catch(console.error)
}
setting("look.crt").subscribe(apply)
apply()

export const setCrt = (m: Crt) => setSetting("look.crt", m)
export const cycleCrt = () => setCrt(MODES[(MODES.indexOf(crt.peek()) + 1) % MODES.length])
