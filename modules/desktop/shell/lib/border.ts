// The focus gradient (border, shadow, glow) turns once when a window takes focus and rests; with
// look.borderLoop it turns for ever, and Hyprland then redraws every window every frame.
// hyprland.lua's border_turn holds both sets of values.
import { timeout } from "ags/time"
import { hypr } from "./hypr"
import { evalLua } from "./hyprlua"
import { setting } from "./settings"

const loop = setting("look.borderLoop")
const apply = () => void evalLua(`border_turn(${loop.peek()})`).catch(console.error)
loop.subscribe(apply)
apply()
// a config reload puts back hyprland.lua's resting turn
hypr.connect("event", (_, ev: string) => { if (ev === "configreloaded") timeout(200, apply) })
