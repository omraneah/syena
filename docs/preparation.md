# Préparation — la source HappyPet

Reprend la page Notion *Seyna × HappyPet — Préparation de l'intégration* (version du 04/11/2026). Chaque
chiffre a été revérifié sur le fichier ; la requête qui le prouve est citée (`E*` = `sql/exploration.sql`,
`C*` = `sql/quality_checks.sql`). Questions : [questions.md](questions.md). Cible : [mapping.md](mapping.md).

**Légende** — **Constat** : vérifié sur le fichier · **Hypothèse** : lecture plausible, non confirmée ·
**Exigence** : règle donnée par l'énoncé Seyna · **→ Qn** : à trancher en entretien.

## 1. Le fichier

| Mesure | Constat | Requête |
|---|---|---|
| Lignes / colonnes | 439 / 34 | E1 |
| Polices (`Reference de la police`) | 308, suffixe toujours `-0` | E1, E6 |
| `Identifiant comptable` | 308, en 1:1 avec la référence | E1, E6 |
| `Code client` | 265 lignes renseignées, 192 codes | E1 |
| Actes | CREATION 379 · AMENDMENT 21 (14 polices) · RENUNCIATION 23 · TERMINATION 16 | E2 |
| Polices multi-animaux | 55 : 42 × 2, 10 × 3, 3 × 4 animaux | E7 |
| Période des actes | 16/07/2025 – 18/11/2025 | E1 |
| Doublons | aucun (ni ligne identique, ni police × acte × animal répété) | C2 |

## 2. Grain et cardinalités

- **Constat** : CREATION et AMENDMENT = une ligne par animal ; TERMINATION et RENUNCIATION = une ligne par police,
  sans animal ni code client (E2, C1). **Hypothèse** : grain = police × acte × animal (non documenté). → Q1
- **Constat** : par police, un seul identifiant comptable, un seul statut, un seul email adhérent, au plus un
  code client ; code client ↔ email en 1:1 quand les deux existent (E6).
- **Constat** : 187 codes client ont 1 police, 5 en ont 2 ; 7 emails portent 2 polices (E8).
- **Constat** : 3 animaux apparaissent sur 2 polices : une police RENUNCIATION puis une nouvelle police le même
  jour ou le lendemain (E9).
- **Constat** : le statut est le même sur toutes les lignes d'une police (E6).

## 3. Valeurs manquantes et formats

- **Constat** : toujours renseignés — référence, identifiant comptable, statut, type d'acte, 3 dates, prime (C1).
- **Constat** : vides sur toutes les sorties — code client, colonnes animal et couverture, civilité, pays,
  nationalité, opt-in (C1).
- **Constat** : code client vide sur 129 / 379 CREATION et 6 / 21 AMENDMENT (C1) ; numéro d'identification de
  l'animal vide sur 144 CREATION + 9 AMENDMENT, formats hétérogènes : puce 15 chiffres (216), tatouages, texte (C13).
- **Constat** : `Date de creation de l'acte` en 3 formats — date seule (217), date-heure (168), heure sur un
  chiffre `8:21:34` (54) (C13). Dates de naissance en MM/JJ/AA, année sur 2 chiffres (corrigé au chargement :
  `68` → 1968).

| Colonne | Valeurs (E3, E4) |
|---|---|
| `Statut de couverture de la police` | RUNNING, SUSPENDED, FINISHED, FUTURE |
| `Type de l'acte` | CREATION, AMENDMENT, TERMINATION, RENUNCIATION |
| `Numero de l'animal` | 1 à 4 |
| `Type de l'animal` / `Sexe de l'animal` | Chien, Chat / Mâle, Femelle |
| `Formule de l'animal` | Sécurité, Budget, Confort |
| `Taux de couverture accidents` | 0,6 ; 0,7 ; 0,8 ; 0,9 ; 1 |
| `Taux de couverture maladies` | 0 (uniquement Budget) ; 0,6 ; 0,7 ; 0,8 (Sécurité) ; 0,8 ; 0,9 ; 1 (Confort) |
| `Plafond de garanties` | 1000 ; 1500 ; 2000 ; 3000 |
| `Montant de la prevention` | 0 ; 30 ; 100 |
| `Pet sitting` | Oui, Non |

## 4. Anomalies et points d'attention

| # | Constat (preuve) | Hypothèse / lecture possible | → |
|---|---|---|---|
| A1 | **Échelle ×100.** Jusqu'au 30/09/2025 primes à décimales (médiane 230–350) ; dès le 01/10/2025 entiers (médiane 21 312). La date de création de l'acte sépare les deux échelles, pas la date d'effet (C3, C4). 2 RENUNCIATION saisies en octobre sur des créations de septembre valent **exactement 100 ×** la prime de création ; 2 TERMINATION ≈ 89–91 × (C5). 6 polices ont des actes des deux côtés (`amount_scale_mixed_in_policy`). | Passage en centimes au 01/10/2025. | Q4 |
| A2 | **Prime répétée par animal.** Identique sur chaque ligne animal des 55 CREATION et 7 AMENDMENT multi-animaux (C6). Une RENUNCIATION annule la prime *d'une* ligne, pas la somme (C5). | Prime portée par la police, recopiée par animal. Risque de double comptage ; ventilation par animal inconnue. | Q2 |
| A3 | **Code client.** 174 lignes sans code : 18 récupérables sur un autre acte de la police (toutes des sorties) ; 111 polices (156 lignes) sans aucun code ; pour 2 d'entre elles l'email porte un code sur une autre police (C9, C9b). | Récupération par email possible mais non validée (non appliquée). Impacte `customer_id` et l'identification de l'adhérent pour la remise. | Q5 |
| A4 | **Sorties.** Primes négatives (C7). RENUNCIATION : 100 % de la prime de création, effet au jour du début de couverture (23/23). TERMINATION : 99–100 % de la prime, effet dans la période, au jour du début pour 7/16. Fin d'effet identique à la CREATION (C5, C11). | RENUNCIATION = annulation dès l'origine ; TERMINATION = résiliation avec remboursement (prorata ?). | Q1 |
| A5 | **Avenants.** Primes faibles ou nulles par rapport à la création (0 à 2,49 avant octobre ; −8 366 à 18 476 après) ; Prévention ajoutée 0→30 ou 0→100 sur 5 polices, dont 2 avec prime 0 ; certains avenants sans changement visible sur les colonnes animal (C8). | Prime d'avenant = delta ? La Prévention ajoutée sans prime interroge sa tarification. | Q1, Q3 |
| A6 | **Statut.** TERMINATION ⇒ SUSPENDED (16/16), RENUNCIATION ⇒ FINISHED (23/23), mais 13 SUSPENDED sans TERMINATION et 2 FINISHED sans sortie (couverture jusqu'en 09/2026). Débuts d'effet : RUNNING jusqu'au 18/11 23:00, FUTURE à partir du 29/11 23:00 (UTC, soit le 30/11 à Paris) (C12). | Statut calculé à la date d'extraction, entre le 19 et le 30/11/2025 ; sens de SUSPENDED à préciser. | Q1, Q6 |
| A7 | **Dates et fuseau.** Lus en UTC, tous les débuts d'effet de CREATION / RENUNCIATION tombent à minuit heure de Paris (22:00 en heure d'été, 23:00 après le 26/10), sauf lignes 230 (01:00) et 292 (06:00). TERMINATION et AMENDMENT portent une heure de traitement (C10, C10b). | Horodatages UTC. Fuseau des dates d'acte sans heure inconnu. | Q4 |
| A8 | **Primes nulles, effets rétroactifs.** 4 CREATION à prime 0 (lignes 56, 294, 357, 423) ; 56 et 294 débutent le 01/10 pour des actes créés les 13/10 et 09/10 (C7, C10b). Une police créée à 0 en septembre reçoit un avenant à 18 476 en novembre (lignes 356–357, C8). | Saisie différée de la prime ? | Q2, Q6 |
| A9 | **Prévention.** `Montant de la prevention` ∈ {0, 30, 100} (E3), ajoutable par avenant (C8) ; aucune colonne de prime Prévention. **Exigence** : HappyPet doit fournir la part Prévention de la prime. | Montant = plafond de remboursement annuel plutôt que prime. | Q3 |
| A10 | **Champs cible sans source** : `portfolio_id`, `recorded_at`, `tax`, `broker_fee`, `cost_acquisition`. | — | Q3, Seyna |

## 5. Colonnes

**Hors mapping cible à ce stade (13)** — données personnelles et nom de l'animal, absents du schéma Seyna
(leur utilité au-delà de l'exercice n'est pas établie) : civilité, prénom, nom, email, téléphone, date / ville /
département / pays de naissance, nationalité, adresse de l'adhérent, opt-in, nom de l'animal.

**Utilisées (21)** — nom SQL = nom de colonne dans DuckDB ; usage cible dans [mapping.md](mapping.md).

| Colonne source | Nom SQL | Constat |
|---|---|---|
| Code client | `code_client` | Absent sur les sorties et sur une partie des créations (A3). |
| Reference de la police | `reference_de_la_police` | Suffixe toujours `-0` ; clé de regroupement des actes. |
| Identifiant comptable | `identifiant_comptable` | UUID, 1:1 avec la référence. |
| Statut de couverture de la police | `statut_de_couverture_de_la_police` | Un par police (A6). |
| Type de l'acte | `type_de_lacte` | 4 valeurs, cohérentes. |
| Date de creation de l'acte | `date_de_creation_de_lacte` | 3 formats, sans fuseau (A7). |
| Date de debut d'effet de l'acte | `date_de_debut_deffet_de_lacte` | Minuit Paris en UTC sur CREATION / RENUNCIATION (A7). |
| Date de fin d'effet de l'acte | `date_de_fin_deffet_de_lacte` | Début + 1 an sur CREATION ; inchangée sur les sorties. |
| Prime emise de l'acte | `prime_emise_de_lacte` | Échelle ×100 (A1), répétée par animal (A2), négative sur les sorties (A4). |
| Numero de l'animal | `numero_de_lanimal` | 1 à 4. |
| Type / Race / Sexe de l'animal | `type_de_lanimal`, `race_de_lanimal`, `sexe_de_lanimal` | Race en libellés non normalisés. |
| Date de naissance de l'animal | `date_de_naissance_de_lanimal` | MM/JJ/AA. |
| Numero d'identification de l'animal | `numero_didentification_de_lanimal` | Souvent vide, formats hétérogènes (C13). |
| Formule de l'animal | `formule_de_lanimal` | Sécurité, Budget, Confort. |
| Taux de couverture accidents / maladies | `taux_de_couverture_accidents_de_lanimal`, `taux_de_couverture_maladies_de_lanimal` | Cohérents avec la formule (E4). |
| Plafond de garanties de l'animal | `plafond_de_garanties_de_lanimal` | 4 valeurs. |
| Montant de la prevention de l'animal | `montant_de_la_prevention_de_lanimal` | Sens non déterminé (A9). |
| Pet sitting de l'animal | `pet_sitting_de_lanimal` | Oui / Non. |
