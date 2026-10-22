# Dernier Enregistrement — notes pour Claude

Jeu d'horreur « found footage » vu à travers la caméra-piéton de Théo. Godot 4.7.2 / GDScript, exporté en .exe Windows.
Ce fichier et `docs/claude/` sont **la mémoire du projet** : ils suivent le dépôt d'un PC à l'autre
(la mémoire automatique de Claude Code, elle, reste sur chaque PC). Les détails sont importés ici :

@docs/claude/NOTES.md
@docs/claude/HISTORIQUE.md

## L'utilisateur
- Écrit en français familier (parfois en anglais) : réponds dans sa langue, tutoiement, ton direct.
- Veut un jeu **réaliste** (vrais modèles, vrais sons, vraies animations) et rejette tout ce qui fait bricolé.
  Il teste lui-même et renvoie des listes de retours précises, souvent avec des captures d'écran.
- Préfère les applis natives (.exe) aux versions navigateur.
- Son budget de session est limité : pour les grosses demandes, propose un ordre de priorité et vérifie avec une
  seule planche de captures plutôt que dix images.

## Règles à ne jamais enfreindre
1. **Ne jamais casser ses cartes.** Ses dispositions (éditeur F8) sont dans
   `%APPDATA%\Godot\app_userdata\Dernier Enregistrement\cartes\` (`maison.json`, `egouts.json`) et copiées dans `maps/`
   (livrées avec le jeu). Avant tout test qui sauvegarde (`--edtest`, `--edcam`, `--edclick`, `--edlap`) : copie de
   sauvegarde, puis restauration et vérification md5. Avant un commit ou une release, si ses cartes de %APPDATA% ont
   changé, recopie-les dans `maps/` (sur un PC neuf sans %APPDATA%, le jeu utilise `maps/`).
2. **Aucun secret dans le dépôt (il est public).** Le jeton API Sketchfab ne s'écrit jamais dans un fichier :
   seulement `SKETCHFAB_TOKEN=...` sur la ligne de commande. Pas d'e-mail ni de chemin personnel dans les fichiers.
3. Tests automatiques : toujours `--nomic` (sinon le jeu écoute son vrai micro) et le mode `--shots` (il ignore
   souris et clavier, l'utilisateur peut se servir du PC pendant ce temps).
4. Les égouts sont sous une **forêt**, pas sous une ville : pas de voitures ni de bruits urbains.
5. Chaque modèle externe est crédité dans `CREDITS.md`.

## Démarrer sur un nouveau PC
1. `git clone https://github.com/Lyrisad/HorrorGame.git`, puis ouvrir Claude Code dans ce dossier.
2. PowerShell, à la racine : `powershell -ExecutionPolicy Bypass -File tools\setup_pc.ps1` → Godot 4.7.2 dans
   `tools\godot\`, modèles d'export Windows, premier import (`.godot/`). Ajouter `-Blender` pour refaire des
   personnages ou modèles.
3. Python (sons, textures, planches de captures) : `python -m venv .venv` puis
   `.venv\Scripts\pip install -r tools\requirements.txt`. Dans Git Bash, n'appelle jamais `python` tout court
   (le raccourci du Microsoft Store bloque) : utilise `.venv/Scripts/python.exe`.
4. Non versionnés (lourds, re-téléchargeables) : `.godot/`, `build/`, `tools/godot/`, `tools/blender/`,
   `tools/rocketbox_src/` (sources des personnages Rocketbox : `tools/dev/rb_download.py`, seulement pour les refaire).

## Commandes utiles
- Test avec captures : `sh tools/dev/run.sh <dossier> <nom> <timeout_s> --level=sewer --torch --shots=3,8 ...`
  → `tools/dev/out/<dossier>/<nom>_N.png` (timeout ≥ 25 s pour les égouts ; la maison met ~11 s à charger).
- Après de nouveaux assets ou scripts `class_name` :
  `tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import`
- Exporter : `tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build/DernierEnregistrement.exe`
  puis `python tools/dev/package.py` → `build/DernierEnregistrement.zip` (exe + `docs/LISEZ-MOI.txt` + CREDITS.md).
- Toutes les options de test : README.md (« Options de test ») et docs/claude/NOTES.md (« Testing »).

## Garder cette mémoire à jour
Quand tu apprends quelque chose de durable (piège technique, décision, préférence ou retour de l'utilisateur),
écris-le dans `docs/claude/NOTES.md` (technique) ou `docs/claude/HISTORIQUE.md` (demandes, état, idées), pas
seulement dans la mémoire automatique locale. À la fin d'une séance, propose de committer et pousser pour que
l'autre PC en profite.
