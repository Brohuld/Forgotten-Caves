extends Node3D
## Terrain voxel de la carte : grille de blocs (terre/pierre/eau/murs),
## construit en un seul mesh par materiau en ne dessinant que les faces
## exposees (culling des faces internes/cachees). Le dessus "terre" (herbe)
## utilise une couleur de base par climat/saison (ClimateDefinitions) avec
## une legere variation continue par case (bruit) pour casser la monotonie ;
## la pierre et les murs gardent un damier clair/fonce (utile pour reperer
## les trous mines).
##
## Filons de metaux/pierres precieuses generes aleatoirement dans la pierre
## (jamais dans la terre), visibles par leur couleur et par des "pepites" 3D
## (petites spheres) incrustees sur les faces exposees des blocs de filon -
## rondes et lisses pour les metaux (metallic/roughness), a facettes et
## legerement lumineuses pour les pierres precieuses. Aucune image/texture/
## shader : uniquement des SphereMesh integres au moteur + MultiMeshInstance3D
## + couleur par instance (meme principe que la couleur par sommet de
## l'herbe/la pierre/les filons).
##
## Lacs et riviere : l'eau est un vrai bloc de terrain (BlockType.WATER, voir
## generate_flat_terrain), qui remplace la terre/pierre sur "water_depth"
## niveaux depuis la surface - la carte reste plate en X/Z (pas de vraie
## depression creusee dans le sol visible de haut), mais la profondeur se
## revele en descendant avec la molette (comme pour la roche). L'eau ne se
## mine pas (voir ActionController._valid_mine_rect_cells) : elle se "puise"
## (bouton Puiser, ressource renouvelable ajoutee a l'inventaire sans retirer
## le bloc, voir Dwarf.gd/_complete_task "puiser").

const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")
const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
const DwarfResourcePileScript := preload("res://scripts/entites/DwarfResourcePile.gd")
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")

## Tout ce qui concerne les filons/pepites (bruit, placement,
## MultiMeshInstance3D) vit dans VoxelVeins.gd - "vein_system" porte
## vein_grid/vein_noises/metal_pepites/gem_pepites.
const VoxelVeinsScript := preload("res://scripts/monde/voxel/VoxelVeins.gd")
var vein_system: VoxelVeinsScript = VoxelVeinsScript.new()

# Dimensions de la carte - SOURCE UNIQUE (single source of truth). Tous les
# autres scripts qui ont besoin des dimensions de la carte (CameraRig,
# ActionController, Forest/BerryBushes/GroundDecoration/Dwarf,
# VoxelHydrology.gd) lisent directement WIDTH/DEPTH/HEIGHT ci-dessous plutot
# que de dupliquer ces valeurs, pour eviter toute desynchronisation (voir le
# bug C19, cause par une telle duplication dans VoxelHydrology.gd).
# WIDTH/DEPTH ne sont plus des const : StartMenu.gd les ecrit AVANT
# change_scene_to_file (meme mecanisme que use_fixed_seed/requested_seed plus
# bas) selon la taille de carte choisie a l'ecran d'accueil. HEIGHT reste
# fixe (la taille de carte ne concerne que X/Z, pas la hauteur).
static var WIDTH: int = 250   # axe X
static var DEPTH: int = 250   # axe Z
const HEIGHT := 50  # axe Y (hauteur totale, y=0 = fond)

## Point de spawn unique de la colonie (nains + stock de bois de depart),
## calcule dans _ready() (voir _find_dry_spawn_center) - garanti hors eau,
## contrairement au centre brut (WIDTH/2, DEPTH/2). Lu par Dwarf.gd via
## %VoxelWorld.colony_spawn_center.
var colony_spawn_center: Vector2 = Vector2.ZERO

# Nombre de niveaux de terre en surface (le reste en dessous = pierre) -
# tire au sort PAR COLONNE (voir generate_flat_terrain), pas une valeur fixe -
# meme comportement que valide dans le prototype CubeSolTestV2.gd
# (2026-07-10, Francois : "on garde le comportement aleatoire").
const DIRT_HEIGHT_MIN := 1
const DIRT_HEIGHT_MAX := 3

# Marge au-dessus du terrain pour pouvoir construire des murs en hauteur
const BUILD_CEILING := HEIGHT + 10

enum BlockType { EMPTY, DIRT, STONE, WOOD_WALL, STONE_WALL, WATER }

# Couleur eau/glace, generation lacs/riviere/cascades et bruits de filon :
# voir VoxelMeshBuilder.gd et VoxelHydrology.gd/VoxelVeins.gd respectivement.

# Etat climat global (pas par case, voir TemperatureSystem.gd), lu par
# VoxelMeshBuilder.gd pour la couleur eau/glace. Reste ici car
# set_climate_state() (API publique appelee par TemperatureSystem.gd) les
# modifie.
var is_frozen: bool = false
var snow_coverage: float = 0.0  # 0..1, pilote par TemperatureSystem.gd

# Grille du monde : cle = Vector3i (position bloc), valeur = BlockType. C'est
# le CUBE (voir modele CUBE+SOL, memoire "Modele CUBE+SOL" 2026-07-08).
var grid: Dictionary = {}

## Le SOL (fine couche sur laquelle on marche, voir modele CUBE+SOL) - cle =
## Vector3i, valeur = BlockType. Stockage SPARSE : une position n'apparait ici
## QUE si son SOL diverge de la regle par defaut (voir get_sol() ci-dessous) -
## jamais peuplee pendant la generation initiale (le SOL de tout bloc frais
## est par definition la valeur par defaut), seulement plus tard par le
## minage/la construction (pas encore implemente). Meme esprit que
## "discovered" : un dictionnaire qui ne grandit qu'avec les evenements
## reels, jamais une grille dense pre-remplie sur toute la carte.
var sol_grid: Dictionary = {}

# Filons (position -> id materiau) : voir vein_system.vein_grid. Dictionnaire
# separe plutot qu'un nouveau BlockType par materiau, pour eviter de faire
# exploser l'enum BlockType et le systeme de buckets pour chaque metal/pierre
# precieuse (voir _bucket_for/_vein_color_for : un seul bucket
# supplementaire, colore par sommet, sert pour tous les materiaux).

## "Brouillard de guerre" souterrain : un bloc est "decouvert" (cle presente,
## valeur toujours true) des qu'on connait deja son apparence - la surface
## naturelle (exposee au ciel depuis le debut), les bords de la carte
## (falaise visible depuis l'exterieur), ou un bloc devenu adjacent a du vide
## suite a un minage/une construction (voir remove_block/build_block). Tant
## qu'un bloc n'est pas dans ce dictionnaire, sa vraie couleur/son filon ne
## sont pas dessines (voir rebuild_mesh) - juste une face grise generique
## s'il se trouve exactement au niveau de coupe courant (view_level).
## Objectif double : ne jamais reveler le contenu de la roche jamais minee
## juste en faisant defiler le niveau de vue, et eviter de parcourir/colorer
## en detail des centaines de milliers de blocs jamais explores a chaque
## changement de niveau - seul cet ensemble "decouvert" (petit au depart,
## grandit lentement au fil du minage) est parcouru en detail.
var discovered: Dictionary = {}

## Cases (colonnes x,z) marquees "interdites" par le mode Interdire,
## exclues de la selection de Miner/Puiser (voir
## ActionValidator.valid_mine_rect_cells/valid_puiser_rect_cells). Cle =
## Vector2i(x,z), valeur toujours true (meme convention que "discovered").
var forbidden_cells: Dictionary = {}

## Escaliers creuses (voir dig_stairs) : Vector3i (position bloc, deja EMPTY
## dans "grid") -> {"piece": "bas"/"haut"/"hautbas" (voir dig_stairs),
## "material": BlockType du bloc qui occupait cette case AVANT le creusage}.
## Le materiau est conserve pour que la plaque d'escalier reprenne la
## couleur reelle de ce qu'elle traverse (terre/pierre/mur), comme une paroi
## minee normale - pas une couleur arbitraire (voir
## VoxelMeshBuilder._stair_color_for). Meme principe que vein_grid
## (dictionnaire separe plutot qu'un nouveau BlockType) - lu par
## VoxelMeshBuilder.gd pour dessiner une plaque de hauteur partielle a la
## place du vide habituel. Navigation verticale REELLE des nains non geree
## pour l'instant (voir memoire "Phase 2 Sprint 1") - seuls le menu/
## creusage/rendu sont couverts par cette premiere passe.
var stair_grid: Dictionary = {}

## Cases VIDES connues comme reliees a la surface par un chemin continu de
## cases vides (6-connexe, voir _mark_reachable_from) - Vector3i -> true.
## Sert a distinguer un "trou" (progresse toujours depuis le sommet reel
## d'une colonne, jamais bloque) d'un "couloir" (case creusee via le niveau
## de vue dans de la roche encore fermee de tous cotes, qui ne devient
## executable par un nain qu'une fois reliee - voir can_reach_block,
## consultee par TaskQueue.pop_nearest_task). Decision Francois 2026-07-08 :
## la designation d'un couloir reste autorisee immediatement, seule son
## EXECUTION attend la connexion. Mise a jour incrementale a chaque
## _remove_block_silent, jamais recalculee entierement.
var reachable: Dictionary = {}

## Etendue verticale (top/bottom, en niveau de station debout - voir doc de
## can_walk_to_level) de l'escalier de chaque colonne (x,z) qui en contient
## un - Vector2i(x,z) -> {"top": int, "bottom": int}. Rempli directement par
## dig_stairs() (qui connait deja top_y/bottom_y), lu par can_walk_to_level/
## find_connecting_stair et par DwarfMovement.ground_y_at - regles de
## pathing des nains, voir memoire "Regles de pathing des nains" (Francois
## 2026-07-08) : un nain ne peut monter/descendre que d'1 niveau max sans
## escalier, au-dela un escalier est obligatoire.
var stair_columns: Dictionary = {}

# 6 directions possibles autour d'un bloc (droite/gauche/haut/bas/avant/arriere)
const DIRECTIONS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


var mesh_instance: MeshInstance3D

## Niveau de "coupe" visible - pilote par CameraRig.set_view_level(). Tout
## bloc strictement au-dessus de view_level n'est pas dessine du tout, et le
## dessus des blocs exactement a view_level est toujours dessine (meme si un
## bloc existait juste au-dessus dans la grille), ce qui revele une coupe
## horizontale complete du niveau courant, avec ses couleurs (damier pierre,
## filons...). La valeur de depart (HEIGHT-1) est corrigee dans _ready()
## pour tenir compte de hill_amplitude (sinon les collines, plus hautes que
## HEIGHT-1, seraient invisibles au demarrage - voir
## VIEW_LEVEL_MARGIN_ABOVE plus bas, deja prevu pour ce cas).
var view_level: int = HEIGHT - 1

# Climat/saison utilises pour la couleur du terrain (voir
# ClimateDefinitions.gd). Une seule saison geree a la fois, mais ces exports
# permettent deja de changer de climat/saison sans toucher au code.
@export var climate_id: String = "tempere"
@export var season_id: String = "ete"

## Amplitude maximale des collines, en nombre de blocs au-dessus de la
## surface de base (HEIGHT-1) - reglable dans l'inspecteur plutot qu'une
## constante en dur. "Douce" par defaut (2-4 blocs).
@export var hill_amplitude: float = 3.0

# Bruit utilise pour la variation subtile de couleur de l'herbe, case par
# case (voir _grass_color_for). Frequence basse => variation douce/continue,
# tres different d'un damier ou d'un bruit purement aleatoire par case.
var terrain_noise := FastNoiseLite.new()

# Meme principe que terrain_noise, mais pour la pierre (voir
# _stone_color_for). Bruit separe pour que les variations de l'herbe et de la
# pierre ne soient pas correlees (pas la meme "forme" de variation).
var stone_noise := FastNoiseLite.new()

# Bruit utilise pour casser le contour parfaitement circulaire des lacs (voir
# _place_lakes) - un cercle "pur" serait trop artificiel/regulier.
var water_noise := FastNoiseLite.new()

## Bruit de hauteur des collines - frequence TRES basse (0.02, contre 0.18
## pour terrain_noise) pour que le relief monte et descende doucement sur
## plusieurs dizaines de cases, jamais case par case (evite un terrain "en
## dents de scie", voir _hill_height_at).
var hill_noise := FastNoiseLite.new()

## Liste des colonnes de cascade calculees a la generation du terrain (voir
## generate_flat_terrain/_place_river), conservee ici pour qu'un script
## decoratif externe (WaterfallStreaks.gd) puisse la lire via
## get_waterfall_columns() et placer ses traits SANS dupliquer la logique de
## generation de riviere.
var waterfall_columns: Array = []

## Mesure de duree de generation du monde - initialise ici (premier script
## "lourd" a demarrer, voir ordre des noeuds dans Main.tscn), lu par
## GroundDecoration.gd (dernier script "lourd" a finir son _ready()) pour
## calculer et afficher la duree totale dans la console. "static" = partage
## entre tous les scripts qui preloadent VoxelWorld.gd, pas besoin d'une
## instance.
static var world_gen_start_ms: int = 0

## StartMenu.gd (ecran affiche avant Main.tscn) ecrit ces 2 valeurs AVANT le
## changement de scene. "static" = memes valeurs lues ici via le meme script
## preload, comme world_gen_start_ms ci-dessus. Si use_fixed_seed est faux,
## une graine aleatoire est tiree ET affichee en console (pour pouvoir la
## reutiliser plus tard si un bug interessant apparait).
## Contrat : SEUL StartMenu.gd a le droit d'ECRIRE ces 2 variables (juste
## avant de changer de scene vers Main.tscn). Tout autre script peut les LIRE
## mais ne doit jamais les modifier.
static var use_fixed_seed: bool = false
static var requested_seed: int = 0


func _ready() -> void:
	# VoxelMeshBuilder.gd duplique manuellement cet enum BlockType (necessaire
	# pour eviter une reference typee croisee dans l'autre sens). Verification
	# de coherence legere ici : compare quelques valeurs connues, avertit sans
	# bloquer si desynchronise.
	if VoxelMeshBuilderScript.BlockType.EMPTY != BlockType.EMPTY \
	or VoxelMeshBuilderScript.BlockType.DIRT != BlockType.DIRT \
	or VoxelMeshBuilderScript.BlockType.STONE != BlockType.STONE \
	or VoxelMeshBuilderScript.BlockType.WOOD_WALL != BlockType.WOOD_WALL \
	or VoxelMeshBuilderScript.BlockType.STONE_WALL != BlockType.STONE_WALL \
	or VoxelMeshBuilderScript.BlockType.WATER != BlockType.WATER:
		push_warning("VoxelWorld: BlockType desynchronise avec la copie dans VoxelMeshBuilder.gd - le rendu des blocs risque d'etre incorrect.")
	world_gen_start_ms = Time.get_ticks_msec()
	if OS.is_debug_build():
		print("[Perf] VoxelWorld (terrain) : debut a %.1f s depuis le debut de la scene" % ((world_gen_start_ms - DayNightCycleScript.scene_start_ms) / 1000.0))
	var active_seed: int = requested_seed
	if not use_fixed_seed:
		randomize()
		active_seed = randi()
	# "seed()" (fonction globale Godot) fixe l'etat de TOUT le generateur
	# aleatoire global du jeu. La meme graine reproduit donc la carte entiere
	# a l'identique (relief, lacs, riviere, cascades, arbres, buissons,
	# decorations) tant qu'aucun script ne reinitialise ce generateur global
	# entre-temps (voir GameRandom.gd pour les flux dedies qui evitent ce
	# risque de decalage).
	seed(active_seed)
	print("Forgotten Caves - graine de la carte utilisee : ", active_seed)
	# Initialise le systeme de flux aleatoires dedies (voir GameRandom.gd)
	# avec la MEME graine de partie - doit rester le plus tot possible, avant
	# tout premier appel a GameRandom.get_rng() (noms des nains, types de
	# baies/arbres, oiseaux, competences, bruit des filons, rivieres/lacs...).
	GameRandom.setup(active_seed)
	# Flux dedie "terrain" (get_rng() cree son propre RandomNumberGenerator
	# independant, derive du seed de partie + du nom du flux - voir
	# GameRandom.gd) pour le bruit de terrain, comme tous les autres systemes
	# du jeu.
	var terrain_rng: RandomNumberGenerator = GameRandom.get_rng("terrain")
	terrain_noise.seed = terrain_rng.randi()
	terrain_noise.frequency = 0.18
	stone_noise.seed = terrain_rng.randi()
	stone_noise.frequency = 0.18
	water_noise.seed = terrain_rng.randi()
	water_noise.frequency = 0.15
	hill_noise.seed = terrain_rng.randi()
	hill_noise.frequency = 0.02
	# Le niveau de coupe par defaut doit couvrir toute l'amplitude des
	# collines (sinon leur sommet, plus haut que HEIGHT-1, resterait
	# invisible tant qu'on n'a pas remonte la molette a la main).
	view_level = HEIGHT - 1 + int(ceil(hill_amplitude))
	vein_system.setup_vein_noises()
	generate_flat_terrain()
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	vein_system.setup_pepites_nodes(self)
	rebuild_mesh()
	# Point de spawn UNIQUE de la colonie, calcule une seule fois ici et
	# garanti hors eau (voir _find_dry_spawn_center) - reutilise par Dwarf.gd
	# (nains) ET DwarfResourcePileScript.spawn_starting_wood_stock (stock de
	# depart) ci-dessous, pour que les deux restent au meme endroit (le
	# centre brut de la carte peut tomber dans une riviere/un lac).
	colony_spawn_center = _find_dry_spawn_center()
	if OS.is_debug_build():
		print("[Spawn colonie] centre calcule = (%.1f, %.1f) - dans l'eau ? %s" % [colony_spawn_center.x, colony_spawn_center.y, is_water(int(colony_spawn_center.x), int(colony_spawn_center.y))])
	# Stock de bois de depart, dispose autour du point de spawn des nains.
	# "%Inventory" est deja accessible ici (noeud existant dans Main.tscn,
	# meme si son _ready() n'a pas encore tourne - add_resource() ne depend
	# que du dictionnaire resource_counts, deja initialise a la declaration de
	# la variable).
	var inventory_node: Node = get_node_or_null("%Inventory")
	if OS.is_debug_build():
		print("[Spawn colonie] noeud Inventory trouve ? ", inventory_node != null)
	DwarfResourcePileScript.spawn_starting_wood_stock(get_parent(), self, inventory_node, colony_spawn_center)
	if OS.is_debug_build():
		var elapsed_ms: int = Time.get_ticks_msec() - world_gen_start_ms
		var elapsed_since_scene_ms: int = Time.get_ticks_msec() - DayNightCycleScript.scene_start_ms
		print("[Perf] VoxelWorld (terrain) : fin en %.1f s (terrain seul), %.1f s depuis le debut de la scene" % [elapsed_ms / 1000.0, elapsed_since_scene_ms / 1000.0])


## Point de spawn unique de la colonie (nains + stock de depart), garanti
## hors eau. Le centre brut de la carte (WIDTH/2, DEPTH/2) peut tomber dans
## une riviere/un lac genere aleatoirement - cherche alors une position seche
## a proximite (rayon croissant, meme motif que
## Forest._pick_dry_position mais avec un flux GameRandom dedie
## "spawn_colonie" pour rester deterministe a graine egale). Repli sur le
## centre brut si vraiment rien de sec n'est trouve (tres improbable, evite
## un blocage plutot que planter).
func _find_dry_spawn_center() -> Vector2:
	var cx: float = WIDTH / 2.0
	var cz: float = DEPTH / 2.0
	if not is_water(int(cx), int(cz)):
		return Vector2(cx, cz)
	var rng: RandomNumberGenerator = GameRandom.get_rng("spawn_colonie")
	for radius in [5.0, 10.0, 15.0, 20.0, 30.0]:
		for attempt in range(20):
			var angle := rng.randf_range(0.0, TAU)
			var dist := rng.randf_range(0.0, radius)
			var x: float = cx + cos(angle) * dist
			var z: float = cz + sin(angle) * dist
			if not is_water(int(x), int(z)):
				return Vector2(x, z)
	push_warning("VoxelWorld: aucune position seche trouvee pres du centre pour le spawn de la colonie - repli sur le centre brut (peut etre dans l'eau).")
	return Vector2(cx, cz)


## Marge de niveaux vides au-dessus de la surface actuelle (HEIGHT-1) - rien
## n'y est genere pour l'instant (grid n'a aucune entree la-bas, donc
## rebuild_mesh n'y dessine rien), mais la camera/la molette peuvent deja s'y
## deplacer, prete pour un futur relief (collines/montagnes) sans dependre
## d'un redimensionnement de HEIGHT.
const VIEW_LEVEL_MARGIN_ABOVE := 15

## Change le niveau de "coupe" visible (voir view_level) et reconstruit le
## mesh en consequence. Appele par CameraRig a chaque changement de niveau
## (molette de la souris). grid_changed=false (voir rebuild_mesh) : la grille
## elle-meme n'a pas bouge, seul le niveau de coupe change - permet a
## VoxelMeshBuilder de reutiliser son cache par couche au lieu de tout
## reconstruire (perf 2026-07-08, voir sa doc).
func set_view_level(level: int) -> void:
	view_level = clampi(level, 0, HEIGHT - 1 + VIEW_LEVEL_MARGIN_ABOVE)
	rebuild_mesh(false)


## Hauteur de colline (en blocs, 0..hill_amplitude) a une position (x,z), a
## partir d'un bruit tres lisse (voir hill_noise) - get_noise_2d renvoie
## -1..1, remis a l'echelle 0..1 puis multiplie par hill_amplitude et arrondi
## (hauteur de bloc = entier). Utilisee par generate_flat_terrain pour
## decaler la surface de base (HEIGHT-1) ; surchargee a une valeur fixe pour
## les colonnes d'eau (lacs aplatis, riviere en paliers - voir
## _compute_water_columns) plutot que d'utiliser le bruit brut, pour eviter
## un lac/une riviere qui "epouserait" chaque bosse.
func _hill_height_at(x: int, z: int) -> int:
	var n: float = hill_noise.get_noise_2d(float(x), float(z))  # -1..1
	var t: float = (n + 1.0) * 0.5  # 0..1
	return int(round(t * hill_amplitude))


## Renvoie le y du bloc le plus haut (non vide) de la colonne (x,z), -1 si vide.
## Cherche jusqu'a BUILD_CEILING pour tenir compte des murs construits en hauteur.
func get_top_block_y(x: int, z: int) -> int:
	for y in range(BUILD_CEILING - 1, -1, -1):
		if get_block(Vector3i(x, y, z)) != BlockType.EMPTY:
			return y
	return -1


## Materiau du SOL a une position donnee (voir modele CUBE+SOL, memoire
## "Modele CUBE+SOL" 2026-07-08) - jamais "dessus" d'un bloc, un concept
## explicitement banni : le SOL est sa propre couche, independante du CUBE.
## Regle par defaut (utilisee tant que "pos" n'a pas d'entree explicite dans
## "sol_grid", donc pour tout bloc frais/jamais perturbe) :
## - Si le CUBE a "pos" est plein (terre/pierre/eau/mur), le SOL reprend LE
##   MEME materiau (Francois 2026-07-08 : "bloc metal = CUBE metal + SOL
##   metal") - couvre aussi bien la pierre/les filons (le SOL suit le CUBE,
##   filon compris, sans logique dediee) que l'eau (CUBE=eau => SOL=eau,
##   aucun lit distinct).
## - Sinon (CUBE vide) : SOL=terre UNIQUEMENT sur la couche d'air marchable
##   juste au-dessus du sommet REEL de la colonne (get_top_block_y + 1), et
##   seulement si ce sommet n'est PAS de l'eau (une colonne d'eau n'a pas de
##   "terre" flottant au-dessus de sa surface - voir cas CUBE=eau ci-dessus,
##   deja couvert). Partout ailleurs (ciel au-dessus de ce niveau), SOL=vide.
func get_sol(pos: Vector3i) -> int:
	if sol_grid.has(pos):
		return sol_grid[pos]
	var cube_type: int = get_block(pos)
	if cube_type != BlockType.EMPTY:
		return cube_type
	var top_y: int = get_top_block_y(pos.x, pos.z)
	if top_y >= 0 and pos.y == top_y + 1 and get_block(Vector3i(pos.x, top_y, pos.z)) != BlockType.WATER:
		return BlockType.DIRT
	return BlockType.EMPTY


## Meme principe que get_top_block_y, mais plafonne la recherche a "max_y" -
## utilise par Miner pour cibler le bloc visible au niveau de vue courant
## (view_level) plutot que le sommet reel de la colonne, qui peut etre
## masque par la coupe (feedback Francois 2026-07-08 : miner un bloc vu en
## coupe a un niveau inferieur minait en realite le sommet, invisible a ce
## moment-la).
func get_top_block_y_at_or_below(x: int, z: int, max_y: int) -> int:
	var start_y: int = mini(BUILD_CEILING - 1, max_y)
	for y in range(start_y, -1, -1):
		if get_block(Vector3i(x, y, z)) != BlockType.EMPTY:
			return y
	return -1


## Indique si on peut encore construire en hauteur sur cette colonne
func can_build(x: int, z: int) -> bool:
	return get_top_block_y(x, z) + 1 < BUILD_CEILING


## Indique si le sommet de la colonne (x,z) est de l'eau - utilise par
## ActionController pour le bouton "Puiser" (ne cible que l'eau) et pour
## exclure l'eau du bouton "Miner" (voir _valid_mine_rect_cells).
func is_water(x: int, z: int) -> bool:
	var y: int = get_top_block_y(x, z)
	if y < 0:
		return false
	return get_block(Vector3i(x, y, z)) == BlockType.WATER


## Indique si la colonne (x,z) est marquee "interdite" (voir forbidden_cells
## ci-dessus).
func is_cell_forbidden(x: int, z: int) -> bool:
	return forbidden_cells.has(Vector2i(x, z))


## Bascule/force l'etat "interdit" de la colonne (x,z) - voir
## ActionDragController.finalize_interdire_selection (appelant).
func set_cell_forbidden(x: int, z: int, forbidden: bool) -> void:
	var key := Vector2i(x, z)
	if forbidden:
		forbidden_cells[key] = true
	else:
		forbidden_cells.erase(key)


## Profondeur d'eau (en niveaux) de la colonne (x,z), 0 si ce n'est pas de
## l'eau - utilise par Dwarf.gd pour n'autoriser la traversee a pied que
## jusqu'a 1 niveau de profondeur (lacs plus profonds = a contourner, voir
## _pick_new_target/_find_dry_target). La profondeur est plafonnee
## (RIVER_DEPTH/LAKE_DEPTH_MIN = 2, LAKE_DEPTH_MAX = 3, voir
## generate_flat_terrain), donc cette fonction retourne toujours 2 ou 3 pour
## une colonne d'eau (jamais 1) : tout lac/riviere reste "profond" au sens
## de Dwarf.gd, contourne a pied plutot que traverse.
func water_depth_at(x: int, z: int) -> int:
	if not is_water(x, z):
		return 0
	var depth := 0
	# Demarre du sommet REEL de la colonne (get_top_block_y) plutot que
	# HEIGHT-1 fixe - une colonne de cascade peut avoir de l'eau au-dessus de
	# HEIGHT-1 (voir _place_river/"waterfalls"), et une colonne en colline
	# peut avoir son sommet plus haut aussi.
	var y := get_top_block_y(x, z)
	while y >= 0 and get_block(Vector3i(x, y, z)) == BlockType.WATER:
		depth += 1
		y -= 1
	return depth


## Met a jour l'etat climat global (gel/neige, voir "is_frozen"/
## "snow_coverage" plus haut) et reconstruit le mesh SEULEMENT si quelque
## chose a reellement change - appele par TemperatureSystem.gd, qui se
## charge deja de ne pas appeler cette fonction a chaque frame (voir son
## commentaire sur le cout de rebuild_mesh).
func set_climate_state(frozen: bool, snow: float) -> void:
	if frozen == is_frozen and is_equal_approx(snow, snow_coverage):
		return
	is_frozen = frozen
	snow_coverage = snow
	rebuild_mesh()


## Indique si le sommet de la colonne (x,z) est de la terre (utilise pour
## placer les decorations de sol : on ne decore que l'herbe/terre, pas la
## pierre nue ni les murs construits). Renvoie un bool plutot que d'exposer
## l'enum BlockType : un script qui recupere %VoxelWorld via un type
## generique Node3D ne peut pas resoudre un enum defini uniquement dans ce
## script.
func is_dirt_top(x: int, z: int) -> bool:
	var y: int = get_top_block_y(x, z)
	if y < 0:
		return false
	return get_block(Vector3i(x, y, z)) == BlockType.DIRT


## Type + materiau du bloc du sommet de la colonne (x,z), pour la fenetre
## d'info au clic (voir ActionController._describe_block). Renvoie des
## chaines ("terre"/"pierre"/"mur_bois"/"mur_pierre"/"vide") plutot que
## l'enum BlockType, meme raison que is_dirt_top ci-dessus.
func get_block_info(x: int, z: int) -> Dictionary:
	var y: int = get_top_block_y(x, z)
	if y < 0:
		return {"type": "vide", "materiau": ""}
	var pos := Vector3i(x, y, z)
	var type: int = get_block(pos)
	var materiau: String = ""
	if type == BlockType.STONE and vein_system.vein_grid.has(pos):
		materiau = vein_system.vein_grid[pos]
	var type_id: String
	match type:
		BlockType.DIRT:
			type_id = "terre"
		BlockType.STONE:
			type_id = "pierre"
		BlockType.WOOD_WALL:
			type_id = "mur_bois"
		BlockType.STONE_WALL:
			type_id = "mur_pierre"
		BlockType.WATER:
			type_id = "eau"
		_:
			type_id = "vide"
	return {"type": type_id, "materiau": materiau}


## Construit un mur (bois, pierre ou terre) au sommet de la colonne (x,z), en
## empilant sur ce qui existe deja (fonctionne aussi bien pour reboucher un
## trou mine que pour construire en hauteur sur un sol plein).
## build_block()/remove_block() declenchent chacun un rebuild_mesh()
## complet, ce qui pourrait couter cher si beaucoup d'appels arrivaient dans
## la MEME frame. Ce n'est pas le cas ici : "miner un rectangle" cree une
## tache separee par case (voir ActionValidator.valid_mine_rect_cells/
## TaskQueue), et chaque tache n'appelle remove_block() qu'une fois, quand UN
## nain (parmi potentiellement plusieurs en parallele) la termine reellement
## - jamais toutes les cases d'un coup dans la meme frame. Meme avec
## plusieurs nains qui terminent des cases voisines a des instants proches,
## ca reste quelques rebuild_mesh() par seconde au pire.
func build_block(x: int, z: int, material: String) -> void:
	var target_y := get_top_block_y(x, z) + 1
	if target_y >= BUILD_CEILING:
		return
	var type: int
	match material:
		"bois":
			type = BlockType.WOOD_WALL
		"pierre":
			type = BlockType.STONE_WALL
		"terre":
			type = BlockType.DIRT  # reutilise le type terre : mine, ca redonne bien "terre"
		_:
			type = BlockType.WOOD_WALL
	var built_pos := Vector3i(x, target_y, z)
	grid[built_pos] = type
	# Un bloc qu'on vient de construire soi-meme est par definition deja
	# "connu" (voir "discovered") - jamais gris.
	discovered[built_pos] = true
	rebuild_mesh()


## Retire un bloc de la grille (mine/creuse), reconstruit le mesh, et renvoie
## le nom de la ressource obtenue ("terre", "pierre", "bois" pour un mur en
## bois, ou l'id d'un filon comme "fer"/"rubis") ou "" si rien a miner.
## WOOD_WALL/STONE_WALL renvoient "bois"/"pierre" (rembourse le materiau d'un
## mur construit, y compris si le mode Miner cible un mur par accident).
## Aucune species/type pour un mur (pas de notion d'essence comme pour le
## bois d'arbre) - "bois"/"pierre" sont deja les compteurs GENERIQUES, pas
## besoin de double alimentation comme pour la coupe d'arbre.
func remove_block(x: int, y: int, z: int) -> String:
	var resource_name := _remove_block_silent(x, y, z)
	rebuild_mesh()
	return resource_name


## Coeur de remove_block, SANS le rebuild_mesh() final - extrait pour
## dig_stairs() ci-dessous, qui retire plusieurs blocs d'affilee et ne veut
## reconstruire le mesh qu'une seule fois a la toute fin (pas un rebuild par
## niveau creuse, meme raisonnement perf que le cache par couche de
## VoxelMeshBuilder.gd).
func _remove_block_silent(x: int, y: int, z: int) -> String:
	var pos := Vector3i(x, y, z)
	if not grid.has(pos):
		push_warning("VoxelWorld.remove_block: case deja vide a (%d, %d, %d)" % [x, y, z])
		return ""
	var type: int = grid[pos]
	grid.erase(pos)
	var vein_id: String = ""
	if vein_system.vein_grid.has(pos):
		vein_id = vein_system.vein_grid[pos]
		vein_system.vein_grid.erase(pos)
	# Miner ce bloc expose ses voisins encore pleins - ils deviennent
	# "decouverts" (voir "discovered"), meme s'ils n'ont jamais ete vus au
	# niveau de coupe courant. C'est cette mise a jour incrementale
	# (seulement 6 voisins, jamais toute la carte) qui remplace le recalcul
	# complet a chaque minage.
	for dir in DIRECTIONS:
		var neighbor_pos: Vector3i = pos + dir
		if grid.has(neighbor_pos) and not discovered.has(neighbor_pos):
			discovered[neighbor_pos] = true
			# Un voisin de pierre qui vient tout juste d'etre decouvert n'a
			# encore jamais eu son filon calcule (voir generate_flat_terrain -
			# le calcul est differe jusqu'a la decouverte reelle, pour ne pas
			# le faire pour toute la roche jamais minee). On le fait ici,
			# une seule fois, au moment ou ce bloc devient visible.
			if grid[neighbor_pos] == BlockType.STONE:
				vein_system.maybe_place_vein(neighbor_pos, VeinMaterials.all())
	# Connectivite (voir "reachable") : ce bloc, maintenant vide, est-il
	# relie a la surface ? Soit il vient d'exposer le ciel (c'etait le
	# sommet reel de sa colonne - cas "trou", toujours accessible), soit un
	# voisin est deja une case vide reliee (cas "couloir" prolonge depuis un
	# point deja accessible). Sinon (couloir creuse via le niveau de vue
	# dans de la roche encore fermee de tous cotes) il reste NON accessible
	# tant qu'un chemin ne le relie pas.
	var is_open_sky: bool = get_top_block_y(x, z) < y
	var has_reachable_neighbor: bool = false
	if not is_open_sky:
		for dir in DIRECTIONS:
			if reachable.has(pos + dir):
				has_reachable_neighbor = true
				break
	if is_open_sky or has_reachable_neighbor:
		_mark_reachable_from(pos)
	if vein_id != "":
		return vein_id
	if type == BlockType.DIRT:
		return "terre"
	elif type == BlockType.STONE:
		return "pierre"
	elif type == BlockType.WOOD_WALL:
		return "bois"
	elif type == BlockType.STONE_WALL:
		return "pierre"
	return ""


## Propage "reachable" par inondation (BFS) depuis "start" (deja vide et
## relie a la surface) a travers les cases vides adjacentes pas encore
## marquees - typiquement 0 ou 1 nouvelle case a chaque minage simple, mais
## peut en relier beaucoup d'un coup si ce minage vient de joindre deux
## poches jusque-la separees.
func _mark_reachable_from(start: Vector3i) -> void:
	if reachable.has(start):
		return
	var queue: Array = [start]
	reachable[start] = true
	while not queue.is_empty():
		var current: Vector3i = queue.pop_back()
		for dir in DIRECTIONS:
			var n: Vector3i = current + dir
			if reachable.has(n):
				continue
			if grid.get(n, BlockType.EMPTY) != BlockType.EMPTY:
				continue
			# Ne jamais suivre le ciel ouvert au-dessus d'une colonne : ces
			# cases sont "vides" simplement parce qu'elles n'ont jamais ete
			# generees (aucune entree dans "grid"), et s'etendent sans limite
			# vers le haut - sans ce garde-fou, la moindre case minee au
			# sommet reel de sa colonne ("trou") declenchait une inondation
			# infinie a travers tout le ciel de la carte, gelant le jeu
			# (feedback Francois 2026-07-08 : gel total sur Creuser/Miner/
			# Escalier). Une case n'est suivie que si elle est au niveau ou
			# EN DESSOUS du sommet reel ACTUEL de sa propre colonne (donc soit
			# deja creusee sous plafond, soit tout juste exposee) - jamais
			# au-dessus.
			if n.y > get_top_block_y(n.x, n.z):
				continue
			reachable[n] = true
			queue.append(n)


## Vrai si un nain peut atteindre ce bloc SOLIDE pour le miner maintenant :
## soit c'est le sommet reel de sa colonne (un "trou" se creuse toujours
## depuis la surface, jamais bloque), soit un de ses 6 voisins est deja une
## case vide reliee a la surface (voir "reachable") - un "couloir" ne se
## creuse que depuis un point deja accessible, pas "dans le vide" via le
## niveau de vue. Consultee par TaskQueue.pop_nearest_task pour ne faire
## executer que les taches "miner" actuellement possibles (la designation,
## elle, reste toujours autorisee - regle Francois 2026-07-08).
func can_reach_block(x: int, y: int, z: int) -> bool:
	if y == get_top_block_y(x, z):
		return true
	var pos := Vector3i(x, y, z)
	for dir in DIRECTIONS:
		if reachable.has(pos + dir):
			return true
	return false


## Etendue de l'escalier de la colonne (x,z), ou {} si aucun escalier n'y a
## ete creuse - voir "stair_columns" plus haut.
func get_stair_range(x: int, z: int) -> Dictionary:
	return stair_columns.get(Vector2i(x, z), {})


## Cherche un escalier permettant a un nain d'atteindre le niveau "to_y" (sa
## future position debout) sur la colonne (to_x,to_z) OU une de ses 4
## voisines immediates (un "couloir" cible part typiquement du pied d'un
## escalier) - portee volontairement limitee a UN SEUL escalier direct par
## trajet (pas de chainage de plusieurs escaliers), voir memoire "Regles de
## pathing des nains". Renvoie {} si aucun escalier ne couvre ce niveau.
func find_connecting_stair(to_x: int, to_z: int, to_y: int) -> Dictionary:
	var candidates: Array = [Vector2i(to_x, to_z),
		Vector2i(to_x + 1, to_z), Vector2i(to_x - 1, to_z),
		Vector2i(to_x, to_z + 1), Vector2i(to_x, to_z - 1)]
	for col in candidates:
		var stair_range: Dictionary = stair_columns.get(col, {})
		if stair_range.is_empty():
			continue
		var top: int = int(stair_range["top"]) + 1
		var bottom: int = int(stair_range["bottom"])
		if to_y < bottom or to_y > top:
			continue
		return {"column": col, "top": top, "bottom": bottom}
	return {}


## Vrai si un nain peut marcher du niveau "from_y" (sa position actuelle) au
## niveau "to_y" sur la colonne (to_x,to_z) - soit un denivele naturel d'au
## plus 1 niveau (toujours autorise, regle 4), soit un denivele plus grand
## mais couvert par un escalier deja creuse (voir find_connecting_stair).
## Ne concerne QUE le deplacement du nain, pas le droit de miner (voir
## can_reach_block - un "trou" reste creusable a n'importe quelle
## profondeur, seule la MARCHE d'un nain y est limitee).
func can_walk_to_level(from_y: int, to_x: int, to_z: int, to_y: int) -> bool:
	if absi(from_y - to_y) <= 1:
		return true
	return not find_connecting_stair(to_x, to_z, to_y).is_empty()


## Vrai si la case contient un bloc (n'importe quel type non-vide) - utilise
## par ActionDragController.gd pour borner l'extension d'un escalier a la
## molette (on ne peut pas creuser un escalier a travers du vide deja mine,
## voir max_stair_bottom).
func is_solid(x: int, y: int, z: int) -> bool:
	return grid.get(Vector3i(x, y, z), BlockType.EMPTY) != BlockType.EMPTY


## Creuse une colonne d'escalier sur plusieurs niveaux d'affilee (geste
## clic+molette+clic, voir ActionDragController.on_stair_click/extend_stair) :
## top_y = niveau de depart (sommet actuel de la colonne, cote surface),
## bottom_y = niveau le plus profond atteint (top_y >= bottom_y). Chaque
## niveau est retire comme un minage classique (_remove_block_silent, memes
## ressources renvoyees) puis marque dans stair_grid selon sa position dans
## la plage :
## - top_y (le plus haut) -> "bas" (l'escalier descend depuis la surface/le
##   niveau ouvert au-dessus, rien en dessous de ce demi-bloc)
## - bottom_y (le plus bas) -> "haut" (l'escalier remonte vers le niveau
##   au-dessus, sol plein juste en dessous)
## - niveaux intermediaires -> "hautbas" (traverse : remonte d'un cote,
##   descend de l'autre)
## - plage d'un seul niveau -> "bas" par defaut (cas limite rare)
## Renvoie les ressources recoltees (nom -> quantite), pour que
## DwarfTaskResolver.gd les ajoute a l'inventaire du nain. Un seul
## rebuild_mesh() a la toute fin (pas un par niveau). Le type de bloc
## (BlockType) est capture AVANT le retrait pour etre conserve dans
## stair_grid - c'est lui qui determine la couleur de la plaque (voir doc de
## stair_grid), pas juste la forme.
func dig_stairs(x: int, z: int, top_y: int, bottom_y: int) -> Dictionary:
	var resources: Dictionary = {}
	var single_level := top_y == bottom_y
	for y in range(top_y, bottom_y - 1, -1):
		var pos := Vector3i(x, y, z)
		if not grid.has(pos):
			continue
		var block_type: int = grid[pos]
		var resource_name := _remove_block_silent(x, y, z)
		if resource_name != "":
			resources[resource_name] = resources.get(resource_name, 0) + 1
		var piece_type: String
		if single_level:
			piece_type = "bas"
		elif y == top_y:
			piece_type = "bas"
		elif y == bottom_y:
			piece_type = "haut"
		else:
			piece_type = "hautbas"
		stair_grid[pos] = {"piece": piece_type, "material": block_type}
	# Etendue de la colonne (voir "stair_columns") - fusionnee avec une
	# eventuelle etendue existante (geste "etendre l'escalier" sur une
	# colonne deja partiellement creusee) pour toujours couvrir le sommet le
	# plus haut et le fond le plus bas creuses sur cette colonne.
	var col_key := Vector2i(x, z)
	var existing_range: Dictionary = stair_columns.get(col_key, {})
	var merged_top: int = maxi(existing_range.get("top", top_y), top_y)
	var merged_bottom: int = mini(existing_range.get("bottom", bottom_y), bottom_y)
	stair_columns[col_key] = {"top": merged_top, "bottom": merged_bottom}
	rebuild_mesh()
	return resources


## Remplit la grille : pierre en bas, terre au-dessus, avec un relief de
## collines (voir hill_amplitude/_hill_height_at). La terre reste limitee aux
## DIRT_HEIGHT_MIN..DIRT_HEIGHT_MAX niveaux du haut du CUBE plein (tire au
## sort par colonne) ; dans la pierre en dessous,
## chaque bloc a une chance (par materiau, voir vein_noises/
## RARITY_THRESHOLDS) de devenir un filon plutot que de la pierre nue.
## Modele CUBE+SOL (Francois 2026-07-09, "1 layer = 1 bloc = CUBE+SOL") : la
## couche "surface_y" elle-meme n'est PLUS un CUBE plein pour une colonne
## SECHE - elle reste vide (CUBE=vide, SOL=terre via get_sol()) car
## Francois l'a confirme explicitement : "l'herbe est le SOL de la surface
## qui a un cube vide". Le CUBE plein (dont les niveaux de terre, voir
## DIRT_HEIGHT_MIN/MAX) descend donc d'un cran, jusqu'a "fill_top_y" =
## surface_y - 1. Les
## colonnes D'EAU restent inchangees (fill_top_y = surface_y, pas de couche
## vide au-dessus - decision Francois 2026-07-08 : CUBE=SOL=eau, aucun lit
## distinct).
func generate_flat_terrain() -> void:
	var veins: Array = VeinMaterials.all()  # deja triee du plus rare au plus commun
	# Flux dedie "sous_sol" (meme nom que CubeSolTestV2.gd) pour la hauteur de
	# terre aleatoire par colonne - recupere UNE SEULE FOIS avant la boucle
	# (comme terrain_rng plus haut dans _ready()), puis randi_range() appele a
	# chaque colonne pour avancer l'etat plutot que de retirer le meme flux a
	# chaque fois (ce qui redonnerait la meme valeur partout).
	var dirt_rng: RandomNumberGenerator = GameRandom.get_rng("sous_sol")
	# Colonnes (x,z) couvertes par un lac ou la riviere -> profondeur en
	# niveaux, PLUS le decalage de relief force pour ces colonnes (lacs
	# aplatis, riviere en paliers) et les colonnes de cascade (voir
	# _compute_water_columns/_place_lakes/_place_river) - calcule une seule
	# fois avant la triple boucle.
	var water_info: Dictionary = _compute_water_columns()
	var water_columns: Dictionary = water_info["cols"]
	var hill_overrides: Dictionary = water_info["hill_overrides"]
	var waterfalls: Dictionary = water_info["waterfalls"]
	# Colonnes de berge (terrain solide, PAS d'eau) juste a cote d'une
	# cascade, a reveler d'emblee comme une vraie falaise visible - voir
	# _place_river/_compute_water_columns.
	var bank_faces: Dictionary = water_info["bank_faces"]
	# La boucle Y doit monter au-dela de HEIGHT-1 pour les colonnes en
	# colline (surface_y peut atteindre HEIGHT-1+hill_amplitude).
	var max_y: int = HEIGHT + int(ceil(hill_amplitude))
	for x in range(WIDTH):
		for z in range(DEPTH):
			var pos2d := Vector2i(x, z)
			var is_edge_column: bool = x == 0 or x == WIDTH - 1 or z == 0 or z == DEPTH - 1
			var water_depth: int = water_columns.get(pos2d, 0)
			var hill_offset: int = hill_overrides.get(pos2d, _hill_height_at(x, z))
			var surface_y: int = HEIGHT - 1 + hill_offset
			var waterfall: Dictionary = waterfalls.get(pos2d, {})
			var bank_face: Dictionary = bank_faces.get(pos2d, {})
			# REVERT 2026-07-09 (Francois : "ca a supprime le relief" - je
			# n'ai pas reussi a isoler le mecanisme exact malgre plusieurs
			# verifications de l'arithmetique, donc je restaure le
			# comportement d'origine ici par prudence plutot que de
			# continuer a deviner sur du code qui touche a toute la carte).
			# fill_top_y = surface_y partout (plus de decalage -1 pour les
			# colonnes seches) - le "CUBE vide + SOL terre" en surface sera
			# reobtenu autrement (voir memoire "Modele CUBE+SOL").
			var fill_top_y: int = surface_y
			var dirt_height: int = dirt_rng.randi_range(DIRT_HEIGHT_MIN, DIRT_HEIGHT_MAX)
			# Berge de riviere/lac GENERALE (2026-07-10, bug Francois : "mur
			# de 2 niveaux, le premier niveau est transparent") - meme
			# principe que "is_bank_face" plus bas (reserve aux rangees de
			# cascade), mais pour TOUTE colonne seche adjacente a une
			# colonne d'eau plus basse (riviere loin d'une chute, ou bord de
			# lac). Sans ca, seul le sommet (y == fill_top_y) est
			# "decouvert" : une berge de 2+ niveaux laisse un ou plusieurs
			# blocs intermediaires jamais decouverts, donc absents du
			# maillage (VoxelMeshBuilder ne dessine que "discovered") - un
			# vrai trou, pas juste gris.
			var river_bank_reveal_bottom: int = fill_top_y + 1  # aucune reveal par defaut
			if water_depth == 0:
				for dir2d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var npos: Vector2i = pos2d + dir2d
					if npos.x < 0 or npos.x >= WIDTH or npos.y < 0 or npos.y >= DEPTH:
						continue
					var n_water_depth: int = water_columns.get(npos, 0)
					if n_water_depth == 0:
						continue
					var n_hill_offset: int = hill_overrides.get(npos, _hill_height_at(npos.x, npos.y))
					var n_surface_y: int = HEIGHT - 1 + n_hill_offset
					if n_surface_y >= surface_y:
						continue
					river_bank_reveal_bottom = mini(river_bank_reveal_bottom, n_surface_y - n_water_depth + 1)
			for y in range(max_y):
				var type := BlockType.EMPTY
				if y <= fill_top_y:
					type = BlockType.STONE
					if y > fill_top_y - dirt_height:
						type = BlockType.DIRT
				# Remplace les "water_depth" derniers niveaux (depuis la
				# surface DE CETTE COLONNE) par de l'eau, au lieu du seul
				# bloc du dessus - c'est ce qui donne une vraie profondeur en
				# nombre de niveaux, visible en descendant avec la molette.
				# La profondeur est plafonnee (voir water_depth_at) pour que
				# l'eau ne s'etende jamais au-dela du niveau -1 en descendant.
				if water_depth > 0 and y > surface_y - water_depth and y <= surface_y:
					type = BlockType.WATER
				# Le segment vertical entre le bassin et le haut de la chute
				# n'est PAS force en eau ici : ca enterrerait la vraie
				# surface du bassin (calculee juste au-dessus, "water_depth")
				# sous cette colonne verticale, ne laissant que la face tout
				# en haut de la chute exposee. La forme decorative de la
				# cascade (quart de cylindre, voir WaterfallShapes.gd) couvre
				# deja visuellement tout le vide entre le bassin et le
				# sommet, le bassin garde donc sa vraie surface d'eau (le
				# remplissage "water_depth" juste au-dessus suffit).
				if type == BlockType.EMPTY:
					continue
				var pos := Vector3i(x, y, z)
				grid[pos] = type
				# "Decouvert" des le depart pour la surface (dessus expose au
				# ciel, surface_y tient compte du relief) et pour les
				# colonnes en bordure de carte (paroi exterieure deja
				# visible, comme une falaise) - voir "discovered" plus haut.
				# Le reste (interieur de la roche, jamais minee) reste gris
				# tant qu'aucun minage ne l'expose. L'eau (tous ses niveaux)
				# est egalement "decouverte" d'emblee - ce n'est pas de la
				# roche a miner pour la reveler, elle doit rester visible en
				# descendant a travers un lac/une riviere/une cascade. Le lit
				# solide juste SOUS l'eau est lui aussi decouvert d'emblee -
				# c'est la "vraie" surface de ces colonnes.
				var is_water_floor: bool = water_depth > 0 and y == surface_y - water_depth
				# Ne decouvre que la chute d'eau elle-meme (du fond du bassin
				# au sommet de la cascade), PAS la roche pleine sous le
				# bassin - meme regle que "is_water_floor" ailleurs sur la
				# carte (juste le lit solide immediatement sous l'eau).
				var is_waterfall_face: bool = not waterfall.is_empty() and y >= int(waterfall["bottom"]) - 1 and y <= int(waterfall["top"])
				# Une berge a cote d'une cascade doit se voir comme une vraie
				# falaise (elle doit "exister", pas rester cachee sous le
				# brouillard de guerre comme de la roche jamais minee) -
				# meme etendue verticale que la chute d'eau elle-meme juste
				# a cote.
				var is_bank_face: bool = not bank_face.is_empty() and y >= int(bank_face["bottom"]) - 1 and y <= int(bank_face["top"])
				var is_river_bank_face: bool = y >= river_bank_reveal_bottom
				if y == fill_top_y or is_edge_column or type == BlockType.WATER or is_water_floor or is_waterfall_face or is_bank_face or is_river_bank_face:
					discovered[pos] = true
					# Le filon d'un bloc de pierre n'a d'interet que s'il peut
					# un jour etre vu ou mine - le calculer pour TOUTE la
					# pierre de la carte (y compris les millions de blocs
					# jamais decouverts en profondeur) etait de tres loin le
					# plus gros cout de la generation sur une grande carte
					# (jusqu'a 17 evaluations de bruit par bloc de pierre). On
					# ne le calcule donc plus qu'ici, au moment ou le bloc
					# devient reellement visible - voir aussi remove_block()
					# pour le meme calcul differe lors du minage (blocs
					# nouvellement exposes). Resultat identique (le bruit ne
					# depend que de la position/seed), seul le MOMENT du
					# calcul change.
					if type == BlockType.STONE:
						vein_system.maybe_place_vein(pos, veins)
	# Conserve la liste des colonnes de cascade (voir declaration de
	# "waterfall_columns" plus haut) pour WaterfallStreaks.gd - le
	# dictionnaire local "waterfalls" ci-dessus serait sinon perdu a la fin
	# de cette fonction.
	waterfall_columns.clear()
	for pos2d in waterfalls:
		var wf: Dictionary = waterfalls[pos2d]
		# Vector2i n'a que "x" et "y" (jamais "z"), meme quand son 2e
		# composant represente l'axe Z du monde (convention utilisee partout
		# ailleurs dans ce fichier, ex. Vector2i(i, cross) plus haut).
		waterfall_columns.append({
			"x": pos2d.x,
			"z": pos2d.y,
			"top": int(wf["top"]),
			"bottom": int(wf["bottom"]),
			# Direction du courant (vers ou l'eau tombe) - necessaire a
			# WaterfallShapes.gd pour orienter le quart de cylindre.
			"dx": int(wf.get("dx", 0)),
			"dz": int(wf.get("dz", 0)),
			"pool_surface_y": int(wf.get("pool_surface_y", wf["bottom"])),
		})


## Liste des colonnes de cascade de la carte courante, chaque entree =
## {"x":int, "z":int, "top":int, "bottom":int, "dx":int, "dz":int,
## "pool_surface_y":int} (memes valeurs Y que celles utilisees pour remplir
## d'eau la colonne dans generate_flat_terrain). Utilise par
## WaterfallStreaks.gd (traits decoratifs) et WaterfallShapes.gd (forme
## quart de cylindre/quart de sphere) pour ne pas dupliquer la logique de
## _place_river.
func get_waterfall_columns() -> Array:
	return waterfall_columns


## Calcule l'ensemble des colonnes (x,z) couvertes par un lac ou la riviere
## (voir _place_lakes/_place_river). Renvoie un Dictionary a 3 cles - "cols"
## (profondeur d'eau, cle = Vector2i), "hill_overrides" (decalage de relief
## FORCE pour ces colonnes - lacs aplatis a 0, riviere en paliers hauts/bas),
## "waterfalls" (colonnes de cascade, cle = Vector2i, valeur = {"top": y,
## "bottom": y} - segment vertical rempli d'eau).

# Generation lacs/riviere/cascades (_place_lakes/_place_river) vit dans
# VoxelHydrology.gd. _compute_water_columns() reste ici comme facade fine :
# generate_flat_terrain() (qui l'appelle) n'a pas besoin de savoir ou vit
# l'implementation.
const VoxelHydrologyScript := preload("res://scripts/monde/voxel/VoxelHydrology.gd")
var hydrology: VoxelHydrologyScript = VoxelHydrologyScript.new()


func _compute_water_columns() -> Dictionary:
	# WIDTH/DEPTH passes en parametres (comme VoxelMeshBuilder.rebuild()) au
	# lieu d'etre dupliques en const dans VoxelHydrology.gd - c'est cette
	# duplication qui avait cause le bug C19 quand la carte etait passee de
	# 100x100 a 250x250.
	return hydrology.compute_water_columns(water_noise, Callable(self, "_hill_height_at"), WIDTH, DEPTH)


func get_block(pos: Vector3i) -> int:
	return grid.get(pos, BlockType.EMPTY)


# Construction du mesh (rebuild_mesh, choix des buckets/couleurs, ajout des
# quads) vit dans VoxelMeshBuilder.gd. rebuild_mesh() reste ici comme facade
# fine : l'API publique de VoxelWorld.gd ne change pas (set_view_level/
# build_block/remove_block/... y font toujours simplement rebuild_mesh()).
const VoxelMeshBuilderScript := preload("res://scripts/monde/voxel/VoxelMeshBuilder.gd")
var mesh_builder: VoxelMeshBuilderScript = VoxelMeshBuilderScript.new()


## grid_changed (true par defaut) : transmis a VoxelMeshBuilder.rebuild(),
## qui invalide son cache par couche uniquement si vrai (voir sa doc, perf
## 2026-07-08). A laisser au defaut (true) partout SAUF depuis
## set_view_level(), le seul appelant qui ne touche ni grid/discovered ni
## climat/saison/neige - tous les autres (build_block/remove_block/
## set_climate_state/generation initiale/SeasonSystem.gd) gardent le
## comportement historique (invalidation systematique, donc toujours a jour).
##
func rebuild_mesh(grid_changed: bool = true) -> void:
	mesh_builder.rebuild(grid, discovered, vein_system, view_level, WIDTH, DEPTH,
			is_frozen, snow_coverage, climate_id, season_id, terrain_noise, stone_noise,
			DIRECTIONS, mesh_instance, Callable(self, "get_top_block_y"), stair_grid, grid_changed,
			Callable(self, "get_sol"))
