# Worlds & Orbis — reshaping aleph from three fixed spaces into a god-view over worlds

Date: 2026-08-21
Status: north-star / design. Born from a 2026-08-21 operator + `claude-machine` riff, building directly
on `2026-08-20-tlon-long-term-vision.md` (the "split the coat" thesis) and
`2026-08-19-orbis-tertius-meta-thread-design.md` (the Borges naming layers). This doc turns those
into a concrete UX skeleton and settles the one architectural fork the vision doc flagged. Slicing is
sketched at the end; detailed task plans are follow-ups.

## The reshape in one breath

Aleph today has three sibling spaces you `Tab` between — **Orbis** (the all-threads chorus),
**Sessions** (an embedded PTY you point at a thread), and **Tlön** (the hardcoded machine dogfood).
The reshape collapses that into **two altitudes**: a **god-view (Orbis)** over *all worlds*, and **a
single World** you zoom into to work. Sessions stops being a space — it was the `attach` verb
over-promoted to a tab. Tlön stops being a fixed tab — it becomes **World #1**, one tenant among many.
Your other projects (`~/projects/ex_riverside`), and non-code contexts (personal life), become peer
Worlds. This is not a new architecture; it is the vision doc's "make the dogfood ordinary," made
literal in the UI.

## The altitude model (the load-bearing idea)

The Borges layering — kept as a *useful guide, not a law* — hands us the extra organizational layer
the operator was reaching for. In the fiction: **Orbis Tertius** (the secret society + encyclopedia
that *authors and catalogs whole worlds*) → **Tlön** (one invented world) → **hrönir** (the objects
*inside* a world; already a coworker name in the cast). Three altitudes:

- **Aleph** — the cockpit shell. The point that contains all points. Unchanged.
- **Orbis** — the **god-view / meta altitude**. Not "one project's threads" like today — *the chorus
  of all worlds*, plus where worlds are **authored**. Survey and authoring are the *same height*
  (both are cross-world, meta), so Orbis has **two faces, not two spaces**.
- **A World** — a single project/context you **zoom into** to work. Center is live PTYs; around it,
  that world's commits/memory/activity/leaves. Tlön is world #1; others are peers.

Navigation is a **zoom**: Orbis is home, pick a world → you're working, `Esc` → back up to the
god-view to pick a different one. `Tab` cycles **two** things now (Orbis · current World), not three.

## Naming

Borges stays as connotative scaffolding, dropped wherever it constricts. **Orbis** = the authoring
god-view (the society that catalogs worlds). **Tlön** = the specific dogfood world (the self-
referential one — the stack building itself). Other worlds need not take Borges names; `ex_riverside`
is just `ex_riverside`. `tertius-machine` (the meta agent) becomes **the resident agent of Orbis** —
it was already the cross-thread surveyor; now it surveys all *worlds*, which is exactly the god-view's
job.

## Orbis — the two faces

- **Survey face** — the reborn chorus, *elevated*. Today's `Aleph.Panel.Chorus` shows one scope's
  threads; the survey face shows **every world at once**: a row per world with its rollup (leads,
  open/stalled/done, cross-thread trouble — the existing `Aleph.Orbis.rollup/0` / `Funes.Board`
  status, re-pointed from "threads in scope" to "worlds"). This is where you sit to see the whole
  box. `Enter` on a world → zoom in.
- **Author face** — config's real home (today it has none — just the Settings modal + the flake).
  Compose worlds from installed capabilities: name, paths, roster, knobs. The **Settings modal is
  absorbed here**. Creating a world (e.g. "personal life" on a Tuesday) happens here, at runtime, with
  no rebuild — see the config seam below.

## A World — what it is, and Sessions folded in

> **A World = one-or-more directories (all git-tracked) + a coworker roster + config knobs.**

A world is a *set of paths*, not one repo: Tlön is the `modules/*` set; `ex_riverside` is one repo;
personal-life is `journal/ + finances/ + notes/`. **Everything is git-tracked, always** — git is a
universal knowledge substrate here (the filesystem-level echo of funes' append-only ledger), so it is
*not* a differentiator between world types; it is furniture every world gets.

Inside a world, **Sessions dies into the furniture**:

- **Leaders in the WindowBar.** The top strip is the scarce, always-visible "who's driving right
  now" — the lead coworker(s) with live PTYs.
- **Everyone in Leaves.** The Leaves panel is the full roster you reach into; its `Enter` already
  "jumps to the session" today — rewire that to **attach in place** (the center swaps to that
  coworker's PTY) instead of switching to a now-deleted Sessions space.
- So "Sessions" was never a space; it was `attach`, and `attach` becomes an action available from
  Leaders and Leaves. The embedded terminal (ghostty PTY) stays exactly as-is; only its *framing*
  changes.

Worlds have a **type / panel-set**: a *code* world lights up Commits/Leaves/PTYs and a build gate; a
*life* or *blank* world drops the dead furniture (a Commits panel is meaningless there) and shows a
leaner set with a different roster. The type is just another knob in the author face.

## The config seam — capabilities (nix) vs compositions (funes)

The vision doc's "one architectural fork to decide deliberately." The forcing function: **you create
worlds by hand at runtime** ("personal life" on a Tuesday), which *cannot* route through a heavy
`home:switch` rebuild. But config is flake-owned today. Resolution — and it is a real seam, not a
mushy hybrid, because the two sides own **disjoint** kinds of thing:

- **nix owns *capabilities*** — the things that require *software to exist*: the pi/claude binaries,
  `models.json`, permission policies, the extension/skill catalog, and the **profile archetypes** (a
  "builder" template, a "life-assistant" template). This is packaging; it must stay reproducible and
  version-controlled. It *cannot* live in funes because it is software, not data.
- **funes owns *compositions*** — a World is an **instance** that references capabilities *by name*:
  `personal-life = { paths: [journal, finances], roster: [life-assistant], type: life, knobs: {} }`.
  Pure data. Runtime-editable from Orbis' author face. No rebuild.

This **dissolves the "who wins on conflict?" question** — nobody, because ownership is disjoint. nix
defines what a "life-assistant" *is*; funes decides your personal-life world *uses* one. It keeps the
boundary law intact: funes stays sovereign, referencing capabilities by name, never reaching *up* to
define them (the `:boundary` compiler still holds). Full-funes was rejected (it would make funes hold
pointers to things nix installs anyway — a round-trip); flake-truth was rejected (a rebuild per world
is exactly the Tuesday-afternoon friction we are removing).

## Tlön's demotion & the release bar

Today Tlön is special-cased in `Aleph.Space.all/0`: `key: :tlon`, `coworker: "tertius"`, a hardcoded
`WindowBar + Terminal + Pulse` surface, the `tlon` tmux session. The reshape moves that special-casing
**out of the space list and into per-world composition data**. The flake **seeds** the dogfood cast as
an initial funes world row at bootstrap; thereafter funes owns it like any other world — so **Tlön
becomes editable too**, and "no special-casing for THE tlon" falls out for free.

The vision doc's release bar becomes literally testable: **the moment a second row can appear next to
Tlön in Orbis' survey — a world spawned from the author face, touching no aleph/funes code — the
dogfood has become "just another world."**

## Interaction tweaks (fold into the reshape)

Three operator asks, two of which are fixable against today's code independent of the collapse:

1. **Lazygit auto-swap — selection drives the center, no `Enter`.** In nav mode, moving the cursor
   over a leaf/thread **previews** — the embedded terminal re-points to that session (cheap; it is
   just which tmux window renders). The critical split: **preview-follows-selection, but focus &
   keystrokes only on commit.** Hovering must NOT send keys or steal focus, or you would drive a
   coworker by scrolling past them. `arrow` = preview swap; `Enter`/typing = commit + attach. This is
   the new nav model (part of the reshape).
2. **Nav up into the SPACES box.** The `h/l/H/L` accent-border focus cycle (from the lazygit-panels
   work) never included SPACES as a target — a focus-state-machine gap. Add it; it matters more after
   the reshape since switching worlds is central. *(Fixable now.)*
3. **Wider border on the active pane.** TUI has no sub-cell width, so "wider" = a **double-line border
   (╔═╗) on the focused pane vs single (┌─┐) elsewhere**, plus **bold + brighter accent** on border &
   title. Reads as "thicker" without real pixels. `border.ex`. *(Fixable now.)*

## Sequencing

- **Slice 0 — the collapse (UX first, almost no new backend).** Delete Sessions; demote Tlön from a
  fixed tab into the sole World; elevate the chorus into Orbis' survey face; fold Sessions' `attach`
  into Leaders/Leaves; ship the three interaction tweaks. **One hardcoded world.** Proves the two-space
  skeleton before any config-truth work. `tertius-machine` re-seats as Orbis' resident agent.
- **Slice 1 — multiplicity.** funes-owned world compositions + Orbis' author face + a real second
  world. The scary architectural part (config truth) lands *after* the UX is already better, against a
  proven skeleton.
- **Later — world types & grouping.** Per-type panel-sets (code vs life vs blank). Grouping worlds
  into orgs/folders is **YAGNI** until the flat list is crowded — the `scope: machine|project`
  primitive is the backbone; a flat list under Orbis suffices first.

## What does not change

The boundary law and sovereign funes module; capabilities-in-nix packaging; the one-mise-loop parity;
the commit-byline rule; the comment standard; the embedded-ghostty terminal itself. This is a redirect
of the substrate's aim and a data-modeling discipline (compositions become funes data), not a rewrite.
The architecture is already the personalization layer; the work is making the dogfood ordinary and
letting worlds multiply.

## Deferred / open

- Exact author-face UX (form vs. edit-a-funes-row vs. a mini-DSL) — settle in Slice 1.
- `record_done`-without-close cadence for the Orbis surveyor (a known funes Bus follow-up).
- The durable cost ledger and approvals/escalation queue (from the vision doc's steal-list) — orthogonal,
  land where they fit.
