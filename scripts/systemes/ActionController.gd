extends CanvasLayer
## Sprint 4 : menu d'actions (Miner / Couper) + designation a la souris.
## Sprint 7 : ajoute Mur Bois / Mur Pierre (construction).
## Sprint 9 : icones de couleur sur les boutons.
## Sprint 9bis : refonte du menu (Construire > materiau), selection de
## plusieurs cases de mur par cliquer-glisser, et mur "fantome" semi-
## transparent tant que la construction n'est pas terminee.
## Sprint 11 : plusieurs nains simultanes (groupe "dwarves" au lieu d'un
## %Dwarf unique) ; chaque nain signale la fin de ses propres constructions.
## Sprint 24ter : ajoute le mode CUEILLIR (recolte de fruits/baies sans
## abattre l'arbre/buisson, cible = groupe "cueillette", voir Forest.gd/
## BerryBushes.gd/TaskQueue.gd/Dwarf.gd).
## Sprint 25 : ajoute "Inspecter" - quand aucun mode d'action n'est actif, un
## clic gauche affiche une petite fenetre d'info sur l'objet clique (arbre,
## buisson/plante, terre, pierre, filon, mur), sans creer de tache. Pas un
## mode a part entiere (pas de bouton dedie) : c'est le comportement par
## defaut du clic quand Mode.NONE.
## Sprint 26 : une icone temporaire apparait sur l'objet/la case designe(e)
## pour Miner/Couper/Cueillir, et disparait une fois la tache terminee - meme
## principe que le mur "fantome" de Construire, generalise a toutes les
## taches via le nouveau signal Dwarf.task_finished (voir _spawn_task_marker/
## _on_task_finished).
## Sprint 26bis : l'icone n'est plus un simple carre colore mais une forme
## d'outil reconnaissable (pioche/hache/panier selon le mode), dessinee
## pixel par pixel a l'execution (voir _get_icon_texture et les fonctions
## _draw_*_icon), toujours dans la couleur du bouton du mode correspondant.

const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")

enum Mode { NONE, MINER, COUPER, CONSTRUIRE, CUEILLIR }
var current_mode: int = Mode.NONE
var selected_material: String = ""  # "bois" / "pierre" / "terre" en mode CONSTRUIRE

const GRID_WIDTH := 20
const GRID_DEPTH := 20
# Sprint 24quinquies : corrige - etait reste a 10.0 (hauteur de carte d'avant
# le Sprint 23, qui l'a portee a 30). Comme la camera regarde le sol en angle,
# une mauvaise hauteur de plan decale aussi x/z du point clique, pas seulement
# y - ca ratait systematiquement les cibles rares ("Cueillir"), et decalait
# probablement aussi (de facon moins visible) miner/couper/construire.
const GROUND_LEVEL := 30.0

# Sprint 26bis : taille (en pixels) des icones d'outil dessinees a l'execution
# pour les marqueurs de tache (voir _get_icon_texture)
const ICON_SIZE := 20

@onready var btn_miner: Button = $HBox/MinerButton
@onready var btn_couper: Button = $HBox/CouperButton
@onready var btn_construire: Button = $HBox/ConstruireButton
@onready var btn_cueillir: Button = $HBox/CueillirButton
@onready var material_box: HBoxContainer = $MaterialBox
@onready var btn_bois: Button = $MaterialBox/BoisButton
@onready var btn_pierre: Button = $MaterialBox/PierreButton
@onready var btn_terre: Button = $MaterialBox/TerreButton
@onready var stats_label: Label = $StatsLabel
@onready var info_panel: PanelContainer = $InfoPanel
@onready var info_label: Label = $InfoPanel/VBox/InfoLabel
@onready var info_close_button: Button = $InfoPanel/VBox/CloseButton

@onready var voxel_world: Node3D = %VoxelWorld
@onready var task_queue: Node = %TaskQueue
@onready var camera: Camera3D = %Camera3D
@onready var inventory: Node = %Inventory

# Selection multi-cases par cliquer-glisser (mode CONSTRUIRE uniquement)
var is_dragging: bool = false
var drag_start: Vector2i = Vector2i.ZERO
var drag_end: Vector2i = Vector2i.ZERO
var drag_preview_ghosts: Array = []

# Murs "fantome" (semi-transparents) affiches tant que la construction
# n'est pas terminee (que ce soit un succes ou un echec faute de ressource)
var queued_ghosts: Dictionary = {}     # task_id -> MeshInstance3D
var pending_columns: Dictionary = {}   # Vector2i(x,z) -> true

# Sprint 26 : icones temporaires sur les objets/cases designes pour Miner/
# Couper/Cueillir, retirees des que Dwarf.task_finished signale la fin de
# la tache correspondante (voir _spawn_task_marker/_on_task_finished)
var queued_markers: Dictionary = {}    # task_id -> MeshInstance3D

# Sprint 26bis : cache des icones d'outil deja dessinees ("kind|couleur" ->
# ImageTexture), pour ne pas redessiner pixel par pixel a chaque tache
var _icon_texture_cache: Dictionary = {}


func _ready() -> void:
	btn_miner.pressed.connect(_on_miner_pressed)
	btn_couper.pressed.connect(_on_couper_pressed)
	btn_construire.pressed.connect(_on_construire_pressed)
	btn_cueillir.pressed.connect(_on_cueillir_pressed)
	btn_bois.pressed.connect(_on_material_pressed.bind("bois"))
	btn_pierre.pressed.connect(_on_material_pressed.bind("pierre"))
	btn_terre.pressed.connect(_on_material_pressed.bind("terre"))
	info_close_button.pressed.connect(_hide_info_panel)
	for d in get_tree().get_nodes_in_group("dwarves"):
		d.build_task_finished.connect(_on_build_task_finished)
		d.task_finished.connect(_on_task_finished)
	_setup_icons()
	_update_buttons()
	_update_material_buttons()
	material_box.visible = false
	info_panel.visible = false


## Sprint 9 : petites icones de couleur (formes simples) sur chaque bouton,
## en attendant de vraies illustrations (style BD du brief)
func _setup_icons() -> void:
	btn_miner.icon = _make_square_icon(Color(0.5, 0.5, 0.5), 18)
	btn_couper.icon = _make_square_icon(Color(0.25, 0.55, 0.15), 18)
	btn_construire.icon = _make_square_icon(Color(0.85, 0.65, 0.13), 18)
	btn_cueillir.icon = _make_square_icon(Color(0.85, 0.25, 0.25), 18)
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
	# Sprint 20 : "Bois" reste le total utilisable pour construire, avec le
	# detail par espece entre parentheses (chene/sapin/bouleau) a titre
	# informatif
	var wood_detail := "Chene %d, Sapin %d, Bouleau %d" % [
		inventory.get_count("bois_chene"),
		inventory.get_count("bois_sapin"),
		inventory.get_count("bois_bouleau"),
	]
	stats_label.text = "Bois : %d (%s)    Pierre : %d    Terre : %d    Taches en attente : %d" % [
		inventory.get_count("bois"),
		wood_detail,
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


func _on_cueillir_pressed() -> void:
	current_mode = Mode.NONE if current_mode == Mode.CUEILLIR else Mode.CUEILLIR
	_update_buttons()


func _on_material_pressed(material: String) -> void:
	selected_material = "" if selected_material == material else material
	_update_material_buttons()


func _update_buttons() -> void:
	btn_miner.button_pressed = (current_mode == Mode.MINER)
	btn_couper.button_pressed = (current_mode == Mode.COUPER)
	btn_construire.button_pressed = (current_mode == Mode.CONSTRUIRE)
	btn_cueillir.button_pressed = (current_mode == Mode.CUEILLIR)
	material_box.visible = (current_mode == Mode.CONSTRUIRE)
	if current_mode != Mode.CONSTRUIRE:
		_cancel_drag()
	_hide_info_panel()


func _update_material_buttons() -> void:
	btn_bois.button_pressed = (selected_material == "bois")
	btn_pierre.button_pressed = (selected_material == "pierre")
	btn_terre.button_pressed = (selected_material == "terre")


func _unhandled_input(event: InputEvent) -> void:
	if current_mode == Mode.NONE:
		# Sprint 25 : aucun mode d'action actif -> le clic gauche sert a
		# inspecter l'objet sous la souris au lieu de ne rien faire
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_inspect_click(event.position)
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
	elif current_mode == Mode.CUEILLIR:
		_handle_gather_click(hit)
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


## Sprint 26 : retire l'icone temporaire d'une tache Miner/Couper/Cueillir
## (ou Construire, mais celle-ci n'en cree pas - voir _finalize_drag_selection
## qui n'ajoute rien a queued_markers) une fois qu'elle est terminee. Signal
## generique emis pour TOUTES les taches (voir Dwarf.gd/task_finished), donc
## on verifie juste si un marqueur existe pour cet id avant de le retirer.
func _on_task_finished(task_id: int) -> void:
	if queued_markers.has(task_id):
		var marker = queued_markers[task_id]
		if is_instance_valid(marker):
			marker.queue_free()
		queued_markers.erase(task_id)


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


## Sprint 26bis : petit marqueur en forme d'outil (pioche/hache/panier selon
## "kind"), toujours face a la camera, affiche au-dessus d'un objet/case
## designe pour Miner/Couper/Cueillir tant que la tache n'est pas terminee.
## L'icone est dessinee pixel par pixel a l'execution (voir _get_icon_texture/
## _draw_pickaxe_icon/_draw_axe_icon/_draw_basket_icon), pas une image chargee
## depuis le disque - meme approche que _make_square_icon (icones de boutons),
## pour eviter le bug de blocs blancs deja rencontre avec les textures de
## filons chargees en fichier (voir memoire).
func _spawn_task_marker(pos: Vector3, kind: String, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	mesh_inst.mesh = quad

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _get_icon_texture(kind, color)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED  # toujours face a la camera
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # rendu net, pas flou
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.position = pos

	get_parent().add_child(mesh_inst)
	return mesh_inst


func _get_icon_texture(kind: String, color: Color) -> ImageTexture:
	var key := "%s|%s" % [kind, color]
	if _icon_texture_cache.has(key):
		return _icon_texture_cache[key]
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # fond transparent
	match kind:
		"pioche":
			_draw_pickaxe_icon(img, color)
		"hache":
			_draw_axe_icon(img, color)
		"panier":
			_draw_basket_icon(img, color)
	var tex := ImageTexture.create_from_image(img)
	_icon_texture_cache[key] = tex
	return tex


## Pioche : manche diagonal + tete en "chevron" (deux branches courbes de
## part et d'autre du sommet du manche, evoque le double pic incurve)
func _draw_pickaxe_icon(img: Image, color: Color) -> void:
	var s := float(ICON_SIZE)
	_draw_thick_line(img, Vector2(s * 0.25, s * 0.88), Vector2(s * 0.55, s * 0.32), color)
	_draw_thick_line(img, Vector2(s * 0.55, s * 0.32), Vector2(s * 0.85, s * 0.15), color)
	_draw_thick_line(img, Vector2(s * 0.85, s * 0.15), Vector2(s * 0.95, s * 0.35), color)
	_draw_thick_line(img, Vector2(s * 0.55, s * 0.32), Vector2(s * 0.28, s * 0.12), color)
	_draw_thick_line(img, Vector2(s * 0.28, s * 0.12), Vector2(s * 0.13, s * 0.24), color)


## Hache : manche vertical + lame triangulaire pleine sur le cote
func _draw_axe_icon(img: Image, color: Color) -> void:
	var s := float(ICON_SIZE)
	_draw_thick_line(img, Vector2(s * 0.58, s * 0.90), Vector2(s * 0.58, s * 0.35), color)
	var blade_top := Vector2(s * 0.58, s * 0.10)
	var blade_bottom := Vector2(s * 0.58, s * 0.48)
	var blade_tip := Vector2(s * 0.14, s * 0.26)
	_fill_triangle(img, blade_top, blade_bottom, blade_tip, color)


## Panier : corps trapezoidal (plus large en haut) + anse courbe au-dessus
func _draw_basket_icon(img: Image, color: Color) -> void:
	var s := float(ICON_SIZE)
	var body_top := s * 0.45
	var body_bottom := s * 0.85
	var top_half_width := s * 0.32
	var bottom_half_width := s * 0.18
	var center_x := s * 0.5

	var y := int(body_top)
	while y <= int(body_bottom):
		var t: float = (float(y) - body_top) / (body_bottom - body_top)
		var half_width: float = lerp(top_half_width, bottom_half_width, t)
		var x_start := int(round(center_x - half_width))
		var x_end := int(round(center_x + half_width))
		for x in range(x_start, x_end + 1):
			_set_pixel_safe(img, x, y, color)
		y += 1

	var handle_top := s * 0.12
	var handle_span := s * 0.22
	var steps := 24
	for i in range(steps + 1):
		var t2 := float(i) / float(steps)
		var x2: float = center_x - handle_span + t2 * (handle_span * 2.0)
		var arc: float = sin(t2 * PI)  # 0 aux extremites, 1 au sommet de l'anse
		var y2: float = body_top - (body_top - handle_top) * arc
		_plot_blob(img, Vector2(x2, y2), 1, color)


## Trace un trait epais entre deux points (utilise pour les manches d'outils)
func _draw_thick_line(img: Image, from: Vector2, to: Vector2, color: Color) -> void:
	var dist := from.distance_to(to)
	var steps := int(dist) * 2 + 1
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := from.lerp(to, t)
		_plot_blob(img, p, 1, color)


## Peint un petit disque de pixels autour de "center" (rayon en pixels)
func _plot_blob(img: Image, center: Vector2, radius: int, color: Color) -> void:
	var cx := int(round(center.x))
	var cy := int(round(center.y))
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				_set_pixel_safe(img, cx + dx, cy + dy, color)


## Remplit un triangle plein (utilise pour la lame de la hache)
func _fill_triangle(img: Image, a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	var min_x := int(floor(min(a.x, min(b.x, c.x))))
	var max_x := int(ceil(max(a.x, max(b.x, c.x))))
	var min_y := int(floor(min(a.y, min(b.y, c.y))))
	var max_y := int(ceil(max(a.y, max(b.y, c.y))))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			if _point_in_triangle(p, a, b, c):
				_set_pixel_safe(img, x, y, color)


func _point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := _triangle_sign(p, a, b)
	var d2 := _triangle_sign(p, b, c)
	var d3 := _triangle_sign(p, c, a)
	var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)


func _triangle_sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


## set_pixel securise (ignore silencieusement les coordonnees hors image)
func _set_pixel_safe(img: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or x >= img.get_width() or y < 0 or y >= img.get_height():
		return
	img.set_pixel(x, y, color)


func _handle_mine_click(hit: Vector3) -> void:
	var gx := int(floor(hit.x))
	var gz := int(floor(hit.z))
	if gx < 0 or gx >= GRID_WIDTH or gz < 0 or gz >= GRID_DEPTH:
		return
	var top_y: int = voxel_world.get_top_block_y(gx, gz)
	if top_y < 0:
		return
	var walk_pos := Vector3(gx + 0.5, GROUND_LEVEL, gz + 0.5)
	var task_id: int = task_queue.add_mine_task(walk_pos, gx, top_y, gz)
	var marker_pos := Vector3(gx + 0.5, top_y + 1.4, gz + 0.5)
	queued_markers[task_id] = _spawn_task_marker(marker_pos, "pioche", Color(0.5, 0.5, 0.5))  # meme gris que l'icone du bouton Miner


func _handle_chop_click(hit: Vector3) -> void:
	var closest_tree: Node3D = null
	var closest_dist := 2.0  # rayon de detection autour du clic

	for tree in get_tree().get_nodes_in_group("trees"):
		var d: float = Vector2(tree.global_position.x - hit.x, tree.global_position.z - hit.z).length()
		if d < closest_dist:
			closest_dist = d
			closest_tree = tree

	if closest_tree:
		var task_id: int = task_queue.add_chop_task(closest_tree)
		var marker_pos: Vector3 = closest_tree.global_position + Vector3(0, 1.9, 0)
		queued_markers[task_id] = _spawn_task_marker(marker_pos, "hache", Color(0.25, 0.55, 0.15))


## Sprint 24ter : detection au clic pour "Cueillir" - cible le groupe
## "cueillette" (arbres fruitiers + buissons a baies, voir Forest.gd/
## BerryBushes.gd), independant du groupe "trees" utilise par "Couper"
func _handle_gather_click(hit: Vector3) -> void:
	var closest_target: Node3D = null
	var closest_dist := 2.0  # rayon de detection autour du clic

	for target in get_tree().get_nodes_in_group("cueillette"):
		var d: float = Vector2(target.global_position.x - hit.x, target.global_position.z - hit.z).length()
		if d < closest_dist:
			closest_dist = d
			closest_target = target

	if closest_target:
		var task_id: int = task_queue.add_gather_task(closest_target)
		# Sprint 26 : hauteur du marqueur plus basse pour un buisson/plante
		# (bas, pas dans le groupe "trees") que pour un arbre fruitier
		var height_offset := 1.2 if closest_target.is_in_group("trees") else 0.6
		var marker_pos: Vector3 = closest_target.global_position + Vector3(0, height_offset, 0)
		queued_markers[task_id] = _spawn_task_marker(marker_pos, "panier", Color(0.85, 0.25, 0.25))


## Sprint 25 : point d'entree de l'inspection (clic gauche quand aucun mode
## d'action n'est actif). Cherche d'abord un arbre/buisson/plante proche du
## clic (groupes "cueillette" puis "trees"), sinon decrit le bloc du sol a
## cet endroit (terre/pierre/filon/mur).
func _handle_inspect_click(screen_pos: Vector2) -> void:
	var hit = _raycast_ground(screen_pos)
	if hit == null:
		_hide_info_panel()
		return

	var label := _inspect_label_for(hit)
	if label == "":
		_hide_info_panel()
	else:
		_show_info_panel(label, screen_pos)


func _inspect_label_for(hit: Vector3) -> String:
	var closest_target: Node3D = null
	var closest_dist := 2.0  # meme rayon de detection que Couper/Cueillir

	for target in get_tree().get_nodes_in_group("cueillette"):
		var d: float = Vector2(target.global_position.x - hit.x, target.global_position.z - hit.z).length()
		if d < closest_dist:
			closest_dist = d
			closest_target = target
	if closest_target == null:
		for target in get_tree().get_nodes_in_group("trees"):
			var d: float = Vector2(target.global_position.x - hit.x, target.global_position.z - hit.z).length()
			if d < closest_dist:
				closest_dist = d
				closest_target = target

	if closest_target:
		return _describe_gatherable(closest_target)

	var gx := int(floor(hit.x))
	var gz := int(floor(hit.z))
	if gx < 0 or gx >= GRID_WIDTH or gz < 0 or gz >= GRID_DEPTH:
		return ""
	return _describe_block(gx, gz)


## Nom + etat de recolte d'un arbre/buisson/plante, via les metadonnees
## deja posees par Forest.gd/BerryBushes.gd ("species_name", "fruits_left")
func _describe_gatherable(node: Node) -> String:
	var species_name: String = node.get_meta("species_name", "?")
	if not node.is_in_group("cueillette"):
		return species_name
	var fruits_left: int = node.get_meta("fruits_left", -1)
	if fruits_left < 0:
		return species_name
	if fruits_left == 0:
		return "%s (vide)" % species_name
	return "%s - %d fruit(s) restant(s)" % [species_name, fruits_left]


## Nom d'un bloc de sol (terre/pierre/mur), via VoxelWorld.get_block_info().
## Si le bloc de pierre contient un filon, affiche son nom (VeinMaterials).
func _describe_block(gx: int, gz: int) -> String:
	var info: Dictionary = voxel_world.get_block_info(gx, gz)
	match info["type"]:
		"terre":
			return "Terre"
		"pierre":
			var materiau: String = info["materiau"]
			if materiau != "":
				var mat: Dictionary = VeinMaterials.get_type(materiau)
				return "Filon de %s" % mat.get("nom", materiau)
			return "Pierre"
		"mur_bois":
			return "Mur en bois"
		"mur_pierre":
			return "Mur en pierre"
		_:
			return ""


func _show_info_panel(text: String, screen_pos: Vector2) -> void:
	info_label.text = text
	info_panel.visible = true
	# Repositionne pres du clic, sans deborder de l'ecran (la taille reelle du
	# panel n'est connue qu'apres un frame, on utilise donc une taille fixe
	# approximative pour le calcul plutot que info_panel.size, encore a 0 ici)
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_width := 220.0
	var panel_height := 70.0
	var pos := screen_pos + Vector2(16, -16)
	pos.x = clampf(pos.x, 0.0, viewport_size.x - panel_width)
	pos.y = clampf(pos.y, 0.0, viewport_size.y - panel_height)
	info_panel.position = pos


func _hide_info_panel() -> void:
	info_panel.visible = false
