defmodule Funes.Recall.CutoverTest do
  # The cutover flags (design: docs/plans/2026-08-19-funes-forgetting-design.md): both default OFF,
  # so the engine lands wired-dark. These assert the gates read config and the embed-on-write hook
  # is a no-op-returning side effect — never load-bearing on the write result.
  use ExUnit.Case, async: false

  alias Funes.Channel
  alias Funes.Dossier
  alias Funes.Recall

  setup do
    Funes.TestDB.clean!()

    on_exit(fn ->
      Application.delete_env(:funes, :embed_on_write)
      Application.delete_env(:funes, :recall)
    end)

    :ok
  end

  describe "flags default off" do
    test "embed_on_write? and read_enabled? are false with nothing configured" do
      Application.delete_env(:funes, :embed_on_write)
      Application.delete_env(:funes, :recall)
      refute Recall.embed_on_write?()
      refute Recall.read_enabled?()
    end

    test "each flag flips only on an explicit true" do
      Application.put_env(:funes, :embed_on_write, true)
      Application.put_env(:funes, :recall, enabled: true)
      assert Recall.embed_on_write?()
      assert Recall.read_enabled?()

      # A non-true value (a stray string, a bare keyword) does NOT arm the gate.
      Application.put_env(:funes, :embed_on_write, "1")
      Application.put_env(:funes, :recall, enabled: "yes")
      refute Recall.embed_on_write?()
      refute Recall.read_enabled?()
    end
  end

  describe "maybe_embed_on_write/1" do
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "t"})
      {:ok, fact} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "x", provenance: "derived"})
      %{fact: fact}
    end

    test "returns the fact unchanged and never raises when off", %{fact: fact} do
      Application.delete_env(:funes, :embed_on_write)
      assert Recall.maybe_embed_on_write(fact) == fact
    end

    test "returns the fact synchronously when on (the embed is fire-and-forget)", %{fact: fact} do
      Application.put_env(:funes, :embed_on_write, true)
      # The write result is the fact itself — the embedder runs off the write path under the
      # TaskSupervisor, so a down ollama can't fail or block this call.
      assert Recall.maybe_embed_on_write(fact) == fact
    end
  end
end
