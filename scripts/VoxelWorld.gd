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

enum BlockType { EMPTY, DIRT, STONE }

# Grille du monde : cle = Vector3i (position bloc), valeur = BlockType
var grid: Dictionary = {}

# 6 directions possibles autour d'un bloc (droite/gauche/haut/bas/avant/arriere)
const DIRECTIONS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


func _ready() -> void:
	generate_flat_terrain()
	build_mesh()


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


## Construit un seul mesh avec une surface "terre" et une surface "pierre",
## en n'ajoutant une face que si le bloc voisin dans cette direction est vide.
## C'est le culling des faces cachees : on evite de dessiner les faces
## entre deux blocs pleins, invisibles de toute facon.
func build_mesh() -> void:
	# 4 buckets : 0=terre claire, 1=terre foncee, 2=pierre claire, 3=pierre foncee
	# L'alternance clair/fonce (damier selon x+z) permet de voir clairement
	# la grille de blocs plutot qu'une surface plate uniforme.
	var surface_tools: Array = []
	for i in range(4):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface_tools.append(st)

	for pos in grid.keys():
		var type: int = grid[pos]
		if type == BlockType.EMPTY:
			continue
		var parity: int = (pos.x + pos.z) % 2
		var idx: int
		if type == BlockType.DIRT:
			idx = 0 if parity == 0 else 1
		else:
			idx = 2 if parity == 0 else 3
		var st: SurfaceTool = surface_tools[idx]
		for dir in DIRECTIONS:
			if get_block(pos + dir) == BlockType.EMPTY:
				_add_face(st, pos, dir)

	var mesh := ArrayMesh.new()
	for st in surface_tools:
		st.commit(mesh)

	mesh.surface_set_material(0, _make_material(Color(0.60, 0.42, 0.24)))
	mesh.surface_set_material(1, _make_material(Color(0.45, 0.30, 0.15)))
	mesh.surface_set_material(2, _make_material(Color(0.58, 0.58, 0.58)))
	mesh.surface_set_material(3, _make_material(Color(0.42, 0.42, 0.42)))

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	add_child(mesh_instance)


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
