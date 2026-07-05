extends Node3D
## Sprint 1 : genere une petite carte de test plate (terre sur pierre)
## et construit un mesh unique par materiau, en ne dessinant que les
## faces exposees (culling des faces cachees / internes).
## Sprint 21 : le dessus "terre" (l'herbe) n'utilise plus le damier
## clair/fonce mais une couleur de base par climat/saison (ClimateDefinitions),
## avec une legere variation continue par case (bruit) pour casser la
## monotonie sans redessiner un motif regulier. Le damier reste inchange
## pour la pierre (utile pour reperer les trous mines) et pour les murs.
## Sprint 23 : profondeur agrandie (voir HEIGHT) + filons de metaux/pierres
## precieuses generes aleatoirement dans la pierre (jamais dans la terre,
## niveaux 1-3), visibles a l'oeil (couleur du filon, voir _vein_color_for).
## Note : le Sprint 23quater avait tente une texture d'atlas pour les filons,
## mais provoquait des blocs blancs non resolus (texture non affichee malgre
## un preload valide) - revert complet au Sprint 23ter (couleur unie par
## materiau) le temps de comprendre la vraie cause.
## Sprint 23sexies : ajout de "pepites" 3D (petites spheres) incrustees sur les
## faces exposees des blocs de filon, en plus de la couleur de fond - rondes et
## lisses pour les metaux (metallic/roughness), a facettes (maillage a peu de
## segments, orientation aleatoire) et legerement lumineuses pour les pierres
## precieuses. Aucune image/texture/shader : uniquement des SphereMesh integres
## au moteur + MultiMeshInstance3D + couleur par instance (meme principe que la
## couleur par sommet utilisee pour l'herbe/la pierre/les filons), pour eviter
## de retomber sur le bug de blocs blancs du Sprint 23quater.
## Sprint 36 (2026-07-03) : lacs + une riviere traversant la carte, demande
## explicite ("on va creer des lacs et des rivieres et gerer la soif des
## nains"). L'eau est un vrai bloc de terrain (BlockType.WATER, voir
## generate_flat_terrain), qui remplace la terre/pierre sur "water_depth"
## niveaux depuis la surface (Sprint 36bis : 1 a 3 niveaux pour un lac, 1 pour
## la riviere, demande explicite - voir LAKE_DEPTH_MIN/MAX/RIVER_DEPTH) - la
## carte reste plate en X/Z (pas de vraie depression creusee dans le sol
## visible de haut, coherent avec le style "terrain plat" d'origine), mais la
## profondeur se revele en descendant avec la molette (comme pour la roche).
## Les nains ne minent pas l'eau (voir ActionController._valid_mine_rect_cells) :
## elle se "puise" (nouveau bouton Puiser, ressource renouvelable ajoutee a
## l'inventaire sans retirer le bloc,
## voir Dwarf.gd/_complete_task "puiser").

const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")
const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")

# Decoupage VoxelWorld.gd (2026-07-05, revue de code item C1) : tout ce qui
# concerne les filons/pepites (bruit, placement, MultiMeshInstance3D) a ete
# deplace dans VoxelVeins.gd - relocalisation pure, voir ce fichier pour le
# detail. "vein_system" porte desormais lui-meme vein_grid/vein_noises/
# metal_pepites/gem_pepites (avant : membres directs de VoxelWorld.gd).
const VoxelVeinsScript := preload("res://scripts/monde/voxel/VoxelVeins.gd")
var vein_system: VoxelVeinsScript = VoxelVeinsScript.new()

# Dimensions de la carte. 2026-07-03 : 20x20x30 -> 100x100x50 (voir memoire
# "map resize" - plusieurs autres scripts dupliquent ces valeurs et doivent
# etre mis a jour en meme temps : CameraRig.grid_height, ActionController.
# GRID_WIDTH/GRID_DEPTH, Forest/BerryBushes/GroundDecoration/Dwarf.grid_width/
# grid_depth, Forest/Dwarf.ground_level.
const WIDTH := 100   # axe X
const DEPTH := 100   # axe Z
const HEIGHT := 50  # axe Y (hauteur totale, y=0 = fond)

# Nombre de niveaux de terre en surface (le reste en dessous = pierre)
const DIRT_HEIGHT := 3

# Marge au-dessus du terrain pour pouvoir construire des murs en hauteur (Sprint 7)
const BUILD_CEILING := HEIGHT + 10

enum BlockType { EMPTY, DIRT, STONE, WOOD_WALL, STONE_WALL, WATER }

# WATER_COLOR (couleur eau/bucket 12) deplace dans VoxelMeshBuilder.gd
# (decoupage 2026-07-05) - historique des reglages successifs conserve la-bas.

# LAKE_COUNT/LAKE_RADIUS_MIN/MAX/RIVER_HALF_WIDTH/LAKE_DEPTH_MIN/MAX/
# RIVER_DEPTH deplaces (dupliques en const, meme convention que WIDTH/DEPTH)
# dans VoxelHydrology.gd (decoupage 2026-07-05) - historique des reglages
# successifs et des regles physiques (R1-R3/C1-C5) conserve la-bas.

# Sprint 37 (2026-07-04, backlog Phase 1 items 1-2) : etat climat global (pas
# par case, voir TemperatureSystem.gd), lu par VoxelMeshBuilder.gd pour la
# couleur eau/glace (ICE_COLOR/SNOW_COLOR, deplacees la-bas, decoupage
# 2026-07-05) - reste ici (is_frozen/snow_coverage) car set_climate_state()
# (API publique appelee par TemperatureSystem.gd) les modifie.
var is_frozen: bool = false
var snow_coverage: float = 0.0  # 0..1, pilote par TemperatureSystem.gd

# Grille du monde : cle = Vector3i (position bloc), valeur = BlockType
var grid: Dictionary = {}

# Sprint 23 : filons (position -> id materiau). Deplace dans vein_system
# (VoxelVeins.gd, decoupage 2026-07-05) - voir vein_system.vein_grid.
# Dictionnaire separe plutot qu'un nouveau BlockType par materiau : evite de
# faire exploser l'enum BlockType et le systeme de buckets pour chaque metal/
# pierre precieuse (voir _bucket_for/_vein_color_for : un seul bucket
# supplementaire, colore par sommet, sert pour tous les materiaux).

# Sprint 35 (2026-07-03) : "brouillard de guerre" souterrain - un bloc est
# "decouvert" (cle presente, valeur toujours true) des qu'on connait deja son
# apparence : la surface naturelle (exposee au ciel depuis le debut), les
# bords de la carte (falaise visible depuis l'exterieur, deja "exposee" avant
# meme de creuser), ou un bloc devenu adjacent a du vide suite a un minage/
# une construction (voir remove_block/build_block). Tant qu'un bloc n'est pas
# dans ce dictionnaire, on ne dessine PAS sa vraie couleur/son filon (voir
# rebuild_mesh) - juste une face grise generique s'il se trouve exactement au
# niveau de coupe courant (view_level). Objectif double : (1) ne plus reveler
# le contenu de la roche jamais minee juste en faisant defiler le niveau de
# vue (demande explicite), et (2) eviter de parcourir/colorer en detail des
# centaines de milliers de blocs jamais explores a chaque changement de
# niveau - seul cet ensemble "decouvert" (petit au depart, grandit lentement
# au fil du minage) est parcouru en detail, voir rebuild_mesh.
var discovered: Dictionary = {}

# UNDISCOVERED_COLOR (couleur des blocs jamais decouverts, voir "discovered"
# ci-dessus) deplace dans VoxelMeshBuilder.gd (decoupage 2026-07-05).

# 6 directions possibles autour d'un bloc (droite/gauche/haut/bas/avant/arriere)
const DIRECTIONS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


var mesh_instance: MeshInstance3D

# Sprint 23bis : niveau de "coupe" visible (correction du systeme de niveaux
## de CameraRig.gd, qui ne faisait jusqu'ici que deplacer la camera sans rien
## cacher du terrain - inutile pour voir un niveau souterrain puisque tout est
## plein). Tout bloc strictement au-dessus de view_level n'est pas dessine du
## tout, et le dessus des blocs exactement a view_level est toujours dessine
## (meme si un bloc existait juste au-dessus dans la grille), ce qui revele
## une coupe horizontale complete du niveau courant, avec ses couleurs
## (damier pierre, filons...). Pilote par CameraRig.set_view_level().
## Sprint 38 (2026-07-04, relief) : la valeur de depart (HEIGHT-1) est
## corrigee dans _ready() pour tenir compte de hill_amplitude (sinon les
## collines, plus hautes que HEIGHT-1, seraient invisibles au demarrage -
## voir VIEW_LEVEL_MARGIN_ABOVE plus bas, deja prevu pour ce cas).
var view_level: int = HEIGHT - 1

# Sprint 21 : climat/saison utilises pour la couleur du terrain (voir
# ClimateDefinitions.gd). Une seule saison geree pour l'instant, mais ces
# exports permettent deja de changer de climat/saison sans toucher au code.
@export var climate_id: String = "tempere"
@export var season_id: String = "ete"

## Sprint 38 (2026-07-04, demande explicite : "ajouter quelques collines qui
## vont dependre d'un parametre de relief du terrain") : amplitude maximale
## des collines, en nombre de blocs au-dessus de la surface de base (HEIGHT-1)
## - parametre expose (reglable dans l'inspecteur Godot ou par script) plutot
## qu'une constante en dur, comme demande. "Douce" par defaut (2-4 blocs).
@export var hill_amplitude: float = 3.0

# Bruit utilise pour la variation subtile de couleur de l'herbe, case par
# case (voir _grass_color_for). Frequence basse => variation douce/continue,
# tres different d'un damier ou d'un bruit purement aleatoire par case.
var terrain_noise := FastNoiseLite.new()

# Sprint 23ter : meme principe que terrain_noise, mais pour la pierre (voir
# _stone_color_for). Bruit separe pour que les variations de l'herbe et de la
# pierre ne soient pas correlees (pas la meme "forme" de variation).
var stone_noise := FastNoiseLite.new()

# Sprint 36 : bruit utilise pour casser le contour parfaitement circulaire des
# lacs (voir _place_lakes) - un cercle "pur" serait trop artificiel/regulier.
var water_noise := FastNoiseLite.new()

## Sprint 38 (2026-07-04, relief) : bruit de hauteur des collines - frequence
## TRES basse (0.02, contre 0.18 pour terrain_noise) pour que le relief monte
## et descende doucement sur plusieurs dizaines de cases, jamais case par
## case (evite un terrain "en dents de scie", voir _hill_height_at).
var hill_noise := FastNoiseLite.new()

# STONE_BASE (couleur de base de la pierre) deplace dans VoxelMeshBuilder.gd
# (decoupage 2026-07-05) - voir _stone_color_for la-bas.

# Bruits de filon, pepites (metal_pepites/gem_pepites) et constantes associees
# (PEPITE_*) deplaces dans vein_system (VoxelVeins.gd, decoupage 2026-07-05).

## Sprint 49 (2026-07-04, "traits en bleu clair et blanc pour montrer l'eau qui
## tombe") : liste des colonnes de cascade calculees a la generation du terrain
## (voir generate_flat_terrain/_place_river), conservee ici (le dictionnaire
## "waterfalls" original n'etait qu'une variable locale, jetee apres usage) pour
## qu'un script decoratif externe (WaterfallStreaks.gd) puisse la lire via
## get_waterfall_columns() et placer ses traits SANS dupliquer la logique de
## generation de riviere.
var waterfall_columns: Array = []

## Sprint 34bis (2026-07-03) : mesure de duree de generation du monde, pour
## savoir combien de temps prend le chargement de la carte 100x100x50 -
## initialise ici (premier script "lourd" a demarrer, voir ordre des noeuds
## dans Main.tscn), lu par GroundDecoration.gd (dernier script "lourd" a
## finir son _ready()) pour calculer et afficher la duree totale dans la
## console Godot. "static" = partage entre tous les scripts qui preloadent
## VoxelWorld.gd (voir GroundDecoration.gd), pas besoin d'une instance.
static var world_gen_start_ms: int = 0

## Sprint 80 (2026-07-04, demande explicite de Francois : "un menu au
## lancement pour choisir si on regenere la map, sinon c'est difficile de
## tester les corrections") : StartMenu.gd (nouvel ecran affiche avant
## Main.tscn, voir project.godot) ecrit ces 2 valeurs AVANT le changement de
## scene. "static" = memes valeurs lues ici via le meme script preload,
## comme world_gen_start_ms ci-dessus. Si use_fixed_seed est faux, une
## graine aleatoire est tiree ET affichee en console (pour pouvoir la
## reutiliser plus tard si un bug interessant apparait).
static var use_fixed_seed: bool = false
static var requested_seed: int = 0


func _ready() -> void:
	world_gen_start_ms = Time.get_ticks_msec()
	var active_seed: int = requested_seed
	if not use_fixed_seed:
		randomize()
		active_seed = randi()
	# "seed()" (fonction globale Godot) fixe l'etat de TOUT le generateur
	# aleatoire global du jeu - pas seulement celui de VoxelWorld.gd. Comme
	# Forest.gd/BerryBushes.gd/GroundDecoration.gd utilisent aussi randf()/
	# randi_range() global (pas leur propre generateur), la MEME graine
	# reproduit donc la carte ENTIERE a l'identique (relief, lacs, riviere,
	# cascades, arbres, buissons, decorations), pas seulement le terrain.
	# 2026-07-05 : cette affirmation etait FAUSSE (revue de code, item C2) -
	# Forest.gd/BerryBushes.gd/GroundDecoration.gd (+ WaterfallFoamClouds.gd/
	# WaterfallStreaks.gd/Birds.gd/CloudSystem.gd) appelaient chacun leur
	# propre randomize() en tete de _ready(), qui reinitialisait ce meme
	# generateur global de facon non deterministe juste apres. Corrige (C2-C6
	# + I9) : ces randomize() ont ete retires, l'affirmation ci-dessus est
	# desormais vraie.
	seed(active_seed)
	print("Forgotten Caves - graine de la carte utilisee : ", active_seed)
	terrain_noise.seed = randi()
	terrain_noise.frequency = 0.18
	stone_noise.seed = randi()
	stone_noise.frequency = 0.18
	water_noise.seed = randi()
	water_noise.frequency = 0.15
	hill_noise.seed = randi()
	hill_noise.frequency = 0.02
	# Sprint 38 : le niveau de coupe par defaut doit couvrir toute l'amplitude
	# des collines (sinon leur sommet, plus haut que HEIGHT-1, resterait
	# invisible tant qu'on n'a pas remonte la molette a la main).
	view_level = HEIGHT - 1 + int(ceil(hill_amplitude))
	vein_system.setup_vein_noises()
	generate_flat_terrain()
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	vein_system.setup_pepites_nodes(self)
	rebuild_mesh()


## Sprint 37octies (2026-07-04, demande explicite Francois : "les niveaux
## geres par la molette doivent permettre de monter au dessus de 0, on aura
## des reliefs dans le futur") : marge de niveaux vides au-dessus de la
## surface actuelle (HEIGHT-1) - rien n'y est genere pour l'instant (grid
## n'a aucune entree la-bas, donc rebuild_mesh n'y dessine rien), mais la
## camera/la molette peuvent deja s'y deplacer, prete pour un futur relief
## (collines/montagnes) sans dependre d'un redimensionnement de HEIGHT.
const VIEW_LEVEL_MARGIN_ABOVE := 15

## Sprint 23bis : change le niveau de "coupe" visible (voir view_level) et
## reconstruit le mesh en consequence. Appele par CameraRig a chaque
## changement de niveau (molette de la souris).
func set_view_level(level: int) -> void:
	view_level = clampi(level, 0, HEIGHT - 1 + VIEW_LEVEL_MARGIN_ABOVE)
	rebuild_mesh()


## Sprint 38 (2026-07-04) : hauteur de colline (en blocs, 0..hill_amplitude)
## a une position (x,z), a partir d'un bruit tres lisse (voir hill_noise) -
## get_noise_2d renvoie -1..1, remis a l'echelle 0..1 puis multiplie par
## hill_amplitude et arrondi (hauteur de bloc = entier). Utilisee par
## generate_flat_terrain pour decaler la surface de base (HEIGHT-1) ;
## surchargee a une valeur fixe pour les colonnes d'eau (lacs aplatis, riviere
## en paliers - voir _compute_water_columns) plutot que d'utiliser le bruit
## brut, pour eviter un lac/une riviere qui "epouserait" chaque bosse.
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


## Indique si on peut encore construire en hauteur sur cette colonne
func can_build(x: int, z: int) -> bool:
	return get_top_block_y(x, z) + 1 < BUILD_CEILING


## Sprint 36 : indique si le sommet de la colonne (x,z) est de l'eau - utilise
## par ActionController pour le bouton "Puiser" (ne cible que l'eau) et pour
## exclure l'eau du bouton "Miner" (voir _valid_mine_rect_cells).
func is_water(x: int, z: int) -> bool:
	var y: int = get_top_block_y(x, z)
	if y < 0:
		return false
	return get_block(Vector3i(x, y, z)) == BlockType.WATER


## Sprint 37 (backlog Phase 1 item 13b) : profondeur d'eau (en niveaux) de la
## colonne (x,z), 0 si ce n'est pas de l'eau - utilise par Dwarf.gd pour
## n'autoriser la traversee a pied que jusqu'a 1 niveau de profondeur (lacs
## plus profonds = a contourner, voir _pick_new_target/_find_dry_target).
## Sprint 37septies : la profondeur est de nouveau plafonnee (RIVER_DEPTH/
## LAKE_DEPTH_MIN = 2, LAKE_DEPTH_MAX = 3, voir generate_flat_terrain) - cette
## fonction retourne donc a nouveau 2 ou 3 pour une colonne d'eau (jamais 1,
## donc tout lac/riviere reste "profond" au sens de Dwarf.gd, contourne a
## pied plutot que traverse).
func water_depth_at(x: int, z: int) -> int:
	if not is_water(x, z):
		return 0
	var depth := 0
	# Sprint 38 (relief) : demarre desormais du sommet REEL de la colonne
	# (get_top_block_y) plutot que HEIGHT-1 fixe - une colonne de cascade peut
	# avoir de l'eau au-dessus de HEIGHT-1 (voir _place_river/"waterfalls"),
	# et une colonne en colline peut avoir son sommet plus haut aussi.
	var y := get_top_block_y(x, z)
	while y >= 0 and get_block(Vector3i(x, y, z)) == BlockType.WATER:
		depth += 1
		y -= 1
	return depth


## Sprint 37 (backlog Phase 1 items 1-2) : met a jour l'etat climat global
## (gel/neige, voir "is_frozen"/"snow_coverage" plus haut) et reconstruit le
## mesh SEULEMENT si quelque chose a reellement change - appele par
## TemperatureSystem.gd, qui se charge deja de ne pas appeler cette fonction a
## chaque frame (voir son commentaire sur le cout de rebuild_mesh).
func set_climate_state(frozen: bool, snow: float) -> void:
	if frozen == is_frozen and is_equal_approx(snow, snow_coverage):
		return
	is_frozen = frozen
	snow_coverage = snow
	rebuild_mesh()


## Indique si le sommet de la colonne (x,z) est de la terre (Sprint 19 :
## utilise pour placer les decorations de sol, on ne decore que l'herbe/terre,
## pas la pierre nue ni les murs construits). Renvoie un bool plutot que
## d'exposer l'enum BlockType, pour eviter le probleme de typage deja
## rencontre (voir Dwarf.gd/ActionController.gd : un script qui recupere
## %VoxelWorld via un type generique Node3D ne peut pas resoudre un enum
## defini uniquement dans ce script).
func is_dirt_top(x: int, z: int) -> bool:
	var y: int = get_top_block_y(x, z)
	if y < 0:
		return false
	return get_block(Vector3i(x, y, z)) == BlockType.DIRT


## Sprint 25 : type + materiau du bloc du sommet de la colonne (x,z), pour la
## fenetre d'info au clic (voir ActionController._describe_block). Renvoie des
## chaines ("terre"/"pierre"/"mur_bois"/"mur_pierre"/"vide") plutot que l'enum
## BlockType, meme raison que is_dirt_top ci-dessus (l'enum n'est pas resolvable
## depuis un script qui recupere %VoxelWorld via un type generique Node3D).
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
## empilant sur ce qui existe deja (fonctionne aussi bien pour reboucher
## un trou mine que pour construire en hauteur sur un sol plein)
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
	# Sprint 35 : un bloc qu'on vient de construire soi-meme est par definition
	# deja "connu" (voir "discovered") - jamais gris.
	discovered[built_pos] = true
	rebuild_mesh()


## Retire un bloc de la grille (mine/creuse), reconstruit le mesh, et renvoie
## le nom de la ressource obtenue ("terre", "pierre", ou l'id d'un filon comme
## "fer"/"rubis" - Sprint 23) ou "" si rien a miner
func remove_block(x: int, y: int, z: int) -> String:
	var pos := Vector3i(x, y, z)
	if not grid.has(pos):
		return ""
	var type: int = grid[pos]
	grid.erase(pos)
	var vein_id: String = ""
	if vein_system.vein_grid.has(pos):
		vein_id = vein_system.vein_grid[pos]
		vein_system.vein_grid.erase(pos)
	# Sprint 35 : miner ce bloc expose ses voisins encore pleins - ils
	# deviennent "decouverts" (voir "discovered"), meme s'ils n'ont jamais ete
	# vus au niveau de coupe courant. C'est cette mise a jour incrementale
	# (seulement 6 voisins, jamais toute la carte) qui remplace le recalcul
	# complet a chaque minage.
	for dir in DIRECTIONS:
		var neighbor_pos: Vector3i = pos + dir
		if grid.has(neighbor_pos):
			discovered[neighbor_pos] = true
	# 2026-07-05 (revue de code, item F008) : le print() de diagnostic Sprint 35
	# et son compteur "newly_discovered" (qui ne servait qu'a ce print) sont
	# retires - role diagnostique termine, il ne servait plus qu'a spammer la
	# console et generait un avertissement "variable inutilisee".
	rebuild_mesh()
	if vein_id != "":
		return vein_id
	if type == BlockType.DIRT:
		return "terre"
	elif type == BlockType.STONE:
		return "pierre"
	return ""


## Remplit la grille : pierre en bas, terre au-dessus, avec un relief de
## collines (Sprint 38, voir hill_amplitude/_hill_height_at). Sprint 23 : la
## terre reste limitee aux DIRT_HEIGHT niveaux du haut (niveaux 1-3 depuis la
## surface) ; dans la pierre en dessous, chaque bloc a une chance (par
## materiau, voir vein_noises/RARITY_THRESHOLDS) de devenir un filon plutot
## que de la pierre nue.
func generate_flat_terrain() -> void:
	var veins: Array = VeinMaterials.all()  # deja triee du plus rare au plus commun
	# Sprint 36/36bis/38 : colonnes (x,z) couvertes par un lac ou la riviere ->
	# profondeur en niveaux, PLUS (Sprint 38) le decalage de relief force pour
	# ces colonnes (lacs aplatis, riviere en paliers) et les colonnes de
	# cascade (voir _compute_water_columns/_place_lakes/_place_river) -
	# calcule une seule fois avant la triple boucle.
	var water_info: Dictionary = _compute_water_columns()
	var water_columns: Dictionary = water_info["cols"]
	var hill_overrides: Dictionary = water_info["hill_overrides"]
	var waterfalls: Dictionary = water_info["waterfalls"]
	# Meme sprint (suite, 2026-07-04, application des 5 regles physiques) :
	# colonnes de berge (terrain solide, PAS d'eau) juste a cote d'une
	# cascade, a reveler d'emblee comme une vraie falaise visible - voir
	# _place_river/_compute_water_columns.
	var bank_faces: Dictionary = water_info["bank_faces"]
	# Sprint 38 : la boucle Y doit maintenant monter au-dela de HEIGHT-1 pour
	# les colonnes en colline (surface_y peut atteindre HEIGHT-1+hill_amplitude).
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
			for y in range(max_y):
				var type := BlockType.EMPTY
				if y <= surface_y:
					type = BlockType.STONE
					if y > surface_y - DIRT_HEIGHT:
						type = BlockType.DIRT
				# Sprint 36bis : remplace les "water_depth" derniers niveaux
				# (depuis la surface DE CETTE COLONNE, Sprint 38) par de l'eau,
				# au lieu du seul bloc du dessus - c'est ce qui donne une vraie
				# profondeur en nombre de niveaux, visible en descendant avec la
				# molette. Sprint 37quater avait tente de faire de l'eau une
				# colonne entiere jusqu'au fond (y=0) mais Francois a signale que
				# l'eau s'etendait alors "au dela du niveau -1" en descendant -
				# la profondeur est donc plafonnee ici (Sprint 37septies).
				if water_depth > 0 and y > surface_y - water_depth and y <= surface_y:
					type = BlockType.WATER
				# Sprint 86 (2026-07-04, bug signale par Francois : "sous la
				# cascade il n'y a pas d'eau", violation de la regle C2) :
				# CE remplissage (Sprint 38) forcait TOUT le segment vertical
				# entre le bassin et le haut de la chute en eau, DANS LA MEME
				# colonne que le bassin lui-meme - la vraie surface du bassin
				# (calculee juste au-dessus, "water_depth") se retrouvait donc
				# enterree sous cette colonne verticale, et seule la face tout
				# en haut de la chute restait exposee : le bassin, au pied de
				# la cascade, n'avait plus aucune surface d'eau visible a la
				# bonne hauteur. Le commentaire du Sprint 56 (voir
				# WaterfallShapes.gd/_build_shape) disait deja que ce
				# remplissage devait etre remplace par la forme decorative -
				# jamais fait. Supprime : la forme decorative (quart de
				# cylindre) couvre deja visuellement tout le vide entre le
				# bassin et le sommet, le bassin garde donc sa vraie surface
				# d'eau (le remplissage "water_depth" juste au-dessus suffit).
				if type == BlockType.EMPTY:
					continue
				var pos := Vector3i(x, y, z)
				grid[pos] = type
				if type == BlockType.STONE:
					vein_system.maybe_place_vein(pos, veins)
				# Sprint 35 : "decouvert" des le depart pour la surface (dessus
				# expose au ciel, Sprint 38 : surface_y au lieu de HEIGHT-1 fixe)
				# et pour les colonnes en bordure de carte (paroi exterieure deja
				# visible, comme une falaise) - voir "discovered" plus haut. Le
				# reste (interieur de la roche, jamais minee) reste gris tant
				# qu'aucun minage ne l'expose. Sprint 36bis : l'eau (tous ses
				# niveaux) est egalement "decouverte" d'emblee - ce n'est pas de
				# la roche a miner pour la reveler, elle doit rester visible en
				# descendant a travers un lac/une riviere/une cascade.
				# Sprint 37ter : le lit solide juste SOUS l'eau est lui aussi
				# decouvert d'emblee - c'est la "vraie" surface de ces colonnes.
				var is_water_floor: bool = water_depth > 0 and y == surface_y - water_depth
				# Sprint 38 : ne decouvre que la chute d'eau elle-meme (du fond
				# du bassin au sommet de la cascade), PAS la roche pleine sous
				# le bassin - meme regle que "is_water_floor" ailleurs sur la
				# carte (juste le lit solide immediatement sous l'eau).
				var is_waterfall_face: bool = not waterfall.is_empty() and y >= int(waterfall["bottom"]) - 1 and y <= int(waterfall["top"])
				# Meme sprint (suite, 2026-07-04, application des 5 regles) :
				# une berge a cote d'une cascade doit se voir comme une vraie
				# falaise (regle 1/2 - la berge doit "exister", pas rester
				# cachee sous le brouillard de guerre comme de la roche
				# jamais minee) - meme etendue verticale que la chute d'eau
				# elle-meme juste a cote.
				var is_bank_face: bool = not bank_face.is_empty() and y >= int(bank_face["bottom"]) - 1 and y <= int(bank_face["top"])
				if y == surface_y or is_edge_column or type == BlockType.WATER or is_water_floor or is_waterfall_face or is_bank_face:
					discovered[pos] = true
	# Sprint 49 : conserve la liste des colonnes de cascade (voir declaration de
	# "waterfall_columns" plus haut) pour WaterfallStreaks.gd - le dictionnaire
	# local "waterfalls" ci-dessus serait sinon perdu a la fin de cette fonction.
	waterfall_columns.clear()
	for pos2d in waterfalls:
		var wf: Dictionary = waterfalls[pos2d]
		# Sprint 51 (2026-07-04, crash signale par Francois : "Invalid access to
		# property or key 'z' on a base object of type 'Vector2i'") : Vector2i
		# n'a que "x" et "y" (jamais "z"), meme quand son 2e composant represente
		# l'axe Z du monde (convention utilisee partout ailleurs dans ce fichier,
		# ex. Vector2i(i, cross) plus haut) - "pos2d.z" n'existe pas et plante.
		waterfall_columns.append({
			"x": pos2d.x,
			"z": pos2d.y,
			"top": int(wf["top"]),
			"bottom": int(wf["bottom"]),
			# Sprint 52/56 : direction du courant (vers ou l'eau tombe) -
			# necessaire a WaterfallShapes.gd pour orienter le quart de
			# cylindre. Sprint 56 : "is_corner" retire (plus de sphere, un
			# seul quart de cylindre par colonne, "top" = vrai sommet de la
			# cascade).
			"dx": int(wf.get("dx", 0)),
			"dz": int(wf.get("dz", 0)),
			"pool_surface_y": int(wf.get("pool_surface_y", wf["bottom"])),
		})
	# 2026-07-05 (revue de code, item F007) : le lookup "waterfall_face_dir"
	# construit ici a ete supprime - code mort confirme (Sprint 86), plus
	# aucune lecture ailleurs dans le projet.


## Sprint 49 : liste des colonnes de cascade de la carte courante, chaque entree
## = {"x":int, "z":int, "top":int, "bottom":int, "dx":int, "dz":int,
## "pool_surface_y":int} (memes valeurs Y que celles utilisees pour remplir
## d'eau la colonne dans generate_flat_terrain). Utilise par WaterfallStreaks.gd
## (traits decoratifs) et WaterfallShapes.gd (forme quart de cylindre/quart de
## sphere) pour ne pas dupliquer la logique de _place_river.
func get_waterfall_columns() -> Array:
	return waterfall_columns


## Sprint 36 : calcule l'ensemble des colonnes (x,z) couvertes par un lac ou la
## riviere (voir _place_lakes/_place_river). Sprint 38 : renvoie desormais un
## Dictionary a 3 cles - "cols" (profondeur d'eau, cle = Vector2i, comme avant),
## "hill_overrides" (decalage de relief FORCE pour ces colonnes - lacs aplatis
## a 0, riviere en paliers hauts/bas), "waterfalls" (colonnes de cascade, cle =
## Vector2i, valeur = {"top": y, "bottom": y} - segment vertical rempli d'eau

# Decoupage VoxelWorld.gd (2026-07-05, revue de code item C1) : generation
# lacs/riviere/cascades (_place_lakes/_place_river) deplacee dans
# VoxelHydrology.gd - relocalisation pure, voir ce fichier pour le detail.
# _compute_water_columns() reste ici comme facade fine : generate_flat_terrain()
# (qui l'appelle) n'a donc pas eu besoin de changer.
const VoxelHydrologyScript := preload("res://scripts/monde/voxel/VoxelHydrology.gd")
var hydrology: VoxelHydrologyScript = VoxelHydrologyScript.new()


func _compute_water_columns() -> Dictionary:
	return hydrology.compute_water_columns(water_noise, Callable(self, "_hill_height_at"))


func get_block(pos: Vector3i) -> int:
	return grid.get(pos, BlockType.EMPTY)


# Decoupage VoxelWorld.gd (2026-07-05, revue de code item C1) : construction
# du mesh (rebuild_mesh, choix des buckets/couleurs, ajout des quads)
# deplacee dans VoxelMeshBuilder.gd - relocalisation quasi pure, voir ce
# fichier pour le detail (2 vraies adaptations documentees a leur endroit :
# _is_face_exposed n'appelle plus get_block(), get_top_block_y passe par un
# Callable). rebuild_mesh() reste ici comme facade fine : l'API publique de
# VoxelWorld.gd ne change pas (set_view_level/build_block/remove_block/... y
# font toujours simplement rebuild_mesh()).
const VoxelMeshBuilderScript := preload("res://scripts/monde/voxel/VoxelMeshBuilder.gd")
var mesh_builder: VoxelMeshBuilderScript = VoxelMeshBuilderScript.new()


func rebuild_mesh() -> void:
	mesh_builder.rebuild(grid, discovered, vein_system, view_level, WIDTH, DEPTH,
			is_frozen, snow_coverage, climate_id, season_id, terrain_noise, stone_noise,
			DIRECTIONS, mesh_instance, Callable(self, "get_top_block_y"))
