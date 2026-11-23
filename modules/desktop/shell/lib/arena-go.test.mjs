// node --test lib/arena-go.test.mjs (mise shell:test): tellArena and toArena against a fake `arena` on PATH.
import { test } from "node:test"
import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import { mkdtempSync, writeFileSync, chmodSync, readFileSync, existsSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { tellArena, toArena } from "./arena-go.ts"

function fake(exit) {
  const dir = mkdtempSync(join(tmpdir(), "arena-go-"))
  const log = join(dir, "argv")
  writeFileSync(join(dir, "arena"), `#!/bin/sh\nprintf '%s\\n' "$*" > ${log}\nexit ${exit}\n`)
  chmodSync(join(dir, "arena"), 0o755)
  const run = (argv) => new Promise((res, rej) => {
    const p = spawn(argv[0], argv.slice(1), { env: { ...process.env, PATH: `${dir}:${process.env.PATH}` } })
    p.on("error", rej)
    p.on("close", res)
  })
  const calls = { open: 0, notice: [], log: [] }
  const go = { run, open: () => calls.open++, notify: (t) => calls.notice.push(t), log: (t) => calls.log.push(t) }
  return { go, calls, argv: () => (existsSync(log) ? readFileSync(log, "utf8").trim() : null) }
}

const args = ["-L", "default", "show", "%290"]

test("a click on a session runs arena show on its pane and nothing else", async () => {
  const f = fake(0)
  await tellArena(args, f.go)
  assert.equal(f.argv(), "-L default show %290")
  assert.deepEqual([f.calls.open, f.calls.notice, f.calls.log], [0, [], []])
})

test("with no arena running (exit 3) a terminal is opened", async () => {
  const f = fake(3)
  await tellArena(args, f.go)
  assert.equal(f.calls.open, 1)
  assert.deepEqual(f.calls.notice, [])
})

test("any other failure is logged and shown", async () => {
  const f = fake(1)
  await tellArena(args, f.go)
  assert.equal(f.calls.open, 0)
  assert.equal(f.calls.log.length, 1)
  assert.match(f.calls.notice[0], /show %290.*exit 1/)
})

test("arena missing from PATH is logged and shown", async () => {
  const f = fake(0)
  await tellArena(args, { ...f.go, run: () => Promise.reject(new Error("spawn arena ENOENT")) })
  assert.match(f.calls.notice[0], /ENOENT/)
  assert.match(f.calls.log[0], /ENOENT/)
})

function shell(f, window) {
  const order = []
  const sh = {
    ...f.go,
    run: (argv) => { order.push("tell"); return f.go.run(argv) },
    arena: () => window,
    focus: (a) => order.push(`focus ${a}`),
  }
  return { sh, order }
}


test("toArena focuses first and passes the args through", async () => {
  const f = fake(0)
  const { sh, order } = shell(f, { address: "0xabc" })
  await toArena(["board", "7"], () => {}, sh)
  assert.deepEqual(order, ["focus 0xabc", "tell"])
  assert.equal(f.argv(), "board 7")
})
