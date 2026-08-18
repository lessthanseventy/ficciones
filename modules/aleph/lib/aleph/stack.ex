defmodule Aleph.Stack do
  @moduledoc """
  The machine/stack read models for the **Tlön** space (§the meta lens): what's changed in the
  env (recent `ficciones` commits with relative time and author — the stack's own changelog),
  what's installed (tool versions), and what's the system state (branch, dirty status, nix
  generation, disk/memory). Best-effort and honest: a missing `git` or tool yields an empty/`"?"`
  value, never a crash. Tool versions are cached in `:persistent_term` (they don't change
  mid-session); commits and system state are read fresh on each Cockpit tick.
  """
  @default_tools [
    {"pi", ["--version"]},
    {"claude", ["--version"]},
    {"nix", ["--version"]},
    {"mise", ["--version"]},
    {"tmux", ["-V"]}
  ]

  @doc "Recent `ficciones` commits as `[%{hash, subject, time, author}]`, newest first (best-effort, fresh)."
  def commits(dir \\ ".", n \\ 8) do
    case cmd("git", ["-C", dir, "log", "--format=#{format()}", "-n", Integer.to_string(n)]) do
      {:ok, out} -> out |> String.split("\n", trim: true) |> Enum.map(&parse_commit/1)
      :error -> []
    end
  end

  @doc "Current branch name, or nil if not in a git repo."
  def branch(dir \\ ".") do
    case cmd("git", ["-C", dir, "branch", "--show-current"]) do
      {:ok, out} -> out |> String.trim() |> then(&if &1 == "", do: nil, else: &1)
      :error -> nil
    end
  end

  @doc "Whether the working tree has uncommitted changes (best-effort)."
  def dirty?(dir \\ ".") do
    case cmd("git", ["-C", dir, "status", "--porcelain"]) do
      {:ok, out} -> String.trim(out) != ""
      :error -> false
    end
  end

  @doc "Installed tool versions as `[%{name, version}]`, cached after the first probe."
  def tools do
    case :persistent_term.get({__MODULE__, :tools}, nil) do
      nil ->
        probed = Enum.map(@default_tools, fn {name, args} -> %{name: name, version: version(name, args)} end)
        :persistent_term.put({__MODULE__, :tools}, probed)
        probed

      cached ->
        cached
    end
  end

  # One nix-env call, shared by nix_generation and nix_behind — halves the subprocess
  # fork per health_read. Returns {current_gen, behind_count} or {nil, nil} on failure.
  # nix-env --list-generations prints one gen per line; the current gen is marked "(current)".
  # "Behind" = how many generations have a higher number than the current one (rollback gap).
  # Tries home-manager first (common on non-NixOS), then the system profile.
  defp nix_generation_and_behind do
    Enum.reduce_while(nix_profile_paths(), {nil, nil}, fn path, _acc ->
      case cmd("nix-env", ["--list-generations", "--profile", path]) do
        {:ok, out} ->
          result = parse_nix_gens(out)
          if elem(result, 0) == nil, do: {:cont, {nil, nil}}, else: {:halt, result}

        :error ->
          {:cont, {nil, nil}}
      end
    end)
  end

  # Profile paths to try, in order: home-manager (non-NixOS), then the system default.
  defp nix_profile_paths do
    home = System.user_home!()
    [Path.join(home, ".local/state/nix/profiles/home-manager"), "/nix/var/nix/profiles/default"]
  end

  defp parse_nix_gens(out) do
    lines = String.split(out, "\n", trim: true)

    current_gen =
      Enum.find_value(lines, fn line ->
        if String.contains?(line, "(current)"), do: parse_nix_gen(line)
      end)

    behind =
      if current_gen do
        Enum.count(lines, fn line ->
          gen = parse_nix_gen(line)
          gen != nil and gen > current_gen
        end)
      else
        0
      end

    {current_gen, behind}
  end

  @doc "Current nix generation number, or nil. Best-effort: nil if nix isn't available."
  def nix_generation, do: elem(nix_generation_and_behind(), 0)

  @doc "How many generations behind the current one is. 0 means current, nil if unknown."
  def nix_behind, do: elem(nix_generation_and_behind(), 1)

  @doc "Disk usage percentage for the root filesystem (best-effort)."
  def disk_pct do
    # GNU coreutils uses `pcent` (percent), not `pct`. Fall back to parsing `df -h`
    # on systems where --output isn't available.
    case cmd("df", ["--output=pcent", "/"]) do
      {:ok, out} ->
        out |> String.split("\n", trim: true) |> List.last() |> String.trim() |> parse_pct()

      :error ->
        case cmd("df", ["-h", "/"]) do
          {:ok, out} ->
            out
            |> String.split("\n", trim: true)
            |> List.last()
            |> String.split()
            |> Enum.at(-2, "")
            |> String.replace("%", "")
            |> parse_pct()

          :error ->
            nil
        end
    end
  end

  @doc "Memory usage percentage (best-effort, reads from /proc/meminfo on Linux)."
  def mem_pct do
    case File.read("/proc/meminfo") do
      {:ok, content} ->
        with {total, _} <- parse_mem_line(content, "MemTotal:"),
             {available, _} <- parse_mem_line(content, "MemAvailable:") do
          if total > 0, do: round((total - available) / total * 100)
        else
          _ -> nil
        end

      {:error, _} ->
        nil
    end
  end

  @doc "System 1-minute load average, or nil. Best-effort, reads /proc/loadavg on Linux."
  def load_avg do
    case File.read("/proc/loadavg") do
      {:ok, content} ->
        case String.split(content) do
          [one_min | _] ->
            case Float.parse(one_min) do
              {f, _} -> Float.round(f, 2)
              :error -> nil
            end

          _ ->
            nil
        end

      {:error, _} ->
        nil
    end
  end

  @doc "Commits ahead/behind the tracking branch, or {nil, nil}. Best-effort."
  def ahead_behind(dir \\ ".") do
    case cmd("git", ["-C", dir, "rev-list", "--left-right", "--count", "@{upstream}...HEAD"]) do
      {:ok, out} ->
        case String.split(String.trim(out), "\t", parts: 2) do
          [behind, ahead] ->
            {to_integer(ahead), to_integer(behind)}

          _ ->
            {nil, nil}
        end

      :error ->
        {nil, nil}
    end
  end

  @doc """
  Git status summary: %{staged, unstaged, untracked} counts from `git status --porcelain`.
  Nil if not in a git repo. Staged = files in the index (X column not blank/?);
  unstaged = modified in the worktree (Y column not blank/?); untracked = `??` lines.
  """
  def status_summary(dir \\ ".") do
    case cmd("git", ["-C", dir, "status", "--porcelain"]) do
      {:ok, out} ->
        lines = String.split(out, "\n", trim: true)

        staged =
          Enum.count(lines, fn l ->
            String.length(l) >= 1 and String.at(l, 0) not in [" ", "?"]
          end)

        unstaged =
          Enum.count(lines, fn l ->
            String.length(l) >= 2 and String.at(l, 1) not in [" ", "?"]
          end)

        untracked = Enum.count(lines, &String.starts_with?(&1, "??"))
        %{staged: staged, unstaged: unstaged, untracked: untracked}

      :error ->
        nil
    end
  end

  @doc "Whether the funes always-up service is reachable on :4040."
  def funes_up? do
    case :gen_tcp.connect(~c"127.0.0.1", 4040, [], 500) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  @doc "Whether the tlon tmux session exists — on the coworker's private server (`-L aleph-tlon`)."
  def tlon_up? do
    case cmd("tmux", ["-L", Aleph.Profiles.socket("tlon"), "has-session", "-t", "tlon"]) do
      {:ok, _} -> true
      :error -> false
    end
  end

  # -- format: hash<tab>relative_time<tab>author_name<tab>subject
  defp format, do: "%h%x09%ar%x09%an%x09%s"

  defp parse_commit(line) do
    case String.split(line, "\t", parts: 4) do
      [hash, time, author, subject] -> %{hash: hash, time: time, author: author, subject: subject}
      [hash, subject] -> %{hash: hash, time: "?", author: "?", subject: subject}
      [hash] -> %{hash: hash, time: "?", author: "?", subject: ""}
    end
  end

  defp parse_nix_gen(nil), do: nil
  defp parse_nix_gen(line), do: line |> String.split() |> List.first() |> to_integer()

  defp to_integer(nil), do: nil

  defp to_integer(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_pct(s) do
    case Integer.parse(String.trim(s)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_mem_line(content, prefix) do
    case Regex.run(~r/#{prefix}\s+(\d+)/, content) do
      [_, num] -> {String.to_integer(num), content}
      _ -> nil
    end
  end

  # First non-empty line of the tool's version output, or "?" if it isn't installed / errored.
  defp version(name, args) do
    case cmd(name, args) do
      {:ok, out} -> out |> String.split("\n", trim: true) |> List.first() |> to_string() |> String.trim()
      :error -> "?"
    end
  end

  defp cmd(bin, args) do
    case System.cmd(bin, args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      _ -> :error
    end
  rescue
    ErlangError -> :error
  end
end
