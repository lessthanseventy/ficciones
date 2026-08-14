# workbench

One person's workbench: the machine-side layer between [Herdr](https://herdr.dev) (terminal),
[pi](https://github.com/earendil-works/pi-coding-agent) (agent), and the work itself.

**Read `docs/spec.md` first.** This repository's first commit is a specification rather than code,
which is the point: version one was arrived at by two weeks of daily use and iteration, and it worked
well enough to be *described* instead of discovered. Version one keeps running until this replaces it
piece by piece.

## What is here

| File | What it is |
|---|---|
| `docs/spec.md` | The specification. Every rule in it names the failure that paid for it. |
| `docs/spec-review.md` | An adversarial review of that specification by a fresh session, which found seven defects in it. Kept because the arguments are the reasoning. |
| `docs/v1-review.md` | An adversarial review of **version one**, which is what made a version two worth specifying. |
| `docs/issues.md` | The bootstrap issue list, until the `issue` table exists to replace it. |

## The one architectural decision

Three owners, no overlap:

- **SQLite** holds the machine's truth — facts, events, issues, signals, the channel.
- **Markdown under `~/notes`** holds what a human reads, generated as a draft rather than authored.
- **Herdr** holds the terminal's truth — workspaces, tabs, panes, focus, agent lifecycle.

Everything else follows from that, so if the split is wrong, most of this is wrong.

## Deliberately not built

A meta-orchestrator session. Mode-switch keybindings. A second log or a dual write. Mirrored Herdr
state. Metrics that never changed a decision. Hand-authored machine documentation. A taxonomy on what
may be posted to the channel. See `docs/spec.md` §10 for why each one is out, with the measurement.

## Not yet a program

There is no code here yet, on purpose. `docs/spec.md` §9 says what day one is, in five steps, and the
first is the database plus a repair tool — because nothing should ship that cannot be fixed at 2am.
