defmodule Aleph.Profile do
  @moduledoc """
  A **coworker profile** — the full pi configuration for one space's machine coworker. A space
  (`Aleph.Space`) names a profile; the cockpit materialises it into a `PI_CODING_AGENT_DIR` and
  launches the coworker with it. Profiles differ on the four dimensions a coworker actually varies
  on (design: `docs/plans/2026-08-17-pi-coworker-profiles-design.md`):

    * **tool / MCP surface** — `mcp` (`:base` inherit, `:none` self-contained, or an explicit
      `%{server => config}`) and `drop_extensions` (which pi extensions to omit).
    * **model + thinking** — `model` (`%{provider, model, thinking}`, or `nil` to inherit the base
      defaults).
    * **system prompt / persona** — `system_prompt` (materialised to a file, passed as
      `--append-system-prompt`).
    * **sandbox** — `sandbox` (a pi-sandbox `sandbox.json` map, or `nil` for unconfined). Scoped to
      the profile because pi-sandbox reads `sandbox.json` from `PI_CODING_AGENT_DIR`.

  A profile is a small DIFF from the base `~/.pi/agent` config, not a full re-declaration — the base
  (extensions, skills, model catalog, auth) stays the single source of truth; the profile drops,
  replaces, and overlays.
  """
  @enforce_keys [:name]
  defstruct name: nil,
            drop_extensions: [],
            mcp: :base,
            model: nil,
            system_prompt: nil,
            sandbox: nil

  @type t :: %__MODULE__{
          name: String.t(),
          drop_extensions: [String.t()],
          mcp: :base | :none | map(),
          model: %{provider: String.t(), model: String.t(), thinking: String.t()} | nil,
          system_prompt: String.t() | nil,
          sandbox: map() | nil
        }
end

defmodule Aleph.Profiles do
  @moduledoc """
  The coworker-profile registry + materialiser. `fetch/1` looks a profile up by name; `render/3`
  is the pure seam (profile + base config → the files a config dir needs); `materialise!/1` is the
  IO wrapper that writes `~/.pi/profiles/<name>/` at cockpit start.

  Materialised layout (`PI_CODING_AGENT_DIR`):

      ~/.pi/profiles/<name>/
        settings.json     profile-specific — base settings with extensions dropped + model overridden
        mcp.json          profile-specific — the profile's MCP servers (`{}` = self-contained)
        sandbox.json      profile-specific — pi-sandbox allowlist (only if profile.sandbox)
        system_prompt.md  profile-specific — the persona (only if profile.system_prompt)
        auth.json      ↳ symlink to ~/.pi/agent/auth.json       (shared credentials)
        models.json    ↳ symlink to ~/.pi/agent/models.json     (shared model catalog)
        models-store.json ↳ symlink                             (shared)
        sessions/         its own — each coworker resumes its own thread (reload --continue)

  Idempotent + self-healing: re-materialised every cockpit start, so editing a profile + restarting
  the cockpit is the whole loop — no `home:switch`.
  """
  alias Aleph.Profile

  # Single-user machine — the repo the coworker writes in (matches flake.nix's `repo`). Used for the
  # Tlön sandbox's write allowlist.
  @repo "/home/andrew/projects/ficciones"

  # The Tlön coworker's sandbox (pi-sandbox `sandbox.json`). Permissive enough that the manos tooling
  # keeps working under bubblewrap — the footgun class this session kept hitting:
  #   * allowAllUnixSockets — the lsp shim binds/connects manos-lspd.sock; reload/tmux use sockets too
  #   * allowWrite the repo + /tmp + the socket dir + caches — the daemon writes the socket file, Expert
  #     writes its .expert index, edits land in the repo
  #   * allowedDomains — the hosts this repo's bash tasks reach (mirrors the machine sandbox allowlist)
  # See [[pi-sandbox-manos-allowlist]]. NOT model API calls (pi's own process, not bash).
  @tlon_sandbox %{
    "enabled" => true,
    "network" => %{
      "allowLocalBinding" => true,
      "allowAllUnixSockets" => true,
      "allowedDomains" => [
        "github.com",
        "*.github.com",
        "*.githubusercontent.com",
        "hex.pm",
        "*.hex.pm",
        "registry.npmjs.org",
        "mise.jdx.dev",
        "ollama.com",
        "registry.ollama.ai",
        "cache.nixos.org",
        "channels.nixos.org",
        "nixos.org"
      ]
    },
    "filesystem" => %{
      "allowWrite" => [@repo, "/tmp", "$XDG_RUNTIME_DIR", "~/.pi", "~/.cache", "~/.local"],
      "allowRead" => [@repo, "~/.config", "~/.local", "~/.pi", "~/.cache"],
      "denyWrite" => [".env", ".env.*", "*.pem", "*.key"]
    }
  }

  # The registry. Tlön: self-contained (no funes MCP), the funes-brief extension (manos/pi) dropped,
  # sandboxed. Driver model is glm-5.2 (ollama-cloud) — a capable ORCHESTRATOR that stays lean by
  # delegating heavy/cheap work to workers via /consult and spawned tabs (route those to LOCAL
  # qwen3-coder / flash to keep the flat cloud plan cool). Not flash: flash context-overflowed on real
  # builds. Not the pro/max tier: mid-tier hedges the plan's usage caps. See design §orchestrator.
  @profiles [
    %Profile{
      name: "tlon",
      drop_extensions: ["/manos/pi/"],
      mcp: :none,
      model: %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"},
      sandbox: @tlon_sandbox
    }
  ]

  @doc "Look a profile up by name, or nil."
  @spec fetch(String.t()) :: Profile.t() | nil
  def fetch(name), do: Enum.find(@profiles, &(&1.name == name))

  @doc """
  Pure: profile + the base `settings.json`/`mcp.json` maps → the files the profile's config dir needs.
  Returns `%{settings: map, mcp: map, sandbox: map | nil, system_prompt: binary | nil}`.
  """
  @spec render(Profile.t(), map(), map()) :: %{
          settings: map(),
          mcp: map(),
          sandbox: map() | nil,
          system_prompt: String.t() | nil
        }
  def render(%Profile{} = p, base_settings, base_mcp) do
    exts =
      Enum.reject(base_settings["extensions"] || [], fn e -> Enum.any?(p.drop_extensions, &String.contains?(e, &1)) end)

    settings =
      base_settings
      |> Map.put("extensions", exts)
      |> apply_model(p.model)

    mcp =
      case p.mcp do
        :base -> base_mcp
        :none -> %{"mcpServers" => %{}}
        servers when is_map(servers) -> %{"mcpServers" => servers}
      end

    %{settings: settings, mcp: mcp, sandbox: p.sandbox, system_prompt: p.system_prompt}
  end

  defp apply_model(settings, nil), do: settings

  defp apply_model(settings, %{provider: prov, model: model, thinking: think}) do
    settings
    |> Map.put("defaultProvider", prov)
    |> Map.put("defaultModel", model)
    |> Map.put("defaultThinkingLevel", think)
  end

  @doc "The config dir a profile materialises into (its `PI_CODING_AGENT_DIR`)."
  @spec config_dir(String.t()) :: String.t()
  def config_dir(name), do: Path.join([base_dir_root(), "profiles", name])

  @doc """
  Materialise a profile's config dir from the base `~/.pi/agent`. Reads the base settings/mcp, renders,
  writes the profile-specific files, and symlinks the shared ones. Idempotent. Returns the dir.

  `opts[:base]` / `opts[:root]` override the base config dir and the profiles root (for tests).
  """
  @spec materialise!(Profile.t(), keyword()) :: String.t()
  def materialise!(%Profile{} = p, opts \\ []) do
    base = opts[:base] || Path.join(base_dir_root(), "agent")
    root = opts[:root] || Path.join(base_dir_root(), "profiles")
    dir = Path.join(root, p.name)
    File.mkdir_p!(dir)

    base_settings = read_json(Path.join(base, "settings.json"), %{})
    base_mcp = read_json(Path.join(base, "mcp.json"), %{"mcpServers" => %{}})
    r = render(p, base_settings, base_mcp)

    write_json!(Path.join(dir, "settings.json"), r.settings)
    write_json!(Path.join(dir, "mcp.json"), r.mcp)

    if r.sandbox, do: write_json!(Path.join(dir, "sandbox.json"), r.sandbox)
    if r.system_prompt, do: File.write!(Path.join(dir, "system_prompt.md"), r.system_prompt)

    # Shared, from the base: one credential store, one model catalog. Relink each time (idempotent).
    for f <- ~w(auth.json models.json models-store.json) do
      link = Path.join(dir, f)
      _ = File.rm(link)
      _ = File.ln_s(Path.join(base, f), link)
    end

    dir
  end

  # The pi config-dir root (honours PI_CODING_AGENT_DIR's parent so a redirected base still finds
  # profiles beside it; falls back to ~/.pi).
  defp base_dir_root do
    case System.get_env("PI_CODING_AGENT_DIR") do
      nil -> Path.expand("~/.pi")
      dir -> Path.dirname(Path.expand(dir))
    end
  end

  defp read_json(path, default) do
    with {:ok, body} <- File.read(path), {:ok, map} <- Jason.decode(body) do
      map
    else
      _ -> default
    end
  end

  defp write_json!(path, map), do: File.write!(path, Jason.encode!(map, pretty: true) <> "\n")
end
