// The shell's sound effects: a decision alert arrives, a landing, a deck timer ends. Played through
// pw-play (the same PipeWire the rest of lib/sound.ts reads); setting `sound.sfx`, muted by do-not-disturb.
import { execAsync } from "ags/process"
import { setting } from "./settings"
import { mayPlay, sfxFile, type Sfx } from "./sfx-core"

const src = () => (typeof SRC === "string" ? SRC : ".")

export function play(name: Sfx) {
  if (!mayPlay({ sfx: setting("sound.sfx").peek(), dnd: setting("notify.dnd").peek() })) return
  execAsync(["pw-play", "--volume=0.6", sfxFile(name, src())]).catch((e) => console.error("sfx:", String(e)))
}
