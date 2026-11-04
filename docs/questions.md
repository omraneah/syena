# Entretien HappyPet — questions, réponses, décisions

15 minutes. Questions et ordre repris de la page Notion. Les **appuis** renvoient aux constats de
[preparation.md](preparation.md) (A1…A10) ; **débloque** = macros en attente de `sql/transform.sql`.

**Ouverture** : « Pouvez-vous me décrire une souscription multi-animaux, ses avenants et sa sortie, et ce que
représente chaque ligne du reporting ? »

## Questions au courtier

### Q1 · Grain et cycle de vie
Quelle est l'unité de la prime et des actes : police, contrat, animal ? Un avenant modifie-t-il l'existant ? Une
sortie concerne-t-elle tous les animaux ? Que signifient TERMINATION, RENUNCIATION et SUSPENDED ?
- Appuis : sorties sans animal (§2) ; RENUNCIATION = 100 % de la prime, effet au début de couverture (A4) ;
  avenants à prime faible ou nulle (A5) ; 13 SUSPENDED sans TERMINATION, 2 FINISHED sans sortie (A6).
- Débloque : `contract_grain` (requête `contract_state`).
- **Réponse** : _à renseigner_

### Q2 · Tarifs Health
La `Prime emise de l'acte` est-elle brute ou nette des taxes / commissions et de la remise multi-animaux de 15 % ?
Est-elle répétée sur les lignes des animaux ou ventilée ? Comment identifier le contrat le plus cher avant remise ?
- Appuis : prime identique sur chaque animal, une RENUNCIATION annule une seule ligne (A2) ; 4 créations à prime 0 (A8).
- Débloque : `health_premium`, `health_discount_factor`.
- **Réponse** : _à renseigner_

### Q3 · Prévention et frais
`Montant de la prevention` désigne-t-il un plafond de soins ou une part tarifaire ? Où est fournie la **prime
Prévention**, requise par Seyna ? Où obtenir taxes, commissions de gestion et d'acquisition ?
- Appuis : valeurs 0 / 30 / 100, Prévention ajoutée par avenant avec prime 0 (A5, A9) ; aucune colonne de frais (A10).
- Débloque : `prevention_premium`, `fee`.
- **Réponse** : _à renseigner_

### Q4 · Formats et dates
L'échelle des primes change apparemment d'un facteur 100 en octobre 2025 : changement d'unité ou anomalie ? Quels
fuseau horaire et conventions de dates d'effet utilisez-vous ?
- Appuis : bascule nette au 01/10/2025 sur la date de l'acte ; 2 renonciations d'octobre = exactement 100 × la
  création de septembre (A1). Débuts d'effet à 22:00 / 23:00 UTC selon l'heure d'été (A7).
- Débloque : `amount_in_euros`, `to_iso8601`.
- **Réponse** : _à renseigner_

### Q5 · Identifiants
Pourquoi le `Code client` est-il absent sur de nombreuses lignes ? Peut-on le retrouver par police ? Quel rôle
jouent l'identifiant comptable et le suffixe « -0 » ?
- Appuis : 111 polices sans aucun code ; 2 récupérables par email (A3) ; suffixe toujours `-0` (§1).
- Débloque : `customer_id_when_missing` ; `id` / `reference` dans `contract_state`.
- **Réponse** : _à renseigner_

### Q6 · Périmètre du reporting
Historique complet ou extraction périodique ? Comment transmettez-vous les corrections et comment identifier une
nouvelle version d'un acte ?
- Appuis : statut apparemment calculé fin novembre (A6) ; prime saisie par avenant après une création à 0 (A8).
- Débloque : `recorded_at` (date d'envoi).
- **Réponse** : _à renseigner_

## À demander à l'équipe Seyna (pas au courtier)

- Grain attendu du contrat cible (police, animal, renouvellement) et représentation des avenants et sorties.
- Provenance de `portfolio_id` et `recorded_at`.
- Règles de rejet ou de traitement des montants et identifiants manquants.
- Conventions : clés de `guarantees` (`Health`, `Prevention`), nommage des clés de `custom_properties`.

## Décisions

Après l'échange, une ligne par règle. **Source** : `HappyPet` / `Seyna` (confirmé) ou `Hypothèse de travail`
(choix assumé faute de réponse, à présenter comme tel). Une fois implémentée : remplacer le corps `error(...)` de la macro.

| Règle (`sql/transform.sql`) | Décision | Source | Implémentée |
|---|---|---|---|
| `contract_grain` / `contract_state` — grain, avenants, sorties, `id`, `reference` | | | |
| `amount_in_euros` — unité ×100 | | | |
| `to_iso8601` — fuseau | | | |
| `health_premium`, `prevention_premium` — parts Health / Prévention | | | |
| `health_discount_factor` — remise 15 % déjà incluse ? | | | |
| `fee` — taxes et commissions | | | |
| `customer_id_when_missing` — client introuvable | | | |
| `portfolio_id`, `recorded_at` — métadonnées Seyna | | | |

À l'issue, classer chaque point : **transformable** / **à corriger par HappyPet** / **règle encore inconnue**.
