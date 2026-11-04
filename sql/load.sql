-- Loads the HappyPet CSV into an in-memory DuckDB database.
-- Run through ./db.sh, which sets the csv_path variable first.
--
-- raw_actes : every column as text, exactly as in the file (format checks)
-- actes     : typed columns (dates, numbers, booleans) for analysis
-- Both tables carry source_line = line number in the CSV (header = line 1),
-- the identifier used in output/anomalies.csv.
-- Column names are snake_case: "Type de l'acte" -> type_de_lacte.

CREATE OR REPLACE TABLE raw_actes AS
SELECT row_number() OVER () + 1 AS source_line, *
FROM read_csv(getvariable('csv_path'), header = true, all_varchar = true, normalize_names = true);

-- Birth dates are MM/DD/YY. A plain %y parse maps 00-68 to 20xx (07/25/68 -> 2068),
-- so any date after today is moved back 100 years. Unreadable values become NULL (see sql/anomalies.sql).
CREATE OR REPLACE MACRO parse_us_date(s) AS (
  CASE
    WHEN try_strptime(s, '%m/%d/%y')::DATE > current_date
      THEN (try_strptime(s, '%m/%d/%y') - INTERVAL 100 YEAR)::DATE
    ELSE try_strptime(s, '%m/%d/%y')::DATE
  END
);

CREATE OR REPLACE TABLE actes AS
SELECT * REPLACE (
  parse_us_date(date_de_naissance_de_ladherent) AS date_de_naissance_de_ladherent,
  parse_us_date(date_de_naissance_de_lanimal)   AS date_de_naissance_de_lanimal,
  -- Département codes lost their leading zero in the export (1 -> 01).
  lpad(departement_de_naissance_de_ladherent, 2, '0') AS departement_de_naissance_de_ladherent
)
FROM (
  SELECT row_number() OVER () + 1 AS source_line, *
  FROM read_csv(
    getvariable('csv_path'),
    header = true,
    normalize_names = true,
    types = {
      'date_de_naissance_de_ladherent': 'VARCHAR',
      'date_de_naissance_de_lanimal': 'VARCHAR',
      'departement_de_naissance_de_ladherent': 'VARCHAR',
      'numero_didentification_de_lanimal': 'VARCHAR'
    }
  )
);

-- Every act of one policy, in date order:  FROM police('<reference>');
CREATE OR REPLACE MACRO police(ref) AS TABLE
SELECT source_line, type_de_lacte AS acte, statut_de_couverture_de_la_police AS statut,
       date_de_creation_de_lacte AS cree_le, date_de_debut_deffet_de_lacte AS debut_effet,
       date_de_fin_deffet_de_lacte AS fin_effet, prime_emise_de_lacte AS prime, code_client,
       numero_de_lanimal AS animal, formule_de_lanimal AS formule,
       taux_de_couverture_accidents_de_lanimal AS taux_acc, taux_de_couverture_maladies_de_lanimal AS taux_mal,
       plafond_de_garanties_de_lanimal AS plafond, montant_de_la_prevention_de_lanimal AS prevention,
       pet_sitting_de_lanimal AS pet_sitting
FROM actes
WHERE reference_de_la_police = ref
ORDER BY date_de_creation_de_lacte, numero_de_lanimal;

-- Hypothesis to confirm with HappyPet (docs/questions.md Q4): source timestamps are UTC.
-- utc_to_paris(debut) = local Paris time; 22:00/23:00 UTC both become midnight.
CREATE OR REPLACE MACRO utc_to_paris(ts) AS timezone('Europe/Paris', timezone('UTC', ts));
