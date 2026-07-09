extends RefCounted
## Validation des cases cibles pour Construire/Miner/Puiser/Detruire/
## Interdire - decide QUELLES cases d'un rectangle sont des cibles legales,
## independamment de leur affichage (fantomes/marqueurs restent dans
## ActionController.gd). Suit le meme pattern que DwarfSkills.gd : pas de
## reference typee vers ActionController.gd, les donnees necessaires
## (voxel_world/dimensions de la carte/etat "en attente") sont passees en
## parametres.

## Renvoie toutes les cases DANS LA CARTE du rectangle a-b, sans aucun filtre
## metier (a appliquer par l'appelant) - factorise le calcul des bornes du
## rectangle et la boucle de filtrage hors-grille, commun a toutes les
## fonctions valid_*_rect_cells ci-dessous (seul le filtre METIER
## constructible/minable/eau differe d'une fonction a l'autre).
func _rect_cells_in_bounds(a: Vector2i, b: Vector2i, grid_width: int, grid_depth: int) -> Array:
	var min_x := mini(a.x, b.x)
	var max_x := maxi(a.x, b.x)
	var min_z := mini(a.y, b.y)
	var max_z := maxi(a.y, b.y)
	var cells: Array = []
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			if x < 0 or x >= grid_width or z < 0 or z >= grid_depth:
				continue
			cells.append(Vector2i(x, z))
	return cells


## Cases valides pour Construire : dans la carte, constructibles (voir
## VoxelWorld.can_build), pas deja en attente de construction.
func valid_rect_cells(a: Vector2i, b: Vector2i, grid_width: int, grid_depth: int, voxel_world: Node, pending_columns: Dictionary) -> Array:
	var cells: Array = []
	for cell in _rect_cells_in_bounds(a, b, grid_width, grid_depth):
		if not voxel_world.can_build(cell.x, cell.y):
			continue
		if pending_columns.has(cell):
			continue
		cells.append(cell)
	return cells


## Cases valides pour Miner - dans la carte, avec quelque chose a miner, hors
## eau (l'eau se puise, ne se mine pas). Pas de filtre "constructible" ni de
## suivi "en attente" (fidele au comportement du clic simple d'origine).
##
## "view_level" (voir VoxelWorld.view_level) : Miner cible le bloc visible au
## niveau de coupe courant, pas forcement le sommet reel de la colonne (voir
## get_top_block_y_at_or_below) - choix de Francois 2026-07-08, pour pouvoir
## miner directement une poche revelee en coupe a un niveau inferieur.
func valid_mine_rect_cells(a: Vector2i, b: Vector2i, grid_width: int, grid_depth: int, voxel_world: Node, view_level: int) -> Array:
	var cells: Array = []
	for cell in _rect_cells_in_bounds(a, b, grid_width, grid_depth):
		if voxel_world.get_top_block_y_at_or_below(cell.x, cell.y, view_level) < 0:
			continue  # rien a miner sur cette colonne a ce niveau de vue ou en dessous
		if voxel_world.is_water(cell.x, cell.y):
			continue  # l'eau se puise (bouton Puiser), ne se mine pas
		# Une case marquee "interdite" ne peut plus etre designee par Miner.
		if voxel_world.is_cell_forbidden(cell.x, cell.y):
			continue
		cells.append(cell)
	return cells


## Univers de cases que le mode Interdire peut marquer/demarquer - MEME
## filtre "quelque chose a miner, hors eau" que valid_mine_rect_cells, mais
## SANS exclure les cases deja interdites (sinon impossible de les
## re-selectionner pour les re-autoriser - Interdire doit justement pouvoir
## cibler les deux etats).
func valid_interdire_rect_cells(a: Vector2i, b: Vector2i, grid_width: int, grid_depth: int, voxel_world: Node) -> Array:
	var cells: Array = []
	for cell in _rect_cells_in_bounds(a, b, grid_width, grid_depth):
		if voxel_world.get_top_block_y(cell.x, cell.y) < 0:
			continue
		if voxel_world.is_water(cell.x, cell.y):
			continue
		cells.append(cell)
	return cells


## Cases valides pour Puiser - dans la carte, avec de l'eau non gelee en
## surface. Pas de suivi "en attente" : l'eau est renouvelable.
func valid_puiser_rect_cells(a: Vector2i, b: Vector2i, grid_width: int, grid_depth: int, voxel_world: Node) -> Array:
	# L'eau gelee (glace) ne se puise pas - etat global, voir
	# VoxelWorld.is_frozen/TemperatureSystem.gd.
	if voxel_world.is_frozen:
		return []
	var cells: Array = []
	for cell in _rect_cells_in_bounds(a, b, grid_width, grid_depth):
		if not voxel_world.is_water(cell.x, cell.y):
			continue
		# Une case marquee "interdite" ne peut plus etre designee par Puiser.
		if voxel_world.is_cell_forbidden(cell.x, cell.y):
			continue
		cells.append(cell)
	return cells


## Cases valides pour Detruire - dans la carte, dont le sommet est un mur
## CONSTRUIT (mur_bois/mur_pierre, voir VoxelWorld.get_block_info). Un mur en
## "terre" reutilise le type DIRT (voir VoxelWorld.build_block) et est donc
## INDISTINGUABLE de la terre naturelle - PAS ciblable par Detruire pour
## l'instant (limite connue, pas un bug).
func valid_destroy_rect_cells(a: Vector2i, b: Vector2i, grid_width: int, grid_depth: int, voxel_world: Node) -> Array:
	var cells: Array = []
	for cell in _rect_cells_in_bounds(a, b, grid_width, grid_depth):
		var info: Dictionary = voxel_world.get_block_info(cell.x, cell.y)
		if info["type"] != "mur_bois" and info["type"] != "mur_pierre":
			continue
		cells.append(cell)
	return cells


## Recherche de cible la plus proche du point de clic "hit" (distance
## horizontale X/Z uniquement) parmi les noeuds du groupe "group_name", dans
## un rayon "max_dist". Renvoie null si rien trouve. Logique partagee par
## Couper (groupe "trees") et Cueillir (groupe "cueillette") dans
## ActionController.gd - purement geometrique, ne modifie rien (le marqueur
## visuel et l'ajout a la queue de taches restent dans
## ActionController.gd/_handle_chop_click/_handle_gather_click).
func closest_in_group(hit: Vector3, group_name: String, scene_tree: SceneTree, max_dist: float) -> Node3D:
	var closest: Node3D = null
	var closest_dist := max_dist
	for node in scene_tree.get_nodes_in_group(group_name):
		# Un noeud du groupe peut etre en cours de liberation (queue_free()
		# appele la meme frame par _harvest_and_clear(), voir Forest.gd/
		# BerryBushes.gd) - y acceder provoquerait un crash. On l'ignore
		# simplement, comme s'il n'existait deja plus.
		if not is_instance_valid(node):
			continue
		var d: float = Vector2(node.global_position.x - hit.x, node.global_position.z - hit.z).length()
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest
