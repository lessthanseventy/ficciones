// The floor plan's sums (lib/floor.ts draws it): who sits where and how tall that makes it, in the
// plan's logical pixels. Pure, so the tests can reach it without the kit or gi.
import type { Crew } from "../office/kit/crew"

export const BOARD_H = 29, STRIP_ROW = 7, DESK_H = 31, LOUNGE_H = 19, HEAD_H = 7
export const DESKS_PER_ROW = 2, LOUNGE_PER_ROW = 4

/** a live session keeps its desk between turns, so a turn ending never moves anyone; bench order holds */
export function tiers<T extends Pick<Crew, "status">>(crew: T[]): { desks: T[]; lounge: T[] } {
  const live = (c: T) => c.status === "working" || c.status === "waiting" || c.status === "idle"
  return { desks: crew.filter(live), lounge: crew.filter((c) => !live(c)) }
}

const rows = (n: number, per: number) => Math.ceil(n / per)
/** the heads and strips are always there, so the plan only changes height when a row fills or empties */
export function floorHeight(desks: number, lounge: number, stripRows: number): number {
  return BOARD_H + stripRows * STRIP_ROW + HEAD_H + Math.max(1, rows(desks, DESKS_PER_ROW)) * DESK_H + (lounge ? HEAD_H + rows(lounge, LOUNGE_PER_ROW) * LOUNGE_H : 0)
}
