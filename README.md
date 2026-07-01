# Forgotten Caves

Jeu de gestion de colonie de nains en 3D par blocs (voxels), inspiré de Dwarf Fortress / RimWorld.

## Stack technique

- Moteur : Godot 4.3+ (GDScript)
- Rendu : Forward+ (3D)
- Plateformes cibles : Windows, macOS

## Structure du projet

```
ForgottenCavesGame/
├── project.godot        # Fichier de configuration du projet
├── scenes/               # Scenes Godot (.tscn)
│   └── Main.tscn         # Scene de depart : camera + lumiere + grille de blocs
├── scripts/              # Scripts GDScript (.gd)
│   ├── VoxelWorld.gd     # Genere la carte de test et construit le mesh (Sprint 1)
│   └── CameraRig.gd      # Camera controlable : deplacement, rotation, zoom, niveaux (Sprint 2)
└── assets/               # Modeles, textures, sons...
```

(le fichier `scripts/Main.gd` du Sprint 0 n'est plus utilise, remplace par `CameraRig.gd` — tu peux le supprimer toi-meme si tu veux faire le menage)

## Prise en main

1. Installer Godot 4.3 ou superieur : https://godotengine.org/download
2. Ouvrir Godot, cliquer sur "Importer", selectionner le fichier `project.godot`
3. Appuyer sur F5 (ou le bouton Play) pour lancer le jeu
4. Une petite carte de blocs (20x20x10, terre sur pierre) doit s'afficher

## Controles camera (Sprint 2)

- Deplacement : Z / Q / S / D
- Rotation : A et E (pas Q, deja pris par le deplacement)
- Zoom : + et -
- Changer de niveau de profondeur : molette de la souris (affiche en haut a gauche)

## Suivi du projet

Le planning de sprints est dans `Forgotten_Caves_Sprints.xlsx` (dossier parent).

## Sprint 0 — Fondations techniques

- [x] Choix du moteur (Godot)
- [x] Structure de projet initiale
- [x] Premier rendu de bloc 3D (cube de test dans Main.tscn)
- [x] Repo Git initialise et pousse sur GitHub

## Sprint 1 — Generation de terrain en blocs

- [x] Generation d'une grille de blocs (20x20x10, terrain plat : terre sur pierre)
- [x] Affichage des blocs terre/pierre (couleurs unies : marron/gris)
- [x] Optimisation de l'affichage : un seul mesh par materiau, seules les faces exposees sont dessinees (culling des faces internes)
- [x] Teste dans Godot (F5) et confirme que la carte s'affiche correctement (damier visible = grille de blocs confirmee)

### Notes techniques Sprint 1

- Taille de test volontairement petite (20x20x10) pour valider l'affichage avant de viser la taille cible (200x200x100)
- Terrain plat pour l'instant : le relief (collines, creux, rivieres) sera ajoute dans un sprint dedie
- `VoxelWorld.gd` stocke la grille dans un dictionnaire `Vector3i -> type de bloc`, puis construit un `ArrayMesh` avec une surface "terre" et une surface "pierre", en n'ajoutant une face que si le bloc voisin est vide (culling)

## Sprint 2 — Navigation camera

- [x] Deplacement (pan) au clavier : ZQSD
- [x] Rotation autour de la scene : touches A / E
- [x] Zoom avant/arriere : touches + / -
- [x] Changement de niveau de profondeur : molette de la souris, avec indicateur affiche a l'ecran
- [ ] Teste dans Godot et confirme que tous les controles fonctionnent

### Notes techniques Sprint 2

- `CameraRig.gd` est un pivot (Node3D) qui porte la camera en enfant : elle tourne autour du pivot (orbite), zoom = distance au pivot
- Utilise `Input.is_physical_key_pressed` / `event.physical_keycode` (position physique de la touche) plutot que le caractere affiche, pour que ZQSD/A/E fonctionnent correctement sur un clavier francais AZERTY
- Le "niveau" actuel deplace juste la hauteur du point vise par la camera ; le rendu en coupe (cacher les niveaux au-dessus) viendra plus tard avec le minage
