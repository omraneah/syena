#!/usr/bin/env bash
# Load the CSV into a DuckDB table, then open the DuckDB shell on that database.
#
# Usage: ./load_csv.sh [csv_file]
#   csv_file defaults to donnees_case_data_integration_anonymise.csv
#
# Re-running the script rebuilds the table from the CSV (CREATE OR REPLACE).
set -euo pipefail

cd "$(dirname "$0")"

CSV="${1:-donnees_case_data_integration_anonymise.csv}"
DB="seyna.duckdb"
TABLE="actes"

DUCKDB="$(command -v duckdb || echo "$HOME/.local/bin/duckdb")"
if [[ ! -x "$DUCKDB" ]]; then
  echo "duckdb not found (expected on PATH or at ~/.local/bin/duckdb)" >&2
  exit 1
fi
if [[ ! -f "$CSV" ]]; then
  echo "CSV not found: $CSV" >&2
  exit 1
fi

CSV_SQL="${CSV//\'/\'\'}"   # escape single quotes for the SQL string literal

echo "Loading $CSV into $DB (table: $TABLE)..."

"$DUCKDB" "$DB" <<SQL
-- Dates in the file are MM/DD/YY. A plain %y parse maps 00-68 to 20xx, so a
-- birth date of 07/25/68 would become 2068. Anything after today is pushed back 100 years.
CREATE OR REPLACE TEMP MACRO parse_us_date(s) AS (
  CASE
    WHEN strptime(s, '%m/%d/%y')::DATE > current_date
      THEN (strptime(s, '%m/%d/%y') - INTERVAL 100 YEAR)::DATE
    ELSE strptime(s, '%m/%d/%y')::DATE
  END
);

CREATE OR REPLACE TABLE $TABLE AS
SELECT * REPLACE (
  parse_us_date(date_de_naissance_de_ladherent) AS date_de_naissance_de_ladherent,
  parse_us_date(date_de_naissance_de_lanimal)   AS date_de_naissance_de_lanimal,
  -- Département codes lost their leading zero in the export (1 -> 01).
  lpad(departement_de_naissance_de_ladherent, 2, '0') AS departement_de_naissance_de_ladherent
)
FROM read_csv(
  '$CSV_SQL',
  header = true,
  normalize_names = true,   -- "Type de l'acte" -> type_de_lacte
  types = {
    'date_de_naissance_de_ladherent': 'VARCHAR',
    'date_de_naissance_de_lanimal': 'VARCHAR',
    'departement_de_naissance_de_ladherent': 'VARCHAR'
  }
);

SELECT count(*) AS rows_loaded FROM $TABLE;
SQL

echo
echo "Opening DuckDB on $DB. Try:  DESCRIBE $TABLE;   SELECT * FROM $TABLE LIMIT 10;   .quit to exit"
exec "$DUCKDB" "$DB"
