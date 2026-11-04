-- HappyPet -> Seyna contracts.  Run: ./db.sh sql/transform.sql
-- -> output/contracts.jsonl (one Seyna contract per line) and output/contract_anomalies.csv (schema checks).
--
-- Every rule not confirmed yet is a macro raising error('Règle non confirmée — ...'): the script
-- lists them, then stops at the first one used and writes nothing. To implement a confirmed rule:
-- record the answer in docs/questions.md, replace the macro body, rerun.
.bail on

-- 1. Rules to confirm (docs/questions.md) ------------------------------------------------------

-- Q1 grain and lifecycle: used as the WHERE of contract_state (step 2) until that query is rewritten.
CREATE OR REPLACE MACRO contract_grain() AS
  error('Règle non confirmée — Q1 : un contrat Seyna = une police, un animal, une période ? Effet des avenants et sorties ?');

-- Q4 unit: source amount -> euros (amounts ~x100 for acts created from 01/10/2025).
CREATE OR REPLACE MACRO amount_in_euros(amount, act_created_at) AS
  error('Règle non confirmée — Q4 : unité des montants avant / après le 01/10/2025 ?');

-- Q4 time zone: source timestamp -> ISO 8601 string with an explicit offset.
CREATE OR REPLACE MACRO to_iso8601(ts) AS
  error('Règle non confirmée — Q4 : fuseau des horodatages source (UTC ?) et des dates sans heure ?');

-- Q2/Q3 premium split: Health and Prevention parts (Prevention part to be supplied by HappyPet).
CREATE OR REPLACE MACRO health_premium(premium_eur, prevention_amount) AS
  error('Règle non confirmée — Q2/Q3 : part Health de la prime ?');
CREATE OR REPLACE MACRO prevention_premium(premium_eur, prevention_amount) AS
  error('Règle non confirmée — Q3 : part Prevention de la prime (NULL si non souscrite) ?');

-- Q2 multi-contract discount. Case study: 15 % off Health on every contract of a policyholder except
-- the most expensive (rank 1). If the source premium already includes it, the factor is 1.
-- Ready formula: CASE WHEN rank_in_customer = 1 THEN 1 ELSE 0.85 END. rank is NULL without customer_id (Q5).
CREATE OR REPLACE MACRO health_discount_factor(rank_in_customer) AS
  error('Règle non confirmée — Q2 : la prime source inclut-elle déjà la remise de 15 % sur Health ?');

-- Q3 fees and taxes, per guarantee: fee_name in ('tax', 'broker_fee', 'cost_acquisition').
CREATE OR REPLACE MACRO fee(fee_name, guarantee_name, premium) AS
  error('Règle non confirmée — Q3 : source des taxes et commissions ?');

-- Q5 client: contracts whose policy carries no client code on any act.
CREATE OR REPLACE MACRO customer_id_when_missing(reference) AS
  error('Règle non confirmée — Q5 : traitement d''un contrat sans code client récupérable ?');

-- Seyna metadata.
CREATE OR REPLACE MACRO portfolio_id() AS error('Règle non confirmée — Seyna : valeur de portfolio_id ?');
CREATE OR REPLACE MACRO recorded_at() AS error('Règle non confirmée — Seyna : recorded_at (date d''envoi à Seyna) ?');

SELECT function_name AS regle_en_attente,
       replace(regexp_extract(macro_definition, 'confirmée — (.*)''\)', 1), '''''', '''') AS question
FROM duckdb_functions()
WHERE function_type = 'macro' AND macro_definition LIKE '%Règle non confirmée%'
ORDER BY 1;

-- 2. One row per Seyna contract (Q1). Rewrite this query once the grain and lifecycle are confirmed:
--    which acts form a contract, and how AMENDMENT / TERMINATION / RENUNCIATION change dates and premium.
--    The columns are the ones step 3 expects. Several animals in one contract: custom_properties structure to confirm.
CREATE OR REPLACE TABLE contract_state AS
SELECT
  identifiant_comptable          AS contract_id,             -- Seyna id; + numero_de_lanimal if one contract = one animal ?
  reference_de_la_police         AS reference,               -- groups subscription and renewals (Q5, Seyna)
  reference_de_la_police,
  date_de_creation_de_lacte      AS subscribed_at,           -- from the CREATION, not from an amendment
  date_de_debut_deffet_de_lacte  AS starting_at,
  date_de_fin_deffet_de_lacte    AS ending_at,               -- after an exit: the exit effect date ?
  prime_emise_de_lacte           AS premium_source,          -- repeated on each animal row (A2); amendment = delta ? (A5)
  date_de_creation_de_lacte      AS premium_act_created_at,
  numero_de_lanimal, type_de_lanimal, race_de_lanimal, sexe_de_lanimal, date_de_naissance_de_lanimal,
  numero_didentification_de_lanimal, formule_de_lanimal, taux_de_couverture_accidents_de_lanimal,
  taux_de_couverture_maladies_de_lanimal, plafond_de_garanties_de_lanimal, montant_de_la_prevention_de_lanimal,
  pet_sitting_de_lanimal
FROM actes
WHERE contract_grain();

-- 3. Seyna contracts (ready: assembly only, every business choice is a macro above) -------------
CREATE OR REPLACE MACRO guarantee(guarantee_name, premium) AS {
  'broker_fee':       fee('broker_fee', guarantee_name, premium)::DOUBLE,
  'cost_acquisition': fee('cost_acquisition', guarantee_name, premium)::DOUBLE,
  'premium':          premium::DOUBLE,
  'tax':              fee('tax', guarantee_name, premium)::DOUBLE
};

CREATE OR REPLACE TABLE contracts AS
WITH policy_customer AS (   -- the single client code carried by the acts of a policy (E6)
  SELECT reference_de_la_police, any_value(code_client) AS code_client
  FROM actes WHERE code_client IS NOT NULL
  GROUP BY 1 HAVING count(DISTINCT code_client) = 1
), priced AS (
  SELECT s.*,
         coalesce(p.code_client, customer_id_when_missing(s.reference_de_la_police)) AS customer_id,
         amount_in_euros(s.premium_source, s.premium_act_created_at) AS premium_eur
  FROM contract_state s LEFT JOIN policy_customer p USING (reference_de_la_police)
), split AS (
  SELECT *, health_premium(premium_eur, montant_de_la_prevention_de_lanimal)     AS health_before_discount,
            prevention_premium(premium_eur, montant_de_la_prevention_de_lanimal) AS prevention
  FROM priced
), discounted AS (
  SELECT *, health_before_discount * health_discount_factor(
              CASE WHEN customer_id IS NOT NULL THEN
                row_number() OVER (PARTITION BY customer_id ORDER BY health_before_discount DESC, contract_id) END) AS health
  FROM split
)
SELECT
  contract_id                  AS id,
  customer_id,
  portfolio_id()               AS portfolio_id,
  reference,
  recorded_at()                AS recorded_at,
  to_iso8601(subscribed_at)    AS subscribed_at,
  to_iso8601(starting_at)      AS starting_at,
  to_iso8601(ending_at)        AS ending_at,
  CASE WHEN prevention IS NULL
       THEN MAP {'Health': guarantee('Health', health)}
       ELSE MAP {'Health': guarantee('Health', health), 'Prevention': guarantee('Prevention', prevention)}
  END                          AS guarantees,
  -- Key names are a proposal (docs/mapping.md); the prevention amount is left out until Q3.
  to_json({
    'animal_number': numero_de_lanimal, 'animal_type': type_de_lanimal, 'breed': race_de_lanimal,
    'sex': sexe_de_lanimal, 'birth_date': date_de_naissance_de_lanimal::VARCHAR,
    'identification_number': numero_didentification_de_lanimal, 'formula': formule_de_lanimal,
    'accident_coverage_rate': taux_de_couverture_accidents_de_lanimal,
    'illness_coverage_rate': taux_de_couverture_maladies_de_lanimal,
    'guarantee_ceiling': plafond_de_garanties_de_lanimal,
    'pet_sitting': CASE pet_sitting_de_lanimal WHEN 'Oui' THEN true WHEN 'Non' THEN false END
  })::VARCHAR                  AS custom_properties
FROM discounted;

COPY contracts TO 'output/contracts.jsonl' (FORMAT json);

-- 4. Seyna schema checks ------------------------------------------------------------------------
CREATE OR REPLACE MACRO iso_with_offset(s) AS
  regexp_matches(s, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$');

CREATE OR REPLACE TABLE contract_anomalies AS
SELECT 'target_missing_field' AS category, id, reference,
       'Champ(s) vide(s) : ' || concat_ws(', ',
         CASE WHEN coalesce(id, '') = '' THEN 'id' END, CASE WHEN coalesce(customer_id, '') = '' THEN 'customer_id' END,
         CASE WHEN coalesce(portfolio_id, '') = '' THEN 'portfolio_id' END, CASE WHEN coalesce(reference, '') = '' THEN 'reference' END,
         CASE WHEN recorded_at IS NULL THEN 'recorded_at' END, CASE WHEN subscribed_at IS NULL THEN 'subscribed_at' END,
         CASE WHEN starting_at IS NULL THEN 'starting_at' END, CASE WHEN ending_at IS NULL THEN 'ending_at' END,
         CASE WHEN guarantees IS NULL THEN 'guarantees' END, CASE WHEN custom_properties IS NULL THEN 'custom_properties' END
       ) AS explanation
FROM contracts
WHERE coalesce(id, '') = '' OR coalesce(customer_id, '') = '' OR coalesce(portfolio_id, '') = '' OR coalesce(reference, '') = ''
   OR recorded_at IS NULL OR subscribed_at IS NULL OR starting_at IS NULL OR ending_at IS NULL
   OR guarantees IS NULL OR custom_properties IS NULL
UNION ALL
SELECT 'target_duplicate_id', id, reference, 'id présent ' || count(*) OVER (PARTITION BY id) || ' fois.'
FROM contracts QUALIFY count(*) OVER (PARTITION BY id) > 1
UNION ALL
SELECT 'target_bad_timestamp', id, reference, 'Horodatage non ISO 8601 avec fuseau : ' || concat_ws(', ',
         CASE WHEN NOT iso_with_offset(recorded_at) THEN 'recorded_at' END, CASE WHEN NOT iso_with_offset(subscribed_at) THEN 'subscribed_at' END,
         CASE WHEN NOT iso_with_offset(starting_at) THEN 'starting_at' END, CASE WHEN NOT iso_with_offset(ending_at) THEN 'ending_at' END)
FROM contracts
WHERE NOT iso_with_offset(recorded_at) OR NOT iso_with_offset(subscribed_at) OR NOT iso_with_offset(starting_at) OR NOT iso_with_offset(ending_at)
UNION ALL
SELECT 'target_dates', id, reference, 'starting_at n''est pas antérieur à ending_at.'
FROM contracts WHERE try_cast(starting_at AS TIMESTAMPTZ) >= try_cast(ending_at AS TIMESTAMPTZ)
UNION ALL
SELECT 'target_bad_guarantee', id, reference, 'guarantees : clé Health absente ou clé inconnue (' || array_to_string(map_keys(guarantees), ', ') || ').'
FROM contracts
WHERE NOT list_contains(map_keys(guarantees), 'Health') OR len(list_filter(map_keys(guarantees), lambda k: k NOT IN ('Health', 'Prevention'))) > 0
UNION ALL
SELECT 'target_bad_guarantee', id, reference, 'Montant manquant (premium, tax, broker_fee ou cost_acquisition).'
FROM contracts
WHERE len(list_filter(map_values(guarantees), lambda g: g.premium IS NULL OR g.tax IS NULL OR g.broker_fee IS NULL OR g.cost_acquisition IS NULL)) > 0
UNION ALL
SELECT 'target_negative_premium', id, reference, 'Prime négative sur une garantie.'
FROM contracts WHERE len(list_filter(map_values(guarantees), lambda g: g.premium < 0)) > 0
UNION ALL
SELECT 'target_bad_custom_properties', id, reference, 'custom_properties n''est pas un objet JSON.'
FROM contracts  -- CASE, not AND: json_type() fails on invalid JSON and AND does not short-circuit
WHERE CASE WHEN coalesce(json_valid(custom_properties), false) THEN json_type(custom_properties) <> 'OBJECT' ELSE true END;

COPY (FROM contract_anomalies ORDER BY category, id) TO 'output/contract_anomalies.csv' (HEADER);

SELECT (SELECT count(*) FROM contracts) AS contrats, (SELECT count(*) FROM contract_anomalies) AS anomalies_cible;
SELECT category, count(*) AS contrats FROM contract_anomalies GROUP BY 1 ORDER BY 2 DESC;
