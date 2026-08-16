defmodule Mix.Tasks.Aleph.Run do
  @shortdoc "Eye test: paint the read-only cockpit board to this terminal, then restore"
  @moduledoc """
  Run in a REAL terminal (ghostty): `mise run aleph:run`.

  Paints a sample 25/50/25 cockpit board straight to the terminal via the termbox2
  NIF, holds it for ~6 seconds, then restores the screen. This is the on-screen paint
  proof the headless tests can't give — they render into an in-memory `ScreenBuffer`
  but can't drive a TTY.

  The left column runs the real `Aleph.Panel.Roster` render; the rest is sample data.
  Wiring the live funes Bus (so it re-renders on `Channel.post/1`) and routing through
  `Aleph.Board`'s `ScreenBuffer` via the termbox `Driver` are the next steps
  (design §9). Until then this draws cells directly.
  """
  use Mix.Task

  @white 0xFFFFFF
  @black 0x000000
  @cyan 0x00FFFF

  # termbox2 defaults to TB_OUTPUT_NORMAL, where color args are small ints [0..8] and
  # the high bits are style attributes (bold/reverse/…). Feeding it 0xRRGGBB there
  # truncates into those attribute bits — that's the reversed highlight block behind
  # every glyph. TB_OUTPUT_TRUECOLOR (5) makes tb_set_cell take real 24-bit RGB, and
  # 0x000000 maps to the terminal's own background. Set once after tb_init, before paint.
  @tb_output_truecolor 5

  @roster [
    %{
      agent: "Sandra",
      thread_id: 1,
      thread_title: "review PR 329",
      workspace_ref: nil,
      warm?: true
    },
    %{
      agent: "Robert",
      thread_id: 2,
      thread_title: "triage inbox",
      workspace_ref: nil,
      warm?: false
    },
    %{
      agent: "Carl",
      thread_id: 3,
      thread_title: "flaky test hunt",
      workspace_ref: nil,
      warm?: false
    }
  ]

  @dossier [
    "NORTH STAR",
    "  ship the aleph board",
    "",
    "LEARNINGS",
    "  raxol_terminal renders;",
    "  termbox2 compiles on this box",
    "",
    "BLOCKERS",
    "  none",
    "",
    "SHIPPED",
    "  the read-only render path",
    "",
    "CHATTER",
    "  Sandra: pushing the panel behaviour"
  ]

  @impl Mix.Task
  def run(_args) do
    case :termbox2_nif.tb_init() do
      0 ->
        try do
          :termbox2_nif.tb_set_output_mode(@tb_output_truecolor)
          paint()
          :termbox2_nif.tb_present()
          Process.sleep(6000)
        after
          :termbox2_nif.tb_shutdown()
        end

        Mix.shell().info("aleph eye-test: painted the cockpit for 6s, screen restored.")

      other ->
        Mix.shell().error(
          "tb_init failed (#{inspect(other)}) — run this in a real terminal (ghostty), not headless."
        )
    end
  end

  defp paint do
    :termbox2_nif.tb_clear()
    w = :termbox2_nif.tb_width()
    h = :termbox2_nif.tb_height()

    left_w = div(w, 4)
    center_w = div(w, 2)
    right_x = left_w + center_w
    right_w = w - right_x

    # column separators
    for y <- 0..(h - 1) do
      cell(left_w, y, ?│)
      cell(right_x, y, ?│)
    end

    # corporate-deadpan headers (§4 register)
    draw(1, 0, "IN FLIGHT", @cyan)
    draw(left_w + 2, 0, "SESSION", @cyan)
    draw(right_x + 2, 0, "IN SCOPE", @cyan)

    # left 25%: the real roster panel
    rect = %{x: 1, y: 2, w: max(left_w - 2, 1), h: max(h - 3, 1)}

    @roster
    |> Aleph.Panel.Roster.render(rect)
    |> Enum.with_index()
    |> Enum.each(fn {line, i} -> draw(1, 2 + i, line, @white) end)

    # center 50%: the placeholder (the tmux-client embed is step 2)
    draw(left_w + 2, 2, "tmux client / pi session", @white)
    draw(left_w + 2, 3, "(embedded here — step 2)", @white)

    # right 25%: the dossier
    @dossier
    |> Enum.take(max(h - 3, 0))
    |> Enum.with_index()
    |> Enum.each(fn {line, i} ->
      draw(right_x + 2, 2 + i, String.slice(line, 0, max(right_w - 3, 1)), @white)
    end)
  end

  defp draw(x, y, str, fg) do
    str
    |> String.to_charlist()
    |> Enum.with_index()
    |> Enum.each(fn {cp, i} -> :termbox2_nif.tb_set_cell(x + i, y, cp, fg, @black) end)
  end

  defp cell(x, y, cp), do: :termbox2_nif.tb_set_cell(x, y, cp, @white, @black)
end
