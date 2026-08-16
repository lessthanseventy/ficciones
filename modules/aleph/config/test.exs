import Config

# aleph's own tests exercise the pure render path (panels → lines → composition) headlessly,
# with no DB. So when `mix test` boots funes as a dep, keep its Repo down — otherwise it would
# try to open a database aleph's test env never configures. PubSub still starts (harmless).
config :funes, start_repo: false
