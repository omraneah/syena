-- Data quality checks on the HappyPet file (source side, before any transformation).
-- Run: ./db.sh sql/quality_checks.sql   (or paste single queries into ./db.sh)
-- Check labels (C1, C2...) are referenced from docs/preparation.md and docs/mapping.md.
-- These queries show the evidence; src/transform.py lists the affected records in output/anomalies.csv.

-- C1. Empty cells per column and act type
WITH vides AS (
  SELECT colonne, type_de_lacte, count(*) FILTER (WHERE valeur = '(vide)') AS vides
  FROM (
    UNPIVOT (
      SELECT type_de_lacte, coalesce(COLUMNS(* EXCLUDE (source_line, type_de_lacte)), '(vide)')
      FROM raw_actes
    ) ON COLUMNS(* EXCLUDE type_de_lacte) INTO NAME colonne VALUE valeur
  )
  GROUP BY ALL
)
SELECT p.*
FROM (PIVOT vides ON type_de_lacte USING sum(vides)) p
JOIN information_schema.columns c ON c.table_name = 'raw_actes' AND c.column_name = p.colonne
ORDER BY c.ordinal_position;

-- C2. Duplicates (0 = none)
SELECT 'lignes strictement identiques' AS controle,
       (SELECT count(*) FROM raw_actes) - (SELECT count(*) FROM (SELECT DISTINCT * EXCLUDE source_line FROM raw_actes)) AS nb
UNION ALL
SELECT 'police x acte x animal x date de l''acte en double', count(*)
FROM (SELECT 1 FROM raw_actes GROUP BY reference_de_la_police, type_de_lacte, numero_de_lanimal, date_de_creation_de_lacte HAVING count(*) > 1)
UNION ALL
SELECT 'police x acte x animal en double (toutes dates)', count(*)
FROM (SELECT 1 FROM raw_actes GROUP BY reference_de_la_police, type_de_lacte, numero_de_lanimal HAVING count(*) > 1);

-- C3. Premium scale by month of act creation: decimal text until September, ~x100 integers from October
SELECT strftime(a.date_de_creation_de_lacte, '%Y-%m') AS mois_acte, a.type_de_lacte,
       count(*)                                                   AS lignes,
       count(*) FILTER (WHERE r.prime_emise_de_lacte LIKE '%.%')  AS avec_decimales,
       min(abs(a.prime_emise_de_lacte))                           AS min_abs,
       median(abs(a.prime_emise_de_lacte))                        AS mediane_abs,
       max(abs(a.prime_emise_de_lacte))                           AS max_abs
FROM actes a JOIN raw_actes r USING (source_line)
GROUP BY ALL
ORDER BY ALL;

-- C4. Where the scale changes: act creation date separates the two scales, effect date does not
SELECT max(a.date_de_creation_de_lacte)     FILTER (WHERE r.prime_emise_de_lacte LIKE '%.%')       AS dernier_acte_decimal,
       min(a.date_de_creation_de_lacte)     FILTER (WHERE abs(a.prime_emise_de_lacte) >= 1000)     AS premier_acte_x100,
       max(a.date_de_debut_deffet_de_lacte) FILTER (WHERE r.prime_emise_de_lacte LIKE '%.%')       AS dernier_effet_decimal,
       min(a.date_de_debut_deffet_de_lacte) FILTER (WHERE abs(a.prime_emise_de_lacte) >= 1000)     AS premier_effet_x100
FROM actes a JOIN raw_actes r USING (source_line);

-- C5. Exit acts vs the creation they reverse: |exit premium| / premium of one creation row.
-- Exits recorded from October on creations from before October show the x100 jump on a single policy.
WITH creation AS (
  SELECT reference_de_la_police, any_value(date_de_creation_de_lacte) AS cree_le,
         max(prime_emise_de_lacte) AS prime_ligne, sum(prime_emise_de_lacte) AS prime_somme_lignes
  FROM actes WHERE type_de_lacte = 'CREATION' GROUP BY 1
)
SELECT e.type_de_lacte,
       c.cree_le >= DATE '2025-10-01'                AS creation_apres_oct,
       e.date_de_creation_de_lacte >= DATE '2025-10-01' AS sortie_apres_oct,
       count(*)                                      AS sorties,
       count(*) FILTER (WHERE abs(e.prime_emise_de_lacte) = c.prime_ligne)        AS egal_prime_ligne,
       count(*) FILTER (WHERE abs(e.prime_emise_de_lacte) = c.prime_somme_lignes) AS egal_somme_lignes,
       list(round(abs(e.prime_emise_de_lacte) / c.prime_ligne, 3) ORDER BY e.source_line) AS ratios
FROM actes e JOIN creation c USING (reference_de_la_police)
WHERE e.type_de_lacte IN ('TERMINATION', 'RENUNCIATION')
GROUP BY ALL
ORDER BY ALL;

-- C6. Multi-animal acts: is the premium identical on every animal row? (double-count risk if summed)
SELECT type_de_lacte,
       count(*)                                          AS actes_multi_animaux,
       count(*) FILTER (WHERE primes_distinctes = 1)     AS prime_identique_sur_chaque_animal,
       count(*) FILTER (WHERE primes_distinctes > 1)     AS primes_differentes
FROM (
  SELECT reference_de_la_police, type_de_lacte, date_de_creation_de_lacte,
         count(DISTINCT prime_emise_de_lacte) AS primes_distinctes
  FROM actes WHERE numero_de_lanimal IS NOT NULL
  GROUP BY ALL HAVING count(*) > 1
)
GROUP BY 1;

-- C7. Premium sign and zero premiums by act type
SELECT type_de_lacte,
       count(*) FILTER (WHERE prime_emise_de_lacte > 0) AS positives,
       count(*) FILTER (WHERE prime_emise_de_lacte = 0) AS nulles,
       count(*) FILTER (WHERE prime_emise_de_lacte < 0) AS negatives
FROM actes
GROUP BY 1
ORDER BY 1;

-- C8. Amendments: premium of the amendment vs creation, and which animal/coverage fields changed
SELECT a.source_line, a.reference_de_la_police, a.numero_de_lanimal AS animal,
       c.prime_emise_de_lacte AS prime_creation, a.prime_emise_de_lacte AS prime_avenant,
       concat_ws(', ',
         CASE WHEN a.formule_de_lanimal IS DISTINCT FROM c.formule_de_lanimal THEN 'formule ' || c.formule_de_lanimal || '->' || a.formule_de_lanimal END,
         CASE WHEN a.montant_de_la_prevention_de_lanimal IS DISTINCT FROM c.montant_de_la_prevention_de_lanimal
              THEN 'prevention ' || c.montant_de_la_prevention_de_lanimal || '->' || a.montant_de_la_prevention_de_lanimal END,
         CASE WHEN a.pet_sitting_de_lanimal IS DISTINCT FROM c.pet_sitting_de_lanimal THEN 'pet_sitting' END,
         CASE WHEN a.taux_de_couverture_accidents_de_lanimal IS DISTINCT FROM c.taux_de_couverture_accidents_de_lanimal THEN 'taux_accidents' END,
         CASE WHEN a.taux_de_couverture_maladies_de_lanimal IS DISTINCT FROM c.taux_de_couverture_maladies_de_lanimal THEN 'taux_maladies' END,
         CASE WHEN a.plafond_de_garanties_de_lanimal IS DISTINCT FROM c.plafond_de_garanties_de_lanimal THEN 'plafond' END,
         CASE WHEN a.numero_didentification_de_lanimal IS DISTINCT FROM c.numero_didentification_de_lanimal THEN 'identification' END,
         CASE WHEN a.race_de_lanimal IS DISTINCT FROM c.race_de_lanimal THEN 'race' END,
         CASE WHEN a.nom_de_lanimal IS DISTINCT FROM c.nom_de_lanimal THEN 'nom' END,
         CASE WHEN a.date_de_naissance_de_lanimal IS DISTINCT FROM c.date_de_naissance_de_lanimal THEN 'naissance' END
       ) AS champs_modifies
FROM actes a
LEFT JOIN actes c ON c.reference_de_la_police = a.reference_de_la_police
                 AND c.numero_de_lanimal = a.numero_de_lanimal AND c.type_de_lacte = 'CREATION'
WHERE a.type_de_lacte = 'AMENDMENT'
ORDER BY a.reference_de_la_police, animal;

-- C9. Client code: missing rows, recoverable from another act of the same policy, policies without any code
WITH police AS (
  SELECT reference_de_la_police, count(code_client) AS lignes_avec_code, any_value(email_de_ladherent) AS email
  FROM actes GROUP BY 1
)
SELECT a.type_de_lacte,
       count(*)                                         AS lignes_sans_code,
       count(*) FILTER (WHERE p.lignes_avec_code > 0)   AS recuperables_meme_police,
       count(*) FILTER (WHERE p.lignes_avec_code = 0)   AS non_recuperables_meme_police
FROM actes a JOIN police p USING (reference_de_la_police)
WHERE a.code_client IS NULL
GROUP BY 1
ORDER BY 1;

-- C9b. Policies with no client code on any act; candidates via the adherent email (hypothesis, not applied)
WITH police AS (
  SELECT reference_de_la_police, count(code_client) AS lignes_avec_code, any_value(email_de_ladherent) AS email
  FROM actes GROUP BY 1
)
SELECT count(*) AS polices_sans_aucun_code,
       count(*) FILTER (WHERE email IN (SELECT email_de_ladherent FROM actes WHERE code_client IS NOT NULL))
         AS dont_email_avec_code_sur_autre_police
FROM police
WHERE lignes_avec_code = 0;

-- C10. Dates by act type. Effect start is compared to Paris midnight assuming UTC timestamps (hypothesis Q4).
SELECT type_de_lacte,
       count(*) AS lignes,
       count(*) FILTER (WHERE date_de_fin_deffet_de_lacte <= date_de_debut_deffet_de_lacte)                         AS fin_avant_debut,
       count(*) FILTER (WHERE date_de_fin_deffet_de_lacte <> date_de_debut_deffet_de_lacte + INTERVAL 1 YEAR)       AS duree_pas_1_an,
       count(*) FILTER (WHERE utc_to_paris(date_de_debut_deffet_de_lacte)::DATE < date_de_creation_de_lacte::DATE)  AS effet_avant_jour_acte,
       count(*) FILTER (WHERE utc_to_paris(date_de_debut_deffet_de_lacte)::TIME <> TIME '00:00:00')                 AS effet_pas_minuit_paris
FROM actes
GROUP BY 1
ORDER BY 1;

-- C10b. Creations whose effect is not Paris midnight, or starts before the act day.
-- (Renunciations are left out: they always take effect on the coverage start, see C11.)
SELECT source_line, reference_de_la_police, date_de_creation_de_lacte,
       date_de_debut_deffet_de_lacte, utc_to_paris(date_de_debut_deffet_de_lacte) AS debut_heure_paris, prime_emise_de_lacte
FROM actes
WHERE type_de_lacte = 'CREATION'
  AND (utc_to_paris(date_de_debut_deffet_de_lacte)::TIME <> TIME '00:00:00'
       OR utc_to_paris(date_de_debut_deffet_de_lacte)::DATE < date_de_creation_de_lacte::DATE)
ORDER BY source_line;

-- C11. Exit acts vs the coverage of the creation: effect date inside the period, end date unchanged
SELECT e.type_de_lacte,
       count(*) AS sorties,
       count(*) FILTER (WHERE e.date_de_fin_deffet_de_lacte = c.date_de_fin_deffet_de_lacte)                AS fin_identique_creation,
       count(*) FILTER (WHERE e.date_de_debut_deffet_de_lacte::DATE = c.date_de_debut_deffet_de_lacte::DATE) AS effet_au_jour_du_debut,
       count(*) FILTER (WHERE e.date_de_debut_deffet_de_lacte < c.date_de_debut_deffet_de_lacte
                           OR e.date_de_debut_deffet_de_lacte >= c.date_de_fin_deffet_de_lacte)            AS effet_hors_periode
FROM actes e
JOIN (SELECT DISTINCT reference_de_la_police, date_de_debut_deffet_de_lacte, date_de_fin_deffet_de_lacte
      FROM actes WHERE type_de_lacte = 'CREATION') c USING (reference_de_la_police)
WHERE e.type_de_lacte IN ('TERMINATION', 'RENUNCIATION')
GROUP BY 1;

-- C12. Coverage status vs lifecycle: exit acts per status, and coverage dates per status
WITH police AS (
  SELECT reference_de_la_police,
         any_value(statut_de_couverture_de_la_police) AS statut,
         bool_or(type_de_lacte = 'TERMINATION')  AS a_termination,
         bool_or(type_de_lacte = 'RENUNCIATION') AS a_renunciation,
         min(date_de_debut_deffet_de_lacte) FILTER (WHERE type_de_lacte = 'CREATION') AS debut,
         min(date_de_fin_deffet_de_lacte)   FILTER (WHERE type_de_lacte = 'CREATION') AS fin
  FROM actes GROUP BY 1
)
SELECT statut, a_termination, a_renunciation, count(*) AS polices,
       min(debut) AS debut_min, max(debut) AS debut_max, min(fin) AS fin_min, max(fin) AS fin_max
FROM police
GROUP BY ALL
ORDER BY ALL;

-- C13. Value formats (digits -> 9, letters -> A): act creation date, premium, animal identification
SELECT 'date_de_creation_de_lacte' AS colonne, regexp_replace(date_de_creation_de_lacte, '[0-9]', '9', 'g') AS format, count(*) AS lignes
FROM raw_actes GROUP BY ALL
UNION ALL
SELECT 'prime_emise_de_lacte', CASE WHEN prime_emise_de_lacte LIKE '%.%' THEN 'avec decimales' ELSE 'entier' END, count(*)
FROM raw_actes GROUP BY ALL
UNION ALL
SELECT 'numero_didentification_de_lanimal',
       coalesce(regexp_replace(regexp_replace(numero_didentification_de_lanimal, '[0-9]', '9', 'g'), '[A-Za-z]', 'A', 'g'), '(vide)'), count(*)
FROM raw_actes WHERE numero_de_lanimal IS NOT NULL GROUP BY ALL
ORDER BY 1, 3 DESC;
