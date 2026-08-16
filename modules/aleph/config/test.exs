import Config

config :funes, start_mcp: false

# aleph's own tests exercise the pure render path (panels → lines → composition) headlessly,
# with no DB. So when `mix test` boots funes as a dep, keep its Repo down — otherwise it would
# try to open a database aleph's test env never configures. PubSub still starts (harmless).
config :funes, start_repo: false

# The hub loop (switchboard wake + MCP Bandit) must NOT start under test: no Repo to drain
# against, and a bound MCP port would collide across runs. aleph's tests are the pure render +
# reducer path (config.exs turns these on for the real `aleph.run` hub).
config :funes, start_switchboard: false
