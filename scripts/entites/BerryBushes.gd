extends Node3D
## Place des buissons/plantes a baies au hasard sur la carte (densite par
## 1000 cases, voir bush_density_per_1000_tiles), a distance de laquelle les
## nains se nourrissent. Deux visuels distincts selon BerryTypes.categorie :
## "buisson" (myrtille/groseille/cassis) = boule de feuillage + baies autour ;
## "plante" (fraise/framboise) = touffe de feuilles basse au ras du sol, baies
## nichees dedans.
##
## Les baies sont recoltees en inventaire via l'action "Cueillir" (memes
## metadonnees fruit_resource/fruits_left et convention de nommage Fruit_%d
## que les arbres fruitiers, voir Forest.gd et Dwarf.gd pour la recolte). Le
## buisson reste en place une fois vide (pas de disparition).
##
## Le corps du buisson/les feuilles de la plante sont construits comme des
## MeshInstance3D temporaires puis recoltes dans des MultiMeshInstance3D
## partages (voir _harvest_and_clear) - seul le noeud "bush" (position/
## groupe/metadonnees, utilise pour la cueillette) et les baies ("Fruit_%d",
## peu nombreuses, recoltees une par une) restent des noeuds individuels.

const BerryTypes := preload("res://scripts/data/materiaux/types/baies/BerryTypes.gd")
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")
const HoverableScript := preload("res://scripts/systemes/Hoverable.gd")
const ViewLevelIndexScript := preload("res://scripts/systemes/ViewLevelIndex.gd")

## Rayon/hauteur du collider de detection souris (voir Hoverable.gd) - un peu
## plus large que BUSH_BODY_RADIUS pour couvrir aussi les baies visibles en
## surface. Herite de bush.scale (size_multiplier, voir _spawn_bush).
const BUSH_HOVER_RADIUS := 0.6
const BUSH_HOVER_HEIGHT := 1.0

@onready var voxel_world: Node3D = %VoxelWorld

# WIDTH/DEPTH ne sont plus des const cote VoxelWorld (reglables depuis
# StartMenu.gd, voir taille de carte) - ne peuvent donc plus l'etre ici non
# plus (mais restent figes une fois lus, la taille ne change jamais en cours
# de partie).
var grid_width: int = VoxelWorldScript.WIDTH
var grid_depth: int = VoxelWorldScript.DEPTH
const ground_level := float(VoxelWorldScript.HEIGHT)  # sommet de la carte
@export var size_multiplier: float = 0.9
const BERRIES_PER_BUSH := 4  # categorie "plante" (fraise/framboise)

## Nombre de baies pour la categorie "buisson" (myrtille/groseille/cassis),
## distinct de BERRIES_PER_BUSH pour que les deux categories restent
## reglables independamment.
const BUISSON_BERRIES_COUNT := 10

## radial_segments/rings par defaut de Godot (64/32) sont concus pour un gros
## objet unique bien visible - beaucoup trop detailles pour les petites
## spheres de ce fichier (corps de buisson, baies), qui se comptent par
## milliers sur une grande carte. Voir _place_berry pour le detail.
const BERRY_SPHERE_RADIAL_SEGMENTS := 8
const BERRY_SPHERE_RINGS := 5

## Le corps du buisson est une sphere tronquee : centre remonte a la moitie
## du rayon pour que 3/4 de sa hauteur reste visible au-dessus du sol et que
## le 1/4 du bas soit enterre (base posee au niveau du sol, pas un simple
## point de tangence).
const BUSH_BODY_RADIUS := 0.4
const BUSH_BODY_CENTER_Y := BUSH_BODY_RADIUS * 0.5


## Nombre maximal de baies pour une categorie donnee ("buisson"/"plante").
func _berries_count_for(categorie: String) -> int:
	if categorie == "plante":
		return BERRIES_PER_BUSH
	return BUISSON_BERRIES_COUNT


## Densite exprimee par 1000 cases plutot qu'un nombre fixe, pour rester
## coherente quelle que soit la taille de la carte.
@export var bush_density_per_1000_tiles: float = 20.0

## Un type par "piece" decorative (hors baies, qui restent individuelles).
enum PartType { BUSH_BODY, PLANT_LEAF }

## Cacher une instance de MultiMesh avec une echelle Vector3.ZERO pile (Basis
## totalement degenere) peut corrompre le rendu de tout le MultiMesh sous un
## materiau a eclairage reel - une echelle non nulle mais infime evite ce
## risque (voir update_view_level).
const HIDDEN_INSTANCE_SCALE := 0.0001

var _mmi: Dictionary = {}              # PartType -> MultiMeshInstance3D
var _pending_xforms: Dictionary = {}   # PartType -> Array[Transform3D]
var _pending_colors: Dictionary = {}   # PartType -> Array[Color] (couleur de BASE, jamais reecrite - voir apply_season_tint)

## Mis a jour par SeasonSystem.gd (voir set_winter_active) : empeche
## _regrow_one_berry de faire regermer une baie pendant que SeasonSystem.gd a
## deja mis fruits_left a 0 pour toute la duree de l'hiver.
var _winter_active: bool = false

## Index niveau de sol -> buissons a ce niveau (int -> Array[Node3D]), rempli
## dans _spawn_bush (le nombre de buissons est fixe a la generation - voir
## _ready, aucune creation dynamique contrairement aux arbres). Permet a
## update_view_level de ne toucher QUE les buissons dont le niveau de sol se
## trouve entre l'ancien et le nouveau niveau de vue, au lieu de rebalayer
## tout le groupe "bushes" (voir _apply_view_level_delta, perf 2026-07-08).
var _level_buckets: Dictionary = {}  # int -> Array[Node3D]
## -1 = pas encore initialise. Voir doc de update_view_level : le tout
## premier appel fait un scan complet classique, tous les suivants passent
## par _apply_view_level_delta.
var _last_view_level: int = -1


## Nombre de buissons construits avant de rendre la main au moteur (await
## process_frame) - generer toute la carte en un seul appel synchrone de
## _ready() bloquerait le rendu sans retour visuel pendant toute la duree.
## Chaque await coute au moins une frame complete (16-30ms) : une valeur trop
## basse (25) multiplie inutilement le nombre de pauses et degrade le temps
## de chargement total - releve a 150, meme raisonnement que Forest.BATCH_SIZE.
const BATCH_SIZE := 150

## Le decoupage par paquets (await) casse la garantie implicite de Godot
## comme quoi le _ready() d'un noeud precedent dans la scene finit toujours
## avant celui du noeud suivant. Les appelants qui dependent de la
## generation terminee (SeasonSystem.gd) doivent attendre explicitement ce
## signal avant leur premier appel a apply_season_tint().
signal generation_finished
var generation_done: bool = false

func _ready() -> void:
	_build_shared_meshes()
	var tile_count: float = float(grid_width * grid_depth)
	var bush_count: int = int(round(bush_density_per_1000_tiles * tile_count / 1000.0))
	for i in range(bush_count):
		_spawn_bush()
		if (i + 1) % BATCH_SIZE == 0:
			await get_tree().process_frame
	_apply_pending_instances()
	generation_done = true
	generation_finished.emit()


## Contrairement aux arbres, un buisson cueilli ne disparait jamais - la
## "repousse" consiste donc a faire regermer des baies au fil du temps sur
## les buissons partiellement ou completement vides, jusqu'a revenir au
## nombre maximal de la categorie. Une seule baie repousse a la fois
## (throttle), choisie au hasard parmi les buissons non pleins.
@export var berry_regrow_interval_seconds: float = 25.0
var _berry_regrow_timer: float = 0.0

func _process(delta: float) -> void:
	_berry_regrow_timer += delta * DayNightCycleScript.game_speed
	if _berry_regrow_timer < berry_regrow_interval_seconds:
		return
	_berry_regrow_timer = 0.0
	_regrow_one_berry()


## Appele par SeasonSystem.gd a chaque changement de saison (active = saison
## hiver).
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
	# Flux GameRandom dedie ("baies_geometrie") plutot que le RNG global -
	# reproductibilite par graine (revue de code M88), meme flux que
	# _place_berry/_pick_dry_position/_build_plant_visual ci-dessous.
	var bush: Node3D = candidates[GameRandom.get_rng("baies_geometrie").randi() % candidates.size()]
	var new_index: int = int(bush.get_meta("fruits_left"))
	bush.set_meta("fruits_left", new_index + 1)
	_build_one_berry(bush, new_index)


## Reconstruit visuellement UNE baie ("Fruit_%d") disparue - meme formule de
## position/taille que le placement initial (voir _place_berry), pour que la
## baie qui repousse soit indiscernable d'une baie d'origine.
func _build_one_berry(bush: Node3D, index: int) -> void:
	var fruit_resource_id: String = String(bush.get_meta("fruit_resource"))
	var berry_type: Dictionary = BerryTypes.get_type(fruit_resource_id)
	if berry_type.is_empty():
		push_warning("BerryBushes: fruit_resource '%s' inconnu de BerryTypes, repousse de baie ignoree" % fruit_resource_id)
		return
	var categorie: String = String(bush.get_meta("categorie", "buisson"))
	_place_berry(bush, index, categorie, berry_type)


## Positionne une baie sur un buisson/plante. "plante" : touffe basse et
## resserree pres du sol. "buisson" : baies reparties sur toute la sphere du
## corps (azimut + elevation), ancrees a sa surface.
func _place_berry(bush: Node3D, index: int, categorie: String, berry_type: Dictionary) -> void:
	var berry := MeshInstance3D.new()
	var berry_mesh := SphereMesh.new()
	# Chaque baie est un MeshInstance3D INDIVIDUEL (pas de MultiMesh possible
	# ici, voir _build_one_berry : doit pouvoir disparaitre une par une a la
	# cueillette) - avec potentiellement plusieurs baies par buisson et des
	# milliers de buissons sur une grande carte, garder les segments par
	# defaut de Godot (64/32, penses pour un objet unique bien visible)
	# multiplie ce cout par des dizaines de milliers d'instances. Reduit ici
	# a une valeur largement suffisante pour une si petite sphere vue de
	# loin - meme principe que TREE_SPHERE_RADIAL_SEGMENTS/_RINGS dans
	# Forest.gd.
	berry_mesh.radial_segments = BERRY_SPHERE_RADIAL_SEGMENTS
	berry_mesh.rings = BERRY_SPHERE_RINGS
	# Flux GameRandom dedie ("baies_geometrie") plutot que le RNG global -
	# reproductibilite par graine (revue de code M88).
	var rng: RandomNumberGenerator = GameRandom.get_rng("baies_geometrie")
	var pos: Vector3
	if categorie == "plante":
		berry_mesh.radius = 0.10
		berry_mesh.height = 0.20
		var angle: float = index * TAU / float(BERRIES_PER_BUSH) + rng.randf_range(-0.3, 0.3)
		var dist: float = rng.randf_range(0.10, 0.24)
		pos = Vector3(cos(angle) * dist, 0.20, sin(angle) * dist)
	else:
		berry_mesh.radius = 0.055
		berry_mesh.height = 0.11
		var angle2: float = index * TAU / float(BUISSON_BERRIES_COUNT) + rng.randf_range(-0.15, 0.15)
		var elev2: float = rng.randf_range(deg_to_rad(-90.0), deg_to_rad(90.0))
		var dist2: float = BUSH_BODY_RADIUS * rng.randf_range(1.05, 1.2)
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
	# Voir commentaire de _place_berry/BERRY_SPHERE_RADIAL_SEGMENTS - meme
	# raison ici (modele partage via MultiMesh, instancie pour chaque
	# buisson de la carte).
	mesh.radial_segments = BERRY_SPHERE_RADIAL_SEGMENTS
	mesh.rings = BERRY_SPHERE_RINGS
	return mesh


func _make_box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## Tire une position au hasard en rejetant l'eau (voir VoxelWorld.is_water).
func _pick_dry_position() -> Vector2:
	# Flux GameRandom dedie ("baies_geometrie") plutot que le RNG global -
	# reproductibilite par graine (revue de code M88).
	var rng: RandomNumberGenerator = GameRandom.get_rng("baies_geometrie")
	var x := rng.randf_range(2.0, float(grid_width - 2))
	var z := rng.randf_range(2.0, float(grid_depth - 2))
	var guard := 0
	while voxel_world != null and voxel_world.is_water(int(x), int(z)) and guard < 20:
		x = rng.randf_range(2.0, float(grid_width - 2))
		z = rng.randf_range(2.0, float(grid_depth - 2))
		guard += 1
	return Vector2(x, z)


## Hauteur du sol (sommet de colonne + 1) a une position XZ donnee.
func _ground_y_at(x: float, z: float) -> float:
	if voxel_world == null:
		return ground_level
	var top: int = voxel_world.get_top_block_y(int(floor(x)), int(floor(z)))
	if top < 0:
		return ground_level
	return float(top) + 1.0


func _spawn_bush() -> void:
	var pos := _pick_dry_position()
	# Centre sur son bloc de grille (case entiere) plutot que sur une
	# position flottante quelconque a l'interieur, pour rester coherent avec
	# la cueillette.
	var x: float = floor(pos.x) + 0.5
	var z: float = floor(pos.y) + 0.5
	var berry_type: Dictionary = BerryTypes.random_type()

	var bush := Node3D.new()
	bush.name = "Bush_%d" % get_child_count()
	bush.position = Vector3(x, _ground_y_at(x, z), z)
	bush.add_to_group("cueillette")
	bush.add_to_group("bushes")  # groupe dedie pour update_view_level (distinct de "cueillette", partage avec les arbres fruitiers)

	# Index par niveau de sol via ViewLevelIndex.gd (voir doc de _level_buckets).
	var _ground_lvl: int = int(bush.position.y - 1.0)
	ViewLevelIndexScript.register(_level_buckets, bush, _ground_lvl)

	var categorie: String = berry_type.get("categorie", "buisson")
	bush.set_meta("fruit_resource", berry_type["id"])
	bush.set_meta("fruits_left", _berries_count_for(categorie))
	bush.set_meta("species_name", berry_type["nom"])
	bush.set_meta("categorie", categorie)  # necessaire pour reconstruire une baie au bon endroit quand elle repousse (voir _build_one_berry)
	bush.set_meta("hover_kind", "gatherable")  # voir EntityDescriptions.describe_by_kind
	bush.scale = Vector3.ONE * size_multiplier  # meme mecanisme que Forest.gd/tree.scale, ancre au sol
	add_child(bush)

	if categorie == "plante":
		_build_plant_visual(bush, berry_type)
	else:
		_build_bush_visual(bush, berry_type)

	# Recolte le corps/les feuilles temporaires dans les MultiMesh partages,
	# et les supprime - seules les baies ("Fruit_%d") restent enfants de "bush".
	_harvest_and_clear(bush)

	# Collider de detection souris (voir Hoverable.gd) - DOIT venir APRES
	# _harvest_and_clear() : celle-ci supprime tout enfant de "bush" dont le
	# nom ne commence pas par "Fruit_" - attache avant, le collider etait
	# detruit aussitot.
	var hover_shape := CylinderShape3D.new()
	hover_shape.radius = BUSH_HOVER_RADIUS
	hover_shape.height = BUSH_HOVER_HEIGHT
	HoverableScript.attach(bush, hover_shape, Vector3(0, BUSH_HOVER_HEIGHT * 0.5, 0))


## Visuel "buisson" (myrtille/groseille/cassis) : boule de feuillage + baies
## disposees autour, a hauteur de genou.
func _build_bush_visual(bush: Node3D, berry_type: Dictionary) -> void:
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = BUSH_BODY_RADIUS
	body_mesh.height = BUSH_BODY_RADIUS * 2.0
	body_mesh.radial_segments = BERRY_SPHERE_RADIAL_SEGMENTS
	body_mesh.rings = BERRY_SPHERE_RINGS
	body.mesh = body_mesh
	body.position.y = BUSH_BODY_CENTER_Y
	var body_color := Color(0.25, 0.45, 0.15)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = body_color
	body.set_surface_override_material(0, body_mat)
	_tag_part(body, PartType.BUSH_BODY, body_color, Vector3.ONE * body_mesh.radius)
	bush.add_child(body)

	for i in range(BUISSON_BERRIES_COUNT):
		_place_berry(bush, i, "buisson", berry_type)


## Visuel "plante" (fraise/framboise) : touffe basse de feuilles pres du sol
## (pas de grosse boule), avec les baies nichees dedans, beaucoup plus proche
## du sol qu'un buisson.
func _build_plant_visual(bush: Node3D, berry_type: Dictionary) -> void:
	var leaf_color := Color(0.20, 0.42, 0.16)
	# Flux GameRandom dedie ("baies_geometrie") plutot que le RNG global -
	# reproductibilite par graine (revue de code M88).
	var rng: RandomNumberGenerator = GameRandom.get_rng("baies_geometrie")
	var leaf_count := rng.randi_range(6, 9)
	for i in range(leaf_count):
		var leaf := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(rng.randf_range(0.12, 0.18), 0.015, rng.randf_range(0.07, 0.11))
		leaf.mesh = mesh
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(0.05, 0.22)
		leaf.position = Vector3(cos(angle) * dist, 0.06 + rng.randf_range(0.0, 0.05), sin(angle) * dist)
		leaf.rotation.y = angle + rng.randf_range(-0.4, 0.4)
		leaf.rotation.x = rng.randf_range(-0.15, 0.15)
		var leaf_mat := StandardMaterial3D.new()
		leaf_mat.albedo_color = leaf_color
		leaf_mat.roughness = 1.0
		leaf_mat.metallic = 0.0
		leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		leaf.set_surface_override_material(0, leaf_mat)
		_tag_part(leaf, PartType.PLANT_LEAF, leaf_color, mesh.size)
		bush.add_child(leaf)

	for i in range(BERRIES_PER_BUSH):
		_place_berry(bush, i, "plante", berry_type)


## Marque une MeshInstance3D temporaire comme "piece a recolter" dans le
## MultiMesh partage correspondant (voir _harvest_and_clear).
func _tag_part(node: MeshInstance3D, part_type: int, color: Color, part_scale: Vector3) -> void:
	node.set_meta("part_type", part_type)
	node.set_meta("part_color", color)
	node.set_meta("part_scale", part_scale)


## Recolte le corps/les feuilles taguees sous "bush" (jamais les baies
## "Fruit_%d", qui n'ont pas cette meta) dans les MultiMesh partages, puis
## supprime uniquement les enfants non-baies de "bush" - "bush" lui-meme
## reste, il porte le groupe "cueillette" et les metadonnees necessaires a
## la recolte.
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
		refs.append([part_type, _pending_xforms[part_type].size() - 1])  # reference pour update_view_level

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


## Applique une seule fois, apres avoir genere TOUS les buissons, les
## instances en attente a chaque MultiMeshInstance3D partage.
func _apply_pending_instances() -> void:
	for part_type in _mmi.keys():
		var mmi: MultiMeshInstance3D = _mmi[part_type]
		var xforms: Array = _pending_xforms[part_type]
		var colors: Array = _pending_colors[part_type]
		mmi.multimesh.instance_count = xforms.size()
		for i in range(xforms.size()):
			mmi.multimesh.set_instance_transform(i, xforms[i])
			mmi.multimesh.set_instance_color(i, colors[i])


## Teinte saisonniere appliquee uniquement a PartType.BUSH_BODY (les
## plantes/fraise-framboise ne changent pas de couleur avec la saison).
## Repart toujours de la couleur de BASE (_pending_colors, jamais reecrite
## ailleurs) pour eviter toute derive cumulative.
const SEASON_BODY_TINT := {
	"ete": Color(1.0, 1.0, 1.0),
	"printemps": Color(1.15, 1.18, 1.05),
}
# La couleur de base du corps du buisson, Color(0.25, 0.45, 0.15), est plus
# verte que rouge : un simple facteur multiplicatif ne peut pas inverser
# cette dominante vers du rouge/gris. L'automne et l'hiver utilisent donc un
# lerp vers une couleur cible plutot qu'une multiplication (meme technique
# que Forest.gd, pour une palette coherente entre arbres et buissons).
const AUTOMNE_BODY_TARGET := Color(0.55, 0.10, 0.05)
const AUTOMNE_BODY_STRENGTH := 0.65
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


## Cache/reaffiche chaque buisson/plante selon que son bloc de sol
## (bush.position.y - 1.0) est au-dessus ou non du niveau de vue courant.
## Restauration via _pending_xforms (jamais vide apres
## _apply_pending_instances). Les baies ("Fruit_%d") basculent via leur
## propre "visible".
## Perf (2026-07-08) : le tout premier appel fait un scan complet classique
## (_apply_view_level_full, identique au comportement d'avant l'indexation).
## Tous les appels suivants (donc chaque cran de molette) passent par
## _apply_view_level_delta, qui ne touche que les buissons dont le niveau de
## sol se trouve entre l'ancien et le nouveau niveau de vue via
## _level_buckets, au lieu de rebalayer tout le groupe "bushes".
func update_view_level(level: int) -> void:
	if _last_view_level == -1:
		_apply_view_level_full(level)
	else:
		_apply_view_level_delta(_last_view_level, level)
	_last_view_level = level


## Bascule un seul buisson cache/visible selon "hidden" (facteur commun entre
## le scan complet et le scan incremental).
func _apply_bush_visibility(bush: Node3D, hidden: bool, zero_xform: Transform3D) -> void:
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
			# "and not _winter_active" evite de reafficher des baies deja
			# cachees par l'hiver quand update_view_level() est rappele.
			child.visible = not hidden and not _winter_active
	# Le collider de survol (voir Hoverable.gd) doit suivre la meme regle que
	# le visuel MultiMesh ci-dessus - sinon un buisson/plante cache par la
	# coupe resterait detectable par le survol/ciblage.
	HoverableScript.set_enabled(bush, not hidden)


## Scan complet (tout le groupe "bushes") - utilise uniquement pour le tout
## premier appel de update_view_level (voir sa doc).
func _apply_view_level_full(level: int) -> void:
	var zero_xform := Transform3D(Basis().scaled(Vector3.ONE * HIDDEN_INSTANCE_SCALE), Vector3.ZERO)
	var bushes: Array = get_tree().get_nodes_in_group("bushes")
	var ground_y_fn := func(bush): return int(bush.position.y - 1.0)
	var apply_fn := func(bush, hidden): _apply_bush_visibility(bush, hidden, zero_xform)
	ViewLevelIndexScript.full_scan(bushes, level, ground_y_fn, apply_fn)


## Scan incremental : ne touche que les buissons dont le niveau de sol se
## trouve entre l'ancien et le nouveau niveau de vue (voir doc de
## _level_buckets et de ViewLevelIndex.delta_scan).
func _apply_view_level_delta(old_level: int, new_level: int) -> void:
	var zero_xform := Transform3D(Basis().scaled(Vector3.ONE * HIDDEN_INSTANCE_SCALE), Vector3.ZERO)
	var apply_fn := func(bush, hidden):
		if is_instance_valid(bush):
			_apply_bush_visibility(bush, hidden, zero_xform)
	ViewLevelIndexScript.delta_scan(_level_buckets, old_level, new_level, apply_fn)
