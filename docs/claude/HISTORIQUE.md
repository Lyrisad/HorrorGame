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
13. L'égoutier ne touchait pas le sol avec ses fesses (posé sur une main) → posé par le bassin ; l'indice du micro
   sortait de l'écran → retour à la ligne. Puis : on ne voyait pas la vapeur (fin tuyau à 2,2 m) → 3 fuites sur
   une conduite à hauteur d'homme ; on ne voyait pas les traces de la créature (elle marchait dans l'eau) → elle
   longe les banquettes ; la lumière des allées voisines se reflétait à travers les murs → ombres sur les lampes
   proches. Carte des égouts du joueur (campement déplacé le 24/10) recopiée dans maps/.
14. Faux contacts de la lampe plus fréquents ; la créature repasse aussi dans l'eau (un tiers du temps) ;
   poussière plus réaliste et un peu plus dense, avec des « orbes » flous près de l'objectif.
15. Idées proposées (liste de 12) ; il a choisi : eau vivante (ronds, gouttes, débris, brume), cafards qui fuient
   le faisceau, exposition automatique qui « pompe » + mise au point qui patine. Faits. Restent en idées : vrais
   sons partout, voix de Théo (à enregistrer par lui), objets qu'on heurte, mains à l'image, batterie de lampe,
   retenir sa respiration, cachettes, plus d'histoire à trouver, réglage de qualité graphique.
16. Vapeur : sur les tuyaux du haut (pas de conduite ajoutée seule). Variété des murs et sols (mousse, sel,
   coulures, vase, flaques, moisissures) ; beaucoup plus de cafards, partout, surtout au sol.
17. Mort vue par la caméra tombée (Théo traîné hors du champ, SIGNAL PERDU, rembobinage façon cassette jusqu'au
   point de reprise) ; événements au hasard (coups de bélier, gravats, lampe qui éclate, grille qui grince,
   ruée de rats).
18. Mort simplifiée : la caméra tombe et filme le plafond + un cri (vrai enregistrement). Débris flottants refaits
   (feuille morte réaliste, mousse, brindille, écume ; plus de plastique blanc en hexagone), gravats irréguliers.
19. Conseils à l'écran refaits : carte sombre arrondie, liseré ambre, titre « CONSEIL », touches dessinées comme
   des touches de clavier (aussi dans l'invite « E »), largeur ajustée au texte. Essoufflement de Théo, respiration
   et dernier souffle de l'égoutier : de vrais enregistrements (le souffle de synthèse « saturé » est supprimé).
20. Boîte des conseils : sans liseré ni titre (juste le texte), tout en bas de l'écran sous les sous-titres ; icône
   de souris « clic droit » pour le lancer de bouteille. Le PNJ n'a plus de fausse voix de synthèse à chaque
   réplique (affreuse) ; sa respiration baisse quand il parle ; sa toux est un vrai enregistrement.
21. Gravats « trop luisants » : morceaux mats à facettes, sombres, briques et mortier ou béton selon la voûte,
   gravillons, petit rebond, filet de poussière. La baladeuse du couloir avant la première apparition grésille,
   se coupe, se rallume puis claque (étincelles) et reste éteinte.
22. Son idée : le téléphone d'Inès posé à côté d'elle (pas ramassable) sonne quand on l'examine, et la créature
   vient voir par curiosité. Toiles d'araignée (coins, arêtes, fils pendants) déplaçables dans l'éditeur ; griffes
   qu'on entend racler les murs quand la créature rôde hors de vue.
23. Toiles : il ne garde que celles qui pendent du plafond (coins et arêtes retirés du jeu et de sa carte, qu'il
   avait sauvegardée avec les toiles par défaut ; rien d'autre n'y avait changé). Build pour l'envoyer à un ami.
24. Voix sur les dialogues : je lui ai donné le texte de l'égoutier et un prompt de voix ; il a fourni les 7 répliques
   (tools/voices_src/egoutier), traitées et branchées (le sous-titre suit la voix). Il a demandé d'attendre avant le
   prochain build (« un autre truc à faire »).
25. Micro-freezes au lancement des scripts (l'homme au masque qui « pop » devant les écrans, événements des égouts) :
   préchauffage des shaders pendant l'écran de chargement (Level.prewarm). Mesuré : l'apparition du masque (143 ms),
   la révélation de la créature (116 ms), le téléphone d'Inès (114 ms), la poussière des éboulements (147 ms), le
   premier cafard (55 ms) → plus d'à-coup. Build pour son ami.
26. « Non, non, non... pas maintenant » au hasard : c'était la lampe qui éclate hors de vue ; Théo ne commente
   plus que s'il l'a vue. Je lui ai donné les 102 répliques de Théo à enregistrer (theo_001 à theo_102).
27. Touches réattribuables (Paramètres → Touches) ; bouteilles à ramasser posables dans l'éditeur. Il trouve la
   surface (forêt de fin) vide : idées proposées.
28. « FAIT MOI UN TRUC DE FOU » : toutes les idées de la surface en un vrai dernier chapitre (traces des sessions,
   pièges à loup, drone abattable, caméra de la victime, cabane et radio, camp des ravisseurs avec écrans, dossiers,
   dons et son téléphone, homme au masque qui patrouille (il voit, entend mal), la radio répond « Ouvrez la trappe »,
   course contre la créature jusqu'à la route, puis la révélation de la caméra du poteau).

29. Il met 5/20 à la surface : refaite de nuit, cabane en rondins aménagée (carte annotée de David Roche, radio,
   lit, bois), camp crédible (bâche, table kaki, écrans, van, feu avec flammes et crépitements, lampe de chantier,
   antennes du brouilleur), deux hommes au masque, drone avec aide à la visée des cailloux, pièges : marteler E,
   vidéo de la caméra de la victime lue sur son écran (vision nocturne), téléphone d'un inconnu (le sien reste
   sur lui), tout déplaçable dans l'éditeur (menu « FORÊT (SURFACE) » ou F8).

30. Retour sur cette version (feuillage qui pousse par blocs et pas naturel, objets du camp traversables, objets de
   la cabane à bouger un par un, aucun ennemi qui le poursuit, drone jamais vu, plus sombre, feuilles en tâches sur
   le sentier et la route, écrans du camp montés à l'envers, poussière des égouts). Fait : écrans retournés, hitbox
   automatiques (plantes traversables), chaque objet de la cabane et de la table du camp déplaçable seul, sous-bois
   en touffes déplaçables (ajouté une fois à sa carte), tapis de feuilles sur les pièges, nuit plus noire (lampe qui
   porte plus loin), poussière, drone avec projecteur, homme au masque qui descend le sentier vers lui (~35 s).
   Bug trouvé dans ses cartes : D (déplacement) dans la liste de l'éditeur créait des « dead tree trunk » empilés au
   point 0 (6 égouts, 43 maison, 52 forêt) → liste sans clavier, ignorés au chargement. Il a précisé que la grosse
   boule blanche au camp était la lampe sur la fumée du feu (pas la poussière) : poussière laissée comme avant.
   Puis : le duvet restait lié au lit, le bocal et les bouteilles à l'étagère → objets séparés (la hache du billot
   aussi).
31. « La route fait tristoune, vide, la transition forêt/route est moche » + « dans la vidéo de la caméra, le
   personnage passe à travers les arbres ». Fait : vraie départementale D 47 (enrobé bombé aux bords grignotés,
   marquage usé et rétroréfléchissant, accotements de gravier, herbe sèche de novembre sur les bas-côtés), ligne
   électrique sur poteaux en bois (la caméra est sur l'un d'eux), balises J6, panneaux 80 et « chasse en cours »,
   borne kilométrique, panneau ONF « Forêt domaniale des Essarts », barrière du chemin ouverte (chaîne coupée),
   déchets, avis de recherche sur le poteau : tout déplaçable (ajouté une fois sur sa carte, drapeau « route »).
   La vidéo suit maintenant les vrais sentiers, en 4 plans (chemin de la cabane, la radio, chemin du camp, la
   course), sans les ennemis de cette nuit. Il a aussi demandé quand arrivent l'homme au masque et la créature.
32. « Je trouve plus les cailloux », « l'homme au masque court de façon efféminée, je veux un truc d'homme », « il
   court trop vite, je peux pas le semer », « un son pour savoir s'il m'a vu, pas "Il m'a vu" 36 fois ». Fait :
   tas de 7 galets gris visibles dans la lampe + Théo les remarque une fois ; personnage « hunter » (le ravisseur
   avec la course CMU 16_55 : buste penché, bras qui pompent ; l'ancienne 35_17 croisait les pieds) ; il court à
   3,6 m/s, s'essouffle après 6 s (trot 2,4), le perd après 3 s hors de vue (portée 20 m lampe allumée, 13 m
   éteinte) ; repéré = note stridente + grésillement de sa radio, ses pas et son souffle s'entendent ; répliques
   et indices dits une seule fois par partie (même après une mort).
33. « Il court encore comme un golmon », « une tenue différente, on sait pas qui est qui », « le premier n'est pas
   là », « le drone est coincé dans le trou, ça bourdonne mais je le vois pas », « portière et son du repérage à
   peine audibles », « pendant la vidéo de la caméra le mec arrive et en sortant il est là, bouh ». Fait : course
   104_37 (droite, grande foulée) + trot 16_35 quand il s'essouffle ; celui du van en tenue de chasse kaki, gilet
   orange fluo, vieux masque à tuyau, lampe jaunâtre (l'autre tout en noir, GP-5, lampe blanche) ; le drone ne
   tourne plus dans les sapins (au-dessus des sentiers / de la route, à ~6,5 m, feux rouges/verts, flash plus fort)
   et arrive de face ; portière +8 dB, repérage +8 dB ; pendant une cinématique les hommes au masque s'arrêtent, le
   drone n'arrive pas, puis 4 s de répit. Dans le test, le premier homme descend bien le sentier (~30 s).
34. « Je spawn, j'entends un bourdonnement à mes pieds » (déjà le « drone coincé dans le trou »). Vraie cause,
   trouvée avec --surfacetest=sounds : la RESPIRATION de la créature endormie, rangée au point 0 (sous la plaque
   d'égout de la sortie) ; elle était « en pause », et Godot relance tout son en pause à la fin de n'importe quelle
   pause du jeu. Corrigé : arrêtée (stop) tant qu'elle dort. Aussi : le drone de préchauffage ne bourdonne plus.

## État actuel
- Jeu complet et jouable de bout en bout (route → maison → égouts → forêt), environ 30-45 min.
- Dernier export : build/DernierEnregistrement.exe + DernierEnregistrement.zip (non versionnés ;
  `tools/dev/package.py` refait le zip après l'export).
- Les cartes de l'utilisateur (maison, égouts, forêt) sont dans `maps/` (identiques à celles de son %APPDATA% au 26/10/2026 ;
  sa forêt, ressauvegardée par lui le 26/10 à 22:07 avec le build de la route : 492 objets, drapeau « route »).

## Idées proposées, pas encore faites
- Ronds dans l'eau et débris qui dérivent dans la cunette (le plus coûteux).
- Petite incohérence : le README appelle l'acte 3 « Sous la ville » alors que les égouts sont sous la forêt.

## À rappeler à l'utilisateur
- Révoquer le jeton API Sketchfab qu'il a collé dans une ancienne conversation (sketchfab.com → Settings → Password & API).
