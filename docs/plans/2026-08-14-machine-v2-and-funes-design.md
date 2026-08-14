# Machine v2, and `funes` — design

Written 2026-08-14, out of a brainstorm that started as "which language for the workbench" and ended as
"what is my whole computer." This is the record of what was decided and, in the spec's own tradition,
*why* — so the next person to find a constraint inconvenient knows what it cost.

This document sits at the **machine-repo** level. The `funes` module carries its own spec
(`modules/funes/docs/spec.md`) — this doc governs the repo *around* it and the one seam between them.

---

## 1 · What this repo is now

It is not "the AI repo." It is **machine v2**: a single monorepo of self-contained modules that, taken
together, are this computer. The AI stack (`funes`) is the first and most-specified module; the rest are
harvested out of the current Arch environment over time.

```
ficciones/                   # this repo — named for the Borges collection that contains the funes story
  flake.nix                  # the installer (see §4)
  hosts/                     # per-machine composition: which modules a host turns on
    personalbox/             #   this Arch box, via home-manager
    testvm/                  #   disposable NixOS VM for trying things (nixos-rebuild build-vm)
  modules/
    funes/                   # the AI stack — spec-driven, §8c-bounded, liftable (see §2)
    desktop/                 # hyprland + its stack        (harvested, later)
    theme/                   # colours, UI prefs, theming   (harvested, later)
    shell/                   # shell, ghostty, dotfiles       (harvested, later)
  docs/plans/                # this document and its successors
```

The env modules (`desktop`, `theme`, `shell`, …) are a **separate, incremental track**. They do not
block `funes`, and `funes` does not depend on them. Nix makes that pull-over gradual by design; there is
no big bang.

---

## 2 · `funes` — the AI stack, and why it keeps its own boundary

`funes` is the module the migrated spec describes (formerly "workbench"). It is renamed after Borges'
*Funes the Memorious* — the man cursed with perfect, total recall who becomes useless because he cannot
forget or generalise ("to think is to forget differences"). A system whose entire §4 is a war on total
recall — *don't load all 297 facts, the always-loaded set is 32 rows* — has no more honest name. The
README tells the joke; the house voice for the docs is that dry, self-aware, faintly-cruel register the
spec already writes in ("It was correct and useless").

**The boundary is load-bearing.** The cohesion model (§3) requires the *same* `funes` to run on the work
machine and the personal machine, sovereign on each. So `funes` must be **liftable** — it never imports
up into machine config, reads no `theme` variable, assumes no `desktop`. The spec's §8c drew its
"nothing travels but the repository" line at the *repository* edge; here that line moves inward to the
**module** edge. The unit that crosses to another machine is `modules/funes/` (a `git subtree` split, or
the flake enabling only that module on that host). This is a **spec amendment**, made in the same commit
as the restructure that proves it — §8b/§8c "repository" → "the `funes` module within the machine repo,"
and the `workbench → funes` rename.

### Runtime

- **TypeScript, run natively on Node 24** (type-stripping — `node src/cli.ts`, no build step, no `dist/`).
  Verified on this machine: a `.ts` file with a type annotation ran unbuilt and printed the right number.
- **`tsc --noEmit` is the only type gate**, run in `npm run check` and in tests. Types are checked, never
  a runtime dependency.
- **Zero runtime dependencies.** `node` + `node:sqlite` only. `package.json` pins `typescript` as the
  sole dev dependency. Nothing in `src/` imports outside `node:*`.
- Cost, stated honestly: "erasable syntax only" (no TS `enum`, `namespace`, or constructor
  parameter-properties). Idiomatic modern TS avoids all three.
- **Why not Elixir** (it is installed, and the owner reaches for it): this stack is short-lived CLI
  invocations against a SQLite file — `doctor`, `glance`, Herdr `command=` hooks firing per pane event.
  BEAM pays its boot cost on *every* invocation, and §10 forbids the long-running supervised process that
  would amortise it ("the database is the bus"). §4's entire write-contract was measured on `node:sqlite`.
  Elixir throws that evidence away for a per-call latency tax on the one shape it least suits.

### Scope

**Spec-tight, one open seam.** Everything is built exactly as §9 specifies: `event.kind` is a **closed
set with a DB CHECK**, extended only by migration; `fact`, `issue`, `signal`, `collection` as written.
The single open surface is the **channel** (§5b) — "any participant posts anything." Generality is
*earned* by a real second writer appearing, not granted up front. A public `wb`/`funes emit` write-API is
a later migration if and only if something outside `funes` genuinely needs to write. Door unlocked, not
opened.

Rejected: "substrate-first," an open `event.kind` string anything can write. It walks straight into the
wide-discriminator dumping-ground failure the spec names three separate times, and an open kind makes a
typo indistinguishable from a real kind — the exact "false zero from a wrong key" failure of §10. The
thing worth building a computing life on is not one that accepts anything; it is one that never lies.

### Migrations

Numbered plain `.sql` files (`001-core.sql`, `002-…`) applied in a transaction, with SQLite's built-in
`PRAGMA user_version` as the counter — no bookkeeping table of our own. The schema **grows one migration
per §9 step**, which exercises the runner for real instead of shipping it unproven. At 2am the schema is
readable SQL you can re-run by hand with `sqlite3`.

---

## 3 · Cohesion — machines and phone "know about each other"

The vision: a coherent herdr / pi / ghostty / OS / phone / life fabric where everything works and knows
about each other, reachable over ssh/Tailscale. This collides head-on with §8c, which *deliberately*
killed shared state ("nothing travels except this repository; no sync, no merge, no partition, no SQLite
on a shared filesystem") because 51% of v1 facts name work systems that must never reach the personal
box, and shared-fs SQLite is a corruption path.

**Resolution: cohesion is communication, not shared state.** Each machine keeps its own sovereign SQLite.
They know about each other by **talking on the channel (§5b) over Tailscale** — never by merging fact
stores. The phone is a thin channel client that posts and reads. Work facts never leave the work box;
§8c stays fully intact. This *elevates* the channel from "item 6 of 7" to the cohesion fabric the whole
"for real" ambition rests on — but it does **not** move it earlier (§9: "do not start at step 3 because
it is more interesting"). Two cheap consequences to honour now:

1. The channel's transport must never assume localhost — a Tailscale-reachable participant is a
   first-class case from the start, even while day one has only local participants.
2. It confirms every portability choice: zero-dep, node-native, `WB_DB` override, no distro-isms.

Rejected: actually syncing state across trusted machines. It reopens the door §8c nailed shut and brings
back the partition problem, a sync engine, and the leak/corruption risk the spec spent a section
eliminating.

---

## 4 · The installer — Nix, gradually

The machine-v2 installer is a **Nix flake**. The decision was close and is worth its reasoning, because
the owner had correctly written NixOS off for the *old* world (preferred Arch/AUR + mise/asdf,
terminal-forward, lowest friction) and only two things changed:

- **The AI world pays the Nix-language tax.** The #1 reason to avoid Nix is the arcane language and
  hostile errors — precisely what an assistant now absorbs. The main historical objection evaporated.
- **Nixpkgs is larger than the AUR** (~100k+ packages); mise/asdf keep working *on* a Nix system for
  per-project runtimes; Nix is all-CLI. The stated worries mostly dissolve on inspection. The chezmoi
  bounce is not predictive — chezmoi is imperative sync/templating; home-manager is one declarative
  source, which is the thing chezmoi failed to be.

**Adopted path — low blast radius:**

1. **Nix (package manager) + home-manager as a flake, on the existing Arch install.** Keep Arch, keep
   mise for per-project runtimes, keep the terminal workflow. home-manager declaratively owns
   dotfiles/packages/home. `hosts/personalbox` is a `homeConfigurations` entry.
2. **A disposable NixOS VM as the testbed.** `hosts/testvm` is a `nixosConfigurations` entry;
   `nixos-rebuild build-vm --flake .#testvm` builds a throwaway QEMU VM of that exact config, run on the
   Arch host, mutating nothing. This is where full-NixOS gets tried before it ever touches metal, and it
   is also the owner's wanted "throwaway VMs" pattern.
3. **Graduate to NixOS on metal only when it feels good**, never as step one.

`funes` is installer-agnostic by construction (§8b: it installs by writing pointers — Herdr `command=`, a
`bin/` wrapper). The flake packages it, but nothing about `funes` or its day-one build depends on Nix. If
Nix were abandoned tomorrow, `funes` would install identically via a bootstrap script.

Rejected: full NixOS now (biggest blast radius, learning everything while fighting the rebuild loop —
do it on the VM first); plain stow + bootstrap.sh (ships today with known tools, but no reproducibility
or rollback, which is the exact thing the new world made the owner want).

---

## 4b · Being on NixOS changes capabilities, never the core

Asked during the brainstorm: on NixOS, could `funes` spin up throwaway VMs and run risky work with
broader permissions instead of sandboxing so hard? Yes to the capability, no to the mechanism the
phrasing implies.

**The core must never branch on platform.** §8c: *"Nothing in the core may branch on platform."* §8: no
provider or mechanism is known to the code. `if (onNixOS)` anywhere in `funes` is a straight violation —
it is exactly what would stop the same `funes` running on the work box and a clean-room VM without a fork.

**So it is a capability, not a platform** — the same shape the spec uses for models and signal sources.
`funes` never asks "am I on NixOS," it asks "is a `disposable-exec` capability configured here?" On
`hosts/personalbox` that capability is wired and backed by `nixos-rebuild build-vm` / ephemeral `nix run`
sandboxes; elsewhere it is **absent, and absent degrades honestly rather than breaks** (§8c) — `funes`
falls back to its normal caution and says so, the way a collector that cannot collect says so.

**The idea underneath is isolation-by-disposability, which is the stronger safety model.** A destructive
command is safe in a throwaway VM not because its permissions were clipped but because the blast radius
*is* the VM and it is deleted after. And the payoff: a disposable VM is the *anti-production*, so §8's
strictest boundary — "in production the human presses Enter, no `send-keys enter`, fail closed" — inverts
inside it. The agent may type-and-run autonomously there, because there is nothing production about a
machine about to be `rm`ed. The capability does not loosen the boundary anywhere it applies; it creates a
*zone* where the boundary does not apply. NixOS makes that zone nearly free to conjure — the whole reason
to wire it on this host.

**Modes stay scarce.** §10 is wary of modes. This is one capability behind a stable interface
(`disposable-exec`), configured per host — not a platform branch and not a mode zoo. What runs in the
zone (risky shell, untrusted MCP servers, a whole throwaway `orient`+agent loop) is a later decision,
made deliberately before it becomes an interface.

## 5 · Build order

Discipline first: the vision does not license skipping step 1. `funes` day one is **still the database
and `funes doctor`**, because nothing ships that cannot be repaired at 2am.

**Track A — `funes` (spec-driven, §9 of the module spec):**
1. Database + `doctor` — schema, migrations, `integrity_check`, JSONL export, nightly backup. The §8b
   Herdr-manifest drift check is honestly stubbed ("no plugin deployed yet") until there is a plugin to
   compare against — no faking a check against nothing.
2. `fact`, empty — provenance, check, supersedes, taught — surfaced in `orient`. First write is the v1
   ledger cutover (freeze read-only) — but the v1 ledger lives on the *work* machine, not here, so on
   this clean-room box `fact` simply starts empty.
3. Signal writer (PR collector) before anything reads signals.
4. `glance` — the two questions, ranked and cut, with data age. Needs an `event` kind meaning "work
   landed."
5. `event`, written by the pieces that exist.
6. The channel — thread per subject, delivery that wakes the recipient, `delivered` ≠ `read`,
   transport not assuming localhost (§3).
7. `issue`, read by `orient` at start — deleted if that acceptance test fails.

**Track 0 — repo scaffold (does not need Nix installed, just files):** restructure current root into
`modules/funes/`; scaffold `flake.nix`, `hosts/{personalbox,testvm}`, `modules/`; rewrite the top-level
README (machine v2) and write `modules/funes/README.md` (the Borges joke); amend the funes spec §8b/§8c.
One commit.

**Track B — env harvest (parallel, incremental, later):** pull Hyprland, theme, shell out of the current
Arch env into declarative modules. No dependency on Track A.

**Owner action required (system change, not mine to run):** install Nix on Arch. Everything in Track 0
is just files and proceeds in parallel.

---

## 6 · Deferred, on purpose

- Full NixOS on metal — after the VM proves it.
- The env-harvest modules — Track B, incremental.
- The coordination surface, day/week views, further signal collectors — the module spec already defers
  these past day one.
- A public write-API for `funes` — only if a real second writer appears.
- The `disposable-exec` capability (§4b) — designed, not built; and the decision of what actually runs
  in the disposable zone, made before it becomes an interface.
