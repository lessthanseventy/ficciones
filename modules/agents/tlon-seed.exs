# This machine's seed for Tlön — its workspaces and the facts every coworker here must see.
#
# The flake links it to ~/.config/tlon/seed.exs; tlon's Server.Seed applies it on every boot,
# idempotently: a workspace by name (then only its missing projects), a fact by `intent`. The first
# workspace is the default. Product knowledge lives in tlon's own priv/seed, never here.

%{
  workspaces: [
    %{
      name: "Machine",
      scope: "machine",
      roster: [
        %{"archetype" => "surveyor", "name" => "tertius"},
        %{"archetype" => "builder", "name" => "hronir"}
      ],
      projects: [
        %{
          name: "Tlön",
          repos: [
            "~/projects/tlon",
            "~/projects/menard",
            "~/projects/ex_compact",
            "~/projects/mix_master",
            "~/projects/ex_cortex",
            "~/projects/ex_ternal"
          ]
        },
        %{
          name: "ficciones",
          repos: [
            "~/projects/ficciones",
            "~/projects/sudo-whimsy",
            "~/projects/tmux-toolkit",
            "~/projects/claudevim",
            "~/projects/claude-hud"
          ]
        }
      ]
    },
    # No bench: a benched workspace keeps its centre and tail running around the clock. Seat a
    # coworker (the office: W, then + to hire) when real work starts there.
    %{
      name: "Accessibility",
      projects: [
        %{name: "excessibility", repos: ["~/projects/excessibility"]}
      ]
    },
    %{
      name: "Riverside",
      projects: [
        %{name: "ex_riverside", repos: ["~/projects/ex_riverside"]},
        %{name: "silliest_of_gooses", repos: ["~/projects/silliest_of_gooses"]}
      ]
    },
    %{
      name: "DeuceSeven",
      projects: [%{name: "deuce_seven", repos: ["~/projects/deuce_seven"]}]
    }
  ],
  facts: [
    %{
      intent: "machine:operator-vision",
      kind: "constraint",
      provenance: "stated",
      text:
        "The operator, Andrew, has XLRS (X-linked retinoschisis): constant double vision and poor acuity. " <>
          "Every surface he reads uses ComicShannsMono Nerd Font, sized up and never down, amber on black. " <>
          "Design for legibility first; a glyph that relies on fine detail or colour alone is lost on him."
    },
    %{
      intent: "machine:ficciones",
      kind: "constraint",
      provenance: "stated",
      text:
        "This box is configured by ficciones (~/projects/ficciones): a Nix flake with home-manager on Garuda " <>
          "Arch, using pacman's nix (Determinate segfaults here). It wires tlon in by path — the service unit " <>
          "and this seed. `mise run check` is its gate; `mise run home:switch` applies it and is " <>
          "the operator's to run, never an agent's."
    },
    %{
      intent: "machine:fix-or-file:2",
      kind: "constraint",
      provenance: "stated",
      text:
        "Never just note a problem. Every fault you hit gets one fate in the same session: fixed now (reproduced " <>
          "first by a test that goes red, then its own small commit), or filed. File only what someone would act " <>
          "on within a week, and look first: file_ticket and raise_issue show the open items that look like it, " <>
          "and the same fault again is seen_again on that item, never a new one. A nit is a line on the thread, " <>
          "not a ticket. A workaround is not a fix: when the code fights you, fix the code. Closing a ticket takes " <>
          "its evidence: the commit that fixed it, or why it closes without one."
    }
  ]
}
