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

## Sprint 37bis (2026-07-03, correction bug "empecher les arbres et buissons
## dans l'eau") - voir la meme correction dans Forest.gd/_pick_dry_position.
@onready var voxel_world: Node3D = %VoxelWorld

@export var grid_width: int = 100  # 2026-07-03 : map resize (etait 20)
@export var grid_depth: int = 100  # 2026-07-03 : map resize (etait 20)
@export var ground_level: float = 50.0  # sommet de la carte (HEIGHT, 2026-07-03 : map resize, etait 30)
@export var size_multiplier: float = 0.9  # 2026-07-02 : buissons/plantes reduits de 10% (jauges nains/arbres/buissons rejustees)
const BERRIES_PER_BUSH := 4

# 2026-07-03 (map resize) : remplace l'ancien bush_count fixe (8, sur la
# carte 20x20=400 cases d'origine) par une densite (nombre par 1000 cases),
# meme principe que Forest.tree_density_per_1000_tiles - garde la meme
# densite qu'avant (8/400*1000 = 20) quelle que soit la taille de la carte.
@export var bush_density_per_1000_tiles: float = 20.0

## Un type par "piece" decorative (hors baies, qui restent individuelles).
enum PartType { BUSH_BODY, PLANT_LEAF }

var _mmi: Dictionary = {}              # PartType -> MultiMeshInstance3D
var _pending_xforms: Dictionary = {}   # PartType -> Array[Transform3D]
var _pending_colors: Dictionary = {}   # PartType -> Array[Color]


func _ready() -> void:
	randomize()
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


func _regrow_one_berry() -> void:
	var candidates: Array = []
	for bush in get_children():
		if bush.has_meta("fruits_left") and int(bush.get_meta("fruits_left")) < BERRIES_PER_BUSH:
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
	var berry_type: Dictionary = BerryTypes.get_type(String(bush.get_meta("fruit_resource")))
	if berry_type.is_empty():
		return
	var categorie: String = String(bush.get_meta("categorie", "buisson"))
	var berry := MeshInstance3D.new()
	var berry_mesh := SphereMesh.new()
	var pos: Vector3
	if categorie == "plante":
		berry_mesh.radius = 0.05
		berry_mesh.height = 0.10
		var angle: float = index * TAU / float(BERRIES_PER_BUSH) + randf_range(-0.3, 0.3)
		var dist: float = randf_range(0.08, 0.18)
		pos = Vector3(cos(angle) * dist, 0.10, sin(angle) * dist)
	else:
		berry_mesh.radius = 0.08
		berry_mesh.height = 0.16
		var angle2: float = index * TAU / float(BERRIES_PER_BUSH)
		pos = Vector3(cos(angle2) * 0.35, 0.55, sin(angle2) * 0.35)
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
	var x := pos.x
	var z := pos.y
	var berry_type: Dictionary = BerryTypes.random_type()

	var bush := Node3D.new()
	bush.name = "Bush_%d" % get_child_count()
	bush.position = Vector3(x, _ground_y_at(x, z), z)
	bush.add_to_group("cueillette")
	bush.add_to_group("bushes")  # Sprint 85 : groupe dedie pour update_view_level (distinct de "cueillette", partage avec les arbres fruitiers)
	bush.set_meta("fruit_resource", berry_type["id"])
	bush.set_meta("fruits_left", BERRIES_PER_BUSH)
	bush.set_meta("species_name", berry_type["nom"])
	# Sprint 37 (backlog Phase 1 item 16) : necessaire pour reconstruire une
	# baie au bon endroit quand elle repousse (voir _build_one_berry).
	bush.set_meta("categorie", berry_type.get("categorie", "buisson"))
	bush.scale = Vector3.ONE * size_multiplier  # meme mecanisme que Forest.gd/tree.scale, ancre au sol
	add_child(bush)

	if berry_type.get("categorie", "buisson") == "plante":
		_build_plant_visual(bush, berry_type)
	else:
		_build_bush_visual(bush, berry_type)

	# Sprint 34 : recolte le corps/les feuilles temporaires (voir
	# _build_bush_visual/_build_plant_visual) dans les MultiMesh partages,
	# et les supprime - seules les baies ("Fruit_%d") restent enfants de "bush".
	_harvest_and_clear(bush)


## Visuel "buisson" (myrtille/groseille/cassis) : boule de feuillage + baies
## disposees autour, a hauteur de genou - inchange depuis les sprints precedents.
func _build_bush_visual(bush: Node3D, berry_type: Dictionary) -> void:
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.4
	body_mesh.height = 0.8
	body.mesh = body_mesh
	body.position.y = 0.4
	var body_color := Color(0.25, 0.45, 0.15)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = body_color
	body.set_surface_override_material(0, body_mat)
	_tag_part(body, PartType.BUSH_BODY, body_color, Vector3.ONE * body_mesh.radius)
	bush.add_child(body)

	var berry_mat := StandardMaterial3D.new()
	berry_mat.albedo_color = berry_type["couleur"]
	for i in range(BERRIES_PER_BUSH):
		var berry := MeshInstance3D.new()
		var berry_mesh := SphereMesh.new()
		berry_mesh.radius = 0.08
		berry_mesh.height = 0.16
		berry.mesh = berry_mesh
		var angle := i * TAU / float(BERRIES_PER_BUSH)
		berry.position = Vector3(cos(angle) * 0.35, 0.55, sin(angle) * 0.35)
		berry.set_surface_override_material(0, berry_mat)
		berry.name = "Fruit_%d" % i
		bush.add_child(berry)


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

	var berry_mat := StandardMaterial3D.new()
	berry_mat.albedo_color = berry_type["couleur"]
	for i in range(BERRIES_PER_BUSH):
		var berry := MeshInstance3D.new()
		var berry_mesh := SphereMesh.new()
		berry_mesh.radius = 0.05
		berry_mesh.height = 0.10
		berry.mesh = berry_mesh
		var angle := i * TAU / float(BERRIES_PER_BUSH) + randf_range(-0.3, 0.3)
		var dist := randf_range(0.08, 0.18)
		berry.position = Vector3(cos(angle) * dist, 0.10, sin(angle) * dist)
		berry.set_surface_override_material(0, berry_mat)
		berry.name = "Fruit_%d" % i
		bush.add_child(berry)


## Sprint 34 : marque une MeshInstance3D temporaire comme "piece a recolter"
## (meme principe que Forest.gd/_tag_part).
func _tag_part(node: MeshInstance3D, part_type: int, color: Color, scale: Vector3) -> void:
	node.set_meta("part_type", part_type)
	node.set_meta("part_color", color)
	node.set_meta("part_scale", scale)


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


## Sprint 85 (2026-07-04, meme demande que Forest.gd/update_view_level -
## voir ses commentaires pour le detail complet du raisonnement) : cache/
## reaffiche chaque buisson/plante selon que son bloc de sol (bush.position.y
## - 1.0) est au-dessus ou non du niveau de vue courant. Restauration via
## _pending_xforms (jamais vide apres _apply_pending_instances). Les baies
## ("Fruit_%d") bascules via leur propre "visible".
func update_view_level(level: int) -> void:
	var zero_xform := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
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
				child.visible = not hidden
