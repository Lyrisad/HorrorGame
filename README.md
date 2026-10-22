# DERNIER ENREGISTREMENT

Jeu d'horreur *found footage* à la première personne, vu à travers la **caméra-piéton** (bodycam)
de Théo, un agent de sécurité qui voulait juste rejoindre l'anniversaire de son pote Max.

Moteur : **Godot 4.7** (GDScript). Plateforme : **Windows** (.exe).

---

## Jouer

Double-clique sur **`build/DernierEnregistrement.exe`** (tout est embarqué dedans, aucune installation).

| Touche | Action |
|---|---|
| **ZQSD / WASD** (ou flèches) | se déplacer (les touches physiques sont détectées : AZERTY et QWERTY marchent) |
| **Souris** | regarder |
| **Maj** | courir (endurance limitée… et ça fait du bruit) |
| **C** (maintenir) | s'accroupir, se déplacer sans bruit |
| **F** | lampe torche |
| **E** | interagir (certaines actions se maintiennent) |
| **G** ou **clic droit** | lancer une bouteille vide (diversion, dans les égouts) |
| **Tab** | rappeler l'objectif |
| **I** | inventaire (objets en poche, documents à relire) — le jeu est en pause |
| **Échap** | pause / paramètres (sensibilité, volume, musique, luminosité, plein écran) |
| **F11** | plein écran / fenêtré |

Casque fortement recommandé : la créature se repère **au son**, et tu dois la repérer au son aussi.

---

## L'histoire (4 actes, environ 20 à 30 min selon ta prudence)

1. **La route** — 23:41. Théo sort de 12 h de garde et roule de nuit, sous la pluie, vers la maison de Max.
   Messages des potes sur le téléphone… et une silhouette immobile au bord de la route.
2. **La maison** — Musique à fond, lumières allumées, gâteau sur la table… personne.
   Leurs trois téléphones alignés. Des caméras de surveillance partout, qui **tournent pour le suivre**.
   La télé retransmet le salon en direct : Théo s'y voit. Quand il a tout fouillé (liste du frigo, télé,
   ordinateur, téléphones, portes fermées), le courant saute. Portes verrouillées.
   Le bureau, fermé à clé, s'ouvre tout seul. Sur l'écran, quelqu'un se tient derrière lui…
3. **Sous la ville** — Théo se réveille **enfermé dans une cage** au fond des égouts (lampe, barreau descellé,
   clés à attraper…). Quelque chose y rôde : **aveugle, il chasse au son**. La grille de l'écluse 3 est
   enchaînée **et** privée de courant : il faut le coupe-boulons du local technique et les **trois fusibles**
   de l'armoire, jetés dans le réseau (un dans chaque partie des égouts), puis remettre le courant — bruyamment.
4. **Surface** — L'aube. Il est sorti… mais une caméra sur un poteau se tourne vers lui.
   Depuis le début, tout était **diffusé en direct**.

### Comment survivre dans les égouts
- La créature n'y voit rien : elle **entend**. Marcher = bruit moyen, courir = beaucoup de bruit, accroupi = presque rien.
- L'eau de la citerne rend tes pas bien plus bruyants.
- **Accroupi et immobile**, elle peut passer juste à côté de toi sans te trouver.
- Quand elle **clique**, elle écoute. Ne bouge plus.
- **À bout de souffle**, Théo halète : si elle est à portée d'oreille, elle charge — plus vite que d'habitude.
- Le vumètre **MIC** en bas à droite montre ce que capte le micro de la caméra… et **ton vrai micro** : si tu parles
  ou cries, il passe au rouge et la créature t'entend (chuchoter : ~3 m, parler : ~8 m, crier : jusqu'à 24 m).
  Seul le niveau sonore est mesuré, rien n'est enregistré. Casque conseillé ; réglages : Paramètres → Micro.
- **On peut la semer** : elle s'essouffle après quelques secondes de galop, et un bruit derrière un mur porte
  moins loin. Tourne à un angle, puis avance sans bruit.
- **Bouteilles vides** : ramasse-les et lance-les (G / clic droit) — le verre qui éclate l'attire là-bas.
- Prendre le coupe-boulons fait tomber un seau : elle **charge**. Si elle t'attrape ensuite (pendant la
  poursuite ou plus tard), tu reprends devant l'établi : il faut reprendre le coupe-boulons et refaire la poursuite.
- Si elle t'attrape : reprise au dernier point de contrôle (sortie de la cage, ou devant l'établi ;
  les fusibles déjà trouvés restent acquis).

---

## Modifier le jeu

1. Récupère le projet : `git clone https://github.com/Lyrisad/HorrorGame.git`.
2. Dans PowerShell, à la racine : `powershell -ExecutionPolicy Bypass -File tools\setup_pc.ps1`
   (télécharge **Godot 4.7.2** dans `tools/godot/`, installe les modèles d'export Windows et importe les ressources ;
   ajoute `-Blender` pour refaire personnages et modèles). Le dossier `build/` et les gros outils ne sont pas sur GitHub.
3. Lance `tools/godot/Godot_v4.7.2-stable_win64.exe`, *Importer* → choisis `project.godot` dans ce dossier.
4. **F5** pour jouer depuis l'éditeur.

Les scripts Python (sons, textures) demandent `pip install -r tools/requirements.txt`.
Les notes de développement (et la mémoire de Claude Code) sont dans `CLAUDE.md` et `docs/claude/`.

### Organisation

```
project.godot            configuration (fenêtre, rendu, autoloads)
scenes/main.tscn         scène racine (vide : tout est construit par code)
scripts/
  core/
    game.gd              chef d'orchestre : niveaux, pause, horloge, effets, sauvegarde
    sound.gd             sons 2D/3D, boucles, bus (réverbération, étouffement)
    player.gd            joueur bodycam : caméra au torse, marches, lampe, endurance, bruit
    hud.gd / ui.gd       incrustation caméra, sous-titres, menus, documents
    level.gd             base des niveaux (attentes, déclencheurs, environnement)
    build.gd             construction : matériaux, modèles (avec cache), lumières, décals
    interactable.gd      objets avec lesquels on interagit [E]
  actors/
    actor.gd             personnage réaliste animé (modèle riggé + captures de mouvement)
    creature.gd          la créature : animations + IA (ronde, enquête, fouille, poursuite)
    twitch_modifier.gd   tics nerveux de la tête de la créature (par-dessus l'animation)
    security_camera.gd   caméras de surveillance qui suivent le joueur
    security_feed.gd     retransmission en direct sur les écrans (SubViewport)
  levels/
    night.gd             Actes I + II : la route ET la maison dans un seul monde continu
    sewer.gd             Acte III — les égouts (plan en ASCII modifiable en haut du fichier !)
    ending.gd            Épilogue
  world/
    car_rig.gd           la voiture vue de l'intérieur (volant, téléphone, autoradio, phares)
    house_builder.gd     la maison : murs, fenêtres, portes, mobilier, éclairage, caméras
    nature.gd            forêt (vrais arbres instanciés), sol, pluie
    props.gd             petits accessoires (téléphones, écrans, bougies, ballons…)
shaders/                 caméra-piéton, écrans de surveillance, eau, pare-brise
assets/
  characters/            personnages animés (.glb) générés par tools/blender_scripts
  sketchfab/             voiture, créature, mobilier, arbres (CC BY, voir CREDITS.md)
  models/, textures/     modèles et textures Poly Haven (CC0)
  audio/, gen/           sons et textures générés par code
tools/                   Godot, Blender, captures de mouvement, scripts (ignoré par Godot)
```

### Personnages et animations
Les personnages sont fabriqués par `tools/blender_scripts/build_characters.py` (Python) :
il lance Blender (`tools/blender/`) qui applique des captures de mouvement CMU
(`tools/mocap/cmu/*.bvh`) sur les humains Rocketbox (`retarget.py`) et exporte des `.glb`.
La créature (« The Rake », Sketchfab) garde les animations faites par son auteur pour son corps
de bête : `prepare_native.py` les met à l'échelle, les renomme et mesure leur vitesse au sol.
Pour ajouter une animation : ajoute un clip dans `CHARACTERS` puis relance le script.

### Éditeur de carte (placer soi-même les objets)
Dans le jeu, touche **F8** dans la maison ou les égouts, ou menu principal → *Éditeur de cartes*.
- **Caméra** : clic droit maintenu pour regarder, ZQSD/WASD pour avancer, Espace / C pour monter / descendre, Maj pour aller vite, molette (sans objet choisi) pour la vitesse.
- **Ajouter** : choisir un modèle dans la liste de gauche (champ de recherche, noms en anglais : *chair*, *bottle*, *plant*…) ; il suit la souris et se pose sur la surface visée (sol, table, étagère, mur) ; clic pour le poser.
- **Modifier** : clic gauche sur un objet : il suit la souris (avec ce qui est posé dessus) ; nouveau clic gauche pour le poser. Cliquer-glisser marche aussi. Molette : tourner (Alt = précis) · **Ctrl + molette : agrandir / réduire** · **Maj + molette : monter / descendre** (ou + / − et PgUp / PgDn) · flèches : ajuster · X : coucher · R : remettre droit.
- **Ctrl+D** dupliquer · **Suppr** supprimer · **Ctrl+Z** annuler · **Ctrl+S** sauvegarder · **F8 / Échap** quitter (sauvegarde automatique) · **L** lampe de travail.
- **Caméras de surveillance** : clic gauche pour en prendre une, elle se fixe sur le mur ou au plafond visé ; molette pour la tourner, Maj + molette pour l'incliner. En jeu, elles suivent Théo sans jamais se retourner vers leur mur.
- **Éléments du niveau déplaçables** (non supprimables) : l'ordinateur portable de la chambre (sa zone d'interaction le suit),
  le tapis de bain, et dans les égouts les hublots muraux (appliques au sodium, feu rouge de l'écluse, lampe de la grille) :
  leur lumière les suit. Posés sur un mur, ils s'y collent face à la pièce.
- **Caméras de surveillance** : le support reste vissé à la surface où tu la poses (mur, poteau, plafond) ; seule la tête pivote.
- Les autres objets liés à l'histoire (téléphones, gâteau, télé, enceinte, rocking-chair, frigo et sa liste, lit, bureau et écrans, lavabo, coupe-boulons, grille…) restent fixes.
- La disposition est enregistrée dans `%APPDATA%\Godot\app_userdata\Dernier Enregistrement\cartes\` (`maison.json`, `egouts.json`) et rechargée à chaque partie. *Remettre le décor d'origine* efface ce fichier. Depuis les sources (Godot), elle est aussi copiée dans `maps/` pour être livrée avec le .exe.

### Idées de modifications faciles
- **Dialogues / textes** : cherche `Game.hud.say(` dans `scripts/levels/*.gd`.
- **Plan des égouts** : tableau `MAP` en haut de `sewer.gd` (`#` mur, `.` couloir, `w` eau, `T` local technique, `G` grille, `E` sortie). Trois époques selon la colonne (`zone_of`) : collecteur voûté en briques, réservoir en béton, galeries techniques. La cunette, les canalisations, les portiques entre époques et les linteaux sont générés automatiquement.
- **Objets de la maison** : `house_builder.gd` ; `put_on()` pose un petit objet sur le meuble en dessous (calculé au chargement), `support()` déclare un meuble qui sert d'appui.
- **Difficulté de la créature** : constantes en haut de `creature.gd` (`CHASE_SPEED`, `CATCH_DIST`…) et rayons de bruit dans `player.gd` (`_footstep`).
- **Look de la caméra** : valeurs par défaut dans `game.gd` (`FX_DEFAULTS` : distorsion, grain, saturation…).
- **Sons** : modifie `tools/audio_gen/generate_sounds.py` puis relance-le (Python + numpy + scipy) ; `extra_sounds.py` ne régénère que quelques sons.
- **Textures « lisibles »** (liste du frigo, note de l'égoutier, écrans des téléphones) : `tools/texture_gen/generate_ui_textures.py` ; marquages des égouts : `generate_sewer_decals.py`.

### Options de test (ligne de commande)
Après `--`, par exemple :
```
Godot_v4.7.2-stable_win64.exe --path . -- --level=sewer --windowed
```
- `--level=drive|house|sewer|ending` : démarre directement un acte
- `--checkpoint=cutters` : égouts, avec le coupe-boulons déjà pris
- `--hwarp=x,z --hyaw=deg` : maison, position dans le repère de la maison
- `--warp=x,z --yaw=deg --pitch=deg` : position / regard de départ (égouts, épilogue)
- `--creature=x,z [--chase]` : égouts, place la créature (et lance la poursuite)
- `--torch` : égouts, saute le réveil et la cage (lampe allumée)
- `--checkpoint=cell|bench|cutters` : égouts, reprise après la cage / devant l'établi / après le coupe-boulons
- `--nomic` : n'ouvre jamais le micro (tests) ; `--mictest`, `--cuttertest`, `--pantest` : tests automatiques
- `--celltest`, `--fusetest` (avec `--torch`), `--bottletest` (avec `--creature --chase`) : tests automatiques des énigmes
- `--bright` : égouts tout éclairés, sans brouillard (pour inspecter la géométrie)
- `--gust` : égouts, coup de vent de la forêt au-dessus du puits le plus proche après 1 s
- `--freecam=x,y,z --freelook=x,y,z` : égouts / épilogue, caméra libre pour inspecter un détail
- `--autotest=house|sewer` : joue une séquence automatiquement ; `--autoexit` sort de la voiture
- `--topdown`, `--hide=Ceil0,Wall1` : vues de débogage des égouts
- `--editor` : ouvre l'éditeur de carte au démarrage ; `--edtest`, `--edclick`, `--edcam`, `--edlap` : tests automatiques de l'éditeur (ils sauvegardent : garder une copie de ses cartes)
- `--shots=3,8 --shot=chemin/prefixe --quit` : captures d'écran automatiques

### Ré-exporter le .exe
Dans l'éditeur : *Projet → Exporter… → Windows Desktop*. Ou en ligne de commande :
```
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build/DernierEnregistrement.exe
```
(les modèles d'export Windows 4.7.2 sont installés par `tools/setup_pc.ps1`), puis `python tools/dev/package.py`
pour refaire `build/DernierEnregistrement.zip` (le .exe + `docs/LISEZ-MOI.txt` + `CREDITS.md`) à envoyer.

---

## Crédits
Voir **CREDITS.md** : Poly Haven (CC0), Sketchfab (CC BY — attribution obligatoire),
Microsoft Rocketbox (MIT), CMU Motion Capture Database, Godot Engine (MIT).