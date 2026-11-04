# Mapping HappyPet → contrat Seyna

Schéma cible fourni par Seyna. Les colonnes « source candidate » sont des points de départ, **pas des
transformations approuvées** : le statut dit ce qui manque. Décisions prises : [questions.md](questions.md#décisions).

**Exigences de l'énoncé**
- Health est la garantie principale ; Prevention est optionnelle.
- Un adhérent ayant plusieurs contrats a 15 % de remise sur Health sur tous ses contrats sauf le plus cher ;
  aucune remise sur Prevention. (Rang par client prêt dans `sql/transform.sql` ; facteur : `health_discount_factor`.)
- HappyPet doit fournir la part Prevention de la prime.

## Champs

Statut : **prêt** (implémenté) · **hypothèse** (implémenté, à valider) · **bloqué** (macro `error(...)` de `sql/transform.sql`).

| Champ | Format | Description Seyna | Source candidate | Statut | Code |
|---|---|---|---|---|---|
| `id` | String | Identifiant unique du contrat | `identifiant_comptable`, + `numero_de_lanimal` si un contrat = un animal | bloqué — Q1, Seyna | `contract_state` |
| `customer_id` | String | Identifiant client, suivi de la relation entre contrats | `code_client`, repris d'un autre acte de la même police | hypothèse (un seul code par police, E6) ; bloqué si aucun code — Q5 | CTE `policy_customer`, `customer_id_when_missing` |
| `portfolio_id` | String | Identifiant de produit Seyna | aucune | bloqué — Seyna | `portfolio_id()` |
| `reference` | String | Regroupe les contrats issus d'une même souscription initiale (renouvellements) | `reference_de_la_police` | bloqué — Q5, Seyna | `contract_state` |
| `recorded_at` | Timestamp ISO 8601 | Date d'envoi des données à Seyna | aucune ; ne pas substituer la date de l'acte | bloqué — Seyna, Q6 | `recorded_at()` |
| `subscribed_at` | Timestamp ISO 8601 | Date de souscription | `date_de_creation_de_lacte` de la CREATION (pas d'un avenant) | bloqué — Q1, Q4 | `contract_state`, `to_iso8601` |
| `starting_at` | Timestamp ISO 8601 (inclus) | Début de couverture | `date_de_debut_deffet_de_lacte` de la CREATION | bloqué — Q1, Q4 | `contract_state`, `to_iso8601` |
| `ending_at` | Timestamp ISO 8601 (exclu) | Fin de couverture | `date_de_fin_deffet_de_lacte` ; en cas de sortie, date d'effet de la sortie ? | bloqué — Q1, Q4 | `contract_state`, `to_iso8601` |
| `guarantees` | Map<String, ContractGuarantee> | Montants par garantie : `premium`, `tax`, `broker_fee`, `cost_acquisition` (Double) | `prime_emise_de_lacte` → `Health` / `Prevention` ; frais : aucune source | bloqué — Q2, Q3, Q4 | `amount_in_euros`, `health_premium`, `prevention_premium`, `health_discount_factor`, `fee` |
| `custom_properties` | String (JSON sérialisé) | Données produit : pricing, risque, gestion | colonnes animal et formule (ci-dessous) | hypothèse (clés proposées) ; structure à revoir si un contrat couvre plusieurs animaux — Q1 | `to_json` (étape 3) |

### `custom_properties` — clés proposées

`animal_number` ← `numero_de_lanimal` · `animal_type` ← `type_de_lanimal` · `breed` ← `race_de_lanimal` ·
`sex` ← `sexe_de_lanimal` · `birth_date` ← `date_de_naissance_de_lanimal` (ISO) · `identification_number` ←
`numero_didentification_de_lanimal` · `formula` ← `formule_de_lanimal` · `accident_coverage_rate` /
`illness_coverage_rate` ← taux accidents / maladies · `guarantee_ceiling` ← `plafond_de_garanties_de_lanimal` ·
`pet_sitting` ← `pet_sitting_de_lanimal` (Oui/Non → booléen).
`montant_de_la_prevention_de_lanimal` est exclu tant que Q3 n'a pas dit s'il s'agit d'un plafond ou d'une prime.

## Contrôles

Catégories de `output/anomalies.csv` (`sql/anomalies.sql`) et `output/contract_anomalies.csv` (`sql/transform.sql`) ; la requête citée montre la preuve agrégée.

| Catégorie | Vérifie | SQL |
|---|---|---|
| `unparseable_value` | dates de naissance convertibles | — |
| `duplicate_act` | police × acte × animal × date unique | C2 |
| `customer_id_inconsistent` / `_missing_recoverable` / `_missing_unrecoverable` | code client par police | E6, C9, C9b |
| `act_without_creation`, `status_without_exit_act`, `exit_outside_coverage` | cohérence du cycle de vie | C11, C12 |
| `premium_repeated_per_animal` | double comptage multi-animaux | C6 |
| `premium_zero`, `premium_sign` | primes nulles, signes par type d'acte | C7 |
| `amount_scale_x100`, `amount_scale_mixed_in_policy` | échelle des montants avant / après le 01/10/2025 | C3, C4, C5 |
| `dates_inverted`, `effect_not_paris_midnight`, `effect_before_act` | dates et fuseau | C10, C10b |
| `target_*` | schéma Seyna : champs obligatoires, `id` unique, ISO 8601 avec fuseau, début < fin, `guarantees` (clés `Health` / `Prevention`, 4 Double), prime négative, `custom_properties` JSON | — |

## Exemples à dérouler pendant la transformation

Pour chacun : transformation réalisée, contrôle effectué, anomalie, hypothèse restante. Les polices sont
listées par **E11** (`./db.sh sql/exploration.sql`), puis `FROM police('<référence>');` dans `./db.sh`.

| Cas | Ce qu'il montre |
|---|---|
| Création simple | 1 animal, 1 acte : le mapping de base |
| Multi-animaux | prime répétée par animal (A2), grain du contrat |
| Client à plusieurs polices | remise de 15 % sur Health, contrat le plus cher |
| Avenant | Prévention ajoutée, prime d'avenant = delta ? (A5) |
| Sortie sur deux échelles | TERMINATION / RENUNCIATION d'octobre sur une création de septembre (A1, A4) |

## Résultats (à compléter après exécution)

- Contrats générés : _n_ — règles appliquées : _voir Décisions_.
- Anomalies : tableau de `output/summary.md` ; erreurs à remonter à HappyPet : _…_
- Hypothèses restantes et interlocuteur : _…_

## Restitution (30 min)

1. Modèle source et règles confirmées — preparation.md §1–2, questions.md *Décisions*.
2. Logique de mapping et résultat — ce fichier, `sql/transform.sql`, `output/contracts.jsonl`.
3. Contrôles et erreurs détectées — `output/summary.md`, `output/anomalies.csv`, `output/contract_anomalies.csv`.
4. Points ouverts, avec l'interlocuteur responsable (HappyPet ou Seyna).
