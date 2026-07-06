extends Node3D
## Sprint 8 : place quelques buissons a baies au hasard sur la carte,
## pour que le nain puisse se nourrir quand il a faim.
##
## Sprint 24quater : 4 types de baies (BerryTypes.gd : groseille, myrtille,
## fraise, framboise) au lieu d'un seul type generique. Les buissons sont
## maintenant recoltes en inventaire via l'action "Cueillir" au lieu d'etre
## manges directement (voir Dwarf.gd/_complete_task pour la recolte,
## generique avec les arbres fruitiers - memes metadonnees fruit_resource/
## fruits_left et meme convention de nommage Fruit_%d, voir Forest.gd). Le
## buisson reste en place une fois vide (pas de disparition), comme un arbre
## fruitier entierement cueilli.
##
## Sprint 24sexies : deux visuels distincts selon BerryTypes.categorie -
## "buisson" (myrtille/groseille/cassis) garde la forme boule + baies autour ;
## "plante" (fraise/framboise) est une touffe de feuilles basse au ras du sol,
## avec les baies nichees dedans. Signale par l'utilisateur : les buissons et
## les plantes basses ne devraient pas avoir le meme sprite.
##
## Sprint 34 (2026-07-03, perf map resize) : meme technique que Forest.gd
## (voir ses commentaires pour le detail) - le corps du buisson/les feuilles
## de la plante deviennent des instances de MultiMeshInstance3D partages
## (construction temporaire inchangee, recolte du global_transform + couleur
## + taille, voir _harvest_and_clear), le noeud "bush" restant lui (position/
## groupe/metadonnees, utilise pour la cueillette). Les baies ("Fruit_%d")
## restent des noeuds individuels comme avant - recoltees une par une, tres
## peu nombreuses (4 par buisson), pas touchees par cette refonte.

const BerryTypes := preload("res://scripts/data/materiaux/types/baies/BerryTypes.gd")
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")
## 2026-07-05 (revue de code, item F010) : uniquement pour le garde-fou de
## _ready() ci-dessous (grid_width/grid_depth dupliques ci-dessous).
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")

## Sprint 37bis (2026-07-03, correction bug "empecher les arbres et buissons
## dans l'eau") - voir la meme correction dans Forest.gd/_pick_dry_position.
@onready var voxel_world: Node3D = %VoxelWorld

@export var grid_width: int = 100  # 2026-07-03 : map resize (etait 20)
@export var grid_depth: int = 100  # 2026-07-03 : map resize (etait 20)
@export var ground_level: float = 50.0  # sommet de la carte (HEIGHT, 2026-07-03 : map resize, etait 30)
@export var size_multiplier: float = 0.9  # 2026-07-02 : buissons/plantes reduits de 10% (jauges nains/arbres/buissons rejustees)
const BERRIES_PER_BUSH := 4  # categorie "plante" (fraise/framboise)

# 2026-07-05 (signale par Francois : "plus de baies par buisson", categorie
# "buisson" - myrtille/groseille/cassis) : nombre distinct de BERRIES_PER_BUSH
# pour ne pas affecter les plantes (fraise/framboise), qui restent a 4.
const BUISSON_BERRIES_COUNT := 10

# 2026-07-05 (signale par Francois : la sphere du corps du buisson "flotte" -
# tangente au sol en un seul point, ce qui parait detache/pas pose) : sphere
# tronquee, centre remonte a la moitie du rayon pour que 3/4 de sa hauteur
# reste visible au-dessus du sol et que le 1/4 du bas soit enterre (base au
# niveau du sol, pas un simple point de contact).
const BUSH_BODY_RADIUS := 0.4
const BUSH_BODY_CENTER_Y := BUSH_BODY_RADIUS * 0.5


## Nombre maximal de baies pour une categorie donnee ("buisson"/"plante") -
## utilise partout ou BERRIES_PER_BUSH etait lu en dur avant le 2026-07-05,
## pour que "plus de baies" (buisson) n'affecte pas les plantes (fraise/
## framboise, restees a BERRIES_PER_BUSH).
func _berries_count_for(categorie: String) -> int:
	if categorie == "plante":
		return BERRIES_PER_BUSH
	return BUISSON_BERRIES_COUNT


# 2026-07-03 (map resize) : remplace l'ancien bush_count fixe (8, sur la
# carte 20x20=400 cases d'origine) par une densite (nombre par 1000 cases),
# meme principe que Forest.tree_density_per_1000_tiles - garde la meme
# densite qu'avant (8/400*1000 = 20) quelle que soit la taille de la carte.
@export var bush_density_per_1000_tiles: float = 20.0

## Un type par "piece" decorative (hors baies, qui restent individuelles).
enum PartType { BUSH_BODY, PLANT_LEAF }

## 2026-07-06 (meme correctif que Forest.gd, voir ses commentaires pour le
## detail complet) : cacher une instance de MultiMesh avec une echelle
## Vector3.ZERO PILE (Basis totalement degenere) peut corrompre le rendu de
## TOUT le MultiMesh concerne avec un materiau a eclairage reel - jamais
## reproduit ici (pas encore observe sur les buissons), mais meme code a
## risque (voir update_view_level ci-dessous) - corrige preventivement.
const HIDDEN_INSTANCE_SCALE := 0.0001

var _mmi: Dictionary = {}              # PartType -> MultiMeshInstance3D
var _pending_xforms: Dictionary = {}   # PartType -> Array[Transform3D]
var _pending_colors: Dictionary = {}   # PartType -> Array[Color] (couleur de BASE, jamais reecrite - voir apply_season_tint)

# 2026-07-05 (cycle des saisons, hiver : "disparition totale des fruits...
# plus aucune recolte possible en hiver") - mis a jour par SeasonSystem.gd
# (voir set_winter_active) : empeche _regrow_one_berry de faire regermer une
# baie (et donc de recreer un noeud Fruit_ visible/recoltable) pendant que
# SeasonSystem.gd a deja mis fruits_left a 0 pour toute la duree de l'hiver -
# sans cette garde, le throttle de repousse continuerait d'incrementer
# fruits_left independamment de cette regle.
var _winter_active: bool = false


func _ready() -> void:
	# 2026-07-05 (revue de code, item F010) : grid_width/grid_depth/ground_level
	# dupliques en dur (aucune garde-fou automatique auparavant) - avertissement
	# si desynchronise de VoxelWorld.gd, sans changer le comportement.
	if grid_width != VoxelWorldScript.WIDTH or grid_depth != VoxelWorldScript.DEPTH or not is_equal_approx(ground_level, float(VoxelWorldScript.HEIGHT)):
		push_warning("BerryBushes.grid_width/grid_depth/ground_level (%d/%d/%.1f) desynchronise de VoxelWorld (%d/%d/%d)" % [grid_width, grid_depth, ground_level, VoxelWorldScript.WIDTH, VoxelWorldScript.DEPTH, VoxelWorldScript.HEIGHT])
	# 2026-07-05 (correctif revue de code C4, meme cause que C2-C3/C5-C6/I9) :
	# randomize() retire - reinitialisait le generateur aleatoire global de
	# facon non deterministe, APRES que VoxelWorld._ready() ait deja fixe sa
	# graine (seed(active_seed)). BerryBushes.gd est declare apres VoxelWorld
	# dans Main.tscn : le generateur global est deja correctement initialise
	# ici - rend desormais la position des buissons/baies reproductible par
	# graine.
	_build_shared_meshes()
	var tile_count: float = float(grid_width * grid_depth)
	var bush_count: int = int(round(bush_density_per_1000_tiles * tile_count / 1000.0))
	for i in range(bush_count):
		_spawn_bush()
	_apply_pending_instances()


## Sprint 37 (backlog Phase 1 item 16, "repousse des buissons") : contrairement
## aux arbres, un buisson cueilli ne disparait jamais (voir note en tete de
## fichier) - la "repousse" ici consiste donc a faire regermer des baies au
## fil du temps sur les buissons partiellement ou completement vides, jusqu'a
## revenir a BERRIES_PER_BUSH. Une seule baie repousse a la fois (throttle),
## choisie au hasard parmi les buissons non pleins.
@export var berry_regrow_interval_seconds: float = 25.0
var _berry_regrow_timer: float = 0.0

func _process(delta: float) -> void:
	_berry_regrow_timer += delta * DayNightCycleScript.game_speed
	if _berry_regrow_timer < berry_regrow_interval_seconds:
		return
	_berry_regrow_timer = 0.0
	_regrow_one_berry()


## 2026-07-05 (cycle des saisons) : appele par SeasonSystem.gd a chaque
## changement de saison (is_winter = season_id == "hiver").
func set_winter_active(active: bool) -> void:
	_winter_active = active


func _regrow_one_berry() -> void:
	if _winter_active:
		return
	var candidates: Array = []
	for bush in get_children():
		if not bush.has_meta("fruits_left"):
			continue
		var categorie: String = String(bush.get_meta("categorie", "buisson"))
		if int(bush.get_meta("fruits_left")) < _berries_count_for(categorie):
			candidates.append(bush)
	if candidates.is_empty():
		return
	var bush: Node3D = candidates[randi() % candidates.size()]
	var new_index: int = int(bush.get_meta("fruits_left"))
	bush.set_meta("fruits_left", new_index + 1)
	_build_one_berry(bush, new_index)


## Reconstruit visuellement UNE baie ("Fruit_%d") disparue - meme formule de
## position/taille que _build_bush_visual/_build_plant_visual (voir plus bas),
## pour que la baie qui repousse soit indiscernable d'une baie d'origine.
func _build_one_berry(bush: Node3D, index: int) -> void:
	var fruit_resource_id: String = String(bush.get_meta("fruit_resource"))
	var berry_type: Dictionary = BerryTypes.get_type(fruit_resource_id)
	if berry_type.is_empty():
		# 2026-07-06 (revue de code, paquet C, M47) : un fruit_resource
		# corrompu/invalide (id absent de BerryTypes) passait inapercu -
		# avertissement pour le reperer (repousse silencieusement ignoree).
		push_warning("BerryBushes: fruit_resource '%s' inconnu de BerryTypes, repousse de baie ignoree" % fruit_resource_id)
		return
	var categorie: String = String(bush.get_meta("categorie", "buisson"))
	_place_berry(bush, index, categorie, berry_type)


## 2026-07-05 (revue de code, item F024) : positionnement d'une baie factorise
## ici - etait duplique a l'identique dans _build_one_berry/_build_bush_visual/
## _build_plant_visual (3 occurrences, seuil DRY depasse), risque de divergence
## si l'une des copies etait corrigee sans les 2 autres. Meme formule qu'avant :
## touffe basse et resserree pour une "plante", couronne en hauteur pour un
## "buisson".
func _place_berry(bush: Node3D, index: int, categorie: String, berry_type: Dictionary) -> void:
	var berry := MeshInstance3D.new()
	var berry_mesh := SphereMesh.new()
	var pos: Vector3
	if categorie == "plante":
		# 2026-07-05 (demande explicite Francois, "agrandir les fraises et les
		# framboises") : rayon/hauteur doubles (etaient 0.05/0.10, jugees trop
		# petites pour bien lire la forme du fruit) - dispersion (dist) un peu
		# elargie en consequence pour eviter que des baies plus grosses ne se
		# chevauchent trop autour de la meme plante.
		berry_mesh.radius = 0.10
		berry_mesh.height = 0.20
		var angle: float = index * TAU / float(BERRIES_PER_BUSH) + randf_range(-0.3, 0.3)
		var dist: float = randf_range(0.10, 0.24)
		pos = Vector3(cos(angle) * dist, 0.20, sin(angle) * dist)
	else:
		berry_mesh.radius = 0.055
		berry_mesh.height = 0.11
		# 2026-07-05 (3e passe, meme jour - "reduire la taille des baies" + "plus
		# de baies par buisson" + "placement aleatoire tout autour, hauteur et
		# angle") : baies retrecies (etaient 0.08/0.16), comptees via
		# BUISSON_BERRIES_COUNT (10, au lieu de BERRIES_PER_BUSH reserve aux
		# plantes), ancrees a la surface reelle du corps (rayon x 1.05-1.2),
		# direction 3D (azimut + elevation) sur la sphere complete (-90..+90,
		# avant -50..+40) pour rester visible a toute hauteur/angle.
		var angle2: float = index * TAU / float(BUISSON_BERRIES_COUNT) + randf_range(-0.15, 0.15)
		var elev2: float = randf_range(deg_to_rad(-90.0), deg_to_rad(90.0))
		var dist2: float = BUSH_BODY_RADIUS * randf_range(1.05, 1.2)
		pos = Vector3(
			cos(elev2) * cos(angle2) * dist2,
			BUSH_BODY_CENTER_Y + sin(elev2) * dist2,
			cos(elev2) * sin(angle2) * dist2
		)
	berry.mesh = berry_mesh
	berry.position = pos
	var berry_mat := StandardMaterial3D.new()
	berry_mat.albedo_color = berry_type["couleur"]
	berry.set_surface_override_material(0, berry_mat)
	berry.name = "Fruit_%d" % index
	bush.add_child(berry)


## Sprint 34 : meme principe que Forest.gd/_build_shared_meshes.
func _build_shared_meshes() -> void:
	_mmi[PartType.BUSH_BODY] = _make_mmi(_make_sphere_mesh(1.0))
	_mmi[PartType.PLANT_LEAF] = _make_mmi(_make_box_mesh(Vector3.ONE))
	for key in _mmi.keys():
		_pending_xforms[key] = []
		_pending_colors[key] = []


func _make_mmi(mesh: Mesh) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = MultiMesh.new()
	mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	mmi.multimesh.use_colors = true
	mmi.multimesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = mat
	add_child(mmi)
	return mmi


func _make_sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh


func _make_box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## Sprint 37bis : tire une position au hasard en rejetant l'eau (voir
## VoxelWorld.is_water) - meme logique que Forest.gd/_pick_dry_position.
func _pick_dry_position() -> Vector2:
	var x := randf_range(2.0, float(grid_width - 2))
	var z := randf_range(2.0, float(grid_depth - 2))
	var guard := 0
	while voxel_world != null and voxel_world.is_water(int(x), int(z)) and guard < 20:
		x = randf_range(2.0, float(grid_width - 2))
		z = randf_range(2.0, float(grid_depth - 2))
		guard += 1
	return Vector2(x, z)


## Sprint 38 (reliefs) : hauteur du sol (sommet de colonne + 1) a une position
## XZ donnee - meme principe que Dwarf.gd/_ground_y_at.
func _ground_y_at(x: float, z: float) -> float:
	if voxel_world == null:
		return ground_level
	var top: int = voxel_world.get_top_block_y(int(floor(x)), int(floor(z)))
	if top < 0:
		return ground_level
	return float(top) + 1.0


func _spawn_bush() -> void:
	var pos := _pick_dry_position()
	# 2026-07-06 (demande explicite Francois) : centre le buisson sur son bloc
	# de grille (case entiere) plutot que sur une position flottante
	# quelconque a l'interieur - un buisson decale dans sa case causait des
	# problemes lors de la cueillette.
	# 2026-07-06 (correctif parse error) : type explicite ("float"), :=
	# echouait a inferer le type de retour de floor() dans ce contexte.
	var x: float = floor(pos.x) + 0.5
	var z: float = floor(pos.y) + 0.5
	var berry_type: Dictionary = BerryTypes.random_type()

	var bush := Node3D.new()
	bush.name = "Bush_%d" % get_child_count()
	bush.position = Vector3(x, _ground_y_at(x, z), z)
	bush.add_to_group("cueillette")
	bush.add_to_group("bushes")  # Sprint 85 : groupe dedie pour update_view_level (distinct de "cueillette", partage avec les arbres fruitiers)
	var categorie: String = berry_type.get("categorie", "buisson")
	bush.set_meta("fruit_resource", berry_type["id"])
	bush.set_meta("fruits_left", _berries_count_for(categorie))
	bush.set_meta("species_name", berry_type["nom"])
	# Sprint 37 (backlog Phase 1 item 16) : necessaire pour reconstruire une
	# baie au bon endroit quand elle repousse (voir _build_one_berry).
	bush.set_meta("categorie", categorie)
	bush.scale = Vector3.ONE * size_multiplier  # meme mecanisme que Forest.gd/tree.scale, ancre au sol
	add_child(bush)

	if categorie == "plante":
		_build_plant_visual(bush, berry_type)
	else:
		_build_bush_visual(bush, berry_type)

	# Sprint 34 : recolte le corps/les feuilles temporaires (voir
	# _build_bush_visual/_build_plant_visual) dans les MultiMesh partages,
	# et les supprime - seules les baies ("Fruit_%d") restent enfants de "bush".
	_harvest_and_clear(bush)


## Visuel "buisson" (myrtille/groseille/cassis) : boule de feuillage + baies
## disposees autour, a hauteur de genou.
## 2026-07-05 (signale par Francois : "sphere flottante, il faudrait une base
## au niveau du sol") : centre remonte a BUSH_BODY_CENTER_Y (voir sa doc plus
## haut) au lieu de "radius" - la sphere s'enfonce desormais de 1/4 de sa
## hauteur dans le sol au lieu d'y etre tangente en un seul point.
func _build_bush_visual(bush: Node3D, berry_type: Dictionary) -> void:
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = BUSH_BODY_RADIUS
	body_mesh.height = BUSH_BODY_RADIUS * 2.0
	body.mesh = body_mesh
	body.position.y = BUSH_BODY_CENTER_Y
	var body_color := Color(0.25, 0.45, 0.15)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = body_color
	body.set_surface_override_material(0, body_mat)
	_tag_part(body, PartType.BUSH_BODY, body_color, Vector3.ONE * body_mesh.radius)
	bush.add_child(body)

	# 2026-07-05 (revue de code, item F024) : positionnement des baies
	# factorise dans _place_berry (voir sa doc plus haut).
	for i in range(BUISSON_BERRIES_COUNT):
		_place_berry(bush, i, "buisson", berry_type)


## Sprint 24sexies : visuel "plante" (fraise/framboise) - touffe basse de
## feuilles pres du sol (pas de grosse boule), avec les baies nichees dedans,
## beaucoup plus proche du sol qu'un buisson.
func _build_plant_visual(bush: Node3D, berry_type: Dictionary) -> void:
	var leaf_color := Color(0.20, 0.42, 0.16)
	var leaf_count := randi_range(6, 9)
	for i in range(leaf_count):
		var leaf := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(randf_range(0.12, 0.18), 0.015, randf_range(0.07, 0.11))
		leaf.mesh = mesh
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(0.05, 0.22)
		leaf.position = Vector3(cos(angle) * dist, 0.06 + randf_range(0.0, 0.05), sin(angle) * dist)
		leaf.rotation.y = angle + randf_range(-0.4, 0.4)
		leaf.rotation.x = randf_range(-0.15, 0.15)
		var leaf_mat := StandardMaterial3D.new()
		leaf_mat.albedo_color = leaf_color
		leaf_mat.roughness = 1.0
		leaf_mat.metallic = 0.0
		leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		leaf.set_surface_override_material(0, leaf_mat)
		_tag_part(leaf, PartType.PLANT_LEAF, leaf_color, mesh.size)
		bush.add_child(leaf)

	# 2026-07-05 (revue de code, item F024) : positionnement des baies
	# factorise dans _place_berry (voir sa doc plus haut).
	for i in range(BERRIES_PER_BUSH):
		_place_berry(bush, i, "plante", berry_type)


## Sprint 34 : marque une MeshInstance3D temporaire comme "piece a recolter"
## (meme principe que Forest.gd/_tag_part).
func _tag_part(node: MeshInstance3D, part_type: int, color: Color, part_scale: Vector3) -> void:
	node.set_meta("part_type", part_type)
	node.set_meta("part_color", color)
	node.set_meta("part_scale", part_scale)


## Sprint 34 : recolte le corps/les feuilles taguees sous "bush" (jamais les
## baies "Fruit_%d", qui n'ont pas cette meta) dans les MultiMesh partages,
## puis supprime uniquement les enfants non-baies de "bush" (meme logique que
## Forest.gd/_harvest_and_clear, mais "bush" lui-meme reste - il porte le
## groupe "cueillette" et les metadonnees necessaires a la recolte).
func _harvest_and_clear(bush: Node3D) -> void:
	var parts: Array = []
	_collect_tagged_parts(bush, parts)
	var refs: Array = []
	for node in parts:
		var part_type: int = node.get_meta("part_type")
		var color: Color = node.get_meta("part_color")
		var part_scale: Vector3 = node.get_meta("part_scale")
		var xform: Transform3D = node.global_transform * Transform3D(Basis().scaled(part_scale), Vector3.ZERO)
		_pending_xforms[part_type].append(xform)
		_pending_colors[part_type].append(color)
		refs.append([part_type, _pending_xforms[part_type].size() - 1])  # Sprint 85 : reference pour update_view_level (meme principe que Forest.gd)

	bush.set_meta("visual_refs", refs)

	for child in bush.get_children():
		if not (child.name as String).begins_with("Fruit_"):
			child.queue_free()


## Remplit "out" avec tous les descendants de "node" tagues via _tag_part.
func _collect_tagged_parts(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child.has_meta("part_type"):
			out.append(child)
		_collect_tagged_parts(child, out)


## Sprint 34 : applique une seule fois, apres avoir genere TOUS les buissons,
## les instances en attente a chaque MultiMeshInstance3D partage.
func _apply_pending_instances() -> void:
	for part_type in _mmi.keys():
		var mmi: MultiMeshInstance3D = _mmi[part_type]
		var xforms: Array = _pending_xforms[part_type]
		var colors: Array = _pending_colors[part_type]
		mmi.multimesh.instance_count = xforms.size()
		for i in range(xforms.size()):
			mmi.multimesh.set_instance_transform(i, xforms[i])
			mmi.multimesh.set_instance_color(i, colors[i])


## 2026-07-05 (cycle des saisons, demande explicite de Francois : "buissons
## couleur plus claire" au printemps, "teinte rouge" en automne (idem que les
## arbres), "teinte grise" en hiver) - UNIQUEMENT PartType.BUSH_BODY (jamais
## PLANT_LEAF : les plantes/fraise-framboise ne sont pas mentionnees, elles ne
## changent pas de couleur avec la saison). Repart toujours de la couleur de
## BASE (_pending_colors, jamais reecrite ailleurs - voir sa declaration),
## meme principe que Forest.gd/apply_season_tint pour eviter toute derive.
const SEASON_BODY_TINT := {
	"ete": Color(1.0, 1.0, 1.0),
	"printemps": Color(1.15, 1.18, 1.05),
}
# 2026-07-06 (Francois : "les buissons... ne sont pas assez rouges en
# automne") : meme cause et meme correctif qu'un lerp cote Forest.gd - la
# couleur de base du corps du buisson, Color(0.25, 0.45, 0.15), est plus verte
# que rouge ; un simple facteur multiplicatif ne pouvait pas inverser cette
# dominante. Meme couleur cible que les arbres (voir Forest.gd), pour que
# l'automne ait une palette coherente entre arbres et buissons.
const AUTOMNE_BODY_TARGET := Color(0.55, 0.10, 0.05)
const AUTOMNE_BODY_STRENGTH := 0.65
# 2026-07-06 (Francois : "et les buissons doivent etre plus gris [en hiver].
# peut-etre le meme bug qu'avec les arbres") : meme cause que l'automne
# ci-dessus - Color(0.72, 0.7, 0.7) multiplie par la base verte donnait
# (0.18, 0.315, 0.105), toujours vert dominant, pas gris du tout (verifie
# numeriquement avant ce correctif). Passage en lerp vers un gris quasi
# neutre, comme pour l'automne.
const HIVER_BODY_TARGET := Color(0.5, 0.5, 0.48)
const HIVER_BODY_STRENGTH := 0.85

func apply_season_tint(season_id: String) -> void:
	var mmi: MultiMeshInstance3D = _mmi[PartType.BUSH_BODY]
	var base_colors: Array = _pending_colors[PartType.BUSH_BODY]
	if season_id == "automne":
		for i in range(base_colors.size()):
			mmi.multimesh.set_instance_color(i, base_colors[i].lerp(AUTOMNE_BODY_TARGET, AUTOMNE_BODY_STRENGTH))
		return
	if season_id == "hiver":
		for i in range(base_colors.size()):
			mmi.multimesh.set_instance_color(i, base_colors[i].lerp(HIVER_BODY_TARGET, HIVER_BODY_STRENGTH))
		return
	var tint: Color = SEASON_BODY_TINT.get(season_id, Color(1.0, 1.0, 1.0))
	for i in range(base_colors.size()):
		mmi.multimesh.set_instance_color(i, base_colors[i] * tint)


## Sprint 85 (2026-07-04, meme demande que Forest.gd/update_view_level -
## voir ses commentaires pour le detail complet du raisonnement) : cache/
## reaffiche chaque buisson/plante selon que son bloc de sol (bush.position.y
## - 1.0) est au-dessus ou non du niveau de vue courant. Restauration via
## _pending_xforms (jamais vide apres _apply_pending_instances). Les baies
## ("Fruit_%d") bascules via leur propre "visible".
func update_view_level(level: int) -> void:
	var zero_xform := Transform3D(Basis().scaled(Vector3.ONE * HIDDEN_INSTANCE_SCALE), Vector3.ZERO)
	for bush in get_tree().get_nodes_in_group("bushes"):
		var ground_block_y: float = bush.position.y - 1.0
		var hidden: bool = ground_block_y > float(level)
		if bush.has_meta("visual_refs"):
			var refs: Array = bush.get_meta("visual_refs")
			for ref in refs:
				var part_type: int = ref[0]
				var idx: int = ref[1]
				if hidden:
					_mmi[part_type].multimesh.set_instance_transform(idx, zero_xform)
				else:
					_mmi[part_type].multimesh.set_instance_transform(idx, _pending_xforms[part_type][idx])
		for child in bush.get_children():
			if (child.name as String).begins_with("Fruit_"):
				## 2026-07-06 : sans "and not _winter_active", cette ligne
				## réaffichait les baies déjà cachées par l'hiver dès qu'un
				## changement de niveau de vue appelait update_view_level().
				child.visible = not hidden and not _winter_active
