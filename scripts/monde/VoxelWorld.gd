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

# Sprint 23 : seuil de bruit (0..1, plus c'est haut plus c'est rare) au-dela
# duquel un bloc de pierre devient un filon, par palier de rarete. Valeurs de
# depart raisonnables, a ajuster apres avoir vu le resultat en jeu.
const RARITY_THRESHOLDS := {
	"commun": 0.45,
	"rare": 0.65,
	"tres_rare": 0.80,
}

# Marge au-dessus du terrain pour pouvoir construire des murs en hauteur (Sprint 7)
const BUILD_CEILING := HEIGHT + 10

enum BlockType { EMPTY, DIRT, STONE, WOOD_WALL, STONE_WALL, WATER }

# Sprint 36 : couleur unie de l'eau (bucket 12, voir rebuild_mesh/_bucket_for)
# Sprint 37duodecies (2026-07-04, signale par Francois : "l'eau est trop
# foncee") : eclaircie/plus vive (etait 0.20/0.45/0.80).
# Sprint 37quaterdecies (2026-07-04, meme plainte persistante) : nouveau
# passage d'eclaircissement plus marque, combine a la remontee de
# LIGHT_ENERGY/AMBIENT_ENERGY dans DayNightCycle.gd (voir la pour la cause).
# Sprint 37septdecies (2026-07-04, meme plainte persistante : "l'eau devrait
# etre beaucoup plus claire") : nouveau passage d'eclaircissement, plus
# franc. Si l'eau apparait encore sombre/grise apres ce changement, ce n'est
# probablement plus cette constante qui est en cause (verifier is_frozen/
# ICE_COLOR, ou si la zone en question est bien du bucket 12 et pas un trou
# non decouvert - voir _bucket_for/discovered).
const WATER_COLOR := Color(0.45, 0.80, 0.98)

# Sprint 36 : nombre de lacs generes + rayon (en blocs, avant variation de
# bruit qui rend le contour moins parfaitement circulaire) + demi-largeur de
# la riviere (en blocs de part et d'autre du centre du lit).
const LAKE_COUNT := 2
const LAKE_RADIUS_MIN := 5.0
const LAKE_RADIUS_MAX := 9.0
const RIVER_HALF_WIDTH := 3  # Sprint 43 : elargi (etait 2) pour une courbe de cascade plus douce/large

# Sprint 36bis (2026-07-03, demande explicite) : profondeur des lacs/riviere -
# nombre de niveaux (depuis la surface HEIGHT-1 vers le bas) remplaces par de
# l'eau au lieu de terre/pierre. Un lac tire UNE profondeur au hasard dans cet
# intervalle (uniforme sur tout le lac, pas case par case, pour eviter un fond
# irregulier en damier) ; la riviere reste a profondeur fixe RIVER_DEPTH.
# Sprint 37septies (2026-07-04) : la version "colonne entiere jusqu'au fond"
# (Sprint 37quater) est REVENUE en arriere - Francois a signale que l'eau
# s'etendait "au dela du niveau -1" en descendant, ce qui n'etait pas voulu.
# Profondeur a nouveau PLAFONNEE (voir generate_flat_terrain), mais LAKE_DEPTH_MIN
# et RIVER_DEPTH remontes a 2 (etaient 1) pour garantir qu'on voit toujours de
# l'eau au niveau -1 (le bug d'origine signale par Francois), sans jamais
# descendre plus bas que ca.
const LAKE_DEPTH_MIN := 2
const LAKE_DEPTH_MAX := 3
const RIVER_DEPTH := 2

# Sprint 37 (2026-07-04, backlog Phase 1 items 1-2) : etat climat global (pas
# par case, voir TemperatureSystem.gd) - couleur de l'eau gelee (glace) et
# voile de neige applique par-dessus la couleur normale de l'herbe/la pierre.
const ICE_COLOR := Color(0.78, 0.88, 0.94)
const SNOW_COLOR := Color(0.95, 0.96, 0.98)
var is_frozen: bool = false
var snow_coverage: float = 0.0  # 0..1, pilote par TemperatureSystem.gd

# Grille du monde : cle = Vector3i (position bloc), valeur = BlockType
var grid: Dictionary = {}

# Sprint 23 : filons. Cle = Vector3i (position bloc, toujours un bloc
# BlockType.STONE), valeur = id du materiau (voir MetalTypes.gd/GemTypes.gd).
# Dictionnaire separe plutot qu'un nouveau BlockType par materiau : evite de
# faire exploser l'enum BlockType et le systeme de buckets pour chaque metal/
# pierre precieuse (voir _bucket_for/_vein_color_for : un seul bucket
# supplementaire, colore par sommet, sert pour tous les materiaux).
var vein_grid: Dictionary = {}

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

# Couleur uniforme des blocs non decouverts (voir "discovered" ci-dessus) -
# gris neutre, deliberement sans variation/bruit pour ne rien laisser deviner
# du materiau reel en dessous.
const UNDISCOVERED_COLOR := Color(0.5, 0.5, 0.5)

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

# Sprint 23ter : couleur de base unique de la pierre (remplace l'ancien
# damier clair/fonce - voir _stone_color_for/_bucket_for). Un niveau de pierre
# donne doit avoir un materiau uniforme, les filons etant la seule exception
## visible (comme demande explicitement : "un materiau uniforme par niveau,
## avec des exceptions aleatoires" pour les filons).
const STONE_BASE := Color(0.58, 0.60, 0.66)

# Sprint 23 : un bruit 3D independant par materiau de filon (metal/pierre
# precieuse), cle = id du materiau. Des seeds differentes evitent que tous
# les materiaux se superposent aux memes endroits.
var vein_noises: Dictionary = {}

# Sprint 23sexies : nombre de pepites 3D generees par bloc de filon visible
# (voir _rebuild_vein_pepites) - densite "beaucoup" choisie explicitement.
const PEPITE_COUNT_MIN := 6
const PEPITE_COUNT_MAX := 9

# Sprint 23sexies : rayon de base d'une pepite (unite = 1 bloc), multiplie par
# un facteur de rarete puis par une petite variation aleatoire par pepite.
const PEPITE_BASE_RADIUS := 0.09
const PEPITE_RARITY_SCALE := {
	"commun": 0.9,
	"rare": 1.15,
	"tres_rare": 1.4,
}

# Sprint 23sexies : les deux MultiMeshInstance3D qui portent toutes les
# pepites (un pour les metaux, un pour les pierres precieuses) - un seul
# noeud par categorie, la couleur de chaque pepite est portee par une couleur
# d'instance (meme principe que la couleur par sommet du reste du terrain).
var metal_pepites: MultiMeshInstance3D
var gem_pepites: MultiMeshInstance3D

## Sprint 49 (2026-07-04, "traits en bleu clair et blanc pour montrer l'eau qui
## tombe") : liste des colonnes de cascade calculees a la generation du terrain
## (voir generate_flat_terrain/_place_river), conservee ici (le dictionnaire
## "waterfalls" original n'etait qu'une variable locale, jetee apres usage) pour
## qu'un script decoratif externe (WaterfallStreaks.gd) puisse la lire via
## get_waterfall_columns() et placer ses traits SANS dupliquer la logique de
## generation de riviere.
var waterfall_columns: Array = []

# Sprint 55 (2026-07-04, bug signale par Francois : le mur plat en cubes
# d'origine n'a jamais ete supprime - WaterfallShapes.gd n'ajoutait sa forme
# courbe QUE par-dessus, sans jamais cacher l'ancien mur, qui recouvrait donc
# la nouvelle forme presque partout). Cle = Vector2i(x,z) d'une colonne de
# cascade, valeur = Vector3i direction (dx,0,dz) de la face a NE PAS dessiner
# dans rebuild_mesh (voir plus bas) - cette face precise est remplacee par le
# quart de cylindre/sphere de WaterfallShapes.gd.
var waterfall_face_dir: Dictionary = {}

## Sprint 34bis (2026-07-03) : mesure de duree de generation du monde, pour
## savoir combien de temps prend le chargement de la carte 100x100x50 -
## initialise ici (premier script "lourd" a demarrer, voir ordre des noeuds
## dans Main.tscn), lu par GroundDecoration.gd (dernier script "lourd" a
## finir son _ready()) pour calculer et afficher la duree totale dans la
## console Godot. "static" = partage entre tous les scripts qui preloadent
## VoxelWorld.gd (voir GroundDecoration.gd), pas besoin d'une instance.
static var world_gen_start_ms: int = 0


func _ready() -> void:
	world_gen_start_ms = Time.get_ticks_msec()
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
	_setup_vein_noises()
	generate_flat_terrain()
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	_setup_vein_pepites_nodes()
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


## Cree un bruit 3D par materiau de filon (voir vein_noises). Frequence assez
## basse pour former des petits amas coherents (des "poches" de quelques
## blocs) plutot qu'un bruit poivre-et-sel bloc par bloc.
func _setup_vein_noises() -> void:
	for entry in VeinMaterials.all():
		var n := FastNoiseLite.new()
		n.seed = randi()
		n.frequency = 0.16
		vein_noises[entry["id"]] = n


## Sprint 23sexies : cree les deux MultiMeshInstance3D qui portent les pepites
## (metaux/pierres precieuses), avec leur mesh et leur materiau. Appele une
## seule fois dans _ready() ; le contenu (nombre/position/couleur des pepites)
## est ensuite recalcule a chaque rebuild_mesh() via _rebuild_vein_pepites().
func _setup_vein_pepites_nodes() -> void:
	metal_pepites = MultiMeshInstance3D.new()
	metal_pepites.multimesh = MultiMesh.new()
	metal_pepites.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	metal_pepites.multimesh.use_colors = true
	metal_pepites.multimesh.mesh = _make_pepite_mesh(true)
	metal_pepites.material_override = _make_pepite_material(true)
	add_child(metal_pepites)

	gem_pepites = MultiMeshInstance3D.new()
	gem_pepites.multimesh = MultiMesh.new()
	gem_pepites.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	gem_pepites.multimesh.use_colors = true
	gem_pepites.multimesh.mesh = _make_pepite_mesh(false)
	gem_pepites.material_override = _make_pepite_material(false)
	add_child(gem_pepites)


## Sprint 23sexies : mesh d'une pepite - une SphereMesh integree au moteur,
## avec peu de segments pour les pierres precieuses (aspect a facettes, comme
## une pierre taillee) et beaucoup de segments pour les metaux (aspect rond/
## lisse, comme une pepite brute). Le rayon reel est applique par instance via
## l'echelle de la transform (voir _rebuild_vein_pepites), donc rayon=1 ici.
func _make_pepite_mesh(is_metal: bool) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	if is_metal:
		mesh.radial_segments = 10
		mesh.rings = 6
	else:
		mesh.radial_segments = 5
		mesh.rings = 3
	return mesh


## Sprint 23sexies : materiau des pepites - couleur par instance (comme la
## couleur par sommet du reste du terrain), mais cette fois avec un vrai
## eclairage (pas "unshaded") pour que metallic/roughness/emission aient un
## effet visible. Metaux : reflets metalliques. Pierres precieuses : surface
## lisse/brillante + leger scintillement (emission) independant de la couleur.
func _make_pepite_material(is_metal: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	if is_metal:
		mat.metallic = 0.85
		mat.roughness = 0.25
	else:
		mat.metallic = 0.0
		mat.roughness = 0.05
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.97, 0.85)
		mat.emission_energy_multiplier = 0.15
	return mat


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
	if type == BlockType.STONE and vein_grid.has(pos):
		materiau = vein_grid[pos]
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
	if vein_grid.has(pos):
		vein_id = vein_grid[pos]
		vein_grid.erase(pos)
	# Sprint 35 : miner ce bloc expose ses voisins encore pleins - ils
	# deviennent "decouverts" (voir "discovered"), meme s'ils n'ont jamais ete
	# vus au niveau de coupe courant. C'est cette mise a jour incrementale
	# (seulement 6 voisins, jamais toute la carte) qui remplace le recalcul
	# complet a chaque minage.
	var newly_discovered: int = 0
	for dir in DIRECTIONS:
		var neighbor_pos: Vector3i = pos + dir
		if grid.has(neighbor_pos) and not discovered.has(neighbor_pos):
			newly_discovered += 1
		if grid.has(neighbor_pos):
			discovered[neighbor_pos] = true
	# Sprint 35 : instrumentation temporaire (diagnostic "le trou n'apparait
	# pas") - confirme que le bloc est bien retire de la grille et que ses
	# voisins passent bien en "decouvert".
	print("[Perf][Voxel] remove_block a %s (type %d), view_level=%d, %d voisin(s) nouvellement decouvert(s)" % [pos, type, view_level, newly_discovered])
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
				# Sprint 38 : colonne de cascade - remplace TOUT le segment
				# vertical entre le palier bas et le palier haut par de l'eau,
				# par-dessus le remplissage normal ci-dessus (voir _place_river).
				if not waterfall.is_empty() and y >= int(waterfall["bottom"]) and y <= int(waterfall["top"]):
					type = BlockType.WATER
				if type == BlockType.EMPTY:
					continue
				var pos := Vector3i(x, y, z)
				grid[pos] = type
				if type == BlockType.STONE:
					_maybe_place_vein(pos, veins)
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
				if y == surface_y or is_edge_column or type == BlockType.WATER or is_water_floor or is_waterfall_face:
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
	# Sprint 55 : construit le lookup "face a ne pas dessiner" (voir declaration
	# de "waterfall_face_dir" plus haut + son usage dans rebuild_mesh).
	waterfall_face_dir.clear()
	for pos2d in waterfalls:
		var wf: Dictionary = waterfalls[pos2d]
		var dx: int = int(wf.get("dx", 0))
		var dz: int = int(wf.get("dz", 0))
		if dx != 0 or dz != 0:
			waterfall_face_dir[pos2d] = Vector3i(dx, 0, dz)


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
## en plus du remplissage normal, voir generate_flat_terrain).
func _compute_water_columns() -> Dictionary:
	var cols: Dictionary = {}
	var hill_overrides: Dictionary = {}
	var waterfalls: Dictionary = {}
	_place_lakes(cols, hill_overrides)
	_place_river(cols, hill_overrides, waterfalls)
	return {"cols": cols, "hill_overrides": hill_overrides, "waterfalls": waterfalls}


## Sprint 36 : place LAKE_COUNT lacs a des centres aleatoires (marge de 12
## blocs par rapport aux bords, pour eviter un lac coupe net par le bord de la
## carte), contour legerement irregulier via water_noise (sinon un cercle
## parfait, trop artificiel). Sprint 36bis : chaque lac tire une profondeur
## (LAKE_DEPTH_MIN..LAKE_DEPTH_MAX) une seule fois, appliquee a toutes ses
## cases - voir generate_flat_terrain pour comment la profondeur devient des
## niveaux d'eau reels. Sprint 38 : le relief est aplati (hill_overrides=0) sur
## tout le rectangle englobant du lac (pas seulement le cercle d'eau) - un lac
## a une surface plate par nature, meme entoure de collines ; simplification
## assumee pour cette premiere version du relief (pas de vraie berge en pente).
func _place_lakes(cols: Dictionary, hill_overrides: Dictionary) -> void:
	for i in range(LAKE_COUNT):
		var cx := randi_range(12, WIDTH - 12)
		var cz := randi_range(12, DEPTH - 12)
		var radius := randf_range(LAKE_RADIUS_MIN, LAKE_RADIUS_MAX)
		var depth := randi_range(LAKE_DEPTH_MIN, LAKE_DEPTH_MAX)
		var margin := int(radius) + 3
		var min_x := maxi(0, cx - margin)
		var max_x := mini(WIDTH - 1, cx + margin)
		var min_z := maxi(0, cz - margin)
		var max_z := mini(DEPTH - 1, cz + margin)
		for x in range(min_x, max_x + 1):
			for z in range(min_z, max_z + 1):
				hill_overrides[Vector2i(x, z)] = 0
				var d: float = Vector2(x - cx, z - cz).length()
				var n: float = water_noise.get_noise_2d(float(x), float(z))  # -1..1
				if d + n * 3.0 < radius:
					var pos := Vector2i(x, z)
					# Si un lac precedent ou la riviere couvre deja cette case,
					# on garde la profondeur la plus grande (pas d'ecrasement).
					cols[pos] = maxi(int(cols.get(pos, 0)), depth)


## Sprint 36 : une riviere qui traverse la carte d'un bord a l'autre, au hasard
## en X (ouest-est) ou en Z (nord-sud), avec une legere ondulation (sinus)
## plutot qu'une ligne parfaitement droite. RIVER_HALF_WIDTH blocs de part et
## d'autre du centre du lit a chaque "tranche" traversee. Sprint 36bis :
## profondeur fixe RIVER_DEPTH (demande explicite, moins profonde qu'un lac).
##
## Sprint 75 (2026-07-04, reecriture complete demandee par Francois) : bug
## identifie ou l'eau du trace pouvait se retrouver plus haute que le relief
## naturel environnant, faute de verifier ce relief le long du trajet.
##
## Sprint 78 (2026-07-04, demande explicite de Francois : "cascade alignee et
## pas avec des blocs qui avancent comme maintenant") : le Sprint 77 (relief
## independant par bande de largeur) provoquait des cascades en escalier
## decalees d'une bande a l'autre (visible sur capture d'ecran - plusieurs
## quarts de cylindre a des rangees differentes). Retour a UNE seule rupture
## de niveau par rangee, valable pour TOUTE la largeur du lit a la fois - donc
## une cascade toujours alignee, jamais en escalier.
## Algorithme (3 etapes demandees par Francois) :
## 1. tracer le centre du lit, rangee par rangee, sans cascade.
## 2. reperer les ruptures de niveau le long du trajet (relief le plus bas
##    sur la largeur totale + berges, palier en escalier depuis la source).
## 3. pour chaque rangee du haut (juste avant une rupture), tracer UNE
##    colonne de cascade valable pour toute la largeur du lit ce jour-la.
##
## Meme sprint (suite, 2026-07-04, bug signale par Francois via capture
## d'ecran : un bloc d'eau sans berge a cote de la cascade) : regle physique
## rappelee par Francois - un bloc d'eau ne peut JAMAIS se retrouver sans
## berge (mur) de chaque cote. Le sondage du relief ne portait QUE sur la
## largeur exacte de la riviere, jamais au-dela - rien ne garantissait donc
## que le terrain juste a l'exterieur de cette largeur (la future berge)
## soit bien plus haut que le niveau d'eau choisi. Fix : le sondage du
## relief (pour decider le palier de chaque rangee) regarde maintenant
## aussi 1 case de plus de chaque cote de la largeur du lit (BANK_MARGIN=1)
## - le niveau d'eau choisi ne peut donc plus jamais depasser le terrain de
## la berge elle-meme. Seul le sondage est elargi ; la largeur d'eau posee
## reste exactement RIVER_HALF_WIDTH comme avant.
func _place_river(cols: Dictionary, hill_overrides: Dictionary, waterfalls: Dictionary) -> void:
	var horizontal: bool = randf() < 0.5
	var length: int = WIDTH if horizontal else DEPTH
	var cross_size: int = DEPTH if horizontal else WIDTH
	var start: float = randf_range(cross_size * 0.25, cross_size * 0.75)
	var end: float = randf_range(cross_size * 0.25, cross_size * 0.75)
	const BANK_MARGIN: int = 1

	# Etape 1 : centre du lit, rangee par rangee (meme sinusoide qu'avant,
	# purement visuelle) - et relief naturel le plus bas sur la largeur du
	# lit PLUS BANK_MARGIN cases de chaque cote (la future berge), pour
	# garantir qu'un palier commun ne depasse jamais le terrain de la berge.
	var centers: Array = []
	var natural_ground: Array = []
	for i in range(length):
		var t: float = float(i) / float(length - 1)
		var center: float = lerp(start, end, t) + sin(t * PI * 3.0) * (cross_size * 0.08)
		centers.append(center)
		var lowest_here: int = 999
		for offset in range(-RIVER_HALF_WIDTH - BANK_MARGIN, RIVER_HALF_WIDTH + BANK_MARGIN + 1):
			var cross: int = int(round(center)) + offset
			if cross < 0 or cross >= cross_size:
				continue
			var hx: int = i if horizontal else cross
			var hz: int = cross if horizontal else i
			# Sprint 76 : priorite a hill_overrides (deja pose par
			# _place_lakes) sur le relief brut, sinon une zone de lac deja
			# aplatie fausserait le relief "naturel" sonde ici.
			var ground_here: int = int(hill_overrides.get(Vector2i(hx, hz), _hill_height_at(hx, hz)))
			lowest_here = mini(lowest_here, ground_here)
		natural_ground.append(lowest_here)

	# Point le plus haut du trajet = la source commune (1ere trouvee si egalite).
	var source_i: int = 0
	for i in range(length):
		if natural_ground[i] > natural_ground[source_i]:
			source_i = i

	# Etape 2 : niveau impose a chaque rangee - descend en escalier depuis la
	# source vers chaque bout (min glissant), jamais au-dessus du relief le
	# plus bas de la largeur - donc valable pour toute la largeur du lit.
	var shelf: Array = []
	shelf.resize(length)
	shelf[source_i] = natural_ground[source_i]
	var level: int = shelf[source_i]
	for i in range(source_i - 1, -1, -1):
		level = mini(level, natural_ground[i])
		shelf[i] = level
	level = shelf[source_i]
	for i in range(source_i + 1, length):
		level = mini(level, natural_ground[i])
		shelf[i] = level

	# Etape 3 : pour chaque rangee du haut (juste avant une rupture par
	# rapport a la rangee plus proche de la source), une colonne de cascade
	# unique, alignee sur toute la largeur du lit ce jour-la.
	for i in range(length):
		var center: float = centers[i]
		var downstream_dx: int = 0
		var downstream_dz: int = 0
		if i > source_i:
			if horizontal: downstream_dx = 1
			else: downstream_dz = 1
		elif i < source_i:
			if horizontal: downstream_dx = -1
			else: downstream_dz = -1

		var is_falls_row: bool = false
		var upper_shelf: int = shelf[i]
		if i > source_i and shelf[i] < shelf[i - 1]:
			is_falls_row = true
			upper_shelf = shelf[i - 1]
		elif i < source_i and shelf[i] < shelf[i + 1]:
			is_falls_row = true
			upper_shelf = shelf[i + 1]

		var upper_surface_y: int = HEIGHT - 1 + upper_shelf
		var lower_surface_y: int = HEIGHT - 1 + shelf[i]

		for offset in range(-RIVER_HALF_WIDTH, RIVER_HALF_WIDTH + 1):
			var cross: int = int(round(center)) + offset
			if cross < 0 or cross >= cross_size:
				continue
			var pos: Vector2i = Vector2i(i, cross) if horizontal else Vector2i(cross, i)
			cols[pos] = maxi(int(cols.get(pos, 0)), RIVER_DEPTH)
			hill_overrides[pos] = shelf[i]
			if is_falls_row:
				waterfalls[pos] = {
					"top": upper_surface_y,
					"bottom": lower_surface_y - RIVER_DEPTH + 1,
					"dx": downstream_dx,
					"dz": downstream_dz,
					"pool_surface_y": lower_surface_y,
				}


## Tire au sort si la case de pierre "pos" devient un filon. Parcourt les
## materiaux du plus rare au plus commun et s'arrete au premier qui "matche"
## (evite qu'un materiau commun ne prenne la place d'un materiau rare sur le
## meme bloc, chacun ayant son propre bruit independant).
func _maybe_place_vein(pos: Vector3i, veins: Array) -> void:
	for entry in veins:
		var id: String = entry["id"]
		var threshold: float = RARITY_THRESHOLDS.get(entry["rarete"], 0.7)
		var noise: FastNoiseLite = vein_noises[id]
		var n: float = noise.get_noise_3d(float(pos.x), float(pos.y), float(pos.z))  # -1..1
		if n > threshold:
			vein_grid[pos] = id
			return


## Renvoie le type de bloc a une position, EMPTY si hors de la carte
func get_block(pos: Vector3i) -> int:
	return grid.get(pos, BlockType.EMPTY)


## Sprint 23bis : une face est exposee (donc dessinee) si la case voisine est
## soit reellement vide (comportement d'origine), soit au-dessus du niveau de
## coupe visible (view_level) - dans ce cas elle n'est pas dessinee non plus,
## donc pour ce qu'on affiche, elle "n'existe pas" et la face doit apparaitre.
## C'est ce qui revele le dessus colore de chaque bloc au niveau courant.
func _is_face_exposed(neighbor_pos: Vector3i) -> bool:
	if neighbor_pos.y > view_level:
		return true
	return get_block(neighbor_pos) == BlockType.EMPTY


## Sprint 21 : couleur de l'herbe (dessus terre) a une position donnee,
## couleur de base du climat/saison actuels modulee par un bruit continu
## (+/- environ 12% de luminosite), pour une variation douce case par case
## au lieu du damier clair/fonce utilise auparavant.
func _grass_color_for(pos: Vector3i) -> Color:
	var base: Color = ClimateDefs.get_terrain_color(climate_id, season_id)
	var n: float = terrain_noise.get_noise_2d(float(pos.x), float(pos.z))  # -1..1
	var factor: float = 1.0 + n * 0.12
	var color := Color(
		clamp(base.r * factor, 0.0, 1.0),
		clamp(base.g * factor, 0.0, 1.0),
		clamp(base.b * factor, 0.0, 1.0),
		base.a
	)
	# Sprint 37 (backlog Phase 1 item 3) : voile de neige, uniquement sur la
	# vraie surface exterieure - pas sur un dessus de terre mis a jour au fond
	# d'un trou mine, ou il n'y a pas de ciel pour neiger. Sprint 38 (relief) :
	# compare au sommet REEL de CETTE colonne (get_top_block_y), plus HEIGHT-1
	# fixe - sinon les sommets de colline (plus hauts que HEIGHT-1) ne
	# recevaient jamais de neige.
	if snow_coverage > 0.0 and pos.y == get_top_block_y(pos.x, pos.z):
		color = color.lerp(SNOW_COLOR, snow_coverage)
	return color


## Sprint 23ter : couleur de la pierre (dessus) a une position donnee - couleur
## de base unique (STONE_BASE) moduleee par un bruit continu (+/- ~12% de
## luminosite), remplace l'ancien damier clair/fonce a deux tons. Meme
## technique que _grass_color_for, sur le meme principe : un materiau uniforme
## par niveau, les filons restant la seule vraie exception de couleur.
func _stone_color_for(pos: Vector3i) -> Color:
	var n: float = stone_noise.get_noise_2d(float(pos.x), float(pos.z))  # -1..1
	var factor: float = 1.0 + n * 0.12
	var color := Color(
		clamp(STONE_BASE.r * factor, 0.0, 1.0),
		clamp(STONE_BASE.g * factor, 0.0, 1.0),
		clamp(STONE_BASE.b * factor, 0.0, 1.0),
		STONE_BASE.a
	)
	# Sprint 37 : meme voile de neige que _grass_color_for, meme restriction a
	# la vraie surface exterieure.
	if snow_coverage > 0.0 and pos.y == get_top_block_y(pos.x, pos.z):
		color = color.lerp(SNOW_COLOR, snow_coverage)
	return color


## Sprint 23 : couleur d'un bloc de filon (metal/pierre precieuse) a une
## position donnee, recuperee depuis MetalTypes/GemTypes via VeinMaterials.
## Couleur neutre de secours si jamais la position n'est plus dans vein_grid
## (ne devrait pas arriver, garde par securite).
func _vein_color_for(pos: Vector3i) -> Color:
	if not vein_grid.has(pos):
		return Color(0.5, 0.5, 0.5)
	var material: Dictionary = VeinMaterials.get_type(vein_grid[pos])
	return material.get("couleur", Color(0.5, 0.5, 0.5))


## Construit un seul mesh avec une surface par materiau, en n'ajoutant une
## face que si le bloc voisin dans cette direction est vide (culling des
## faces cachees). Sprint 10 : les faces verticales/du dessous (parois d'un
## trou mine ou d'un mur) sont assombries par rapport aux faces du dessus,
## pour bien distinguer un creux (paroi sombre visible) d'une simple
## variation de couleur de surface. Sprint 21 : le dessus terre (bucket 0,
## l'herbe) n'est plus un damier clair/fonce mais une couleur par climat/
## saison + variation de bruit par case, appliquee via des couleurs de
## sommet (voir _grass_color_for et _add_face). Le bucket 1 (ancien "terre
## fonce" du damier) n'est plus utilise pour l'instant mais reste reserve
## (evite de renumeroter tous les autres buckets). Sprint 23 : bucket 10
## ajoute pour les filons (metal/pierre precieuse), colore par sommet comme
## l'herbe, mais applique a toutes les faces du bloc (dessus ET parois) pour
## que le filon reste visible/reperable une fois une paroi exposee. Sprint
## 23bis : les blocs strictement au-dessus de view_level ne sont pas dessines
## du tout, et leur "absence" compte comme une face exposee pour le bloc
## juste en dessous (voir _is_face_exposed) - c'est ce qui revele une coupe
## horizontale complete et coloree du niveau courant (comme un Dwarf Fortress),
## au lieu de se contenter de deplacer la camera a l'interieur de la roche pleine.
## Sprint 23ter : le dessus pierre (bucket 2) suit maintenant le meme principe
## que l'herbe (bucket 0) - couleur uniforme (STONE_BASE) + bruit, au lieu de
## l'ancien damier clair/fonce a deux tons (bucket 3 devient inutilise, meme
## traitement que le bucket 1 pour l'herbe).
func rebuild_mesh() -> void:
	# 13 buckets : 0-3 = dessus terre/pierre (0=herbe couleur variable, 1=inutilise,
	# 2=pierre couleur variable, 3=inutilise), 4-5 = dessus mur bois/pierre,
	# 6-9 = parois assombries (terre, pierre, mur bois, mur pierre),
	# 10 = filon (metal/pierre precieuse, toutes faces, couleur variable),
	# 11 = bloc non decouvert (gris uniforme, voir "discovered"),
	# 12 = eau (Sprint 36, couleur unie WATER_COLOR, toutes faces).
	var surface_tools: Array = []
	for i in range(13):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface_tools.append(st)

	# Sprint 35 (2026-07-03) : la version precedente (map resize 100x100x50)
	# bouclait deja sur "seulement" les colonnes visibles (y de 0 a view_level),
	# mais ca representait encore jusqu'a 500 000 cases a view_level eleve -
	# recalculees en entier a CHAQUE minage/construction/changement de niveau,
	# ce qui restait tres lent (plusieurs secondes) sur la carte agrandie.
	# Remplace maintenant par une passe "detaillee" bornee a l'ensemble
	# "discovered" (voir plus haut) - petit au depart (juste la surface + les
	# bords de carte), grandit lentement au fil du minage, jamais toute la
	# grille. Le rendu (couleur/filon/exposition de face) est identique a
	# avant pour tout ce qui est decouvert - seule la SOURCE de l'iteration
	# change (un ensemble cible au lieu d'une triple boucle x/z/y).
	var _detailed_faces: int = 0
	for pos in discovered.keys():
		if pos.y > view_level:
			continue
		var type: int = grid.get(pos, BlockType.EMPTY)
		if type == BlockType.EMPTY:
			continue
		for dir in DIRECTIONS:
			# Sprint 55 (2026-07-04) : sur une colonne de cascade, ne dessine
			# PAS la face plate qui fait face au courant - remplacee par le
			# quart de cylindre de WaterfallShapes.gd.
			# Sprint 59 (2026-07-04, correction demandee par Francois : "pour
			# avoir un quart de cylindre il faut supprimer la surface ET les
			# parois, pas juste une face") : supprimer UNE SEULE face
			# laissait le dessus (surface d'eau plate) et les 2 parois
			# laterales (largeur du lit) intacts - la forme courbe se
			# retrouvait "en plus" de ce cube, pas "a la place". On supprime
			# maintenant TOUTES les faces du bloc de cascade sauf le dessous
			# (jamais visible de toute facon, c'est le fond du bassin) :
			# dessus, face aval (deja supprimee) ET les 2 parois laterales.
			if type == BlockType.WATER:
				var pos2d := Vector2i(pos.x, pos.z)
				if waterfall_face_dir.has(pos2d) and dir != Vector3i(0, -1, 0):
					continue
			if _is_face_exposed(pos + dir):
				var idx := _bucket_for(pos, type, dir)
				var face_color := Color.WHITE
				if idx == 0:
					face_color = _grass_color_for(pos)
				elif idx == 2:
					face_color = _stone_color_for(pos)
				elif idx == 10:
					face_color = _vein_color_for(pos)
				_add_face(surface_tools[idx], pos, dir, face_color)
				_detailed_faces += 1

	# Sprint 35 : passe "non decouvert" - une seule face (le dessus) par
	# colonne, grise, pour representer ce qui n'a jamais ete explore au
	# niveau de coupe courant (remplace l'ancien rendu detaille/colore pour
	# tout ce qui n'est pas dans "discovered"). Ne coute qu'une iteration sur
	# les colonnes (WIDTH*DEPTH = 10 000), jamais sur la profondeur - c'est ce
	# qui rend le changement de niveau rapide meme a view_level eleve.
	var _grey_faces: int = 0
	for x in range(WIDTH):
		for z in range(DEPTH):
			var pos := Vector3i(x, view_level, z)
			if discovered.has(pos):
				continue  # deja traite avec sa vraie couleur dans la passe ci-dessus
			var type: int = grid.get(pos, BlockType.EMPTY)
			if type == BlockType.EMPTY:
				continue
			_add_face(surface_tools[11], pos, Vector3i(0, 1, 0), UNDISCOVERED_COLOR)
			_grey_faces += 1

	# Sprint 35 : instrumentation temporaire (diagnostic "le trou n'apparait
	# pas") - confirme la taille de "discovered" et le nombre de faces
	# generees dans chaque passe a chaque reconstruction du mesh.
	print("[Perf][Voxel] rebuild_mesh : view_level=%d, discovered=%d, faces detaillees=%d, faces grises=%d" % [view_level, discovered.size(), _detailed_faces, _grey_faces])

	# Sprint 13 : palette plus vive/saturee (direction "BD"), sur le meme
	# principe qu'avant (damier clair/fonce + parois assombries)
	var dirt_dark := Color(0.58, 0.34, 0.10)  # garde pour bucket 6 (paroi terre)
	var stone_dark := Color(0.48, 0.50, 0.56)  # garde pour bucket 3 (inutilise) et bucket 7 (paroi)
	var wood_wall := Color(0.70, 0.46, 0.16)
	var stone_wall := Color(0.74, 0.76, 0.82)

	# Sprint 24octies : materiau associe a chaque bucket (index dans
	# surface_tools). Un SurfaceTool sans aucune face ajoutee ne produit PAS
	# de surface lors du commit() (Godot ignore silencieusement les buckets
	# vides), donc l'indice de surface reellement obtenu dans le mesh final
	# peut etre INFERIEUR a l'indice du bucket d'origine des qu'un bucket
	# precedent est vide (ex : aucun mur en bois sur la carte -> bucket 4
	# vide -> tout ce qui suit se decale). Assigner les materiaux a des
	# indices fixes 0-10 provoquait donc "Index p_idx out of bounds" des
	# qu'un type de bloc etait absent de la carte (cas frequent sur une
	# carte fraiche/petite). On mappe maintenant chaque bucket a son
	# materiau via un dictionnaire, et on n'appelle surface_set_material
	# qu'apres coup, sur le vrai indice de surface obtenu (compte a part,
	# qui n'avance que quand un commit() a effectivement ajoute une surface).
	var bucket_materials := {
		0: _make_vertex_color_material(),
		1: _make_material(dirt_dark),  # inutilise (voir plus haut)
		2: _make_vertex_color_material(),
		3: _make_material(stone_dark),  # inutilise (voir plus haut)
		4: _make_material(wood_wall),
		5: _make_material(stone_wall),
		6: _make_material(_darken(dirt_dark)),
		7: _make_material(_darken(stone_dark)),
		8: _make_material(_darken(wood_wall)),
		9: _make_material(_darken(stone_wall)),
		10: _make_vertex_color_material(),
		11: _make_material(UNDISCOVERED_COLOR),  # Sprint 35 : gris uniforme, pas besoin de couleur par sommet
		# Sprint 37 (backlog Phase 1 item 2) : l'eau devient de la glace (couleur
		# claire) quand is_frozen est vrai (etat global, voir TemperatureSystem.gd).
		12: _make_material(ICE_COLOR if is_frozen else WATER_COLOR),
	}

	var mesh := ArrayMesh.new()
	for bucket_idx in range(surface_tools.size()):
		var st: SurfaceTool = surface_tools[bucket_idx]
		var surfaces_before := mesh.get_surface_count()
		st.commit(mesh)
		if mesh.get_surface_count() > surfaces_before:
			mesh.surface_set_material(surfaces_before, bucket_materials[bucket_idx])

	mesh_instance.mesh = mesh
	_rebuild_vein_pepites()


## Determine dans quelle surface (materiau + face) placer un bloc donne.
## Sprint 21 : le dessus terre (herbe) n'utilise plus qu'un seul bucket (0,
## couleur variable par sommet), le damier clair/fonce est retire pour ce cas.
## Sprint 23ter : meme traitement pour le dessus pierre (bucket 2, couleur
## variable) - retire de l'ancien damier clair/fonce a deux tons, pour que
## chaque niveau ait un materiau de pierre uniforme (les filons restant la
## seule exception de couleur, voir plus bas).
## Sprint 23 : un bloc de pierre qui est un filon (vein_grid) passe sur le
## bucket 10 (couleur variable), sur toutes ses faces (dessus ET parois),
## avant meme de regarder le type - un filon reste un filon peu importe la face.
func _bucket_for(pos: Vector3i, type: int, dir: Vector3i) -> int:
	var is_top := dir == Vector3i(0, 1, 0)

	if type == BlockType.STONE and vein_grid.has(pos):
		return 10

	if is_top:
		match type:
			BlockType.DIRT:
				return 0
			BlockType.STONE:
				return 2
			BlockType.WOOD_WALL:
				return 4
			BlockType.STONE_WALL:
				return 5
			BlockType.WATER:
				return 12
		return 0

	match type:
		BlockType.DIRT:
			return 6
		BlockType.STONE:
			return 7
		BlockType.WOOD_WALL:
			return 8
		BlockType.STONE_WALL:
			return 9
		BlockType.WATER:
			return 12
	return 6


## Assombrit une couleur (utilise pour les parois des trous/murs, effet
## d'ombrage simple sans veritable eclairage)
func _darken(color: Color) -> Color:
	return Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, color.a)


## Cree un materiau simple, dans la couleur donnee.
## 2026-07-02 : passe de SHADING_MODE_UNSHADED a l'eclairage reel (mode par
## defaut de StandardMaterial3D) pour que le terrain reagisse enfin au cycle
## jour/nuit (DayNightCycle.gd) - un materiau "unshaded" ignore totalement
## la lumiere/les ombres, ce qui rendait la carte aussi lumineuse en pleine
## nuit qu'en plein jour et empechait toute ombre portee de s'afficher.
## roughness=1/metallic=0 evite les reflets speculaires pour garder un rendu
## plat/mat coherent avec le style low-poly du jeu, tout en recevant
## lumiere directionnelle + ombres + lumiere ambiante.
func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## Sprint 21 : materiau pour le bucket 0 (herbe), qui lit la couleur par
## sommet (definie via SurfaceTool.set_color dans _add_face) au lieu d'une
## seule couleur fixe - c'est ce qui permet la variation continue par case.
## 2026-07-02 : meme passage a l'eclairage reel que _make_material ci-dessus.
func _make_vertex_color_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## Ajoute un quad (2 triangles) sur la face "dir" du bloc a la position "pos".
## face_color : couleur de sommet (Sprint 21, utilisee uniquement par le
## bucket "herbe"/"pierre"/"filon" dont le materiau lit vertex_color_use_as_albedo ;
## ignoree par les autres materiaux, donc sans effet pour eux).
func _add_face(st: SurfaceTool, pos: Vector3i, dir: Vector3i, face_color: Color = Color.WHITE) -> void:
	var p := Vector3(pos.x, pos.y, pos.z)
	var verts: Array

	if dir == Vector3i(1, 0, 0):
		verts = [p + Vector3(1, 0, 0), p + Vector3(1, 1, 0), p + Vector3(1, 1, 1), p + Vector3(1, 0, 1)]
	elif dir == Vector3i(-1, 0, 0):
		verts = [p + Vector3(0, 0, 1), p + Vector3(0, 1, 1), p + Vector3(0, 1, 0), p + Vector3(0, 0, 0)]
	elif dir == Vector3i(0, 1, 0):
		verts = [p + Vector3(0, 1, 0), p + Vector3(0, 1, 1), p + Vector3(1, 1, 1), p + Vector3(1, 1, 0)]
	elif dir == Vector3i(0, -1, 0):
		verts = [p + Vector3(1, 0, 0), p + Vector3(1, 0, 1), p + Vector3(0, 0, 1), p + Vector3(0, 0, 0)]
	elif dir == Vector3i(0, 0, 1):
		verts = [p + Vector3(1, 0, 1), p + Vector3(1, 1, 1), p + Vector3(0, 1, 1), p + Vector3(0, 0, 1)]
	else: # Vector3i(0, 0, -1)
		verts = [p + Vector3(0, 0, 0), p + Vector3(0, 1, 0), p + Vector3(1, 1, 0), p + Vector3(1, 0, 0)]

	var normal := Vector3(dir.x, dir.y, dir.z)

	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[0])
	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[1])
	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[2])

	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[0])
	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[2])
	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[3])


## Sprint 23sexies : recalcule entierement les pepites (metaux/pierres
## precieuses) a partir de vein_grid - appele a la fin de rebuild_mesh(), donc
## a chaque fois que le terrain change (miner/construire/changer de niveau).
## Ne place des pepites que sur les blocs de filon qui ont au moins une face
## exposee (meme logique que le reste du terrain, voir _is_face_exposed) - un
## filon entierement enterre/hors vue n'a pas de pepites.
func _rebuild_vein_pepites() -> void:
	var metal_transforms: Array = []
	var metal_colors: Array = []
	var gem_transforms: Array = []
	var gem_colors: Array = []

	for pos in vein_grid.keys():
		if pos.y > view_level:
			continue
		# Sprint 35 : un filon jamais decouvert ne doit pas laisser deviner sa
		# presence via ses pepites (meme principe que le gris uniforme du
		# rendu de bloc, voir "discovered"/rebuild_mesh).
		if not discovered.has(pos):
			continue
		var exposed_dir: Vector3i = Vector3i.ZERO
		var found_exposed := false
		for dir in DIRECTIONS:
			if _is_face_exposed(pos + dir):
				exposed_dir = dir
				found_exposed = true
				break
		if not found_exposed:
			continue

		var material_id: String = vein_grid[pos]
		var material: Dictionary = VeinMaterials.get_type(material_id)
		var couleur: Color = material.get("couleur", Color(0.5, 0.5, 0.5))
		var rarete: String = material.get("rarete", "commun")
		var rarity_scale: float = PEPITE_RARITY_SCALE.get(rarete, 1.0)
		var is_metal: bool = VeinMaterials.is_metal(material_id)

		var block_seed: int = _seed_for_pos(pos)
		var count_rng := RandomNumberGenerator.new()
		count_rng.seed = block_seed
		var count: int = count_rng.randi_range(PEPITE_COUNT_MIN, PEPITE_COUNT_MAX)

		for i in range(count):
			var rng := RandomNumberGenerator.new()
			rng.seed = block_seed + i * 97
			var offset := _biased_local_offset(rng, exposed_dir)
			var world_pos := Vector3(pos.x, pos.y, pos.z) + offset
			var radius: float = PEPITE_BASE_RADIUS * rarity_scale * rng.randf_range(0.85, 1.15)
			var pepite_basis := Basis.from_euler(Vector3(
				rng.randf_range(0, TAU), rng.randf_range(0, TAU), rng.randf_range(0, TAU)
			)).scaled(Vector3.ONE * radius)
			var xform := Transform3D(pepite_basis, world_pos)

			if is_metal:
				metal_transforms.append(xform)
				metal_colors.append(couleur)
			else:
				gem_transforms.append(xform)
				gem_colors.append(couleur)

	_apply_pepite_instances(metal_pepites, metal_transforms, metal_colors)
	_apply_pepite_instances(gem_pepites, gem_transforms, gem_colors)


## Sprint 23sexies : applique une liste de transforms/couleurs a un
## MultiMeshInstance3D (redimensionne d'abord instance_count, puis remplit)
func _apply_pepite_instances(mmi: MultiMeshInstance3D, transforms: Array, colors: Array) -> void:
	mmi.multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		mmi.multimesh.set_instance_transform(i, transforms[i])
		mmi.multimesh.set_instance_color(i, colors[i])


## Sprint 23sexies : seed deterministe a partir d'une position de bloc - les
## pepites d'un bloc donne restent toujours les memes d'un rebuild a l'autre
## (miner/construire ailleurs ne doit pas faire "sauter" les pepites existantes)
func _seed_for_pos(pos: Vector3i) -> int:
	return pos.x * 73856093 ^ pos.y * 19349663 ^ pos.z * 83492791


## Sprint 23sexies : position locale (0..1 dans le bloc) d'une pepite, tiree au
## sort mais poussee vers la face exposee "dir" pour que la pepite affleure/
## depasse legerement de cette face au lieu d'etre cachee a l'interieur du bloc.
func _biased_local_offset(rng: RandomNumberGenerator, dir: Vector3i) -> Vector3:
	var v := Vector3(rng.randf_range(0.25, 0.75), rng.randf_range(0.25, 0.75), rng.randf_range(0.25, 0.75))
	if dir.x != 0:
		v.x = 0.5 + sign(dir.x) * rng.randf_range(0.38, 0.55)
	if dir.y != 0:
		v.y = 0.5 + sign(dir.y) * rng.randf_range(0.38, 0.55)
	if dir.z != 0:
		v.z = 0.5 + sign(dir.z) * rng.randf_range(0.38, 0.55)
	return v
