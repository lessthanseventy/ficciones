defmodule Aleph.Style do
  @moduledoc """
  The one palette. Panels render in **semantic styles** (`:header`, `:warm`, `:selected`, …),
  never raw hex — so the whole cockpit reads as one surface and a re-theme is one edit here,
  not a hunt through every panel (design §3: panels are thin; presentation is centralized).

  Colors are 24-bit RGB for termbox2's `TB_OUTPUT_TRUECOLOR` (see `Mix.Tasks.Aleph.Run`);
  `@bg` is `0x000000`, which truecolor maps to the terminal's own background.
  """

  @bg 0x000000

  # Retro amber/green phosphor with a hot-pink pop: amber is the primary text, green marks life
  # and labels, burnt orange draws the structure, and pink flags the agents — a CRT "cyber
  # hacker" surface on black. One accent per meaning.
  @colors %{
    normal: {0xFFB454, @bg},
    header: {0xFFD75F, @bg},
    label: {0x5FD75F, @bg},
    accent: {0xE0218A, @bg},
    warm: {0x5FFF87, @bg},
    dim: {0x9A803F, @bg},
    separator: {0xB5651D, @bg},
    selected: {0xFFD75F, 0x332600},
    selected_accent: {0xFFF4C2, 0x332600}
  }

  @doc "The `{fg, bg}` truecolor pair for a semantic style. Unknown styles fall back to `:normal`."
  @spec fg_bg(atom()) :: {non_neg_integer(), non_neg_integer()}
  def fg_bg(style), do: Map.get(@colors, style, @colors.normal)

  @doc "The default background (terminal-native black under truecolor)."
  def bg, do: @bg
end
