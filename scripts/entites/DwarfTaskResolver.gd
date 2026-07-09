extends RefCounted
## Resolution des taches terminees (miner/couper/construire/cueillir/
## puiser/detruire), extraite de Dwarf.gd. Chaque fonction recoit le nain
## via un parametre "dwarf" (Node3D) plutot qu'un "self" implicite, et
## lit/ecrit ses proprietes via dwarf.get()/dwarf.set() (acces dynamique
## Godot, necessaire car "dwarf" est type generiquement Node3D, pas Dwarf).

const SkillDefs := preload("res://scripts/data/creatures/nains/caracteristiques/SkillDefinitions.gd")
const DwarfSkillsScript := preload("res://scripts/entites/DwarfSkills.gd")
const DwarfResourcePileScript := preload("res://scripts/entites/DwarfResourcePile.gd")


## Point d'entree, une fonction par type de tache appelee via un match
## compact.
static func complete_task(dwarf: Node3D) -> void:
	var current_task: Dictionary = dwarf.get("current_task")
	# Competence liee au type de tache (si il y en a une), pour le gain
	# d'xp et la chance de ressource bonus a la recolte.
	var skill_id: String = SkillDefs.skill_for_task(current_task.get("type", ""))

	match current_task.get("type"):
		"miner":
			complete_miner_task(dwarf, skill_id)
		"couper":
			complete_couper_task(dwarf, skill_id)
		"construire":
			complete_construire_task(dwarf)
		"cueillir":
			complete_cueillir_task(dwarf, skill_id)
		"puiser":
			complete_puiser_task(dwarf)
		"detruire":
			complete_detruire_task(dwarf)
		"escalier":
			complete_escalier_task(dwarf)

	if skill_id != "":
		var skills: DwarfSkillsScript = dwarf.get("skills")
		var skill_levels: Dictionary = dwarf.get("skill_levels")
		var skill_xp: Dictionary = dwarf.get("skill_xp")
		var dwarf_name: String = dwarf.get("dwarf_name")
		skills.gain_xp(skill_levels, skill_xp, skill_id, DwarfSkillsScript.SKILL_XP_PER_TASK, dwarf_name)

	# Signale la fin de la tache (quel que soit son type) pour que
	# ActionController.gd retire l'icone temporaire affichee au moment de
	# la designation.
	dwarf.emit_signal("task_finished", current_task.get("id", -1))

	dwarf.set("current_task", {})

	# Communes a TOUTES les taches.
	dwarf.set("is_working", false)
	dwarf.call("_pick_new_target")


static func complete_miner_task(dwarf: Node3D, skill_id: String) -> void:
	var current_task: Dictionary = dwarf.get("current_task")
	var voxel_world: Node3D = dwarf.get("voxel_world")
	var bx: int = current_task["bx"]
	var by: int = current_task["by"]
	var bz: int = current_task["bz"]
	# Miner peut desormais cibler le niveau de vue courant plutot que le
	# vrai sommet de la colonne (voir ActionValidator.valid_mine_rect_cells)
	# - decision Francois 2026-07-08 : le "plafond" (blocs restes au-dessus)
	# ne disparait PAS, comme dans Dwarf Fortress. La decoration au sol
	# (herbe/fleur/caillou, voir GroundDecoration.remove_decoration_at)
	# n'existe elle que sur le VRAI sommet - il faut donc verifier AVANT de
	# miner que "by" est bien ce sommet, sinon on effacerait a tort la
	# decoration de surface en minant une poche plus bas.
	var was_top: bool = (by == voxel_world.get_top_block_y(bx, bz))
	var resource_name: String = voxel_world.remove_block(bx, by, bz)
	if was_top:
		var ground_decoration: Node3D = dwarf.get("ground_decoration")
		if ground_decoration and ground_decoration.has_method("remove_decoration_at"):
			ground_decoration.remove_decoration_at(bx, bz)
	if resource_name != "":
		# Le tas tombe au fond du trou (niveau "by", meme convention que
		# complete_escalier_task) au lieu de rester a la position du nain -
		# pour un bloc mine SOUS les pieds du nain (le cas le plus courant,
		# un "trou" creuse depuis la surface), dwarf.global_position resterait
		# au niveau du DESSUS du trou, pas dedans (bug remonte par Francois
		# 2026-07-08, meme symptome que l'escalier : tas en apesanteur).
		var pile_pos := Vector3(bx + 0.5, float(by), bz + 0.5)
		DwarfResourcePileScript.collect_resource(dwarf, resource_name, pile_pos)
		var skills: DwarfSkillsScript = dwarf.get("skills")
		var skill_levels: Dictionary = dwarf.get("skill_levels")
		if skills.roll_bonus_yield(skill_levels, skill_id):
			DwarfResourcePileScript.collect_resource(dwarf, resource_name, pile_pos)


## Creuse toute la plage de niveaux d'un coup (voir VoxelWorld.dig_stairs) -
## un seul nain, une seule tache, plusieurs niveaux ressource par ressource.
## Pas de bonus de competence pour l'instant (SkillDefs.skill_for_task ne
## mappe pas "escalier" - a revoir si besoin, cette premiere passe se
## concentre sur le menu/creusage/rendu, pas l'equilibrage).
static func complete_escalier_task(dwarf: Node3D) -> void:
	var current_task: Dictionary = dwarf.get("current_task")
	var voxel_world: Node3D = dwarf.get("voxel_world")
	var bx: int = current_task["bx"]
	var bz: int = current_task["bz"]
	var bottom_y: int = current_task["bottom_y"]
	var resources: Dictionary = voxel_world.dig_stairs(bx, bz, current_task["top_y"], bottom_y)
	var ground_decoration: Node3D = dwarf.get("ground_decoration")
	if ground_decoration and ground_decoration.has_method("remove_decoration_at"):
		ground_decoration.remove_decoration_at(bx, bz)
	# Les tas "tombent" au fond de l'escalier creuse (niveau bottom_y) au lieu
	# de rester a la hauteur ou se tenait le nain avant de commencer - il
	# creuse toute la plage de niveaux d'un coup sans bouger, donc
	# dwarf.global_position (repli par defaut de collect_resource) resterait
	# fige au sommet, au-dessus du trou nouvellement creuse (bug remonte par
	# Francois 2026-07-08, capture d'ecran : tas flottant en l'air).
	var pile_pos := Vector3(bx + 0.5, float(bottom_y), bz + 0.5)
	for resource_name in resources:
		var count: int = resources[resource_name]
		for i in range(count):
			DwarfResourcePileScript.collect_resource(dwarf, resource_name, pile_pos)


## Demolit un mur construit (mur_bois/mur_pierre uniquement - un mur en
## "terre" est indistinguable de la terre naturelle, pas ciblable, voir
## ActionValidator.valid_destroy_rect_cells). Rembourse le materiau via
## remove_block (qui renvoie "bois"/"pierre" pour un mur). Pas de
## decoration au sol a nettoyer (contrairement a complete_miner_task) : un
## mur n'a jamais de decoration.
static func complete_detruire_task(dwarf: Node3D) -> void:
	var current_task: Dictionary = dwarf.get("current_task")
	var voxel_world: Node3D = dwarf.get("voxel_world")
	var resource_name: String = voxel_world.remove_block(
		current_task["bx"], current_task["by"], current_task["bz"]
	)
	if resource_name != "":
		DwarfResourcePileScript.collect_resource(dwarf, resource_name)


static func complete_couper_task(dwarf: Node3D, skill_id: String) -> void:
	var current_task: Dictionary = dwarf.get("current_task")
	var tree = current_task.get("tree")
	# Chaque arbre porte son type de bois en metadonnee.
	var wood_type: String = "bois"
	if is_instance_valid(tree):
		wood_type = tree.get_meta("wood_resource", "bois")
		# Tout le visuel de l'arbre vit dans des maillages partages entre
		# TOUS les arbres - il faut donc explicitement les cacher ici,
		# sinon ils resteraient visibles pour toujours meme apres
		# tree.queue_free().
		var forest: Node3D = dwarf.get("forest")
		if forest and forest.has_method("hide_tree_visuals"):
			forest.hide_tree_visuals(tree)
		tree.queue_free()
	var skills: DwarfSkillsScript = dwarf.get("skills")
	var skill_levels: Dictionary = dwarf.get("skill_levels")
	var wood_count: int = 2 if skills.roll_bonus_yield(skill_levels, skill_id) else 1
	var inventory: Node = dwarf.get("inventory")
	for i in range(wood_count):
		DwarfResourcePileScript.collect_resource(dwarf, wood_type)
		# Le compteur generique "bois" reste alimente en plus du type
		# specifique, pour que la construction (qui ne connait que "bois"
		# generique) continue de fonctionner sans etre modifiee.
		if wood_type != "bois":
			inventory.add_resource("bois", 1)


static func complete_construire_task(dwarf: Node3D) -> void:
	var current_task: Dictionary = dwarf.get("current_task")
	var material: String = current_task["material"]
	var bx: int = current_task["bx"]
	var bz: int = current_task["bz"]
	var inventory: Node = dwarf.get("inventory")
	var voxel_world: Node3D = dwarf.get("voxel_world")
	if inventory.remove_resource(material, 1):
		voxel_world.build_block(bx, bz, material)
		if OS.is_debug_build():
			print("Mur en %s construit a (%d, %d)" % [material, bx, bz])
	else:
		if OS.is_debug_build():
			print("Pas assez de %s pour construire (tache annulee)" % material)
	dwarf.emit_signal("build_task_finished", current_task.get("id", -1), bx, bz)


## Recolte un fruit/une baie sans detruire la cible - generique entre
## arbres fruitiers (Forest.gd) et buissons (BerryBushes.gd).
static func complete_cueillir_task(dwarf: Node3D, skill_id: String) -> void:
	var current_task: Dictionary = dwarf.get("current_task")
	var target: Node = current_task.get("tree")
	if is_instance_valid(target):
		var fruit_resource: String = target.get_meta("fruit_resource", "")
		var fruits_left: int = target.get_meta("fruits_left", 0)
		if fruit_resource != "" and fruits_left > 0:
			fruits_left = harvest_one_fruit(target, fruits_left)
			DwarfResourcePileScript.collect_resource(dwarf, fruit_resource)
			# Bonus de recolte (competence Agriculture), limite aux fruits
			# reellement encore disponibles sur la cible.
			var skills: DwarfSkillsScript = dwarf.get("skills")
			var skill_levels: Dictionary = dwarf.get("skill_levels")
			if fruits_left > 0 and skills.roll_bonus_yield(skill_levels, skill_id):
				harvest_one_fruit(target, fruits_left)
				DwarfResourcePileScript.collect_resource(dwarf, fruit_resource)


## Contrairement a "miner", on ne retire rien de VoxelWorld - l'eau est une
## ressource renouvelable.
static func complete_puiser_task(dwarf: Node3D) -> void:
	DwarfResourcePileScript.collect_resource(dwarf, "eau")


## Retire un fruit de "target" (fruits_left-1 -> meta + suppression du
## noeud Fruit_%d correspondant), utilise pour la recolte de base et pour
## le fruit bonus eventuel. Renvoie le nouveau nombre de fruits restants.
static func harvest_one_fruit(target: Node, fruits_left: int) -> int:
	var new_count: int = fruits_left - 1
	target.set_meta("fruits_left", new_count)
	var fruit_node: Node = target.get_node_or_null("Fruit_%d" % new_count)
	if fruit_node:
		fruit_node.queue_free()
	return new_count
