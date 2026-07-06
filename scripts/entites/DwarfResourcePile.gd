extends RefCounted
## 2026-07-06 (dette d'architecture A1, I60 - revue de code) : tas de
## ressources au sol + couleur des ressources, extraits mecaniquement de
## Dwarf.gd - fonctions inchangees, seule la signature change ("dwarf" recoit
## le Dwarf via parametre au lieu d'un "self" implicite, meme motif que
## DwarfVisuals.gd/DwarfMovement.gd/DwarfNeeds.gd).
## Proprietes lues/ecrites via dwarf.get()/dwarf.set() (acces dynamique
## Godot, necessaire car "dwarf" est type generiquement Node3D, pas Dwarf).
## resource_color() est une fonction pure (pas de "dwarf" necessaire) -
## reutilisee par DwarfNeeds.gd (teinte de l'indicateur de repas).

const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
const TreeSpecies := preload("res://scripts/data/materiaux/types/bois/TreeSpecies.gd")
const BerryTypes := preload("res://scripts/data/materiaux/types/baies/BerryTypes.gd")
const NightDarkenScript := preload("res://scripts/systemes/NightDarken.gd")

# Sprint 37 (backlog Phase 1 items 10/11, "piles d'objets")
const PILE_MERGE_RADIUS := 1.2
const PILE_MAX_SCALE := 1.8

# 2026-07-06 (revue de code, paquet H, I65) : materiaux UNSHADED de ce fichier
# (SHADING_MODE_UNSHADED, voir plus bas) - meme teinte nocturne que CloudSystem.gd/
# WaterfallFoamClouds.gd (Sprint 44).
const NIGHT_TINT := Color(0.10, 0.11, 0.16)
const NIGHT_DARKEN_STRENGTH := 0.8


## Ajoute la ressource a l'inventaire et fait apparaitre/grossir un tas au sol.
## Sprint 37 : le tas est une vraie entite (groupe "resource_piles", meta
## resource_name/count) - les recoltes proches du meme type fusionnent dans
## le meme tas au lieu de creer un nouveau tas a chaque fois.
static func collect_resource(dwarf: Node3D, resource_name: String) -> void:
	var inventory: Node = dwarf.get("inventory")
	inventory.add_resource(resource_name, 1)
	add_to_resource_pile(dwarf, resource_name, dwarf.global_position)
	if OS.is_debug_build():
		print("Recolte : +1 %s (total %d)" % [resource_name, inventory.get_count(resource_name)])


## Cherche un tas existant du meme type de ressource a proximite ; l'agrandit
## et incremente son compteur si trouve, sinon en cree un nouveau.
static func add_to_resource_pile(dwarf: Node3D, resource_name: String, pos: Vector3) -> void:
	var pile: Node3D = find_nearby_pile(dwarf, resource_name, pos)
	if pile != null:
		var count: int = int(pile.get_meta("count")) + 1
		pile.set_meta("count", count)
		pile.scale = Vector3.ONE * clampf(1.0 + float(count) * 0.03, 1.0, PILE_MAX_SCALE)
		return
	pile = Node3D.new()
	pile.position = pos
	pile.add_to_group("resource_piles")
	pile.set_meta("resource_name", resource_name)
	pile.set_meta("count", 1)
	dwarf.get_parent().add_child(pile)
	build_pile_visual(pile, resource_name)


static func find_nearby_pile(dwarf: Node3D, resource_name: String, pos: Vector3) -> Node3D:
	for pile in dwarf.get_tree().get_nodes_in_group("resource_piles"):
		if String(pile.get_meta("resource_name")) != resource_name:
			continue
		if pile.global_position.distance_to(pos) <= PILE_MERGE_RADIUS:
			return pile
	return null


## Petit tas de 3-4 morceaux colores pose au sol a l'endroit de la recolte -
## visuel construit une seule fois a la creation du tas.
static func build_pile_visual(pile: Node3D, resource_name: String) -> void:
	var color := resource_color(resource_name)
	# 2026-07-06 (revue de code, paquet H, I65/A2) : assombrissement nocturne
	# applique UNE FOIS a la construction, avant la branche bois (qui retourne
	# tot) pour couvrir aussi build_wood_bundle_visual - voir limite
	# documentee en tete de NightDarken.gd : ce tas ne continuera pas a
	# s'assombrir/eclaircir tout seul apres coup, contrairement aux nuages qui
	# ont leur propre _process().
	var night_factor: float = NightDarkenScript.night_factor(pile.get_node_or_null("%DayNightCycle"))
	color = NightDarkenScript.apply(color, night_factor, NIGHT_TINT, NIGHT_DARKEN_STRENGTH)
	if resource_name.begins_with("bois"):
		build_wood_bundle_visual(pile, color)
		return
	var chunk_count := randi_range(3, 4)
	for i in range(chunk_count):
		var chunk := MeshInstance3D.new()
		var box := BoxMesh.new()
		var size: float = randf_range(0.12, 0.20)
		box.size = Vector3(size, size * 0.7, size)
		chunk.mesh = box
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(0.0, 0.12)
		chunk.position = Vector3(cos(angle) * dist, size * 0.35, sin(angle) * dist)
		chunk.rotation.y = randf_range(0.0, TAU)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		chunk.set_surface_override_material(0, mat)
		pile.add_child(chunk)


## 2026-07-05 (demande explicite Francois) : le bois recolte est represente
## par un fagot de rondins (cylindres couches, groupes en botte compacte)
## plutot que par les petits cubes generiques.
static func build_wood_bundle_visual(pile: Node3D, color: Color) -> void:
	var log_count := randi_range(5, 7)
	var log_radius := 0.09
	var log_length := 0.55
	for i in range(log_count):
		var log_inst := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = log_radius
		cyl.bottom_radius = log_radius
		cyl.height = log_length
		log_inst.mesh = cyl
		# Rondins couches (rotation de 90 sur Z), alignes cote a cote pour
		# former une botte compacte, avec une legere variation aleatoire.
		var offset_side := (float(i) - float(log_count - 1) / 2.0) * (log_radius * 1.6)
		var offset_along := randf_range(-0.05, 0.05)
		var offset_up := randf_range(0.0, 0.05)
		log_inst.position = Vector3(offset_along, log_radius + offset_up, offset_side)
		log_inst.rotation = Vector3(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05), PI / 2.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color * randf_range(0.85, 1.15)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		log_inst.set_surface_override_material(0, mat)
		pile.add_child(log_inst)


static func resource_color(resource_name: String) -> Color:
	if resource_name.begins_with("bois"):  # "bois", "bois_chene", "bois_sapin", "bois_bouleau"
		return Color(0.4, 0.25, 0.1)
	match resource_name:
		"pierre":
			return Color(0.55, 0.55, 0.55)
		"terre":
			return Color(0.35, 0.25, 0.15)
		"eau":
			return Color(0.25, 0.55, 0.85)
		_:
			# Sprint 23 : metaux/pierres precieuses recoltes en filon - couleur
			# reprise directement de MetalTypes.gd/GemTypes.gd (via VeinMaterials).
			var vein: Dictionary = VeinMaterials.get_type(resource_name)
			if not vein.is_empty():
				return vein["couleur"]
			# Sprint 24ter/quater : fruits d'arbres et baies.
			var berry: Dictionary = BerryTypes.get_type(resource_name)
			if not berry.is_empty():
				return berry["couleur"]
			if TreeSpecies.is_fruit(resource_name):
				return TreeSpecies.fruit_color_for(resource_name)
			return Color(1, 1, 1)
