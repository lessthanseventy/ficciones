// node --test lib/tell-core.test.mjs (mise shell:test): sendTell against a fake `babylon` on PATH.
import { test } from "node:test"
import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import { mkdtempSync, writeFileSync, chmodSync, readFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { sendTell } from "./tell-core.ts"

function fake(exit, stderr = "") {
  const dir = mkdtempSync(join(tmpdir(), "tell-"))
  const log = join(dir, "argv")
  writeFileSync(join(dir, "babylon"), `#!/bin/sh\nprintf '%s\\n' "$@" > ${log}\nprintf '%s' '${stderr}' >&2\nexit ${exit}\n`)
  chmodSync(join(dir, "babylon"), 0o755)
  const run = (argv) => new Promise((res, rej) => {
    const p = spawn(argv[0], argv.slice(1), { env: { ...process.env, PATH: `${dir}:${process.env.PATH}` } })
    let err = ""
    p.stderr.on("data", (d) => (err += d))
    p.on("error", rej)
    p.on("close", (code) => res({ code, err }))
  })
  return { run, argv: () => readFileSync(log, "utf8").trim().split("\n") }
}

test("a line is run as `babylon tell <line>`, whole, in one argument", async () => {
  const f = fake(0)
  assert.deepEqual(await sendTell("start #12 now; then 'rest'", f.run), { ok: true })
  assert.deepEqual(f.argv(), ["tell", "start #12 now; then 'rest'"])
})

test("a refusal comes back as babylon's first line of stderr", async () => {
  const f = fake(1, "the box already has text\nsecond line")
  assert.deepEqual(await sendTell("hello", f.run), { ok: false, reason: "the box already has text" })
})

test("a refusal with nothing said still has a reason", async () => {
  const f = fake(2)
  assert.deepEqual(await sendTell("hello", f.run), { ok: false, reason: "babylon tell exited 2" })
})

test("babylon missing from PATH is a refusal too", async () => {
  const r = await sendTell("hello", () => Promise.reject(new Error("spawn babylon ENOENT")))
  assert.equal(r.ok, false)
  assert.match(r.reason, /ENOENT/)
})

test("the house is told through `asterion -- --tell <line>`", async () => {
  const dir = mkdtempSync(join(tmpdir(), "tell-"))
  const log = join(dir, "argv")
  writeFileSync(join(dir, "asterion"), `#!/bin/sh\nprintf '%s\\n' "$@" > ${log}\n`)
  chmodSync(join(dir, "asterion"), 0o755)
  const run = (argv) => new Promise((res, rej) => {
    const p = spawn(argv[0], argv.slice(1), { env: { ...process.env, PATH: `${dir}:${process.env.PATH}` } })
    p.on("error", rej)
    p.on("close", (code) => res({ code, err: "" }))
  })
  assert.deepEqual(await sendTell("buy milk; 'now'", run, "house"), { ok: true })
  assert.deepEqual(readFileSync(log, "utf8").trim().split("\n"), ["--", "--tell", "buy milk; 'now'"])
})
