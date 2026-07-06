extends RefCounted
## 2026-07-06 (dette d'architecture A1, I60 - revue de code) : resolution des
## taches terminees (miner/couper/construire/cueillir/puiser), extraite
## mecaniquement de Dwarf.gd - fonctions inchangees, seule la signature
## change ("dwarf" recoit le Dwarf via parametre au lieu d'un "self"
## implicite, meme motif que DwarfVisuals.gd/DwarfMovement.gd/DwarfNeeds.gd).
## Proprietes lues/ecrites via dwarf.get()/dwarf.set() (acces dynamique
## Godot). Delegue a DwarfResourcePile.gd (collect_resource) - preloade
## ci-dessous.

const SkillDefs := preload("res://scripts/data/creatures/nains/caracteristiques/SkillDefinitions.gd")
const DwarfSkillsScript := preload("res://scripts/entites/DwarfSkills.gd")
const DwarfResourcePileScript := preload("res://scripts/entites/DwarfResourcePile.gd")


## 2026-07-06 (revue de code Phase 4, C17) : decoupee en une fonction par
## type de tache, appelees via un match compact au lieu d'une cascade
## if/elif. Aucun changement de comportement.
static func complete_task(dwarf: Node3D) -> void:
	var current_task: Dictionary = dwarf.get("current_task")
	# Sprint 18 : competence liee au type de tache (si il y en a une), pour
	# le gain d'xp et la chance de ressource bonus a la recolte
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

	if skill_id != "":
		var skills: DwarfSkillsScript = dwarf.get("skills")
		var skill_levels: Dictionary = dwarf.get("skill_levels")
		var skill_xp: Dictionary = dwarf.get("skill_xp")
		var dwarf_name: String = dwarf.get("dwarf_name")
		skills.gain_xp(skill_levels, skill_xp, skill_id, DwarfSkillsScript.SKILL_XP_PER_TASK, dwarf_name)

	# Sprint 26 : signale la fin de la tache (quel que soit son type) pour
	# que ActionController.gd retire l'icone temporaire affichee au moment
	# de la designation
	dwarf.emit_signal("task_finished", current_task.get("id", -1))

	dwarf.set("current_task", {})

	# 2026-07-06 : correctif regression - ces deux lignes etaient communes a
	# TOUTES les taches avant le decoupage Phase 4 (C17), voir historique du
	# fichier d'origine.
	dwarf.set("is_working", false)
	dwarf.call("_pick_new_target")


static func complete_miner_task(dwarf: Node3D, skill_id: String) -> void:
	var current_task: Dictionary = dwarf.get("current_task")
	var voxel_world: Node3D = dwarf.get("voxel_world")
	var resource_name: String = voxel_world.remove_block(
		current_task["bx"], current_task["by"], current_task["bz"]
	)
	# 2026-07-05 (correctif bug "decoration ne disparait pas au minage") :
	# retire toute decoration (herbe/fleur/caillou) posee sur cette colonne.
	var ground_decoration: Node3D = dwarf.get("ground_decoration")
	if ground_decoration and ground_decoration.has_method("remove_decoration_at"):
		ground_decoration.remove_decoration_at(current_task["bx"], current_task["bz"])
	if resource_name != "":
		DwarfResourcePileScript.collect_resource(dwarf, resource_name)
		var skills: DwarfSkillsScript = dwarf.get("skills")
		var skill_levels: Dictionary = dwarf.get("skill_levels")
		if skills.roll_bonus_yield(skill_levels, skill_id):
			DwarfResourcePileScript.collect_resource(dwarf, resource_name)


static func complete_couper_task(dwarf: Node3D, skill_id: String) -> void:
	var current_task: Dictionary = dwarf.get("current_task")
	var tree = current_task.get("tree")
	# Sprint 20 : chaque arbre porte son type de bois en metadonnee.
	var wood_type: String = "bois"
	if is_instance_valid(tree):
		wood_type = tree.get_meta("wood_resource", "bois")
		# Sprint 34 : tout le visuel de l'arbre vit dans des maillages
		# partages entre TOUS les arbres - il faut donc explicitement les
		# cacher ici, sinon ils restent visibles pour toujours meme apres
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


## Sprint 24ter : recolte un fruit/une baie sans detruire la cible - generique
## entre arbres fruitiers (Forest.gd) et buissons (BerryBushes.gd).
static func complete_cueillir_task(dwarf: Node3D, skill_id: String) -> void:
	var current_task: Dictionary = dwarf.get("current_task")
	var target: Node = current_task.get("tree")
	if is_instance_valid(target):
		var fruit_resource: String = target.get_meta("fruit_resource", "")
		var fruits_left: int = target.get_meta("fruits_left", 0)
		if fruit_resource != "" and fruits_left > 0:
			fruits_left = harvest_one_fruit(target, fruits_left)
			DwarfResourcePileScript.collect_resource(dwarf, fruit_resource)
			# Sprint 24septies : bonus de recolte (competence Agriculture),
			# limite aux fruits reellement encore disponibles sur la cible.
			var skills: DwarfSkillsScript = dwarf.get("skills")
			var skill_levels: Dictionary = dwarf.get("skill_levels")
			if fruits_left > 0 and skills.roll_bonus_yield(skill_levels, skill_id):
				harvest_one_fruit(target, fruits_left)
				DwarfResourcePileScript.collect_resource(dwarf, fruit_resource)


## Sprint 36 : contrairement a "miner", on ne retire rien de VoxelWorld -
## l'eau est une ressource renouvelable.
static func complete_puiser_task(dwarf: Node3D) -> void:
	DwarfResourcePileScript.collect_resource(dwarf, "eau")


## Sprint 24septies : retire un fruit de "target" (fruits_left-1 -> meta +
## suppression du noeud Fruit_%d correspondant), utilise pour la recolte de
## base et pour le fruit bonus eventuel. Renvoie le nouveau nombre de fruits
## restants.
static func harvest_one_fruit(target: Node, fruits_left: int) -> int:
	var new_count: int = fruits_left - 1
	target.set_meta("fruits_left", new_count)
	var fruit_node: Node = target.get_node_or_null("Fruit_%d" % new_count)
	if fruit_node:
		fruit_node.queue_free()
	return new_count
