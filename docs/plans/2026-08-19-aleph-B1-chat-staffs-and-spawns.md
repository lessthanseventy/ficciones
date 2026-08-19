# B1 — Chat staffs + spawns a coworker on the new thread

> **For Claude:** REQUIRED SUB-SKILL: superpowers:executing-plans / subagent-driven-development.

**Goal:** Typing in the Tlön chat creates a thread, staffs a coworker on it (@-mention wins, else
the configured default), and spawns that coworker as a session **bound to that thread**, so it
answers **on that thread**. Closes the "who am i talking to? → silence" loop end to end.

**Architecture (decided):** the chat tab and the cockpit are separate processes sharing only the
funes DB. So the **chat writes** (thread + lead), the **cockpit spawns** (its render loop sees a
staffed-but-session-less machine thread in the shared DB and spawns the bound coworker, then
injects the opening turn). No cross-process signaling — the DB is the handoff. Reference:
`2026-08-19-aleph-chat-attention-design.md` Revision B.

**Picking rule:** the composer message's first coworker `@`-mention is the pick; with none, the
configured default coworker. (Andrew: "3 with a sprinkle of 2.")

**Scope guard (YAGNI):** B1 supports **claude-launched** coworkers (claude-machine and the
`$TLON_THIRD_AGENT` voice — both use `claude-code/launch.sh`). pi-launched staffing and ongoing
operator↔per-thread-window reply routing are follow-ups (B2 / the sessions index). B1 delivers the
first answer; the sessions index makes it navigable.

---

## Foundation (testable, no live tmux) — do these first, commit, then CHECKPOINT

### Task B1.1: `Aleph.Config.default_coworker/0`

**Files:** Modify `lib/aleph/config.ex`; Test `test/aleph/config_test.exs` (create if absent).

Add a read + writer mirroring `coworker_model/2` / `put_coworker_model/3`, over a top-level
`"default_coworker"` string key, defaulting to `"claude-machine"` when absent/corrupt.

**Step 1 — failing test:**
```elixir
test "default_coworker/1 reads the configured default, else claude-machine" do
  path = tmp_config(%{"default_coworker" => "pi-machine"})
  assert Aleph.Config.default_coworker(path) == "pi-machine"
end

test "default_coworker/1 falls back to claude-machine when unset" do
  assert Aleph.Config.default_coworker(tmp_config(%{})) == "claude-machine"
end
```
(Use the same tmp-file helper pattern the existing config tests use; if none, write one that
`File.write!`s JSON to a `System.tmp_dir!` path.)

**Step 2 — run, watch fail** (`default_coworker/1 undefined`).

**Step 3 — implement:**
```elixir
@default_coworker "claude-machine"

@doc "The configured default coworker handle for new chat threads, or claude-machine."
@spec default_coworker(String.t()) :: String.t()
def default_coworker(path \\ path()) do
  case read(path) do
    %{"default_coworker" => h} when is_binary(h) and h != "" -> h
    _ -> @default_coworker
  end
end

@doc "Persist the default coworker handle."
def put_default_coworker(handle, path \\ path()) when is_binary(handle) do
  read(path) |> Map.put("default_coworker", handle) |> write(path)
end
```
(Confirm `read/1` + the JSON `write` helper names in `config.ex`; match them.)

**Step 4 — run, watch pass. Step 5 — commit** (`aleph: config — default_coworker knob for chat staffing`).

### Task B1.2: pure staffing-pick + `do_submit` staffs the lead

**Files:** Modify `lib/aleph/machine_chat/loop.ex`; Test `test/aleph/machine_chat/*` (new pure test).

1. **Pure pick function** — extract so it's testable without the TTY. In `loop.ex` (or a small new
   `Aleph.MachineChat.Staffing` module if cleaner):
   ```elixir
   @doc "The coworker to staff on a new thread: the first @-mentioned coworker, else the default."
   def pick_coworker(text, default) do
     case Aleph.Mention.mentions(text) do
       [{handle, _window} | _] -> handle
       [] -> default
     end
   end
   ```
   Test it: `pick_coworker("@pi-machine do x", "claude-machine") == "pi-machine"`;
   `pick_coworker("no mention", "claude-machine") == "claude-machine"`;
   `pick_coworker("@andrew hi", "claude-machine") == "claude-machine"` (non-coworker @ ignored).

2. **Wire into `do_submit/2`** (`loop.ex:199`): after the `Channel.post`, resolve
   `handle = pick_coworker(text, Aleph.Config.default_coworker())`, look up the agent with
   `Funes.Staff.agent_by_name(handle)` (skip staffing if nil — coworker never registered), and
   `Funes.Staff.assign(thread, agent)`. Wrap in the existing rescue/catch so a staffing failure
   just clears the box. `Funes.Staff` must be reachable — confirm it's a `Funes` export or add a
   delegate (`:boundary`); if aleph currently can't call `Funes.Staff.assign/2`, add
   `Funes.assign_lead(thread_id, handle)` to `funes.ex` that does the `agent_by_name` +
   `Channel.get`/`assign` and call that instead (cleaner boundary).

**Commit** (`aleph: machine-chat — staff the picked/default coworker as the new thread's lead`).

### Task B1.3: bridge `wake_mentions` to `route/2`

**Files:** Modify `lib/aleph/machine_chat/loop.ex:216` (`wake_mentions/3`).

Resolve the thread's lead and pass it, mirroring the cockpit's Phase-1 change:
```elixir
defp wake_mentions(author, body, thread_id) do
  lead = safe_thread_lead(thread_id)
  for {window, text} <- Mention.route(%{author: author, body: body, thread_id: thread_id}, lead: lead) do
    System.cmd("tmux", ["send-keys", "-t", "tlon:#{window}", "-l", text], stderr_to_stdout: true)
    System.cmd("tmux", ["send-keys", "-t", "tlon:#{window}", "Enter"], stderr_to_stdout: true)
  end
  :ok
rescue
  _ -> :ok
end

defp safe_thread_lead(tid) do
  Funes.thread_lead(tid)
rescue
  _ -> nil
catch
  :exit, _ -> nil
end
```
Note: for a brand-new thread the lead's per-thread window doesn't exist yet, so this wakes nothing
*for fresh threads* — the fresh-thread wake comes from B1.4's spawn+inject. This bridge matters for
threads whose lead already has a live window (the standing coworkers). Keep it for consistency.

**Verify B1.1–B1.3:** `mise run aleph:check` green. **Commit, then CHECKPOINT with Andrew** — the
foundation is in but produces no visible change alone; B1.4 (below) is the fragile live piece.

---

## The live piece (needs Andrew-driven live verify) — B1.4

> **Design simplification (Andrew, 2026-08-19): clean slate, no window-storm qualifier.** The old
> machine threads are disposable — clear them first, so `ensure_thread_sessions` can spawn for ANY
> staffed-but-session-less machine thread with **no `since` marker**. The only pre-existing thread
> after the clear is the standing coworker thread (pi/claude), which is **excluded** because the
> cockpit knows its id (the `:machine` terminal's bound thread — capture it in state at
> `spawn_machine_coworker`, or resolve via `machine_thread_id()` at spawn time and stash it). Keep
> the standing pi/claude and the embedded-center bootstrap AS-IS for B1 (retiring them for a
> chat-first center is the Rev B endgame, not B1).
>
> **Clean-slate step (once, before turning B1.4 on):** close/delete the existing machine-scope
> threads in the cockpit's `.dev` db (:4041). Prefer a small `mise`/mix helper or a funes call over
> raw SQL; if none exists, add `mise run aleph:clear-machine-threads` (a tiny task that opens the
> `.dev` Repo and deletes `scope=="machine"` threads + their messages). Andrew runs it live.

### Task B1.4: cockpit spawns a bound session for staffed-but-session-less threads

**Files:** Modify `lib/aleph/cockpit.ex` (new `ensure_thread_sessions` pass + generalize
`spawn_agent_window`).

1. **Generalize the spawn** — `spawn_agent_window(agent, window, thread_id \\ machine_thread_id())`
   → `Spawn.join(thread_id, agent, mandate: "machine")` (currently hard-codes `machine_thread_id()`
   at `cockpit.ex:1075-1076`). This is the hinge: same launcher, but `FUNES_THREAD=thread_id`.

2. **New ensure pass** (added to render's Tlön preamble, after `ensure_log_window`):
   ```elixir
   defp ensure_thread_sessions(%{active_key: :tlon} = state) do
     for t <- Funes.staffed_threads_without_window(claude_launched_handles(), tlon_window_names()) do
       spawn_agent_window(t.lead, "t#{t.id}", t.id)     # window named per-thread
       inject_opening_turn(t)                            # send-keys the latest operator msg
     end
     state
   end
   defp ensure_thread_sessions(state), do: state
   ```
   - Add a funes read `staffed_threads_without_window/2` (or do the filtering aleph-side from
     `Funes` reads): machine-scope threads with a non-nil lead whose per-thread window name
     (`"t#{id}"`) is not in `tlon_tabs()`. Restrict to leads whose launcher is claude
     (`claude-machine` + `$TLON_THIRD_AGENT`); skip pi-led for B1.
   - **Dedup / no spawn-storm:** gate on the window's absence (like `ensure_claude_coworker`), and
     add a short per-thread backoff map (mirror `machine_retry_at`) so a failing spawn doesn't
     retry every render.

3. **`inject_opening_turn/1`** — after the window exists, `tmux send-keys` the thread's latest
   operator message as `[funes thread #N] andrew: <body>` into `tlon:t#{N}`, ONCE. Boot timing is
   the fragile part: claude isn't ready to receive keys the instant `new-window` returns. Options
   to try live: (a) inject on the render AFTER the window first appears in `tlon_tabs()` (two-phase,
   tracked in state), or (b) a brief settle before the send-keys. Mark this as the live-iteration
   knob.

4. **Register the per-thread window with the mention router** so a later operator reply to thread N
   routes to `t#{N}` — needs `Aleph.Mention.coworkers()` to become dynamic (thread→window), OR the
   sessions index (B2) to own routing. **Out of B1 scope**; note it. B1's win is the FIRST answer.

**Verify B1.4 (Andrew, live — out of headless suite):** `aleph:reset && uqbar`; in Tlön chat type a
message (bare → default coworker; `@pi-machine …` → that one, once pi-launch supported); watch a
`t<N>` window spawn, the coworker answer ON thread N (visible in the chat feed). Iterate on the
inject timing until the opening turn lands reliably.

---

## Sequencing & principles

1. B1.1–B1.3 first (testable foundation) → commit → **checkpoint** (no visible change yet).
2. B1.4 is the live piece — build, then Andrew live-verifies + iterates the inject timing.
3. Ongoing reply routing to per-thread windows + pi-launched staffing = B2 / follow-ups.
4. TDD the pure bits (Config, `pick_coworker`); the tmux/boot pieces verify live. Green
   `aleph:check` before every commit. Subagent commits carry the Sonnet trailer; my own carry Opus.
