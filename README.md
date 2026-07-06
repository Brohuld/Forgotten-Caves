# Forgotten Caves

Jeu de gestion de colonie de nains en 3D par blocs (voxels), inspiré de Dwarf Fortress / RimWorld.

## Stack technique

- Moteur : Godot 4.7 (GDScript)
- Rendu : Forward+ (3D)
- Plateformes cibles : Windows, macOS

## Structure du projet

`scripts/` est rangé par catégorie (depuis le Sprint 22) :

```
ForgottenCavesGame/
├── project.godot        # Fichier de configuration du projet
├── scenes/
│   └── Main.tscn         # Scène de départ : caméra + lumière + grille de blocs + tous les acteurs
├── scripts/
│   ├── data/             # Tables de données statiques, éditables (matériaux, climats, créatures)
│   ├── entites/          # Scripts de comportement des acteurs vivants (Dwarf, Forest, BerryBushes...)
│   ├── monde/            # Terrain et décor (VoxelWorld, GroundDecoration, cascades)
│   ├── ui/                # Interface (CharacterSheetUI)
│   └── systemes/          # Logique globale (ActionController, TaskQueue, Inventory, CameraRig, cycles)
└── assets/               # Modèles, textures, sons...
```

## Prise en main

1. Installer Godot 4.7 ou supérieur : https://godotengine.org/download
2. Ouvrir Godot, cliquer sur "Importer", sélectionner le fichier `project.godot`
3. Appuyer sur F5 (Run Project, pas F6 "Run Current Scene") pour lancer le jeu

## Contrôles caméra

- Déplacement : Z / Q / S / D
- Rotation : A et E (pas Q, déjà pris par le déplacement)
- Zoom : + et - (ou Ctrl+molette)
- Changer de niveau de profondeur (coupe façon Dwarf Fortress) : molette de la souris
- Angle de vue : maintenir le clic molette et glisser la souris
- Vitesse du temps : Espace (pause), F1/F2/F3 (x1/x2/x4)

## Suivi du projet

Le planning de sprints est dans `Forgotten_Caves_Sprints.xlsx` (dossier parent).

---

## Historique de développement

Le développement a dépassé les 85 sprints numérotés individuellement, ce qui rendait ce fichier illisible. **À partir de cette réorganisation (2026-07-04), l'historique est regroupé par paquet thématique plutôt que par numéro de sprint.** Les numéros de sprint ne sont plus l'identifiant principal (gardés ponctuellement entre parenthèses quand utile).

### 1. Fondations & MVP

Terrain en blocs (grille 3D, culling des faces cachées), navigation caméra (pan/rotation/zoom/niveau de profondeur), premier nain autonome, désignation de tâches (Miner/Couper), récolte + inventaire global, file de tâches par priorité de distance, construction multi-matériaux (bois/pierre/terre) par cliquer-glisser avec mur fantôme, besoins de base (faim/énergie), interface minimale (fiche personnage, icônes d'action). Session de validation de bout en bout confirmée — ce socle (MVP) est stable et n'a plus été remis en cause depuis.

**Notes utiles** : `Input.is_physical_key_pressed`/`event.physical_keycode` (position physique de la touche, pas le caractère affiché) pour que ZQSD/A/E fonctionnent en AZERTY. Le mur "fantôme" pendant la construction est un `MeshInstance3D` semi-transparent ajouté directement dans la scène 3D. Chaque tâche de construction a un id unique, le nain émet un signal à la fin (succès ou échec) pour que l'UI retire le bon fantôme sans dépendre du rendu du terrain.

**Écran de démarrage & graine reproductible (Sprint 80-83)** : avant `Main.tscn`, un premier écran (`StartMenu.gd`, scène de démarrage désignée dans `project.godot`) propose de saisir une graine (seed) de génération de carte — la même graine tapée deux fois reproduit exactement la même carte (relief/lacs/rivière/cascades), utile pour rejouer un bug précis pendant les tests. Champ laissé vide = carte aléatoire comme avant. La dernière graine utilisée est sauvegardée (`user://last_seed.txt`) et reproposée par défaut au lancement suivant.

**Bug Couper/Cueillir (RÉSOLU 2026-07-05)** : aucune icône de tâche n'apparaissait et l'arbre/buisson désigné n'était jamais réellement récolté. Cause réelle : l'évitement d'arbres pendant le déplacement du nain (`Dwarf.gd`) excluait mal la cible elle-même de ce calcul, l'empêchant de jamais l'atteindre physiquement.

### 2. Colonie & profils des nains

Passage à 3 nains simultanés (groupe Godot `"dwarves"`, plus de référence unique `%Dwarf`), chacun avec 6 caractéristiques aléatoires (Force/Agilité/Constitution/Intelligence/Beauté/Bonheur) purement informatives, 3 compétences (Minage/Bûcheronnage/Construction, table `SkillDefinitions.gd`) qui réduisent la durée de travail et augmentent la chance de ressource bonus, accessoires d'action (outil en main pendant le travail, "Z z z" flottant au repos, baie approchée de la bouche au repas).

**Bonheur** : stat existante, sans aucun effet de gameplay pour l'instant — reporté explicitement à beaucoup plus tard (décision 2026-07-02).

### 3. Apparence des nains

Trois générations successives : (a) silhouette procédurale articulée par code, (b) sprite 2D illustré avec normal map + recoloration par shader (masque de régions cheveux/barbe/vêtements/armure), (c) **abandon du sprite au profit d'un vrai modèle 3D low-poly** (`DwarfModel3D.gd`), développé dans une longue série de sprints de prototype isolé (`scenes/prototypes/`) avant intégration.

Le modèle 3D final couvre : coiffures/barbes multi-styles, corpulence réglable, 4 tenues (tunique simple/cape/armure légère/lourde), système d'armes à 5 configurations (1 main/2 mains/1 main+bouclier/deux armes/distance, non utilisé en jeu pour l'instant — viendra avec le combat en Phase 4), animations par rotation réelle des articulations (marche/travail/combat/manger/dormir), portraits 3D (mini `SubViewport` isolé par nain) et fiche personnage à 3 onglets (État général/Caractéristiques/Compétences). Noms générés aléatoirement (prénom norrois du Dvergatal, domaine public + clan inventé).

**Leçons Godot retenues** (récurrentes dans cette série) :
- Un `Sprite3D` en mode billboard ignore la rotation du nœud — les animations doivent passer par position/échelle, jamais par rotation, tant que le personnage est un billboard.
- Un shader spatial personnalisé n'a pas de billboard natif intégré (seul `BaseMaterial3D` sait le faire) — le billboard doit être refait à la main si on utilise un `material_override` shader.
- `add_child()` appelé dans `_ready()` peut échouer silencieusement ; `look_at()` appelé avant `add_child()` plante ("Node not inside tree"). Toujours vérifier la console avant de soupçonner autre chose.
- Les nains restent volontairement non éclairés (`SHADING_MODE_UNSHADED`) : les passer en éclairage réel casserait le rendu isolé du portrait 3D — identifié, pas encore traité.

**Statut** : intégration confirmée par l'utilisateur ; le design de base des nains est validé, plus de retour en arrière prévu sur ce socle visuel.

### 4. Interface & confort d'utilisation

Menu de construction en sous-menu matériau, fiche personnage progressive (PV/Faim/Énergie puis 3 onglets), fenêtre d'inspection au clic (nom + fruits restants pour un arbre/buisson, type de bloc/mur), icônes de tâche flottantes en forme d'outil (pioche/hache/panier, dessinées pixel par pixel en mémoire — jamais de fichier image externe, pour éviter le bug de blocs blancs rencontré avec des textures de filons), sélection multiple de nains (glisser-rectangle + Ctrl/Maj+clic sur portrait, anneau bleu au sol), panneau d'information au survol, boutons de vitesse du temps (Pause/x1/x2/x4, avec raccourcis clavier), onglet Équipement en lecture seule (stub, pas encore un vrai système d'artisanat).

**Note** : toute icône/marqueur généré à l'exécution doit être dessiné via `Image.create`/`set_pixel` en mémoire plutôt que chargé depuis un fichier — convention adoptée après un bug de rendu (textures de filons, voir paquet 6) jamais totalement élucidé.

**Icônes de tâche retracées + tailles de police (2026-07-05, à confirmer en jeu)** : les icônes hache/pioche ont été entièrement retracées suite à un bug de rendu identifié (l'ancien traçage de trait épais "en tampon circulaire" recouvrait complètement les petites formes voisines sur un canevas de 40x40 — remplacé par un traçage en polygones via `_stroke_segment`/`_fill_quad`). Toutes les tailles de police de l'interface ont été augmentées : un `Theme` Godot global (`themes/DefaultTheme.tres`, référencé dans `project.godot`) fixe la taille par défaut pour tout élément sans taille explicite, en complément des tailles explicites déjà présentes (relevées elles aussi). Le dessin des icônes a été extrait d'`ActionController.gd` vers `IconRenderer.gd` (voir dette d'architecture A1, `Forgotten_Caves_Sprints.xlsx`).

### 5. Végétation, cueillette & décor

Arbres par espèce (chêne/sapin/bouleau, silhouettes distinctes, bois différencié), décor de sol (herbe/fleurs/cailloux, densité et couleur liées au climat), arbres fruitiers (pommier/oranger/cerisier) et 5 types de buissons à baies (groseille/myrtille/fraise/framboise/cassis, avec un visuel distinct "buisson" vs "plante basse"), action **Cueillir** dédiée (récolte sans détruire la plante), repousse progressive (nouveaux arbres si la densité baisse, baies qui repoussent une par une), compétence Agriculture (vitesse + bonus de rendement), calories différenciées par aliment, tas de ressources visuels au sol à chaque récolte (remplace l'ancien item flottant animé).

**Refonte perf (Sprint 34)** : arbres/buissons/décor ne sont plus des dizaines de milliers de nœuds individuels mais partagent des `MultiMeshInstance3D` par type de pièce — chaque objet est construit une fois (temporairement), "récolté" (transform + couleur capturés dans un tableau qui reste en mémoire) puis ses nœuds temporaires libérés. Un arbre coupé ne peut donc plus disparaître par simple `queue_free()` : `hide_tree_visuals()` met à l'échelle zéro les seules instances qui lui appartiennent.

**Ajustements chêne/sapin/buissons (2026-07-05, à confirmer en jeu)** : chêne agrandi de 20% en hauteur/largeur (échelle globale de l'arbre) et feuillage encore élargi de 30% en plus (rayon des boules de feuillage, indépendant du tronc), tronc assombri. Sapin : hauteur totale +30% sans changer le diamètre du feuillage (le rayon des cônes ne dépend pas de la hauteur totale), espace tronc visible/bas du feuillage réduit, tronc assombri. Buissons ("myrtille"/"groseille"/"cassis") : baies rétrécies, comptées séparément des plantes basses via `BUISSON_BERRIES_COUNT` (10, vs 4 pour fraise/framboise), réparties aléatoirement à 360° en hauteur et en angle autour du corps du buisson (avant : plage d'élévation biaisée, baies visibles seulement d'un côté).

### 6. Sous-sol : filons, niveaux & brouillard de guerre

Filons de métaux/pierres précieuses dans la pierre (14 matériaux, triés du plus rare au plus commun, bruit 3D indépendant par matériau, pépites 3D incrustées via `MultiMeshInstance3D` — tentative de texture d'atlas abandonnée après un bug de blocs blancs jamais résolu, revert complet vers couleur unie + pépites). Système de coupe par niveau (`view_level`) : tout ce qui est au-dessus du niveau courant n'est pas dessiné, ce qui révèle une coupe horizontale complète et colorée (façon Dwarf Fortress), avec brouillard de guerre (une zone jamais minée reste grise jusqu'à exposition).

**Complété le 2026-07-04** : arbres, buissons et décorations de sol (herbe/fleurs/cailloux) disparaissent désormais complètement quand on descend sous leur niveau de sol, exactement comme le terrain — jusque-là seul `VoxelWorld` réagissait à `view_level`. `Forest.gd`/`BerryBushes.gd` exposent `update_view_level(level)` (restaure/masque les instances via les transforms d'origine, conservés en mémoire) ; `GroundDecoration.gd` (dont chaque décoration n'a pas de nœud persistant) fait de même via un tableau parallèle du niveau de sol par instance. `CameraRig.gd` notifie ces systèmes à chaque changement de niveau, en plus de `VoxelWorld.set_view_level()`.

### 7. Carte & performance

Carte agrandie de 20x20x30 à 100x100x50 blocs, densité d'arbres/buissons/décor exprimée en "par 1000 cases" (indépendante de la taille de carte), `rebuild_mesh()` limité à la portion découverte (pas toute la grille) à chaque changement.

### 8. Cycle jour/nuit, météo & saisons

Cycle jour/nuit complet (lever/coucher exact par saison, jeu démarrant à 7h du matin, lumière + ambiant pilotés par script), ombres réelles (matériaux du terrain/arbres/décor passés en éclairage réel, sauf les nains), système météo (Normal/Brouillard/Pluie/Neige, particules réelles), 4 saisons avec calendrier affiché (1 jour = 2 minutes réelles, 1 mois = 20 jours, 1 saison = 3 mois), climat/température, nuages et oiseaux décoratifs (forme cumulus, teinte selon météo/nuit).

**Bugs coûteux résolus** (leçon générale : un post-effet en aval peut masquer complètement un correctif fait en amont) :
- Couleurs "trop sombres" qui ne réagissaient à aucun correctif → cause réelle : `ambient_light_source` de la scène ne se mettait pas à jour assez vite pour un cycle de 2 minutes ; remplacé par une couleur pilotée directement par script à chaque frame.
- Ciel resté gris en plein jour malgré plusieurs correctifs de couleur → cause réelle : `fog_sky_affect` recouvrait le ciel par défaut, indépendamment de l'heure/la météo.
- Bandeau horaire "bande blanche à droite" → cause réelle : tout `Gradient` créé par code garde 2 points par défaut qu'il faut explicitement vider avant d'ajouter les siens ; un premier correctif (boucle de suppression) a provoqué un plantage au lancement (boucle infinie dès 1 point restant), corrigé ensuite.
- **Couplage DayNightCycle.gd/WeatherSystem.gd fiabilisé (revue de code, Phase 2 du plan de correction, C8/C10/I49/I56, 2026-07-06)** : la composition météo (assombrissement/teinte du ciel appliqués par-dessus l'énergie lumineuse et les couleurs du ciel) ne dépendait QUE de l'ordre des nœuds dans `Main.tscn`, sans aucune garde dans le code — un réordonnancement accidentel aurait cassé silencieusement le rendu. `DayNightCycle.gd` expose désormais des champs publics (`base_light_energy`/`base_sky_top_color`/`base_sky_horizon_color`/`base_ground_bottom_color`/`base_ground_horizon_color`) que `WeatherSystem.gd` lit directement via `%DayNightCycle`, indépendamment de l'ordre d'exécution des `_process()`. Confirmé en jeu par François.

### 9. Rivières, cascades & relief

Le chantier le plus long du projet. Relief en collines douces (bruit), lacs, une rivière qui traverse la carte, soif des nains (ressource "eau" récoltée via le bouton **Puiser**). Plusieurs réécritures complètes du tracé de rivière et de la forme de cascade, jusqu'à la version actuelle :

- **Tracé de rivière** (`VoxelWorld._place_river`) : le relief naturel est sondé sur toute la largeur du lit (+ marge de berge) à chaque rangée ; l'eau part du bout du trajet dont le relief est le plus haut et redescend en escalier (jamais au-dessus du relief environnant, jamais un point milieu comme source) ; une rupture de niveau = une cascade, valable sur toute la largeur du lit à la fois (jamais en escalier décalé).
- **Règles physiques figées** (voir mémoire projet, à respecter avant toute modification) : R1-R3 pour les rivières (berges obligatoires des deux côtés, sens du courant constant, ondulation acceptée seulement sans changement de niveau), C1-C5 pour les cascades (la case d'eau du niveau supérieur doit se retrouver en case d'eau recouverte par la cascade une rangée plus loin dans le sens du courant, jamais l'inverse obligatoire, jamais de cascade sans eau au-dessus).
- **Forme de cascade** (`WaterfallShapes.gd`) : un vrai quart de cylindre (pas un mur plat), rempli en volume. **Géométrie gelée** (`_build_quarter_cylinder_mesh`/`_build_shape` : rayon/position/rotation) après plusieurs régressions de positionnement — ne plus modifier sans autorisation explicite. Seule la couleur reste ajustable.
- **Effets décoratifs** : petits nuages d'écume mobiles (`WaterfallFoamClouds.gd`, plus foncés en haut/plus clairs en bas, assombris par météo/nuit) et traits de chute verticaux multicolores (`WaterfallStreaks.gd`, animés le long de la courbe).
- **Disparition par niveau** (2026-07-04) : cascades (forme + traits + écume) cachées quand leur niveau de rivière n'est plus visible, même mécanisme que le paquet 6.

**3 bugs de cascade corrigés le 2026-07-04**, tous des violations de la règle C2 (pas d'eau sous la cascade) :
1. Un remplissage vertical devenu obsolète (censé être remplacé par la forme décorative depuis longtemps, jamais fait) enterrait la vraie surface du bassin sous une colonne d'eau fictive — supprimé.
2. Quand deux chutes se suivent immédiatement (relief en plusieurs petits paliers), la seconde recopiait une position théorique jamais mise à jour au lieu de la position réellement posée par la première — corrigé en retenant les colonnes réellement posées, rangée par rangée, dans l'ordre réel du courant (confirmé par simulation : 0 violation sur 2000 cartes générées hors jeu).
3. Un code hérité masquait toutes les faces (sauf le dessous) de tout bloc d'eau d'une colonne de cascade — conçu à l'origine pour cacher un mur de blocs empilés qui n'existe plus depuis le correctif n°1 ; il masquait donc par erreur la surface même du bassin. Supprimé entièrement.

**Leçon de méthode** : avant d'annoncer un correctif de génération de terrain comme suffisant, simuler le pipeline complet (données ET logique de rendu/face-culling) hors du jeu, pas seulement relire le code.

### 10. Végétation saisonnière

**Implémenté le 2026-07-05, NON VÉRIFIÉ EN JEU** (pas de rendu Godot possible côté agent — à confirmer par François). Complément visuel au paquet 8 (cycle des saisons) et au paquet 5 (végétation) : chaque saison change l'aspect de la végétation existante, sans regénérer la carte.

- **Printemps** : herbe et buissons plus clairs, feuillage de TOUS les arbres (sapin inclus) plus clair, ~40% de fleurs de décoration en plus (fleurs "bonus" taguées à la génération, cachées les autres saisons).
- **Été** : couleurs des arbres = référence (aucun changement, saison neutre), herbe légèrement plus jaune, ~30% des décorations (herbe/fleurs/cailloux) masquées.
- **Automne** : teinte rouge/orange sur les feuilles des arbres ET sur les buissons, sauf les sapins.
- **Hiver** : feuilles des arbres quasi disparues (sauf sapins, qui restent verts) ; buissons teinte grise ; fruits des arbres fruitiers, plantes et buissons totalement indisponibles (`fruits_left` mis à 0, restauré au dégel) — aucune récolte possible.

**Détails techniques** :
- `Forest.gd` : la teinte de saison est désormais séparée en deux tables — `SEASON_FOLIAGE_TINT` (chêne/bouleau/arbres fruitiers) et `SEASON_CONE_TINT` (sapin uniquement, jamais rougi ni éclairci en hiver). La "chute des feuilles" en hiver passe par le canal alpha de la teinte (transparence activée sur les matériaux des boules de feuillage/petites feuilles) plutôt que par une manipulation de transform, pour ne pas entrer en conflit avec `update_view_level()`/`hide_tree_visuals()` (qui restaurent en permanence la transform d'origine indépendamment de la saison).
- `BerryBushes.gd` : `apply_season_tint()` ne teinte que le corps du buisson (`PartType.BUSH_BODY`), jamais les plantes basses (fraise/framboise).
- `GroundDecoration.gd` : toute la décoration est générée UNE fois au démarrage (jamais de vraie régénération dynamique) — "plus de fleurs" au printemps et "-30% en été" sont obtenus en taguant chaque décoration à sa création avec deux booléens indépendants, combinés avec le masquage par niveau de vue/minage déjà existant.
- Disparition des fruits en hiver : logique générique dans `SeasonSystem.gd`, sur le groupe `"cueillette"` (arbres fruitiers + buissons + plantes). Limite connue acceptée : un arbre/buisson qui repousse en plein hiver n'est remis en mode hiver qu'au prochain changement de saison (cas jugé rare).
- `SeasonSystem` a été déplacé après `BerryBushes`/`GroundDecoration` dans `Main.tscn` (l'ordre des `_ready()` de nœuds frères suit l'ordre de déclaration) — nécessaire pour que leurs `MultiMeshInstance3D`/décorations existent avant le premier appel de reteinte.

---

## Scénarios de test à vérifier manuellement (revue de code, paquet H)

Cas limites identifiés par la revue de code du 2026-07-06 sans scénario de
test documenté nulle part ailleurs - a verifier au fil des prochaines
sessions de jeu (pas des bugs confirmes, juste des zones a surveiller) :

- **File de tâches vide** (`TaskQueue.gd`) : cas exact à l'origine du bug
  critique C7 (déjà corrigé) - revérifier qu'une file vide ne replante pas.
- **Repousse hivernale des baies** (`BerryBushes.gd`, `_winter_active`) :
  vérifier qu'un buisson qui repousse en plein hiver se comporte bien.
- **Saison + niveau de vue** (`Forest.gd`, `_winter_fruits_hidden` +
  `update_view_level()`) : un vrai bug a déjà été trouvé ici le 2026-07-06
  (fruits visibles en hiver) - surveiller en priorité après un changement de
  saison combiné à un minage/changement de niveau de vue.
- **Cliquer-glisser cas limites** (`ActionController.gd`) : rectangle vide,
  glisser en dehors de la carte.
- **Fin de tâche cas limites** (`Dwarf.gd`, `_complete_task`) : cible détruite
  entre-temps (ex: arbre coupé par un autre nain avant la fin), et
  interaction énergie critique + recherche d'eau (`is_seeking_dry_land`).

---

## État actuel du projet

**Phase 1 (nains de base et environnement) n'est pas refermée.** Les paquets 6 à 9 (filons/niveaux, cycle jour/nuit/météo/saisons, rivières/cascades/relief) ont été retestés et confirmés en jeu par François le 2026-07-05. Le bug Couper/Cueillir est résolu (voir paquet 1). Reste à confirmer en jeu par François : les ajustements chêne/sapin/buissons et l'interface (paquets 4-5) et le nouveau cycle de végétation saisonnière (paquet 10).

**Revue de code du 2026-07-06 (scan complet, 116 findings + 5 hors scan) : TERMINÉE ET CONFIRMÉE EN JEU.** Traitée en 8 paquets thématiques (A à H) après les 4 phases initiales de correctifs critiques (C7-C18, dont la dette d'architecture A1 : `ActionController.gd` et `Dwarf.gd` découpés en plusieurs fichiers par responsabilité, voir structure du projet ci-dessus). Paquet A (déterminisme/seed, système `GameRandom.gd`), B (duplication de code), C (robustesse), D (print() de debug), E (fonctions/fichiers trop longs), F (ordre d'initialisation implicite), G (performance), H (divers - dernier paquet) tous corrigés et confirmés en jeu par François le 2026-07-06. Bilan final : 91 corrigés, 25 vérifiés déjà corrects (aucun changement nécessaire), 3 ignorés (décision explicite), 2 encore ouverts (`VoxelHydrology._place_river()`/`VoxelWorld.generate_flat_terrain()` - geometrie "Cascade GELÉE", autorisation explicite de François requise avant toute modification). Détail complet par item : dossier `Code Review` (hors de ce dépôt git), fichier `Revue_de_code_2026-07-06.html`. À surveiller particulièrement si un souci apparaît : position des armes dans le dos (`DwarfWeaponBuilder.attach_to_back`, ajustement à l'estime) et assombrissement nocturne des tas de ressources (`DwarfResourcePile.gd`, effectif seulement à la création du tas, pas de mise à jour continue).

Ne pas commencer la Phase 2 DU JEU (Ateliers & artisanat, ci-dessous) avant confirmation explicite.

**Phase 2 (à venir) — Ateliers & artisanat** : ateliers de production, qualité/usure des objets, champs & agriculture, stockage, et l'équipement réel (habits/armures/armes fabricables et utilisables, pas seulement l'apparence du modèle 3D — décision du 2026-07-02, traité avec les ateliers plutôt qu'en sprint isolé).

Voir `Forgotten_Caves_Sprints.xlsx` (dossier parent) pour le détail phase par phase.
