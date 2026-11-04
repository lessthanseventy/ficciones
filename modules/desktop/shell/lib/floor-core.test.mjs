import test from "node:test"
import assert from "node:assert/strict"
import { BOARD_H, DESK_H, HEAD_H, LOUNGE_H, STRIP_ROW, floorHeight, tiers } from "./floor-core.ts"

const crew = (...s) => s.map((status, i) => ({ name: `p${i}`, status }))

test("a live session keeps its desk between turns; cold and off sit in the lounge", () => {
  const { desks, lounge } = tiers(crew("idle", "cold", "working", "off", "waiting"))
  assert.deepEqual(desks.map((c) => c.name), ["p0", "p2", "p4"])
  assert.deepEqual(lounge.map((c) => c.name), ["p1", "p3"])
})

test("the plan is as tall as its rows, and an empty floor still has one row of it", () => {
  assert.equal(floorHeight(3, 5, 2), BOARD_H + 2 * STRIP_ROW + HEAD_H + 2 * DESK_H + HEAD_H + 2 * LOUNGE_H)
  assert.equal(floorHeight(0, 0, 0), BOARD_H + HEAD_H + DESK_H)
})
