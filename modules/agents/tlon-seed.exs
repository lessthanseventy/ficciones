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
        %{name: "excessibility", repos: ["~/projects/excessibility"]},
        %{name: "a11y-with-phoenix-guide", repos: ["~/projects/a11y-with-phoenix-guide"]}
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
          "Arch, using pacman's nix (Determinate segfaults here). It wires tlon in by path — the service unit, " <>
          "pi's models and this seed. `mise run check` is its gate; `mise run home:switch` applies it and is " <>
          "the operator's to run, never an agent's."
    },
    %{
      intent: "machine:fix-or-file",
      kind: "constraint",
      provenance: "stated",
      text:
        "Never just note a problem. Every fault you hit gets one fate in the same session: fixed now (reproduced " <>
          "first by a test that goes red, then its own small commit), or filed — a Tlön ticket when it is small and " <>
          "later, a new Tlön thread on its project when it needs a conversation. A workaround is not a fix: when the " <>
          "code fights you, fix the code. A report says what was fixed and which ticket or thread each deferred " <>
          "thing went to."
    }
  ]
}
