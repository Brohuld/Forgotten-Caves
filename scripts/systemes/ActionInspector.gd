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
const PointerResolverScript := preload("res://scripts/systemes/PointerResolver.gd")
const EntityDescriptionsScript := preload("res://scripts/entites/EntityDescriptions.gd")

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


## Traduit un resultat PointerResolver.resolve() en texte a afficher - AUCUNE
## connaissance du type d'entite ici (voir EntityDescriptions.describe_by_kind,
## qui lit la metadonnee "hover_kind" posee par l'entite elle-meme). Remplace
## l'ancienne recherche par proximite (rayon fixe 1.0-2.0 unites) qui
## debordait sur les cases voisines pres d'une berge/falaise - un tas/arbre
## "presque a cote" pouvait gagner a tort sur le terrain reellement vise
## (feedback Francois 2026-07-10).
static func describe_pointed_object(controller: CanvasLayer, result) -> String:
	if result == null:
		return ""
	if result["kind"] == "entity":
		var node: Node3D = result["node"]
		if node == null or not is_instance_valid(node):
			return ""
		return EntityDescriptionsScript.describe_by_kind(node)
	var voxel_world: Node3D = controller.get("voxel_world")
	return describe_block_at(voxel_world, result["cell"])


## Nom d'un bloc de sol (terre/pierre/mur) a une case EXACTE, via
## VoxelWorld.describe_visible_cell() - PAS get_block_info() (qui recalcule
## le sommet de la colonne et ratait donc une paroi de falaise/berge visee
## en biais, voir doc de raycast_visible_face). Si le bloc de pierre contient
## un filon, affiche son nom (VeinMaterials). Meme suffixe "[Interdit]" que
## describe_gatherable ci-dessus, si VoxelWorld.is_cell_forbidden(gx,gz).
static func describe_block_at(voxel_world: Node3D, cell: Vector3i) -> String:
	var info: Dictionary = voxel_world.describe_visible_cell(cell)
	var suffix: String = "  [Interdit]" if voxel_world.is_cell_forbidden(cell.x, cell.z) else ""
	# Coordonnees (x, y, z) de la case visee, remises dans le texte de survol
	# (perdues lors du passage au raymarching voxel/PointerResolver generique
	# 2026-07-10) - utiles pour correler ce qui est affiche avec les positions
	# loggees en debug (ex: "discovered.has(pos)").
	var coords: String = " (%d, %d, %d)" % [cell.x, cell.y, cell.z]
	match info["type"]:
		"non_decouvert":
			return "Terrain non decouvert" + coords
		"terre":
			# "Herbe" pour une case SOL SEUL (CUBE vide - surface naturelle ou
			# fond de trou, voir modele CUBE+SOL), "Terre" pour un vrai CUBE
			# plein (creuser y donnera bien de la terre) - meme type "terre"
			# cote donnees (get_sol renvoie DIRT dans les 2 cas), mais le
			# joueur doit pouvoir les distinguer au survol (Francois
			# 2026-07-10).
			var label := "Terre" if voxel_world.is_solid(cell.x, cell.y, cell.z) else "Herbe"
			return label + suffix + coords
		"pierre":
			var materiau: String = info["materiau"]
			if materiau != "":
				var mat: Dictionary = VeinMaterials.get_type(materiau)
				return "Filon de %s%s%s" % [mat.get("nom", materiau), suffix, coords]
			return "Pierre" + suffix + coords
		"mur_bois":
			return "Mur en bois" + suffix + coords
		"mur_pierre":
			return "Mur en pierre" + suffix + coords
		"eau":
			return "Eau" + coords
		_:
			return ""


## Mis a jour chaque frame - decrit ce qui se trouve sous la souris (nain,
## ou n'importe quel objet resolu par PointerResolver : terrain, tas, arbre,
## buisson, et tout futur objet avec un collider Hoverable), quel que soit
## le mode courant. Utilise PointerResolver.resolve() (raycast physique sur
## les colliders Hoverable + raymarching voxel pour le terrain, comparaison
## par distance reelle) plutot qu'une recherche par proximite avec un rayon
## fixe - qui debordait sur les cases voisines pres d'une berge/falaise
## (feedback Francois 2026-07-10 : "il faut une logique tres precise et
## generique").
static func update_hover_info_panel(controller: CanvasLayer) -> void:
	var info_label: Label = controller.get("info_label")
	var screen_pos: Vector2 = controller.get_viewport().get_mouse_position()

	var hovered_dwarf: Node = dwarf_at_screen_pos(controller, screen_pos)
	if hovered_dwarf != null and is_instance_valid(hovered_dwarf):
		info_label.text = "%s\nTache : %s" % [hovered_dwarf.dwarf_name, hover_task_description(hovered_dwarf)]
		return

	var camera: Camera3D = controller.get("camera")
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var result = PointerResolverScript.resolve(controller, ray_origin, ray_dir)
	if result == null:
		info_label.text = "Survolez un element de la carte..."
		return

	var label := describe_pointed_object(controller, result)
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
