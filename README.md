# Forgotten Caves

Jeu de gestion de colonie de nains en 3D par blocs (voxels), inspiré de Dwarf Fortress / RimWorld.

## Stack technique

- Moteur : Godot 4.3+ (GDScript)
- Rendu : Forward+ (3D)
- Plateformes cibles : Windows, macOS

## Structure du projet

Depuis le Sprint 22, `scripts/` est range par categorie plutot qu'a plat (voir la section Sprint 22 plus bas pour le detail complet) :

```
ForgottenCavesGame/
├── project.godot        # Fichier de configuration du projet
├── scenes/
│   └── Main.tscn         # Scene de depart : camera + lumiere + grille de blocs + tous les acteurs
├── scripts/
│   ├── data/             # Tables de donnees statiques, editables (materiaux, climats, creatures)
│   ├── entites/           # Scripts de comportement des acteurs vivants (Dwarf, Forest, BerryBushes...)
│   ├── monde/             # Terrain et decor (VoxelWorld, GroundDecoration)
│   ├── ui/                # Interface (CharacterSheetUI)
│   └── systemes/          # Logique globale (ActionController, TaskQueue, Inventory, CameraRig)
└── assets/               # Modeles, textures, sons...
```

(le fichier `scripts/systemes/Main.gd` du Sprint 0 n'est plus utilise, remplace par `CameraRig.gd` — tu peux le supprimer toi-meme si tu veux faire le menage)

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

# Phase 2 — Colonie complete

## Sprint 11 — Plusieurs nains

- [x] La colonie compte maintenant 3 nains simultanes (au lieu d'1 seul), chacun avec un nom (Nain 1/2/3)
- [x] Chaque nain libre prend la tache la plus proche de LUI dans la file commune (pas de coordination entre eux pour l'instant, mais pas de doublon possible non plus : des qu'un nain prend une tache elle sort de la file)
- [x] Les 3 nains partagent le meme inventaire et la meme file de taches, comme avant
- [x] Fiche personnage : une icone par nain (empilees en haut a droite), cliquer sur une icone ouvre/ferme la fiche de CE nain (une seule fiche visible a la fois)
- [x] Retrait de l'ancien affichage fixe Faim/Energie en bas a gauche (ne pouvait montrer qu'un seul nain) : desormais uniquement visible via la fiche personnage de chaque nain
- [x] Teste dans Godot et confirme

### A tester

1. Verifie qu'il y a bien 3 nains visibles sur la carte au demarrage (ils partent d'une position proche puis se dispersent en errant)
2. Verifie qu'il y a bien 3 icones empilees en haut a droite ; clique sur chacune : la fiche du bon nain doit s'ouvrir (nom, Faim/Energie/tache differents pour chacun)
3. Designe plusieurs taches (miner/couper/construire) d'un coup : verifie que les 3 nains se repartissent le travail (chacun va vers une tache differente, pas tous vers la meme)
4. Verifie que faim/energie/repos fonctionnent independamment pour chaque nain (l'un peut se reposer pendant que les autres travaillent)
5. Verifie que l'inventaire (Bois/Pierre/Terre) continue de s'incrementer correctement, peu importe quel nain recolte

### Notes techniques Sprint 11

- Les 3 nains sont des noeuds independants (`Colony/Dwarf1`, `Dwarf2`, `Dwarf3` dans `Main.tscn`), tous avec le script `Dwarf.gd`, differencies par la propriete exportee `dwarf_name`
- Comme Godot execute les scripts sequentiellement (pas de vrai parallelisme), un nain qui pioche une tache via `TaskQueue.pop_nearest_task()` la retire immediatement de la file : deux nains ne peuvent donc jamais se retrouver sur la meme tache, meme sans code de coordination explicite
- `Dwarf.gd` n'a plus de reference unique `%Dwarf` : il rejoint le groupe Godot `"dwarves"` a son `_ready()`, ce qui permet a `ActionController.gd` et `CharacterSheetUI.gd` de retrouver tous les nains dynamiquement (fonctionne meme si le nombre de nains change plus tard)
- `CharacterSheetUI.gd` genere maintenant ses icones/fiches par code (une par nain trouve dans le groupe), au lieu d'avoir des noeuds fixes dans la scene — ca s'adapte automatiquement a n'importe quel nombre de nains
- Un leger decalage aleatoire est applique a la position de depart de chaque nain pour eviter qu'ils ne demarrent parfaitement superposes

## Sprint 12 — Caracteristiques de base

- [x] Chaque nain recoit 6 caracteristiques generees aleatoirement a sa creation : Force, Agilite, Constitution, Intelligence, Beaute (1-10) et Bonheur (40-80%)
- [x] Affichees dans la fiche personnage (sous le nom), en plus de PV/Faim/Energie/tache en cours deja presents
- [x] Purement informatif pour l'instant : aucun effet sur la vitesse de travail, de deplacement, etc. (viendra avec les competences dans un sprint dedie)
- [x] Teste dans Godot et confirme

### A tester

1. Ouvre la fiche de chaque nain (icones en haut a droite) : verifie que Force/Agilite/Constitution/Intelligence/Beaute/Bonheur s'affichent, avec des valeurs differentes d'un nain a l'autre
2. Verifie que le reste de la fiche (PV, Faim, Energie, tache en cours) fonctionne toujours comme avant
3. Verifie que le jeu se comporte normalement par ailleurs (les stats n'ont volontairement aucun effet pour l'instant)

### Notes techniques Sprint 12

- `Dwarf._generate_characteristics()` est appelee une seule fois, au `_ready()` de chaque nain (avant `_pick_new_target()`), donc les valeurs restent fixes pour toute la partie
- Les stats sont de simples `int` sur le nain (pas de resource ou systeme dedie) : suffisant tant qu'elles restent purement informatives ; un vrai systeme (avec effets, evolution, etc.) sera introduit avec les competences
- `CharacterSheetUI.gd` : les stats sont ecrites une seule fois a la creation de la fiche (`_create_entry`), pas rafraichies en `_process` comme Faim/Energie, puisqu'elles ne changent pas pendant la partie pour l'instant

## Sprint 13 — Direction artistique "BD"

- [x] Ciel + ambiance : ajout d'un `WorldEnvironment` (ciel degrade bleu, brouillard leger) au lieu du fond noir/gris par defaut
- [x] Palette du terrain (terre/pierre/murs) rendue plus vive et saturee, dans l'esprit BD/cartoon
- [x] Apparence des nains entierement generee par code (pas d'assets externes) : contour noir façon dessin anime, tunique coloree (rouge/bleu/vert selon le nain), petit chapeau pointu et une barbe
- [x] Teste dans Godot et confirme

### A tester

1. Verifie qu'un ciel degrade (bleu en haut, plus clair vers l'horizon) est visible en arriere-plan, avec un leger brouillard au loin
2. Verifie que chaque nain a maintenant un contour noir, une tunique coloree differente (Nain 1 = rouge, Nain 2 = bleu, Nain 3 = vert), un chapeau et une barbe
3. Verifie que les couleurs du terrain (terre/pierre) sont plus vives qu'avant, et que la difference clair/fonce (damier) et parois sombres (trous) du Sprint 10 sont toujours bien visibles
4. Verifie que rien d'autre n'a change de comportement (deplacement, minage, construction, etc.)

### Notes techniques Sprint 13

- `WorldEnvironment` + `ProceduralSkyMaterial` (ciel) + leger `fog` : purement de l'ambiance, n'affecte pas le shading des blocs (toujours en `UNSHADED`, pour eviter de refaire apparaitre les anciens problemes d'eclairage deja rencontres — voir note Sprint 1/2)
- Couleurs de `VoxelWorld.gd` retouchees (plus saturees), meme mecanique de damier clair/fonce et parois assombries qu'avant (Sprint 10), rien de casse
- `Dwarf._build_appearance()` (appelee au `_ready()`) genere par code : un contour noir (copie du mesh de la capsule, legerement agrandie, qui n'affiche que ses faces arrieres via `CULL_FRONT` — technique classique de contour "toon"), une tunique (`CylinderMesh` colore par `tunic_color`, propriete exportee differente par nain dans `Main.tscn`), un chapeau (`CylinderMesh` conique) et une barbe (`SphereMesh` aplati)
- Simplification assumee : le contour noir ne couvre que le corps (capsule), pas le chapeau/la tunique/la barbe — suffisant pour bien lire la silhouette sans complexifier davantage

## Sprint 14 — Silhouette de nain articulee

- [x] Remplacement de la capsule unique par un corps en plusieurs parties : tete, torse (= tunique coloree), 2 bras, 2 jambes, assembles a partir de formes simples
- [x] Jambes et bras se balancent en opposition de phase pendant la marche (marche naturelle), et se remettent en position neutre a l'arret (travail, repos, repas)
- [x] Chapeau et barbe repositionnes sur la nouvelle silhouette ; contour noir "BD" applique au torse et a la tete
- [x] Tout le reste (repos allonge, animation de repas, tremblement pendant le travail) fonctionne toujours, adapte a la nouvelle structure
- [ ] A tester dans Godot

### A tester

1. Regarde un nain marcher : les jambes et les bras doivent se balancer alternativement (comme une vraie marche), pas rester figes
2. Quand un nain arrive a destination, commence a travailler, mange ou se repose : les bras/jambes doivent revenir en position neutre (pas rester bloques en plein balancement)
3. Verifie que le repos allonge fonctionne toujours normalement (le nain se couche sur le cote et ne traverse pas le sol)
4. Verifie que la silhouette est bien lisible : tete, torse colore, bras, jambes, chapeau, barbe, contour noir

### Notes techniques Sprint 14

- Le noeud `$MeshInstance3D` (une capsule) est remplace par `$Body`, un simple conteneur `Node3D` vide dans `Main.tscn` ; toute la silhouette (tete/torse/bras/jambes/chapeau/barbe) est construite dedans par code dans `Dwarf._build_appearance()`
- Bras et jambes sont chacun un pivot (`Node3D`) place au niveau de l'articulation (epaule/hanche), avec le membre (une `CapsuleMesh`) accroche en dessous : faire tourner le pivot fait bouger le membre entier de façon naturelle, comme un vrai bras/jambe articule
- `_animate_walk_cycle()` (appelee depuis `_move_toward`, donc pendant toute marche) fait osciller les 4 pivots en opposition de phase (jambe gauche + bras droit ensemble, jambe droite + bras gauche ensemble), en reutilisant le meme `bob_time` que le rebond de marche existant
- Les animations globales existantes (inclinaison pendant le travail, hochement de tete pour manger, bascule a 90° pour le repos) continuent de s'appliquer a `body` dans son ensemble, comme avant avec la capsule — simplification assumee : pas de tete qui hoche independamment du reste du corps
- Le contour noir façon BD (Sprint 13) est desormais applique separement au torse et a la tete (les deux plus grandes masses), plutot qu'a une capsule unique

## Sprint 15 — Sprite 2D illustre (remplace la silhouette procedurale)

- [x] La silhouette articulee (Sprint 13/14, generee par code) est remplacee par une vraie illustration 2D du nain (fournie par l'utilisateur via Canva), affichee en `Sprite3D`
- [x] Fond de l'image retire et petit logo/texte parasite efface (traitement d'image fait cote serveur, pas dans Godot)
- [x] Le sprite est en mode "billboard" (fait toujours face a la camera), essentiel puisque la camera peut tourner librement autour de la scene
- [x] Animations adaptees : comme un sprite en billboard ignore la rotation du noeud (limitation confirmee de Godot), les anciennes animations en rotation (inclinaison travail, hochement tete, bascule 90° repos) sont remplacees par des animations en position/echelle (tremblement horizontal au travail, petit rebond rapide en mangeant, tassement vertical pour le repos)
- [x] Les 3 nains utilisent pour l'instant la meme image (les couleurs de tunique differentes du Sprint 13 n'existent plus)
- [x] Teste et confirme par l'utilisateur (deuxieme image fournie, un nain arme plus sobre — la premiere, un peu trop chargee/complexe, a ete ecartee)

### A tester

1. Verifie que le nain s'affiche bien comme une image (pas une forme geometrique), sans fond blanc/violet ni texte parasite autour
2. Tourne la camera (Q/E, clic molette + glisser) : le nain doit toujours faire face a la camera quel que soit l'angle
3. Regarde-le marcher, travailler, manger, se reposer : verifie que chaque etat a un mouvement visible (rebond de marche, tremblement au travail, petit rebond en mangeant, tassement au repos), meme si ce n'est plus une vraie posture articulee
4. Les 3 nains doivent pour l'instant se ressembler (meme image) : normal, les variantes de couleur viendront dans un sprint suivant

### Notes techniques Sprint 15

- Image source traitee avec Python/Pillow (hors Godot) : fond blanc + fond lavande retires par seuil de saturation/luminosite (HSV), petit logo texte efface, image recadree autour du personnage ; resultat enregistre dans `assets/nain.png`
- `Sprite3D.billboard = BILLBOARD_FIXED_Y` : le sprite reste toujours vertical et pivote uniquement autour de l'axe Y pour faire face a la camera (plutot que `BILLBOARD_ENABLED`, qui basculerait aussi avec l'inclinaison de la camera, moins naturel pour un personnage debout)
- `Sprite3D.alpha_cut = ALPHA_CUT_DISCARD` : evite les problemes de tri de transparence avec le terrain (le pixel est soit oppaque soit invisible, pas de degrade)
- Important : **la rotation d'un noeud n'a aucun effet visuel en mode billboard** (confirme par la doc/communaute Godot) — toutes les anciennes animations bases sur `rotation.x/z` ont ete remplacees par des animations de `position`/`scale`, qui elles restent visibles
- `sprite_texture` est une propriete exportee sur `Dwarf.gd` (une image par instance) : les 3 nains pointent pour l'instant vers la meme image `res://assets/nain.png`, mais la structure est prete pour donner une image differente a chacun plus tard
- Le nain ne s'oriente plus visuellement vers sa direction de deplacement (impossible avec un billboard qui fait toujours face a la camera) ; la rotation Y du noeud racine est conservee dans le code mais n'a plus d'effet visuel direct

## Sprint 15bis — Volume sur le sprite plat (relief + profondeur)

- [x] Relief par eclairage : une normal map est generee automatiquement a partir de l'image du nain (relief de luminance, flou leger pour eviter le bruit pixel), le sprite principal passe en `shaded = true` et recoit cette normal map (`assets/nain_normal.png`) — la lumiere directionnelle de la scene cree maintenant des zones d'ombre/lumiere sur le personnage
- [x] Silhouette de profondeur : une copie du sprite, teintee plus sombre et legerement agrandie (6%), est placee juste derriere en profondeur (Z local) — elle depasse un peu sur les bords et donne une impression d'epaisseur/de contour
- [x] Correction : ombre du nain qui apparaissait de façon incoherente/instable selon l'angle de camera — desactivee (voir notes techniques)
- [x] Correction : l'image source contenait une ombre ovale opaque au sol sous les pieds (heritee du rendu Canva) — supprimee de l'image, qui a ete recadree en consequence
- [x] Teste et confirme par l'utilisateur ("ok ça marche")

### A tester

1. Regarde le nain sous l'angle de la lumiere (tourne la camera) : le corps ne doit plus etre un aplat totalement uniforme, on doit deviner un leger volume (zones plus claires/plus sombres selon l'orientation)
2. Verifie qu'on voit un fin lisere sombre depasser sur les bords du personnage (silhouette de profondeur) sans que ça ne fasse un contour trop epais ou disgracieux
3. Verifie que les animations (marche, travail, repas, repos) fonctionnent toujours normalement et que les deux sprites (principal + profondeur) restent bien superposes/synchronises dans tous les etats
4. Verifie qu'il n'y a plus d'ombre projetee visible sous/autour du nain (ni ombre dynamique de la lumiere, ni ovale gris fixe sous les pieds)
5. Verifie que les pieds touchent bien le sol (l'image a ete recadree, le nain ne doit pas sembler flotter ni s'enfoncer)

### Notes techniques Sprint 15bis

- Normal map generee en Python/Pillow+numpy (hors Godot) : luminance de l'image legerement floutee (`GaussianBlur` rayon 2) utilisee comme "hauteur", gradient calcule par difference centree, converti en normale tangent-space (convention Godot/OpenGL, canal vert vers le haut de l'image) ; alpha copie depuis l'image source pour que la transparence reste identique
- Correction : `Sprite3D` n'expose pas de propriete `normal_map` directement (limitation connue de Godot 4, confirmee par la doc/communaute) — la normal map est appliquee via un `material_override` (StandardMaterial3D avec `normal_enabled`/`normal_texture`, decoupe alpha et billboard reproduits manuellement) applique uniquement au sprite principal du nain ; le terrain (`VoxelWorld`) reste volontairement en `SHADING_MODE_UNSHADED` (aplat colore), ce n'est pas incoherent d'avoir un mode de rendu different pour le personnage
- La silhouette de profondeur est un second `Sprite3D` (meme texture, `modulate` sombre, `pixel_size` x1.06, `position.z = -0.05`), ajoute en enfant de `Body` avant le sprite principal : comme les deux sont en billboard `FIXED_Y`, ils pivotent ensemble et le decalage en Z reste coherent sous tous les angles de camera
- Reglages actuels (`DEPTH_OFFSET`, `DEPTH_SCALE`, `DEPTH_TINT` dans `Dwarf.gd`) sont un premier essai, faciles a ajuster si l'effet est trop fort/trop faible une fois vu dans Godot
- Correction "ombre aleatoire" : un billboard qui pivote pour faire face a la camera se reoriente aussi pendant le rendu de la carte d'ombre (ce passage "regarde" depuis la lumiere, pas depuis la camera), ce qui produit une silhouette d'ombre incoherente qui semble sauter selon l'angle — les deux sprites du nain ont `cast_shadow = SHADOW_CASTING_SETTING_OFF`, ils ne projettent donc plus d'ombre du tout (le reste de la scene, blocs et arbres, continue d'en projeter normalement)
- Correction "ovale sous les pieds" : l'image Canva source integrait une ombre au sol dessinee en dur (pixels opaques gris clair, pas de degrade de transparence) ; detectee par seuil de saturation/luminosite (HSV) restreint a la bande basse de l'image, rendue transparente, puis l'image recadree a nouveau au plus juste autour du personnage (les pieds touchent desormais le bord bas du fichier) ; la normal map a ete regeneree a partir de cette version finale

## Sprint 16 — Personnalisation par region (cheveux, barbe, vetements, armure)

- [x] `assets/nain_mask.png` : masque de couleurs reperes peint (semi-manuellement, par polygones) par-dessus `nain.png` ; une couleur pure identifie chaque region recolorable (rouge = cheveux, vert = barbe, bleu = vetements, jaune = armure), le reste (peau, visage, mains) n'est marque par aucune region et garde sa couleur d'origine
- [x] `shaders/dwarf_recolor.gdshader` : shader custom applique au sprite principal du nain, qui recolore chaque region a partir de sa luminance d'origine (donc l'ombrage/le relief du dessin reste visible) multipliee par une couleur cible
- [x] 4 nouvelles proprietes exportees sur `Dwarf.gd` : `hair_color`, `beard_color`, `clothing_color`, `armor_color` — reglables par nain, independamment les unes des autres
- [x] Les 3 nains de `Main.tscn` ont chacun une combinaison de couleurs differente (a titre de demonstration) : Nain 1 roux/cuir, Nain 2 blond/bleu, Nain 3 brun fonce/vert
- [x] Teste et confirme par l'utilisateur ("ok ça marche")

### A tester

1. Verifie que les 3 nains sont maintenant visuellement distincts (couleur de cheveux, barbe, vetements)
2. Verifie qu'il n'y a pas de zones mal recolorees : peau/visage/mains qui changeraient de couleur par erreur, ou au contraire des bouts de cheveux/barbe/vetements qui resteraient dans la couleur d'origine (le masque a ete peint a la main, les bords sont approximatifs)
3. Verifie que le relief (normal map, Sprint 15bis) fonctionne toujours : le nain ne doit pas etre revenu a un aplat totalement plat
4. Verifie que le sprite continue de bien faire face a la camera sous tous les angles (le billboard automatique de Sprite3D a du etre refait a la main pour ce sprint, voir notes techniques)
5. Verifie particulierement l'animation de repos (le nain "s'aplatit" pour dormir) : comme le corps est deforme de façon non uniforme a ce moment-la, il pourrait potentiellement y avoir un leger effet de biais/deformation sur le sprite recolore (a verifier, correction possible si visible)

### Notes techniques Sprint 16

- Le masque a ete peint en definissant des polygones a la main par inspection visuelle de l'image (pas de segmentation automatique par couleur : cheveux, barbe, vetements et armure sont tous dans la meme famille de teintes brun/orange sur l'image source, donc indissociables par un simple seuil de couleur, verifie par echantillonnage avant de s'y lancer) ; la zone "vetements" est peinte en un seul grand rectangle, puis l'armure/les mains sont peintes par-dessus (polygones plus precis), ce qui evite d'avoir a tracer le contour exact du vetement
- Formule de recolor : `couleur_finale = teinte_cible * luminance_originale` (sans "boost" de luminance) — teste visuellement avec plusieurs facteurs (x1, x1.3, x1.6, x2) : un facteur superieur a 1 delave les teintes vers le blanc des qu'une zone contient beaucoup de blanc/clair dans le dessin d'origine (typiquement la barbe, dessinee tres claire), ce qui rendait les teintes sombres illisibles
- Le shader (`ShaderMaterial` + `material_override`) remplace entierement le materiau que Sprite3D genererait automatiquement ; consequence : le billboard et la decoupe alpha automatiques de Sprite3D sont perdus. La decoupe alpha est refaite dans le shader (`ALPHA_SCISSOR_THRESHOLD`), et le billboard est refait a la main cote script (`Dwarf._face_camera()`, appelee chaque frame), car les shaders spatiaux Godot n'ont pas de `render_mode` billboard integre (verifie aupres de la documentation officielle) — seul `BaseMaterial3D` (donc `StandardMaterial3D`) sait le faire nativement
- La silhouette de profondeur (Sprint 15bis) n'est pas recoloree (elle garde l'image et la teinte sombre d'origine) : elle sert uniquement de liseré/ombre de profondeur, sa teinte n'est presque pas visible, donc pas utile de la faire passer par le meme shader
- Reglages actuels des 3 nains de demonstration sont juste des exemples ; un vrai systeme de generation (aleatoire ou choisi par le joueur) reste a construire plus tard

## Sprint 17 — Accessoires d'action (dormir/manger/travailler)

- [x] Outil (pioche/hache/marteau) : forme 3D simple (manche + tete, generee par code, sans texture), apparait pres de la main et se balance pendant le travail ; le type d'outil correspond au type de tache (miner -> pioche, couper -> hache, construire -> marteau)
- [x] "Z z z" (`Label3D`) flottant au-dessus de la tete pendant le repos, avec un leger mouvement de flottement
- [x] Petite baie qui s'approche de la bouche en rythme avec le hochement de tete pendant le repas
- [x] Teste et confirme par l'utilisateur ("ok ça marche")

### A tester

1. Lance une tache de minage : verifie qu'une pioche apparait pres de la main et se balance
2. Lance une tache de coupe de bois : verifie que c'est une hache (pas une pioche) qui apparait
3. Lance une construction : verifie que c'est un marteau
4. Verifie que l'outil disparait bien une fois la tache terminee (pas d'outil qui reste affiche en marchant)
5. Laisse un nain s'endormir (energie critique) : verifie le "Z z z" au-dessus de la tete, qui doit disparaitre au reveil
6. Laisse un nain manger : verifie la petite baie qui s'approche de la bouche en rythme avec le hochement de tete

### Notes techniques Sprint 17

- Aucun nouvel art du personnage : les outils sont des primitives 3D (deux `BoxMesh`, manche + tete) avec des materiaux non eclaires (`SHADING_MODE_UNSHADED`), pas des sprites illustres — coherent avec l'objectif "accessoires rapides" plutot que reprendre l'art
- Contrairement au personnage (Sprite3D billboard), les outils sont de vrais objets 3D : ils ne pivotent pas pour faire face a la camera, donc leur orientation visuelle varie legerement selon l'angle de vue (a verifier si ca choque une fois vu dans Godot ; facile a corriger en les rendant billboard aussi si besoin)
- Le "Z z z" utilise `Label3D` avec son propre `billboard = BILLBOARD_ENABLED` natif : contrairement au sprite du nain (Sprint 16), `Label3D` n'a pas besoin de `material_override` pour son usage ici, donc pas de probleme de billboard a gerer a la main pour lui
- Reglages de position (hauteur de la bouche, position de l'outil pres de la main) sont approximatifs, bases sur des reperes visuels de l'image ; a ajuster si mal place une fois vu dans Godot

## Sprint 18 — Competences (Minage, Bucheronnage, Construction)

- [x] `scripts/SkillDefinitions.gd` : table centrale des competences (id, nom, tache liee), pensee pour etre facile a etendre (ajouter une ligne = ajouter une competence, y compris sans tache liee pour l'instant, ex. Agriculture/Combat en exemple commente)
- [x] Chaque nain recoit un niveau de depart aleatoire par competence, reparti a "budget" constant (total = nb de competences x 5) : un nain fort dans une competence l'est un peu moins dans les autres, plutot que d'etre bon partout
- [x] Chaque tache terminee du bon type donne de l'xp a la competence correspondante ; l'xp necessaire augmente a chaque niveau
- [x] Effet gameplay : le niveau reduit la duree de travail (jusqu'a -60% a haut niveau, plafonne) et augmente la chance d'obtenir une ressource bonus a la recolte (minage/coupe, jusqu'a 60% de chance a haut niveau)
- [x] Fiche personnage : affiche les competences et leur niveau/xp, rafraichi en continu (contrairement aux caracteristiques du Sprint 12, qui sont figees a la creation)
- [x] Teste et confirme par l'utilisateur ("ok ça marche")

### A tester

1. Ouvre la fiche d'un nain : verifie que les 3 competences (Minage, Bucheronnage, Construction) s'affichent avec un niveau de depart different d'un nain a l'autre
2. Fais miner/couper/construire un nain plusieurs fois de suite : verifie que le niveau de la competence correspondante augmente (xp affichee qui progresse, niveau qui monte)
3. Verifie que la duree des taches semble diminuer legerement a mesure que le niveau augmente (plus visible apres plusieurs niveaux)
4. Recolte plusieurs fois (minage/coupe) : verifie qu'on obtient parfois 2 ressources au lieu d'une (log dans la console) — plus frequent si le niveau de competence est deja eleve au depart

### Notes techniques Sprint 18

- Repartition initiale par "budget constant" : chaque competence reçoit un poids aleatoire, normalise puis multiplie par le budget total, arrondi, et le reste (du a l'arrondi) est redistribue un point a la fois au hasard — evite les nains "generalistes" forts partout
- `SkillDefinitions.gd` n'est pas un singleton/autoload : il est charge via `preload()` dans `Dwarf.gd` et `CharacterSheetUI.gd` (chacun sa propre reference au meme script, comportement normal et sans cout en GDScript)
- La duree de travail effective (`current_work_duration`) est calculee une fois au debut de chaque tache (pas recalculee en continu), donc un level-up en cours de tache ne change pas la duree de la tache deja en cours, seulement la suivante
- Le systeme est concu pour rester utilisable meme si toutes les competences ne sont pas encore definies (l'utilisateur a indique ne pas vouloir fixer la liste complete tout de suite) : ajouter une competence dans la table suffit, elle apparait automatiquement dans la fiche personnage et dans la repartition aleatoire

## Sprint 19 — Decoration du sol (herbe, fleurs, cailloux)

- [x] `scripts/ClimateDefinitions.gd` : table des climats (un seul "tempere" implemente pour l'instant, structure prete pour en ajouter d'autres plus tard - aride, enneige... - sans toucher au reste du code)
- [x] `scripts/GroundDecoration.gd` : parcourt la carte et pose, sur ~12% des cases dont le dessus est de la terre (densite "eparse", pour casser la monotonie sans surcharger), soit une touffe d'herbe (3-5 brins fins), soit une fleur (tige + bouton colore), soit un petit caillou
- [x] Couleur de l'herbe/des fleurs basee sur le climat de la carte (`ClimateDefinitions.CLIMATES`), avec de legeres variations aleatoires pour eviter un aspect trop uniforme
- [x] `VoxelWorld.is_dirt_top(x, z)` : nouvelle methode utilitaire pour savoir si une case a de la terre en surface, sans exposer l'enum interne `BlockType`
- [x] Purement decoratif : aucune interaction, aucun effet sur le gameplay
- [ ] A tester dans Godot

### A tester

1. Regarde le terrain : de petites touffes d'herbe, fleurs (rouges/jaunes/violettes) et cailloux doivent apparaitre eparpilles sur les cases de terre, sans etre trop denses ni trop rares
2. Verifie qu'il n'y a pas de decoration sur la pierre nue (zones minees) ni sur les murs construits
3. Verifie que les decorations ne genent pas visuellement les nains, les arbres ou les buissons a baies (chevauchement possible puisque les positions sont aleatoires independantes, a signaler si ça choque)
4. Verifie que les decorations n'ont aucun impact sur les performances/le gameplay (juste visuel)

### Notes techniques Sprint 19

- Les decorations sont generees une seule fois au demarrage a partir de l'etat initial du terrain : si une case est minee ensuite, une decoration deja posee dessus ne disparait pas automatiquement (limitation connue, acceptable pour l'instant vu la faible densite ; a corriger plus tard si ça devient genant, par exemple en re-scannant apres chaque minage)
- Positions non alignees sur la grille exacte (petit decalage aleatoire dans chaque case) pour un rendu plus naturel qu'un pur quadrillage
- Materiaux en `SHADING_MODE_UNSHADED`, comme le terrain (`VoxelWorld._make_material`), pour rester coherent avec le rendu plat du sol plutot que d'avoir des decorations "brillantes" a cote d'un sol mat
- `climate_id` est deja un champ expose sur `GroundDecoration` (actuellement toujours "tempere"), pret a devenir un vrai choix par carte quand un systeme de climats/saisons plus complet sera construit
- Les arbres (`Forest.gd`) et buissons (`BerryBushes.gd`) placent leurs elements a des positions aleatoires continues, sans verifier la grille de blocs ; les decorations de sol, elles, sont bien alignees sur la grille (une par case), car il fallait interroger `VoxelWorld` pour savoir ou se trouve la terre

## Fenetre de jeu agrandie

- [x] Fenetre par defaut passee de 1600x900 a 3200x1800 (x4 en surface d'affichage), reglage dans `project.godot` (`window/size/viewport_width/height`)
- [ ] A tester dans Godot (verifier que la fenetre s'ouvre bien plus grande, l'ajuster si elle deborde de l'ecran)

## Sprint 20 — Arbres realistes par espece (chene, sapin, bouleau)

- [x] `scripts/TreeSpecies.gd` : table des especes (chene, sapin, bouleau pour l'instant, facile a etendre), avec couleurs de tronc/branches/racines/feuillage et une "forme" generale par espece (touffue/conique/fine)
- [x] `scripts/Forest.gd` reecrit : chaque arbre a maintenant des racines evasees, un tronc effile, 2-4 branches inclinees, et un feuillage en plusieurs grappes (spheres pour chene/bouleau, cones empiles pour le sapin) plutot qu'un tronc + une sphere unique
- [x] Variations aleatoires par instance (echelle, teinte legere) pour que deux arbres de la meme espece ne soient jamais identiques
- [x] Chaque espece donne un type de bois different a la recolte (`bois_chene`, `bois_sapin`, `bois_bouleau`), en plus du compteur generique `bois` (qui reste seul utilise pour la construction, inchange)
- [x] Fiche de stats (bas de l'ecran) : detail du bois par espece affiche entre parentheses
- [ ] A tester dans Godot

### A tester

1. Regarde la foret : les arbres doivent avoir des silhouettes differentes (chene touffu/arrondi, sapin conique, bouleau plus fin/clair), pas tous identiques
2. Verifie que deux arbres de la meme espece ne sont pas des clones parfaits (taille/teinte legerement differentes)
3. Coupe plusieurs arbres d'especes differentes : verifie dans les stats que le compteur "Bois" total augmente ET que le detail par espece (chene/sapin/bouleau) se met a jour correctement
4. Verifie que la construction (mur en bois) fonctionne toujours normalement (elle consomme le total generique, pas une espece en particulier)

### Notes techniques Sprint 20

- Chaque arbre porte son type de bois via `set_meta("wood_resource", ...)`, lu par `Dwarf._complete_task()` avant de detruire l'arbre — pas besoin d'un script dedie sur chaque arbre (comme pour les buissons/`BerryBush.gd`), plus simple pour une info aussi ponctuelle
- Double comptage volontaire dans `Inventory` : `bois_chene`/`bois_sapin`/`bois_bouleau` sont des compteurs a part, mais chaque recolte alimente aussi le compteur generique `bois` — ainsi la construction (qui ne connait que `bois`) continue de fonctionner sans aucune modification, et le detail par espece est purement informatif pour l'instant (aucune consommation dediee, ex: pas encore de "mur en chene" specifique)
- Le sapin utilise `CylinderMesh` avec `top_radius = 0.0` (un cone) pour le feuillage ; le chene/bouleau utilisent des `SphereMesh` en grappe. Toutes les formes restent des primitives generees par code, coherent avec le reste du monde (terrain, decorations)

## Sprint 21 — Sol en herbe (climat/saison), suppression du damier

- [x] Le dessus du terrain ("terre") n'affiche plus le damier clair/fonce : il est remplace par une couleur d'herbe issue du climat et de la saison actuels (`ClimateDefinitions.get_terrain_color`)
- [x] Variation subtile et continue de couleur par case (bruit `FastNoiseLite`, +/- ~12% de luminosite), pour eviter un aplat totalement uniforme sans redessiner de motif regulier
- [x] `ClimateDefinitions.gd` etendu : chaque climat a maintenant un champ `terrain_par_saison` (une couleur par saison) ; une seule saison geree pour l'instant (`ete`), structure prete a en accueillir d'autres
- [x] Le damier de la pierre (utile pour reperer les trous mines) et les murs ne sont pas touches — seul le sol en herbe change
- [ ] A tester dans Godot

### A tester

1. Regarde le sol : il doit apparaitre en vert herbe uniforme (avec de tres legeres variations de teinte case a case), plus aucun damier visible
2. Verifie que la pierre (sous la terre / dans un trou mine) garde bien son damier clair/fonce comme avant
3. Verifie que miner puis reboucher un trou de terre redonne bien la couleur d'herbe normale (pas de couleur figee/incorrecte)
4. Verifie que les decorations de sol (herbe/fleurs/cailloux du Sprint 19) restent coherentes visuellement par-dessus ce nouveau sol

### Notes techniques Sprint 21

- Le damier clair/fonce du dessus de terre (buckets 0/1) devient un seul bucket (0) dont le materiau lit une couleur par sommet (`vertex_color_use_as_albedo = true`), fixee via `SurfaceTool.set_color()` dans `_add_face` — le bucket 1 (ancien "terre fonce") reste reserve mais inutilise, pour ne pas renumeroter tout le reste
- `VoxelWorld` expose `climate_id`/`season_id` (par defaut "tempere"/"ete"), sur le meme principe que `GroundDecoration.climate_id` (Sprint 19) : pret a devenir un vrai choix par carte plus tard
- Le bruit utilise une frequence basse (0.18) pour une variation douce et continue d'une case a l'autre, contrairement a un simple hachage aleatoire par case qui donnerait un resultat "poivre et sel" peu naturel

## Sprint 22 — Reorganisation de scripts/ en hierarchie par categorie

- [x] `scripts/` n'est plus un dossier plat : les fichiers sont ranges par categorie, prets a accueillir beaucoup plus de contenu (materiaux, creatures...) sans redevenir un fouillis
- [x] `scripts/data/` : tables de donnees statiques (const TABLE + static func), sans logique de jeu
  - `data/materiaux/types/bois/TreeSpecies.gd` (types de bois : chene/sapin/bouleau)
  - `data/materiaux/types/terre/`, `data/materiaux/types/pierre/`, `data/materiaux/types/metaux/` : dossiers vides prepares pour plus tard (terre, pierre — granite/argile/sable/calcaire —, metaux — fer/or —), pas encore de fichier ni d'effet en jeu
  - `data/climats/ClimateDefinitions.gd` (climats + couleur de terrain par saison)
  - `data/creatures/nains/caracteristiques/SkillDefinitions.gd` (competences)
  - `data/creatures/ennemis/`, `data/creatures/amis/`, `data/creatures/betes/` : dossiers vides prepares pour plus tard
- [x] `scripts/entites/` : Dwarf.gd, Forest.gd, BerryBush.gd, BerryBushes.gd (scripts de comportement des acteurs vivants)
- [x] `scripts/monde/` : VoxelWorld.gd, GroundDecoration.gd (terrain/decor)
- [x] `scripts/ui/` : CharacterSheetUI.gd
- [x] `scripts/systemes/` : ActionController.gd, TaskQueue.gd, Inventory.gd, CameraRig.gd, Main.gd (inutilise)
- [x] Tous les `preload(...)` et tous les chemins de script dans `Main.tscn` mis a jour vers les nouveaux emplacements
- [ ] A tester dans Godot

### A tester

1. Ouvre le projet dans Godot : verifie qu'il n'y a aucune erreur "resource introuvable" au chargement de la scene `Main.tscn`
2. Lance le jeu (F5) : tout doit fonctionner exactement comme avant (aucun changement de gameplay, uniquement de rangement des fichiers)
3. Dans le panneau FileSystem de Godot, verifie que l'arborescence `scripts/data/`, `entites/`, `monde/`, `ui/`, `systemes/` apparait bien comme prevu

### Notes techniques Sprint 22

- Reorganisation pure : aucun code de gameplay modifie, uniquement des deplacements de fichiers (`.gd` + `.gd.uid`) et la mise a jour des chemins qui les referencent (`preload()` dans les scripts, `ext_resource` dans `Main.tscn`)
- Les fichiers `.gd.uid` (identifiant stable genere par Godot) ont ete deplaces avec leur script correspondant : Godot les utilise pour retrouver une ressource meme si son chemin change, ce qui limite le risque de reference cassee
- Les dossiers vides (`pierre/`, `metaux/`, `terre/`, `ennemis/`, `amis/`, `betes/`) sont volontairement sans fichier : ils marquent la place prevue pour du contenu futur, sur le meme modele que `TreeSpecies.gd` ou `SkillDefinitions.gd` (`const TABLE` + `static func`), a creer seulement quand ce contenu sera vraiment implemente

## Sprint 23 — Profondeur : filons de metaux et pierres precieuses dans la pierre

- [x] Carte de test agrandie en profondeur : 10 -> 30 niveaux de haut (toujours 3 niveaux de terre en surface, le reste en pierre), pour laisser de la place aux filons
- [x] `data/materiaux/types/metaux/MetalTypes.gd` : fer, cuivre, etain, charbon (communs), argent (rare), or, platine (tres rares)
- [x] `data/materiaux/types/pierres_precieuses/GemTypes.gd` : emeraude, rubis, saphir, lapis-lazuli, jade, diamant blanc (rares), diamant rose, diamant noir (tres rares)
- [x] `data/materiaux/types/VeinMaterials.gd` : regroupe les deux tables, triees du plus rare au plus commun, pour la generation
- [x] Filons generes uniquement dans la pierre (jamais dans les 3 niveaux de terre), sous forme de petits amas (bruit 3D par materiau), visibles a l'oeil (couleur du filon dans la roche)
- [x] Miner un bloc de filon donne directement la ressource correspondante (ex: "fer", "rubis") au lieu de "pierre"
- [x] Nouveaux compteurs dans l'inventaire pour les 14 metaux/pierres precieuses (suivi interne, pas encore affiche dans la barre de stats)
- [x] L'item qui "saute" a la recolte reprend la couleur du materiau mine
- [ ] A tester dans Godot

### A tester

1. Descends sous la terre (molette de la souris) : au bout de quelques niveaux de pierre, tu dois voir apparaitre des taches de couleur differente (les filons) au milieu du gris de la roche
2. Mine un filon : verifie dans la console que la ressource recoltee correspond bien au filon (ex: "Recolte : +1 fer" et non "+1 pierre"), et que le petit cube qui saute a la bonne couleur
3. Verifie que les 3 niveaux du dessus (terre/herbe) n'ont jamais de filon, seulement la pierre en dessous
4. Verifie que la camera peut bien descendre jusqu'au fond de la carte (niveau -27 environ) sans bug d'affichage

### Notes techniques Sprint 23

- Les filons ne sont pas un nouveau `BlockType` : ils restent des blocs `STONE` normaux, avec juste une entree dans un dictionnaire separe (`vein_grid`, position -> id du materiau). Ca evite de faire exploser l'enum et le systeme de "buckets" de rendu pour chaque metal/pierre precieuse (14 types) - un seul bucket supplementaire (colore par sommet, meme technique que l'herbe du Sprint 21) suffit pour tous
- Chaque materiau a son propre bruit 3D (seed different), verifie du plus rare au plus commun pour qu'un materiau commun ne "prenne" pas un bloc qui aurait pu etre un materiau rare
- Les seuils de rarete (`RARITY_THRESHOLDS` dans `VoxelWorld.gd` : commun=0.45, rare=0.65, tres_rare=0.80) sont des valeurs de depart raisonnables, faciles a ajuster apres avoir vu la densite des filons en jeu
- Pas d'affichage detaille des 14 ressources dans la barre de stats pour l'instant (choix explicite pour ne pas la surcharger) - un vrai panneau d'inventaire viendra plus tard

## Sprint 23bis — Correction du systeme de niveaux (vue en coupe)

- [x] Bug corrige : changer de niveau (molette) ne faisait que deplacer la camera en Y, sans rien cacher du terrain - inutile pour voir un niveau souterrain puisque tout est plein autour (la camera se retrouvait juste a l'interieur de la roche)
- [x] `VoxelWorld.gd` : nouveau `view_level`, pilote par `CameraRig` a chaque changement de niveau. Tout ce qui est au-dessus de `view_level` n'est plus dessine du tout, et le dessus de chaque bloc exactement a `view_level` est toujours revele (meme s'il y avait un bloc juste au-dessus) - ca donne une coupe horizontale complete et coloree du niveau courant, comme dans un Dwarf Fortress
- [x] `CameraRig.gd` appelle `voxel_world.set_view_level(...)` a chaque molette (et au demarrage), en plus de deplacer la camera comme avant
- [ ] A tester dans Godot

### A tester

1. Au demarrage, tu dois voir la surface (herbe) comme avant, sans changement
2. Descends d'un niveau (molette bas) : la vue doit maintenant montrer une coupe complete et coloree du niveau (plus de sensation d'etre "dans le noir"/coince dans la roche)
3. Continue a descendre a travers la pierre : tu dois voir le damier de pierre + les taches colorees des filons sur toute la surface du niveau affiche
4. Remonte (molette haut) jusqu'a la surface : verifie que tout redevient normal

### Notes techniques Sprint 23bis

- Le systeme de niveaux existait deja depuis le Sprint 2, mais n'avait jamais ete relie a un vrai mecanisme de visibilite - il ne faisait que deplacer `CameraRig.global_position.y`. Ca ne posait pas de probleme visible tant que la carte etait fine (10 niveaux, dont 7 de pierre) et que le joueur ne s'attardait pas sous terre, mais devient genant avec la profondeur et les filons du Sprint 23
- Technique : un bloc a `pos.y > view_level` n'est pas ajoute au mesh du tout ; et une face est consideree "exposee" (donc dessinee) si son voisin est soit reellement vide, soit lui-meme au-dessus de `view_level` (donc "invisible" de toute facon). C'est cette deuxieme condition qui revele le dessus color de chaque bloc du niveau courant
- Cout : un `rebuild_mesh()` complet a chaque changement de niveau (comme pour miner/construire), donc pas de cout supplementaire en dehors des moments ou le joueur change reellement de niveau

## Sprint 23ter — Retrait du damier de la pierre (materiau uniforme par niveau)

- [x] Le dessus de la pierre n'affiche plus de damier clair/fonce a deux tons : couleur de pierre unique (`STONE_BASE`), avec une legere variation continue par case (meme technique que l'herbe du Sprint 21), au lieu de deux teintes alternees
- [x] Un niveau de pierre donne a maintenant un materiau uniforme, les filons de metaux/pierres precieuses restant la seule vraie exception de couleur (conforme a la demande initiale)
- [x] Le damier de la pierre n'avait pas de lien avec les filons ni avec la detection des trous mines (qui repose sur l'assombrissement des parois, inchange) - retire sans effet de bord
- [ ] A tester dans Godot

### A tester

1. Descends a un niveau de pierre (sans filon visible dessus) : la couleur doit etre uniforme (gris-bleu), pas en damier
2. Verifie que les filons ressortent toujours bien comme des taches de couleur differente sur ce fond uniforme
3. Mine un trou dans la pierre : verifie que les parois du trou restent bien visibles (plus sombres), ce mecanisme est independant du damier retire

### Notes techniques Sprint 23ter

- Meme demarche que pour l'herbe (Sprint 21) : bucket 2 (dessus pierre) passe en materiau "couleur par sommet" (`vertex_color_use_as_albedo`), le bucket 3 (ancien "pierre fonce" du damier) devient inutilise mais reste reserve, pour ne pas renumeroter les autres buckets
- Bruit separe de celui de l'herbe (`stone_noise`) pour que les deux variations ne soient pas correlees visuellement

## Sprint 23quater — Textures pour les filons (ABANDONNE)

- [x] Tentative : les filons de metaux/pierres precieuses devaient afficher une texture (atlas genere via Python/Pillow, `tools/gen_vein_atlas.py` -> `assets/vein_atlas.png`) au lieu d'un aplat de couleur
- [x] Bug bloquant : tous les blocs de filon s'affichaient en blanc dans Godot, meme apres un fix (passage de `load()` a `preload()` pour la texture, avec fallback magenta de diagnostic) - la texture se chargeait bien (pas de magenta) mais restait invisible, cause racine jamais identifiee
- [x] **ABANDONNE** sur decision explicite de Francois - revert complet vers le bloc de couleur uni (voir Sprint 23quinquies ci-dessous)
- Fichiers laisses en place mais inutilises (code mort, pas nettoye) : `assets/vein_atlas.png`, `tools/gen_vein_atlas.py`, `VeinMaterials.atlas_order()`/`atlas_index()`

## Sprint 23quinquies — Retour au bloc de couleur uni pour les filons (revert du Sprint 23quater)

- [x] `VoxelWorld.gd` : le bucket "filon" (10) revient a une couleur par sommet (`_vein_color_for`, meme mecanisme que Sprint 23), suppression de tout le mapping UV/texture ajoute au Sprint 23quater
- [x] Suppression de `_make_vein_atlas_material()`, des consts `VEIN_ATLAS_*`, et des parametres UV de `_add_face()`
- [ ] A tester dans Godot : les filons de metaux/pierres precieuses doivent a nouveau apparaitre en blocs de couleur unie (pas blancs, pas textures)

### Notes techniques Sprint 23quinquies

- Retour exact a l'etat du Sprint 23ter pour le rendu des filons - aucune autre logique (generation des filons, rarete, profondeur) n'a ete touchee
- Les fichiers orphelins du Sprint 23quater (`vein_atlas.png`, `gen_vein_atlas.py`, `atlas_order()`/`atlas_index()`) restent presents mais ne sont plus utilises par `VoxelWorld.gd`

## Sprint 23sexies — Pepites 3D + materiaux brillants pour les filons

- [x] Les blocs de filon affichent maintenant en plus de leur couleur de fond des "pepites" 3D incrustees sur la face visible : petites spheres rondes et metalliques (reflets) pour les metaux, petites spheres a facettes (peu de segments, orientation aleatoire) et legerement lumineuses pour les pierres precieuses
- [x] Taille des pepites variable selon la rarete (plus grosses pour les materiaux tres rares)
- [x] Densite choisie : 6 a 9 pepites par bloc de filon visible
- [x] `VeinMaterials.gd` : nouvelle fonction `is_metal(id)` pour distinguer metal/pierre precieuse sans dupliquer un champ dans les tables
- [x] Teste et confirme dans Godot par l'utilisateur

### A tester

1. Regarde un filon de metal (ex: fer, or) : en plus du fond colore, tu dois voir de petites boules rondes/brillantes incrustees dedans
2. Regarde un filon de pierre precieuse (ex: rubis, emeraude) : tu dois voir de petites boules a facettes, avec un leger scintillement
3. Verifie que les filons de materiaux tres rares (or, platine, diamant rose/noir) ont des pepites visiblement un peu plus grosses que les communs
4. Change de niveau (molette) et mine un bloc de filon : les pepites doivent apparaitre/disparaitre en coherence avec la coupe et le minage, sans decalage ni pepite "flottante"

### Notes techniques Sprint 23sexies

- Aucune image/texture/shader : les pepites sont des `SphereMesh` integres au moteur (peu de segments = aspect facette pour les gemmes, beaucoup de segments = aspect rond pour les metaux), portees par deux `MultiMeshInstance3D` (un par categorie), avec une couleur par instance - meme principe deja fiable que la couleur par sommet utilisee pour l'herbe/la pierre/les filons, pour eviter de retomber sur le bug de blocs blancs du Sprint 23quater
- Position/taille/orientation de chaque pepite tirees au sort mais **deterministes** (graine calculee a partir de la position du bloc) : elles ne changent pas d'aspect a chaque minage/construction ailleurs sur la carte, seul le recalcul (miner ce bloc precis, changer de niveau) les fait apparaitre/disparaitre
- Recalcule integralement a chaque `rebuild_mesh()` (comme le reste du terrain) - ne place des pepites que sur les blocs de filon ayant au moins une face exposee (coherent avec la vue en coupe du Sprint 23bis)
- Materiaux des pepites *eclaires* (pas "unshaded" comme le reste du terrain) pour que `metallic`/`roughness`/`emission` aient un effet visible - depend donc de la lumiere/l'environnement deja en place depuis le Sprint 13

## Sprint 24 — Herbe assombrie + decorations de sol doublees

- [x] Couleur de l'herbe (terrain + touffes de decoration) assombrie d'environ 20%, jugee trop claire
- [x] Densite des decorations de sol (touffes d'herbe, fleurs, cailloux) doublee : 0.24 au lieu de 0.12
- [ ] A tester dans Godot

### Notes techniques Sprint 24

- `ClimateDefinitions.gd` : `herbe_base`/`herbe_variations`/`terrain_par_saison.ete` du climat "tempere" multiplies par ~0.8
- `GroundDecoration.gd` : `decoration_chance` 0.12 -> 0.24 (le detail touffe/fleur/caillou parmi les decorations n'a pas change, juste la frequence globale)

## Sprint 24bis — Arbres : branches/feuilles ameliorees + troncs raccourcis

- [x] Branches plus nombreuses (3 a 5 au lieu de 2 a 4), plus longues et plus epaisses
- [x] Vraies "feuilles" (petites plaques, sans texture) aux extremites des branches et sur le feuillage touffu/fin (chene, bouleau) - pas sur le sapin, deja represente par des aiguilles
- [x] Troncs de sapin (1.7 -> 1.15) et de bouleau (1.4 -> 1.05) raccourcis
- [ ] A tester dans Godot

### A tester

1. Regarde un chene ou un bouleau : les branches doivent etre bien visibles, avec de petites feuilles a leurs extremites et sur le feuillage
2. Compare la hauteur des sapins/bouleaux aux chenes : ils doivent paraitre moins hauts qu'avant

### Notes techniques Sprint 24bis

- Nouvelle fonction generique `_build_leaf_cluster()` (Forest.gd) : petites `BoxMesh` tres fines, orientation aleatoire, utilisee a la fois pour les extremites de branches et sur les blobs de feuillage - aucune image/texture
- Les feuilles aux extremites de branches sont ancrees en enfant du noeud de la branche elle-meme (pas recalcul de position monde a la main) : heritent automatiquement de toutes les rotations parent

## Sprint 24ter — Arbres fruitiers + action "Cueillir"

- [x] 3 nouvelles especes d'arbres (`TreeSpecies.gd/FRUIT_SPECIES`) : pommier, oranger, cerisier, avec fruits visibles sur l'arbre
- [x] Nouvelle action **Cueillir** (bouton dedie) : recolte un fruit a la fois sans abattre l'arbre, contrairement a "Couper"
- [x] Fruit recolte stocke en inventaire comme une vraie ressource (pomme/orange/cerise)
- [ ] A tester dans Godot

### A tester

1. Repere un pommier/oranger/cerisier (feuillage avec des boules colorees en plus des feuilles)
2. Clique sur "Cueillir" puis sur l'arbre : un nain doit venir cueillir un fruit (sans couper l'arbre), qui part en inventaire
3. Verifie que "Couper" fonctionne toujours normalement sur un arbre fruitier (donne le bois, detruit l'arbre)
4. Une fois tous les fruits cueillis, l'arbre reste en place (juste sans fruits)

### Notes techniques Sprint 24ter

- Arbres fruitiers generes a part des arbres de foret (`Forest.gd`, `fruit_tree_count`), pas dans le tirage aleatoire de `random_species()`
- Metadonnees `fruit_resource`/`fruits_left` + enfants nommes `Fruit_%d` (memes conventions que les buissons a baies, voir Sprint 24quater) - `Dwarf.gd/_complete_task` traite "cueillir" de facon generique entre arbres et buissons
- Nouveau groupe Godot `cueillette` (arbres fruitiers + buissons), independant du groupe `trees` (toujours utilise par "Couper")

## Sprint 24quater — 4 types de buissons a baies + repas depuis l'inventaire

- [x] 4 types de baies (`BerryTypes.gd`) : groseille, myrtille, fraise, framboise, un type au hasard par buisson
- [x] Les buissons se recoltent maintenant via l'action "Cueillir" (comme les arbres fruitiers) au lieu d'etre manges directement
- [x] Les nains mangent depuis l'inventaire commun quand ils ont faim (n'importe quelle baie/fruit disponible), sans se deplacer jusqu'a un buisson
- [ ] A tester dans Godot

### A tester

1. Repere un buisson, utilise "Cueillir" dessus : une baie doit partir en inventaire (le buisson reste en place, juste avec moins de baies visibles)
2. Attends qu'un nain ait faim sans avoir cueilli de baies : il ne doit plus se deplacer vers un buisson (l'ancien comportement), et rester affame si l'inventaire n'a pas de nourriture
3. Une fois des baies/fruits en inventaire, verifie qu'un nain affame mange directement sur place (petite animation), sans marcher nulle part

### Notes techniques Sprint 24quater

- `BerryBush.gd` (l'ancien script avec la methode `eat()`) n'est plus utilise - les buissons sont maintenant des noeuds simples avec metadonnees (`fruit_resource`/`fruits_left`), exactement comme les arbres fruitiers
- `Dwarf.gd` : toute la logique de recherche de buisson (`_start_seeking_food`/`_find_nearest_bush`/`_process_seek_food`) est remplacee par `_try_start_eating()`, qui verifie simplement si une ressource de nourriture (baie ou fruit) est disponible en inventaire commun
- `CharacterSheetUI.gd` : l'etat affiche "Va manger" (`is_seeking_food`) n'existe plus, remplace par le seul etat "Manger" (le trajet n'a plus lieu d'etre)

## Sprint 24quinquies — Corrections : sapin trop de tronc + action "Cueillir" muette

- [x] Bug signale par l'utilisateur : le tronc du sapin restait long avant que les "feuilles" (aiguilles) ne commencent - le feuillage part maintenant du sommet d'un tronc visuel beaucoup plus court, et couvre presque toute la hauteur de l'arbre (comme un vrai sapin)
- [x] Bug signale par l'utilisateur : l'action "Cueillir" ne mettait jamais de tache en attente - cause trouvee : `ActionController.GROUND_LEVEL` etait reste a 10.0 (hauteur de carte d'avant le Sprint 23, qui l'a portee a 30), ce qui decalait le point clique (x/z, pas seulement y, la camera regardant en angle) - corrige a 30.0
- [x] Suite au premier correctif, deuxieme signalement de l'utilisateur : le sapin etait devenu trop petit dans l'ensemble (la hauteur totale avait ete raccourcie au Sprint 24bis en meme temps que le tronc) et ses branches depassaient du cone de feuillage - hauteur totale remontee (1.15 -> 1.6, tronc visuel toujours court), branches retirees pour le sapin (le cone de feuillage suffit a representer la silhouette)
- [x] "Cueillir" confirme fonctionnel par l'utilisateur apres correctif
- [ ] Sapin (hauteur/silhouette) a tester dans Godot

### A tester

1. Regarde un sapin : tronc court, feuillage qui commence presque au sol et couvre presque toute la hauteur, aucune branche qui depasse, silhouette globale pas plus petite que les autres arbres
2. Verifie que Miner/Couper/Construire visent toujours bien la case sous le curseur (le meme correctif de hauteur les concerne aussi, meme si ca semblait moins genant avant)

### Notes techniques Sprint 24quinquies

- `Forest.gd/_build_trunk` renvoie desormais la hauteur visuelle du tronc (courte pour le sapin, `max(trunk_height * 0.25, 0.18)`) ; `_build_foliage_conique` recoit cette valeur et etale ses 4-5 niveaux de cones entre ce point et le sommet reel de l'arbre, au lieu de 2-3 cones tasses juste sous le sommet
- `ActionController.GROUND_LEVEL` : 10.0 -> 30.0 (deja repere/note en memoire comme risque potentiel pendant le Sprint 24ter, confirme ici comme cause reelle du bug "Cueillir muet")
- `TreeSpecies.gd` : hauteur du sapin remontee a 1.6 (le tronc visuel etant deja decouple de cette valeur, on peut agrandir l'arbre sans faire revenir un long tronc) ; `Forest.gd/_build_branches` retourne immediatement (aucune branche construite) pour les especes "conique"

## Sprint 24sexies — Buissons vs plantes basses : deux sprites distincts

- [x] Ajout du cassis (`BerryTypes.gd`) - absent de la liste initiale
- [x] Chaque type de baie a maintenant une "categorie" : "buisson" (myrtille, groseille, cassis) garde le sprite boule + baies autour existant ; "plante" (fraise, framboise) a un nouveau sprite bas au ras du sol (touffe de feuilles + baies nichees dedans)
- [ ] A tester dans Godot

### A tester

1. Repere plusieurs buissons/plantes sur la carte : myrtille/groseille/cassis doivent ressembler a une boule de feuillage avec des baies autour (comme avant), fraise/framboise doivent ressembler a une touffe basse pres du sol
2. Verifie que "Cueillir" fonctionne toujours sur les deux types (peu importe le sprite, la recolte est identique)

### Notes techniques Sprint 24sexies

- `BerryBushes.gd` : `_spawn_bush()` aiguille vers `_build_bush_visual()` (inchange) ou `_build_plant_visual()` (nouveau, petites feuilles plates + baies basses) selon `BerryTypes.categorie`

## Sprint 24septies — Tas de ressources au sol + competence Agriculture + calories

- [x] Toute recolte (fruits, baies, terre, pierre, metaux...) fait desormais tomber un petit tas de morceaux colores a l'endroit de la recolte, au lieu d'un item flottant qui disparaissait en fondu - la ressource est comptee immediatement dans l'inventaire, le tas est purement visuel pour l'instant et reste en place indefiniment (une future tache "transport vers le stockage" viendra le faire disparaitre, pas encore construite)
- [x] Nouvelle competence "Agriculture" (`SkillDefinitions.gd`) reliee a la tache "cueillir" : meme mecanique que Minage/Bucheronnage, augmente la vitesse de cueillette et donne une chance de recolter un fruit/baie bonus par action
- [x] Chaque fruit (`TreeSpecies.FRUIT_SPECIES`) et chaque baie (`BerryTypes.TYPES`) a maintenant une valeur de calories propre (pomme 35, orange 30, cerise 22, myrtille/cassis 20-22, groseille/framboise 18, fraise 16) - manger restaure desormais un nombre de faim different selon l'aliment, au lieu d'un montant fixe identique pour tous
- [ ] A tester dans Godot

### A tester

1. Recolte du bois, de la pierre, un minerai et un fruit/baie : verifie qu'un petit tas de morceaux colores apparait bien au sol a chaque recolte, et qu'il reste visible durablement (pas de fondu/disparition)
2. Verifie que la ressource recoltee est bien comptee dans l'inventaire des la recolte (le tas au sol n'est qu'un decor, pas un objet a ramasser)
3. Fais cueillir un nain plusieurs fois de suite sur un meme arbre fruitier/buisson : de temps en temps, verifie dans les stats/logs qu'un fruit bonus est recolte en une seule action (chance liee au niveau d'Agriculture, comme pour le minage/la coupe)
4. Verifie dans la fiche personnage qu'un nain peut avoir un niveau d'Agriculture qui progresse en cueillant
5. Fais manger un nain differents fruits/baies (par ex. une pomme puis une fraise) et verifie que la faim remonte de facon differente selon l'aliment (une pomme doit restaurer plus qu'une fraise)

### Notes techniques Sprint 24septies

- `Dwarf.gd/_spawn_resource_pile()` remplace l'ancien `_spawn_loot_item()` (cube flottant + tween de fondu) : cree un `Node3D` avec 3-4 `BoxMesh` de petite taille et de couleur (`_resource_color`), disperses aleatoirement autour du point de recolte, sans animation ni destruction automatique
- `_collect_resource()` appelle desormais `add_resource` (comptage immediat) puis `_spawn_resource_pile` (visuel), au lieu de l'ancien enchainement comptage + item flottant anime
- `_complete_task()` (branche "cueillir") utilise le nouveau helper `_harvest_one_fruit()` et tente une deuxieme recolte via `_roll_bonus_yield(skill_id)` (meme fonction generique deja utilisee par minage/coupe) si le buisson/arbre a encore des fruits disponibles
- `_process_eating()` et le nouveau helper `_food_calories()` : cherche la valeur "calories" dans `BerryTypes.calories_for()` puis `TreeSpecies.calories_for()`, et retombe sur l'ancienne constante `hunger_restore_per_berry` si l'aliment n'a pas de valeur definie (securite, ne devrait plus arriver avec les tables a jour)
- Valeurs de calories choisies a la main (pas de source reelle), facilement ajustables dans `TreeSpecies.FRUIT_SPECIES` / `BerryTypes.TYPES` si un aliment parait trop ou pas assez nourrissant en jeu
- Les deux visuels utilisent toujours la convention `Fruit_%d` pour les baies - aucun changement cote recolte/inventaire (`Dwarf.gd`)

## Sprint 25 — Fenetre d'info au clic sur un objet ("Inspecter")

- [x] Quand aucun mode d'action (Miner/Couper/Cueillir/Construire) n'est actif, un clic gauche sur un arbre, un buisson/plante, un bloc de terre/pierre ou un filon affiche une petite fenetre avec son nom (et, pour les arbres fruitiers/buissons, le nombre de fruits restants)
- [x] Pas de nouveau bouton : c'est le comportement par defaut du clic quand aucun mode n'est enclenche (choix pour rester simple, moins de boutons a apprendre)
- [x] La fenetre se ferme via son bouton "Fermer", ou automatiquement des qu'un mode d'action est active
- [ ] A tester dans Godot

### A tester

1. Sans activer Miner/Couper/Cueillir/Construire, clique sur un arbre : la fenetre doit afficher son espece (Chene/Sapin/Bouleau/Pommier/Oranger/Cerisier)
2. Clique sur un pommier/oranger/cerisier ou un buisson/plante a baies : verifie que le nombre de fruits restants s'affiche, et qu'il diminue si tu le recoltes puis reinspectes (et affiche "(vide)" une fois a 0)
3. Clique sur de la terre, de la pierre nue, et un bloc de filon (metal/pierre precieuse visible) : verifie les noms "Terre", "Pierre", "Filon de X" (avec le bon nom de materiau)
4. Clique sur un mur construit (bois ou pierre) : verifie "Mur en bois" / "Mur en pierre"
5. Verifie que la fenetre se ferme bien en cliquant sur "Fermer", et aussi automatiquement si tu actives ensuite Miner/Couper/Cueillir/Construire
6. Verifie que Miner/Couper/Cueillir/Construire fonctionnent toujours normalement une fois actives (l'inspection ne doit intervenir que quand aucun mode n'est actif)

### Notes techniques Sprint 25

- `VoxelWorld.gd/get_block_info(x, z)` : nouvelle fonction qui renvoie le type du bloc du sommet d'une colonne ("terre"/"pierre"/"mur_bois"/"mur_pierre"/"vide") et l'id du filon s'il y en a un - renvoie des chaines plutot que l'enum `BlockType` (meme raison que `is_dirt_top()` deja existant : l'enum n'est pas resolvable depuis un script qui recupere `%VoxelWorld` via un type generique `Node3D`)
- `ActionController.gd/_handle_inspect_click()` : cherche d'abord un noeud proche dans les groupes "cueillette" puis "trees" (meme rayon de detection que Couper/Cueillir), sinon decrit le bloc de sol via `get_block_info()` ; le nom affiche pour un arbre/buisson vient de la metadonnee `species_name` deja posee par `Forest.gd`/`BerryBushes.gd`, le compte de fruits de `fruits_left`
- Nouveau noeud `ActionUI/InfoPanel` (PanelContainer + Label + bouton Fermer) dans `Main.tscn`, cache par defaut, repositionne pres du point de clic a chaque inspection
- Le clic d'inspection reutilise `_raycast_ground()` (deja utilise par Miner/Couper/Cueillir/Construire), donc soumis au meme `GROUND_LEVEL` deja corrige au Sprint 24quinquies

## Sprint 26 — Icone temporaire sur les objets designes (Miner/Couper/Cueillir)

- [x] Un petit carre colore apparait desormais sur la case/l'objet designe des qu'une tache Miner, Couper ou Cueillir est mise en file, et disparait automatiquement une fois la tache terminee - meme principe que le mur "fantome" deja existant pour Construire, applique aux trois autres actions
- [x] Couleur du marqueur identique a celle de l'icone du bouton du mode (gris pour Miner, vert pour Couper, rouge pour Cueillir)
- [ ] A tester dans Godot

### A tester

1. Active Miner et clique sur un bloc : un petit carre gris doit apparaitre au-dessus, et disparaitre quand le nain a fini de miner ce bloc
2. Active Couper et clique sur un arbre : un carre vert doit apparaitre au-dessus de l'arbre, et disparaitre quand l'arbre est abattu
3. Active Cueillir et clique sur un arbre fruitier puis sur un buisson/plante : un carre rouge doit apparaitre sur chacun, et disparaitre une fois la recolte terminee (meme si l'arbre/buisson reste en place)
4. Designe plusieurs taches d'un coup (par ex. 3 arbres a couper) : verifie que chaque objet garde son marqueur jusqu'a ce que SA tache a lui soit terminee (pas tous en meme temps)
5. Verifie que le mur "fantome" de Construire fonctionne toujours normalement (inchange par ce sprint)

### Notes techniques Sprint 26

- `TaskQueue.gd` : `add_mine_task`/`add_chop_task`/`add_gather_task` ont maintenant un id unique (meme mecanisme que `add_build_task` deja existant) et le renvoient
- `Dwarf.gd` : nouveau signal generique `task_finished(task_id)`, emis a la fin de `_complete_task()` quel que soit le type de tache - independant de `build_task_finished` (garde tel quel, toujours utilise pour le mur fantome de Construire)
- `ActionController.gd` : `queued_markers` (task_id -> marqueur), rempli par les 3 handlers de clic (Miner/Couper/Cueillir) et vide par `_on_task_finished()` connecte au nouveau signal generique de chaque nain
- `_spawn_task_marker()` : un `QuadMesh` colore, unshaded, avec `billboard_mode` active pour toujours faire face a la camera - pas de texture/image (le projet a deja rencontre un bug de blocs blancs avec des textures de filons, voir memoire), juste une couleur unie comme les murs fantomes
- Hauteur du marqueur au-dessus de la cible : fixe et approximative selon le type d'objet (bloc mine, arbre, arbre fruitier, buisson/plante bas) plutot que calculee depuis la vraie hauteur du modele - suffisant pour un marqueur flottant, evite de dupliquer les donnees de hauteur de `TreeSpecies.gd`

## Sprint 26bis — Icones d'outil (pioche/hache/panier) au lieu de simples carres colores

- [x] Les marqueurs de tache (Sprint 26) sont remplaces par une vraie forme d'outil reconnaissable : pioche pour Miner, hache pour Couper, panier pour Cueillir - toujours dans la couleur du bouton du mode
- [ ] A tester dans Godot

### A tester

1. Active Miner et clique sur un bloc : le marqueur doit avoir la forme d'une pioche (manche + tete), en gris
2. Active Couper et clique sur un arbre : le marqueur doit avoir la forme d'une hache (manche + lame triangulaire), en vert
3. Active Cueillir et clique sur un arbre fruitier ou un buisson : le marqueur doit avoir la forme d'un panier (corps + anse), en rouge
4. Verifie que les icones restent nettes (pas floues) et bien visibles sous differents angles de camera (billboard toujours face a la camera)
5. Designe plusieurs taches differentes en meme temps (ex: miner + couper + cueillir) : verifie que chaque marqueur garde la bonne forme et disparait au bon moment

### Notes techniques Sprint 26bis

- `_spawn_task_marker()` prend maintenant un parametre `kind` ("pioche"/"hache"/"panier") en plus de la couleur, et applique une texture (`albedo_texture`) au lieu d'une simple couleur unie sur le `QuadMesh`
- Les icones sont dessinees pixel par pixel a l'execution dans une petite image en memoire (`Image.create` + `set_pixel`, 20x20, fond transparent), exactement comme `_make_square_icon` (icones des boutons) - aucun fichier image charge depuis le disque, donc pas de risque de retomber sur le bug de blocs blancs deja rencontre avec les textures de filons (voir memoire)
- Fonctions de dessin dediees par outil : `_draw_pickaxe_icon` (manche diagonal + tete en chevron), `_draw_axe_icon` (manche vertical + lame triangulaire pleine), `_draw_basket_icon` (corps trapezoidal + anse courbe) - construites a partir de petits utilitaires generiques (`_draw_thick_line`, `_plot_blob`, `_fill_triangle`) reutilisables si d'autres icones sont ajoutees plus tard
- `_get_icon_texture()` met en cache les textures deja generees (cle = outil + couleur) pour ne pas redessiner a chaque nouvelle tache designee
- `mat.texture_filter = TEXTURE_FILTER_NEAREST` pour un rendu net (pixel art), pas flou comme le ferait le filtrage par defaut sur une si petite image

## Sprint 27 — Arbres plus grands (branches/feuillage), tronc inchange

- [x] Branches plus longues et un peu plus nombreuses, grappes de feuilles a leurs extremites agrandies
- [x] Feuillage (chene/fruitiers "touffu", bouleau "fin", sapin "conique") plus gros/fourni et etale plus haut au-dessus du tronc
- [x] Fruits repartis sur une plage verticale plus large pour rester coherents avec le feuillage desormais plus haut (arbres fruitiers)
- [x] Hauteur totale du sapin remontee (1.6 -> 1.85) ; le tronc visuel du sapin reste une fraction fixe de cette valeur (25%), donc n'allonge que tres legerement
- [x] Tronc du chene/bouleau/arbres fruitiers **volontairement inchange** (aucune modification de `_build_trunk` ni du champ `hauteur` de ces especes) - toute la hauteur supplementaire vient de la couronne (branches + feuillage), pas du tronc
- [ ] A tester dans Godot

### A tester

1. Regarde plusieurs chenes/bouleaux : la silhouette globale doit paraitre plus haute qu'avant (couronne plus etoffee et plus haute), mais le tronc doit avoir exactement la meme taille qu'avant ce sprint
2. Regarde un sapin : doit paraitre un peu plus haut, tronc toujours tres court (pas de retour du "tronc trop long")
3. Regarde un arbre fruitier (pommier/oranger/cerisier) : couronne plus grande, fruits toujours bien repartis dans le feuillage (pas en-dessous ni flottant loin au-dessus)
4. Verifie que Couper/Cueillir visent toujours bien le bon arbre au clic (la detection au clic n'a pas change, mais autant verifier apres un changement visuel)
5. Verifie que les performances restent correctes avec plusieurs arbres a l'ecran (un peu plus de geometrie par arbre : branches/feuilles/niveaux de cone en plus)

### Notes techniques Sprint 27

- Aucune modification de `_build_trunk()` : le tronc de "touffu"/"fin" reste directement egal a `species["hauteur"]` comme avant, et cette valeur n'a pas ete touchee pour chene/bouleau/arbres fruitiers dans `TreeSpecies.gd`
- `_build_branches()` : `branch_count` 3-5 -> 4-6, `branch_length` 0.35-0.55 -> 0.5-0.8, point de depart des branches parfois legerement au-dessus du sommet du tronc (`trunk_top_y + randf_range(-0.25, 0.15)` au lieu de toujours en-dessous) pour que la couronne s'eleve sans agrandir le tronc
- `_build_foliage_touffu()`/`_build_foliage_fin()` : rayon des blobs de feuillage et plage verticale (au-dessus de `top_y`, donc au-dessus du tronc inchange) augmentes, nombre de blobs et de feuilles par grappe augmentes
- `_build_foliage_conique()` (sapin) : un niveau de cone de plus en moyenne (4-5 -> 5-6), base des cones un peu plus large (0.42 -> 0.48) ; la hauteur totale suit `TreeSpecies.SPECIES[sapin].hauteur` (remontee), le tronc visuel restant une fraction fixe et donc quasi inchange
- `TreeSpecies.gd` : seul le champ `hauteur` du sapin a change (1.6 -> 1.85) ; celui de chene/bouleau/arbres fruitiers est explicitement laisse tel quel (commente pour eviter qu'un futur sprint le modifie par erreur en pensant "augmenter la hauteur")

## Sprint 28 — Prototype de nain 3D (scene separee, aucun fichier du jeu touche)

- [x] L'utilisateur n'aime pas le sprite 2D actuel des nains, souhaite explorer un "vrai" objet 3D - decide de proceder par prototype separe pour ajuster au fur et a mesure sans risquer de casser le jeu principal
- [x] Nouvelle scene `scenes/prototypes/DwarfModel3DPrototype.tscn` + script `scripts/prototypes/DwarfModel3D.gd`, independants de `Dwarf.gd`/`Main.tscn` (aucun des deux n'est modifie)
- [x] Nain low-poly construit avec les memes primitives que le reste du monde (cylindres/boites/spheres, couleurs unies non eclairees) : jambes courtes + bottes, torse, ceinture, bras + mains, tete, cheveux, barbe - reutilise les 4 couleurs personnalisables existantes (cheveux/barbe/vetements/armure, voir Dwarf.gd Sprint 16)
- [x] Script en `@tool` : le modele apparait des l'ouverture de la scene dans l'editeur (pas besoin de lancer le jeu), toutes les couleurs et proportions sont des champs exportes reglables dans l'Inspecteur, une case a cocher ("Rebuild In Editor") regenere le modele apres un changement
- [ ] A essayer/ajuster dans Godot

### A tester

1. Ouvre `scenes/prototypes/DwarfModel3DPrototype.tscn` dans Godot (double-clic dans le panneau FileSystem) : le nain 3D doit apparaitre directement dans la vue, sans avoir besoin d'appuyer sur Jouer
2. Selectionne le noeud "DwarfModel3D" dans l'arborescence : les groupes "Couleurs" et "Proportions" doivent apparaitre dans l'Inspecteur a droite
3. Change une couleur ou une proportion, puis coche la case "Rebuild In Editor" (groupe "Debug") : le modele doit se regenerer immediatement avec la nouvelle valeur
4. Verifie que ni `Main.tscn` ni `Dwarf.gd` n'ont change de comportement - le jeu principal doit tourner exactement comme avant ce sprint

### Notes techniques Sprint 28

- Rien dans `Dwarf.gd`/`Main.tscn`/`ActionController.gd` n'a ete touche - ce sprint est purement additif (2 nouveaux fichiers), zero risque de regression sur le jeu existant
- `DwarfModel3D.gd` est annote `@tool`, ce qui le fait s'executer aussi dans l'editeur Godot (pas seulement en jeu) - necessaire pour previsualiser/ajuster sans lancer la scene a chaque fois. Chaque noeud genere recoit un `owner` (`get_tree().edited_scene_root`, uniquement en mode editeur via `Engine.is_editor_hint()`) pour etre visible/persistant dans l'arborescence de la scene ouverte
- Materiaux `StandardMaterial3D` avec `shading_mode = SHADING_MODE_UNSHADED` (couleur plate, non eclairee), coherent avec le reste du monde (terrain, arbres, decorations, outils - voir `Forest.gd/_flat_material` et `Dwarf.gd/_make_tool_mesh`)
- Si le style convient a l'usage, l'etape suivante serait de porter cette construction dans `Dwarf.gd` (nouvelle fonction, en remplacement optionnel du sprite existant `_build_appearance`) - decision a prendre APRES avoir vu/ajuste le prototype, pas encore faite
- Proportions de depart pensees "trapues" (jambes courtes, grosse tete) pour rester dans l'esprit nain, mais tout est expose dans l'Inspecteur pour etre corrige a l'oeil

## Sprint 28bis — Torse elargi, jambes raccourcies, visage (yeux/nez/bouche)

- [x] Torse elargi (0.34 -> 0.44) et jambes raccourcies (0.34 -> 0.26) pour un aspect plus trapu de nain
- [x] Ecartement des jambes/bottes desormais proportionnel a la largeur du torse (au lieu d'une valeur fixe), pour rester bien positionnees sous un torse plus large
- [x] Cheveux agrandis et recentres (etaient trop discrets/trop en arriere)
- [x] Visage ajoute : yeux (2 petites spheres sombres), nez (petite sphere protuberante), bouche (fine boite sombre) - places sur l'avant de la tete, du meme cote que la barbe
- [ ] A essayer/ajuster dans Godot

### A tester

1. Ouvre `scenes/prototypes/DwarfModel3DPrototype.tscn` : le nain doit paraitre plus trapu (torse large, jambes courtes)
2. Verifie que le visage est lisible depuis la camera par defaut : yeux et nez visibles, bouche probablement en partie cachee par la barbe (attendu)
3. Essaie de changer `head_radius` ou `torso_width` dans l'Inspecteur (case "Rebuild In Editor") : le visage doit rester bien positionne sur la tete (les formules sont proportionnelles a `head_radius`)

### Notes techniques Sprint 28bis

- `EYE_COLOR`/`MOUTH_COLOR` sont des constantes fixes (pas des champs `@export`) pour ne pas surcharger l'Inspecteur avec des couleurs secondaires - faciles a exposer plus tard si besoin d'ajustement fin
- Le nez reutilise `skin_color` (legerement assombri) plutot qu'une couleur dediee, pour rester coherent avec la tete sans ajouter de parametre
- Toutes les positions du visage sont exprimees en fraction de `head_radius`, donc la fonction reste correcte si `head_radius` change dans l'Inspecteur (pas de valeurs absolues codees en dur)

## Sprint 28ter — Finalisation du skin de base (torse trapeze, bras musclus, tete ovale, cheveux courts, yeux avec blanc, sourcils)

- [x] Cheveux : corrige un bug ou ils etaient presque invisibles (sphere trop enfoncee dans la tete), puis redessines en "enveloppe" courte pres du crane (`hair_size`/`hair_lift`/`hair_back_offset` exposes dans l'Inspecteur) plutot qu'une boule au sommet
- [x] Torse remplace par un vrai tronc de piramide (`_make_trapezoid_mesh`, via `SurfaceTool`) : plus large aux epaules qu'a la taille (silhouette en V), epaules elargies au fil des retours (0.34 -> 0.58)
- [x] Bras muscles : cylindre + renflement du biceps (petite sphere superposee), au lieu d'un simple cylindre fin
- [x] Tete ovale (`head_height_factor`) plutot que ronde ; ajout de `_head_surface_radius()` (geometrie d'ellipsoide) pour placer correctement les elements du visage sur une tete non-spherique
- [x] Bouche reconstruite en vraie courbe (segments de boites fines reliees bout a bout, factorise dans `_build_curve_segments()`) plutot qu'une boite plate ou des perles isolees ; couleur/position/profondeur ajustees sur plusieurs retours
- [x] Yeux : ajout d'un "blanc" (sclere, sphere aplatie) derriere la pupille, forme ovale (scale X/Y), plusieurs corrections (pupille invisible car cachee derriere le blanc, strabisme du a une tentative de rotation suivant la courbure de la tete puis annulee) - version finale simple : blanc et pupille partagent exactement les memes coordonnees X/Y, seule la pupille est legerement avancee en Z
- [x] Sourcils ajoutes (meme technique de courbe que la bouche, `_build_curve_segments()` reutilise), couleur assortie aux cheveux
- [x] Correction d'un bug editeur Godot ("Node not found" en boucle) : suppression immediate (`remove_child`+`free()`) au lieu de `queue_free()` differe, et nom explicite/stable donne a chaque noeud genere
- [x] Confirme par l'utilisateur ("je pense que le skin de base est bien", 2026-07-02)

### Notes techniques Sprint 28ter

- `_head_surface_radius(dy)` calcule le rayon horizontal reel de la surface ovale de la tete a une hauteur donnee (geometrie d'ellipsoide : `head_radius * sin(phi)`), evite de deviner un facteur fixe pour placer bouche/sourcils sans qu'ils s'enfoncent dans le visage
- `_build_curve_segments(pts, thickness, color, name_prefix)` : fonction commune extraite de l'ancienne `_build_mouth`, reutilisee pour les sourcils - relie une liste de points par des segments (boites tournees suivant la tangente locale, leger chevauchement) pour un vrai trait courbe continu
- Le "blanc" de l'oeil est une sphere fortement aplatie en Z (`scale.z = 0.55`, comme un galet colle sur le visage) plutot qu'une bille complete, sinon elle depasse devant la pupille et la cache entierement - piege rencontre puis corrige
- Une tentative de corriger un effet de "strabisme convergent" en orientant chaque oeil (rotation Y) vers sa direction radiale par rapport au centre de la tete a en fait cause un strabisme DIVERGENT (la pupille derivait vers la tempe) - abandonnee au profit d'une version sans rotation, ou le blanc et la pupille partagent exactement les memes coordonnees X/Y (centrage garanti par construction, pas besoin de rotation)
- Idee notee pour plus tard (pas commencee) : lier la forme de la bouche (sourire/grimace) au bonheur du nain, une fois ce modele integre a `Dwarf.gd`

## Sprint 28quater — Systeme de variations (cheveux/barbe/corpulence/tenue) + grille de demonstration 3x3

- [x] `hair_style` (8 formes : Chauve, Court, Attache, Iroquois, Touffu, Frange basse, Longs, Tresse) et `beard_style` (5 formes de depart) exposes en `@export_enum`, chacun aiguillant vers sa propre fonction de construction
- [x] `corpulence` (0.7-1.4) : multiplicateur de largeur/epaisseur du torse/des membres, independant de `torso_shoulder_width` (deja reglable separement)
- [x] `outfit_style` (4 tenues de depart : Tunique simple, Tunique + cape, Armure legere, Armure lourde) - voir Sprint 28sexies pour le detail des pieces
- [x] Bouton "Randomiser" (`randomize_variation`, case a cocher auto-decochee) : tire une combinaison au hasard et reconstruit
- [x] Nouvelle scene `scenes/prototypes/DwarfVariationGridPrototype.tscn` + script `scripts/prototypes/DwarfVariationGrid.gd` : grille 3x3 de 9 `DwarfModel3D` independants, chacun randomise, avec un numero flottant au-dessus pour identifier precisement un individu lors d'un retour ("le n°5 a tel probleme")
- [ ] A tester dans Godot

### Notes techniques Sprint 28quater

- La grille instancie `DwarfModel3D.gd` par script (`set_script`) plutot que de dupliquer la logique de forme - appelle directement `_randomize_variation()` puis `_rebuild()` sur chaque instance (GDScript n'a pas de vraie visibilite privee malgre le prefixe `_`)
- Chaque coiffure/barbe est une fonction dediee (`_build_hair_short`, `_build_hair_bushy`, etc.), aiguillee par un `match` dans `_build_hair`/`_build_beard` - facilite l'ajout de nouveaux styles sans toucher aux existants

## Sprint 28quinquies — Extensions barbe + couleurs naturelles aleatoires + corrections visuelles

- [x] Largeur de barbe (`beard_width`, 0.6-1.6) combinable avec tous les styles
- [x] 3 nouveaux styles de barbe : Bouc, Moustache (refaite en "fer a cheval" plus tard, voir Sprint 28octies), Fourchue (deux meches divergentes)
- [x] Couleurs de cheveux/barbe/sourcils tirees au hasard dans une palette naturelle (`NATURAL_HAIR_COLORS` : noir, gris, blond, roux, chatain), independamment l'une de l'autre - les sourcils suivent automatiquement la couleur des cheveux
- [x] Correction : casque ne couvrait pas l'arriere du crane (ajout d'une 2e piece "HelmetGuard" dediee a la nuque)
- [x] Correction : bug "Frange basse" qui ajoutait un 2e morceau de cheveux disjoint au lieu d'avancer la ligne de cheveux existante
- [x] Correction : coiffure "Touffu" qui avalait tout le visage (recul calcule a partir d'une limite avant explicite plutot que d'un facteur pense pour une sphere plus petite)
- [ ] A tester dans Godot

### Notes techniques Sprint 28quinquies

- Chaque style de barbe conique (Courte/Longue/Tressee/Fournie/Bouc) reutilise une fonction commune parametree (`_build_beard_shape`), Moustache/Fourchue ont leur propre forme dediee

## Sprint 28sexies — Tenues/armures completes + animations (marche/travail/combat/manger/dormir)

- [x] 4 tenues completes : Tunique simple (torse de base), Tunique + cape, Armure legere (plastron), Armure lourde (plastron + epaulieres + casque)
- [x] Jambes ET bras restructures en pivots (`LegPivot_L/R`, `ArmPivot_L/R`, noeuds vides a la hanche/l'epaule, membres suspendus dessous) - meme principe que l'ancienne silhouette articulee du Sprint 14 (avant le passage au sprite 2D)
- [x] `preview_animation` (`@export_enum` : Aucune, Marche, Travail, Combat, Manger, Dormir) joue en continu via `_process()`, y compris DANS L'EDITEUR (script `@tool`) - rotation sinusoidale des pivots, pas besoin de lancer la scene pour juger le mouvement
- [x] "Dormir" incline le corps entier a l'horizontale (`rotation.z`) - possible car ce modele est un vrai objet 3D, contrairement au sprite billboard qui ne pouvait que s'aplatir en echelle
- [x] "Manger" : les deux bras convergent vers le centre du corps (combinaison rotation X + Z) pour simuler les mains portees a la bouche, apres un premier essai (un seul bras) juge pas convaincant
- [ ] A tester dans Godot

### Notes techniques Sprint 28sexies

- `_leg_pivot_l/_r`/`_arm_pivot_l/_r` sont gardes en variables d'instance (remplis a chaque `_build_legs()`/`_build_arms()`) pour que `_process()` les anime sans recherche par nom a chaque frame
- Etat "Aucune" remet explicitement `rotation.z` du corps a 0 pour ne pas rester incline si on quitte "Dormir"
- Pensee explicitement avec la portabilite future vers `Dwarf.gd` en tete : ce modele etant un vrai objet 3D (pas un billboard), l'animation par rotation d'articulations redevient possible, contrairement au sprite (Sprint 15/16 de `Dwarf.gd`)

## Sprint 28septies — Systeme d'armes complet (5 configurations, materiaux, poses repos/combat)

- [x] 5 configurations (`weapon_loadout`) : 1 main, 2 mains, 1 main + bouclier, deux armes 1 main, arme a distance
- [x] Modeles generes : epee/masse/hache (1 et 2 mains, les 2 mains nettement agrandies), bouclier rond/carre, arc (vraie courbe, meme technique que la bouche/les sourcils)/arbalete
- [x] `weapon_material` (Bois, Cuivre, Fer, Acier - `MATERIAL_COLORS`) determine la couleur de la tete/lame ; l'arc reste toujours en bois, l'arbalete toujours en metal (le tirage aleatoire exclut "Bois" du pool)
- [x] Position "Repos" : armes 1 main a la ceinture, armes 2 mains/boucliers/armes a distance dans le dos (poignee vers le haut, tete/lame vers le bas, inclinaison arriere moderee - plusieurs corrections de sens/angle)
- [x] Position "Combat" : main droite = arme principale (a deux mains si besoin, l'autre bras suit le mouvement), main gauche = bouclier si applicable, devant le nain
- [x] `_effective_weapon_pose()` : l'animation en cours a le dernier mot sur la pose (Combat force les armes en main, toute autre animation en mouvement force le rangement), pour eviter des armes brandies pendant "Manger"/"Marche"
- [x] Grip repense au milieu de la poignee (epee) ou tout en bas (masse/hache, "tenues au bout du manche") plutot qu'a un seul point fixe, pour un rendu "tenu en main" credible
- [ ] A tester dans Godot

### Notes techniques Sprint 28septies

- `_attach_to_belt`/`_attach_to_back`/`_attach_to_hand` : 3 fonctions de positionnement reutilisees par tous les types d'armes/bouclier, selon la position voulue
- `_pose_two_handed_grip()`/`_pose_shield_arm()` : poses statiques du bras libre, respectees aussi PENDANT l'animation "Combat" (le bras gauche suit le mouvement du droit pour une arme 2 mains, au lieu d'etre ecrase par l'etat generique de `_process()`)
- Personnage oriente vers +Z (voir `_build_face`) : plusieurs bugs de signe rencontres et corriges sur les rotations d'armes (pointaient vers l'arriere/la tete au lieu de l'avant)

## Sprint 28octies — Grille de verification unifiee 6x6 + corrections finales

- [x] Grille 3x3 remplacee par une grille 6x6 (36 nains) en mode par defaut "Verification complete" : `_randomize_variation()` etendu pour tirer AUSSI la configuration d'armes complete (avant, seul le materiau l'etait) ; chaque colonne joue une animation differente parmi les 6 disponibles, pour voir variete ET animations en un seul chargement de scene
- [x] Themes d'habits (`CLOTHING_THEMES` : gris, noir, vert, rouge, bleu, marron, toutes des teintes mates) - chemise et pantalon (nouveau champ `pants_color`, avant fixe a `clothing_color * 0.85`) derives independamment du meme theme
- [x] Manteau et gants ajoutes comme accessoires independants de `outfit_style` (`wear_coat`/`wear_gloves`, groupe "Accessoires"), tires au hasard ; manteau avec epaules arrondies et rangee de boutons devant
- [x] Un peu de "texture" sur la coiffure de base : 15 petites "meches" (spheres) superposees sur la sphere principale, legerement teintees (variation aleatoire de couleur), pour casser la silhouette parfaitement ronde
- [x] Epaules du corps arrondies (petite sphere a la jonction torse/bras, evite l'angle droit visible)
- [x] Moustache refaite en "fer a cheval" (barre + deux meches tombantes de chaque cote de la bouche) suite a un retour utilisateur negatif sur la version d'origine (simple barre)
- [x] Plusieurs corrections de bugs trouves via la grille de verification : barbe qui pouvait former un enorme triangle a largeur aleatoire elevee (top_radius plafonne + reduit), gris des cheveux trop proche des tons metalliques des armes, blond quasi invisible sur la peau (assombri), casque qui laissait une "frange" de cheveux colores visible (les cheveux sont desormais masques quand un casque complet est porte)
- [ ] A tester dans Godot

### Notes techniques Sprint 28octies

- Le mode "Demonstration armes" (9 configurations fixes couvrant les 5 categories x2 poses) et "Variations aleatoires" (grille 3x3 d'origine) restent disponibles via le menu deroulant `Grid Mode`, en plus du nouveau mode par defaut
- Toute la randomisation (apparence, armes, materiau, theme d'habits, accessoires) est centralisee dans `_randomize_variation()`, appelable independamment de la grille (case "Randomiser" sur un nain seul)

## Sprint 28novies — Design de base des nains valide

- [x] Confirme par l'utilisateur ("on a fini le design des nains", 2026-07-02) - cloture l'etape de prototypage visuel independant
- [x] Prochaine etape : integration dans le jeu principal, voir Sprint 28decies ci-dessous

## Sprint 28decies — Integration du nain 3D dans le jeu principal (remplacement du sprite)

- [x] `Dwarf.gd` / `_build_appearance()` instancie desormais `DwarfModel3D` (scripts/prototypes/DwarfModel3D.gd) comme enfant de `Body`, a la place du Sprite3D/normal map/masque de recolor/shader (Sprint 15/15bis/16, entierement retires)
- [x] Les 4 couleurs personnalisables existantes (hair/beard/clothing/armor_color, deja distinctes par nain dans `Main.tscn`) sont conservees et transmises au modele ; le reste de l'apparence (coiffure/barbe/tenue/corpulence) est tire au hasard via `DwarfModel3D._randomize_variation()` a la creation de chaque nain
- [x] Pas d'armes dans le jeu principal pour l'instant (`weapon_loadout` force a "Aucune") - le jeu n'a pas encore de systeme de combat, viendra avec la Phase 4
- [x] Animations marche/travail/repos/repas repilotees sur `DwarfModel3D.preview_animation` ("Marche"/"Travail"/"Dormir"/"Manger"/"Aucune") a la place des anciens hacks position/echelle penses pour un billboard (bob de marche, tremblement au travail, aplatissement au repos, bob en mangeant) - le nain tourne desormais reellement vers sa direction de marche (avant sans effet visuel, le sprite billboard ignorait la rotation)
- [x] L'outil d'action (pioche/hache/marteau, Sprint 17) est rattache a la main droite du modele (`DwarfModel3D._hand_r`) au lieu d'un offset fixe anime a la main - suit naturellement le bras pendant "Travail"
- [x] Indicateurs "Z z z" (repos) et baie (repas) repositionnes pour la taille du nouveau modele (plus petit qu'un sprite de 1.6 unite)
- [x] `Main.tscn` nettoye : suppression de `sprite_texture` sur les 3 nains et de la ressource `nain.png` devenue inutile
- [x] Teste et confirme par l'utilisateur dans Godot ("ok c'est bien", 2026-07-02)

### Notes techniques Sprint 28decies

- `DwarfModel3D.gd` reste dans `scripts/prototypes/` (pas duplique) - `Dwarf.gd` le precharge directement, meme pattern que `DwarfVariationGrid.gd` ; la scene de prototype isolee reste disponible pour des reglages fins independants du jeu principal
- Acces aux membres prefixes `_` du script attache (`_hand_r`, `_randomize_variation()`, `_rebuild()`) depuis `Dwarf.gd` malgre le typage statique `Node3D` de la variable : GDScript n'a pas de vraie visibilite privee, comportement deja valide par `DwarfVariationGrid.gd`
- Les assets/fichiers du sprite 2D (`nain.png`, `nain_normal.png`, `nain_mask.png`, `shaders/dwarf_recolor.gdshader`) sont laisses en place, orphelins et inutilises, plutot que supprimes - meme choix que les fichiers orphelins du Sprint 23quater

## Sprint 28undecies — Redimensionnement (nains, arbres, buissons)

- [x] Nains reduits d'environ 20% (`Dwarf.model_scale = 0.8`, applique au modele 3D - sans effet sur la logique de jeu, l'origine du modele reste au niveau des pieds)
- [x] Arbres agrandis d'environ 30% (`Forest.size_multiplier = 1.3`, multiplie dans le jitter d'echelle deja existant)
- [x] Buissons/plantes reduits d'environ 10% (`BerryBushes.size_multiplier = 0.9`)
- [x] Teste et confirme par l'utilisateur

### Notes techniques Sprint 28undecies

- Les trois echelles sont ancrees a la position au sol de chaque objet (origine du modele = pieds/base) - redimensionner ne decale rien verticalement
- Indicateurs (sommeil/repas) et position de l'outil dans la main sont eux aussi mis a l'echelle de `model_scale` dans `Dwarf.gd`, pour rester correctement positionnes sur un nain plus petit

## Sprint 28duodecies — Noms de nains aleatoires (prenom + clan)

- [x] `scripts/data/creatures/nains/NainNames.gd` : table de prenoms puisee dans le Dvergatal (catalogue des nains de l'Edda poetique, domaine public - la meme source dont Tolkien a tire Thorin/Fili/Kili/Bombur...) completee de prenoms feminins authentiques du vieux norrois, et une table de noms de clan inventes ("Barbe-de-Fer", "Poing-de-Granit"...)
- [x] `Dwarf.dwarf_name` genere automatiquement au `_ready()` si laisse vide (`NainNames.random_name()`), au lieu des noms fixes "Nain 1/2/3"
- [x] `Main.tscn` nettoye des noms fixes
- [x] Teste et confirme par l'utilisateur

### Notes techniques Sprint 28duodecies

- Choix de source deliberement du domaine public (Edda poetique, XIIIe siecle) pour obtenir le style "nom de nain classique" sans reprendre de noms de personnages d'une oeuvre protegee
- `random_name()` est un simple tirage independant prenom/nom de clan (pas de logique d'unicite entre nains pour l'instant - deux nains pourraient theoriquement partager le meme nom)

## Sprint 28tredecies — Portraits 3D et refonte complete de la fiche personnage

- [x] Chaque bouton de portrait affiche desormais un vrai rendu 3D de la tete du nain (mini `SubViewport` isole + camera cadree), plus son nom en permanence a cote (avant : cercle colore generique, nom visible seulement en ouvrant la fiche)
- [x] Fiche de personnage agrandie (police bien plus grosse) et reorganisee en 3 onglets : **Etat general** (nom, PV/Energie/Faim/Soif, tache en cours), **Caracteristiques**, **Competences**
- [x] "Soif" ajoutee comme jauge placeholder (toujours pleine) - aucune mecanique de soif n'existe encore cote gameplay, meme traitement que "PV" depuis le Sprint 9
- [x] Onglet Competences : nom de la competence + niveau (juste le chiffre) + barre de progression vers le niveau suivant, au lieu d'une ligne de texte
- [x] Icone de portrait agrandie, nom lisible (fond sombre semi-transparent derriere le texte blanc), fiche elargie pour que les 3 onglets soient visibles sans fleches de defilement
- [x] Fermeture de la fiche par Echap ou en recliquant sur le portrait deja ouvert
- [x] Anneau bleu au sol autour des pieds du nain dont la fiche est ouverte
- [x] Teste et confirme par l'utilisateur

### Notes techniques Sprint 28tredecies

- Portrait 3D : `SubViewport` avec `own_world_3d = true` contenant une copie du `DwarfModel3D` du nain (apparence copiee via une liste explicite de champs, pas une reflexion generique, pour ne jamais copier par erreur une propriete de transform) + une `Camera3D` cadree sur le buste
- Panel de fiche : `StyleBoxFlat` sombre + `Theme` assigne au panel (cascade la couleur du texte a tous les enfants) pour rester lisible quel que soit l'arriere-plan 3D
- Deux bugs corriges pendant ce sprint, tous deux de la meme famille ("noeud pas encore pret") :
  - L'anneau de selection ne s'affichait pas du tout : `add_child()` appele depuis `_ready()` echouait silencieusement ("Parent node is busy setting up children") - corrige avec `add_child.call_deferred(...)`
  - La camera du portrait plantait avec l'erreur "Node not inside tree" : `look_at()` etait appele AVANT `add_child()` (une camera hors de l'arbre n'a pas de transform global valide) - corrige en inversant l'ordre des deux lignes
  - Lecon generale : quand un noeud genere par code "ne fait rien" sans plantage visible, verifier d'abord la console pour une erreur silencieuse de ce type avant de soupconner un probleme de position/materiau

## Sprint 29 — Correction du bug de materiaux VoxelWorld (des milliers d'erreurs en debogueur)

- [x] Bug trouve pendant le sprint precedent (sans lien avec l'anneau de selection) : `VoxelWorld.rebuild_mesh()` assignait un materiau a des indices de surface fixes (0 a 10), alors qu'un `SurfaceTool` sans aucune face ne produit PAS de surface au moment du `commit()` - des qu'un type de bloc etait absent de la carte (frequent sur une petite carte), les indices reels se decalaient et l'appel plantait ("Index p_idx out of bounds"), en continu
- [x] Corrige : les materiaux sont maintenant assignes au VRAI indice de surface obtenu apres chaque `commit()` (compte a part, qui n'avance que si une surface a effectivement ete ajoutee), plus a un indice fixe suppose
- [x] Teste et confirme par l'utilisateur (plus aucune erreur dans le debogueur)

### Notes techniques Sprint 29

- Lecon generale (meme famille que les corrections du Sprint 28tredecies) : dans Godot, une operation "vide" (SurfaceTool sans geometrie, noeud pas encore dans l'arbre...) echoue souvent silencieusement plutot que de lever une exception bloquante - toujours verifier la console en cas de comportement inattendu avant de chercher ailleurs

## Sprint 30 — Cycle jour/nuit

- [x] Nouveau `scripts/systemes/DayNightCycle.gd`, cycle complet (matin rose -> jour bleu -> soir rouge sombre -> nuit gris tres sombre) avec transitions continues (aucune bascule brutale)
- [x] Rotation continue de la lumiere directionnelle (le "soleil"), qui balaie le ciel en diagonale et passe sous l'horizon la nuit - fait naturellement suivre les ombres
- [x] Lune fixe (sphere simple, non eclairee) qui apparait uniquement la nuit, en fondu
- [x] `cycle_duration_seconds` reglable dans l'inspecteur (30s pour les tests, a ralentir pour la version definitive - simple changement de valeur)
- [x] Teste et confirme par l'utilisateur
- [x] Purement visuel (aucun lien avec le sommeil des nains ou toute autre mecanique de jeu)

### Notes techniques Sprint 30

- Les couleurs (ciel, lumiere, fog) sont interpolees en continu entre 4 phases reparties a intervalles egaux sur le cycle
- La rotation du soleil N'utilise PAS ce systeme de phases (risque de mauvais sens de rotation avec une interpolation par quaternions entre positions disjointes) : une seule formule continue base directement sur l'avancement du cycle, un tour complet par cycle

## Sprint 30bis — Ombres reelles et obscurite nocturne complete

- [x] Cause trouvee suite a un signalement de l'utilisateur ("ombres quasi invisibles", "il ne devrait plus y avoir de lumiere sur la carte la nuit") : tous les materiaux du terrain (`VoxelWorld.gd`), des arbres (`Forest.gd`) et des decorations de sol (`GroundDecoration.gd`, `BerryBushes.gd`) etaient en mode "non eclaire" (`SHADING_MODE_UNSHADED`) - un materiau non eclaire ignore totalement la lumiere ET les ombres, quel que soit le cycle jour/nuit
- [x] Ces materiaux passent en eclairage reel (`roughness = 1.0`, `metallic = 0.0` pour garder le rendu plat/mat sans reflet) - le terrain recoit desormais vraiment les ombres portees et s'assombrit la nuit
- [x] `DayNightCycle.gd` pilote maintenant aussi la lumiere ambiante (`environment.ambient_light_energy`), a 0.0 exactement la nuit (comme la lumiere directionnelle) - plus aucune lumiere sur la carte la nuit, comme demande
- [x] Les nains (modele 3D) restent volontairement non eclaires pour l'instant : passer leur materiau en eclaire casserait le rendu du portrait 3D dans la fiche personnage (mini-monde isole sans source de lumiere) - point identifie, pas encore traite
- [x] Teste et confirme par l'utilisateur

### Notes techniques Sprint 30bis

- Lecon pour la suite : toute nouvelle fabrique de materiau devrait par defaut utiliser l'eclairage reel (ou documenter explicitement pourquoi elle reste non eclairee) - un materiau non eclaire sort silencieusement un objet de tout le systeme jour/nuit, sans que ca se voie en le regardant seul

## Sprint 31 — Systeme meteo (Normal / Brouillard / Pluie / Neige)

- [x] Nouveau `scripts/systemes/WeatherSystem.gd` : alterne aleatoirement entre 4 etats a intervalles de 15 a 35 secondes (rythme de test, "Normal" deux fois plus frequent que les 3 autres)
- [x] Pluie et neige : vraies particules qui tombent (`GPUParticles3D`), couvrant toute la carte
- [x] Brouillard : densite de fog augmentee ; pluie/neige assombrissent legerement la lumiere (ciel couvert), par-dessus l'etat du cycle jour/nuit sans l'ecraser
- [x] Purement visuel (aucun effet sur le gameplay) pour l'instant
- [x] Teste et confirme par l'utilisateur

### Notes techniques Sprint 31

- `WeatherSystem` est place juste apres `DayNightCycle` dans `Main.tscn` : Godot traite les enfants dans l'ordre de l'arbre, donc son `_process()` s'execute juste apres celui du cycle jour/nuit et peut ajouter ses propres effets (fog, multiplicateur de lumiere) sans les figer en dur ni entrer en conflit
- Particules generees entierement par code (pas de scene/ressource dediee) : necessite de definir `visibility_aabb` a la main, sans quoi Godot peut considerer les particules hors-champ et ne jamais les afficher (pas d'etape editeur "Generate Visibility AABB" possible pour un noeud cree au runtime)

## Sprint 32 — Selection multiple de nains

- [x] Glisser-clic sur la carte (uniquement quand aucun mode d'action Miner/Couper/Cueillir/Construire n'est actif) : dessine un rectangle et selectionne tous les nains a l'interieur au relachement
- [x] Ctrl ou Maj + clic sur un portrait (liste a droite) : ajoute/retire ce nain de la selection sans ouvrir sa fiche
- [x] Un clic simple sur un portrait garde le comportement historique (ouvre/ferme sa fiche, remplace la selection par ce seul nain)
- [x] Chaque nain selectionne a son anneau bleu au sol, et son portrait est legerement teinte dans la liste
- [x] Purement visuel pour l'instant (aucune action groupee disponible - viendra plus tard, une fois un besoin concret identifie)
- [x] Teste et confirme par l'utilisateur

### Notes techniques Sprint 32

- Le glisser-carte coexiste avec le clic simple "Inspecter" (Sprint 25) deja en place quand aucun mode n'est actif : la decision clic-simple vs glisser est prise au relachement de la souris (seuil de 6 pixels), pas a l'appui, pour eviter tout affichage parasite d'un panneau d'inspection avant qu'un vrai glisser ne soit detecte
- `CharacterSheetUI.gd` : l'ancien `selected_dwarf` unique devient `selected_dwarves` (un ensemble), et l'ancien anneau de selection partage devient un anneau par nain (`selection_rings`) - meme principe que les portraits/fiches, deja construits dynamiquement par nain
- `ActionController.gd` doit maintenant referencer `CharacterSheetUI` (`%CharacterSheetUI`) pour lui transmettre la selection issue du glisser - a necessite d'ajouter `unique_name_in_owner` sur ce noeud dans `Main.tscn`

---

# Phase 1 — Nains de base et environnement : FINALISEE (2026-07-02)

Cette etiquette regroupe tout le travail effectue jusqu'ici (l'ancien "MVP" du Sprint 0 a 10, et l'ancienne "Phase 2 - Colonie complete" du Sprint 11 au Sprint 32 ci-dessus) sous un seul intitule, a la demande de Francois : **"Phase 1 - nains de base et environnement"**. Elle couvre : le terrain en blocs, la navigation camera, un puis plusieurs nains autonomes (taches, besoins, caracteristiques, competences, fiche de personnage complete, selection multiple), la vegetation et le decor (arbres par espece, buissons/plantes, decorations de sol, filons souterrains), et l'environnement (cycle jour/nuit, meteo, eclairage/ombres reels).

**Phase 2 (a venir) : Ateliers & artisanat.** D'apres la decision de Francois du 2026-07-02, l'equipement (habits/armures/armes utilisables et fabricables, pas seulement l'apparence du modele 3D) sera traite avec ce systeme d'ateliers, plutot qu'en sprint isole. Le "Bonheur" (stat existante mais sans effet reel) est explicitement reporte a beaucoup plus tard.

Voir `Forgotten_Caves_Sprints.xlsx` (dossier parent) pour le detail phase par phase mis a jour.
