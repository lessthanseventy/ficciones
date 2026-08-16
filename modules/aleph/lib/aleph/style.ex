defmodule Aleph.Style do
  @moduledoc """
  The one palette. Panels render in **semantic styles** (`:header`, `:warm`, `:selected`, …),
  never raw hex — so the whole cockpit reads as one surface and a re-theme is one edit here,
  not a hunt through every panel (design §3: panels are thin; presentation is centralized).

  Colors are 24-bit RGB for termbox2's `TB_OUTPUT_TRUECOLOR` (see `Mix.Tasks.Aleph.Run`);
  `@bg` is `0x000000`, which truecolor maps to the terminal's own background.
  """

  @bg 0x000000

  # Tokyo-night-ish: calm on black, one cyan accent, warmth in green, cold in slate.
  @colors %{
    normal: {0xC0CAF5, @bg},
    header: {0x7DCFFF, @bg},
    label: {0x7AA2F7, @bg},
    accent: {0xFFFFFF, @bg},
    warm: {0x9ECE6A, @bg},
    dim: {0x565F89, @bg},
    separator: {0x3B4261, @bg},
    selected: {0xC0CAF5, 0x283457},
    selected_accent: {0xFFFFFF, 0x283457}
  }

  @doc "The `{fg, bg}` truecolor pair for a semantic style. Unknown styles fall back to `:normal`."
  @spec fg_bg(atom()) :: {non_neg_integer(), non_neg_integer()}
  def fg_bg(style), do: Map.get(@colors, style, @colors.normal)

  @doc "The default background (terminal-native black under truecolor)."
  def bg, do: @bg
end
