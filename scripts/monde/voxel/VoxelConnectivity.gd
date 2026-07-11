extends RefCounted
## Connectivite (BFS "reachable") + escaliers - extrait de VoxelWorld.gd
## (revue de code C24, 2026-07-11 : fichier a 1438 lignes). Fonctions
## STATIQUES, aucun etat propre - VoxelWorld.gd garde la PROPRIETE de tous
## les dictionnaires (reachable/grid/stair_grid/stair_columns, passes ici
## par reference, GDScript ne les copie jamais implicitement) ainsi que des
## fonctions qui touchent a d'autre etat non passe directement
## (_remove_block_silent/clear_sol/rebuild_mesh, recues en Callable).


## Propage "reachable" par inondation (BFS) depuis "start" (deja vide et
## relie a la surface) a travers les cases vides adjacentes pas encore
## marquees. Voir VoxelWorld._mark_reachable_from pour le contexte complet
## (garde-fous ciel ouvert / SOL plancher fin).
static func mark_reachable_from(start: Vector3i, reachable: Dictionary, grid: Dictionary, directions: Array, empty_type: int, get_top_block_y_fn: Callable, get_sol_fn: Callable) -> void:
	if reachable.has(start):
		return
	var queue: Array = [start]
	reachable[start] = true
	while not queue.is_empty():
		var current: Vector3i = queue.pop_back()
		for dir in directions:
			var n: Vector3i = current + dir
			if reachable.has(n):
				continue
			if grid.get(n, empty_type) != empty_type:
				continue
			# Ne jamais suivre le ciel ouvert au-dessus d'une colonne (voir
			# VoxelWorld._mark_reachable_from - sans ce garde-fou, inondation
			# infinie / gel du jeu).
			if n.y > get_top_block_y_fn.call(n.x, n.z):
				continue
			# SOL = plancher fin, jamais traversable a la verticale.
			if dir.y > 0 and get_sol_fn.call(n) != empty_type:
				continue
			if dir.y < 0 and get_sol_fn.call(current) != empty_type:
				continue
			reachable[n] = true
			queue.append(n)


## Vrai si un nain peut atteindre ce bloc SOLIDE pour le miner maintenant -
## voir VoxelWorld.can_reach_block pour le contexte complet.
static func can_reach_block(x: int, y: int, z: int, reachable: Dictionary, directions: Array, empty_type: int, get_top_block_y_fn: Callable, get_sol_fn: Callable) -> bool:
	if y == get_top_block_y_fn.call(x, z):
		return true
	var pos := Vector3i(x, y, z)
	for dir in directions:
		var n: Vector3i = pos + dir
		if not reachable.has(n):
			continue
		if dir == Vector3i(0, 1, 0) and get_sol_fn.call(n) != empty_type:
			continue
		return true
	return false


## Cherche un escalier permettant d'atteindre "to_y" - voir
## VoxelWorld.find_connecting_stair pour le contexte complet.
static func find_connecting_stair(to_x: int, to_z: int, to_y: int, stair_columns: Dictionary) -> Dictionary:
	var candidates: Array = [Vector2i(to_x, to_z),
		Vector2i(to_x + 1, to_z), Vector2i(to_x - 1, to_z),
		Vector2i(to_x, to_z + 1), Vector2i(to_x, to_z - 1)]
	for col in candidates:
		var stair_range: Dictionary = stair_columns.get(col, {})
		if stair_range.is_empty():
			continue
		var top: int = int(stair_range["top"]) + 1
		var bottom: int = int(stair_range["bottom"])
		if to_y < bottom or to_y > top:
			continue
		return {"column": col, "top": top, "bottom": bottom}
	return {}


## Vrai si un nain peut marcher de "from_y" a "to_y" - voir
## VoxelWorld.can_walk_to_level pour le contexte complet.
static func can_walk_to_level(from_y: int, to_x: int, to_z: int, to_y: int, stair_columns: Dictionary) -> bool:
	if absi(from_y - to_y) <= 1:
		return true
	return not find_connecting_stair(to_x, to_z, to_y, stair_columns).is_empty()


## Creuse une colonne d'escalier sur plusieurs niveaux d'affilee - voir
## VoxelWorld.dig_stairs pour le contexte complet (piece "bas"/"haut"/
## "hautbas", fusion d'etendue existante). "clear_sol_fn"/
## "remove_block_silent_fn"/"rebuild_mesh_fn" restent des Callables vers
## VoxelWorld : ces 3 operations touchent a de l'etat non passe ici
## (vein_system, discovered, reachable...).
static func dig_stairs(x: int, z: int, top_y: int, bottom_y: int, grid: Dictionary, stair_grid: Dictionary, stair_columns: Dictionary, clear_sol_fn: Callable, remove_block_silent_fn: Callable, rebuild_mesh_fn: Callable) -> Dictionary:
	var resources: Dictionary = {}
	var single_level := top_y == bottom_y
	clear_sol_fn.call(Vector3i(x, top_y + 1, z))
	for y in range(top_y, bottom_y - 1, -1):
		var pos := Vector3i(x, y, z)
		if not grid.has(pos):
			continue
		var block_type: int = grid[pos]
		var resource_name: String = remove_block_silent_fn.call(x, y, z)
		if resource_name != "":
			resources[resource_name] = resources.get(resource_name, 0) + 1
		var piece_type: String
		if single_level:
			piece_type = "bas"
		elif y == top_y:
			piece_type = "bas"
		elif y == bottom_y:
			piece_type = "haut"
		else:
			piece_type = "hautbas"
		stair_grid[pos] = {"piece": piece_type, "material": block_type}
	var col_key := Vector2i(x, z)
	var existing_range: Dictionary = stair_columns.get(col_key, {})
	var merged_top: int = maxi(existing_range.get("top", top_y), top_y)
	var merged_bottom: int = mini(existing_range.get("bottom", bottom_y), bottom_y)
	stair_columns[col_key] = {"top": merged_top, "bottom": merged_bottom}
	rebuild_mesh_fn.call(true, maxi(0, bottom_y - 1), top_y + 1, maxi(0, x - 1), x + 1, maxi(0, z - 1), z + 1)
	return resources
