# Forgotten Caves

Jeu de gestion de colonie de nains en 3D par blocs (voxels), inspiré de Dwarf Fortress / RimWorld.

## Stack technique

- Moteur : Godot 4.7 (GDScript)
- Rendu : Forward+ (3D)
- Plateformes cibles : Windows, macOS (portage iPad/iPhone envisagé mais pas encore traité, voir section Portabilité)

## Prise en main

1. Installer Godot 4.7 ou supérieur : https://godotengine.org/download
2. Ouvrir Godot, cliquer sur "Importer", sélectionner le fichier `project.godot`
3. Appuyer sur F5 (Run Project, pas F6 "Run Current Scene") pour lancer le jeu

Le jeu démarre sur `StartMenu.tscn` (écran de saisie de graine de génération de carte) avant de charger `Main.tscn`, la scène de jeu proprement dite.

## Contrôles

**Caméra** (`CameraRig.gd`) :
- Déplacement : Z / Q / S / D
- Rotation : A et E
- Zoom : + et - (ou Ctrl+molette)
- Changer de niveau de vue (coupe horizontale façon Dwarf Fortress) : molette de la souris
- Angle de vue : maintenir le clic molette et glisser la souris

**Actions** (`ActionMenuBar.gd`) : boutons Construire/Couper/Cueillir/Creuser/Puiser/Détruire/Interdire, chacun avec un raccourci clavier physique. Vitesse du temps : Espace (pause), F1/F2/F3 (x1/x2/x4).

## Structure du projet

```
ForgottenCavesGame/
├── project.godot           # Configuration du projet (autoload GameRandom, scène de démarrage StartMenu)
├── scenes/
│   ├── StartMenu.tscn       # Écran de saisie de graine, scène de démarrage réelle
│   ├── Main.tscn            # Scène de jeu : terrain + acteurs + UI (voir Architecture ci-dessous)
│   └── prototypes/          # Scènes de test isolées (voir section Prototypes)
├── scripts/
│   ├── data/                 # Tables de données statiques (matériaux, climats, créatures, tâches)
│   ├── entites/               # Acteurs vivants et végétation (Dwarf, Forest, BerryBushes, Birds...)
│   ├── monde/                 # Terrain voxel et décor (VoxelWorld, cascades, décoration de sol)
│   ├── systemes/               # Logique globale transversale (actions, tâches, climat, caméra, UI générique...)
│   ├── ui/                     # Interface spécifique (fiche de personnage, portraits)
│   └── prototypes/             # Modèle 3D du nain (EN PRODUCTION malgré le nom) + prototypes isolés jetables
└── assets/, shaders/, themes/, tools/   # Ressources (actuellement peu peuplés - tout le rendu est procédural)
```

## Architecture générale

Le jeu ne charge aucun modèle 3D ni texture externe pour son terrain/sa végétation/ses personnages : tout est généré par code au démarrage (formes procédurales, couleurs calculées, icônes dessinées pixel par pixel). Cette section décrit les systèmes majeurs, dans l'ordre où un nouveau développeur devrait les découvrir.

### 1. Scène de jeu et ordre des nœuds (`Main.tscn`)

`Main.tscn` place environ 25 nœuds racine, dans un ordre volontaire (plusieurs systèmes lisent l'état d'un autre nœud dès leur `_ready()`, donc l'ordre de déclaration compte) :

```
DwarfModelPrewarm → WorldEnvironment/DirectionalLight3D/Moon → DayNightCycle → WeatherSystem
→ VoxelWorld → CloudSystem → WaterfallShapes/WaterfallStreaks/WaterfallFoamClouds → Forest
→ Birds → TemperatureSystem → BerryBushes → GroundDecoration → SeasonSystem → TaskQueue
→ Inventory → CameraRig → Colony (Dwarf1/2/3) → ActionUI → CharacterSheetUI
```

Points notables :
- `DwarfModelPrewarm` est délibérément premier : construire le tout premier modèle 3D de nain coûte plusieurs secondes, autant l'absorber pendant que le reste charge.
- `VoxelWorld` doit exister avant tout ce qui dépend de sa géométrie (cascades, forêt, décor, caméra).
- La plupart des systèmes climatiques/temporels (DayNightCycle/WeatherSystem/SeasonSystem/TemperatureSystem) communiquent entre eux via des références par nom unique (`%NomDuNoeud`), pas par ordre — l'ordre ne compte que pour les tout premiers appels en `_ready()`.

### 2. Le terrain voxel (`scripts/monde/`)

`VoxelWorld.gd` est le cœur du terrain : une grille 3D de blocs (terre/pierre/eau/murs), jusqu'à 250×250 en X/Z. Il a été découpé en plusieurs fichiers par responsabilité, tous dans `scripts/monde/voxel/`, qui reçoivent l'état nécessaire en paramètres plutôt que de garder leur propre copie :

| Fichier | Rôle |
|---|---|
| `VoxelMeshBuilder.gd` | Construit le mesh visible : culling des faces cachées, choix de la couleur par bloc (bruit/pénombre/AO), cache de géométrie par (niveau Y, chunk 16×16) pour ne recalculer que la zone réellement modifiée. |
| `VoxelBlockAppearance.gd` | Primitives pures de géométrie (quads/boîtes) et de couleur, sans état - extrait de VoxelMeshBuilder.gd. |
| `VoxelHydrology.gd` | Génération des lacs/rivière/cascades (partie la plus retravaillée du terrain - règles R1-R3/C1-C5 documentées dans le code). |
| `VoxelVeins.gd` | Filons de métaux/pierres précieuses dans la pierre, et leurs pépites 3D incrustées. |
| `VoxelConnectivity.gd` | Accessibilité (parcours en largeur) et creusage d'escaliers. |
| `VoxelRaycast.gd` | Raymarching voxel pour savoir quel bloc/quelle face est réellement visible sous le curseur. |

**Niveau de vue (molette)** : le jeu affiche une coupe horizontale du terrain (comme Dwarf Fortress), pilotée par `CameraRig.gd` qui appelle `VoxelWorld.set_view_level()`. Tout ce qui est au-dessus du niveau courant est caché. Un brouillard de guerre simple (case jamais minée = grise) est géré par un flag "découvert" par colonne.

### 3. Les nains (`scripts/entites/Dwarf*.gd`)

`Dwarf.gd` est le point d'entrée d'un nain (une instance par nain, tous dans le groupe Godot `"dwarves"`), mais la majorité de la logique est extraite dans des fichiers compagnons qui reçoivent le nain en paramètre (`dwarf: Node3D`) plutôt que d'hériter :

| Fichier | Rôle |
|---|---|
| `DwarfMovement.gd` | Déplacement, évitement d'obstacles, coûts de terrain (eau/escalier/dénivelé). |
| `DwarfNeeds.gd` | Besoins critiques : faim, énergie, soif. |
| `DwarfTaskResolver.gd` | Résolution d'une tâche terminée (miner/couper/construire/cueillir/puiser/détruire/escalier). |
| `DwarfVisuals.gd` | Apparence et accessoires visuels d'action (outil en main, indicateurs). |
| `DwarfResourcePile.gd` | Tas de ressources déposés au sol. |
| `DwarfSkills.gd` | Caractéristiques et compétences (gain d'XP, calcul de durée de travail). |

Le modèle 3D visuel du nain vit dans `scripts/prototypes/` (voir section 8) mais est bien utilisé en jeu, pas un prototype jetable.

### 4. Végétation et décor (`scripts/entites/`, `scripts/monde/`)

- `Forest.gd` + `ForestGeometryBuilder.gd` : arbres (forêt + fruitiers), cycle de vie (coupe/repousse/teinte saisonnière). La géométrie pure (racines/tronc/branches/feuillage) est dans `ForestGeometryBuilder.gd`, le cycle de vie reste dans `Forest.gd`.
- `BerryBushes.gd` : buissons et plantes à baies, même logique de repousse et de teinte saisonnière.
- `GroundDecoration.gd` : herbe/fleurs/cailloux, purement décoratifs, générés une fois au démarrage.
- `Birds.gd`, `CloudSystem.gd` : décor animé sans interaction gameplay.
- `WaterfallShapes.gd`, `WaterfallStreaks.gd`, `WaterfallFoamClouds.gd` : rendu visuel des cascades (le bloc EAU sous-jacent est géré par `VoxelHydrology.gd`, ces 3 fichiers n'ajoutent qu'un habillage décoratif par-dessus).

Arbres/buissons/décor partagent des `MultiMeshInstance3D` par type de pièce plutôt que des milliers de nœuds individuels, pour la performance.

### 5. Actions et tâches (`scripts/systemes/Action*.gd`, `TaskQueue.gd`)

`ActionController.gd` est le point d'entrée de l'UI d'action (barre de boutons + désignation à la souris), mais délègue à plusieurs fichiers spécialisés (même pattern de délégation que les nains - fonctions statiques recevant le contrôleur en paramètre) :

| Fichier | Rôle |
|---|---|
| `ActionDragController.gd` | Cœur du glisser-déposer/sélection rectangle et création des tâches (Miner/Construire/Puiser/Couper/Cueillir/Détruire/Interdire). |
| `ActionValidator.gd` | Détermine quelles cases d'un rectangle sont des cibles légales pour un mode donné. |
| `ActionInspector.gd` | Inspection/survol en lecture seule (panneau d'info). |
| `ActionMenuBar.gd` | Construit la barre de boutons et le sous-menu Construire à partir de tables de données. |
| `ActionShortcuts.gd` | Raccourcis clavier (changement de mode, sous-type Creuser, contrôle du temps). |

`TaskQueue.gd` est la file d'attente centrale des tâches désignées ; les nains y piochent la tâche accessible la plus proche au lieu d'errer.

`IconRenderer.gd` dessine toutes les icônes (marqueurs de tâche, climat, boutons) pixel par pixel en mémoire - jamais de fichier image externe.

### 6. Climat, temps et saisons (`scripts/systemes/`)

Quatre systèmes indépendants, chacun un minuteur/état propre, qui se lisent mutuellement via des références par nom unique (`%NomDuNoeud`) :

- `DayNightCycle.gd` : cycle jour/nuit visuel (ciel, lumière, lune). Expose des champs de base (`base_light_energy`, couleurs de ciel) que les autres systèmes lisent pour composer leurs propres effets par-dessus.
- `WeatherSystem.gd` : météo (Normal/Brouillard/Pluie/Neige), ajoute ses effets par-dessus ceux de DayNightCycle.
- `SeasonSystem.gd` : 4 saisons en boucle, reteinte le terrain et la végétation à chaque changement.
- `TemperatureSystem.gd` : température, gel du sol et neige - déterministe par saison/épisode "vague de froid" (pas un simple seuil de température continu).
- `ClimateUI.gd` : bandeaux heure/saison/météo affichés à l'écran, purement visuel.

### 7. Interface (`scripts/ui/`, `scripts/systemes/InventoryUI.gd`)

- `CharacterSheetUI.gd` : icônes de nains cliquables + fiche de personnage à onglets (État général/Caractéristiques/Compétences/Équipement).
- `PortraitRenderer.gd` : portrait 3D d'un nain (mini `SubViewport` isolé cadré sur la tête).
- `InventoryUI.gd` : panneau d'inventaire groupé par catégorie.

### 8. Modèle 3D du nain (`scripts/prototypes/DwarfModel3D.gd` et builders)

Malgré son emplacement dans `scripts/prototypes/` (héritage historique : c'était un prototype avant intégration), `DwarfModel3D.gd` est le vrai modèle 3D utilisé par tous les nains en jeu, référencé directement par `Dwarf.gd`. Sa construction est répartie en fichiers spécialisés :

| Fichier | Rôle |
|---|---|
| `DwarfWeaponBuilder.gd` | Armes (5 configurations - pas encore utilisées en jeu, en attente du système de combat). |
| `DwarfOutfitBuilder.gd` | Tenues/armures. |
| `DwarfHairBuilder.gd` | Coiffures et barbes. |
| `Model3DUtils.gd` | Utilitaires géométriques partagés entre les builders ci-dessus. |

**Le reste de `scripts/prototypes/`** (`CubeSolTest.gd`/`CubeSolTestV2.gd`, `CompositionBenchmark.gd`, `DwarfVariationGrid.gd`) sont de vrais prototypes isolés et jetables, sans aucun lien avec le jeu principal - utilisés pour dérisquer une idée (modèle de bloc CUBE+SOL, benchmark de génération) avant de la reporter dans le code de production. Leurs scènes associées sont dans `scenes/prototypes/`.

### 9. Systèmes transversaux génériques (`scripts/systemes/`)

Conçus explicitement pour qu'un futur type d'objet (porte, meuble, arme posée, ennemi...) puisse s'y brancher sans toucher au système lui-même :

- `Hoverable.gd` + `PointerResolver.gd` + `EntityDescriptions.gd` : survol/ciblage générique. Un objet devient survolable en portant une `Area3D` sur un layer dédié ; `PointerResolver.gd` arbitre terrain vs objet par distance réelle ; `EntityDescriptions.gd` fournit le texte de description.
- `Gravity.gd` : un objet posé au sol (tas de ressources aujourd'hui) retombe au premier support disponible quand le bloc sous lui est retiré, via une convention de groupe (`GRAVITY_GROUPS`).
- `ViewLevelIndex.gd` : factorise la règle de visibilité par niveau de vue (seuil, indexation, scan complet/incrémental), utilisée par la végétation et le décor.
- `GameRandom.gd` (autoload) : fournit un flux aléatoire indépendant et déterministe par nom (`GameRandom.get_rng("nom_flux")`), dérivé de la graine de partie - garantit qu'une même graine reproduit exactement la même carte/apparence, quel que soit l'ordre d'exécution des systèmes.
- `NightDarken.gd` : formule d'assombrissement nocturne partagée par les objets non éclairés (nuages, écume de cascade, tas de ressources).

### 10. Tables de données (`scripts/data/`)

Données statiques éditables sans toucher à la logique : `ClimateDefinitions.gd`, `NainNames.gd`, `SkillDefinitions.gd`, `TaskDefinitions.gd`, et sous `materiaux/` : `TreeSpecies.gd`, `BerryTypes.gd`, `MetalTypes.gd`, `GemTypes.gd` (regroupés par `VeinMaterials.gd`). Chaque table suit le même pattern (`const TABLE` + fonction statique de recherche par id) - ajouter une entrée à la table suffit généralement à ajouter une variante en jeu, sans autre modification de code.

## Conventions de code

- **Découpage sans héritage** : un fichier trop volumineux est découpé en fichiers de fonctions **statiques** qui reçoivent leur contexte en paramètre (`dwarf: Node3D`, `controller: CanvasLayer`, etc.) plutôt qu'en sous-classes ou en références typées croisées - évite les dépendances circulaires entre scripts qui se préchargent mutuellement (voir Dwarf*/Action*/DwarfModel3D+builders).
- **Accès dynamique (`get()`/`set()`/`call()`)** : quand une fonction extraite reçoit un nœud générique (`Node3D`, `CanvasLayer`) plutôt que le type exact, elle lit/écrit ses propriétés dynamiquement - un `preload()` typé ne permettrait pas d'éviter la dépendance circulaire, et une lecture de constante (`Script.CONSTANTE`) ne fonctionne qu'à travers un `preload()` réellement typé, jamais via ce type générique.
- **Déterminisme par graine** : tout tirage aléatoire qui doit être reproductible pour une graine donnée passe par `GameRandom.get_rng("nom_flux")`, jamais par le RNG global de Godot (`randf()`, `Array.shuffle()`...).
- **Aucun asset externe pour le contenu procédural** : terrain, végétation, nains et icônes sont entièrement générés par code (formes procédurales, `Image.create`/`set_pixel` pour les icônes) plutôt que chargés depuis des fichiers - un choix initial pour éviter des soucis de rendu rencontrés tôt dans le projet avec des textures externes.

## Portabilité

Le projet cible actuellement Windows/macOS avec clavier + souris. Plusieurs points sont identifiés mais volontairement non traités en l'absence de portage iPad/iPhone planifié : résolution de fenêtre fixe (`project.godot`), contrôles caméra et raccourcis d'action sans équivalent tactile (`CameraRig.gd`, `ActionMenuBar.gd`). Voir les commentaires de ces fichiers pour le détail.

## Suivi du projet

- Planning de sprints/phases : `Forgotten_Caves_Sprints.xlsx` (dossier parent).
- Revue de code (suivi qualité, findings ouverts/corrigés) : dossier `Code Review` (hors de ce dépôt).
