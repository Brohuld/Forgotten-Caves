extends Node3D

const VoxelVeinsScript := preload("res://scripts/monde/voxel/VoxelVeins.gd")
const VoxelMeshBuilderScript := preload("res://scripts/monde/voxel/VoxelMeshBuilder.gd")
const VoxelHydrologyScript := preload("res://scripts/monde/voxel/VoxelHydrology.gd")
## Reutilise UNIQUEMENT _build_quarter_cylinder_mesh() (meme geometrie deja
## validee que V1/CubeSolTest.gd) - voir _setup_cascade_rendering().
const WaterfallShapesScript := preload("res://scripts/monde/WaterfallShapes.gd")

## Meme enum/ordre que VoxelHydrology.gd/VoxelMeshBuilder.gd (EMPTY=0, DIRT=1,
## STONE=2, WOOD_WALL=3, STONE_WALL=4, WATER=5) - ces deux scripts codent le
## BlockType en dur, un ordre different confondrait WATER avec WOOD_WALL.
enum BlockType { EMPTY, DIRT, STONE, WOOD_WALL, STONE_WALL, WATER }

const WIDTH := 50
const DEPTH := 50
const PROTOTYPE_SEED := 123456

const HILL_MIN := 1
const HILL_MAX := 5
const HILL_NOISE_FREQUENCY := 0.04
const SUBSOIL_DEPTH := 30
const DIRT_HEIGHT_MIN := 1
const DIRT_HEIGHT_MAX := 3

## Socle absolu (2026-07-10, Francois : "il faut que le fond soit plat") -
## FIXE pour toute la carte, independant du relief de chaque colonne.
## SUBSOIL_DEPTH est l'epaisseur de sous-sol sous la colonne la PLUS BASSE
## (HILL_MIN) ; les colonnes de colline creusent plus profond pour atteindre
## ce meme socle (voir _layer_to_y/_generate_composition). Avant ce fix,
## chaque colonne calculait son fond comme "MA surface - SUBSOIL_DEPTH", ce
## qui faisait onduler le fond avec le relief au lieu d'etre plat.
const BEDROCK_Y := HILL_MIN - SUBSOIL_DEPTH
const LAYER_COUNT := HILL_MAX - BEDROCK_Y + 1  # socle -> relief le plus haut possible

const CLIMATE_ID := "tempere"
const SEASON_ID := "ete"

const DIRECTIONS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

const MIN_VIEW_LEVEL := BEDROCK_Y
const MAX_VIEW_LEVEL := HILL_MAX

## Aretes DEBUG (Francois 2026-07-10, "je vois mal ou est le bug en 3D") -
## petites lignes foncees sur les aretes de chaque cube visible, pour tous les
## types de bloc.
const EDGE_COLOR := Color(0.05, 0.05, 0.05)

var composition: PackedByteArray = PackedByteArray()
var discovered: Dictionary = {}  # Vector3i -> true, tout marque decouvert (test uniquement)
var grid: Dictionary = {}        # Vector3i -> BlockType (CUBE)
var sol_grid: Dictionary = {}    # Vector3i -> BlockType, sparse (exceptions uniquement, voir _get_sol)
var vein_system := VoxelVeinsScript.new()
var mesh_builder := VoxelMeshBuilderScript.new()
var relief_noise := FastNoiseLite.new()
var terrain_noise := FastNoiseLite.new()
var stone_noise := FastNoiseLite.new()

## Rivieres + lacs + cascades (2026-07-10, reprise apres annulation - voir
## [[project_forgotten_caves_river_rules]]). hydrology = meme classe partagee que le jeu principal
## (VoxelHydrology.gd), appelee via son VRAI point d'entree portable
## `compute_water_columns()` (plus de raccourci `_place_rivers()` direct
## depuis que les lacs sont revenus - c'etait l'ecart de portabilite flague
## la 1ere fois, desormais resolu).
var hydrology := VoxelHydrologyScript.new()
var water_noise := FastNoiseLite.new()
var water_columns: Dictionary = {}   # Vector2i -> profondeur d'eau
var hill_overrides: Dictionary = {}  # Vector2i -> decalage de relief force (lac/palier riviere)
var waterfalls: Dictionary = {}      # Vector2i -> {"top","bottom","dx","dz","pool_surface_y"}, voir _build_cascade_shapes
var bank_faces: Dictionary = {}      # inutilise (brouillard de guerre, sans objet ici - tout est deja "discovered")

## Cascades (2026-07-10, voir _build_cascade_shapes) - un seul
## MeshInstance3D par colonne de cascade, cree une fois par
## WaterfallShapesScript._build_shape(), stocke dans cascade_mesh_container.
var cascade_material: StandardMaterial3D
var cascade_mesh_container: Node3D

var mesh_instance: MeshInstance3D
var edge_mesh_instance: MeshInstance3D
var edge_material: StandardMaterial3D
var view_level: int = MAX_VIEW_LEVEL

var cam: Camera3D
var orbit_target: Vector3
var orbit_yaw: float = 0.0
var orbit_pitch: float = -0.5
var orbit_distance: float = 55.0
const ORBIT_SENSITIVITY := 0.01
const ZOOM_STEP := 3.0
const MIN_DISTANCE := 5.0
const MAX_DISTANCE := 150.0
const PAN_SPEED := 20.0


func _ready() -> void:
	GameRandom.setup(PROTOTYPE_SEED)
	relief_noise.seed = GameRandom.get_rng("relief").randi()
	relief_noise.frequency = HILL_NOISE_FREQUENCY
	terrain_noise.seed = GameRandom.get_rng("terrain_couleur").randi()
	terrain_noise.frequency = 0.18
	stone_noise.seed = GameRandom.get_rng("pierre_couleur").randi()
	stone_noise.frequency = 0.18
	water_noise.seed = GameRandom.get_rng("eau").randi()
	water_noise.frequency = 0.15
	vein_system.setup_vein_noises()
	vein_system.setup_pepites_nodes(self)
	_compute_hydrology()
	_generate_composition()
	_compute_apparent()
	_setup_scene()
	_build_cascade_shapes()
	_rebuild_mesh(true)


## Cascades (2026-07-10, REECRIT apres avoir trouve le vrai design dans
## WaterfallShapes.gd/VoxelWorld.gd - voir memoire section 7bis) : le jeu reel
## n'ecrit JAMAIS de bloc d'eau dans la grille pour la chute elle-meme, un
## SEUL MeshInstance3D par colonne de cascade suffit (voir
## WaterfallShapes._build_shape - position/rotation/echelle deja valides,
## reutilises TELS QUELS ici, aucune logique reinventee). N'ecrit RIEN dans
## grid/discovered - purement decoratif, comme le jeu reel.
func _build_cascade_shapes() -> void:
	var shape_builder := WaterfallShapesScript.new()
	# height_offset = repere PROPRE a VoxelHydrology.gd (HEIGHT-1) - le jeu
	# reel n'a PAS besoin de cette conversion (son propre surface_y utilise
	# deja HEIGHT-1 comme base), mais V2 utilise HILL_MIN comme base (voir
	# _surface_y_for) - meme conversion que partout ailleurs dans ce fichier.
	var height_offset: int = hydrology.HEIGHT - 1
	for pos2d in waterfalls:
		var fall: Dictionary = waterfalls[pos2d]
		var col: Dictionary = {
			"x": pos2d.x,
			"z": pos2d.y,
			"dx": fall["dx"],
			"dz": fall["dz"],
			"top": HILL_MIN + int(fall["top"]) - height_offset,
			"pool_surface_y": HILL_MIN + int(fall["pool_surface_y"]) - height_offset,
		}
		var shape: MeshInstance3D = shape_builder._build_shape(col, cascade_material)
		cascade_mesh_container.add_child(shape)
	shape_builder.free()


## Rivieres + lacs (voir commentaire pres de "var hydrology" plus haut) -
## remplit water_columns/hill_overrides AVANT toute generation, puisque
## _surface_y_for()/_generate_composition() en dependent. Doit rester appelee
## avant _generate_composition().
func _compute_hydrology() -> void:
	var water_info: Dictionary = hydrology.compute_water_columns(
		water_noise, Callable(self, "_natural_hill_offset"), WIDTH, DEPTH)
	water_columns = water_info["cols"]
	hill_overrides = water_info["hill_overrides"]
	waterfalls = water_info["waterfalls"]
	bank_faces = water_info["bank_faces"]


func _composition_index(x: int, layer: int, z: int) -> int:
	return x + z * WIDTH + layer * WIDTH * DEPTH


## Decalage de relief NATUREL (bruit brut, avant tout palier de riviere) -
## meme convention que VoxelWorld._hill_height_at() : un OFFSET 0..(HILL_MAX-
## HILL_MIN), pas une position Y absolue. Passee a VoxelHydrology en
## Callable (hill_height_at), voir _compute_hydrology().
func _natural_hill_offset(x: int, z: int) -> int:
	var n := relief_noise.get_noise_2d(float(x), float(z))
	var t := (n + 1.0) * 0.5
	return int(round(t * (HILL_MAX - HILL_MIN)))


## Position Y absolue de la SURFACE : decalage naturel SAUF sur une colonne
## de riviere, ou hill_overrides impose son propre palier (voir
## VoxelWorld.generate_flat_terrain, meme formule HEIGHT-1+hill_offset a la
## base HILL_MIN pres).
func _surface_y_for(x: int, z: int) -> int:
	var offset: int = hill_overrides.get(Vector2i(x, z), _natural_hill_offset(x, z))
	return HILL_MIN + offset


## Correspondance ABSOLUE layer -> Y (2026-07-10, fond plat) : layer=0 =
## BEDROCK_Y (le socle, identique pour toute la carte), layer=LAYER_COUNT-1 =
## HILL_MAX (le relief le plus haut possible). Ne depend plus de x/z - avant
## ce fix, chaque colonne avait son propre repere (surface_y(x,z) - layer),
## ce qui faisait onduler le fond avec le relief.
func _layer_to_y(layer: int) -> int:
	return BEDROCK_Y + layer


## Colonne d'eau (meme regle que VoxelWorld.generate_flat_terrain, "CUBE=SOL=
## eau, aucun lit distinct") : PAS de SURFACE vide separee - les
## water_depth premiers layers (depuis le sommet REEL de la colonne, deja
## abaisse au palier via _surface_y_for/hill_overrides) sont directement de
## l'EAU, le sous-sol dirt/stone habituel continue juste en dessous. Colonne
## seche (water_depth=0) : comportement inchange (layer 0 = SURFACE vide).
## 2026-07-10 (Francois: "donc, on corrige le prototype") - le vecteur
## composition n'inclut PLUS les filons : le benchmark a confirme que
## maybe_place_vein() (jusqu'a 17 evaluations de bruit/bloc de pierre) est
## trop lent pour etre precalcule sur toute la carte (voir memoire section
## 3bis). Les filons restent geres par VoxelVeins.gd, mais separement de ce
## vecteur - plus appeles ici.
## Fond plat (2026-07-10) : "layer" indexe maintenant un Y ABSOLU
## (BEDROCK_Y + layer, voir _layer_to_y), identique pour toute la carte -
## "depth_from_surface" (surface_y - y) remplace l'ancien "layer" dans la
## logique metier (eau/terre/pierre), qui reste sinon inchangee. Si
## depth_from_surface < 0, ce layer est AU-DESSUS du relief de cette colonne
## precise -> EMPTY (les colonnes basses ont donc plusieurs layers hauts
## vides, c'est attendu : LAYER_COUNT couvre le relief le plus haut possible,
## pas seulement celui de CETTE colonne).
func _generate_composition() -> void:
	composition.resize(WIDTH * DEPTH * LAYER_COUNT)
	var rng := GameRandom.get_rng("sous_sol")
	for x in range(WIDTH):
		for z in range(DEPTH):
			var surface_y: int = _surface_y_for(x, z)
			var water_depth: int = water_columns.get(Vector2i(x, z), 0)
			var dirt_height := rng.randi_range(DIRT_HEIGHT_MIN, DIRT_HEIGHT_MAX)
			for layer in range(LAYER_COUNT):
				var depth_from_surface: int = surface_y - _layer_to_y(layer)
				var block_type: int
				if depth_from_surface < 0:
					block_type = BlockType.EMPTY  # au-dessus du relief de CETTE colonne
				elif depth_from_surface < water_depth:
					block_type = BlockType.WATER
				elif water_depth == 0 and depth_from_surface == 0:
					block_type = BlockType.EMPTY  # SURFACE seche
				else:
					var subsoil_index: int = depth_from_surface - maxi(water_depth, 1)
					block_type = BlockType.DIRT if subsoil_index < dirt_height else BlockType.STONE
				composition[_composition_index(x, layer, z)] = block_type


func _compute_apparent() -> void:
	# Tout marque "discovered" (demande explicite Francois) : le rendu passe
	# par la navigation view_level (molette), pas par un mode X-ray.
	for layer in range(LAYER_COUNT):
		for x in range(WIDTH):
			for z in range(DEPTH):
				var pos := Vector3i(x, _layer_to_y(layer), z)
				discovered[pos] = true
				grid[pos] = composition[_composition_index(x, layer, z)]


## Colonne d'eau : le CUBE est deja plein a la SURFACE (pas de couche vide
## separee, voir _generate_composition) - le sommet reel est _surface_y_for()
## lui-meme, pas -1 comme une colonne seche.
func _get_top_block_y(x: int, z: int) -> int:
	if water_columns.get(Vector2i(x, z), 0) > 0:
		return _surface_y_for(x, z)
	return _surface_y_for(x, z) - 1


## Meme regle par defaut que VoxelWorld.get_sol() (modele CUBE+SOL) : CUBE
## plein -> SOL = meme materiau ; CUBE vide -> SOL = terre uniquement sur la
## case marchable juste au-dessus du sommet reel de la colonne, ET SEULEMENT
## SI ce sommet n'est pas de l'eau, vide sinon.
##
## Fix 2026-07-10 (bug trouve en comparant avec le vrai VoxelWorld.get_sol()) :
## il manquait la garde "top n'est pas WATER" - sans elle, une colonne d'eau
## affichait une case de terre/herbe flottante juste au-dessus de sa surface
## (une colonne d'eau n'a pas de "terre" flottante au-dessus, deja couvert
## par le cas CUBE=eau ci-dessus).
func _get_sol(pos: Vector3i) -> int:
	if sol_grid.has(pos):
		return sol_grid[pos]
	var cube_type: int = grid.get(pos, BlockType.EMPTY)
	if cube_type != BlockType.EMPTY:
		return cube_type
	var top_y: int = _get_top_block_y(pos.x, pos.z)
	if pos.y == top_y + 1 and grid.get(Vector3i(pos.x, top_y, pos.z), BlockType.EMPTY) != BlockType.WATER:
		return BlockType.DIRT
	return BlockType.EMPTY


## Cascades : plus aucune donnee dans grid (voir _build_cascade_shapes) - la
## grille est envoyee TELLE QUELLE, aucune copie filtree necessaire.
func _rebuild_mesh(grid_changed: bool) -> void:
	mesh_builder.rebuild(grid, discovered, vein_system, view_level, WIDTH, DEPTH,
		false, 0.0, CLIMATE_ID, SEASON_ID, terrain_noise, stone_noise,
		DIRECTIONS, mesh_instance, Callable(self, "_get_top_block_y"), {},
		grid_changed, Callable(self, "_get_sol"))
	_rebuild_edges()
	# Meme mecanisme que le jeu reel (WaterfallShapes.update_view_level) :
	# bascule .visible sur les formes deja construites (waterfall_top <=
	# view_level), aucune reconstruction de geometrie.
	if cascade_mesh_container != null:
		for child in cascade_mesh_container.get_children():
			if child is MeshInstance3D and child.has_meta("waterfall_top"):
				child.visible = float(child.get_meta("waterfall_top")) <= float(view_level)


## Aretes DEBUG (voir EDGE_COLOR) : une case est visible si elle est
## exactement au niveau de coupe (view_level, toujours dessinee en cube
## complet, meme regle que VoxelMeshBuilder._add_boundary_cube_faces) OU si au
## moins un de ses 6 voisins est vide/au-dessus de la coupe (meme regle que
## VoxelMeshBuilder._is_face_exposed) - evite de dessiner des aretes pour de
## la roche pleine entouree de roche, invisible de toute facon.
func _rebuild_edges() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var has_lines := false
	for pos in grid:
		if pos.y > view_level:
			continue
		if grid[pos] == BlockType.EMPTY:
			continue
		if _is_edge_visible(pos):
			_add_cube_edges(st, pos)
			has_lines = true
	var mesh := ArrayMesh.new()
	if has_lines:
		st.commit(mesh)
		mesh.surface_set_material(0, edge_material)
	edge_mesh_instance.mesh = mesh


func _is_edge_visible(pos: Vector3i) -> bool:
	if pos.y == view_level:
		return true
	for dir in DIRECTIONS:
		var neighbor: Vector3i = pos + dir
		if neighbor.y > view_level:
			return true
		if grid.get(neighbor, BlockType.EMPTY) == BlockType.EMPTY:
			return true
	return false


func _add_cube_edges(st: SurfaceTool, pos: Vector3i) -> void:
	var p := Vector3(pos.x, pos.y, pos.z)
	var corners := [
		p + Vector3(0, 0, 0), p + Vector3(1, 0, 0), p + Vector3(1, 0, 1), p + Vector3(0, 0, 1),
		p + Vector3(0, 1, 0), p + Vector3(1, 1, 0), p + Vector3(1, 1, 1), p + Vector3(0, 1, 1),
	]
	var segments := [
		[0, 1], [1, 2], [2, 3], [3, 0],  # bas
		[4, 5], [5, 6], [6, 7], [7, 4],  # haut
		[0, 4], [1, 5], [2, 6], [3, 7],  # verticales
	]
	for seg in segments:
		st.set_color(EDGE_COLOR)
		st.add_vertex(corners[seg[0]])
		st.set_color(EDGE_COLOR)
		st.add_vertex(corners[seg[1]])


func _change_view_level(delta: int) -> void:
	view_level = clampi(view_level + delta, MIN_VIEW_LEVEL, MAX_VIEW_LEVEL)
	_rebuild_mesh(false)


func _setup_scene() -> void:
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)

	edge_mesh_instance = MeshInstance3D.new()
	add_child(edge_mesh_instance)
	edge_material = StandardMaterial3D.new()
	edge_material.albedo_color = EDGE_COLOR
	edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_material.vertex_color_use_as_albedo = true

	# Cascades : meme materiau EXACT que WaterfallShapes._ready() (jeu reel) -
	# vertex_color_use_as_albedo pour que le degrade baque par
	# _build_quarter_cylinder_mesh (_color_for_height) soit visible, eclairage
	# reel (roughness=1.0/metallic=0.0/metallic_specular=0.0) pour suivre la
	# lumiere du jour comme l'eau, cull_disabled pour la geometrie ouverte du
	# quart de cylindre.
	cascade_material = StandardMaterial3D.new()
	cascade_material.albedo_color = Color.WHITE
	cascade_material.vertex_color_use_as_albedo = true
	cascade_material.vertex_color_is_srgb = true
	cascade_material.roughness = 1.0
	cascade_material.metallic = 0.0
	cascade_material.metallic_specular = 0.0
	cascade_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cascade_mesh_container = Node3D.new()
	add_child(cascade_mesh_container)

	cam = Camera3D.new()
	add_child(cam)
	orbit_target = Vector3(WIDTH / 2.0, 0.0, DEPTH / 2.0)
	cam.current = true
	_update_camera_transform()

	var light := DirectionalLight3D.new()
	add_child(light)
	light.position = Vector3(WIDTH / 2.0, 20.0, DEPTH / 2.0)
	light.rotation_degrees = Vector3(-90, 0, 0)  # verticale, pointe vers le bas (midi)
	light.light_energy = 1.1

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	env_node.environment = env
	add_child(env_node)


## ZQSD (touches PHYSIQUES W/A/S/D, meme technique que CameraRig.gd - marche
## directement sur clavier francais AZERTY, pas de code touche separe). Deplace
## orbit_target dans le plan XZ, relatif au yaw actuel de la camera (pas au
## pitch - "avancer" reste horizontal quel que soit l'angle de vue).
func _process(delta: float) -> void:
	var input_dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_D):
		input_dir += _camera_right()
	if Input.is_physical_key_pressed(KEY_A):  # touche Q sur clavier francais
		input_dir -= _camera_right()
	if Input.is_physical_key_pressed(KEY_W):  # touche Z sur clavier francais
		input_dir += _camera_forward()
	if Input.is_physical_key_pressed(KEY_S):
		input_dir -= _camera_forward()
	if input_dir != Vector3.ZERO:
		orbit_target += input_dir.normalized() * PAN_SPEED * delta
		_update_camera_transform()


func _camera_forward() -> Vector3:
	return Vector3(-sin(orbit_yaw), 0, -cos(orbit_yaw))


func _camera_right() -> Vector3:
	return Vector3(cos(orbit_yaw), 0, -sin(orbit_yaw))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		orbit_yaw -= event.relative.x * ORBIT_SENSITIVITY
		orbit_pitch = clamp(orbit_pitch - event.relative.y * ORBIT_SENSITIVITY, -1.5, -0.05)
		_update_camera_transform()
	elif event is InputEventMouseButton and event.pressed:
		# Meme repartition que CameraRig.gd : Ctrl+molette = zoom, molette
		# seule = navigation entre niveaux de vue (view_level).
		if event.ctrl_pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = clamp(orbit_distance - ZOOM_STEP, MIN_DISTANCE, MAX_DISTANCE)
			_update_camera_transform()
		elif event.ctrl_pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = clamp(orbit_distance + ZOOM_STEP, MIN_DISTANCE, MAX_DISTANCE)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_view_level(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_view_level(-1)


func _update_camera_transform() -> void:
	var offset := Vector3(
		cos(orbit_pitch) * sin(orbit_yaw),
		sin(-orbit_pitch),
		cos(orbit_pitch) * cos(orbit_yaw)
	) * orbit_distance
	cam.position = orbit_target + offset
	cam.look_at(orbit_target, Vector3.UP)
