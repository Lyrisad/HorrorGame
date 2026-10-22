# Historique du projet (demandes de l'utilisateur, décisions, état)

À lire pour comprendre d'où vient chaque choix. Ajoute une entrée à chaque séance de travail.

## L'idée de départ (octobre 2026)
Jeu d'horreur réaliste en vue caméra-piéton, appli PC Windows (.exe) — une première version navigateur
(Three.js) a été refusée (« je veux un jeu jouable en appli ») → Godot 4. Histoire : Théo roule de nuit vers la
fête de ses potes ; la maison est « surveillée » (caméras qui le suivent, télé qui le filme) ; le courant saute,
il est kidnappé, se réveille enfermé dans les égouts, traqué par une créature aveugle qui chasse au son ;
il s'échappe par la surface (forêt) à l'aube… où une caméra sur un poteau le filme encore : tout était en direct.

## Ce que l'utilisateur a demandé, dans l'ordre (résumé)
1. **Réalisme d'abord** : il a rejeté les objets procéduraux « bricolés », les bonshommes bâtons, les sons ridicules
   → vrais modèles (Poly Haven, Sketchfab, Rocketbox), vraies captures de mouvement, sons travaillés.
2. Liste de 19 retours : interface du téléphone, objets qui flottent, WC cubiques, kidnappeur mal orienté, flaques et
   tuyaux des égouts, monotonie, monstre jamais visible, pas de texte tutoriel sur la cécité de la créature.
3. Pare-brise ajusté + barre d'essuie-glace ; monstre plus effrayant (The Rake) ; laptop déplaçable ; barre de saisie
   du téléphone (clic → clavier) ; cadre du bureau ; son du robinet ; couper la musique ; porte qui claque plus vite.
4. Égouts : coins arrondis (murs puis cunette), poussière en suspension (petite et ronde), le monstre contourne les
   piliers, on peut le semer (essoufflement, murs qui étouffent le son, bouteilles à lancer), départ dans une cage
   (énigme), objectifs en plus (3 fusibles + armoire), géométrie propre (rampes, raccords, lumières, décals derrière
   les tuyaux) — « je veux un truc parfait ».
5. Télé (on ne voyait rien, déjà allumée, bug en s'approchant), à bout de souffle le monstre fonce, le E qui ferme
   un document ne doit pas le rouvrir, tout fouiller avant que le courant saute, grille fantôme, échelle fluide,
   marches du perron praticables, inventaire (I).
6. Coupe-boulons qui faisait planter le jeu + course-poursuite + point de contrôle (si on meurt : reprendre le
   coupe-boulons et refaire la poursuite) ; boîtes de pizza trop brillantes ; robinet en cascade ; cercle noir dans
   la cuisine ; téléphones trop blancs ; meilleur screamer du kidnappeur ; casque de Bertrand (« œuf doré ») puis vrais
   modèles pour le casque et la casquette ; battements de cœur pendant la poursuite ; **le vrai micro attire le
   monstre** (puis : micro qui ne marchait pas, vumètre affolé → choix du micro + barre de test) ; grognements qui
   sonnaient comme des motos → refaits ; vraies icônes dans le téléphone (haut-parleur, silence, clavier, décrocher /
   raccrocher) ; armoire à fusibles réaliste avec fusibles visibles.
7. Tapis de bain bleu et hublots des égouts déplaçables dans l'éditeur ; caméras de surveillance : support fixé au mur,
   seule la tête tourne ; caméra du poteau de la forêt (fin) bien accrochée ; lampe torche moins forte ;
   préparation d'un zip pour l'envoyer à un pote (LISEZ-MOI, crédits).
8. Immersion des égouts : mouches sur les corps, fuite de vapeur sur un tuyau (couvre les petits bruits), et à la
   place d'une voiture (refusée : « on est sous une forêt, pas sous une ville ») des **coups de vent de la forêt**
   par les grilles des puits (sifflement, feuilles mortes qui tombent et flottent, lune qui tremble, chouette).
9. 23/10/2026 : projet mis sur GitHub (Lyrisad/HorrorGame, dépôt public) pour travailler depuis un autre PC, avec
   cette mémoire dans le dépôt (CLAUDE.md + docs/claude/).

## État actuel
- Jeu complet et jouable de bout en bout (route → maison → égouts → forêt), environ 30-45 min.
- Dernier export : build/DernierEnregistrement.exe + DernierEnregistrement.zip (non versionnés ;
  `tools/dev/package.py` refait le zip après l'export).
- Les cartes de l'utilisateur (maison, égouts) sont dans `maps/` (identiques à celles de son %APPDATA% au 23/10/2026).

## Idées proposées, pas encore faites
- Buée et gouttes sur l'objectif de la caméra-piéton dans les égouts (coût moyen, plusieurs vérifications visuelles).
- Ronds dans l'eau et débris qui dérivent dans la cunette (le plus coûteux).
- Petite incohérence : le README appelle l'acte 3 « Sous la ville » alors que les égouts sont sous la forêt.

## À rappeler à l'utilisateur
- Révoquer le jeton API Sketchfab qu'il a collé dans une ancienne conversation (sketchfab.com → Settings → Password & API).
