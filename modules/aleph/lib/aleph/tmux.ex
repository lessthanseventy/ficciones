defmodule Aleph.Tmux do
  @moduledoc """
  The thin tmux adapter for the center surface (design §2/§5): tmux stays the multiplexer; aleph
  only *renders a view* of a pane and forwards keys to it. Nothing is mirrored — the pane is read
  live at the point of use (`capture-pane`) and cached nowhere. A missing tmux binary or a dead
  pane is not an error here, it's `:no_session` — the panel shows an honest placeholder.

  `target` is a tmux pane spec (funes' opaque `pane_ref`), e.g. `"work:1.0"` or a `%<pane-id>`.
  """

  @doc """
  The visible content of a pane as a list of plain lines (at most `h`), or `:no_session` when the
  pane can't be read. `capture-pane -p` is the plain snapshot; colour (`-e` + SGR) is a later polish.
  """
  @spec capture(String.t() | nil, %{h: pos_integer()}) :: [String.t()] | :no_session
  def capture(nil, _dims), do: :no_session

  def capture(target, %{h: h}) do
    case run(["capture-pane", "-p", "-t", target]) do
      {:ok, out} -> out |> String.split("\n") |> Enum.take(h)
      :error -> :no_session
    end
  end

  @doc "Forward literal text to a pane (used when the center is focused). Best-effort; ignores failure."
  @spec send_text(String.t() | nil, String.t()) :: :ok
  def send_text(nil, _text), do: :ok

  def send_text(target, text) do
    run(["send-keys", "-t", target, "-l", text])
    :ok
  end

  @doc "Forward a named key (tmux key name, e.g. `Enter`, `Up`, `C-c`) to a pane. Best-effort."
  @spec send_key(String.t() | nil, String.t()) :: :ok
  def send_key(nil, _key), do: :ok

  def send_key(target, key) do
    run(["send-keys", "-t", target, key])
    :ok
  end

  # Run a tmux command. `{:ok, stdout}` on success; `:error` on non-zero OR a missing binary
  # (System.cmd raises when tmux isn't installed — a headless CI box, say — which we treat as
  # "no session" rather than a crash).
  defp run(args) do
    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      _ -> :error
    end
  rescue
    ErlangError -> :error
  end
end
