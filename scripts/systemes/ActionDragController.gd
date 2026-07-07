extends RefCounted
## Coeur du systeme de glisser-depose / selection / creation de taches
## (Miner/Construire/Puiser/Couper/Cueillir/Detruire/Interdire/selection de
## nains).
##
## Fonctions statiques : "controller" recoit le ActionController via
## parametre au lieu d'un "self" implicite (meme motif que Model3DUtils.gd/
## DwarfWeaponBuilder.gd pour les nains). L'etat partage (is_dragging,
## drag_start/end, queued_ghosts/markers, pending_columns, _select_*) reste
## physiquement stocke sur le ActionController (proprietes @onready/var
## normales) - ces fonctions le lisent/l'ecrivent via controller.get()/
## controller.set() (acces dynamique Godot, necessaire car "controller" est
## type generiquement CanvasLayer, pas ActionController, pour eviter un
## preload circulaire). Pour les Dictionary/Array (queued_ghosts,
## queued_markers, pending_columns, drag_preview_ghosts), un
## controller.get(...) suffit et peut etre mute directement (ce sont des
## types par reference en GDScript - pas besoin de set() pour une simple
## mutation en place).
## Enum Mode et quelques constantes (GROUND_LEVEL, SELECT_DRAG_THRESHOLD,
## ICON_SIZE/ICON_GLYPH_SIZE) sont dupliques ci-dessous car les "const" ne
## sont pas visibles via get() (meme raison que MATERIAL_COLORS dans
## DwarfWeaponBuilder.gd) - a garder synchronises si les valeurs d'origine
## changent dans ActionController.gd. Pour GRID_WIDTH/GRID_DEPTH, plutot que
## d'ajouter une 3e copie, ce fichier lit directement VoxelWorld.WIDTH/DEPTH
## (la source faisant deja autorite).

const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")

## Garder synchronise avec ActionController.Mode, voir doc en tete de
## fichier.
enum Mode { NONE, MINER, COUPER, CONSTRUIRE, CUEILLIR, PUISER, ANNULER, DETRUIRE, INTERDIRE }

const GROUND_LEVEL := 50.0
const SELECT_DRAG_THRESHOLD := 6.0
const ICON_SIZE := 40
const ICON_GLYPH_SIZE := 24
## Rayon de detection (pixels ecran) autour du clic pour trouver le marqueur/
## fantome de tache le plus proche (mode ANNULER) - meme valeur que
## DWARF_CLICK_RADIUS_PX dans ActionInspector.gd (duplique ici pour la meme
## raison que ICON_SIZE ci-dessus).
const ANNULER_CLICK_RADIUS_PX := 28.0
## Rayon de recherche (unites monde, comme closest_in_group utilise deja par
## Couper/Cueillir) pour trouver un arbre/element de cueillette proche du
## clic avant de retomber sur le comportement "case de terrain" (mode
## INTERDIRE).
const INTERDIRE_ENTITY_RADIUS := 2.0


## Miner utilise le meme rectangle "monde" que Construire (un simple clic =
## rectangle de 1 case, un glisser = plusieurs).
static func on_left_press(controller: CanvasLayer, screen_pos: Vector2) -> void:
	var hit = raycast_ground(controller, screen_pos)
	if hit == null:
		return

	var current_mode: int = controller.get("current_mode")
	if current_mode == Mode.MINER:
		var cell := cell_from_hit(hit)
		controller.set("drag_start", cell)
		controller.set("drag_end", cell)
		controller.set("is_dragging", true)
		update_mine_drag_preview(controller)
	elif current_mode == Mode.PUISER:
		var cell := cell_from_hit(hit)
		controller.set("drag_start", cell)
		controller.set("drag_end", cell)
		controller.set("is_dragging", true)
		update_puiser_drag_preview(controller)
	elif current_mode == Mode.CONSTRUIRE:
		if controller.get("selected_material") == "":
			return
		var cell := cell_from_hit(hit)
		controller.set("drag_start", cell)
		controller.set("drag_end", cell)
		controller.set("is_dragging", true)
		update_drag_preview(controller)
	elif current_mode == Mode.DETRUIRE:
		var cell := cell_from_hit(hit)
		controller.set("drag_start", cell)
		controller.set("drag_end", cell)
		controller.set("is_dragging", true)
		update_destroy_drag_preview(controller)
	elif current_mode == Mode.INTERDIRE:
		# Essaie d'abord un arbre/element de cueillette proche du clic
		# (toggle IMMEDIAT, pas de glisser - une entite se cible en un seul
		# clic, meme convention que Couper/Cueillir). Si rien trouve,
		# retombe sur le comportement "case de terrain" (rectangle, comme
		# Miner) - is_dragging reste donc a false dans le cas "entite", ce
		# qui fait que on_left_release/update_drag ne feront rien de plus
		# pour ce clic (voir leur garde "if not is_dragging: return").
		var action_validator = controller.get("action_validator")
		var target: Node3D = action_validator.closest_in_group(hit, "trees", controller.get_tree(), INTERDIRE_ENTITY_RADIUS)
		if target == null:
			target = action_validator.closest_in_group(hit, "cueillette", controller.get_tree(), INTERDIRE_ENTITY_RADIUS)
		if target != null:
			toggle_interdit_entity(target)
			return
		var cell := cell_from_hit(hit)
		controller.set("drag_start", cell)
		controller.set("drag_end", cell)
		controller.set("is_dragging", true)
		update_interdire_drag_preview(controller)


## Miner et Construire se desactivent tous les deux automatiquement (retour
## a Mode.NONE) une fois la selection finalisee - Detruire fait de meme
## (branche dediee, sinon tomberait a tort dans le "_" par defaut qui
## execute la logique de CONSTRUIRE). "_reset_mode_selection" est utilise
## plutot qu'un simple "current_mode = Mode.NONE" : depuis l'adoption de
## ButtonGroup pour les boutons de mode, forcer directement la variable
## current_mode ne suffit plus a depresser visuellement le bouton (Godot/
## ButtonGroup gerent desormais eux-memes l'etat des boutons, plus de boucle
## de mise a jour systematique cote ActionController) - voir sa doc.
static func on_left_release(controller: CanvasLayer) -> void:
	if not controller.get("is_dragging"):
		return
	controller.set("is_dragging", false)
	var current_mode: int = controller.get("current_mode")
	match current_mode:
		Mode.MINER:
			finalize_mine_selection(controller)
		Mode.PUISER:
			finalize_puiser_selection(controller)
		Mode.DETRUIRE:
			finalize_destroy_selection(controller)
		Mode.INTERDIRE:
			finalize_interdire_selection(controller)
		_:
			finalize_drag_selection(controller)
	clear_drag_preview(controller)
	# Contrairement aux autres modes, INTERDIRE reste actif apres chaque
	# action (clic sur une entite OU rectangle de cases) - c'est un outil
	# qu'on utilise typiquement plusieurs fois de suite (marquer plusieurs
	# arbres/zones) avant de vouloir en sortir, pas une tache "one-shot"
	# comme Miner/Couper.
	if current_mode != Mode.INTERDIRE:
		controller.call("_reset_mode_selection")


static func update_drag(controller: CanvasLayer, screen_pos: Vector2) -> void:
	var hit = raycast_ground(controller, screen_pos)
	if hit == null:
		return
	controller.set("drag_end", cell_from_hit(hit))
	var current_mode: int = controller.get("current_mode")
	match current_mode:
		Mode.MINER:
			update_mine_drag_preview(controller)
		Mode.PUISER:
			update_puiser_drag_preview(controller)
		Mode.DETRUIRE:
			update_destroy_drag_preview(controller)
		Mode.INTERDIRE:
			update_interdire_drag_preview(controller)
		_:
			update_drag_preview(controller)


static func cancel_drag(controller: CanvasLayer) -> void:
	controller.set("is_dragging", false)
	clear_drag_preview(controller)


## Appui du clic gauche en Mode.NONE - on ne sait pas encore si ce sera un
## simple clic (Inspecter) ou un glisser (selection de nains), la decision
## est prise au relachement ou des que le glisser depasse le seuil.
static func on_select_press(controller: CanvasLayer, screen_pos: Vector2) -> void:
	controller.set("_select_press_pos", screen_pos)
	controller.set("_select_dragging_active", false)


## Appelee a chaque mouvement de souris tant que le bouton gauche est enfonce
## en Mode.NONE. Bascule en mode "glisser" des que la distance au point de
## depart depasse le seuil, et affiche/redimensionne le rectangle a l'ecran.
static func update_select_drag(controller: CanvasLayer, screen_pos: Vector2) -> void:
	var select_box: Panel = controller.get("_select_box")
	# press_pos lue une seule fois ici (au lieu d'une 2e fois dans le bloc
	# "if" ci-dessous, meme valeur a chaque fois puisque _select_press_pos ne
	# change pas entre les deux lectures) - evite l'avertissement Godot sur
	# une redeclaration ambigue du meme nom dans un bloc enfant puis le bloc
	# parent.
	var press_pos: Vector2 = controller.get("_select_press_pos")
	if not controller.get("_select_dragging_active"):
		if press_pos.distance_to(screen_pos) < SELECT_DRAG_THRESHOLD:
			return
		controller.set("_select_dragging_active", true)
		select_box.visible = true
	var top_left := Vector2(minf(press_pos.x, screen_pos.x), minf(press_pos.y, screen_pos.y))
	var size := (press_pos - screen_pos).abs()
	select_box.position = top_left
	select_box.size = size


## Relachement du clic gauche en Mode.NONE : soit on termine un vrai glisser
## (selection de nains/arbres/buissons dans le rectangle), soit c'etait un
## simple clic (Inspecter/Couper/Cueillir sur une seule cible).
static func on_select_release(controller: CanvasLayer, screen_pos: Vector2) -> void:
	var current_mode: int = controller.get("current_mode")
	var press_pos: Vector2 = controller.get("_select_press_pos")
	if controller.get("_select_dragging_active"):
		match current_mode:
			Mode.COUPER:
				finalize_chop_selection(controller, press_pos, screen_pos)
			Mode.CUEILLIR:
				finalize_gather_selection(controller, press_pos, screen_pos)
			_:
				finalize_box_selection(controller, press_pos, screen_pos)
		controller.set("_select_dragging_active", false)
		var select_box: Panel = controller.get("_select_box")
		select_box.visible = false
	elif current_mode == Mode.COUPER:
		var hit = raycast_ground(controller, press_pos)
		if hit != null:
			handle_chop_click(controller, hit)
	elif current_mode == Mode.CUEILLIR:
		var hit = raycast_ground(controller, press_pos)
		if hit != null:
			handle_gather_click(controller, hit)
	else:
		controller.call("_handle_inspect_click", press_pos)

	if current_mode == Mode.COUPER or current_mode == Mode.CUEILLIR:
		# Voir doc de on_left_release ci-dessus.
		controller.call("_reset_mode_selection")


## Trouve tous les nains dont la position ecran (projetee via la camera
## active) tombe dans le rectangle glisse, et transmet la selection a
## CharacterSheetUI. Ctrl/Maj enfonce au relachement = ajoute a la selection
## existante au lieu de la remplacer.
static func finalize_box_selection(controller: CanvasLayer, a: Vector2, b: Vector2) -> void:
	var camera: Camera3D = controller.get("camera")
	var top_left := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var bottom_right := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var found: Array = []
	for dwarf in controller.get_tree().get_nodes_in_group("dwarves"):
		var screen_pos: Vector2 = camera.unproject_position(dwarf.global_position)
		if screen_pos.x >= top_left.x and screen_pos.x <= bottom_right.x \
				and screen_pos.y >= top_left.y and screen_pos.y <= bottom_right.y:
			found.append(dwarf)
	var additive: bool = Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)
	var character_sheet_ui: CanvasLayer = controller.get("character_sheet_ui")
	character_sheet_ui.set_map_selection(found, additive)


## Tous les membres de "group" (ex: "trees"/"cueillette") dont la position
## ecran tombe dans le rectangle glisse - meme principe que
## finalize_box_selection (nains), generalise a un groupe quelconque.
static func targets_in_screen_rect(controller: CanvasLayer, a: Vector2, b: Vector2, group: String) -> Array:
	var camera: Camera3D = controller.get("camera")
	var top_left := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var bottom_right := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var found: Array = []
	for target in controller.get_tree().get_nodes_in_group(group):
		var screen_pos: Vector2 = camera.unproject_position(target.global_position)
		if screen_pos.x >= top_left.x and screen_pos.x <= bottom_right.x \
				and screen_pos.y >= top_left.y and screen_pos.y <= bottom_right.y:
			found.append(target)
	return found


## Version "plusieurs a la fois" de handle_chop_click. Les cibles marquees
## "interdites" (voir toggle_interdit_entity) sont exclues - meme convention
## que "pas de cible trouvee", aucune tache creee pour elles.
static func finalize_chop_selection(controller: CanvasLayer, a: Vector2, b: Vector2) -> void:
	var task_queue: Node = controller.get("task_queue")
	var queued_markers: Dictionary = controller.get("queued_markers")
	for target in targets_in_screen_rect(controller, a, b, "trees"):
		if target.get_meta("interdit", false):
			continue
		var task_id: int = task_queue.add_chop_task(target)
		var marker_pos: Vector3 = target.global_position + Vector3(0, marker_height_for(target), 0)
		queued_markers[task_id] = spawn_task_marker(controller, marker_pos, "hache", Color(0.25, 0.55, 0.15))


## Version "plusieurs a la fois" de handle_gather_click. Meme exclusion que
## finalize_chop_selection ci-dessus.
static func finalize_gather_selection(controller: CanvasLayer, a: Vector2, b: Vector2) -> void:
	var task_queue: Node = controller.get("task_queue")
	var queued_markers: Dictionary = controller.get("queued_markers")
	for target in targets_in_screen_rect(controller, a, b, "cueillette"):
		if target.get_meta("interdit", false):
			continue
		var marker_pos: Vector3 = target.global_position + Vector3(0, marker_height_for(target), 0)
		var task_id: int = task_queue.add_gather_task(target)
		queued_markers[task_id] = spawn_task_marker(controller, marker_pos, "panier", Color(0.85, 0.25, 0.25))


## Intersection du rayon camera->souris avec le sol. Plusieurs passes pour
## suivre le relief : la premiere passe suppose un plan plat a GROUND_LEVEL,
## puis chaque passe suivante recalcule l'intersection au niveau REEL du
## terrain a cet endroit (get_top_block_y) - converge en quelques
## iterations tant que le relief local n'est pas trop abrupt.
static func raycast_ground(controller: CanvasLayer, screen_pos: Vector2):
	var camera: Camera3D = controller.get("camera")
	var voxel_world: Node3D = controller.get("voxel_world")
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	if absf(ray_dir.y) < 0.0001:
		return null
	var plane_y: float = GROUND_LEVEL
	var hit: Vector3 = Vector3.ZERO
	for i in range(4):
		var t := (plane_y - ray_origin.y) / ray_dir.y
		if t < 0.0:
			return null
		hit = ray_origin + ray_dir * t
		var top_y: int = voxel_world.get_top_block_y(int(floor(hit.x)), int(floor(hit.z)))
		if top_y < 0:
			break
		var real_y: float = float(top_y) + 1.0
		if absf(real_y - plane_y) < 0.01:
			break
		plane_y = real_y
	return hit


static func cell_from_hit(hit: Vector3) -> Vector2i:
	return Vector2i(int(floor(hit.x)), int(floor(hit.z)))


## Toutes les cases valides (dans la carte, constructibles, pas deja en
## attente) du rectangle defini par deux coins - delegue a ActionValidator.gd.
static func valid_rect_cells(controller: CanvasLayer, a: Vector2i, b: Vector2i) -> Array:
	var action_validator = controller.get("action_validator")
	var voxel_world: Node3D = controller.get("voxel_world")
	var pending_columns: Dictionary = controller.get("pending_columns")
	return action_validator.valid_rect_cells(a, b, VoxelWorldScript.WIDTH, VoxelWorldScript.DEPTH, voxel_world, pending_columns)


static func update_drag_preview(controller: CanvasLayer) -> void:
	clear_drag_preview(controller)
	var voxel_world: Node3D = controller.get("voxel_world")
	var selected_material: String = controller.get("selected_material")
	var drag_start: Vector2i = controller.get("drag_start")
	var drag_end: Vector2i = controller.get("drag_end")
	var drag_preview_ghosts: Array = controller.get("drag_preview_ghosts")
	for cell in valid_rect_cells(controller, drag_start, drag_end):
		var y: int = voxel_world.get_top_block_y(cell.x, cell.y) + 1
		var ghost := spawn_ghost(controller, cell.x, y, cell.y, selected_material, 0.35)
		drag_preview_ghosts.append(ghost)


## Toutes les cases valides (dans la carte, avec quelque chose a miner) du
## rectangle - delegue a ActionValidator.gd.
static func valid_mine_rect_cells(controller: CanvasLayer, a: Vector2i, b: Vector2i) -> Array:
	var action_validator = controller.get("action_validator")
	var voxel_world: Node3D = controller.get("voxel_world")
	return action_validator.valid_mine_rect_cells(a, b, VoxelWorldScript.WIDTH, VoxelWorldScript.DEPTH, voxel_world)


static func update_mine_drag_preview(controller: CanvasLayer) -> void:
	clear_drag_preview(controller)
	var voxel_world: Node3D = controller.get("voxel_world")
	var drag_start: Vector2i = controller.get("drag_start")
	var drag_end: Vector2i = controller.get("drag_end")
	var drag_preview_ghosts: Array = controller.get("drag_preview_ghosts")
	for cell in valid_mine_rect_cells(controller, drag_start, drag_end):
		var y: int = voxel_world.get_top_block_y(cell.x, cell.y)
		var ghost := spawn_ghost(controller, cell.x, y, cell.y, "gris_minage", 0.35)
		drag_preview_ghosts.append(ghost)


## Version "plusieurs a la fois" du minage - une tache par case valide,
## chacune avec son propre marqueur.
static func finalize_mine_selection(controller: CanvasLayer) -> void:
	var voxel_world: Node3D = controller.get("voxel_world")
	var task_queue: Node = controller.get("task_queue")
	var queued_markers: Dictionary = controller.get("queued_markers")
	var drag_start: Vector2i = controller.get("drag_start")
	var drag_end: Vector2i = controller.get("drag_end")
	for cell in valid_mine_rect_cells(controller, drag_start, drag_end):
		var top_y: int = voxel_world.get_top_block_y(cell.x, cell.y)
		var walk_pos := Vector3(cell.x + 0.5, GROUND_LEVEL, cell.y + 0.5)
		var task_id: int = task_queue.add_mine_task(walk_pos, cell.x, top_y, cell.y)
		var marker_pos := Vector3(cell.x + 0.5, top_y + 1.4, cell.y + 0.5)
		queued_markers[task_id] = spawn_task_marker(controller, marker_pos, "pioche", Color(0.5, 0.5, 0.5))


## Toutes les cases valides (sommet = mur_bois/mur_pierre) du rectangle -
## delegue a ActionValidator.gd (mode Detruire).
static func valid_destroy_rect_cells(controller: CanvasLayer, a: Vector2i, b: Vector2i) -> Array:
	var action_validator = controller.get("action_validator")
	var voxel_world: Node3D = controller.get("voxel_world")
	return action_validator.valid_destroy_rect_cells(a, b, VoxelWorldScript.WIDTH, VoxelWorldScript.DEPTH, voxel_world)


static func update_destroy_drag_preview(controller: CanvasLayer) -> void:
	clear_drag_preview(controller)
	var voxel_world: Node3D = controller.get("voxel_world")
	var drag_start: Vector2i = controller.get("drag_start")
	var drag_end: Vector2i = controller.get("drag_end")
	var drag_preview_ghosts: Array = controller.get("drag_preview_ghosts")
	for cell in valid_destroy_rect_cells(controller, drag_start, drag_end):
		var y: int = voxel_world.get_top_block_y(cell.x, cell.y)
		var ghost := spawn_ghost(controller, cell.x, y, cell.y, "detruire", 0.5)
		drag_preview_ghosts.append(ghost)


## Une tache de demolition par mur valide, chacune avec son propre marqueur
## (glyphe "pioche" reutilise, teinte de destruction - voir _material_color).
static func finalize_destroy_selection(controller: CanvasLayer) -> void:
	var voxel_world: Node3D = controller.get("voxel_world")
	var task_queue: Node = controller.get("task_queue")
	var queued_markers: Dictionary = controller.get("queued_markers")
	var drag_start: Vector2i = controller.get("drag_start")
	var drag_end: Vector2i = controller.get("drag_end")
	var destroy_color = controller.call("_material_color", "detruire")
	for cell in valid_destroy_rect_cells(controller, drag_start, drag_end):
		var top_y: int = voxel_world.get_top_block_y(cell.x, cell.y)
		var walk_pos := Vector3(cell.x + 0.5, GROUND_LEVEL, cell.y + 0.5)
		var task_id: int = task_queue.add_destroy_task(walk_pos, cell.x, top_y, cell.y)
		var marker_pos := Vector3(cell.x + 0.5, top_y + 1.4, cell.y + 0.5)
		queued_markers[task_id] = spawn_task_marker(controller, marker_pos, "pioche", destroy_color)


## Univers de cases que le rectangle Interdire peut cibler - delegue a
## ActionValidator.valid_interdire_rect_cells (meme filtre "quelque chose a
## miner, hors eau" que Miner, mais SANS exclure les cases deja interdites).
static func valid_interdire_rect_cells(controller: CanvasLayer, a: Vector2i, b: Vector2i) -> Array:
	var action_validator = controller.get("action_validator")
	var voxel_world: Node3D = controller.get("voxel_world")
	return action_validator.valid_interdire_rect_cells(a, b, VoxelWorldScript.WIDTH, VoxelWorldScript.DEPTH, voxel_world)


static func update_interdire_drag_preview(controller: CanvasLayer) -> void:
	clear_drag_preview(controller)
	var voxel_world: Node3D = controller.get("voxel_world")
	var drag_start: Vector2i = controller.get("drag_start")
	var drag_end: Vector2i = controller.get("drag_end")
	var drag_preview_ghosts: Array = controller.get("drag_preview_ghosts")
	for cell in valid_interdire_rect_cells(controller, drag_start, drag_end):
		var y: int = voxel_world.get_top_block_y(cell.x, cell.y)
		var ghost := spawn_ghost(controller, cell.x, y, cell.y, "interdire", 0.5)
		drag_preview_ghosts.append(ghost)


## Bascule l'etat "interdit" de TOUTES les cases valides du rectangle - la
## case de DEPART du glisser (drag_start) decide du sens pour tout le
## rectangle (si elle n'etait pas encore interdite, tout le rectangle
## DEVIENT interdit ; si elle l'etait deja, tout le rectangle est
## RE-AUTORISE). Simple clic = rectangle d'une seule case, donc bascule
## juste cette case-la (comportement standard des autres modes rectangle,
## voir on_left_press).
static func finalize_interdire_selection(controller: CanvasLayer) -> void:
	var voxel_world: Node3D = controller.get("voxel_world")
	var drag_start: Vector2i = controller.get("drag_start")
	var drag_end: Vector2i = controller.get("drag_end")
	var will_forbid: bool = not voxel_world.is_cell_forbidden(drag_start.x, drag_start.y)
	for cell in valid_interdire_rect_cells(controller, drag_start, drag_end):
		voxel_world.set_cell_forbidden(cell.x, cell.y, will_forbid)


## Bascule l'etat "interdit" d'un arbre/element de cueillette individuel -
## stocke en metadonnee directement sur le noeud (meme convention legere que
## "species_name"/"fruits_left" poses par Forest.gd/BerryBushes.gd), pas
## besoin d'un registre separe. Lu par ActionDragController
## (handle_chop_click/handle_gather_click/finalize_chop_selection/
## finalize_gather_selection, voir plus bas) et par
## ActionInspector.describe_gatherable (affichage au survol).
static func toggle_interdit_entity(target: Node) -> void:
	target.set_meta("interdit", not target.get_meta("interdit", false))


## Toutes les cases valides (avec de l'eau en surface) du rectangle -
## delegue a ActionValidator.gd.
static func valid_puiser_rect_cells(controller: CanvasLayer, a: Vector2i, b: Vector2i) -> Array:
	var action_validator = controller.get("action_validator")
	var voxel_world: Node3D = controller.get("voxel_world")
	return action_validator.valid_puiser_rect_cells(a, b, VoxelWorldScript.WIDTH, VoxelWorldScript.DEPTH, voxel_world)


static func update_puiser_drag_preview(controller: CanvasLayer) -> void:
	clear_drag_preview(controller)
	var voxel_world: Node3D = controller.get("voxel_world")
	var drag_start: Vector2i = controller.get("drag_start")
	var drag_end: Vector2i = controller.get("drag_end")
	var drag_preview_ghosts: Array = controller.get("drag_preview_ghosts")
	for cell in valid_puiser_rect_cells(controller, drag_start, drag_end):
		var y: int = voxel_world.get_top_block_y(cell.x, cell.y)
		var ghost := spawn_ghost(controller, cell.x, y, cell.y, "eau", 0.5)
		drag_preview_ghosts.append(ghost)


## Une tache de puisage par case d'eau valide, chacune avec son propre
## marqueur (icone "panier" teintee en bleu).
static func finalize_puiser_selection(controller: CanvasLayer) -> void:
	var voxel_world: Node3D = controller.get("voxel_world")
	var task_queue: Node = controller.get("task_queue")
	var queued_markers: Dictionary = controller.get("queued_markers")
	var drag_start: Vector2i = controller.get("drag_start")
	var drag_end: Vector2i = controller.get("drag_end")
	for cell in valid_puiser_rect_cells(controller, drag_start, drag_end):
		var top_y: int = voxel_world.get_top_block_y(cell.x, cell.y)
		var walk_pos := Vector3(cell.x + 0.5, GROUND_LEVEL, cell.y + 0.5)
		var task_id: int = task_queue.add_puiser_task(walk_pos, cell.x, cell.y)
		var marker_pos := Vector3(cell.x + 0.5, top_y + 1.2, cell.y + 0.5)
		queued_markers[task_id] = spawn_task_marker(controller, marker_pos, "panier", Color(0.25, 0.55, 0.85))


static func clear_drag_preview(controller: CanvasLayer) -> void:
	var drag_preview_ghosts: Array = controller.get("drag_preview_ghosts")
	for ghost in drag_preview_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	drag_preview_ghosts.clear()


## Cliquer-glisser termine : une tache de construction par case valide,
## chacune avec son propre mur fantome persistant jusqu'a la fin de la tache.
static func finalize_drag_selection(controller: CanvasLayer) -> void:
	var voxel_world: Node3D = controller.get("voxel_world")
	var task_queue: Node = controller.get("task_queue")
	var queued_ghosts: Dictionary = controller.get("queued_ghosts")
	var pending_columns: Dictionary = controller.get("pending_columns")
	var selected_material: String = controller.get("selected_material")
	var drag_start: Vector2i = controller.get("drag_start")
	var drag_end: Vector2i = controller.get("drag_end")
	for cell in valid_rect_cells(controller, drag_start, drag_end):
		var walk_pos := Vector3(cell.x + 0.5, GROUND_LEVEL, cell.y + 0.5)
		var task_id: int = task_queue.add_build_task(walk_pos, cell.x, cell.y, selected_material)
		pending_columns[cell] = true
		var y: int = voxel_world.get_top_block_y(cell.x, cell.y) + 1
		queued_ghosts[task_id] = spawn_ghost(controller, cell.x, y, cell.y, selected_material, 0.5)


## Retire le mur fantome correspondant une fois la tache de construction
## terminee (que le mur ait vraiment ete pose ou non).
static func on_build_task_finished(controller: CanvasLayer, task_id: int, bx: int, bz: int) -> void:
	var pending_columns: Dictionary = controller.get("pending_columns")
	var queued_ghosts: Dictionary = controller.get("queued_ghosts")
	pending_columns.erase(Vector2i(bx, bz))
	if queued_ghosts.has(task_id):
		var ghost = queued_ghosts[task_id]
		if is_instance_valid(ghost):
			ghost.queue_free()
		queued_ghosts.erase(task_id)


## Retire l'icone temporaire d'une tache Miner/Couper/Cueillir/Puiser une
## fois qu'elle est terminee (signal generique emis pour TOUTES les taches -
## on verifie juste si un marqueur existe pour cet id).
static func on_task_finished(controller: CanvasLayer, task_id: int) -> void:
	var queued_markers: Dictionary = controller.get("queued_markers")
	if queued_markers.has(task_id):
		var marker = queued_markers[task_id]
		if is_instance_valid(marker):
			marker.queue_free()
		queued_markers.erase(task_id)


## Point d'entree du clic en mode Annuler - trouve le marqueur/fantome de
## tache le plus proche du clic (ecran) et annule la tache correspondante.
## Ne fait rien si aucun marqueur/fantome n'est dans le rayon (pas d'erreur,
## comme Inspecter quand rien n'est sous le clic).
static func on_annuler_click(controller: CanvasLayer, screen_pos: Vector2) -> void:
	var task_id := find_task_id_at_screen_pos(controller, screen_pos)
	if task_id == -1:
		return
	cancel_task(controller, task_id)


## Cherche, parmi TOUS les marqueurs (Miner/Couper/Cueillir/Puiser) et
## fantomes (Construire) actuellement affiches, celui dont la position
## projetee a l'ecran est la plus proche du clic - meme principe que
## ActionInspector.dwarf_at_screen_pos (rayon ANNULER_CLICK_RADIUS_PX).
static func find_task_id_at_screen_pos(controller: CanvasLayer, screen_pos: Vector2) -> int:
	var camera: Camera3D = controller.get("camera")
	var queued_markers: Dictionary = controller.get("queued_markers")
	var queued_ghosts: Dictionary = controller.get("queued_ghosts")
	var closest_id := -1
	var closest_dist := ANNULER_CLICK_RADIUS_PX
	for task_id in queued_markers:
		var node = queued_markers[task_id]
		if not is_instance_valid(node):
			continue
		var d: float = camera.unproject_position(node.position).distance_to(screen_pos)
		if d < closest_dist:
			closest_dist = d
			closest_id = task_id
	for task_id in queued_ghosts:
		var node = queued_ghosts[task_id]
		if not is_instance_valid(node):
			continue
		var d: float = camera.unproject_position(node.position).distance_to(screen_pos)
		if d < closest_dist:
			closest_dist = d
			closest_id = task_id
	return closest_id


## Annule la tache "task_id" : la retire de TaskQueue si elle y est encore,
## sinon interrompt proprement le nain qui l'avait deja prise (meme etats
## remis a zero que l'interruption faim/soif critique dans Dwarf.gd, voir
## _handle_critical_needs - sauf qu'ici la tache n'est PAS remise en file,
## elle est vraiment annulee). Nettoie ensuite le marqueur/fantome associe et,
## pour une tache Construire, la colonne "pending_columns" correspondante
## (sinon la case resterait bloquee pour une future designation).
static func cancel_task(controller: CanvasLayer, task_id: int) -> void:
	var task_queue: Node = controller.get("task_queue")
	var removed: Dictionary = task_queue.remove_task(task_id)
	if removed.is_empty():
		for d in controller.get_tree().get_nodes_in_group("dwarves"):
			if d.current_task.get("id", -1) == task_id:
				removed = d.current_task
				d.set("current_task", {})
				d.set("is_working", false)
				d.set("work_timer", 0.0)
				d.call("_hide_tools")
				d.call("_reset_pose")
				break
	if removed.is_empty():
		return

	var queued_markers: Dictionary = controller.get("queued_markers")
	if queued_markers.has(task_id):
		var marker = queued_markers[task_id]
		if is_instance_valid(marker):
			marker.queue_free()
		queued_markers.erase(task_id)

	var queued_ghosts: Dictionary = controller.get("queued_ghosts")
	if queued_ghosts.has(task_id):
		var ghost = queued_ghosts[task_id]
		if is_instance_valid(ghost):
			ghost.queue_free()
		queued_ghosts.erase(task_id)
		var pending_columns: Dictionary = controller.get("pending_columns")
		pending_columns.erase(Vector2i(removed.get("bx", 0), removed.get("bz", 0)))


static func spawn_ghost(controller: CanvasLayer, gx: int, gy: int, gz: int, material: String, alpha: float) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.94, 0.94, 0.94)  # legerement plus petit que le bloc reel pour bien le distinguer
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	var color: Color = controller.call("_material_color", material)
	color.a = alpha
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.position = Vector3(gx + 0.5, gy + 0.5, gz + 0.5)

	controller.get_parent().add_child(mesh_inst)
	return mesh_inst


## Petit marqueur en forme d'outil, toujours face a la camera, affiche
## au-dessus d'un objet/case designe pour Miner/Couper/Cueillir/Puiser tant
## que la tache n'est pas terminee.
static func spawn_task_marker(controller: CanvasLayer, pos: Vector3, kind: String, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	mesh_inst.mesh = quad

	var icon_renderer = controller.get("icon_renderer")
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = icon_renderer.get_icon_texture(kind, color, ICON_SIZE, ICON_GLYPH_SIZE)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED  # toujours face a la camera
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # rendu net, pas flou
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.position = pos

	controller.get_parent().add_child(mesh_inst)
	return mesh_inst


## Recherche de la cible la plus proche deleguee a ActionValidator.gd - seuls
## le marqueur visuel et l'ajout a la queue de taches restent ici.
static func handle_chop_click(controller: CanvasLayer, hit: Vector3) -> void:
	var action_validator = controller.get("action_validator")
	var task_queue: Node = controller.get("task_queue")
	var queued_markers: Dictionary = controller.get("queued_markers")
	var closest_tree: Node3D = action_validator.closest_in_group(hit, "trees", controller.get_tree(), 2.0)

	# Un arbre "interdit" n'est pas cible - meme comportement que si rien
	# n'avait ete trouve (pas de recherche du "suivant" plus loin,
	# comportement simple).
	if closest_tree and closest_tree.get_meta("interdit", false):
		return

	if closest_tree:
		var task_id: int = task_queue.add_chop_task(closest_tree)
		var marker_pos: Vector3 = closest_tree.global_position + Vector3(0, marker_height_for(closest_tree), 0)
		queued_markers[task_id] = spawn_task_marker(controller, marker_pos, "hache", Color(0.25, 0.55, 0.15))


## La hauteur du marqueur suit l'echelle reelle de la cible (arbres mis a
## l'echelle aleatoirement a la creation, voir Forest.gd/scale_jitter) - 2.9
## choisi pour rester au-dessus de la couronne la plus haute (chene).
static func marker_height_for(target: Node3D) -> float:
	if target.is_in_group("trees"):
		return 2.9 * target.scale.y
	return 1.0


## Detection au clic pour "Cueillir" - cible le groupe "cueillette" (arbres
## fruitiers + buissons a baies), independant du groupe "trees" utilise par
## "Couper".
static func handle_gather_click(controller: CanvasLayer, hit: Vector3) -> void:
	var action_validator = controller.get("action_validator")
	var task_queue: Node = controller.get("task_queue")
	var queued_markers: Dictionary = controller.get("queued_markers")
	var closest_target: Node3D = action_validator.closest_in_group(hit, "cueillette", controller.get_tree(), 2.0)

	# Meme exclusion que handle_chop_click ci-dessus.
	if closest_target and closest_target.get_meta("interdit", false):
		return

	if closest_target:
		var task_id: int = task_queue.add_gather_task(closest_target)
		var marker_pos: Vector3 = closest_target.global_position + Vector3(0, marker_height_for(closest_target), 0)
		queued_markers[task_id] = spawn_task_marker(controller, marker_pos, "panier", Color(0.85, 0.25, 0.25))
