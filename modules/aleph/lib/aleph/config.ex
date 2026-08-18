defmodule Aleph.Config do
  @moduledoc """
  The operator's **runtime settings file** — the knobs the cockpit exposes in-app (the SETTINGS
  panel + verbs) so changing them never means editing Elixir source or re-running `home:switch`.
  A plain JSON map at `~/.config/aleph/config.json` (override with `config :aleph, :config_path`,
  which the test env points away from the real home).

  Shape (all keys optional — absent means "the compiled default wins"):

      {
        "coworkers": {
          "tlon": {"provider": "anthropic", "model": "claude-opus-4-8", "thinking": "medium"}
        }
      }

  `Aleph.Profiles.fetch/1` merges `coworkers.<profile>` over the profile's compiled `model`, so a
  settings change applies wherever the profile flows (materialised settings.json AND the launcher's
  `--model` flag) the next time the coworker spawns. Best-effort on read (a missing or corrupt file
  is just "no overrides"); writes are atomic (tmp + rename) so a crash mid-write can't truncate it.
  """

  @doc "The settings file path (`config :aleph, :config_path` override, else ~/.config/aleph/config.json)."
  @spec path() :: String.t()
  def path do
    Application.get_env(:aleph, :config_path) ||
      Path.join([xdg_config_home(), "aleph", "config.json"])
  end

  @doc "The whole settings map — `%{}` when the file is absent or unreadable (defaults win)."
  @spec read(String.t()) :: map()
  def read(path \\ path()) do
    with {:ok, body} <- File.read(path), {:ok, %{} = map} <- Jason.decode(body) do
      map
    else
      _ -> %{}
    end
  end

  @doc """
  The operator's model override for a coworker profile, or nil (compiled default wins).
  Returned in the `Aleph.Profile.model` shape: `%{provider, model, thinking}` with atom keys.
  """
  @spec coworker_model(String.t(), String.t()) :: map() | nil
  def coworker_model(profile, path \\ path()) do
    case get_in(read(path), ["coworkers", profile]) do
      %{"provider" => prov, "model" => model} = m ->
        %{provider: prov, model: model, thinking: m["thinking"] || "medium"}

      _ ->
        nil
    end
  end

  @doc "Persist a coworker profile's model override (`%{provider, model, thinking}`)."
  @spec put_coworker_model(String.t(), map(), String.t()) :: :ok
  def put_coworker_model(profile, %{provider: prov, model: model, thinking: think}, path \\ path()) do
    path
    |> read()
    |> put_in_new(["coworkers", profile], %{"provider" => prov, "model" => model, "thinking" => think})
    |> write!(path)
  end

  # put_in/2 raises on a missing intermediate map; this seeds it.
  defp put_in_new(map, [k1, k2], value), do: Map.update(map, k1, %{k2 => value}, &Map.put(&1, k2, value))

  # Atomic: write beside the target then rename, so a crash mid-write never truncates the file.
  defp write!(map, path) do
    File.mkdir_p!(Path.dirname(path))
    tmp = path <> ".tmp"
    File.write!(tmp, Jason.encode!(map, pretty: true) <> "\n")
    File.rename!(tmp, path)
    :ok
  end

  defp xdg_config_home do
    System.get_env("XDG_CONFIG_HOME") || Path.join(System.user_home!(), ".config")
  end
end
