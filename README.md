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
│   ├── Main.gd           # Positionne la camera au demarrage
│   └── VoxelWorld.gd     # Genere la carte de test et construit le mesh (Sprint 1)
└── assets/               # Modeles, textures, sons...
```

## Prise en main

1. Installer Godot 4.3 ou superieur : https://godotengine.org/download
2. Ouvrir Godot, cliquer sur "Importer", selectionner le fichier `project.godot`
3. Appuyer sur F5 (ou le bouton Play) pour lancer le jeu
4. Une petite carte de blocs (20x20x10, terre sur pierre) doit s'afficher, vue de dessus/de loin

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
- [ ] Teste dans Godot (F5) et confirme que la carte s'affiche correctement

### Notes techniques Sprint 1

- Taille de test volontairement petite (20x20x10) pour valider l'affichage avant de viser la taille cible (200x200x100)
- Terrain plat pour l'instant : le relief (collines, creux, rivieres) sera ajoute dans un sprint dedie
- `VoxelWorld.gd` stocke la grille dans un dictionnaire `Vector3i -> type de bloc`, puis construit un `ArrayMesh` avec une surface "terre" et une surface "pierre", en n'ajoutant une face que si le bloc voisin est vide (culling)
