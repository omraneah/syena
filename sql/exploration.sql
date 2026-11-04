-- Exploration of the HappyPet file: volumes, distinct values, cardinalities.
-- Run: ./db.sh sql/exploration.sql   (or paste single queries into ./db.sh)
-- Query labels (E1, E2...) are referenced from docs/preparation.md.

-- E1. Volumes and period covered
SELECT count(*)                                AS lignes,
       (SELECT count(*) - 1 FROM information_schema.columns WHERE table_name = 'raw_actes') AS colonnes_source,
       count(DISTINCT reference_de_la_police)  AS polices,
       count(DISTINCT identifiant_comptable)   AS identifiants_comptables,
       count(code_client)                      AS lignes_avec_code_client,
       count(DISTINCT code_client)             AS codes_client,
       count(DISTINCT email_de_ladherent)      AS emails_adherent,
       min(date_de_creation_de_lacte)          AS premier_acte,
       max(date_de_creation_de_lacte)          AS dernier_acte
FROM actes;

-- E2. Acts by type: rows, policies, rows carrying an animal / a client code
SELECT type_de_lacte,
       count(*)                               AS lignes,
       count(DISTINCT reference_de_la_police) AS polices,
       count(numero_de_lanimal)               AS lignes_avec_animal,
       count(code_client)                     AS lignes_avec_code_client
FROM actes
GROUP BY 1
ORDER BY 2 DESC;

-- E3. Distinct values of the categorical columns (raw text; empty cells shown as '(vide)')
SELECT colonne, valeur, count(*) AS lignes
FROM (
  UNPIVOT (
    SELECT coalesce(COLUMNS([
      'statut_de_couverture_de_la_police', 'type_de_lacte', 'numero_de_lanimal', 'type_de_lanimal',
      'sexe_de_lanimal', 'formule_de_lanimal', 'taux_de_couverture_accidents_de_lanimal',
      'taux_de_couverture_maladies_de_lanimal', 'plafond_de_garanties_de_lanimal',
      'montant_de_la_prevention_de_lanimal', 'pet_sitting_de_lanimal', 'civilite_de_ladherent', 'optin'
    ]), '(vide)')
    FROM raw_actes
  ) ON COLUMNS(*) INTO NAME colonne VALUE valeur
)
GROUP BY ALL
ORDER BY colonne, valeur;

-- E4. Disease coverage rate by formula (0 only appears with Budget?)
SELECT formule_de_lanimal, taux_de_couverture_maladies_de_lanimal, count(*) AS lignes
FROM actes
WHERE numero_de_lanimal IS NOT NULL
GROUP BY ALL
ORDER BY ALL;

-- E5. Coverage status x act type (status is per policy, repeated on each row)
SELECT statut_de_couverture_de_la_police AS statut, type_de_lacte,
       count(*) AS lignes, count(DISTINCT reference_de_la_police) AS polices
FROM actes
GROUP BY ALL
ORDER BY ALL;

-- E6. Key relationships: each count is the number of violations (0 = the relationship holds)
SELECT 'police -> plusieurs identifiants comptables' AS relation, count(*) AS violations
FROM (SELECT reference_de_la_police FROM actes GROUP BY 1 HAVING count(DISTINCT identifiant_comptable) > 1)
UNION ALL
SELECT 'identifiant comptable -> plusieurs polices', count(*)
FROM (SELECT identifiant_comptable FROM actes GROUP BY 1 HAVING count(DISTINCT reference_de_la_police) > 1)
UNION ALL
SELECT 'police -> plusieurs codes client', count(*)
FROM (SELECT reference_de_la_police FROM actes GROUP BY 1 HAVING count(DISTINCT code_client) > 1)
UNION ALL
SELECT 'police -> plusieurs statuts', count(*)
FROM (SELECT reference_de_la_police FROM actes GROUP BY 1 HAVING count(DISTINCT statut_de_couverture_de_la_police) > 1)
UNION ALL
SELECT 'police -> plusieurs emails adherent', count(*)
FROM (SELECT reference_de_la_police FROM actes GROUP BY 1 HAVING count(DISTINCT email_de_ladherent) > 1)
UNION ALL
SELECT 'code client -> plusieurs emails', count(*)
FROM (SELECT code_client FROM actes WHERE code_client IS NOT NULL GROUP BY 1 HAVING count(DISTINCT email_de_ladherent) > 1)
UNION ALL
SELECT 'email -> plusieurs codes client', count(*)
FROM (SELECT email_de_ladherent FROM actes WHERE code_client IS NOT NULL GROUP BY 1 HAVING count(DISTINCT code_client) > 1)
UNION ALL
SELECT 'reference sans suffixe -0', count(*)
FROM actes WHERE reference_de_la_police NOT LIKE '%-0';

-- E7. Animals per policy (multi-animal policies)
SELECT nb_animaux, count(*) AS polices
FROM (SELECT reference_de_la_police, count(DISTINCT numero_de_lanimal) AS nb_animaux FROM actes GROUP BY 1)
GROUP BY 1
ORDER BY 1;

-- E8. Policies per client code and per adherent email
SELECT 'code_client' AS cle, nb_polices, count(*) AS clients
FROM (SELECT code_client, count(DISTINCT reference_de_la_police) AS nb_polices FROM actes WHERE code_client IS NOT NULL GROUP BY 1)
GROUP BY ALL
UNION ALL
SELECT 'email_adherent', nb_polices, count(*)
FROM (SELECT email_de_ladherent, count(DISTINCT reference_de_la_police) AS nb_polices FROM actes GROUP BY 1)
GROUP BY ALL
ORDER BY 1, 2;

-- E9. Same animal on several policies (owner email + animal name + birth date), with the acts of each policy
SELECT a.email_de_ladherent, a.nom_de_lanimal, a.date_de_naissance_de_lanimal,
       a.reference_de_la_police, list(DISTINCT p.type_de_lacte ORDER BY p.type_de_lacte) AS actes_de_la_police,
       min(p.date_de_creation_de_lacte) AS premier_acte
FROM actes a
JOIN actes p USING (reference_de_la_police)
WHERE (a.email_de_ladherent, a.nom_de_lanimal, a.date_de_naissance_de_lanimal) IN (
  SELECT (email_de_ladherent, nom_de_lanimal, date_de_naissance_de_lanimal)
  FROM actes WHERE numero_de_lanimal IS NOT NULL
  GROUP BY ALL HAVING count(DISTINCT reference_de_la_police) > 1)
GROUP BY ALL
ORDER BY 1, premier_acte;

-- E10. Column profile: type, min, max, approx. distinct values, % empty
SUMMARIZE actes;

-- E11. Example policies for the cases to walk through during the transformation (docs/mapping.md)
WITH p AS (
  SELECT reference_de_la_police AS reference, any_value(code_client) AS code_client, count(*) AS lignes,
         count(DISTINCT numero_de_lanimal) AS animaux, list(DISTINCT type_de_lacte ORDER BY type_de_lacte) AS actes,
         min(date_de_creation_de_lacte) AS premier_acte, max(date_de_creation_de_lacte) AS dernier_acte
  FROM actes GROUP BY 1
), multi_policy_clients AS (
  SELECT code_client FROM actes WHERE code_client IS NOT NULL GROUP BY 1 HAVING count(DISTINCT reference_de_la_police) > 1
), cases AS (
  SELECT '1 création simple' AS cas, * FROM p WHERE lignes = 1 AND code_client IS NOT NULL
  UNION ALL SELECT '2 multi-animaux', * FROM p WHERE animaux >= 3 AND code_client IS NOT NULL
  UNION ALL SELECT '3 client à plusieurs polices', * FROM p WHERE code_client IN (FROM multi_policy_clients)
  UNION ALL SELECT '4 avenant', * FROM p WHERE list_contains(actes, 'AMENDMENT')
  UNION ALL SELECT '5 sortie sur deux échelles (x100)', * FROM p
    WHERE (list_contains(actes, 'TERMINATION') OR list_contains(actes, 'RENUNCIATION'))
      AND premier_acte < DATE '2025-10-01' AND dernier_acte >= DATE '2025-10-01'
)
SELECT cas, reference, code_client, animaux, actes, premier_acte
FROM cases
QUALIFY row_number() OVER (PARTITION BY cas ORDER BY premier_acte, reference) <= 2
ORDER BY cas, premier_acte;
