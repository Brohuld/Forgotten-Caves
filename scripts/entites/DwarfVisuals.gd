extends RefCounted
## Apparence et accessoires visuels d'action (outils/indicateurs) d'un
## nain, extrait de Dwarf.gd. Chaque fonction recoit le nain via un
## parametre "dwarf" (Node3D) plutot qu'un "self" implicite, et lit/ecrit
## ses proprietes via dwarf.get()/dwarf.set() (acces dynamique Godot,
## necessaire car "dwarf" est type generiquement Node3D, pas Dwarf, pour
## eviter un preload circulaire).
## HEAD_HEIGHT_APPROX est aussi declaree dans DwarfNeeds.gd (utilisee par
## _process_resting pour le balancement du "Z z z") - const non visible via
## get(), doit donc etre dupliquee la ou elle est utilisee.

const HEAD_HEIGHT_APPROX := 0.95
const DwarfModel3DScript := preload("res://scripts/prototypes/DwarfModel3D.gd")


## --- Apparence : modele 3D procedural ---
static func build_appearance(dwarf: Node3D) -> void:
	var dwarf_model := Node3D.new()
	dwarf_model.set_script(load("res://scripts/prototypes/DwarfModel3D.gd"))
	dwarf_model.name = "DwarfModel"

	dwarf_model._randomize_variation()
	dwarf_model.hair_color = dwarf.get("hair_color")
	dwarf_model.beard_color = dwarf.get("beard_color")
	dwarf_model.clothing_color = dwarf.get("clothing_color")
	dwarf_model.armor_color = dwarf.get("armor_color")
	# Pas de systeme de combat dans le jeu principal pour l'instant : on
	# force "sans arme" quel que soit le tirage aleatoire.
	dwarf_model.weapon_loadout = "Aucune"

	var body: Node3D = dwarf.get("body")
	body.add_child(dwarf_model)
	dwarf_model.scale = Vector3.ONE * float(dwarf.get("model_scale"))
	dwarf.set("dwarf_model", dwarf_model)

	build_tool_accessory(dwarf)
	build_sleep_indicator(dwarf)
	build_food_indicator(dwarf)


## Remet l'animation en position neutre (utilise a chaque arret de marche :
## travail, repos, repas).
static func reset_pose(dwarf: Node3D) -> void:
	var dwarf_model: Node3D = dwarf.get("dwarf_model")
	dwarf_model.preview_animation = "Aucune"


## Construit les 3 outils possibles (pioche/hache/marteau), caches par
## defaut ; seul celui qui correspond au type de tache en cours est montre
## (voir show_tool_for_task). Attache a la main droite du modele 3D.
static func build_tool_accessory(dwarf: Node3D) -> void:
	var dwarf_model: Node3D = dwarf.get("dwarf_model")
	# Couple a DwarfModel3D._build_arms() (qui remplit _hand_r) - fonctionne
	# grace a l'ordre interne de _build_model(). Garde de nullite pour
	# eviter un crash silencieux sur "Nonexistent function/attribute" si
	# _hand_r n'existe pas encore.
	if dwarf_model._hand_r == null:
		push_warning("DwarfVisuals.build_tool_accessory : dwarf_model._hand_r est null - _build_arms() a-t-il ete appele avant ceci ?")
		return
	var tool_pivot := Node3D.new()
	dwarf_model._hand_r.add_child(tool_pivot)

	var tool_pickaxe := make_tool_mesh(Vector3(0.05, 0.32, 0.05), Vector3(0.26, 0.07, 0.05), Color(0.4, 0.28, 0.15), Color(0.5, 0.5, 0.55))
	var tool_axe := make_tool_mesh(Vector3(0.05, 0.30, 0.05), Vector3(0.20, 0.16, 0.05), Color(0.4, 0.28, 0.15), Color(0.72, 0.74, 0.78))
	var tool_hammer := make_tool_mesh(Vector3(0.045, 0.26, 0.045), Vector3(0.16, 0.14, 0.14), Color(0.4, 0.28, 0.15), Color(0.42, 0.42, 0.46))

	tool_pivot.add_child(tool_pickaxe)
	tool_pivot.add_child(tool_axe)
	tool_pivot.add_child(tool_hammer)
	tool_pickaxe.visible = false
	tool_axe.visible = false
	tool_hammer.visible = false

	dwarf.set("tool_pivot", tool_pivot)
	dwarf.set("tool_pickaxe", tool_pickaxe)
	dwarf.set("tool_axe", tool_axe)
	dwarf.set("tool_hammer", tool_hammer)


## Cree un outil simple (manche + tete) a partir de 2 boites, sans texture
## (couleurs unies non eclairees, coherent avec le style "icone")
static func make_tool_mesh(handle_size: Vector3, head_size: Vector3, handle_color: Color, head_color: Color) -> Node3D:
	var root := Node3D.new()

	var handle := MeshInstance3D.new()
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = handle_size
	handle.mesh = handle_mesh
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = handle_color
	handle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	handle.set_surface_override_material(0, handle_mat)
	root.add_child(handle)

	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = head_size
	head.mesh = head_mesh
	head.position = Vector3(0, handle_size.y * 0.5, 0)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = head_color
	head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	head.set_surface_override_material(0, head_mat)
	root.add_child(head)

	return root


## Montre le bon outil selon le type de tache en cours (masque les autres)
static func show_tool_for_task(dwarf: Node3D) -> void:
	var tool_pickaxe: Node3D = dwarf.get("tool_pickaxe")
	var tool_axe: Node3D = dwarf.get("tool_axe")
	var tool_hammer: Node3D = dwarf.get("tool_hammer")
	tool_pickaxe.visible = false
	tool_axe.visible = false
	tool_hammer.visible = false
	var current_task: Dictionary = dwarf.get("current_task")
	match current_task.get("type"):
		"miner":
			tool_pickaxe.visible = true
		"couper":
			tool_axe.visible = true
		"construire":
			tool_hammer.visible = true


static func hide_tools(dwarf: Node3D) -> void:
	var tool_pickaxe: Node3D = dwarf.get("tool_pickaxe")
	var tool_axe: Node3D = dwarf.get("tool_axe")
	var tool_hammer: Node3D = dwarf.get("tool_hammer")
	var tool_pivot: Node3D = dwarf.get("tool_pivot")
	tool_pickaxe.visible = false
	tool_axe.visible = false
	tool_hammer.visible = false
	tool_pivot.rotation = Vector3.ZERO


## "Z z z" flottant au-dessus de la tete pendant le repos
static func build_sleep_indicator(dwarf: Node3D) -> void:
	var sleep_indicator := Label3D.new()
	sleep_indicator.text = "Z z z"
	sleep_indicator.font_size = 60
	sleep_indicator.outline_size = 10
	sleep_indicator.modulate = Color(0.85, 0.9, 1.0)
	sleep_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sleep_indicator.no_depth_test = true
	var model_scale: float = dwarf.get("model_scale")
	sleep_indicator.position = Vector3(0, (HEAD_HEIGHT_APPROX + 0.35) * model_scale, 0)
	sleep_indicator.visible = false
	var body: Node3D = dwarf.get("body")
	body.add_child(sleep_indicator)
	dwarf.set("sleep_indicator", sleep_indicator)


## Petite baie qui flotte pres de la bouche pendant le repas
static func build_food_indicator(dwarf: Node3D) -> void:
	var food_indicator := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	food_indicator.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.1, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	food_indicator.set_surface_override_material(0, mat)
	var model_scale: float = dwarf.get("model_scale")
	food_indicator.position = Vector3(0, HEAD_HEIGHT_APPROX * 0.9 * model_scale, 0.18 * model_scale)  # hauteur approximative de la bouche
	food_indicator.visible = false
	var body: Node3D = dwarf.get("body")
	body.add_child(food_indicator)
	dwarf.set("food_indicator", food_indicator)
