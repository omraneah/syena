# Seyna × HappyPet — intégration de données

Cas pratique *Data Integration Manager* : transformer le reporting du courtier HappyPet (assurance animaux) au
format contrat Seyna et relever les erreurs de données. Déroulé : préparation → entretien HappyPet (15 min) →
mise à jour de la documentation (15 min) → transformation (45 min) → restitution (30 min).

Seyna demande de limiter la préparation de la transformation : l'outillage et les contrôles sont prêts ;
**les règles métier non confirmées restent volontairement ouvertes**.

## Contenu

```text
db.sh                    lance DuckDB en mémoire sur le CSV : shell interactif ou exécution d'un fichier SQL
sql/load.sql             chargement : tables raw_actes (texte) et actes (typée), macros police(), utc_to_paris()
sql/exploration.sql      volumes, valeurs distinctes, cardinalités, polices d'exemple (E1–E11)
sql/quality_checks.sql   contrôles qualité de la source, preuves agrégées (C1–C13)
sql/anomalies.sql        rapport d'anomalies ligne à ligne -> output/anomalies.csv, output/summary.md
sql/transform.sql        transformation en contrats Seyna + contrôles du schéma cible
docs/preparation.md      la source : volumétrie, grain, valeurs, anomalies A1–A10 (constats / hypothèses)
docs/questions.md        entretien : questions Q1–Q6, réponses, journal des décisions
docs/mapping.md          champs Seyna et statut de chaque règle, contrôles, exemples, plan de restitution
output/                  fichiers générés (non versionnés)
```

Le CSV source `donnees_case_data_integration_anonymise.csv` se place à la racine ; il n'est pas versionné.

## Prérequis

DuckDB CLI 1.1 ou plus (testé en 2.0.0) : `brew install duckdb`, ou binaire depuis
https://github.com/duckdb/duckdb/releases. Rien d'autre.

## Utilisation

```bash
./db.sh                           # shell : FROM police('<référence>'); SUMMARIZE actes;
./db.sh sql/exploration.sql       # E1–E11
./db.sh sql/quality_checks.sql    # C1–C13
./db.sh sql/anomalies.sql         # -> output/anomalies.csv, output/summary.md
./db.sh sql/transform.sql         # -> output/contracts.jsonl, output/contract_anomalies.csv
```

La base est en mémoire, rechargée depuis le CSV à chaque lancement. Noms de colonnes en snake_case :
`Type de l'acte` → `type_de_lacte`. Autre fichier : `CSV=autre.csv ./db.sh …`.

| Sortie | Contenu |
|---|---|
| `output/anomalies.csv` | une ligne par problème de la source : catégorie, référence, lignes source, acte, animal, explication |
| `output/summary.md` | nombre de signalements par catégorie |
| `output/contracts.jsonl` | contrats Seyna, un JSON par ligne |
| `output/contract_anomalies.csv` | contrats non conformes au schéma Seyna : champ vide, `id` en double, horodatage, `guarantees`, JSON |

`transform.sql` liste d'abord les règles en attente, puis **s'arrête à la première** (code retour 1, aucun
fichier écrit) avec le message `Règle non confirmée — Qn : …`.

Inspecter les résultats dans `./db.sh` :

```sql
FROM read_csv('output/anomalies.csv') WHERE category = 'customer_id_missing_unrecoverable';
FROM read_json('output/contracts.jsonl') LIMIT 5;
```

## Implémenter une règle confirmée

1. Noter la réponse dans `docs/questions.md` (champ **Réponse** et tableau **Décisions**).
2. Dans `sql/transform.sql`, remplacer le corps `error('Règle non confirmée …')` de la macro par la règle
   (pour Q1 : réécrire la requête `contract_state`).
3. `./db.sh sql/transform.sql`, vérifier un exemple avec `FROM police('<référence>')` et lire
   `output/contract_anomalies.csv`.
4. Mettre à jour le statut dans `docs/mapping.md`.

Exemple de demande à Claude Code : *« HappyPet confirme que les montants sont en centimes à partir des actes du
01/10/2025 (Q4). Implémente `amount_in_euros` et relance la transformation. »*

## État

**Prêt** — chargement (3 formats de date, années sur 2 chiffres), 16 contrôles source, assemblage du contrat
(`guarantees` en Map, `custom_properties` en JSON, calcul du rang pour la remise), contrôles du schéma Seyna,
exports. Testé avec des règles factices.

**Volontairement ouvert** — 10 règles : grain et cycle de vie (Q1), unité ×100 et fuseau (Q4), parts Health /
Prévention (Q2, Q3), remise déjà incluse ou non (Q2), taxes et commissions (Q3), client introuvable (Q5),
`portfolio_id` et `recorded_at` (Seyna).

## Confidentialité

Le CSV et tout ce qui en dérive (`output/`, bases DuckDB) sont exclus de Git par `.gitignore`.
