extends RefCounted
## Tas de ressources au sol + couleur des ressources, extrait de Dwarf.gd.
## Chaque fonction recoit le nain via un parametre "dwarf" (Node3D) plutot
## qu'un "self" implicite, et lit/ecrit ses proprietes via
## dwarf.get()/dwarf.set() (acces dynamique Godot, necessaire car "dwarf"
## est type generiquement Node3D, pas Dwarf).
## resource_color() est une fonction pure (pas de "dwarf" necessaire) -
## reutilisee par DwarfNeeds.gd (teinte de l'indicateur de repas).

const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
const TreeSpecies := preload("res://scripts/data/materiaux/types/bois/TreeSpecies.gd")
const BerryTypes := preload("res://scripts/data/materiaux/types/baies/BerryTypes.gd")
const NightDarkenScript := preload("res://scripts/systemes/NightDarken.gd")

const PILE_MERGE_RADIUS := 1.2
const PILE_MAX_SCALE := 1.8

## Stock de bois de depart au lancement d'une partie, pour pouvoir tester la
## construction sans attendre d'avoir coupe des arbres. Rayon reduit pour
## que les tas restent groupes pres du point de spawn (garanti hors eau,
## voir VoxelWorld.colony_spawn_center), plus faciles a reperer qu'eparpilles.
const STARTING_WOOD_PILE_COUNT := 4
const STARTING_WOOD_PILE_SIZE := 25
const STARTING_WOOD_SPAWN_RADIUS := 4.0

## Meme teinte nocturne que CloudSystem.gd/WaterfallFoamClouds.gd, appliquee
## aux materiaux UNSHADED de ce fichier.
const NIGHT_TINT := Color(0.10, 0.11, 0.16)
const NIGHT_DARKEN_STRENGTH := 0.8


## Ajoute la ressource a l'inventaire et fait apparaitre/grossir un tas au
## sol. Le tas est une vraie entite (groupe "resource_piles", meta
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


## Cree STARTING_WOOD_PILE_COUNT tas de bois de STARTING_WOOD_PILE_SIZE
## chacun, disperses autour de "center" (point de spawn des nains) en
## evitant l'eau (meme motif que Forest._pick_dry_position), avec un flux
## GameRandom dedie ("stock_depart") pour rester deterministe a graine
## egale. Essence tiree au hasard PAR TAS parmi toutes les especes d'arbres
## du jeu (bois "normal" ET fruitier). Appele une seule fois par
## VoxelWorld._ready(), apres generation du terrain (voxel_world.is_water/
## get_top_block_y doivent deja repondre correctement).
static func spawn_starting_wood_stock(parent: Node3D, voxel_world: Node3D, inventory: Node, center: Vector2) -> void:
	if voxel_world == null or inventory == null:
		push_warning("DwarfResourcePile.spawn_starting_wood_stock : voxel_world ou inventory introuvable, stock de depart non cree.")
		return
	var wood_resources: Array = []
	for species in TreeSpecies.SPECIES:
		wood_resources.append(species["wood_resource"])
	for species in TreeSpecies.FRUIT_SPECIES:
		wood_resources.append(species["wood_resource"])
	var rng: RandomNumberGenerator = GameRandom.get_rng("stock_depart")
	for i in range(STARTING_WOOD_PILE_COUNT):
		var x: float = center.x
		var z: float = center.y
		var guard := 0
		while guard < 20:
			var angle := rng.randf_range(0.0, TAU)
			var dist := rng.randf_range(1.5, STARTING_WOOD_SPAWN_RADIUS)
			x = center.x + cos(angle) * dist
			z = center.y + sin(angle) * dist
			if not voxel_world.is_water(int(x), int(z)):
				break
			guard += 1
		var resource_name: String = wood_resources[rng.randi_range(0, wood_resources.size() - 1)]
		var top: int = voxel_world.get_top_block_y(int(x), int(z))
		var y: float = float(top) + 1.0 if top >= 0 else 0.0
		var pile := Node3D.new()
		pile.position = Vector3(x, y, z)
		pile.add_to_group("resource_piles")
		pile.set_meta("resource_name", resource_name)
		pile.set_meta("count", STARTING_WOOD_PILE_SIZE)
		pile.scale = Vector3.ONE * clampf(1.0 + float(STARTING_WOOD_PILE_SIZE) * 0.03, 1.0, PILE_MAX_SCALE)
		# "parent" est encore en train d'entrer dans l'arbre de scene au
		# moment de cet appel (VoxelWorld._ready tourne avant que son propre
		# parent ait fini son _ready) - add_child() direct echouerait avec
		# "Parent node is busy setting up children". call_deferred() reporte
		# l'ajout au prochain traitement d'image, une fois l'arbre stable.
		parent.add_child.call_deferred(pile)
		build_pile_visual(pile, resource_name)
		inventory.add_resource(resource_name, STARTING_WOOD_PILE_SIZE)
		if OS.is_debug_build():
			print("[Stock depart] pile %d/%d creee : %s x%d a (%.1f, %.1f, %.1f), dans l'eau ? %s" % [i + 1, STARTING_WOOD_PILE_COUNT, resource_name, STARTING_WOOD_PILE_SIZE, x, y, z, voxel_world.is_water(int(x), int(z))])
		# Le compteur GENERIQUE "bois" (seul lu par la construction et le
		# StatsLabel, voir ActionController._update_stats_label) doit aussi
		# etre alimente en plus du compteur par essence ci-dessus.
		if resource_name != "bois":
			inventory.add_resource("bois", STARTING_WOOD_PILE_SIZE)


## Petit tas de 3-4 morceaux colores pose au sol a l'endroit de la recolte -
## visuel construit une seule fois a la creation du tas.
static func build_pile_visual(pile: Node3D, resource_name: String) -> void:
	var color := resource_color(resource_name)
	# Assombrissement nocturne applique une seule fois a la construction
	# (avant la branche bois, qui retourne tot, pour couvrir aussi
	# build_wood_bundle_visual) - ce tas ne continuera pas a s'assombrir/
	# eclaircir tout seul apres coup, contrairement aux nuages qui ont leur
	# propre _process() (voir limite documentee en tete de NightDarken.gd).
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


## Le bois recolte est represente par un fagot de rondins (cylindres
## couches, groupes en botte compacte) plutot que par les petits cubes
## generiques utilises pour les autres ressources.
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
			# Metaux/pierres precieuses recoltes en filon - couleur reprise
			# directement de MetalTypes.gd/GemTypes.gd (via VeinMaterials).
			var vein: Dictionary = VeinMaterials.get_type(resource_name)
			if not vein.is_empty():
				return vein["couleur"]
			# Fruits d'arbres et baies.
			var berry: Dictionary = BerryTypes.get_type(resource_name)
			if not berry.is_empty():
				return berry["couleur"]
			if TreeSpecies.is_fruit(resource_name):
				return TreeSpecies.fruit_color_for(resource_name)
			return Color(1, 1, 1)
