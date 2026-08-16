defmodule Aleph.Style do
  @moduledoc """
  The one palette. Panels render in **semantic styles** (`:header`, `:warm`, `:selected`, …),
  never raw hex — so the whole cockpit reads as one surface and a re-theme is one edit here,
  not a hunt through every panel (design §3: panels are thin; presentation is centralized).

  Colors are 24-bit RGB for termbox2's `TB_OUTPUT_TRUECOLOR` (see `Mix.Tasks.Aleph.Run`);
  `@bg` is `0x000000`, which truecolor maps to the terminal's own background.
  """

  @bg 0x000000

  # 80s phosphor green (#33FF00) is the body — content/strings, the bulk of the surface. Amber
  # (#FFB000) is the *chrome* — titles, labels, warm dots — where it pops instead of tiring the
  # eye everywhere. Pink flags the agents, burnt orange draws the structure, and a deep violet
  # wash marks selection. A CRT "cyber hacker" surface on black. The dark hex (`@sel`) is a
  # background, where deep colour reads best.
  @sel 0x5B00AE

  # The two canonical phosphors: green #33FF00 (body) and amber #FFB000 (chrome).
  @green 0x33FF00
  @amber 0xFFB000

  @colors %{
    normal: {@green, @bg},
    header: {@amber, @bg},
    label: {@amber, @bg},
    accent: {0xE0218A, @bg},
    warm: {@amber, @bg},
    dim: {0x9A803F, @bg},
    separator: {0xB5651D, @bg},
    selected: {0xFFF4C2, @sel},
    selected_accent: {0xFFFFFF, @sel}
  }

  @doc "The `{fg, bg}` truecolor pair for a semantic style. Unknown styles fall back to `:normal`."
  @spec fg_bg(atom()) :: {non_neg_integer(), non_neg_integer()}
  def fg_bg(style), do: Map.get(@colors, style, @colors.normal)

  @doc "The default background (terminal-native black under truecolor)."
  def bg, do: @bg
end
