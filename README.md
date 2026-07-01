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
- Angle de vue et rotation : maintenir le clic molette et glisser la souris (horizontal = rotation, vertical = pitch)

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
- [x] Teste dans Godot et confirme que tous les controles fonctionnent

### Notes techniques Sprint 2

- `CameraRig.gd` est un pivot (Node3D) qui porte la camera en enfant : elle tourne autour du pivot (orbite), zoom = distance au pivot
- Utilise `Input.is_physical_key_pressed` / `event.physical_keycode` (position physique de la touche) plutot que le caractere affiche, pour que ZQSD/A/E fonctionnent correctement sur un clavier francais AZERTY
- Le "niveau" actuel deplace juste la hauteur du point vise par la camera ; le rendu en coupe (cacher les niveaux au-dessus) viendra plus tard avec le minage

### A savoir : "Embed Game" dans Godot 4.7

Par defaut, Godot lance le jeu integre dans une fenetre-panneau a l'interieur de l'editeur, avec sa propre barre d'outils qui peut interferer avec les clics/touches. Ce reglage a ete desactive (Godot > Parametres > recherche "jeu" > decocher "Integrer le jeu lors du prochain lancement", puis redemarrer Godot). Si un futur test semble ne recevoir aucune touche/clic, verifier que ce reglage est toujours desactive.

## Sprint 3 — Le premier nain

- [x] Modele provisoire (capsule) representant le nain
- [x] Deplacement automatique entre points aleatoires de la carte (remplace par de vraies taches au Sprint 4)
- [x] Orientation vers la direction de deplacement
- [x] Petit effet de rebond pendant la marche ("animation" sans modele anime)
- [x] Teste dans Godot et confirme

### Notes techniques Sprint 3

- `Dwarf.gd` : capsule qui choisit une case aleatoire, s'y deplace a vitesse constante, tourne progressivement vers sa direction (lerp_angle), et rebondit legerement (sinus) pendant le mouvement
- Le deplacement aleatoire est temporaire : au Sprint 4, l'utilisateur designera les destinations/taches a la place

## Sprint 4 — Designer une tache (miner / couper)

- [x] Menu d'actions (boutons "Miner" et "Couper" en bas a gauche de l'ecran)
- [x] Clic sur un bloc du terrain (mode Miner) ou sur un arbre (mode Couper) pour designer une tache
- [x] Le nain rejoint la tache en priorite (avant de reprendre son errance aleatoire), effectue une courte animation de travail, puis le bloc/arbre disparait
- [x] Quelques arbres de test places au hasard sur la carte (pas encore lies au climat/vegetation du brief)
- [x] Teste dans Godot et confirme que Miner et Couper fonctionnent tous les deux
- [x] Compteur "Blocs mines / Arbres coupes" ajoute pour confirmer visuellement (le mine etait difficile a voir a l'oeil nu)
- [x] Bonus : clic molette + glisser pour changer l'angle de vue et tourner la camera

### A tester

1. Clique sur le bouton **Miner**, puis clique sur un bloc de terrain visible : le nain devrait s'y rendre et le bloc disparaitre apres ~1.5s
2. Clique sur le bouton **Couper**, puis clique pres d'un arbre (petits arbres marron/vert sur la carte) : le nain devrait s'y rendre et l'arbre disparaitre
3. Sans mode actif, cliquer ne fait rien (comportement normal)
4. Entre deux taches, le nain reprend son errance aleatoire (Sprint 3)

### Notes techniques Sprint 4

- `TaskQueue.gd` : simple file d'attente (liste) de taches, alimentee par `ActionController.gd` et consommee par `Dwarf.gd`
- `ActionController.gd` : gere les 2 boutons (mode Miner/Couper) et convertit un clic ecran en position 3D via une intersection avec le plan horizontal du niveau du sol (pas de vraie physique/collision pour l'instant, suffisant pour un terrain plat)
- `Forest.gd` : place des arbres simples (tronc + feuillage, groupe Godot "trees") a des positions aleatoires
- Simplification actuelle : le minage ne cible que le bloc le plus haut de la colonne cliquee, et le nain garde une hauteur de marche fixe (pas encore de gestion du relief/creux crees par le minage) — sera affine avec le systeme de mines complet

## Sprint 5 — Recolte et inventaire

- [x] Miner un bloc de terre donne "Terre", miner un bloc de pierre donne "Pierre", couper un arbre donne "Bois"
- [x] Petit item colore apparait au sol puis "saute" et disparait (effet de recolte)
- [x] Inventaire global affiche en haut de l'ecran (remplace le compteur du Sprint 4)
- [x] Teste dans Godot et confirme que Bois/Pierre/Terre augmentent correctement

### Notes techniques Sprint 5

- `Inventory.gd` : simple dictionnaire {ressource: quantite}, accessible via %Inventory
- `Dwarf.gd` : a la fin d'une tache, appelle `_collect_resource()` qui incremente l'inventaire et declenche l'effet visuel (`_spawn_loot_item`, anime avec un Tween : monte + retrecit puis disparait)
- Pas encore de transport vers un entrepot (Sprint dedie au stockage plus tard) : la ressource va directement dans l'inventaire global des la recolte

## Sprint 6 — File de taches et priorites

- [x] Le nain choisit la tache la plus proche de lui (pas juste la premiere designee)
- [x] Nombre de taches en attente affiche a l'ecran
- [x] Teste : designe plusieurs taches d'un coup (miner + couper a differents endroits) et verifie que le nain va d'abord au plus proche

### Notes techniques Sprint 6

- `TaskQueue.pop_nearest_task(position)` remplace `pop_task()` : parcourt la liste et retire celle dont la distance a `position` est minimale
- Annulation d'une tache en attente : pas encore implementee (prevu si besoin plus tard)

## Sprint 7 — Construction simple

- [x] Deux boutons "Mur Bois" et "Mur Pierre" en plus de Miner/Couper
- [x] Construction possible n'importe ou en hauteur : le mur s'empile sur le sommet actuel de la colonne cliquee (pas besoin d'un trou mine au prealable)
- [x] Cout : 1 unite de ressource (bois ou pierre) par mur construit, deduite de l'inventaire au moment de la construction
- [x] Si pas assez de ressource au moment ou le nain arrive, la construction est annulee (message dans la console)
- [x] Teste : construis quelques murs en bois et en pierre, verifie que l'inventaire diminue et qu'on peut empiler plusieurs murs au meme endroit (tour)

### Notes techniques Sprint 7

- `VoxelWorld.BUILD_CEILING` (HEIGHT + 10) definit la limite de hauteur constructible
- `build_block(x, z, material)` empile toujours au sommet actuel de la colonne (`get_top_block_y + 1`), que ce sommet soit le sol naturel, un trou mine, ou un mur deja construit
- La ressource est deduite seulement a la fin de la construction (pas a la designation), pour rester coherent avec le reste des taches ; si plusieurs constructions sont en attente et que le stock est epuise entre-temps, celles en trop echouent silencieusement (log console)

## Sprint 8 — Besoins de base (faim / energie)

- [x] Jauges Faim et Energie affichees en haut a gauche, qui diminuent avec le temps
- [x] Quand la faim est critique (<20), le nain interrompt sa tache/errance et va manger au buisson a baies le plus proche
- [x] Quand l'energie est critique (<15), le nain s'arrete et se repose sur place jusqu'a 70 d'energie avant de reprendre
- [x] La tache en cours (si il y en avait une) est remise dans la file au lieu d'etre perdue
- [x] Quelques buissons a baies (3 baies chacun) sur la carte, ils disparaissent une fois epuises
- [x] Teste : laisse le jeu tourner ~1 minute sans rien faire, verifie que le nain va se nourrir/reposer tout seul quand les jauges baissent
- [x] Ajustements : jauges accelerees pour tester plus vite, animations dormir/manger, fenetre 1600x900, camera plus zoomee au demarrage

### Notes techniques Sprint 8

- Vitesse de baisse : faim -8/s, energie -5/s (critique en 10-15s, pense pour tester rapidement)
- Animation "dormir" : le nain s'incline a 90 degres (couche) avec une legere respiration (oscillation) pendant le repos
- Animation "manger" : petit hochement de tete pendant ~1.2s a l'arrivee au buisson, puis la baie est consommee
- `BerryBush.gd` : chaque buisson a 3 baies ; `eat()` en retire une et renvoie true/false ; le buisson disparait quand il est vide
- Pas de mecanique de "mort de faim" pour l'instant si aucun buisson n'est disponible (le nain continue simplement son activite) ; a ajouter plus tard avec les points de vie

## Sprint 9 — Interface minimale

- [x] Icone du nain en haut a droite de l'ecran, cliquable
- [x] Fiche de personnage (ouverte/fermee au clic sur l'icone) : jauge de Points de Vie factice (100/100), Faim, Energie, et tache en cours
- [x] Icones colorees (formes simples) sur les 4 boutons d'action : Miner (gris), Couper (vert), Mur Bois (marron), Mur Pierre (gris clair)
- [x] Teste dans Godot et confirme

### A tester

1. Clique sur l'icone ronde du nain (en haut a droite) : une fiche doit s'ouvrir avec PV/Faim/Energie/tache en cours
2. Reclique sur l'icone : la fiche doit se fermer
3. Verifie que les jauges Faim/Energie de la fiche bougent en meme temps que celles deja affichees en bas a gauche
4. Verifie que les 4 boutons d'action (Miner/Couper/Mur Bois/Mur Pierre) affichent maintenant un petit carre colore en plus du texte

### Notes techniques Sprint 9

- `CharacterSheetUI.gd` : genere une icone circulaire via `Image`/`set_pixel` (pas besoin d'asset externe), affiche/masque un `Panel` au clic ; les jauges Faim/Energie sont lues directement depuis `%Dwarf` (source unique de verite, pas de duplication d'etat)
- La jauge de PV est factice pour l'instant (toujours 100/100) : le systeme de points de vie reel n'existe pas encore
- `ActionController._setup_icons()` genere 4 petites icones carrees unies (une couleur par action) via la meme technique `Image`/`set_pixel`

## Sprint 9bis — Refonte du menu de construction

- [x] Le bouton "Construire" remplace "Mur Bois"/"Mur Pierre" : il ouvre un sous-menu avec 3 boutons materiau (Bois / Pierre / Terre)
- [x] Materiau "Terre" desormais constructible (en plus de Bois et Pierre)
- [x] Selection de plusieurs cases d'un coup par cliquer-glisser (ligne ou rectangle), au lieu d'un clic = un mur
- [x] Mur "fantome" semi-transparent affiche a l'emplacement prevu pendant la selection (clair) puis pendant l'attente de construction (plus visible), jusqu'a ce que le nain ait fini (pose ou echec)
- [x] Teste dans Godot et confirme

### A tester

1. Clique sur **Construire** : un sous-menu Bois / Pierre / Terre doit apparaitre au-dessus des boutons principaux
2. Choisis un materiau (ex: Pierre), puis clique-glisse sur plusieurs cases du terrain : des cubes semi-transparents gris doivent suivre la selection en temps reel
3. Relache le clic : les cases selectionnees passent en fantome plus marque (en attente), et des taches de construction sont ajoutees (regarde le compteur "Taches en attente")
4. Le nain rejoint chaque case l'une apres l'autre ; a chaque mur pose (ou echoue faute de ressource), le fantome correspondant disparait
5. Verifie que "Terre" fonctionne aussi comme materiau de construction (en plus de Bois/Pierre)
6. Verifie qu'on ne peut pas re-selectionner une case deja en attente de construction (elle n'apparait pas en fantome une seconde fois)

### Notes techniques Sprint 9bis

- `ActionController.gd` : le mode `CONSTRUIRE` ouvre `MaterialBox` (3 boutons), le materiau choisi est memorise dans `selected_material` ; le cliquer-glisser est gere via `_on_left_press`/`_update_drag`/`_on_left_release` sur `_unhandled_input`, independant des modes Miner/Couper qui restent en clic simple
- Chaque tache de construction recoit un id unique (`TaskQueue.next_task_id`) ; `Dwarf.gd` emet le signal `build_task_finished(task_id, bx, bz)` a la fin de chaque construction (succes ou echec), ce qui permet a `ActionController` de retirer le bon fantome sans dependre du rendu du terrain
- Les fantomes sont des `MeshInstance3D` semi-transparents (materiau `TRANSPARENCY_ALPHA`) ajoutes directement dans la scene 3D (pas dans le CanvasLayer, qui est reserve a l'UI 2D)
- `VoxelWorld.build_block()` accepte maintenant aussi `"terre"` (reutilise `BlockType.DIRT` : miner un mur de terre redonne bien de la "terre")
- `pending_columns` empeche de selectionner deux fois la meme colonne tant que sa construction n'est pas resolue (evite les taches en double/conflits d'empilement)

## Sprint 10 — Validation MVP

- [x] Session de test de bout en bout (camera, minage, coupe, file de taches, construction multi-cases, faim/energie, fiche personnage) : boucle complete confirmee fonctionnelle
- [x] Correction : l'affichage du niveau de profondeur (molette) partait de 0 en bas au lieu de 0 en surface, ce qui donnait l'impression de ne pas pouvoir descendre plus bas alors que toute la carte etait deja accessible — l'affichage indique maintenant 0 = surface et les niveaux negatifs = sous-sol
- [x] Amelioration visuelle : les parois d'un trou mine (ou d'un mur construit) sont maintenant assombries par rapport aux faces du dessus, pour bien voir la difference entre un creux et une simple case non minee
- [x] Teste dans Godot et confirme — MVP valide

### A tester

1. Mine plusieurs blocs a la suite au meme endroit (pour creuser un vrai trou) : les parois du trou doivent apparaitre nettement plus sombres que la surface environnante
2. Verifie que la molette affiche bien "Niveau : 0 (surface)" au demarrage, et des valeurs negatives en descendant
3. Reprends le scenario de test complet du Sprint 10 (voir historique) : tout doit s'enchainer sans blocage

### Notes techniques Sprint 10

- `CameraRig._update_label()` : conversion d'affichage uniquement (`current_level - (grid_height - 1)`), aucun changement sur la logique de deplacement/clamp de la camera, qui parcourait deja toute la hauteur de la carte
- `VoxelWorld.rebuild_mesh()` / `_bucket_for()` : le choix du materiau (bucket) depend maintenant aussi de la direction de la face (`dir`) et non plus seulement du type de bloc ; les faces du dessus gardent le damier clair/fonce existant, toutes les autres (parois, dessous) passent sur une variante assombrie (`_darken()`, x0.55) — effet d'ombrage simple, sans veritable eclairage dynamique
- Le MVP (Sprints 0 a 10) est valide : place a la Phase 2 (backlog) quand tu voudras continuer
