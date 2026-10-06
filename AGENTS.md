# ficciones — boundaries for a session at the repo root

This repository is one person's whole machine: an installer, dotfiles, a desktop, and the agent wiring,
as Nix-shaped modules under `modules/`. It is named *ficciones* after the Borges collection: the machine
holds the stories. The apps it runs are their own repos, pinned here by path — **tlon**
(`~/projects/tlon`: the server, the office, the pi/Claude Code adapters, with its own `AGENTS.md` and
loop) and **menard** (`~/projects/menard`). Read
`docs/plans/2026-08-14-machine-v2-and-funes-design.md` before reshaping anything here — it is the
design and every decision behind it.

## The dev loop — one shared API

The human and any agent drive this repo through the **same mise tasks** (`mise tasks` lists them) — one
control loop, not two, and no second way to run anything:

- `mise run check` — the names gate, the manual's drift check and the flake; the green-before-commit gate.
- `mise run flake:check` — the machine-level Nix gate.
- `mise run home:switch` — install/update this machine into the user profile via home-manager.
- `mise run machine:update` — apply the checkout to the live machine: home:switch, then restart the shell and tlon's server (the one update verb).

Elixir, the server loop, the pi model launchers and menard's verbs live in tlon (`cd ~/projects/tlon &&
mise tasks`).

mise owns dev runtimes; Nix owns packaging and the system. **If a command belongs in the loop, it becomes
a task in `tasks/<group>.toml` (mise.toml includes them)** — never a prose instruction that drifts out of sync with what actually runs.

### Run once, read the log — never re-run to see more

When you run a command whose output you'll inspect — a test suite, a build, a `scratchpad`
script — run it through **`scripts/cap.sh`** (or `mise run cap -- <cmd>`). It runs the command
**once**, captures all output to a log under `.logs/`, and prints a lean summary: the exit code,
a test/build-summary line, failure lines on a non-zero exit, and a short tail — plus the exact
`tail`/`grep` to read more **from the saved log**.

The rule this enforces: **do not re-run a command with an escalating `grep … | tail -N` to see
more of its output.** The full output is already on disk — `grep`/`tail` the log. Re-running
burns tokens, re-streams noise into context, and risks a slightly-different invocation each time.
Catching yourself about to run the same command a second time with a different filter is the
signal to read the log, not repeat the call — the same escape hatch any SWE reaches for when a
loop starts repeating itself.

`cap` prints a distilled **signal** view (results, errors, warnings, counts) and drops the
install/compile/debug noise; a green suite collapses to a couple of lines. Knobs when you need
them: `CAP_TAIL=all` (the whole log inline, once), `CAP_TAIL=<n>`, `CAP_SIGNAL=<n>`. `mise run
cap:clean` sweeps the logs (they self-cap at 40 anyway).

### Let the watcher run the tests — don't spend a turn doing it by hand

When you're iterating on a change, **register a watcher instead of re-running tests yourself**:

- `scripts/watch.sh <cmd>` (or `mise run watch -- <cmd>`) — watch-and-run anything, any scope
  (one test file, a folder, the whole suite). New test files under a watched dir are picked up.

Run it **in the background** (this harness: `Bash` with `run_in_background` — you're re-invoked
with the result when the suite settles; pi: a pane). Then just edit: you're pinged **red/green
automatically**, and you only spend a turn when something actually breaks. Kill the watcher when
the change is done. This is the intended inner loop here — not "edit, then manually run tests,
then read 1800 lines," every time.

## How to work — the four rules

Every agent on this machine, in any repo, works by the four rules in `modules/agents/how-to-work.md`:
think before coding (state assumptions, ask when readings diverge), the simplest thing that works,
surgical changes, and goal-driven execution against a check you can run. The flake installs that file
as `~/.claude/CLAUDE.md` and `~/.pi/agent/AGENTS.md`, so it is already in your context; this section
exists so a reader of the repo knows where the law comes from and edits the one source.

## The rules most likely to be broken by accident

- **`nix` runs from the agent tools now** (Arch's nix, not Determinate — see the Nix machine-truth
  memory). So `nix flake check`, `nix eval`, and `nix build .#astal-shell` are fair to run and verify directly.
  What stays the human's are the **system-mutating** commands — `home-manager switch`, `nixos-rebuild
  switch` on the host — because building the machine is a change the human owns. A claim that a build
  works without having run it is the one thing this repo cannot afford.
- **A module is born when it has content.** Do not create empty placeholder directories to imply a
  structure that does not exist yet. The tree should not lie about what is built.
- **An `AGENTS.md` is born the same way a comment is — when a scope needs context its parent doesn't
  give.** Root holds repo-wide invariants; a module or subapp gets its own when it has distinct law, a
  distinct dev loop, or gotchas that bite (`modules/desktop/shell`). Don't add one per
  folder by reflex — `lib/schemas/`, `test/`, etc. earn a file only once they accumulate a rule a
  weaker model keeps getting wrong; until then that guidance lives in the module's file. Keep every one
  terse and actionable to the same standard as comments: orientation, the exact commands, the law, the
  gotchas, a pointer to the one deeper doc — no lore. Skeleton: **what it is → Law → dev loop → Verify.**
  `find . -name AGENTS.md` lists them; a copy of that list here only ever goes stale, and had.
- **Keep docs in sync with the code, in the same commit.** A change that makes a module's `AGENTS.md`
  or a load-bearing comment stale updates it in that change — stale guidance is worse than none,
  because a weaker model trusts it. Nothing mechanical can catch this (staleness is semantic, invisible
  to compile/tests), so it's on you. (The `programs.rbw` comment that survived the rbw→agenix switch
  still describing the old design is the incident this comes from.)
- **Adopt Nix gradually.** home-manager on Arch first, a disposable NixOS VM (`nixos-rebuild build-vm`)
  as the testbed, metal last. Do not propose replacing the OS as a first step.
- **Commit as who you are.** An agent's commit ends with a `Co-Authored-By:` trailer naming the model
  that wrote it — YOUR model, read from the brief's `You are … (pi)` line (or `$PI_MODEL`), never a
  name copied from an example or another model's commit. Format: `Co-Authored-By: <your model> (pi)
  <noreply@ollama.com>` (pi) or `Co-Authored-By: <your model> <noreply@anthropic.com>` (Claude Code).
  `git log` is part of the machine's memory; a commit that hides its author — or names the wrong one —
  lies to it. (The first dogfood branch shipped 7 unattributed machine commits — that's the incident
  this rule comes from.)
- **Sandboxed Bash — phantom dotfiles and unreachable localhost are the sandbox, not the repo.** Both
  harnesses are affected: pi via the `pi-sandbox` extension (`~/.pi/agent/sandbox.json`, seeded at
  `flake.nix`'s `piSandboxSeed`) and Claude Code via its own. pi-sandbox delegates to
  `@carderne/sandbox-runtime`, a fork of Anthropic's, so **the `CLAUDE_CODE_*` and proxy env vars
  inside a pi bash call come from the fork — they are not evidence you're in Claude Code.** Two
  symptoms follow, and neither is a bug to chase:
  - *Phantom untracked dotfiles.* The wrapper bind-mounts over shell-rc / `.gitconfig` / editor paths,
    so `git status` **run inside a bash call** reports `.bashrc`, `.zshrc`, `.gitconfig`, `.env`,
    `.mcp.json`, `.idea`, `.vscode`, … as untracked at the repo root. The tell: `ls -la` shows them
    0-byte `-r--r--r--` (or `crw-rw-rw- 1,3`, a `/dev/null` char device). They don't exist on disk.
    Never `git add`/`rm` them or try to "clean them up".
  - *`127.0.0.1` is not the host's loopback.* bash runs under `bwrap --unshare-net` in a private netns,
    so `curl 127.0.0.1:4041`, `ss -tlnp`, and `systemctl --user` can never see the server channel —
    **regardless of whether it is up.** `allowLocalBinding` only permits binding *within* that netns.
    External traffic escapes via a socat→unix-socket proxy, but that proxy refuses loopback targets
    with a `403`, so there is no route. Do not conclude "server is down" from a bash probe; a bash
    probe cannot answer the question. **server MCP tools still work** — pi makes those calls from its
    own process, outside bubblewrap — so use them, or ask the human to check from the host.

  To get true git state or real host network, disable the sandbox: `Alt+S`, `/sandbox-disable`, or
  relaunch `pi --no-sandbox`.
- **Comments earn their place — load-bearing only.** A comment survives only if it states a non-obvious
  *why* or a real gotcha the code can't. Narrative, lore, dated incident references, decorative
  `# --- section ---` dividers, and restatements of what the next line plainly does are noise — don't
  write them, and trim them when you touch a file. Prose belongs in docstrings (`@moduledoc`/`@doc`/
  `@spec`, JSDoc) and the `*.md` files; inline comments are load-bearing only. (A repo-wide pass cut
  ~320 comment lines to this standard — don't grow them back.)
  - **No devlog.** A comment describes what IS, never how it got here. Cut the evolution storytelling:
    *"used to X / now Y instead"*, *"supersedes / replaces / reverses the old…"*, *"the bug this
    replaces was…"*, *"before the fix / pre-B1.4"*, rename & migration history, "we tried X then…".
    Keep the current-state constraint even when it grew out of a past bug — just state the constraint,
    drop the incident. The git history holds the story; the code holds the present.
- **Secrets: agenix for the machine, rbw for you.** A secret a non-interactive process needs — a
  service, a spawned pane (e.g. `OLLAMA_API_KEY` for the Tlön pi) — lives age-encrypted in
  `secrets/*.age` (agenix), decrypted at `home:switch` to `$XDG_RUNTIME_DIR/agenix/<name>` with *no*
  runtime unlock. Human/interactive passwords live in Bitwarden via `rbw`. Never a plaintext key in the
  repo, a dotfile, or the nix store. To add a machine secret: recipient pubkey → `secrets/secrets.nix`,
  `agenix -e secrets/<name>.age`, `git add` it (nix can't see untracked files), reference it via
  `age.secrets` in `flake.nix`.

## Verify

`mise run check` is the gate: the names gate, the manual's drift check and `flake:check` (Nix).
`mise run check:names` (first in it) checks that every mise task a guide, script or `flake.nix` names
exists, and that every `~/.pi/agent` file tlon's adapters read is one the flake writes — a rename that
strands a reference fails here instead of at 2am. A claim that something works is backed by the
command that proved it — and the agent and human run the *same* `mise` tasks, so "it works" means the
shared task passed, not two private ones.
