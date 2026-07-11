extends RefCounted
## Deplacement/steering/relief d'un nain, extrait de Dwarf.gd. Chaque
## fonction recoit le nain via un parametre "dwarf" (Node3D) plutot qu'un
## "self" implicite, et lit/ecrit ses proprietes via dwarf.get()/dwarf.set()
## (acces dynamique Godot, necessaire car "dwarf" est type generiquement
## Node3D, pas Dwarf).
## WATER_SLOWDOWN_FACTOR/LEVEL_CHANGE_SLOWDOWN_FACTOR/STAIR_SLOWDOWN_FACTOR/
## TREE_AVOID_RADIUS/TREE_AVOID_STRENGTH sont declarees ici (les "const" ne
## sont pas visibles via get(), elles doivent donc vivre la ou elles sont
## utilisees).

const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")

## Facteurs de vitesse = 1/cout - regles de pathing validees avec Francois le
## 2026-07-08 (voir memoire "Regles de pathing des nains") : plat=1, eau=3,
## denivele sans escalier=2, escalier=1.5.
const WATER_SLOWDOWN_FACTOR := 0.333        # eau (cout 3)
const LEVEL_CHANGE_SLOWDOWN_FACTOR := 0.5   # denivele d'1 niveau SANS escalier (cout 2) - montee ET descente
const STAIR_SLOWDOWN_FACTOR := 0.667        # sur une colonne d'escalier (cout 1.5)
const TREE_AVOID_RADIUS := 1.3      # evitement des arbres (steering)
const TREE_AVOID_STRENGTH := 1.6

## Cache partage (static, donc commun a TOUS les nains) des arbres, sous
## forme de GRILLE SPATIALE (Vector2i cellule -> Array d'arbres) plutot
## qu'une simple liste a plat : sur une grande carte (des milliers d'arbres),
## parcourir TOUTE la liste a chaque frame pour chaque nain en deplacement
## devenait le principal cout runtime (le nombre d'arbres croit avec la
## surface de la carte, contrairement au rayon d'evitement qui reste fixe -
## voir tree_avoidance_offset/TREE_AVOID_RADIUS). La grille permet de ne
## regarder que les arbres proches (cellule du nain + les 8 voisines) au
## lieu de la carte entiere. Rafraichie au plus toutes les
## TREES_CACHE_REFRESH_INTERVAL secondes : les arbres ne bougent jamais,
## seule leur existence change (coupe/repousse), donc un leger retard avant
## qu'un arbre coupe/nouveau soit pris en compte par l'evitement est sans
## consequence visible.
const TREES_CACHE_REFRESH_INTERVAL := 2.0
## Taille de cellule de la grille spatiale. Doit rester >= TREE_AVOID_RADIUS
## pour garantir qu'un arbre a moins de TREE_AVOID_RADIUS d'un nain se
## trouve forcement dans sa cellule ou l'une des 8 voisines (jamais plus
## loin) - voir _nearby_trees.
const TREE_GRID_CELL_SIZE := 2.0
static var _trees_grid: Dictionary = {}  # Vector2i (cellule) -> Array d'arbres
static var _trees_cache_time_ms: int = -999999


## Deplacement generique reutilise par la marche normale et la recherche de
## nourriture/eau/case seche. Vitesse reduite tant que le nain se trouve sur
## une case d'eau. Pas de vraie navigation avec obstacles (aucun A* dans ce
## projet), mais une legere deviation de direction ("steering") qui ecarte
## le nain des troncs proches.
## Nommee "advance_toward" (pas "move_toward") pour eviter une collision
## avec la fonction native Godot @GlobalScope.move_toward(from, to, delta)
## -> float : un appel non qualifie a "move_toward(...)" depuis ce meme
## fichier serait capte par la fonction native au lieu de celle-ci.
static func advance_toward(dwarf: Node3D, to_target: Vector3, distance: float, delta: float) -> void:
	var direction := to_target.normalized()
	var avoidance := tree_avoidance_offset(dwarf, direction)
	if avoidance != Vector3.ZERO:
		direction = (direction + avoidance).normalized()
	var move_speed: float = dwarf.get("move_speed")
	var effective_speed: float = move_speed
	if is_on_water(dwarf):
		effective_speed *= WATER_SLOWDOWN_FACTOR
	elif is_on_stairs(dwarf):
		effective_speed *= STAIR_SLOWDOWN_FACTOR
	elif is_changing_level(dwarf, direction):
		effective_speed *= LEVEL_CHANGE_SLOWDOWN_FACTOR
	var step: float = min(effective_speed * delta, distance)
	dwarf.global_position += direction * step
	# La hauteur suit le relief case par case (pas de y fige a ground_level).
	dwarf.global_position.y = ground_y_at(dwarf, dwarf.global_position.x, dwarf.global_position.z)

	# Rotation reelle du modele 3D vers sa direction de deplacement.
	var target_yaw: float = atan2(direction.x, direction.z)
	var rotation_speed: float = dwarf.get("rotation_speed")
	dwarf.rotation.y = lerp_angle(dwarf.rotation.y, target_yaw, rotation_speed * delta)

	var dwarf_model: Node3D = dwarf.get("dwarf_model")
	dwarf_model.preview_animation = "Marche"


## Hauteur du sol (sommet de colonne + 1) a une position XZ donnee. Repli
## sur ground_level si hors carte (get_top_block_y renvoie -1).
## Cas particulier "colonne d'escalier" (voir VoxelWorld.stair_columns) :
## dig_stairs() vide TOUS les niveaux de la colonne (top a bottom), donc
## get_top_block_y y renverrait desormais un niveau bien plus bas que
## l'entree reelle de l'escalier - sans ce cas particulier, un nain qui
## traverse simplement le dessus d'un escalier (sans tache de descente
## active, voir advance_vertical) glissait instantanement au FOND de tout
## escalier croise (bug remonte par Francois 2026-07-08 : "aucun nain ne
## descend pour creuser un couloir" - la vraie descente, elle, est geree a
## part par le systeme d'etapes de Dwarf.gd, pas par cette fonction).
static func ground_y_at(dwarf: Node3D, x: float, z: float) -> float:
	var voxel_world: Node3D = dwarf.get("voxel_world")
	var xi := int(floor(x))
	var zi := int(floor(z))
	var stair_range: Dictionary = voxel_world.get_stair_range(xi, zi)
	if not stair_range.is_empty():
		return float(stair_range["top"]) + 1.0
	var top: int = voxel_world.get_top_block_y(xi, zi)
	if top < 0:
		return dwarf.get("ground_level")
	return float(top) + 1.0


## Vrai si le nain se trouve actuellement sur une colonne d'escalier -
## utilise pour appliquer STAIR_SLOWDOWN_FACTOR plutot que
## LEVEL_CHANGE_SLOWDOWN_FACTOR lors d'une traversee normale (hors descente
## active).
static func is_on_stairs(dwarf: Node3D) -> bool:
	var voxel_world: Node3D = dwarf.get("voxel_world")
	var pos: Vector3 = dwarf.global_position
	return not voxel_world.get_stair_range(int(floor(pos.x)), int(floor(pos.z))).is_empty()


## Compare la hauteur du sol juste devant le nain (dans le sens de
## deplacement) a sa hauteur actuelle - effet simple, pas de vraie physique
## de pente. Detecte un changement de niveau dans les DEUX sens (montee ET
## descente, regle 5 : meme cout pour les deux) - anciennement nommee
## "is_climbing" et ne detectait que la montee.
static func is_changing_level(dwarf: Node3D, direction: Vector3) -> bool:
	var ahead_x: float = dwarf.global_position.x + direction.x * 0.5
	var ahead_z: float = dwarf.global_position.z + direction.z * 0.5
	var here_y := ground_y_at(dwarf, dwarf.global_position.x, dwarf.global_position.z)
	var ahead_y := ground_y_at(dwarf, ahead_x, ahead_z)
	return absf(ahead_y - here_y) > 0.1


static func is_on_water(dwarf: Node3D) -> bool:
	var voxel_world: Node3D = dwarf.get("voxel_world")
	return voxel_world.is_water(int(floor(dwarf.global_position.x)), int(floor(dwarf.global_position.z)))


## Descente/montee dediee d'un escalier (voir Dwarf.gd, mode "stair_descent")
## - purement verticale, XZ fige au centre de la colonne d'escalier pendant
## tout le mouvement. Necessaire car advance_toward ignore totalement l'axe
## Y pour savoir si le nain est "arrive" (to_target.y = 0.0 dans Dwarf.gd) -
## un point intermediaire a la meme position XZ mais un Y different serait
## sinon considere atteint instantanement, sautant tout le cout de temps de
## l'escalier (STAIR_SLOWDOWN_FACTOR, cout 1.5). Renvoie true une fois le Y
## cible atteint.
static func advance_vertical(dwarf: Node3D, target_position: Vector3, delta: float) -> bool:
	dwarf.global_position.x = target_position.x
	dwarf.global_position.z = target_position.z
	var move_speed: float = dwarf.get("move_speed")
	var step: float = move_speed * STAIR_SLOWDOWN_FACTOR * delta
	var current_y: float = dwarf.global_position.y
	var diff: float = target_position.y - current_y
	var dwarf_model: Node3D = dwarf.get("dwarf_model")
	dwarf_model.preview_animation = "Marche"
	if absf(diff) <= step:
		dwarf.global_position.y = target_position.y
		return true
	dwarf.global_position.y = current_y + signf(diff) * step
	return false


## Deplacement horizontal a Y FIGE (voir Dwarf.gd, mode "underground") -
## utilise pour la derniere etape vers une cible en sous-sol, une fois
## l'escalier descendu : get_top_block_y ne peut pas servir de reference la
## (le "plafond" reste intact au-dessus d'un couloir mine, voir doc de
## VoxelWorld._remove_block_silent - la colonne semble donc encore pleine
## bien plus haut). Le Y correct est deja connu (celui atteint au bas de
## l'escalier) et reste fixe pendant toute cette derniere approche, au lieu
## d'etre recalcule via ground_y_at comme le fait advance_toward.
static func advance_toward_fixed_y(dwarf: Node3D, to_target: Vector3, distance: float, delta: float, fixed_y: float) -> void:
	var direction := to_target.normalized()
	var move_speed: float = dwarf.get("move_speed")
	var step: float = min(move_speed * delta, distance)
	dwarf.global_position += direction * step
	dwarf.global_position.y = fixed_y
	var target_yaw: float = atan2(direction.x, direction.z)
	var rotation_speed: float = dwarf.get("rotation_speed")
	dwarf.rotation.y = lerp_angle(dwarf.rotation.y, target_yaw, rotation_speed * delta)
	var dwarf_model: Node3D = dwarf.get("dwarf_model")
	dwarf_model.preview_animation = "Marche"


## Calcule les etapes intermediaires necessaires pour qu'un nain rejoigne
## une tache "miner" dont la cible peut etre en sous-sol (regles 1 et 4,
## voir memoire "Regles de pathing des nains") - Array de
## {"position":Vector3, "mode":"surface"/"stair_descent"/"underground"}, ou
## [] si aucune etape intermediaire n'est necessaire (denivele naturel d'au
## plus 1 niveau, ou tache sans notion de profondeur). Portee volontairement
## limitee a UN SEUL escalier direct par trajet. Le blocage "aucun escalier
## connectant" (regle 4, denivele >1 niveau) est verifie EN AMONT par
## TaskQueue.pop_nearest_task (voir VoxelWorld.can_walk_to_level) - cette
## tache n'aurait donc pas du etre assignee dans ce cas ; le repli "aucune
## etape" ci-dessous n'est qu'une securite qui ne devrait jamais s'activer
## en pratique.
static func compute_task_waypoints(dwarf: Node3D, task: Dictionary) -> Array:
	if task.get("type", "") != "miner":
		return []
	var voxel_world: Node3D = dwarf.get("voxel_world")
	var bx: int = task["bx"]
	var bz: int = task["bz"]
	var target_level: int = task["by"]
	var current_level: int = int(round(dwarf.global_position.y))
	if absi(current_level - target_level) > 1:
		var stair: Dictionary = voxel_world.find_connecting_stair(bx, bz, target_level)
		if not stair.is_empty():
			var col: Vector2i = stair["column"]
			var stair_top_pos := Vector3(col.x + 0.5, float(stair["top"]), col.y + 0.5)
			var stair_bottom_pos := Vector3(col.x + 0.5, float(stair["bottom"]), col.y + 0.5)
			var target_pos := Vector3(bx + 0.5, float(target_level), bz + 0.5)
			return [
				{"position": stair_top_pos, "mode": "surface"},
				{"position": stair_bottom_pos, "mode": "stair_descent"},
				{"position": target_pos, "mode": "underground"},
			]
		return []
	# Couloir (la case visee n'est PAS le vrai sommet de sa colonne, voir
	# VoxelWorld.can_reach_block) : passer d'abord par la case DEJA OUVERTE
	# qui donne acces, jamais foncer en ligne droite vers la cible - sinon le
	# trajet traverse le terrain intact au-dessus (le SOL de surface, encore
	# plein tout du long) et ne plonge qu'au tout dernier instant, donnant
	# l'impression fausse de creuser depuis le ciel (Francois 2026-07-10,
	# bug remonte : "il creuse a travers le SOL de la surface, ce qui est
	# interdit"). Un "trou" classique (cible = vrai sommet de colonne) n'a
	# jamais besoin de ce detour : il se creuse toujours depuis la surface.
	if target_level != voxel_world.get_top_block_y(bx, bz):
		var entry: Vector3i = _find_entry_neighbor(voxel_world, bx, target_level, bz)
		var target_cell := Vector3i(bx, target_level, bz)
		if entry != target_cell:
			var entry_pos := Vector3(entry.x + 0.5, float(entry.y), entry.z + 0.5)
			var target_pos2 := Vector3(bx + 0.5, float(target_level), bz + 0.5)
			return [
				{"position": entry_pos, "mode": "surface"},
				{"position": target_pos2, "mode": "underground"},
			]
	return []


## Cherche, parmi les 6 voisins de la case a miner (bx,by,bz), une case DEJA
## OUVERTE et accessible (meme regle que VoxelWorld.can_reach_block : un SOL
## bloque l'acces par le dessus) - c'est par LA qu'un nain doit passer pour
## miner un couloir. Renvoie Vector3i(bx,by,bz) lui-meme si aucune case
## d'entree n'est trouvee (repli - ne devrait pas arriver en pratique, la
## tache n'aurait pas du etre assignee sinon, voir can_reach_block).
static func _find_entry_neighbor(voxel_world: Node3D, bx: int, by: int, bz: int) -> Vector3i:
	var target := Vector3i(bx, by, bz)
	var dirs := [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
		Vector3i(0, -1, 0), Vector3i(0, 1, 0),
	]
	for dir in dirs:
		var n: Vector3i = target + dir
		if not voxel_world.reachable.has(n):
			continue
		if dir == Vector3i(0, 1, 0) and voxel_world.get_sol(n) != VoxelWorldScript.BlockType.EMPTY:
			continue
		return n
	return target


## Cellule de grille (voir _trees_grid/TREE_GRID_CELL_SIZE) contenant une
## position XZ donnee.
static func _tree_cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / TREE_GRID_CELL_SIZE)), int(floor(pos.z / TREE_GRID_CELL_SIZE)))


## Reconstruit entierement _trees_grid a partir du groupe "trees" - appele au
## plus toutes les TREES_CACHE_REFRESH_INTERVAL secondes (voir
## _nearby_trees), jamais a chaque frame.
static func _rebuild_trees_grid(dwarf: Node3D) -> void:
	_trees_grid.clear()
	for tree in dwarf.get_tree().get_nodes_in_group("trees"):
		var cell := _tree_cell(tree.global_position)
		if not _trees_grid.has(cell):
			_trees_grid[cell] = []
		_trees_grid[cell].append(tree)


## Renvoie uniquement les arbres proches d'un nain (sa cellule + les 8
## voisines, ce qui couvre tout TREE_AVOID_RADIUS - voir
## TREE_GRID_CELL_SIZE) au lieu de la liste complete des arbres de la carte.
## La grille elle-meme n'est rafraichie qu'au plus toutes les
## TREES_CACHE_REFRESH_INTERVAL secondes.
static func _nearby_trees(dwarf: Node3D) -> Array:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _trees_cache_time_ms > int(TREES_CACHE_REFRESH_INTERVAL * 1000.0):
		_rebuild_trees_grid(dwarf)
		_trees_cache_time_ms = now_ms
	var center: Vector2i = _tree_cell(dwarf.global_position)
	var nearby: Array = []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cell: Vector2i = center + Vector2i(dx, dz)
			if _trees_grid.has(cell):
				nearby.append_array(_trees_grid[cell])
	return nearby


## Les arbres n'ont pas de vraie collision/pathfinding, donc on approxime
## "traversable/non traversable" par une deviation de direction ("steering")
## qui repousse doucement le nain des troncs proches situes globalement
## devant lui.
static func tree_avoidance_offset(dwarf: Node3D, direction: Vector3) -> Vector3:
	# L'arbre vise par la tache en cours (couper/cueillir) est exclu de
	# l'evitement - sinon le nain ne pourrait jamais s'approcher a moins de
	# TREE_AVOID_RADIUS de SA PROPRE cible.
	var current_task: Dictionary = dwarf.get("current_task")
	var target_tree = null
	if current_task.get("type") in ["couper", "cueillir"]:
		target_tree = current_task.get("tree")
	var avoid := Vector3.ZERO
	for tree in _nearby_trees(dwarf):
		# Le cache peut contenir un arbre coupe depuis (tree.queue_free()
		# dans Forest.gd) jusqu'au prochain rafraichissement -
		# is_instance_valid() l'ignore plutot que de planter sur une
		# reference perimee.
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
	# Flux GameRandom dedie ("nains_deplacement") plutot que le RNG global -
	# reproductibilite par graine, meme flux que Dwarf._pick_new_target
	# (revue de code M84).
	var rng: RandomNumberGenerator = GameRandom.get_rng("nains_deplacement")
	var guard := 0
	while guard < 20:
		var x := rng.randf_range(1.0, float(grid_width - 1))
		var z := rng.randf_range(1.0, float(grid_depth - 1))
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
