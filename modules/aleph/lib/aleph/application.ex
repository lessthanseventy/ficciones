defmodule Aleph.Application do
  @moduledoc """
  aleph's OTP entrypoint. For now it supervises nothing — the read-only board's
  render path is pure, and the live-Bus subscription + the termbox `Driver` loop
  are wired in later steps (see `docs/plans/2026-08-15-aleph-tui-design.md` §9).
  """
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([], strategy: :one_for_one, name: Aleph.Supervisor)
  end
end
