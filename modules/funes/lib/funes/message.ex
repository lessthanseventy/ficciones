defmodule Funes.Message do
  @moduledoc """
  A message on a thread — the channel, and §4's capture path. `delivered_at` is
  written only by the switchboard's atomic delivery claim (`Funes.Switchboard`),
  never by a sender — and it can only ever mean delivered, because there is no
  `read` column (day one cannot prove a read, §5b.3). The sender's `post_changeset`
  cannot touch `delivered_at` at all.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "message" do
    field :author, :string
    field :body, :string
    field :created_at, :utc_datetime
    field :delivered_at, :utc_datetime
    # Optional: the message this one replies to (aleph §2). A reply is addressed to
    # the replied-to message's author — one of the three ways delivery is targeted.
    field :reply_to, :id
    belongs_to :thread, Funes.Thread
  end

  @doc """
  A message posted by a participant. A thread, an author, and a body are required
  (§5b). `delivered_at` is intentionally not castable here: the sender's own write
  path can never assert delivery — only the switchboard's atomic claim can.
  """
  def post_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:thread_id, :author, :body, :reply_to])
    |> validate_required([:thread_id, :author, :body])
    |> put_change(:created_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
