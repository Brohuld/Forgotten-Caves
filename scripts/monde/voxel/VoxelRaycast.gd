extends RefCounted
## Raycast voxel (raymarching) + description de case ciblee - extrait de
## VoxelWorld.gd (revue de code C24, 2026-07-11 : fichier a 1438 lignes).
## Fonctions STATIQUES, aucun etat propre - tout etat lu (grid/discovered/
## sol_grid/view_level...) est passe en parametre par VoxelWorld.gd ; les
## seules fonctions qui font plus qu'une simple lecture de dictionnaire
## (get_top_block_y/get_sol/_block_type_info_at) restent des Callables vers
## VoxelWorld, pour ne jamais dupliquer leur logique ici.


## Lance un rayon et renvoie la premiere face de bloc REELLEMENT VISIBLE a
## l'ecran qu'il touche (algorithme d'Amanatides-Woo) - voir
## VoxelWorld.raycast_visible_face pour le contexte complet (regles de
## visibilite, format du Dictionary renvoye, "cell"/"entered_dir").
static func raycast_visible_face(ray_origin: Vector3, ray_dir: Vector3, view_level: int, width: int, depth: int, build_ceiling: int, grid: Dictionary, discovered: Dictionary, sol_grid: Dictionary, directions: Array, empty_type: int, get_top_block_y_fn: Callable, get_sol_fn: Callable) -> Variant:
	var y_max: int = mini(view_level, build_ceiling - 1)
	if y_max < 0 or width <= 0 or depth <= 0:
		return null
	var box_min := Vector3(0.0, 0.0, 0.0)
	var box_max := Vector3(float(width), float(y_max) + 1.0, float(depth))

	# Intersection rayon/boite englobante (methode des "slabs").
	var t_enter: float = -INF
	var t_exit: float = INF
	var entry_axis: int = -1
	for axis in range(3):
		var o: float = ray_origin[axis]
		var d: float = ray_dir[axis]
		var mn: float = box_min[axis]
		var mx: float = box_max[axis]
		if absf(d) < 0.000001:
			if o < mn or o > mx:
				return null
			continue
		var t1: float = (mn - o) / d
		var t2: float = (mx - o) / d
		var axis_enter: float = t1
		var axis_exit: float = t2
		if t1 > t2:
			axis_enter = t2
			axis_exit = t1
		if axis_enter > t_enter:
			t_enter = axis_enter
			entry_axis = axis
		if axis_exit < t_exit:
			t_exit = axis_exit
	if t_enter > t_exit or t_exit < 0.0:
		return null

	var t_start: float = maxf(t_enter, 0.0) + 0.0001
	var start: Vector3 = ray_origin + ray_dir * t_start
	var ix: int = clampi(int(floor(start.x)), 0, width - 1)
	var iy: int = clampi(int(floor(start.y)), 0, y_max)
	var iz: int = clampi(int(floor(start.z)), 0, depth - 1)

	var step_x: int = 1 if ray_dir.x > 0.0 else (-1 if ray_dir.x < 0.0 else 0)
	var step_y: int = 1 if ray_dir.y > 0.0 else (-1 if ray_dir.y < 0.0 else 0)
	var step_z: int = 1 if ray_dir.z > 0.0 else (-1 if ray_dir.z < 0.0 else 0)

	var t_max_x: float = INF
	var t_max_y: float = INF
	var t_max_z: float = INF
	var t_delta_x: float = INF
	var t_delta_y: float = INF
	var t_delta_z: float = INF
	if step_x != 0:
		t_delta_x = absf(1.0 / ray_dir.x)
		t_max_x = (float(ix + (1 if step_x > 0 else 0)) - ray_origin.x) / ray_dir.x
	if step_y != 0:
		t_delta_y = absf(1.0 / ray_dir.y)
		t_max_y = (float(iy + (1 if step_y > 0 else 0)) - ray_origin.y) / ray_dir.y
	if step_z != 0:
		t_delta_z = absf(1.0 / ray_dir.z)
		t_max_z = (float(iz + (1 if step_z > 0 else 0)) - ray_origin.z) / ray_dir.z

	# Direction d'entree de la toute premiere case, deduite de l'axe qui a
	# determine t_enter - repli sur _has_any_exposed_face si aucune (camera
	# deja a l'interieur du volume visible, cas rare).
	var entered_dir := Vector3i.ZERO
	if t_enter > 0.0:
		if entry_axis == 0:
			entered_dir = Vector3i(-step_x, 0, 0)
		elif entry_axis == 1:
			entered_dir = Vector3i(0, -step_y, 0)
		elif entry_axis == 2:
			entered_dir = Vector3i(0, 0, -step_z)

	var max_steps: int = width + depth + y_max + 4
	for i in range(max_steps):
		var pos := Vector3i(ix, iy, iz)
		var type: int = grid.get(pos, empty_type)
		if type != empty_type:
			if iy == view_level:
				return {"hit": Vector3(float(ix) + 0.5, float(iy) + 0.5, float(iz) + 0.5), "cell": pos, "entered_dir": entered_dir}
			elif discovered.has(pos):
				var exposed: bool
				if entered_dir == Vector3i.ZERO:
					exposed = _has_any_exposed_face(pos, grid, directions, empty_type)
				else:
					exposed = grid.get(pos + entered_dir, empty_type) == empty_type
				if exposed:
					return {"hit": Vector3(float(ix) + 0.5, float(iy) + 0.5, float(iz) + 0.5), "cell": pos, "entered_dir": entered_dir}
		else:
			# Case VIDE : peut porter un SOL SEUL (herbe naturelle ou fond de
			# trou) - le rayon doit s'arreter ici plutot que de traverser
			# jusqu'au vrai CUBE solide en dessous (voir doc complete sur
			# VoxelWorld.raycast_visible_face).
			if iy <= view_level:
				if sol_grid.has(pos):
					return {"hit": Vector3(float(ix) + 0.5, float(iy) + 0.5, float(iz) + 0.5), "cell": pos, "entered_dir": entered_dir}
				var top_y: int = get_top_block_y_fn.call(ix, iz)
				if top_y >= 0 and iy == top_y + 1 and discovered.has(Vector3i(ix, top_y, iz)) and get_sol_fn.call(pos) != empty_type:
					return {"hit": Vector3(float(ix) + 0.5, float(iy) + 0.5, float(iz) + 0.5), "cell": pos, "entered_dir": entered_dir}

		# Avance a la case voxel suivante le long du rayon (DDA).
		if t_max_x < t_max_y and t_max_x < t_max_z:
			ix += step_x
			t_max_x += t_delta_x
			entered_dir = Vector3i(-step_x, 0, 0)
			if t_max_x > t_exit:
				break
		elif t_max_y < t_max_z:
			iy += step_y
			t_max_y += t_delta_y
			entered_dir = Vector3i(0, -step_y, 0)
			if t_max_y > t_exit:
				break
		else:
			iz += step_z
			t_max_z += t_delta_z
			entered_dir = Vector3i(0, 0, -step_z)
			if t_max_z > t_exit:
				break
		if ix < 0 or ix >= width or iy < 0 or iy > y_max or iz < 0 or iz >= depth:
			break

	return null


## Repli pour raycast_visible_face quand la direction d'entree d'une case
## n'est pas connue - vraie si AU MOINS une des 6 faces est naturellement
## exposee (voisin vide dans la grille).
static func _has_any_exposed_face(pos: Vector3i, grid: Dictionary, directions: Array, empty_type: int) -> bool:
	for dir in directions:
		if grid.get(pos + dir, empty_type) == empty_type:
			return true
	return false


## Decrit la case exacte visee par raycast_visible_face - voir
## VoxelWorld.describe_visible_cell pour le contexte complet (regle "gris
## non decouvert", distinction CUBE plein / SOL seul). "block_type_info_fn"
## reste un Callable vers VoxelWorld._block_type_info_at (a besoin de
## vein_system, non passe ici).
static func describe_visible_cell(pos: Vector3i, grid: Dictionary, empty_type: int, view_level: int, discovered: Dictionary, sol_grid: Dictionary, block_type_info_fn: Callable) -> Dictionary:
	if grid.get(pos, empty_type) == empty_type:
		if sol_grid.has(pos):
			return block_type_info_fn.call(pos)
		if pos.y - 1 < 0 or not discovered.has(Vector3i(pos.x, pos.y - 1, pos.z)):
			return {"type": "non_decouvert", "materiau": ""}
		return block_type_info_fn.call(pos)
	if pos.y == view_level and not discovered.has(pos):
		return {"type": "non_decouvert", "materiau": ""}
	return block_type_info_fn.call(pos)
