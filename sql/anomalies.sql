-- Anomaly report on the HappyPet file: one line per issue, with the source records involved.
-- Run: ./db.sh sql/anomalies.sql   ->  output/anomalies.csv, output/summary.md
-- Facts only: no business rule is applied, nothing is corrected. Evidence: sql/quality_checks.sql.

-- Acts before / after this date carry amounts ~100x apart (observed, C3-C5; unit not confirmed).
SET VARIABLE scale_change = TIMESTAMP '2025-10-01';

CREATE OR REPLACE TEMP TABLE policy AS
SELECT reference_de_la_police AS reference,
       count(DISTINCT code_client)                                AS codes,
       string_agg(DISTINCT code_client, ', ')                     AS code_list,
       any_value(statut_de_couverture_de_la_police)               AS status,
       bool_or(type_de_lacte = 'CREATION')                        AS has_creation,
       bool_or(type_de_lacte = 'TERMINATION')                     AS has_termination,
       bool_or(type_de_lacte = 'RENUNCIATION')                    AS has_renunciation,
       min(date_de_creation_de_lacte)                             AS first_act,
       max(date_de_creation_de_lacte)                             AS last_act,
       string_agg(source_line::VARCHAR, ' ' ORDER BY source_line) AS lines,
       string_agg(DISTINCT type_de_lacte, ' ')                    AS acts,
       string_agg(DISTINCT numero_de_lanimal::VARCHAR, ' ')       AS animals
FROM actes
GROUP BY 1;

CREATE OR REPLACE TABLE anomalies AS
-- Value present in the file but not converted (date, number)
SELECT 'unparseable_value' AS category, a.reference_de_la_police AS reference, a.source_line::VARCHAR AS source_lines,
       a.type_de_lacte AS act_type, a.numero_de_lanimal::VARCHAR AS animal,
       'Date de naissance de l''animal non convertie : ' || r.date_de_naissance_de_lanimal AS explanation
FROM actes a JOIN raw_actes r USING (source_line)
WHERE r.date_de_naissance_de_lanimal IS NOT NULL AND a.date_de_naissance_de_lanimal IS NULL

UNION ALL -- Same policy, act, animal and act date on several rows
SELECT 'duplicate_act', reference_de_la_police, string_agg(source_line::VARCHAR, ' ' ORDER BY source_line),
       type_de_lacte, numero_de_lanimal::VARCHAR, count(*) || ' lignes pour la même police, le même acte, le même animal et la même date d''acte.'
FROM actes GROUP BY reference_de_la_police, type_de_lacte, numero_de_lanimal, date_de_creation_de_lacte HAVING count(*) > 1

UNION ALL -- Client code
SELECT 'customer_id_inconsistent', reference, lines, acts, animals, 'Codes client ' || code_list || ' sur la même police.'
FROM policy WHERE codes > 1
UNION ALL
SELECT 'customer_id_missing_recoverable', a.reference_de_la_police, string_agg(a.source_line::VARCHAR, ' ' ORDER BY a.source_line),
       string_agg(DISTINCT a.type_de_lacte, ' '), string_agg(DISTINCT a.numero_de_lanimal::VARCHAR, ' '),
       'Code client absent sur ' || count(*) || ' ligne(s) ; ' || any_value(p.code_list) || ' figure sur un autre acte de la même police.'
FROM actes a JOIN policy p ON p.reference = a.reference_de_la_police
WHERE a.code_client IS NULL AND p.codes = 1 GROUP BY a.reference_de_la_police
UNION ALL
SELECT 'customer_id_missing_unrecoverable', reference, lines, acts, animals, 'Aucun acte de la police ne porte de code client.'
FROM policy WHERE codes = 0

UNION ALL -- Lifecycle
SELECT 'act_without_creation', reference, lines, acts, animals, 'Aucune CREATION pour cette police dans le fichier.'
FROM policy WHERE NOT has_creation
UNION ALL
SELECT 'status_without_exit_act', reference, lines, acts, animals,
       CASE status WHEN 'FINISHED' THEN 'Statut FINISHED sans TERMINATION ni RENUNCIATION.' ELSE 'Statut SUSPENDED sans TERMINATION.' END
FROM policy WHERE (status = 'FINISHED' AND NOT (has_termination OR has_renunciation)) OR (status = 'SUSPENDED' AND NOT has_termination)
UNION ALL
SELECT 'exit_outside_coverage', e.reference_de_la_police, e.source_line::VARCHAR, e.type_de_lacte, NULL,
       'Effet de la sortie hors de la période couverte par la CREATION.'
FROM actes e
JOIN (SELECT reference_de_la_police, min(date_de_debut_deffet_de_lacte) AS debut, min(date_de_fin_deffet_de_lacte) AS fin
      FROM actes WHERE type_de_lacte = 'CREATION' GROUP BY 1) c USING (reference_de_la_police)
WHERE e.type_de_lacte IN ('TERMINATION', 'RENUNCIATION')
  AND NOT (e.date_de_debut_deffet_de_lacte >= c.debut AND e.date_de_debut_deffet_de_lacte < c.fin)

UNION ALL -- Premiums
SELECT 'premium_repeated_per_animal', reference_de_la_police, string_agg(source_line::VARCHAR, ' ' ORDER BY source_line),
       type_de_lacte, string_agg(numero_de_lanimal::VARCHAR, ' ' ORDER BY numero_de_lanimal),
       'Prime ' || any_value(prime_emise_de_lacte) || ' répétée sur les ' || count(*) || ' lignes animal de l''acte : ne pas additionner sans règle de ventilation.'
FROM actes WHERE numero_de_lanimal IS NOT NULL
GROUP BY reference_de_la_police, type_de_lacte, date_de_creation_de_lacte
HAVING count(*) > 1 AND count(DISTINCT prime_emise_de_lacte) = 1
UNION ALL
SELECT 'premium_zero', reference_de_la_police, source_line::VARCHAR, type_de_lacte, numero_de_lanimal::VARCHAR, 'Prime nulle sur une CREATION.'
FROM actes WHERE type_de_lacte = 'CREATION' AND prime_emise_de_lacte = 0
UNION ALL
SELECT 'premium_sign', reference_de_la_police, source_line::VARCHAR, type_de_lacte, numero_de_lanimal::VARCHAR,
       'Prime ' || prime_emise_de_lacte || ' inattendue pour un acte ' || type_de_lacte || '.'
FROM actes WHERE (type_de_lacte = 'CREATION' AND prime_emise_de_lacte < 0)
              OR (type_de_lacte IN ('TERMINATION', 'RENUNCIATION') AND prime_emise_de_lacte > 0)
UNION ALL
SELECT 'amount_scale_x100', reference_de_la_police, source_line::VARCHAR, type_de_lacte, numero_de_lanimal::VARCHAR,
       'Acte du ' || strftime(date_de_creation_de_lacte, '%d/%m/%Y') || ', prime ' || prime_emise_de_lacte
       || ' : échelle ~x100 des actes antérieurs (unité à confirmer).'
FROM actes WHERE date_de_creation_de_lacte >= getvariable('scale_change')
UNION ALL
SELECT 'amount_scale_mixed_in_policy', reference, lines, acts, animals,
       'Actes créés avant et après le 01/10/2025 : montants de deux échelles sur la même police.'
FROM policy WHERE first_act < getvariable('scale_change') AND last_act >= getvariable('scale_change')

UNION ALL -- Dates (Paris midnight assumes UTC source timestamps, hypothesis Q4)
SELECT 'dates_inverted', reference_de_la_police, source_line::VARCHAR, type_de_lacte, numero_de_lanimal::VARCHAR,
       'Fin d''effet antérieure ou égale au début d''effet.'
FROM actes WHERE date_de_fin_deffet_de_lacte <= date_de_debut_deffet_de_lacte
UNION ALL
SELECT 'effect_not_paris_midnight', reference_de_la_police, source_line::VARCHAR, type_de_lacte, numero_de_lanimal::VARCHAR,
       'Début d''effet ' || date_de_debut_deffet_de_lacte || ' UTC = ' || strftime(utc_to_paris(date_de_debut_deffet_de_lacte), '%H:%M')
       || ' à Paris (hypothèse UTC).'
FROM actes WHERE type_de_lacte = 'CREATION' AND utc_to_paris(date_de_debut_deffet_de_lacte)::TIME <> TIME '00:00:00'
UNION ALL
SELECT 'effect_before_act', reference_de_la_police, source_line::VARCHAR, type_de_lacte, numero_de_lanimal::VARCHAR,
       'Effet au ' || strftime(utc_to_paris(date_de_debut_deffet_de_lacte), '%d/%m/%Y') || ', acte créé le '
       || strftime(date_de_creation_de_lacte, '%d/%m/%Y') || '.'
FROM actes WHERE type_de_lacte = 'CREATION' AND utc_to_paris(date_de_debut_deffet_de_lacte)::DATE < date_de_creation_de_lacte::DATE;

COPY (FROM anomalies ORDER BY category, reference, source_lines) TO 'output/anomalies.csv' (HEADER);

-- Summary: issues per category ------------------------------------------------------
CREATE OR REPLACE TEMP TABLE category_help (category VARCHAR, description VARCHAR);
INSERT INTO category_help VALUES
  ('unparseable_value',                 'Valeur source impossible à convertir.'),
  ('duplicate_act',                     'Même police, acte, animal et date d''acte sur plusieurs lignes.'),
  ('customer_id_inconsistent',          'Plusieurs codes client sur une même police.'),
  ('customer_id_missing_recoverable',   'Code client absent sur des lignes, présent sur un autre acte de la police.'),
  ('customer_id_missing_unrecoverable', 'Aucun acte de la police ne porte de code client.'),
  ('act_without_creation',              'Police sans acte CREATION dans le fichier.'),
  ('status_without_exit_act',           'Statut FINISHED / SUSPENDED sans acte de sortie correspondant.'),
  ('exit_outside_coverage',             'Date d''effet de sortie hors de la période de couverture.'),
  ('premium_repeated_per_animal',       'Prime identique sur chaque ligne animal d''un acte (risque de double comptage).'),
  ('premium_zero',                      'CREATION avec une prime nulle.'),
  ('premium_sign',                      'Signe de prime inattendu (CREATION négative ou sortie positive).'),
  ('amount_scale_x100',                 'Acte créé à partir du 01/10/2025 : montants ~x100 (unité à confirmer, non corrigé).'),
  ('amount_scale_mixed_in_policy',      'Actes d''une même police de part et d''autre du 01/10/2025.'),
  ('dates_inverted',                    'Fin d''effet antérieure ou égale au début d''effet.'),
  ('effect_not_paris_midnight',         'Début d''effet d''une CREATION différent de minuit à Paris (si source en UTC).'),
  ('effect_before_act',                 'Début d''effet d''une CREATION antérieur au jour de l''acte (rétroactivité ?).');

CREATE OR REPLACE TEMP TABLE summary AS
SELECT h.category AS categorie, count(a.category) AS signalements,
       coalesce(sum(len(string_split(a.source_lines, ' '))), 0) AS lignes_source, h.description
FROM category_help h LEFT JOIN anomalies a USING (category)
GROUP BY h.category, h.description
ORDER BY signalements DESC, categorie;

-- Written as raw lines so the file does not depend on the shell's display mode.
COPY (
  SELECT line FROM (
    SELECT 0 AS o, unnest([
      '# Anomalies de la source HappyPet', '',
      'Généré le ' || strftime(now(), '%Y-%m-%d %H:%M') || ' : ' || (SELECT count(*) FROM actes) || ' lignes source, '
        || (SELECT count(*) FROM anomalies) || ' signalements. Détail : `output/anomalies.csv`.', '',
      '| Catégorie | Signalements | Lignes source | Description |', '|---|---:|---:|---|']) AS line
    UNION ALL
    SELECT 1, '| `' || categorie || '` | ' || signalements || ' | ' || lignes_source || ' | ' || description || ' |'
    FROM summary
  ) ORDER BY o
) TO 'output/summary.md' (FORMAT csv, HEADER false, QUOTE '', ESCAPE '', DELIMITER '\t');

FROM summary;
