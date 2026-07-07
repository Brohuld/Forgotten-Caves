extends RefCounted
## Inspection/survol en lecture seule (clic Inspecter, panneau d'info survole)
## - aucun etat de glisser/tache partage (voir ActionDragController.gd pour
## l'autre moitie, plus complexe car stateful).
##
## Meme motif que Model3DUtils.gd/DwarfWeaponBuilder.gd : "controller" recoit
## le ActionController via parametre (type generique CanvasLayer pour eviter
## un preload circulaire), proprietes lues via controller.get() (acces
## dynamique Godot - necessaire car les proprietes de script ne sont pas
## visibles a la verification de type statique sur un CanvasLayer generique).
## DWARF_CLICK_RADIUS_PX duplique ci-dessous (les "const" ne sont pas
## visibles via get(), meme raison que MATERIAL_COLORS dans
## DwarfWeaponBuilder.gd) - a garder synchronise si la valeur d'origine
## change dans ActionController.gd. Utilise VoxelWorld.WIDTH/DEPTH
## directement (source faisant deja autorite) plutot que de dupliquer une 3e
## fois GRID_WIDTH/GRID_DEPTH.

const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")
const ActionDragControllerScript := preload("res://scripts/systemes/ActionDragController.gd")

const DWARF_CLICK_RADIUS_PX := 28.0


## Point d'entree de l'inspection (clic gauche quand aucun mode d'action
## n'est actif) : ne gere que la selection/ouverture de fiche d'un nain
## clique directement.
static func handle_inspect_click(controller: CanvasLayer, screen_pos: Vector2) -> void:
	var clicked_dwarf: Node = dwarf_at_screen_pos(controller, screen_pos)
	if clicked_dwarf == null:
		return
	var additive: bool = Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)
	var character_sheet_ui: CanvasLayer = controller.get("character_sheet_ui")
	character_sheet_ui.select_and_open_dwarf(clicked_dwarf, additive)


## Nain le plus proche d'une position ECRAN (pas monde), dans un rayon de
## DWARF_CLICK_RADIUS_PX pixels.
static func dwarf_at_screen_pos(controller: CanvasLayer, screen_pos: Vector2) -> Node:
	var camera: Camera3D = controller.get("camera")
	var closest: Node = null
	var closest_dist := DWARF_CLICK_RADIUS_PX
	for dwarf in controller.get_tree().get_nodes_in_group("dwarves"):
		var projected: Vector2 = camera.unproject_position(dwarf.global_position)
		var d: float = projected.distance_to(screen_pos)
		if d < closest_dist:
			closest_dist = d
			closest = dwarf
	return closest


## Les tas de ressources au sol (groupe "resource_piles") sont detectes en
## priorite, avant les arbres/buissons.
static func closest_resource_pile(controller: CanvasLayer, hit: Vector3) -> Node3D:
	var closest: Node3D = null
	var closest_dist := 1.0
	for pile in controller.get_tree().get_nodes_in_group("resource_piles"):
		var d: float = Vector2(pile.global_position.x - hit.x, pile.global_position.z - hit.z).length()
		if d < closest_dist:
			closest_dist = d
			closest = pile
	return closest


static func describe_resource_pile(pile: Node3D) -> String:
	var resource_name: String = String(pile.get_meta("resource_name"))
	var count: int = int(pile.get_meta("count"))
	return "Pile de %d %s" % [count, resource_name.capitalize()]


## Reutilise action_validator.closest_in_group (deja utilise pour Couper/
## Cueillir dans ActionDragController.gd) au lieu de refaire a la main la
## meme recherche.
static func inspect_label_for(controller: CanvasLayer, hit: Vector3) -> String:
	var pile := closest_resource_pile(controller, hit)
	if pile != null:
		return describe_resource_pile(pile)

	var action_validator = controller.get("action_validator")
	var closest_target: Node3D = action_validator.closest_in_group(hit, "cueillette", controller.get_tree(), 2.0)
	if closest_target == null:
		closest_target = action_validator.closest_in_group(hit, "trees", controller.get_tree(), 2.0)

	if closest_target:
		return describe_gatherable(closest_target)

	var gx := int(floor(hit.x))
	var gz := int(floor(hit.z))
	if gx < 0 or gx >= VoxelWorldScript.WIDTH or gz < 0 or gz >= VoxelWorldScript.DEPTH:
		return ""
	var voxel_world: Node3D = controller.get("voxel_world")
	return describe_block(voxel_world, gx, gz)


## Nom + etat de recolte d'un arbre/buisson/plante, via les metadonnees deja
## posees par Forest.gd/BerryBushes.gd ("species_name", "fruits_left").
## Suffixe "[Interdit]" si toggle_interdit_entity (ActionDragController.gd) a
## marque ce noeud - sans ca, rien ne permet au joueur de savoir qu'un arbre
## est interdit (Couper/Cueillir echouent silencieusement dessus, voir
## handle_chop_click/handle_gather_click).
static func describe_gatherable(node: Node) -> String:
	var species_name: String = node.get_meta("species_name", "?")
	var suffix: String = "  [Interdit]" if node.get_meta("interdit", false) else ""
	if not node.is_in_group("cueillette"):
		return species_name + suffix
	var fruits_left: int = node.get_meta("fruits_left", -1)
	if fruits_left < 0:
		return species_name + suffix
	if fruits_left == 0:
		return "%s (vide)%s" % [species_name, suffix]
	return "%s - %d fruit(s) restant(s)%s" % [species_name, fruits_left, suffix]


## Nom d'un bloc de sol (terre/pierre/mur), via VoxelWorld.get_block_info().
## Si le bloc de pierre contient un filon, affiche son nom (VeinMaterials).
## Meme suffixe "[Interdit]" que describe_gatherable ci-dessus, si
## VoxelWorld.is_cell_forbidden(gx,gz).
static func describe_block(voxel_world: Node3D, gx: int, gz: int) -> String:
	var info: Dictionary = voxel_world.get_block_info(gx, gz)
	var suffix: String = "  [Interdit]" if voxel_world.is_cell_forbidden(gx, gz) else ""
	match info["type"]:
		"terre":
			return "Terre" + suffix
		"pierre":
			var materiau: String = info["materiau"]
			if materiau != "":
				var mat: Dictionary = VeinMaterials.get_type(materiau)
				return "Filon de %s%s" % [mat.get("nom", materiau), suffix]
			return "Pierre" + suffix
		"mur_bois":
			return "Mur en bois" + suffix
		"mur_pierre":
			return "Mur en pierre" + suffix
		"eau":
			return "Eau"
		_:
			return ""


## Mis a jour chaque frame - decrit ce qui se trouve sous la souris (nain,
## arbre/buisson, bloc de sol), quel que soit le mode courant.
static func update_hover_info_panel(controller: CanvasLayer) -> void:
	var info_label: Label = controller.get("info_label")
	var screen_pos: Vector2 = controller.get_viewport().get_mouse_position()

	var hovered_dwarf: Node = dwarf_at_screen_pos(controller, screen_pos)
	if hovered_dwarf != null and is_instance_valid(hovered_dwarf):
		info_label.text = "%s\nTache : %s" % [hovered_dwarf.dwarf_name, hover_task_description(hovered_dwarf)]
		return

	var hit = ActionDragControllerScript.raycast_ground(controller, screen_pos)
	if hit == null:
		info_label.text = "Survolez un element de la carte..."
		return

	var label := inspect_label_for(controller, hit)
	info_label.text = label if label != "" else "Survolez un element de la carte..."


## Description courte de la tache en cours d'un nain survole.
static func hover_task_description(dwarf: Node) -> String:
	if dwarf.is_working:
		return String(dwarf.current_task.get("type", "?")).capitalize()
	if dwarf.is_resting:
		return "Repos"
	if dwarf.is_eating:
		return "Manger"
	if dwarf.is_drinking:
		return "Boire"
	if not dwarf.current_task.is_empty():
		return String(dwarf.current_task.get("type", "?")).capitalize()
	return "Errance"
