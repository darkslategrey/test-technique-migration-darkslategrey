# Test technique — Développeur·se Intégrations & Migration de données

Merci de l'intérêt que vous portez au poste.

Ce test reproduit le quotidien du poste : un nouveau client arrive chez nous et
souhaite retrouver dans Baqio les données de son ancien logiciel. Nous
fournissons ce que nous recevons réellement dans ces situations, et le travail
consiste à les faire entrer proprement en base.

Un collègue a commencé la reprise avant de passer à autre chose.
**Le code existant fonctionne sur un extrait simplifié des fichiers, mais pas
sur les fichiers réels du client.** Il est incomplet et il contient des
erreurs. L'objectif est donc autant de le corriger et de le compléter que
d'écrire du nouveau code.

---

## Temps et rendu

- Une semaine pour nous rendre le sujet, à faire quand cela vous arrange.
- Rendu avec un historique de commits lisible.
- Nous enchaînons sur un entretien d'environ une heure pendant lequel nous
  parcourons votre code ensemble. Le débrief compte autant que le code.

---

## Ce que nous évaluons

La justesse des données en base, ce que vous faites des données douteuses, la
traçabilité et la lisibilité.

Le point le plus important : **une erreur silencieuse est pire qu'un rejet
explicite**. Un client qui découvre trois mois plus tard que 40 de ses tarifs
sont faux, c'est un incident. Un rapport qui dit « 12 lignes non importées,
voici lesquelles et pourquoi », c'est un échange de cinq minutes.

---

## Les fichiers du client

Le client quitte **CaveGest 4.2**, un logiciel installé en local qu'il utilise
depuis 2011. Son prestataire lui a sorti deux exports, dans `data/` : ses
clients, et son catalogue avec ses grilles tarifaires.

---

## Le travail attendu

Les données des deux exports doivent se retrouver en base, justes, et la
reprise doit pouvoir être relancée sans dégât.

Deux importeurs existent et sont faux : `Customer::Import::Cavegest` et
`ProductPrice::Import::Cavegest`. `Importer::Audit` est vide : il doit porter
les contrôles qui permettent d'affirmer au client que sa reprise est juste,
et nous les attendons calculés depuis la base.

`lib/migration_report.rb` collecte ce qui s'est passé pendant l'import. À la
fin d'une reprise, nous devons pouvoir dire combien d'enregistrements ont été
créés, ce qui a été rejeté et pourquoi, et ce qui est passé mais mérite une
vérification humaine. La forme est libre ; la personne qui lit ce rapport n'est
pas développeuse.

---

## Précisions

Le schéma, les modèles et l'architecture sont modifiables, y compris en
repartant de zéro si vous jugez le code existant irrécupérable. Dites-nous
simplement pourquoi.

Les gems aussi : `roo` est une suggestion, pas une contrainte.

Bon courage.

---

## Notes de reprise

### Décisions prises au fil de la reprise

- Type de tiers (R = REVENDEUR) : mappé sur `customer`, avec
  `customer_category = "REVENDEUR"` qui conserve l'information d'origine
  (982 lignes).

- Doublons de référence produits : 6 références apparaissent plusieurs fois
  dans l'export (CUV227, CUV228, HAU214, LES194, TER232, VIENM6), avec des
  noms ou volumes différents. La référence étant l'identifiant métier unique
  du produit, on ne peut pas trancher à la place du client. Plutôt que
  d'inventer une référence dérivée ou d'écraser silencieusement, ces produits
  sont **rejetés explicitement** et listés avec le détail de chaque ligne dans
  le rapport. Le client doit corriger sa référence avant la reprise.

- Prix EXPO exprimés TTC : convertis en HT en divisant par le coefficient de
  TVA du produit (20 % -> /1,2 ; 5,5 % -> /1,055), arrondis à 2 décimales.
  Les autres grilles sont lues en HT directement.

- Numéros de TVA : normalisés à l'import (espaces retirés, lettres en
  majuscules, ex. `FR 43 313181739` -> `FR43313181739`).

- Volumes : exprimés en centilitres dans le fichier, convertis en
  millilitres (x10). Les contenants non volumétriques (Carton, `6 x 75`,
  vide) renvoient `volume_ml = nil`.

- Lignes vides et lignes de structure (tarifs) : ignorées silencieusement,
  pour ne pas noyer le rapport de bruit.

- Clients sans identité : lignes avec une référence mais sans nom, prénom ou
  raison sociale (3 cas) : rejetées explicitement et listées dans le rapport,
  plutôt qu'un échec silencieux.

- Idempotence : l'import est rejouable sans dégât (upsert sur référence pour
  les clients, upsert produit + tarif pour les tarifs, index d'unicité).
  Un second `rake import:all` ne crée rien de plus.

- Données douteuses : stockées telles quelles en base et listées dans l'audit
  de cohérence (grilles inconnues, clients sans email) pour être traitées par un
  humain, plutôt qu'écrasées.

### Points à confirmer avec le client

- Grille inconnue `GDCPT` (5 clients, « GRANDS COMPTES ») : grille absente
  des tarifs. Faut-il la créer, ou la rattacher à une grille existante
  (`PART` / `DEPC`) ?

- Emails génériques `contact@baqio.fake` (497 clients) : adresses
  manifestement factices. Faut-il les passer à `nil` plutôt que de les
  conserver (risque d'envoi d'emails à des adresses inertes) ?

- Grilles tarifaires vides : `SALON` est vide pour la plupart des produits et
  `PART` pour quelques-uns. Normal si `SALON` ne sert qu'à l'événementiel,
  à confirmer.

- Clients inutilisables : le fichier marque 340 clients inutilisables.
  Faut-il les importer avec `active = false` ou les écarter ?

- Doublons clients exacts : quelques références apparaissent en double dans
  l'export sans différence. Traités comme des doublons d'export (le second
  import met à jour sans changement), à confirmer.

- Pays manquant : 992 clients sans code pays. Faut-il leur affecter un pays
  par défaut ou les laisser sans ?
