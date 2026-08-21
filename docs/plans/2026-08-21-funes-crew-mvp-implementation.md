# funes crew MVP — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship the smallest end-to-end funes-crew slice — a Claude leader spawns one `reviewer`
coworker onto a task thread; the reviewer reviews a diff, is *structurally unable to write*, and
ESCALATEs a proposed fix to the leader over the mention bus; the leader judges (risk × operator
presence) and either applies-on-behalf or surfaces to the operator — with every hand-off captured
as a funes thread message.

**Architecture:** Four seams, all reusing machinery that already exists.
1. A new **`reviewer` profile** in `Aleph.Profiles` (a `%Profile{}` like `tertius`), whose
   permission policy denies the `write`/`edit` tools and the obvious bash-write patterns — the
   *structural* half of the gate (pi-permission-system per-tool surfaces; verified: built-in file
   writers are exactly `write` and `edit`, reads are `read`/`grep`/`find`/`ls`).
2. A new **`Aleph.Crew`** module: a role registry (`reviewer` today), a deterministic per-thread
   window name (`crew_window/2` → `"r<tid>"`), and pure tmux command builders for spawn/kill. Its
   IO wrappers mint identity via `Funes.MCP.Spawn.join/3` (`FUNES_AUTHOR="reviewer-machine"`) and
   spawn onto the *same* standing `tlon` tmux server the cockpit uses.
3. **`Aleph.Mention`** gains crew-role resolution keyed on the message's thread id
   (`reviewer-machine` on thread 42 → window `r42`). Because the cockpit's existing
   `mention_notify` delivers to *whatever window `route/2` returns*, and the staffed-thread redirect
   already rewrites the lead's handle onto `t<tid>`, this one change makes leader↔reviewer routing
   work with **zero cockpit changes**.
4. Two **mix tasks** (`aleph.crew.spawn`, `aleph.crew.kill`) — the leader's control surface (it is
   an agent in a tmux window with bash, not the operator pressing cockpit keys). Plus a **leader
   playbook** doc encoding the ESCALATE protocol, the risk×presence judgment, and teardown.

The **gate** = the reviewer's write-deny policy (structural floor) + the `@<leader> ESCALATE apply:`
mention protocol (persona-parsed by the leader). **Presence + wake need no new code:** the leader
reads operator recency from funes messages it already fetches, and "surface" is a marked post the
existing `desktop_notify` wakes on.

**Tech Stack:** Elixir/OTP (aleph on funes, `:boundary`-enforced), pi coworker profiles
(`Aleph.Profiles` → `~/.pi/profiles/<name>/`), `@gotgenes/pi-permission-system` flat policy, tmux
(`-L aleph-tertius`, session `tlon`), funes MCP (`Funes.MCP.Spawn`).

**Contract:** `docs/plans/2026-08-21-funes-crew-mvp-contract.md`. **Design:**
`docs/plans/2026-08-20-funes-crew-plugin-design.md`, `…-value-feedback-loop-design.md`.

**Decisions resolved during planning (were "Open" in the contract):**
- **Spawn seam** → leader-invoked mix task CLI (`mix aleph.crew.spawn` / `.kill`). Chosen over
  cockpit-mediated markers and a funes MCP verb: the leader has bash and lives in the standing
  `tlon` tmux server already, so the CLI reuses the profile+tmux machinery with no new cross-service
  control channel. Mention resolution is *convention-based* (`role`+`tid` → window), so it needs no
  cross-node registry.
- **Operator presence** → funes-recency heuristic (did a human post on this thread in the last
  ~10 min, read via the leader's `get_dossier`/messages). No new attention bus. Matches the
  contract's "focus flag + recent activity is enough."
- **ESCALATE parsing** → leader-side persona instruction parsing the `@<leader> ESCALATE apply:`
  marker (MVP). A structured funes verb is phase-2.

**Key seam references (verified 2026-08-21):**
- `Aleph.Profile` struct — `modules/aleph/lib/aleph/profiles.ex:24-44` (`name, drop_extensions,
  add_extensions, mcp, model, system_prompt, sandbox, permissions`).
- `@profiles`, `@tertius_role`, `@tlon_funes_mcp`, `@tlon_sandbox`, `@tlon_permissions` —
  `profiles.ex:290-343` / `137-281`. `fetch/1` merges operator overrides (`profiles.ex:359`).
  `materialise!/2` writes the config dir incl. `extensions/pi-permission-system/config.json`
  (`profiles.ex:474-514`, permission write at `491-495`).
- `Aleph.Mention` — `modules/aleph/lib/aleph/mention.ex`: `@base_coworkers` (`:23`), `coworkers/0`
  (`:38`), `mentions/1` (`:50`), `route/2` (`:81`), `redirect/3` staffed rewrite (`:101`).
- Cockpit mention delivery — `modules/aleph/lib/aleph/cockpit.ex`: `mention_notify/2` (`:488`),
  `delivery_target/3` staffed-window decision (`:516`), `inject_turn/2` send-keys (`:560`),
  `tlon_window_index/1` (`:548`), `tlon_tmux/1` socket (`:1657`).
- Tmux window spawn template — cockpit `spawn_agent_window/3` (`:1544`), `profile_launcher/1`
  (`:1614`), `pi_command/1` (`:1597`), `funes_identity_flags/0` (`:1634`), `@tlon_session` /
  `@machine_window`.
- Identity mint — `Funes.MCP.Spawn.join/3` (`modules/funes/lib/funes/mcp/spawn.ex:73`), sets
  `FUNES_AUTHOR="#{agent.name}"` (`:138`) and staffs the agent on the thread (`ensure/3` `:51`).
- pi-permission-system per-tool surfaces — the config's top-level keys are surface names; built-in
  file writers are `write`/`edit`, reads are `read`/`grep`/`find`/`ls`
  (`@gotgenes/pi-permission-system/src/access-intent/path-surfaces.ts`, `config-schema.ts:87`). A
  `path` deny cannot be overridden by a per-tool allow (cross-cutting floor).

---

## Topology (how the pieces sit at runtime)

```
funes thread T ("review PR #42")  ── lead = claude-machine (existing staffing default)
  ├── tmux window  tT   → real Claude (the LEADER), spawned by the cockpit's ensure_thread_sessions
  └── tmux window  rT   → pi reviewer (glm-5.2), spawned by `mix aleph.crew.spawn reviewer T`
        both on tmux server  -L aleph-tertius , session  tlon
        both are funes citizens on thread T (distinct FUNES_AUTHOR)

leader posts  "@reviewer-machine review the diff in <ref>"
   → mention_notify → route resolves reviewer-machine@T → window rT → send-keys into rT
reviewer posts "@claude-machine ESCALATE apply: <patch>"
   → mention_notify → delivery_target(T)=claude-led+ready → staffed_window "tT"
   → route: target claude-machine→hronir, redirect(hronir==lead ∧ staffed) → tT → send-keys into tT
leader judges (risk × presence-from-funes-recency):
   routine + operator away → applies (leader has write) → posts "applied on your behalf: …"
   risky OR operator present → posts "@operator NEEDS DECISION: …" (desktop_notify wakes them)
leader done → `mix aleph.crew.kill T` → tmux kill-window rT
```

No cross-node registry: `rT` is a pure function of (`reviewer`, `T`), computed identically by the
spawner (mix task, its own BEAM) and the router (cockpit BEAM).

---

## Task 1: `Aleph.Crew` role registry + `crew_window/2`

**Files:**
- Create: `modules/aleph/lib/aleph/crew.ex`
- Test: `modules/aleph/test/aleph/crew_test.exs`

**Step 1: Write the failing test**

```elixir
# modules/aleph/test/aleph/crew_test.exs
defmodule Aleph.CrewTest do
  use ExUnit.Case, async: true
  alias Aleph.Crew

  describe "roles/0 and role/1" do
    test "reviewer is a known role with its handle, window prefix, and profile" do
      assert %{handle: "reviewer-machine", window_prefix: "r", profile: "reviewer"} =
               Crew.role("reviewer")
    end

    test "an unknown role is nil" do
      assert Crew.role("nope") == nil
    end

    test "roles/0 lists the MVP crew" do
      assert Crew.roles() |> Map.keys() |> Enum.sort() == ["reviewer"]
    end
  end

  describe "crew_window/2" do
    test "names a per-thread window from role prefix + thread id" do
      assert Crew.crew_window("reviewer", 42) == "r42"
    end

    test "accepts a string thread id" do
      assert Crew.crew_window("reviewer", "42") == "r42"
    end

    test "unknown role raises (a caller must pass a real role)" do
      assert_raise ArgumentError, fn -> Crew.crew_window("planner", 42) end
    end
  end

  describe "handle_role/1 (reverse: a funes handle → its role key)" do
    test "resolves the reviewer handle" do
      assert Crew.handle_role("reviewer-machine") == "reviewer"
    end

    test "a non-crew handle is nil" do
      assert Crew.handle_role("claude-machine") == nil
    end
  end
end
```

**Step 2: Run it, verify it fails**

Run: `cd modules/aleph && mise exec -- mix test test/aleph/crew_test.exs`
Expected: FAIL — `Aleph.Crew` undefined.

**Step 3: Write the minimal implementation**

```elixir
# modules/aleph/lib/aleph/crew.ex
defmodule Aleph.Crew do
  @moduledoc """
  The funes crew — roles the leader spawns onto a task thread and tears down when done.

  A **role** is a seat, not an identity: a `%{handle, window_prefix, profile}` naming the funes
  author the seat posts as, the tmux window it runs in, and the `Aleph.Profile` that materialises
  its pi config. MVP staffs one role, `reviewer`.

  The per-thread window name (`crew_window/2`) is a PURE function of (role, thread id), so the
  spawner (the `mix aleph.crew.*` task, in its own BEAM) and the mention router (in the cockpit
  BEAM) agree on `r<tid>` with no shared state — that is what lets a leader-invoked CLI spawn a
  window the running cockpit can route `@reviewer-machine` to.

  Spawn/teardown (the IO + tmux builders) live below; see `spawn/3` and `kill/2`.
  """

  @roles %{
    "reviewer" => %{handle: "reviewer-machine", window_prefix: "r", profile: "reviewer"}
  }

  @doc "The MVP crew: role key → %{handle, window_prefix, profile}."
  @spec roles() :: %{String.t() => map()}
  def roles, do: @roles

  @doc "A role by key, or nil."
  @spec role(String.t()) :: map() | nil
  def role(key), do: Map.get(@roles, key)

  @doc "The funes handle → role key (reverse of `role/1`'s handle), or nil for a non-crew handle."
  @spec handle_role(String.t()) :: String.t() | nil
  def handle_role(handle) do
    Enum.find_value(@roles, fn {key, %{handle: h}} -> if h == handle, do: key end)
  end

  @doc """
  The tmux window a role runs in on a given thread: `<prefix><thread_id>` (e.g. `"r42"`). Pure and
  deterministic — the spawner and the router both compute it. Raises on an unknown role.
  """
  @spec crew_window(String.t(), integer() | String.t()) :: String.t()
  def crew_window(role_key, thread_id) do
    case role(role_key) do
      %{window_prefix: p} -> p <> to_string(thread_id)
      nil -> raise ArgumentError, "unknown crew role: #{inspect(role_key)}"
    end
  end
end
```

**Step 4: Run, verify pass**

Run: `cd modules/aleph && mise exec -- mix test test/aleph/crew_test.exs`
Expected: PASS.

**Step 5: Commit**

```bash
git add modules/aleph/lib/aleph/crew.ex modules/aleph/test/aleph/crew_test.exs
git commit -F - <<'EOF'
aleph: Aleph.Crew role registry + deterministic per-thread window names

The funes-crew MVP's pure core: role→{handle,window_prefix,profile} and
crew_window/2 (role+thread_id → "r<tid>"), computed identically by the CLI
spawner and the cockpit mention router so no cross-node registry is needed.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 2: `Aleph.Mention` crew-role resolution (per thread)

Make `route/2` resolve crew handles against the message's thread id so `@reviewer-machine` on
thread 42 targets window `r42`, and the reviewer's own posts are loop-guarded. Everything else
(delivery, the staffed redirect, ESCALATE→`tT`) already works.

**Files:**
- Modify: `modules/aleph/lib/aleph/mention.ex` (`coworkers/0`/`mentions/1` are thread-agnostic; add a
  thread-aware resolver used by `route/2`).
- Test: `modules/aleph/test/aleph/mention_test.exs` (extend; keep existing cases green).

**Step 1: Write the failing tests**

```elixir
# add to modules/aleph/test/aleph/mention_test.exs
describe "crew role resolution (per-thread windows)" do
  test "@reviewer-machine on a thread routes to that thread's r<id> window" do
    row = %{author: "claude-machine", body: "@reviewer-machine review the diff in HEAD~1", thread_id: 42}
    assert Aleph.Mention.route(row, lead: "claude-machine", staffed_window: "t42") ==
             [{"r42", "[funes thread #42] claude-machine: @reviewer-machine review the diff in HEAD~1"}]
  end

  test "a reviewer's own post never wakes its own r<id> window (loop guard)" do
    row = %{author: "reviewer-machine", body: "@reviewer-machine note to self", thread_id: 42}
    assert Aleph.Mention.route(row, lead: "claude-machine", staffed_window: "t42") == []
  end

  test "reviewer ESCALATE to the leader lands on the leader's staffed window" do
    row = %{author: "reviewer-machine", body: "@claude-machine ESCALATE apply: <patch>", thread_id: 42}
    assert Aleph.Mention.route(row, lead: "claude-machine", staffed_window: "t42") ==
             [{"t42", "[funes thread #42] reviewer-machine: @claude-machine ESCALATE apply: <patch>"}]
  end

  test "a crew handle without a thread id does not resolve (no tid → no per-thread window)" do
    row = %{author: "claude-machine", body: "@reviewer-machine hi", thread_id: nil}
    assert Aleph.Mention.route(row, lead: "claude-machine") == []
  end
end
```

**Step 2: Run, verify the new cases fail** (existing tertius/hronir cases must still pass)

Run: `cd modules/aleph && mise exec -- mix test test/aleph/mention_test.exs`
Expected: the four new tests FAIL (crew handle resolves to `[]` today); all prior tests PASS.

**Step 3: Implement — thread-aware resolution in `route/2`**

Replace the body of `route/2` and add crew-aware resolvers. `mentions/1` and `coworkers/0` stay for
the static base; add a private `resolve/2` that layers crew windows on top when a `tid` is present.

```elixir
# in modules/aleph/lib/aleph/mention.ex
alias Aleph.Crew

def route(%{author: author, body: body, thread_id: tid}, opts) do
  author_window = resolve(author, tid)
  targets = mention_targets(body, opts[:lead], tid)
  lead_window = opts[:lead] && resolve(opts[:lead], tid)
  staffed = opts[:staffed_window]

  for_result =
    for window <- targets, window != author_window do
      {redirect(window, lead_window, staffed),
       "[funes thread #{tid_str(tid)}] #{display_author(author)}: #{one_line(body)}"}
    end

  Enum.uniq(for_result)
end

def route(_, _), do: []

# A handle → window: the static base map, else a crew role's per-thread window (`r<tid>`), else nil.
# Crew roles only resolve WITH a thread id — their window is per-thread, so a nil tid (standing
# thread, uqbar console) leaves a crew handle unresolved and it is simply not woken.
defp resolve(handle, tid) do
  cond do
    w = coworkers()[handle] -> w
    role = tid && Crew.handle_role(handle) -> Crew.crew_window(role, tid)
    true -> nil
  end
end

# The windows to wake: the @-mentioned handles resolved for THIS thread, or — when none are named —
# the thread's lead coworker's window (nil/unknown → []).
defp mention_targets(body, lead, tid) do
  case mentioned_handles(body) do
    [] -> lead |> lead_window(tid) |> List.wrap()
    handles -> handles |> Enum.map(&resolve(&1, tid)) |> Enum.reject(&is_nil/1)
  end
end

defp lead_window(nil, _tid), do: nil
defp lead_window(handle, tid), do: resolve(handle, tid)

# Every @handle token in the body (deduped, first-seen). Resolution to windows happens per-thread
# in `resolve/2`; this stays purely lexical so crew handles are seen even though they are not in
# the static `coworkers/0` map.
defp mentioned_handles(body) do
  ~r/@([\w-]+)/
  |> Regex.scan(body, capture: :all_but_first)
  |> List.flatten()
  |> Enum.uniq()
end
```

> Note: the public `mentions/1` (returns `[{handle, window}]` from the static map) is kept for its
> existing callers/tests. If nothing outside the module still uses it after this change, delete it
> in a follow-up — do not expand its contract to be thread-aware (that is `resolve/2`'s job).

**Step 4: Run, verify all pass**

Run: `cd modules/aleph && mise exec -- mix test test/aleph/mention_test.exs`
Expected: PASS (new + existing).

**Step 5: Commit**

```bash
git add modules/aleph/lib/aleph/mention.ex modules/aleph/test/aleph/mention_test.exs
git commit -F - <<'EOF'
aleph: mention router resolves crew handles to per-thread windows

route/2 now resolves @<crew>-machine against the message's thread id via
Aleph.Crew (reviewer-machine@42 → r42), layered over the static tertius/hronir
map. The staffed-window redirect already sends the reviewer's @<leader>
ESCALATE onto t<tid>, so leader↔reviewer routing works with no cockpit change.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 3: `reviewer` profile + write-deny permission policy

Add `@reviewer_permissions` (write/edit tools + obvious bash-writes → deny; reads/git-read →
allow; `yoloMode: true`; catastrophic deny-floor preserved) and a `reviewer` `%Profile{}`, and
register it in `@profiles`. This is the *structural* half of the gate.

**Files:**
- Modify: `modules/aleph/lib/aleph/profiles.ex` (add `@reviewer_role`, `@reviewer_permissions`,
  the `%Profile{name: "reviewer"}` entry in `@profiles`).
- Test: `modules/aleph/test/aleph/profiles_test.exs` (extend).

**Step 1: Write the failing tests**

```elixir
# add to modules/aleph/test/aleph/profiles_test.exs
describe "the reviewer profile — the write-deny gate" do
  test "reviewer is a fetchable profile on glm-5.2" do
    p = Aleph.Profiles.fetch("reviewer")
    assert %Aleph.Profile{name: "reviewer"} = p
    assert p.model.model == "glm-5.2"
  end

  test "its permission policy DENIES the write and edit tools but ALLOWS reads" do
    perms = Aleph.Profiles.fetch("reviewer").permissions
    assert perms["permission"]["write"] == "deny"
    assert perms["permission"]["edit"] == "deny"
    # reads fall through the "*" => "allow" fallback (no read/grep/find/ls deny)
    assert perms["permission"]["*"] == "allow"
    refute Map.has_key?(perms["permission"], "read")
  end

  test "the obvious bash-write patterns are denied" do
    bash = Aleph.Profiles.fetch("reviewer").permissions["permission"]["bash"]
    for pat <- ["* > *", "* >> *", "sed -i*", "tee *", "dd *"], do: assert bash[pat] == "deny"
  end

  test "the catastrophic deny-floor is preserved from @tlon_permissions" do
    bash = Aleph.Profiles.fetch("reviewer").permissions["permission"]["bash"]
    assert bash["rm -rf /*"] == "deny"
    assert bash["sudo *"] == "deny"
  end

  test "yoloMode is on so allowed reads never stall on an ask" do
    assert Aleph.Profiles.fetch("reviewer").permissions["yoloMode"] == true
  end

  test "materialise! writes the write-deny into the pi-permission-system config" do
    root = Path.join(System.tmp_dir!(), "crew-mat-#{System.unique_integer([:positive])}")
    base = Path.join(root, "agent")
    File.mkdir_p!(base)
    File.write!(Path.join(base, "settings.json"), ~s({"extensions":[]}))
    File.write!(Path.join(base, "mcp.json"), ~s({"mcpServers":{}}))

    dir = Aleph.Profiles.materialise!(Aleph.Profiles.fetch("reviewer"), base: base, root: Path.join(root, "profiles"))
    cfg = Path.join(dir, "extensions/pi-permission-system/config.json") |> File.read!() |> Jason.decode!()
    assert cfg["permission"]["write"] == "deny"
    assert cfg["permission"]["edit"] == "deny"
  end
end
```

**Step 2: Run, verify fail**

Run: `cd modules/aleph && mise exec -- mix test test/aleph/profiles_test.exs`
Expected: FAIL — `fetch("reviewer")` returns nil.

**Step 3: Implement**

Add near `@tlon_permissions` (after line ~281) and `@tertius_role` (after ~324):

```elixir
# in modules/aleph/lib/aleph/profiles.ex

# The reviewer's permission policy — @tlon_permissions with the WRITE FENCE added: the built-in
# file-writers (`write`, `edit`) and the obvious bash-write forms are denied, so a reviewer
# STRUCTURALLY cannot land a change (its only path is to escalate). Reads/greps/git-read fall
# through the "*" => "allow" fallback; yoloMode keeps those from stalling on an ask. The
# catastrophic deny-floor rides along from @tlon_permissions unchanged. See the crew contract §A.
#
# pi-permission-system per-tool surfaces: top-level keys are surface names; `write`/`edit` are the
# only built-in file WRITERS (reads are read/grep/find/ls), and a per-tool deny needs no path glob.
# Bash writes are token-gated, so we deny the common redirect/in-place forms — the airtight fence is
# the tool deny; the bash patterns are belt-and-suspenders for the MVP (the model-judge for the
# ambiguous middle is phase-2).
@reviewer_permissions put_in(@tlon_permissions, ["permission"], Map.merge(@tlon_permissions["permission"], %{
  "write" => "deny",
  "edit" => "deny",
  "bash" => Map.merge(@tlon_permissions["permission"]["bash"], %{
    "* > *" => "deny",
    "* >> *" => "deny",
    "sed -i*" => "deny",
    "tee *" => "deny",
    "dd *" => "deny"
  })
}))

@reviewer_role """
You are reviewer-machine, a code REVIEWER on this funes task thread. Read the diff you are asked to
review (use `git diff`/`git show` — you have repo READ access) and post terse, high-signal findings
as thread messages. You do NOT ship changes: you CANNOT write files (the write/edit tools are denied
to you, by policy — do not fight it). When a fix is warranted, post the patch and escalate it to the
thread's leader with a single line:

    @<leader> ESCALATE apply: <unified diff or exact change>

Then STOP and wait for the leader's verdict. If a write is denied, that is expected — never retry
it; escalate instead. Attribute nothing to yourself that you did not actually verify. Be brief; a
review nobody reads is worse than none.
"""
```

Then add to `@profiles` (after the `tertius` entry, `profiles.ex:342`):

```elixir
    %Profile{
      name: "reviewer",
      drop_extensions: [],
      add_extensions: [@footer_extension],
      mcp: @tlon_funes_mcp,
      model: %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"},
      sandbox: @tlon_sandbox,
      permissions: @reviewer_permissions,
      system_prompt: @reviewer_role
    }
```

> The `@reviewer_role` prompt names `@<leader>` literally; the concrete leader handle
> (`claude-machine` in the MVP) is supplied by the spawn task's opening turn (Task 5), so the prompt
> stays role-generic. The reviewer's funes surface reuses `@tlon_funes_mcp` (it already carries
> `post_message`, `bank_fact`, `record_check`, `raise_issue`, `get_dossier` — the contract's set;
> the extra `record_done`/`propose_habit` are harmless).

**Step 4: Run, verify pass**

Run: `cd modules/aleph && mise exec -- mix test test/aleph/profiles_test.exs`
Expected: PASS.

**Step 5: Commit**

```bash
git add modules/aleph/lib/aleph/profiles.ex modules/aleph/test/aleph/profiles_test.exs
git commit -F - <<'EOF'
aleph: reviewer profile — the structural write-deny half of the crew gate

A new %Profile{name: "reviewer"} (glm-5.2, @tlon_sandbox, @tlon_funes_mcp) whose
permission policy denies the write/edit tools and the obvious bash-write forms
while leaving reads/git allowed — so a reviewer cannot land a change and its only
path is to ESCALATE. Catastrophic deny-floor preserved from @tlon_permissions.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 4: `Aleph.Crew` spawn/kill command builders (pure)

Pure tmux argv + boot-script builders — no IO. They mirror the cockpit's `spawn_agent_window/3`
(`cockpit.ex:1544`) but target a crew role's `r<tid>` window and use the profile launcher.

**Files:**
- Modify: `modules/aleph/lib/aleph/crew.ex`
- Test: `modules/aleph/test/aleph/crew_test.exs` (extend)

**Step 1: Write the failing tests**

```elixir
# add to modules/aleph/test/aleph/crew_test.exs
describe "spawn_argv/3 and boot_script/2 (pure tmux builders)" do
  test "spawn_argv targets the tlon session on the aleph-tertius socket, window r<id>, detached" do
    argv = Crew.spawn_argv("reviewer", 42, "boot-script-here")
    assert argv == [
             "-L", "aleph-tertius",
             "new-window", "-d", "-t", "tlon", "-n", "r42", "boot-script-here"
           ]
  end

  test "boot_script sources the funes exports then execs the reviewer profile launcher" do
    script = Crew.boot_script("export FUNES_THREAD=\"42\"", "tmux -L aleph-reviewer … 'pi …'")
    assert script =~ "export TERM=xterm-256color"
    assert script =~ "export FUNES_THREAD=\"42\""
    assert String.contains?(script, "\nexec tmux -L aleph-reviewer")
  end

  test "kill_argv removes the role's window on the same server" do
    assert Crew.kill_argv("reviewer", 42) ==
             ["-L", "aleph-tertius", "kill-window", "-t", "tlon:r42"]
  end
end
```

> The `aleph-tertius` socket comes from `Aleph.Profiles.socket(Aleph.Space.fetch(:tlon).coworker)`
> — same derivation the cockpit uses in `tlon_tmux/1` (`cockpit.ex:1657`). Assert against the
> resolved value; if `Space.fetch(:tlon).coworker` is not `"tertius"` in the test env, compute the
> expected socket from that call rather than hardcoding.

**Step 2: Run, verify fail**

Run: `cd modules/aleph && mise exec -- mix test test/aleph/crew_test.exs`
Expected: FAIL — builders undefined.

**Step 3: Implement**

```elixir
# in modules/aleph/lib/aleph/crew.ex
alias Aleph.{Profiles, Space}

@tlon_session "tlon"

@doc "The tmux server socket the Tlön coworkers share (`aleph-<tlon coworker>`), e.g. `aleph-tertius`."
@spec tlon_socket() :: String.t()
def tlon_socket, do: Profiles.socket(Space.fetch(:tlon).coworker)

@doc "The `tmux` argv to spawn a role's per-thread window (detached) running `script`."
@spec spawn_argv(String.t(), integer() | String.t(), String.t()) :: [String.t()]
def spawn_argv(role_key, thread_id, script) do
  ["-L", tlon_socket(), "new-window", "-d", "-t", @tlon_session,
   "-n", crew_window(role_key, thread_id), script]
end

@doc "The `tmux` argv to tear down a role's per-thread window."
@spec kill_argv(String.t(), integer() | String.t()) :: [String.t()]
def kill_argv(role_key, thread_id) do
  ["-L", tlon_socket(), "kill-window", "-t", "#{@tlon_session}:#{crew_window(role_key, thread_id)}"]
end

@doc """
The window's boot script: set TERM, source the funes `exports` block (so `${FUNES_MCP_URL}` etc.
reach pi's env), then `exec` the profile launcher. Mirrors `Cockpit.spawn_agent_window/3`.
"""
@spec boot_script(String.t(), String.t()) :: String.t()
def boot_script(exports, launcher) do
  "export TERM=xterm-256color\n" <> exports <> "\nexec " <> launcher
end
```

**Step 4: Run, verify pass**

Run: `cd modules/aleph && mise exec -- mix test test/aleph/crew_test.exs`
Expected: PASS.

**Step 5: Commit**

```bash
git add modules/aleph/lib/aleph/crew.ex modules/aleph/test/aleph/crew_test.exs
git commit -F - <<'EOF'
aleph: Aleph.Crew pure tmux spawn/kill builders

spawn_argv/kill_argv target the shared aleph-tertius tlon server + the role's
r<tid> window; boot_script sources funes exports then execs the profile
launcher. Pure — mirrors Cockpit.spawn_agent_window with a role window.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 5: `Aleph.Crew.spawn/3` + `kill/2` (IO: identity + tmux + opening turn)

The IO wrappers: mint `reviewer-machine` identity on the task thread, materialise the profile,
spawn the window, and inject the leader's opening assignment after a settle delay (mirroring the
cockpit's two-phase opening turn). tmux/command execution is injected via app env so the seam is
testable headless (same pattern as `:spawn_agent`/`:spawn_launcher`).

**Files:**
- Modify: `modules/aleph/lib/aleph/crew.ex`
- Test: `modules/aleph/test/aleph/crew_test.exs` (extend)

**Step 1: Write the failing test** (inject a fake command runner + fake identity minter)

```elixir
# add to modules/aleph/test/aleph/crew_test.exs
describe "spawn/3 (IO seam, injected runner)" do
  setup do
    test_pid = self()
    # fake tmux runner: records argv, returns success
    Application.put_env(:aleph, :crew_cmd, fn "tmux", argv, _opts ->
      send(test_pid, {:tmux, argv}); {"", 0}
    end)
    # fake identity minter: asserts author + thread, returns a canned exports block
    Application.put_env(:aleph, :crew_join, fn thread_id, author, opts ->
      send(test_pid, {:join, thread_id, author, opts})
      {:ok, %{exports: ~s(export FUNES_THREAD="#{thread_id}"\nexport FUNES_AUTHOR="#{author}")}}
    end)
    on_exit(fn ->
      Application.delete_env(:aleph, :crew_cmd)
      Application.delete_env(:aleph, :crew_join)
    end)
    :ok
  end

  test "mints reviewer-machine identity on the thread and spawns the r<id> window" do
    assert {:ok, "r42"} = Aleph.Crew.spawn("reviewer", 42, "review HEAD~1", inject: false)
    assert_receive {:join, 42, "reviewer-machine", opts}
    assert opts[:mandate] == "machine"
    assert_receive {:tmux, ["-L", _sock, "new-window", "-d", "-t", "tlon", "-n", "r42", script]}
    assert script =~ ~s(export FUNES_AUTHOR="reviewer-machine")
    assert script =~ "\nexec "
  end

  test "an unknown role is an error, no spawn" do
    assert {:error, {:unknown_role, "planner"}} = Aleph.Crew.spawn("planner", 42, "x")
  end
end

describe "kill/2 (IO seam)" do
  test "kills the role window via the injected runner" do
    test_pid = self()
    Application.put_env(:aleph, :crew_cmd, fn "tmux", argv, _ -> send(test_pid, {:tmux, argv}); {"", 0} end)
    on_exit(fn -> Application.delete_env(:aleph, :crew_cmd) end)
    assert :ok = Aleph.Crew.kill("reviewer", 42)
    assert_receive {:tmux, ["-L", _, "kill-window", "-t", "tlon:r42"]}
  end
end
```

**Step 2: Run, verify fail**

Run: `cd modules/aleph && mise exec -- mix test test/aleph/crew_test.exs`
Expected: FAIL — `spawn/3`/`kill/2` undefined.

**Step 3: Implement**

```elixir
# in modules/aleph/lib/aleph/crew.ex

# The reviewer runs on the SAME funes the cockpit uses (aleph's :4041/.dev) — the injected minter
# defaults to Funes.MCP.Spawn.join, which reads :funes/:mcp_port from the running app config, so a
# `mix aleph.crew.*` task inherits aleph's funes port/db just by booting the aleph app.
defp cmd_runner, do: Application.get_env(:aleph, :crew_cmd, &System.cmd/3)
defp joiner, do: Application.get_env(:aleph, :crew_join, &Funes.MCP.Spawn.join/3)

# Wait between window boot and injecting the opening turn — the profile pi's TUI must settle before
# send-keys, same reason as Cockpit's @opening_submit_delay_ms two-phase inject.
@opening_settle_ms 1_500

@doc """
Spawn `role_key` onto task `thread_id` as a funes citizen, then inject the leader's `task` as its
opening turn. Returns `{:ok, window}`. `opts[:inject]` (default true) can be set false in tests to
skip the timed send-keys.
"""
@spec spawn(String.t(), integer() | String.t(), String.t(), keyword()) ::
        {:ok, String.t()} | {:error, term()}
def spawn(role_key, thread_id, task, opts \\ []) do
  with %{handle: handle, profile: profile_name} <- role(role_key) || {:error, {:unknown_role, role_key}},
       %Aleph.Profile{} = profile <- Profiles.fetch(profile_name),
       _dir <- Profiles.materialise!(profile),
       {:ok, %{exports: exports}} <- joiner().(thread_id, handle, mandate: "machine") do
    window = crew_window(role_key, thread_id)
    script = boot_script(exports, Aleph.Cockpit.profile_launcher(profile))
    {_out, 0} = cmd_runner().("tmux", spawn_argv(role_key, thread_id, script), stderr_to_stdout: true)
    if Keyword.get(opts, :inject, true), do: inject_opening(window, opening_turn(thread_id, task))
    {:ok, window}
  else
    {:error, _} = err -> err
    nil -> {:error, {:unknown_role, role_key}}
    other -> {:error, other}
  end
end

@doc "Tear down a role's window on a thread. Best-effort; a missing window is not an error."
@spec kill(String.t(), integer() | String.t()) :: :ok
def kill(role_key, thread_id) do
  _ = cmd_runner().("tmux", kill_argv(role_key, thread_id), stderr_to_stdout: true)
  :ok
end

# The opening assignment the leader hands the reviewer. Names the leader handle so the reviewer's
# @<leader> ESCALATE resolves — MVP leader is claude-machine (the task thread's staffed lead).
defp opening_turn(thread_id, task) do
  "You are reviewing on funes thread ##{thread_id}. Leader handle: claude-machine. " <>
    "Task: #{task}. Read the diff (git diff/show), post findings, and escalate any fix per your protocol."
end

# Two-phase send-keys into the freshly-booted window: literal text, settle, then Enter. Best-effort.
defp inject_opening(window, text) do
  sock = tlon_socket()
  target = "#{@tlon_session}:#{window}"
  _ = cmd_runner().("tmux", ["-L", sock, "send-keys", "-l", "-t", target, text], stderr_to_stdout: true)
  Process.sleep(@opening_settle_ms)
  _ = cmd_runner().("tmux", ["-L", sock, "send-keys", "-t", target, "Enter"], stderr_to_stdout: true)
  :ok
end
```

> `Aleph.Cockpit.profile_launcher/1` is already public (`@doc false def profile_launcher`,
> `cockpit.ex:1614`). Calling it from `Aleph.Crew` reuses the exact launcher the standing coworkers
> use. If `:boundary` or a compile warning objects to the cross-module call, extract
> `profile_launcher/1` (+ its `pi_command/1`, `funes_identity_flags/0`, `sh_single_quote/1`
> helpers) into `Aleph.Profiles` or a small `Aleph.Launcher` module in a prep step and have both
> callers use it — do not duplicate the launcher string.

**Step 4: Run, verify pass**

Run: `cd modules/aleph && mise exec -- mix test test/aleph/crew_test.exs`
Expected: PASS.

**Step 5: Commit**

```bash
git add modules/aleph/lib/aleph/crew.ex modules/aleph/test/aleph/crew_test.exs
git commit -F - <<'EOF'
aleph: Aleph.Crew.spawn/kill — identity mint + tmux window + opening turn

spawn/3 mints reviewer-machine on the task thread (Funes.MCP.Spawn.join,
mandate machine), materialises the profile, spawns the r<tid> window on the
tlon server, and injects the leader's assignment after a TUI settle. Runner +
minter are app-env-injected so the seam tests headless.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 6: `mix aleph.crew.spawn` / `mix aleph.crew.kill` — the leader's CLI

Thin mix tasks the leader runs from bash. They boot the aleph app (so funes is up on aleph's port)
and call `Aleph.Crew`. Keep logic in a tested pure arg-parser; the task shell is a one-liner.

**Files:**
- Create: `modules/aleph/lib/mix/tasks/aleph.crew.spawn.ex`
- Create: `modules/aleph/lib/mix/tasks/aleph.crew.kill.ex`
- Test: `modules/aleph/test/mix/tasks/aleph_crew_test.exs`

**Step 1: Write the failing test** (parse-only; no app boot in unit tests)

```elixir
# modules/aleph/test/mix/tasks/aleph_crew_test.exs
defmodule Mix.Tasks.Aleph.Crew.SpawnTest do
  use ExUnit.Case, async: true

  test "parse/1 pulls role, thread id, and --task" do
    assert Mix.Tasks.Aleph.Crew.Spawn.parse(["reviewer", "42", "--task", "review HEAD~1"]) ==
             {:ok, "reviewer", 42, "review HEAD~1"}
  end

  test "a missing --task is an error" do
    assert {:error, _} = Mix.Tasks.Aleph.Crew.Spawn.parse(["reviewer", "42"])
  end

  test "a non-integer thread id is an error" do
    assert {:error, _} = Mix.Tasks.Aleph.Crew.Spawn.parse(["reviewer", "x", "--task", "t"])
  end
end

defmodule Mix.Tasks.Aleph.Crew.KillTest do
  use ExUnit.Case, async: true

  test "parse/1 pulls thread id and optional role (default reviewer)" do
    assert Mix.Tasks.Aleph.Crew.Kill.parse(["42"]) == {:ok, "reviewer", 42}
    assert Mix.Tasks.Aleph.Crew.Kill.parse(["42", "reviewer"]) == {:ok, "reviewer", 42}
  end
end
```

**Step 2: Run, verify fail**

Run: `cd modules/aleph && mise exec -- mix test test/mix/tasks/aleph_crew_test.exs`
Expected: FAIL — tasks undefined.

**Step 3: Implement**

```elixir
# modules/aleph/lib/mix/tasks/aleph.crew.spawn.ex
defmodule Mix.Tasks.Aleph.Crew.Spawn do
  @shortdoc "Spawn a crew coworker (role) onto a funes task thread"
  @moduledoc """
  The leader's spawn verb. Usage:

      mix aleph.crew.spawn <role> <thread_id> --task "<what to review>"

  Boots the aleph app (funes comes up on aleph's configured port), mints the role's identity on the
  thread, spawns its `r<tid>` window on the standing `tlon` tmux server, and injects the leader's
  assignment. Run it from the leader's own shell (it already lives on that tmux server).
  """
  use Mix.Task

  @impl true
  def run(argv) do
    case parse(argv) do
      {:ok, role, thread_id, task} ->
        Mix.Task.run("app.start")
        case Aleph.Crew.spawn(role, thread_id, task) do
          {:ok, window} -> Mix.shell().info("spawned #{role} → #{window} on thread #{thread_id}")
          {:error, reason} -> Mix.raise("crew spawn failed: #{inspect(reason)}")
        end

      {:error, msg} ->
        Mix.raise(msg)
    end
  end

  @doc false
  def parse(argv) do
    {opts, positional, _} = OptionParser.parse(argv, strict: [task: :string])
    with ["role" = _, _] <- [role_ok(positional), :_],
         [role, tid_str] <- positional,
         {tid, ""} <- Integer.parse(tid_str),
         task when is_binary(task) <- opts[:task] do
      {:ok, role, tid, task}
    else
      _ -> {:error, ~s(usage: mix aleph.crew.spawn <role> <thread_id> --task "<what>")}
    end
  end

  defp role_ok([role | _]) when is_binary(role), do: "role"
  defp role_ok(_), do: nil
end
```

> Simplify the `parse/1` guard clause to whatever reads cleanly — the test pins the contract
> (`{:ok, role, tid, task}` on good input, `{:error, _}` on missing `--task` or a bad id). The
> `role_ok` scaffolding above is illustrative; a straightforward `case positional` is fine.

```elixir
# modules/aleph/lib/mix/tasks/aleph.crew.kill.ex
defmodule Mix.Tasks.Aleph.Crew.Kill do
  @shortdoc "Tear down a crew coworker's window on a funes thread"
  @moduledoc "Usage: `mix aleph.crew.kill <thread_id> [role]` (role defaults to reviewer)."
  use Mix.Task

  @impl true
  def run(argv) do
    case parse(argv) do
      {:ok, role, thread_id} ->
        Mix.Task.run("app.start")
        :ok = Aleph.Crew.kill(role, thread_id)
        Mix.shell().info("killed #{role} window on thread #{thread_id}")

      {:error, msg} ->
        Mix.raise(msg)
    end
  end

  @doc false
  def parse([tid_str]), do: parse([tid_str, "reviewer"])
  def parse([tid_str, role]) do
    case Integer.parse(tid_str) do
      {tid, ""} -> {:ok, role, tid}
      _ -> {:error, "usage: mix aleph.crew.kill <thread_id> [role]"}
    end
  end
  def parse(_), do: {:error, "usage: mix aleph.crew.kill <thread_id> [role]"}
end
```

**Step 4: Run, verify pass**

Run: `cd modules/aleph && mise exec -- mix test test/mix/tasks/aleph_crew_test.exs`
Expected: PASS.

**Step 5: Commit**

```bash
git add modules/aleph/lib/mix/tasks/aleph.crew.spawn.ex modules/aleph/lib/mix/tasks/aleph.crew.kill.ex modules/aleph/test/mix/tasks/aleph_crew_test.exs
git commit -F - <<'EOF'
aleph: mix aleph.crew.spawn/kill — the leader's crew control surface

Thin mix tasks (tested pure arg-parsers + app.start shell) so the Claude leader,
an agent with bash on the tlon tmux server, can spawn/tear-down a reviewer
onto a task thread without pressing cockpit keys.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

## Task 7: The leader playbook (crew-plugin instructions)

The "leader role" is Claude-under-aleph following crew instructions (contract §A). Write them as a
doc the leader reads: compose the crew, spawn/kill via the mix tasks, parse the ESCALATE marker,
judge risk × presence (funes-recency), and surface vs approve-on-behalf.

**Files:**
- Create: `docs/plans/2026-08-21-funes-crew-leader-playbook.md`

**Step 1–2: (no test — this is prose)** Write the playbook. It MUST cover:

1. **Launch:** the operator opens/points at a task thread (claude-led by default —
   `MachineChat.Staffing.pick_coworker` → `claude-machine`, so the cockpit gives it a `t<id>`
   window; you are that window).
2. **Compose the crew (MVP):** for "review this diff/PR," spawn exactly one reviewer:
   `mix aleph.crew.spawn reviewer <thread_id> --task "<what to review>"`. Then post the concrete
   review target to the thread with `@reviewer-machine …` (durable + wakes its window).
3. **The ESCALATE protocol:** watch your incoming turns for a line
   `@claude-machine ESCALATE apply: <patch>` from `reviewer-machine`. That is a request to LAND a
   change the reviewer is forbidden to write.
4. **Judge — risk × presence:**
   - *Presence* = did the operator (a human author, not a coworker) post on this thread in the last
     ~10 minutes? Read it from your funes tools (`get_dossier` / recent messages) — do not guess.
   - *Routine change + operator away* → **approve-on-behalf**: apply the patch yourself (you have
     write), then post `applied on your behalf: <what/why>` and `record_check`/`bank_fact` the
     outcome.
   - *Destructive/important* OR *operator present* → **surface**: post
     `@operator NEEDS DECISION: <summary + patch>` (the cockpit's desktop_notify wakes them) and
     wait for the human call. Do not apply.
5. **Capture (value loop):** every {escalation → verdict → apply outcome} is already a thread
   message; additionally `record_check`/`bank_fact` "reviewer proposed fix of kind K → leader
   approved/denied → landed/reverted" so the value loop can later grade it (contract §C).
6. **Teardown:** when the review is resolved, `mix aleph.crew.kill <thread_id>` and post a one-line
   synthesis. Memory (facts/checks) carries what recurs; the agent does not.

**Step 3: (n/a)**

**Step 5: Commit**

```bash
git add docs/plans/2026-08-21-funes-crew-leader-playbook.md
git commit -F - <<'EOF'
docs: funes crew leader playbook — spawn, ESCALATE gate, risk×presence, teardown

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

> Follow-up (phase-2, not this MVP): package the playbook as an auto-loaded Claude Code skill under
> the repo's `.claude/` so the leader loads it without being pointed at the file. MVP proves the
> loop with the leader reading the doc.

---

## Task 8: Live end-to-end smoke — the MVP proof

The MVP is "the loop with the gate FIRING." Prove it live. This is the gate before calling the MVP
done; parts are human-driven (real Claude leader + a live cockpit).

**Step 1: Headless gate first**

Run: `cd modules/aleph && mise run aleph:check`
Expected: format clean, no warnings-as-errors, headless suite green (Crew, Mention, Profiles, mix
tasks).

**Step 2: Bring up the dogfood cockpit**

Run (human, in a terminal): `uqbar` (or `mise run aleph:run`). Confirm the Tlön space is up and
funes is on :4041.

**Step 3: Drive the loop** (as the leader, real Claude in the task thread's `t<id>` window)

1. Create/point at a task thread with a real, small diff to review (e.g. a scratch branch with a
   deliberate off-by-one or a missing nil guard). Confirm it is claude-led and you are its `t<id>`
   window.
2. `mix aleph.crew.spawn reviewer <thread_id> --task "review the working-tree diff"`. Verify:
   - a new `r<thread_id>` tab appears (`tmux -L aleph-tertius list-windows -t tlon`);
   - the reviewer posts to the thread as `reviewer-machine` (funes messages).
3. **Verify the gate is structural:** in the reviewer window, observe it CANNOT write — a `write`/
   `edit` attempt is denied by policy (check `~/.pi/profiles/reviewer/extensions/pi-permission-system/logs`
   or the reviewer's own report). It should post findings and a
   `@claude-machine ESCALATE apply: <patch>` line instead.
4. As the leader, receive the ESCALATE turn (it arrives in your `t<id>` window). Judge:
   - With the operator idle >10 min and the fix routine → apply it, post `applied on your behalf`,
     `record_check`.
   - Force the other branch too: post as the operator (or have the operator post) within the window
     and confirm a subsequent escalation SURFACES (`@operator NEEDS DECISION`) instead of
     self-approving.
5. `mix aleph.crew.kill <thread_id>`. Verify the `r<thread_id>` tab is gone and no reviewer process
   lingers.

**Step 4: Confirm capture**

Every hand-off (assignment, findings, ESCALATE, verdict, apply outcome) is a message on the thread;
the leader's `record_check`/`bank_fact` are present. Read them back via `get_dossier` / the funes
CHECKS view.

**Step 5: Record the outcome**

Post a short synthesis to the machine thread and update the crew memory note
(`funes-crew-mvp.md`) with "MVP landed + verified live" (or the specific gap if a branch failed).

> **Do NOT claim the MVP done without Step 3–4 observed live** — the headless suite proves the
> seams (routing, policy shape, builders) but not that pi actually refuses the write and the leader
> actually judges. Per `verify-with-home-switch-before-done`: module unit suites are not every gate.

---

## Definition of done

- [ ] `aleph:check` green (Tasks 1–6 suites).
- [ ] Live: reviewer spawns, reviews, is *structurally* write-denied, and ESCALATEs (Task 8.3).
- [ ] Live: leader judges — both approve-on-behalf AND surface branches exercised (Task 8.4).
- [ ] Live: teardown clean; every hand-off captured as a funes message + a `record_check` (Task 8.4).
- [ ] Playbook committed; crew memory note updated with the live result.

## Out of scope (phase 2+, per contract)

- The model-judging authorizer-link for the ambiguous middle (a worker needing a genuine
  judgment-call write that is not cleanly deny-able).
- planner / builder roles and the full brainstorm→plan→build→review arc.
- A real presence dial / attention bus (MVP: funes recency + existing desktop_notify).
- The scheduled value-loop grading pass (MVP only *emits* the CHECKS signal).
- Auto-loading the leader playbook as a `.claude` skill.
```