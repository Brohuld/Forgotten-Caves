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
│   └── Main.tscn         # Scene de depart : camera + lumiere + 1 bloc de test
├── scripts/              # Scripts GDScript (.gd)
└── assets/               # Modeles, textures, sons...
```

## Prise en main

1. Installer Godot 4.3 ou superieur : https://godotengine.org/download
2. Ouvrir Godot, cliquer sur "Importer", selectionner le fichier `project.godot`
3. Appuyer sur F5 (ou le bouton Play) pour lancer le jeu
4. Un cube marron doit s'afficher a l'ecran : c'est le premier "bloc" du jeu (Sprint 0 valide)

## Suivi du projet

Le planning de sprints est dans `Forgotten_Caves_Sprints.xlsx` (dossier parent).

## Sprint 0 — Fondations techniques

- [x] Choix du moteur (Godot)
- [x] Structure de projet initiale
- [x] Premier rendu de bloc 3D (cube de test dans Main.tscn)
- [ ] Repo Git initialise et pousse sur GitHub
