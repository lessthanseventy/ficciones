# Reshape Slice B: Tracking Is the Lazy Path (auto-promote on first commit)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A chat thread where real work lands becomes a tracked thread automatically — the ticket condenses out of the work; nobody fills out a form.

**Architecture:** `Workline.promote/1` flips an untracked thread to stage `"build"` (slug derived from title, `stage_advanced` event with `promoted` detail, build-stage brief posted). A new self-thread MCP tool `track_thread` exposes it. Both harnesses call it mechanically when a `git commit` succeeds: pi at `turn_end` (scans the turn's entries), claude-code via a PostToolUse hook sibling of the heartbeat. Idempotent everywhere; the server is the single gate.

**Context:** Evidence from the 08-27 session god-view: real work leaves `stage=NULL`, zero events. Design: docs/plans/2026-08-27-clarity-rename-slack-shape-design.md. Conventions to mirror: `Workline.flip/1` (transaction: stage change + `stage_advanced` event), `Brief.stage_message/1` post, slug charset `~r/\A[a-z0-9][a-z0-9-]*\z/`.

---

### Task B1: `Workline.promote/1` (funes, TDD)

Tests (`test/funes/workline_test.exs`, new describe): plain thread → `{:ok, t}` with `stage: "build"`, slug slugified from title (e.g. "Fix the CHAT feed!" → "fix-the-chat-feed"), a `stage_advanced` event with `detail["promoted"] == true` and `from` nil / `to` "build", and a build-stage brief posted to the thread; already-tracked thread → `{:ok, t}` unchanged, no second event; the ROOT machine thread → `{:error, :root_machine_thread}`; slug collision → falls back to `<base>-<thread_id>`; unslugifiable title ("🎉🎉") → `thread-<id>`.

Implementation: `Thread.promote_changeset/2` (sets stage "build" + slug, validates the slug charset); `Workline.promote/1` guards root via `Funes.Channel.machine_thread/0` id compare, wraps flip-style transaction (update + `Dossier.record_event` with `correlation: "workline:<slug>"`, `detail: %{"from" => nil, "to" => "build", "promoted" => true}`), posts `Brief.stage_message/1`. Commit.

### Task B2: `track_thread` MCP tool (funes, TDD)

`Funes.MCP.Tool.TrackThread` — no args, self-thread (identity from frame, like `presence_thinking`). Calls promote on this connection's thread; replies `{stage, slug}`; `:root_machine_thread` and changeset errors as tool errors. Register in `mcp/server.ex` component list. Tests mirror `world_tools_test.exs` style. Commit.

### Task B3: shared commit detector + pi wiring (manos/pi, TDD)

`activity.ts`: pure `isCommitCommand(cmd: string): boolean` (a `git … commit` invocation — word-boundary match, tolerates flags/paths between git and commit, rejects `commit` inside strings like grep patterns — keep it simple: first two non-flag words are `git`/`commit`-ish) and `sawSuccessfulCommit(entries: Entry[]): boolean` (a Bash-ish `tool_use` whose `command` matches, with a following non-error `tool_result`). bun tests for both.

`mcp.ts`: `trackThread(): Promise<void>` calling the tool. `extension.ts`: at `turn_end`, if not already tracked this session and `sawSuccessfulCommit(...)` → `client.trackThread()` (best-effort, silent failure), set a session flag. Commit.

### Task B4: claude-code hook (manos, TDD where pure)

`cc-track.ts`: read PostToolUse JSON from stdin; `tool_name == "Bash"`, `tool_input.command` matches `isCommitCommand`, `tool_response` not errored → `FunesClient` from env (same construction as cc-heartbeat) → `track_thread`. Silent no-op on anything missing. `track-hook.sh` thin wrapper (mirror heartbeat-hook.sh); wire into `launch.sh` `settings_json` PostToolUse list. bun test the stdin-payload matcher (pure part). Commit.

### Task B5: gates

`mise run check` + `mise run flake:check` (launch.sh changed → flake copies it? verify), fix fallout, commit residue.
