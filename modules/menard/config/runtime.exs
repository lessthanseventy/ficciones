import Config

# The log level, asked for at RUN time rather than baked in: `MENARD_LOG_LEVEL=debug mise run
# menard -- mcp` to watch the transport, anything else stays at the quiet default. Values are
# Logger's own levels; an unknown one falls back to :warning rather than crashing the server.
level =
  case System.get_env("MENARD_LOG_LEVEL") do
    nil ->
      :warning

    name ->
      Enum.find(
        [:emergency, :alert, :critical, :error, :warning, :notice, :info, :debug],
        :warning,
        &(Atom.to_string(&1) == name)
      )
  end

config :logger, level: level
