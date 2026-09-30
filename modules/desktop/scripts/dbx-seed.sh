#!/usr/bin/env bash
# Seed dbx's store ($DBX_DATA_DIR/dbx.db) before the app starts: the machine's connections and
# the ollama.com AI profile. Every row is create-if-absent by id — after the first launch dbx
# owns the rows, so an edit in its UI is never overwritten. Nothing secret enters the nix store:
# the AI key is read from the agenix file at launch (dbx moves it into its encrypted store on
# first open), and connections whose host/user don't belong in a public repo come from the
# agenix JSON file (an array in dbx's connection shape).
#
# usage: dbx-seed.sh <seed.json>
#   {"connections":[...],"ai":{...},"ai_key_secret":"<name>","extra_connections_secret":"<name>"}
#   the two names are agenix secrets, read from $XDG_RUNTIME_DIR/agenix/<name>
set -euo pipefail

seed="$1"
: "${DBX_DATA_DIR:?}"
umask 077
mkdir -p "$DBX_DATA_DIR"
db="$DBX_DATA_DIR/dbx.db"
agenix="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agenix"

# Same DDL as dbx's own schema (crates/dbx-core/src/persistence/storage.rs); dbx runs
# CREATE TABLE IF NOT EXISTS with these columns and adds the rest itself.
sqlite3 "$db" <<'SQL'
CREATE TABLE IF NOT EXISTS connections (id TEXT PRIMARY KEY, config_json TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS ai_configs (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  model TEXT NOT NULL DEFAULT '',
  models TEXT NOT NULL DEFAULT '[]',
  config_json TEXT NOT NULL,
  is_default INTEGER NOT NULL DEFAULT 0
);
SQL

insert_connections() {
  jq -r '.[] | [.id, (. | tojson)] | @tsv' "$1" | while IFS=$'\t' read -r id json; do
    sqlite3 "$db" "INSERT OR IGNORE INTO connections (id, config_json) VALUES ('$id', '${json//\'/\'\'}');"
  done
}

jq '.connections' "$seed" > "$DBX_DATA_DIR/.seed-connections.json"
insert_connections "$DBX_DATA_DIR/.seed-connections.json"
rm -f "$DBX_DATA_DIR/.seed-connections.json"

extra="$agenix/$(jq -r '.extra_connections_secret' "$seed")"
[ -f "$extra" ] && insert_connections "$extra"

# The AI profile waits for the key file: inserting it without a key would freeze an empty key
# in place (create-if-absent), and dbx needs the bearer token for ollama.com.
key_file="$agenix/$(jq -r '.ai_key_secret' "$seed")"
if [ -f "$key_file" ]; then
  key=$(tr -d '\n' < "$key_file")
  ai=$(jq -c --arg key "$key" '.ai.config + {api_key: $key}' "$seed")
  id=$(jq -r '.ai.id' "$seed")
  name=$(jq -r '.ai.name' "$seed")
  model=$(jq -r '.ai.config.model' "$seed")
  sqlite3 "$db" "INSERT OR IGNORE INTO ai_configs (id, name, model, models, config_json, is_default) VALUES ('$id', '$name', '$model', '[]', '${ai//\'/\'\'}', 1);"
fi
