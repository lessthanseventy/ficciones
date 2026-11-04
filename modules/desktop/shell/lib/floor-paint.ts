// The floor plan on Cairo: the art blown up S times with no smoothing, the text over it at screen
// resolution in the system font.
import Cairo from "cairo"
import GLib from "gi://GLib?version=2.0"
import Gdk from "gi://Gdk?version=4.0"
import GdkPixbuf from "gi://GdkPixbuf?version=2.0"
import { ROLE } from "./palette"
import { useRoles } from "../office/kit/palette"
import type { Agents } from "./agents"
import type { Hit } from "../office/kit/canvas"
import { W, renderFloor } from "./floor"

export const S = 3
const FONT = "ComicShannsMono Nerd Font"

/** paint the plan; returns the click targets in widget pixels */
export function paintFloor(cr: Cairo.Context, areaW: number, a: Agents, ws: number | null, focus: { picked: number | null; person: string | null }): Hit[] {
  // the theme can switch under us: the plan reads its colours from these on every frame
  useRoles(ROLE)
  const ox = Math.floor((areaW - W * S) / 2)
  cr.selectFontFace(FONT, Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL)
  const fr = renderFloor(a, ws, focus, (s, size) => { cr.setFontSize(size); return cr.textExtents(s).width / S })
  const ink = (c: string) => cr.setSourceRGB(...([1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16) / 255) as [number, number, number]))
  cr.setAntialias(Cairo.Antialias.NONE)
  const art = GdkPixbuf.Pixbuf.new_from_bytes(new GLib.Bytes(fr.rgba), GdkPixbuf.Colorspace.RGB, true, 8, fr.width, fr.height, fr.width * 4)
  cr.save(); cr.translate(ox, 0); cr.scale(S, S)
  Gdk.cairo_set_source_pixbuf(cr, art, 0, 0)
  ;(cr.getSource() as Cairo.SurfacePattern).setFilter(Cairo.Filter.NEAREST)
  cr.paint(); cr.restore()
  // the art wants hard edges; the text does not
  cr.setAntialias(Cairo.Antialias.GRAY)
  for (const i of fr.ink) {
    if (i.t === "text") {
      cr.setFontSize(i.size); ink(i.color)
      const w = i.align === "center" ? cr.textExtents(i.s).width : 0
      cr.moveTo(Math.round(ox + i.x * S - w / 2), i.y * S); cr.showText(i.s)
    } else if (i.t === "brackets") {
      ink(i.color); cr.setLineWidth(2)
      const hx = ox + i.x * S, hy = i.y * S, hw = i.w * S, hh = i.h * S
      for (const [x0, y0, gx, gy] of [[hx, hy, 1, 1], [hx + hw, hy, -1, 1], [hx, hy + hh, 1, -1], [hx + hw, hy + hh, -1, -1]]) {
        cr.moveTo(x0! + gx! * 10, y0!); cr.lineTo(x0!, y0!); cr.lineTo(x0!, y0! + gy! * 10); cr.stroke()
      }
    }
  }
  return fr.hits.map((h) => ({ ...h, x: ox + h.x * S, y: h.y * S, w: h.w * S, h: h.h * S }))
}
