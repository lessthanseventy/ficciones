# Per-space pi coworker profiles — design

_2026-08-17. Status: designed, not yet built. Supersedes the ad-hoc "sever funes from Tlön" cut —
that becomes one profile, not a launcher special-case._

## Why

aleph spaces host machine coworkers (Tlön has `pi-machine`; a "Support Desk" and others are coming).
Each coworker wants a **different pi** — not just funes on/off, but its whole configuration:

1. **Tool / MCP surface** — Tlön is self-contained (no funes); Support Desk might want funes *plus*
   support-specific tools.
2. **Model + thinking level** — a support agent and a coding agent aren't the same model.
3. **System prompt / persona** — the coworker's role.
4. **Extensions / skills** — which of lsp/reload/consult/fmt/pi (and future skills) a coworker gets.

Today there is one global pi config (`~/.pi/agent`, the funes-citizen "default"), and Tlön inherits
it wholesale — which is why the machine coworker posts/banks into a thread the Tlön space doesn't even
render. The fix is not a funes off-switch in the launcher; it's **per-space profiles**: each space
declares a named profile that fully specifies its coworker's pi.

## The mechanism

pi reads its whole config (`settings.json`, `mcp.json`, `models.json`, `auth.json`) from
`PI_CODING_AGENT_DIR` (default `~/.pi/agent`). Verified: pointing it elsewhere makes pi load a
different config. So a profile is **a materialized config dir + a few launch flags**.

One structural fact drives the shape: of the four dimensions, three can be launch flags
(`--model`/`--thinking`, `--append-system-prompt`, `--extension`/`--skill`), but the **MCP surface
can only come from `mcp.json` in the config dir** — there is no `--mcp` flag. So a profile
unavoidably needs its own config dir; the model/prompt can ride as flags or as that dir's
`settings.json` defaults.

## Decision: declarative profiles, materialized by aleph at runtime

Weighed three homes for the definition:

- **Chosen — declarative data in the repo, materialized by aleph at cockpit start.** Profiles are
  `%Aleph.Profile{}` values in an `Aleph.Profiles` module (git-versioned, recompiled on cockpit
  restart). At start aleph writes each into `~/.pi/profiles/<name>/`. **Why:** reproducible *and*
  fast to iterate — edit a profile, restart the cockpit (which recompiles), no `home:switch`. That
  matches everything this stack optimizes for (reload, the lspd sidecar — iteration speed). aleph
  already owns the spaces and their coworkers, so it owns their configs too.
- **Rejected — flake-declarative.** Purest reproducibility, but every profile tweak needs a
  `home:switch` — the slow loop we've been designing away from.
- **Rejected — hybrid (flake base + aleph overlay).** More moving parts than the win justifies; the
  shared bits (auth, model catalog) are already handled by symlinks (below).

## Architecture

```
  Aleph.Profiles          (git-versioned data)          ~/.pi/agent      (base: funes-citizen default,
   ├─ %Profile{name: "tlon",  mcp: %{}, exts: […]}        ├─ auth.json      flake-owned, used by CLI
   └─ %Profile{name: "support", mcp: %{funes…}, …}        ├─ models.json    launchers pi:* / funes:claude)
             │  materialize at cockpit start              └─ …
             ▼
  ~/.pi/profiles/<name>/                                 Space{key: :tlon, coworker: "tlon"}
   ├─ settings.json   (extensions + skills + model defaults)     │  spawn_coworker(space)
   ├─ mcp.json        (this profile's MCP servers; {} = none)    ▼
   ├─ auth.json    → symlink ~/.pi/agent/auth.json     PI_CODING_AGENT_DIR=~/.pi/profiles/tlon
   ├─ models.json  → symlink ~/.pi/agent/models.json   + --append-system-prompt … → the coworker's pi
   ├─ models-store.json → symlink
   └─ sessions/       (this coworker's own history — reload --continue resumes within it)
```

### The profile value

```elixir
%Aleph.Profile{
  name: "tlon",
  # nil = inherit the base defaults (settings.json defaultProvider/Model/thinkingLevel).
  model: %{provider: "ollama-cloud", model: "deepseek-v4-flash", thinking: "medium"} | nil,
  # The persona. Can't live in settings.json — passed as --append-system-prompt (or --system-prompt).
  system_prompt: nil | binary,
  # Which pi extensions/skills this coworker loads. :base = the standard manos set.
  extensions: [binary] | :base,
  skills: [binary] | :base,
  # MCP servers for THIS coworker. %{} = self-contained (no MCP). A funes entry re-wires it.
  mcp: %{optional(binary) => map()},
}
```

### Materialization (aleph, runtime, idempotent)

`Aleph.Profiles.materialize!/1` writes `~/.pi/profiles/<name>/` each cockpit start:

- `settings.json` — `extensions`, `skills`, `defaultProvider/Model/thinkingLevel`, `enabledModels`,
  from the profile (falling back to the base `~/.pi/agent` values). Extensions are absolute repo
  paths (as today), so they resolve regardless of config dir.
- `mcp.json` — `{"mcpServers": <profile.mcp>}`. Empty for Tlön ⇒ no funes server ⇒ its
  `${FUNES_MCP_URL}` collab tools never load, and — because the manos/pi funes-brief extension isn't
  in Tlön's extension list — no register/brief either. Self-contained, by config, no env hack.
- `auth.json`, `models.json`, `models-store.json` — **symlinks** to `~/.pi/agent/*`. One credential
  store, one model catalog, shared across every profile.
- `sessions/` — the profile's own dir. Each coworker resumes its own thread; `reload --continue`
  (see [[expert-lsp-stdio-crash]]'s sibling, the reload tool) stays scoped per space.

Idempotent and self-healing: re-materialized on every boot, so editing a profile + restarting the
cockpit is the whole loop. No `home:switch`.

### Launch & mapping

- `Space` gains `coworker: profile_name | nil`. Tlön → `"tlon"`. Spaces with no coworker spawn no pi.
  One coworker per space for now (multi-coworker per space is a later extension — YAGNI).
- `spawn_machine_coworker` generalizes to `spawn_coworker(space)`: look up the profile, `materialize!`,
  build the launcher. `tlon_launcher` generalizes to `profile_launcher(profile)`, which sets
  `PI_CODING_AGENT_DIR=~/.pi/profiles/<name>`, adds `--append-system-prompt` if the profile has a
  persona, and carries both into `MANOS_RELOAD_CMD` so a reload stays on-profile.

## Scope / YAGNI

- Build the **mechanism** + the **`tlon` profile** (the only real coworker today). Do NOT build
  Support Desk or multi-coworker-per-space — the system supports them; instantiate when they exist.
- `~/.pi/agent` stays the base/default (funes citizen) for the CLI launchers (`pi:*`, `funes:claude`)
  — unchanged. Profiles are an aleph-space concern. (A space could later reference a `"default"`
  profile equal to the base if wanted.)
- The Tlön machine *thread* stays as-is for the cockpit's own rendering; the coworker simply no
  longer posts into it (no funes tools, no manos/pi brief).

## Testing

- Pure render seam — `Profile → {settings_json, mcp_json}` — unit-tested (like the launcher tests):
  Tlön renders `mcpServers: {}` and omits the manos/pi extension; a funes profile renders the funes
  server.
- Materialization — into a tmp dir: asserts the four files + three symlinks land correctly, idempotent
  on a second call.
- `profile_launcher/1` — asserts `PI_CODING_AGENT_DIR` and the persona flag are in the command, and
  that `MANOS_RELOAD_CMD` carries them.
- Space mapping — the Tlön space resolves to the `"tlon"` profile.

## Rollout

1. `Aleph.Profile` struct + `Aleph.Profiles` (the `tlon` profile) + `materialize!/1`.
2. Generalize `spawn_machine_coworker`/`tlon_launcher` to be profile-driven; add `Space.coworker`.
3. Cockpit-start hook materialises every referenced profile before spawning coworkers.
4. Deploy: aleph change only — profiles materialise at runtime from the `~/.pi/agent` base, so **no
   `home:switch`**; a cockpit reboot applies it. (First boot creates `~/.pi/profiles/`.)
5. Prove: launch Tlön, confirm the coworker has no funes tools and no brief, and that lsp/reload/etc.
   still work; `reload` resumes on the tlon profile.

## Risks / open questions

- **System prompt as a flag** — `--append-system-prompt` vs a per-profile prompt *file*; a file is
  cleaner for long personas. Decide at build time.
- **Base drift** — profiles inherit base defaults by falling back to `~/.pi/agent` at materialize
  time; if the base's model list changes, re-materialize picks it up on next boot (good).
- **Sessions dir per profile** — confirm `reload`'s `--continue` resolves within `PI_CODING_AGENT_DIR`'s
  `sessions/` (expected; verify live).
- **The manos/pi extension** — it is the funes-brief renderer, so it belongs only in funes-citizen
  profiles. Confirm nothing else (footer, status) that Tlön wants lives solely in it.
