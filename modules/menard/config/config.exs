import Config

# `mix menard.mcp` speaks MCP over stdio, where STDOUT IS THE PROTOCOL CHANNEL: the spec says a
# stdio server must not write anything to stdout that is not a valid MCP message, and that logs
# belong on stderr. Elixir logs to stdout by default, so every transport debug line landed
# mid-protocol — tolerated by the client, but bytes in a channel that has no room for them.
config :logger, :default_handler, config: %{type: :standard_error}

# And quiet by default: the transport logs every frame at :debug. Ask for more with
# MENARD_LOG_LEVEL=debug (read in runtime.exs).
config :logger, level: :warning
