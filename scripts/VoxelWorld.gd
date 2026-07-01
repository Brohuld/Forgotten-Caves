extends Node3D
## Sprint 1 : genere une petite carte de test plate (terre sur pierre)
## et construit un mesh unique par materiau, en ne dessinant que les
## faces exposees (culling des faces cachees / internes).

# Dimensions de la carte de test (on agrandira vers 200x200x100 plus tard)
const WIDTH := 20   # axe X
const DEPTH := 20   # axe Z
const HEIGHT := 10  # axe Y (hauteur totale, y=0 = fond)

# Nombre de niveaux de terre en surface (le reste en dessous = pierre)
const DIRT_HEIGHT := 3

# Marge au-dessus du terrain pour pouvoir construire des murs en hauteur (Sprint 7)
const BUILD_CEILING := HEIGHT + 10

enum BlockType { EMPTY, DIRT, STONE, WOOD_WALL, STONE_WALL }

# Grille du monde : cle = Vector3i (position bloc), valeur = BlockType
var grid: Dictionary = {}

# 6 directions possibles autour d'un bloc (droite/gauche/haut/bas/avant/arriere)
const DIRECTIONS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


var mesh_instance: MeshInstance3D


func _ready() -> void:
	generate_flat_terrain()
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	rebuild_mesh()


## Renvoie le y du bloc le plus haut (non vide) de la colonne (x,z), -1 si vide.
## Cherche jusqu'a BUILD_CEILING pour tenir compte des murs construits en hauteur.
func get_top_block_y(x: int, z: int) -> int:
	for y in range(BUILD_CEILING - 1, -1, -1):
		if get_block(Vector3i(x, y, z)) != BlockType.EMPTY:
			return y
	return -1


## Indique si on peut encore construire en hauteur sur cette colonne
func can_build(x: int, z: int) -> bool:
	return get_top_block_y(x, z) + 1 < BUILD_CEILING


## Construit un mur (bois, pierre ou terre) au sommet de la colonne (x,z), en
## empilant sur ce qui existe deja (fonctionne aussi bien pour reboucher
## un trou mine que pour construire en hauteur sur un sol plein)
func build_block(x: int, z: int, material: String) -> void:
	var target_y := get_top_block_y(x, z) + 1
	if target_y >= BUILD_CEILING:
		return
	var type: int
	match material:
		"bois":
			type = BlockType.WOOD_WALL
		"pierre":
			type = BlockType.STONE_WALL
		"terre":
			type = BlockType.DIRT  # reutilise le type terre : mine, ca redonne bien "terre"
		_:
			type = BlockType.WOOD_WALL
	grid[Vector3i(x, target_y, z)] = type
	rebuild_mesh()


## Retire un bloc de la grille (mine/creuse), reconstruit le mesh, et renvoie
## le nom de la ressource obtenue ("terre", "pierre") ou "" si rien a miner
func remove_block(x: int, y: int, z: int) -> String:
	var pos := Vector3i(x, y, z)
	if not grid.has(pos):
		return ""
	var type: int = grid[pos]
	grid.erase(pos)
	rebuild_mesh()
	if type == BlockType.DIRT:
		return "terre"
	elif type == BlockType.STONE:
		return "pierre"
	return ""


## Remplit la grille : pierre en bas, terre au-dessus (terrain plat pour l'instant)
func generate_flat_terrain() -> void:
	for x in range(WIDTH):
		for z in range(DEPTH):
			for y in range(HEIGHT):
				var type := BlockType.STONE
				if y >= HEIGHT - DIRT_HEIGHT:
					type = BlockType.DIRT
				grid[Vector3i(x, y, z)] = type


## Renvoie le type de bloc a une position, EMPTY si hors de la carte
func get_block(pos: Vector3i) -> int:
	return grid.get(pos, BlockType.EMPTY)


## Construit un seul mesh avec une surface par materiau, en n'ajoutant une
## face que si le bloc voisin dans cette direction est vide (culling des
## faces cachees). Sprint 10 : les faces verticales/du dessous (parois d'un
## trou mine ou d'un mur) sont assombries par rapport aux faces du dessus,
## pour bien distinguer un creux (paroi sombre visible) d'une simple
## variation de couleur du damier de surface.
func rebuild_mesh() -> void:
	# 10 buckets : 0-3 = dessus terre/pierre (clair/fonce, damier), 4-5 = dessus
	# mur bois/pierre, 6-9 = parois assombries (terre, pierre, mur bois, mur pierre).
	var surface_tools: Array = []
	for i in range(10):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface_tools.append(st)

	for pos in grid.keys():
		var type: int = grid[pos]
		if type == BlockType.EMPTY:
			continue
		for dir in DIRECTIONS:
			if get_block(pos + dir) == BlockType.EMPTY:
				var idx := _bucket_for(pos, type, dir)
				_add_face(surface_tools[idx], pos, dir)

	var mesh := ArrayMesh.new()
	for st in surface_tools:
		st.commit(mesh)

	var dirt_light := Color(0.60, 0.42, 0.24)
	var dirt_dark := Color(0.45, 0.30, 0.15)
	var stone_light := Color(0.58, 0.58, 0.58)
	var stone_dark := Color(0.42, 0.42, 0.42)
	var wood_wall := Color(0.55, 0.38, 0.20)
	var stone_wall := Color(0.60, 0.62, 0.66)

	mesh.surface_set_material(0, _make_material(dirt_light))
	mesh.surface_set_material(1, _make_material(dirt_dark))
	mesh.surface_set_material(2, _make_material(stone_light))
	mesh.surface_set_material(3, _make_material(stone_dark))
	mesh.surface_set_material(4, _make_material(wood_wall))
	mesh.surface_set_material(5, _make_material(stone_wall))
	mesh.surface_set_material(6, _make_material(_darken(dirt_dark)))
	mesh.surface_set_material(7, _make_material(_darken(stone_dark)))
	mesh.surface_set_material(8, _make_material(_darken(wood_wall)))
	mesh.surface_set_material(9, _make_material(_darken(stone_wall)))

	mesh_instance.mesh = mesh


## Determine dans quelle surface (materiau + face) placer un bloc donne.
## Les faces du dessus gardent le damier clair/fonce (lisibilite de la grille) ;
## toutes les autres faces (parois, dessous) passent sur la variante assombrie.
func _bucket_for(pos: Vector3i, type: int, dir: Vector3i) -> int:
	var is_top := dir == Vector3i(0, 1, 0)
	var parity: int = (pos.x + pos.z) % 2

	if is_top:
		match type:
			BlockType.DIRT:
				return 0 if parity == 0 else 1
			BlockType.STONE:
				return 2 if parity == 0 else 3
			BlockType.WOOD_WALL:
				return 4
			BlockType.STONE_WALL:
				return 5
		return 0

	match type:
		BlockType.DIRT:
			return 6
		BlockType.STONE:
			return 7
		BlockType.WOOD_WALL:
			return 8
		BlockType.STONE_WALL:
			return 9
	return 6


## Assombrit une couleur (utilise pour les parois des trous/murs, effet
## d'ombrage simple sans veritable eclairage)
func _darken(color: Color) -> Color:
	return Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, color.a)


## Cree un materiau simple, non eclaire, dans la couleur donnee
func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Ajoute un quad (2 triangles) sur la face "dir" du bloc a la position "pos"
func _add_face(st: SurfaceTool, pos: Vector3i, dir: Vector3i) -> void:
	var p := Vector3(pos.x, pos.y, pos.z)
	var verts: Array

	if dir == Vector3i(1, 0, 0):
		verts = [p + Vector3(1, 0, 0), p + Vector3(1, 1, 0), p + Vector3(1, 1, 1), p + Vector3(1, 0, 1)]
	elif dir == Vector3i(-1, 0, 0):
		verts = [p + Vector3(0, 0, 1), p + Vector3(0, 1, 1), p + Vector3(0, 1, 0), p + Vector3(0, 0, 0)]
	elif dir == Vector3i(0, 1, 0):
		verts = [p + Vector3(0, 1, 0), p + Vector3(0, 1, 1), p + Vector3(1, 1, 1), p + Vector3(1, 1, 0)]
	elif dir == Vector3i(0, -1, 0):
		verts = [p + Vector3(1, 0, 0), p + Vector3(1, 0, 1), p + Vector3(0, 0, 1), p + Vector3(0, 0, 0)]
	elif dir == Vector3i(0, 0, 1):
		verts = [p + Vector3(1, 0, 1), p + Vector3(1, 1, 1), p + Vector3(0, 1, 1), p + Vector3(0, 0, 1)]
	else: # Vector3i(0, 0, -1)
		verts = [p + Vector3(0, 0, 0), p + Vector3(0, 1, 0), p + Vector3(1, 1, 0), p + Vector3(1, 0, 0)]

	var normal := Vector3(dir.x, dir.y, dir.z)

	st.set_normal(normal)
	st.add_vertex(verts[0])
	st.set_normal(normal)
	st.add_vertex(verts[1])
	st.set_normal(normal)
	st.add_vertex(verts[2])

	st.set_normal(normal)
	st.add_vertex(verts[0])
	st.set_normal(normal)
	st.add_vertex(verts[2])
	st.set_normal(normal)
	st.add_vertex(verts[3])
