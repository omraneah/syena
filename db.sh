#!/usr/bin/env bash
# DuckDB on the HappyPet CSV. The database is in memory: every run reloads the CSV
# through sql/load.sql, so there is no database file to lock, rebuild or leak.
#
#   ./db.sh                          interactive shell (tables raw_actes, actes; macro police('<reference>'))
#   ./db.sh sql/quality_checks.sql   run a SQL file and exit
#   CSV=other.csv ./db.sh            use another CSV with the same columns
set -euo pipefail

cd "$(dirname "$0")"

CSV="${CSV:-donnees_case_data_integration_anonymise.csv}"
DUCKDB="$(command -v duckdb || echo "$HOME/.local/bin/duckdb")"

if [[ ! -x "$DUCKDB" ]]; then
  echo "duckdb not found (expected on PATH or at ~/.local/bin/duckdb)" >&2
  exit 1
fi
if [[ ! -f "$CSV" ]]; then
  echo "CSV not found: $CSV" >&2
  exit 1
fi

SET_CSV="SET VARIABLE csv_path = '${CSV//\'/\'\'}'"

if [[ $# -gt 0 ]]; then
  if [[ ! -f "$1" ]]; then
    echo "SQL file not found: $1" >&2
    exit 1
  fi
  exec "$DUCKDB" :memory: -c "$SET_CSV" -c ".read sql/load.sql" -c ".read $1"
fi

echo "Tables: raw_actes (text, as in the file), actes (typed). Shortcut: FROM police('<reference>');  .quit to exit"
exec "$DUCKDB" :memory: -cmd "$SET_CSV" -cmd ".read sql/load.sql"
