extends RefCounted
## 2026-07-06 (dette d'architecture A1, I60 - revue de code) : deplacement/
## steering/relief extraits mecaniquement de Dwarf.gd - fonctions inchangees,
## seule la signature change ("dwarf" recoit le Dwarf via parametre au lieu
## d'un "self" implicite, meme motif que DwarfVisuals.gd).
## Proprietes lues/ecrites via dwarf.get()/dwarf.set() (acces dynamique
## Godot, necessaire car "dwarf" est type generiquement Node3D, pas Dwarf).
## WATER_SLOWDOWN_FACTOR/SLOPE_SLOWDOWN_FACTOR/TREE_AVOID_RADIUS/
## TREE_AVOID_STRENGTH dupliques ci-dessous (les "const" ne sont pas visibles
## via get()) - a garder synchronises si les valeurs d'origine changent dans
## Dwarf.gd.

# Sprint 37 (backlog Phase 1 item 13c) : facteur applique a move_speed quand
# le nain traverse une case d'eau.
const WATER_SLOWDOWN_FACTOR := 0.4
# Sprint 38 (reliefs, "impacte le deplacement") : facteur applique en montee.
const SLOPE_SLOWDOWN_FACTOR := 0.6
# Sprint 37 (backlog Phase 1 item 13a) : evitement des arbres (steering).
const TREE_AVOID_RADIUS := 1.3
const TREE_AVOID_STRENGTH := 1.6

# 2026-07-06 (revue de code, paquet G, M55) : cache partage (static, donc
# commun a TOUS les nains) de la liste d'arbres, pour eviter de relire
# get_nodes_in_group("trees") a chaque frame et par nain en deplacement -
# voir _cached_trees() plus bas. Rafraichi au plus toutes les
# TREES_CACHE_REFRESH_INTERVAL secondes (les arbres ne bougent jamais, seule
# leur EXISTENCE change - coupe/repousse - donc un leger retard de quelques
# secondes avant qu'un arbre coupe/nouveau soit pris en compte par
# l'evitement est sans consequence visible).
const TREES_CACHE_REFRESH_INTERVAL := 2.0
static var _trees_cache: Array = []
static var _trees_cache_time_ms: int = -999999


## Deplacement generique reutilise par la marche normale et la recherche de
## nourriture/eau/case seche. Sprint 37 (item 13c, "l'eau ralentit la marche") :
## vitesse reduite tant que le nain se trouve sur une case d'eau. Sprint 37
## (item 13a, "les arbres sont non traversables") : pas de vraie navigation
## avec obstacles (aucun A* dans ce projet), mais une legere deviation de
## direction ("steering") qui ecarte le nain des troncs proches.
## 2026-07-06 (correctif) : nommee "advance_toward" (pas "move_toward") pour
## eviter une collision avec la fonction native Godot @GlobalScope.move_toward
## (from, to, delta) -> float - un appel non qualifie a "move_toward(...)"
## depuis ce meme fichier etait capte par la fonction native au lieu de
## celle-ci, provoquant une erreur de parsing (mauvais nombre/type d'arguments).
static func advance_toward(dwarf: Node3D, to_target: Vector3, distance: float, delta: float) -> void:
	var direction := to_target.normalized()
	var avoidance := tree_avoidance_offset(dwarf, direction)
	if avoidance != Vector3.ZERO:
		direction = (direction + avoidance).normalized()
	var move_speed: float = dwarf.get("move_speed")
	var effective_speed: float = move_speed
	if is_on_water(dwarf):
		effective_speed *= WATER_SLOWDOWN_FACTOR
	elif is_climbing(dwarf, direction):
		effective_speed *= SLOPE_SLOWDOWN_FACTOR
	var step: float = min(effective_speed * delta, distance)
	dwarf.global_position += direction * step
	# Sprint 38 (reliefs) : la hauteur suit desormais le relief case par case
	# (avant : y fige a ground_level, le nain "flottait"/"s'enfoncait" sur une
	# colline).
	dwarf.global_position.y = ground_y_at(dwarf, dwarf.global_position.x, dwarf.global_position.z)

	# Le modele 3D n'est plus un billboard : cette rotation tourne desormais
	# reellement le nain vers sa direction de deplacement.
	var target_yaw: float = atan2(direction.x, direction.z)
	var rotation_speed: float = dwarf.get("rotation_speed")
	dwarf.rotation.y = lerp_angle(dwarf.rotation.y, target_yaw, rotation_speed * delta)

	var dwarf_model: Node3D = dwarf.get("dwarf_model")
	dwarf_model.preview_animation = "Marche"


## Sprint 38 (reliefs) : hauteur du sol (sommet de colonne + 1) a une position
## XZ donnee. Repli sur ground_level si hors carte (get_top_block_y renvoie -1).
static func ground_y_at(dwarf: Node3D, x: float, z: float) -> float:
	var voxel_world: Node3D = dwarf.get("voxel_world")
	var top: int = voxel_world.get_top_block_y(int(floor(x)), int(floor(z)))
	if top < 0:
		return dwarf.get("ground_level")
	return float(top) + 1.0


## Sprint 38 (reliefs, "impacte le deplacement") : compare la hauteur du sol
## juste devant le nain (dans le sens de deplacement) a sa hauteur actuelle -
## effet simple, pas de vraie physique de pente.
static func is_climbing(dwarf: Node3D, direction: Vector3) -> bool:
	var ahead_x: float = dwarf.global_position.x + direction.x * 0.5
	var ahead_z: float = dwarf.global_position.z + direction.z * 0.5
	var here_y := ground_y_at(dwarf, dwarf.global_position.x, dwarf.global_position.z)
	var ahead_y := ground_y_at(dwarf, ahead_x, ahead_z)
	return ahead_y > here_y + 0.1


static func is_on_water(dwarf: Node3D) -> bool:
	var voxel_world: Node3D = dwarf.get("voxel_world")
	return voxel_world.is_water(int(floor(dwarf.global_position.x)), int(floor(dwarf.global_position.z)))


## 2026-07-06 (revue de code, paquet G, M55) : renvoie la liste d'arbres
## (groupe "trees"), rafraichie au plus toutes les
## TREES_CACHE_REFRESH_INTERVAL secondes au lieu d'un appel a
## get_nodes_in_group() a CHAQUE frame par CHAQUE nain en deplacement -
## demande explicite de Francois apres verification qu'un arbre coupe
## (tree.queue_free(), voir Forest.gd) est bien filtre via is_instance_valid()
## dans tree_avoidance_offset() ci-dessous, pour ne jamais utiliser une
## reference perimee restee dans le cache entre deux rafraichissements.
static func _cached_trees(dwarf: Node3D) -> Array:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _trees_cache_time_ms > int(TREES_CACHE_REFRESH_INTERVAL * 1000.0):
		_trees_cache = dwarf.get_tree().get_nodes_in_group("trees")
		_trees_cache_time_ms = now_ms
	return _trees_cache


## Sprint 37 (backlog Phase 1 item 13a) : les arbres n'ont pas de vraie
## collision/pathfinding, donc on approxime "traversable/non traversable" par
## une deviation de direction ("steering") qui repousse doucement le nain des
## troncs proches situes globalement devant lui.
static func tree_avoidance_offset(dwarf: Node3D, direction: Vector3) -> Vector3:
	# 2026-07-05 (correctif bug Couper/Cueillir) : l'arbre vise par la tache en
	# cours (couper/cueillir) est exclu de l'evitement - sinon le nain ne peut
	# jamais s'approcher a moins de TREE_AVOID_RADIUS (1.3) de SA PROPRE cible.
	var current_task: Dictionary = dwarf.get("current_task")
	var target_tree = null
	if current_task.get("type") in ["couper", "cueillir"]:
		target_tree = current_task.get("tree")
	var avoid := Vector3.ZERO
	for tree in _cached_trees(dwarf):
		# 2026-07-06 (paquet G, M55) : le cache peut contenir un arbre coupe
		# depuis (tree.queue_free() dans Forest.gd) jusqu'au prochain
		# rafraichissement - is_instance_valid() l'ignore plutot que de
		# planter sur une reference perimee.
		if not is_instance_valid(tree):
			continue
		if tree == target_tree:
			continue
		var to_tree: Vector3 = tree.global_position - dwarf.global_position
		to_tree.y = 0.0
		var dist: float = to_tree.length()
		if dist < 0.001 or dist > TREE_AVOID_RADIUS:
			continue
		if direction.dot(to_tree.normalized()) < 0.2:
			continue
		var push: Vector3 = dwarf.global_position - tree.global_position
		push.y = 0.0
		var weight: float = (TREE_AVOID_RADIUS - dist) / TREE_AVOID_RADIUS
		avoid += push.normalized() * weight * TREE_AVOID_STRENGTH
	return avoid


## Tire des positions au hasard sur la carte jusqu'a en trouver une qui n'est
## pas de l'eau (essais bornes par securite) ; repli sur le centre de la carte
## si vraiment aucune n'est trouvee.
static func find_dry_target(dwarf: Node3D) -> Vector3:
	var grid_width: int = dwarf.get("grid_width")
	var grid_depth: int = dwarf.get("grid_depth")
	var voxel_world: Node3D = dwarf.get("voxel_world")
	var guard := 0
	while guard < 20:
		var x := randf_range(1.0, float(grid_width - 1))
		var z := randf_range(1.0, float(grid_depth - 1))
		if not voxel_world.is_water(int(x), int(z)):
			return Vector3(x, ground_y_at(dwarf, x, z), z)
		guard += 1
	return Vector3(grid_width / 2.0, dwarf.get("ground_level"), grid_depth / 2.0)


static func process_seeking_dry_land(dwarf: Node3D, delta: float) -> void:
	var target_position: Vector3 = dwarf.get("target_position")
	var to_target: Vector3 = target_position - dwarf.global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance < 0.15 or not is_on_water(dwarf):
		dwarf.set("is_seeking_dry_land", false)
		dwarf.call("_start_resting")
		return
	advance_toward(dwarf, to_target, distance, delta)
