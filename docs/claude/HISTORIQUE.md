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
10. 23/10/2026 (2e séance) : grosse liste de retours, tout fait : moins d'aberration chromatique et de grain
   (« effet neige »), flare sur les lampes, faisceau de la lampe centré, égouts plus sombres, caméra fêlée après
   l'agression, moins de balancement (mouvement en « U » doux en courant), shaders plus réalistes (macroblocs,
   buée, gouttes), un égoutier mourant juste à la sortie de la cage qui explique les 3 fusibles, pas dans l'eau
   refaits, éclats de verre qui craquent même accroupi (les bouteilles en laissent), chaque fusible agite le
   monstre, traces mouillées de la créature, sons étouffés derrière les murs, écho par zone, planque d'une
   ancienne victime, buée en entrant dans la citerne, mains qui tremblent après une poursuite, la vapeur couvre
   les bruits du monstre, faux contacts de la lampe ; à la maison, Théo ne dit plus « ils connaissent mon nom »
   (c'est sur les téléphones de ses potes) mais un truc confus.
11. 24/10/2026 : 2e liste. PNJ : mains au sol (plus de bras de zombie), conversation en gros plan jusqu'au bout
   (bug des sous-titres qui s'effaçaient) ; flare sans dédoublement (« pas l'effet bourré »), plus de fissure ;
   bouteille cassée réaliste ; égouts encore plus sombres, lampe moins forte avec plusieurs faux contacts
   (dont une coupure d'1 s) ; gouttes floues et discrètes ; traces mouillées réalistes ; vrais sons enregistrés
   (pas, eau, verre, rats, mouches) ; mouches en essaim ; corps bien au sol ; poteaux de la citerne en béton
   vieilli (plus le gris uni) ; la créature touche le sol au galop ; campement déplaçable dans l'éditeur ;
   citerne : seulement des quais le long des murs, un socle à chaque poteau ; plantage de la lampe corrigé.
   Sa carte des égouts modifiée le 23/10 (121 objets) est recopiée dans maps/.
12. Retour : « les nouveaux bruits de pas j'adore », mais pas ceux dans l'eau → remplacés par une marche dans
   l'eau peu profonde (on brasse l'eau). La créature flottait encore au galop → recalage image par image.
   Elle piétinait ~0,5 s en s'arrêtant à sa première apparition → animation pilotée par la vitesse réelle.

## État actuel
- Jeu complet et jouable de bout en bout (route → maison → égouts → forêt), environ 30-45 min.
- Dernier export : build/DernierEnregistrement.exe + DernierEnregistrement.zip (non versionnés ;
  `tools/dev/package.py` refait le zip après l'export).
- Les cartes de l'utilisateur (maison, égouts) sont dans `maps/` (identiques à celles de son %APPDATA% au 23/10/2026).

## Idées proposées, pas encore faites
- Ronds dans l'eau et débris qui dérivent dans la cunette (le plus coûteux).
- Petite incohérence : le README appelle l'acte 3 « Sous la ville » alors que les égouts sont sous la forêt.

## À rappeler à l'utilisateur
- Révoquer le jeton API Sketchfab qu'il a collé dans une ancienne conversation (sketchfab.com → Settings → Password & API).
