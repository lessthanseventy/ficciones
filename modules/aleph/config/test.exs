import Config

# Point the operator settings file away from the real ~/.config so the box's own overrides can
# never leak into test assertions; Aleph.Config tests pass explicit paths.
config :aleph, config_path: "/nonexistent/aleph-test-config.json"

# Don't run the app-global Aleph.Worlds cache under test. It subscribes to the funes worlds Bus at
# boot, so worlds registered by the async DB tests (worlds_test.exs) would leak into its cache and
# pollute Space.all/0 for the pure-render tests. Unstarted, fetch_worlds/0 degrades to [] → the
# deterministic hardcoded [:orbis, :tlon] fallback. worlds_test.exs starts its own local pids.
config :aleph, start_worlds: false

# No Repo → nothing for boot integrity to check; keep the one-shot out of the tree.
config :funes, bootstrap: false
config :funes, start_mcp: false

# aleph's own tests exercise the pure render path (panels → lines → composition) headlessly,
# with no DB. So when `mix test` boots funes as a dep, keep its Repo down — otherwise it would
# try to open a database aleph's test env never configures. PubSub still starts (harmless).
config :funes, start_repo: false

# The hub loop (switchboard wake + MCP Bandit) must NOT start under test: no Repo to drain
# against, and a bound MCP port would collide across runs. aleph's tests are the pure render +
# reducer path (config.exs turns these on for the real `aleph.run` hub).
config :funes, start_switchboard: false
