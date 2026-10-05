// The office scene for the right rail (surfaces/Office.tsx): tlon's rail room (office/rooms/rail.ts,
// linked in from the tlon checkout — the Nix build copies it from the pinned `tlon` input), painted
// with Cairo. The room hands back a frame in its logical pixels — the art, the text and overlays
// over it, the click targets — and this blows the art up S times with no smoothing and sets the
// text in the system font at screen resolution.
import Cairo from "cairo"
import GLib from "gi://GLib?version=2.0"
import Gdk from "gi://Gdk?version=4.0"
import GdkPixbuf from "gi://GdkPixbuf?version=2.0"
import { ROLE } from "./palette"
import { useRoles } from "../office/kit/palette"
import { RailRoom, W } from "../office/rooms/rail"
import type { Agents } from "./agents"
import type { Frame, Hit } from "../office/kit/canvas"

export { boardColumns, crewOf, type BoardItem, type Crew } from "../office/kit/crew"
export { W }
export type { Hit }
export const S = 3
const FONT = "ComicShannsMono Nerd Font"

export class OfficeSim extends RailRoom {
  /** paint the room; returns the click targets (widget pixels) and the scene's height (lpx) */
  /** `focus`: the agent whose card is open — the arrow follows them as it follows the picked thread */
  draw(cr: Cairo.Context, areaW: number, a: Agents, picked: number | null, armed: number | null, focus: string | null = null): { hits: Hit[]; height: number } {
    // the theme can switch under us: the room reads its colours from these on every frame
    useRoles(ROLE)
    const ox = Math.floor((areaW - W * S) / 2)
    cr.selectFontFace(FONT, Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL)
    const fr = this.render(a, { picked, armed, person: focus }, (s, size) => { cr.setFontSize(size); return cr.textExtents(s).width / S })
    paint(cr, fr, ox)
    return { hits: fr.hits.map((h) => ({ ...h, x: ox + h.x * S, y: h.y * S, w: h.w * S, h: h.h * S })), height: fr.height }
  }
}

function paint(cr: Cairo.Context, fr: Frame, ox: number) {
  const rgb = (c: string) => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16) / 255) as [number, number, number]
  const ink = (c: string) => cr.setSourceRGB(...rgb(c))
  cr.setAntialias(Cairo.Antialias.NONE)
  // the art: one pixbuf, scaled S times with no smoothing — a Cairo rectangle per logical pixel
  // cost a third of a core with a full office
  const art = GdkPixbuf.Pixbuf.new_from_bytes(new GLib.Bytes(fr.rgba), GdkPixbuf.Colorspace.RGB, true, 8, fr.width, fr.height, fr.width * 4)
  cr.save(); cr.translate(ox, 0); cr.scale(S, S)
  Gdk.cairo_set_source_pixbuf(cr, art, 0, 0)
  ;(cr.getSource() as Cairo.SurfacePattern).setFilter(Cairo.Filter.NEAREST)
  cr.paint(); cr.restore()
  cr.selectFontFace(FONT, Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL)
  for (const i of fr.ink) {
    if (i.t === "text") {
      cr.setFontSize(i.size); ink(i.color)
      const x = ox + i.x * S, w = i.align === "center" ? cr.textExtents(i.s).width : 0
      cr.moveTo(Math.round(x - w / 2), i.y * S); cr.showText(i.s)
    } else if (i.t === "brackets") {
      ink(i.color); cr.setLineWidth(2)
      const hx = ox + i.x * S, hy = i.y * S, hw = i.w * S, hh = i.h * S
      for (const [x0, y0, gx, gy] of [[hx, hy, 1, 1], [hx + hw, hy, -1, 1], [hx, hy + hh, 1, -1], [hx + hw, hy + hh, -1, -1]]) {
        cr.moveTo(x0 + gx * 10, y0); cr.lineTo(x0, y0); cr.lineTo(x0, y0 + gy * 10); cr.stroke()
      }
    } else {
      // what someone said, over their head, clamped inside the room
      cr.setFontSize(11)
      const lh = 14, bw = Math.max(...i.lines.map((l) => cr.textExtents(l).width)) + 14, bh = i.lines.length * lh + 8
      const bx = Math.min(Math.max(ox + i.cx * S - bw / 2, ox + 4), ox + W * S - bw - 4), by = Math.max(4, i.top * S - bh - 12)
      ink(ROLE.prose); cr.rectangle(bx, by, bw, bh); cr.fill()
      cr.rectangle(ox + i.cx * S - 3, by + bh, 6, 6); cr.fill()
      ink(ROLE.fieldInk)
      i.lines.forEach((l, n) => { cr.moveTo(bx + 7, by + 4 + (n + 1) * lh - 3); cr.showText(l) })
    }
  }
}
