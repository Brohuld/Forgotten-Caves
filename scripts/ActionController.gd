extends CanvasLayer
## Sprint 4 : menu d'actions (Miner / Couper) + designation a la souris.
## Sprint 7 : ajoute Mur Bois / Mur Pierre (construction).
## Sprint 9 : icones de couleur sur les boutons.
## Sprint 9bis : refonte du menu (Construire > materiau), selection de
## plusieurs cases de mur par cliquer-glisser, et mur "fantome" semi-
## transparent tant que la construction n'est pas terminee.

enum Mode { NONE, MINER, COUPER, CONSTRUIRE }
var current_mode: int = Mode.NONE
var selected_material: String = ""  # "bois" / "pierre" / "terre" en mode CONSTRUIRE

const GRID_WIDTH := 20
const GRID_DEPTH := 20
const GROUND_LEVEL := 10.0

@onready var btn_miner: Button = $HBox/MinerButton
@onready var btn_couper: Button = $HBox/CouperButton
@onready var btn_construire: Button = $HBox/ConstruireButton
@onready var material_box: HBoxContainer = $MaterialBox
@onready var btn_bois: Button = $MaterialBox/BoisButton
@onready var btn_pierre: Button = $MaterialBox/PierreButton
@onready var btn_terre: Button = $MaterialBox/TerreButton
@onready var stats_label: Label = $StatsLabel

@onready var voxel_world: Node3D = %VoxelWorld
@onready var task_queue: Node = %TaskQueue
@onready var camera: Camera3D = %Camera3D
@onready var inventory: Node = %Inventory
@onready var dwarf: Node3D = %Dwarf

# Selection multi-cases par cliquer-glisser (mode CONSTRUIRE uniquement)
var is_dragging: bool = false
var drag_start: Vector2i = Vector2i.ZERO
var drag_end: Vector2i = Vector2i.ZERO
var drag_preview_ghosts: Array = []

# Murs "fantome" (semi-transparents) affiches tant que la construction
# n'est pas terminee (que ce soit un succes ou un echec faute de ressource)
var queued_ghosts: Dictionary = {}     # task_id -> MeshInstance3D
var pending_columns: Dictionary = {}   # Vector2i(x,z) -> true


func _ready() -> void:
	btn_miner.pressed.connect(_on_miner_pressed)
	btn_couper.pressed.connect(_on_couper_pressed)
	btn_construire.pressed.connect(_on_construire_pressed)
	btn_bois.pressed.connect(_on_material_pressed.bind("bois"))
	btn_pierre.pressed.connect(_on_material_pressed.bind("pierre"))
	btn_terre.pressed.connect(_on_material_pressed.bind("terre"))
	dwarf.build_task_finished.connect(_on_build_task_finished)
	_setup_icons()
	_update_buttons()
	_update_material_buttons()
	material_box.visible = false


## Sprint 9 : petites icones de couleur (formes simples) sur chaque bouton,
## en attendant de vraies illustrations (style BD du brief)
func _setup_icons() -> void:
	btn_miner.icon = _make_square_icon(Color(0.5, 0.5, 0.5), 18)
	btn_couper.icon = _make_square_icon(Color(0.25, 0.55, 0.15), 18)
	btn_construire.icon = _make_square_icon(Color(0.85, 0.65, 0.13), 18)
	btn_bois.icon = _make_square_icon(_material_color("bois"), 18)
	btn_pierre.icon = _make_square_icon(_material_color("pierre"), 18)
	btn_terre.icon = _make_square_icon(_material_color("terre"), 18)


func _make_square_icon(color: Color, size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _material_color(material: String) -> Color:
	match material:
		"bois":
			return Color(0.55, 0.38, 0.20)
		"pierre":
			return Color(0.60, 0.62, 0.66)
		"terre":
			return Color(0.35, 0.25, 0.15)
		_:
			return Color(1, 1, 1)


func _process(_delta: float) -> void:
	stats_label.text = "Bois : %d    Pierre : %d    Terre : %d    Taches en attente : %d" % [
		inventory.get_count("bois"),
		inventory.get_count("pierre"),
		inventory.get_count("terre"),
		task_queue.task_count(),
	]


func _on_miner_pressed() -> void:
	current_mode = Mode.NONE if current_mode == Mode.MINER else Mode.MINER
	_update_buttons()


func _on_couper_pressed() -> void:
	current_mode = Mode.NONE if current_mode == Mode.COUPER else Mode.COUPER
	_update_buttons()


func _on_construire_pressed() -> void:
	current_mode = Mode.NONE if current_mode == Mode.CONSTRUIRE else Mode.CONSTRUIRE
	_update_buttons()


func _on_material_pressed(material: String) -> void:
	selected_material = "" if selected_material == material else material
	_update_material_buttons()


func _update_buttons() -> void:
	btn_miner.button_pressed = (current_mode == Mode.MINER)
	btn_couper.button_pressed = (current_mode == Mode.COUPER)
	btn_construire.button_pressed = (current_mode == Mode.CONSTRUIRE)
	material_box.visible = (current_mode == Mode.CONSTRUIRE)
	if current_mode != Mode.CONSTRUIRE:
		_cancel_drag()


func _update_material_buttons() -> void:
	btn_bois.button_pressed = (selected_material == "bois")
	btn_pierre.button_pressed = (selected_material == "pierre")
	btn_terre.button_pressed = (selected_material == "terre")


func _unhandled_input(event: InputEvent) -> void:
	if current_mode == Mode.NONE:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_press(event.position)
		else:
			_on_left_release()
	elif event is InputEventMouseMotion and is_dragging:
		_update_drag(event.position)


func _on_left_press(screen_pos: Vector2) -> void:
	var hit = _raycast_ground(screen_pos)
	if hit == null:
		return

	if current_mode == Mode.MINER:
		_handle_mine_click(hit)
	elif current_mode == Mode.COUPER:
		_handle_chop_click(hit)
	elif current_mode == Mode.CONSTRUIRE:
		if selected_material == "":
			return
		var cell := _cell_from_hit(hit)
		drag_start = cell
		drag_end = cell
		is_dragging = true
		_update_drag_preview()


func _on_left_release() -> void:
	if not is_dragging:
		return
	is_dragging = false
	_finalize_drag_selection()
	_clear_drag_preview()


func _update_drag(screen_pos: Vector2) -> void:
	var hit = _raycast_ground(screen_pos)
	if hit == null:
		return
	drag_end = _cell_from_hit(hit)
	_update_drag_preview()


func _cancel_drag() -> void:
	is_dragging = false
	_clear_drag_preview()


## Intersection du rayon camera->souris avec le plan horizontal du sol
func _raycast_ground(screen_pos: Vector2):
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	if absf(ray_dir.y) < 0.0001:
		return null
	var t := (GROUND_LEVEL - ray_origin.y) / ray_dir.y
	if t < 0.0:
		return null
	return ray_origin + ray_dir * t


func _cell_from_hit(hit: Vector3) -> Vector2i:
	return Vector2i(int(floor(hit.x)), int(floor(hit.z)))


## Toutes les cases valides (dans la carte, constructibles, pas deja en
## attente de construction) du rectangle defini par deux coins
func _valid_rect_cells(a: Vector2i, b: Vector2i) -> Array:
	var min_x := mini(a.x, b.x)
	var max_x := maxi(a.x, b.x)
	var min_z := mini(a.y, b.y)
	var max_z := maxi(a.y, b.y)
	var cells: Array = []
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			if x < 0 or x >= GRID_WIDTH or z < 0 or z >= GRID_DEPTH:
				continue
			if not voxel_world.can_build(x, z):
				continue
			if pending_columns.has(Vector2i(x, z)):
				continue
			cells.append(Vector2i(x, z))
	return cells


func _update_drag_preview() -> void:
	_clear_drag_preview()
	for cell in _valid_rect_cells(drag_start, drag_end):
		var y: int = voxel_world.get_top_block_y(cell.x, cell.y) + 1
		var ghost := _spawn_ghost(cell.x, y, cell.y, selected_material, 0.35)
		drag_preview_ghosts.append(ghost)


func _clear_drag_preview() -> void:
	for ghost in drag_preview_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	drag_preview_ghosts.clear()


## Cliquer-glisser termine : on file une tache de construction par case
## valide, chacune avec son propre mur fantome persistant jusqu'a ce que
## le nain ait fini de construire (succes ou echec faute de ressource)
func _finalize_drag_selection() -> void:
	for cell in _valid_rect_cells(drag_start, drag_end):
		var walk_pos := Vector3(cell.x + 0.5, GROUND_LEVEL, cell.y + 0.5)
		var task_id: int = task_queue.add_build_task(walk_pos, cell.x, cell.y, selected_material)
		pending_columns[cell] = true
		var y: int = voxel_world.get_top_block_y(cell.x, cell.y) + 1
		queued_ghosts[task_id] = _spawn_ghost(cell.x, y, cell.y, selected_material, 0.5)


## Retire le mur fantome correspondant une fois la tache de construction
## terminee (que le mur ait vraiment ete pose ou non)
func _on_build_task_finished(task_id: int, bx: int, bz: int) -> void:
	pending_columns.erase(Vector2i(bx, bz))
	if queued_ghosts.has(task_id):
		var ghost = queued_ghosts[task_id]
		if is_instance_valid(ghost):
			ghost.queue_free()
		queued_ghosts.erase(task_id)


func _spawn_ghost(gx: int, gy: int, gz: int, material: String, alpha: float) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.94, 0.94, 0.94)  # legerement plus petit que le bloc reel pour bien le distinguer
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	var color := _material_color(material)
	color.a = alpha
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.position = Vector3(gx + 0.5, gy + 0.5, gz + 0.5)

	get_parent().add_child(mesh_inst)
	return mesh_inst


func _handle_mine_click(hit: Vector3) -> void:
	var gx := int(floor(hit.x))
	var gz := int(floor(hit.z))
	if gx < 0 or gx >= GRID_WIDTH or gz < 0 or gz >= GRID_DEPTH:
		return
	var top_y: int = voxel_world.get_top_block_y(gx, gz)
	if top_y < 0:
		return
	var walk_pos := Vector3(gx + 0.5, GROUND_LEVEL, gz + 0.5)
	task_queue.add_mine_task(walk_pos, gx, top_y, gz)


func _handle_chop_click(hit: Vector3) -> void:
	var closest_tree: Node3D = null
	var closest_dist := 2.0  # rayon de detection autour du clic

	for tree in get_tree().get_nodes_in_group("trees"):
		var d: float = Vector2(tree.global_position.x - hit.x, tree.global_position.z - hit.z).length()
		if d < closest_dist:
			closest_dist = d
			closest_tree = tree

	if closest_tree:
		task_queue.add_chop_task(closest_tree)
