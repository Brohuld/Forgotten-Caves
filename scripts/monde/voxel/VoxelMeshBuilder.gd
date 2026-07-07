extends RefCounted
## Construction du mesh du terrain : culling des faces cachees, choix du
## "bucket" (materiau/couleur) par bloc, couleurs herbe/pierre/filon, ajout
## des quads.
##
## "rebuild(...)" copie les parametres recus dans ses propres membres (memes
## noms qu'un acces direct aux champs de VoxelWorld.gd : grid, discovered,
## view_level, WIDTH, DEPTH, DIRECTIONS, is_frozen, snow_coverage,
## climate_id, season_id, terrain_noise, stone_noise, mesh_instance), puis
## reconstruit le mesh. Deux adaptations par rapport a un acces direct aux
## champs de VoxelWorld : _is_face_exposed n'appelle plus VoxelWorld.get_block()
## (inutile, ce module a deja "grid") et _grass_color_for/_stone_color_for
## appellent get_top_block_y via un Callable (cette fonction reste sur
## VoxelWorld, pas dupliquee ici - evite un ecart si sa logique change un jour).
##
## Ce module ne prend jamais de reference typee vers VoxelWorld.gd lui-meme
## (meme raison que VoxelVeins.gd, voir sa note en tete de fichier - une
## reference typee generique ne resout pas un acces direct du type
## "voxel_world.WATER_COLOR").

const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")
const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
const VoxelVeinsScript := preload("res://scripts/monde/voxel/VoxelVeins.gd")

# Duplique de l'enum BlockType de VoxelWorld.gd (memes valeurs/ordre exacts -
# EMPTY=0, DIRT=1, STONE=2, WOOD_WALL=3, STONE_WALL=4, WATER=5). Necessaire
# car un enum defini dans un script ne se resout pas depuis un autre script
# sans creer une reference typee croisee (voir note en tete de fichier) - les
# entiers stockes dans "grid" restent valides quel que soit l'enum utilise
# pour les nommer. ATTENTION : si le BlockType de VoxelWorld.gd change un
# jour (ajout/retrait/reordonnancement), reproduire le changement ici.
enum BlockType { EMPTY, DIRT, STONE, WOOD_WALL, STONE_WALL, WATER }

const UNDISCOVERED_COLOR := Color(0.5, 0.5, 0.5)
const WATER_COLOR := Color(0.45, 0.80, 0.98)
const ICE_COLOR := Color(0.78, 0.88, 0.94)
const SNOW_COLOR := Color(0.95, 0.96, 0.98)
const STONE_BASE := Color(0.58, 0.60, 0.66)

# Membres copies depuis VoxelWorld.gd a chaque appel de rebuild() (voir
# commentaire de tete). Noms EN MAJUSCULES (WIDTH/DEPTH/DIRECTIONS) volontai-
# rement gardes tels quels (pas la convention habituelle pour un "var") pour
# que le corps des fonctions ci-dessous reste identique, caractere pour
# caractere, a un acces direct aux champs de VoxelWorld.gd - minimise le
# risque d'erreur de transcription sur du code deja tres retravaille.
var grid: Dictionary
var discovered: Dictionary
var vein_grid: Dictionary
var vein_system: VoxelVeinsScript
var view_level: int
var WIDTH: int
var DEPTH: int
var is_frozen: bool
var snow_coverage: float
var climate_id: String
var season_id: String
var terrain_noise: FastNoiseLite
## Cache des 13 materiaux de bucket - voir _get_bucket_materials plus bas.
var _bucket_materials: Dictionary = {}
var stone_noise: FastNoiseLite
var DIRECTIONS: Array
var mesh_instance: MeshInstance3D
var get_top_block_y: Callable


## Point d'entree, appele par VoxelWorld.rebuild_mesh() (facade fine).
## Recopie l'etat necessaire puis reconstruit le mesh (voir _rebuild_mesh_body).
func rebuild(p_grid: Dictionary, p_discovered: Dictionary, p_vein_system: VoxelVeinsScript,
		p_view_level: int, p_width: int, p_depth: int, p_is_frozen: bool,
		p_snow_coverage: float, p_climate_id: String, p_season_id: String,
		p_terrain_noise: FastNoiseLite, p_stone_noise: FastNoiseLite,
		p_directions: Array, p_mesh_instance: MeshInstance3D,
		p_get_top_block_y: Callable) -> void:
	grid = p_grid
	discovered = p_discovered
	vein_system = p_vein_system
	vein_grid = p_vein_system.vein_grid
	view_level = p_view_level
	WIDTH = p_width
	DEPTH = p_depth
	is_frozen = p_is_frozen
	snow_coverage = p_snow_coverage
	climate_id = p_climate_id
	season_id = p_season_id
	terrain_noise = p_terrain_noise
	stone_noise = p_stone_noise
	DIRECTIONS = p_directions
	mesh_instance = p_mesh_instance
	get_top_block_y = p_get_top_block_y
	_rebuild_mesh_body()


## Une face est exposee (donc dessinee) si la case voisine est soit
## reellement vide, soit au-dessus du niveau de coupe visible (view_level) -
## dans ce cas elle n'est pas dessinee non plus, donc pour ce qu'on affiche,
## elle "n'existe pas" et la face doit apparaitre. C'est ce qui revele le
## dessus colore de chaque bloc au niveau courant.
func _is_face_exposed(neighbor_pos: Vector3i) -> bool:
	if neighbor_pos.y > view_level:
		return true
	return grid.get(neighbor_pos, BlockType.EMPTY) == BlockType.EMPTY


## Couleur de l'herbe (dessus terre) a une position donnee, couleur de base
## du climat/saison actuels modulee par un bruit continu (+/- environ 12% de
## luminosite), pour une variation douce case par case au lieu d'un damier
## clair/fonce.
func _grass_color_for(pos: Vector3i) -> Color:
	var base: Color = ClimateDefs.get_terrain_color(climate_id, season_id)
	return _noise_modulated_color(base, terrain_noise, pos)


## Couleur de la pierre (dessus) a une position donnee - couleur de base
## unique (STONE_BASE) moduleee par un bruit continu (+/- ~12% de
## luminosite). Meme technique que _grass_color_for : un materiau uniforme
## par niveau, les filons restant la seule vraie exception de couleur.
func _stone_color_for(pos: Vector3i) -> Color:
	return _noise_modulated_color(STONE_BASE, stone_noise, pos)


## Logique commune a _grass_color_for/_stone_color_for (les 2 partagent le
## meme calcul de bruit + voile de neige, seule la couleur/le bruit de base
## different). Bruit continu (+/- ~12% de luminosite) puis voile de neige,
## uniquement sur la vraie surface exterieure - pas sur un dessus de terre
## mis a jour au fond d'un trou mine, ou il n'y a pas de ciel pour neiger.
## Compare au sommet REEL de CETTE colonne (get_top_block_y), pas HEIGHT-1
## fixe - sinon les sommets de colline (plus hauts que HEIGHT-1) ne
## recevraient jamais de neige.
func _noise_modulated_color(base: Color, noise: FastNoiseLite, pos: Vector3i) -> Color:
	var n: float = noise.get_noise_2d(float(pos.x), float(pos.z))  # -1..1
	var factor: float = 1.0 + n * 0.12
	var color := Color(
		clamp(base.r * factor, 0.0, 1.0),
		clamp(base.g * factor, 0.0, 1.0),
		clamp(base.b * factor, 0.0, 1.0),
		base.a
	)
	if snow_coverage > 0.0 and pos.y == get_top_block_y.call(pos.x, pos.z):
		color = color.lerp(SNOW_COLOR, snow_coverage)
	return color


## Couleur d'un bloc de filon (metal/pierre precieuse) a une position
## donnee, recuperee depuis MetalTypes/GemTypes via VeinMaterials. Couleur
## neutre de secours si jamais la position n'est plus dans vein_grid (ne
## devrait pas arriver, garde par securite).
func _vein_color_for(pos: Vector3i) -> Color:
	if not vein_grid.has(pos):
		return Color(0.5, 0.5, 0.5)
	var material: Dictionary = VeinMaterials.get_type(vein_grid[pos])
	return material.get("couleur", Color(0.5, 0.5, 0.5))


## Construit un seul mesh avec une surface par materiau, en n'ajoutant une
## face que si le bloc voisin dans cette direction est vide (culling des
## faces cachees). Les faces verticales/du dessous (parois d'un trou mine ou
## d'un mur) sont assombries par rapport aux faces du dessus, pour bien
## distinguer un creux (paroi sombre visible) d'une simple variation de
## couleur de surface. Le dessus terre (bucket 0, l'herbe) et le dessus
## pierre (bucket 2) utilisent une couleur par climat/saison + variation de
## bruit par case, appliquee via des couleurs de sommet (voir
## _grass_color_for/_stone_color_for et _add_face) plutot qu'un damier
## clair/fonce ; les buckets 1 et 3 (ancien damier) restent reserves mais
## inutilises, pour eviter de renumeroter les autres buckets. Le bucket 10
## est reserve aux filons (metal/pierre precieuse), colore par sommet comme
## l'herbe, mais applique a toutes les faces du bloc (dessus ET parois) pour
## que le filon reste visible/reperable une fois une paroi exposee. Les
## blocs strictement au-dessus de view_level ne sont pas dessines du tout,
## et leur "absence" compte comme une face exposee pour le bloc juste en
## dessous (voir _is_face_exposed) - c'est ce qui revele une coupe
## horizontale complete et coloree du niveau courant, au lieu de se
## contenter de deplacer la camera a l'interieur de la roche pleine.
func _rebuild_mesh_body() -> void:
	# 13 buckets : 0-3 = dessus terre/pierre (0=herbe couleur variable, 1=inutilise,
	# 2=pierre couleur variable, 3=inutilise), 4-5 = dessus mur bois/pierre,
	# 6-9 = parois assombries (terre, pierre, mur bois, mur pierre),
	# 10 = filon (metal/pierre precieuse, toutes faces, couleur variable),
	# 11 = bloc non decouvert (gris uniforme, voir "discovered"),
	# 12 = eau (couleur unie WATER_COLOR, toutes faces).
	var surface_tools: Array = []
	for i in range(13):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface_tools.append(st)

	# Boucler sur les colonnes visibles (y de 0 a view_level) representerait
	# encore jusqu'a plusieurs centaines de milliers de cases a view_level
	# eleve, recalculees en entier a CHAQUE minage/construction/changement de
	# niveau. La passe "detaillee" ci-dessous est bornee a l'ensemble
	# "discovered" (voir sa doc sur VoxelWorld.gd) - petit au depart (juste
	# la surface + les bords de carte), grandit lentement au fil du minage,
	# jamais toute la grille. Le rendu (couleur/filon/exposition de face)
	# est identique pour tout ce qui est decouvert - seule la SOURCE de
	# l'iteration change (un ensemble cible au lieu d'une triple boucle x/z/y).
	for pos in discovered.keys():
		if pos.y > view_level:
			continue
		var type: int = grid.get(pos, BlockType.EMPTY)
		if type == BlockType.EMPTY:
			continue
		for dir in DIRECTIONS:
			if _is_face_exposed(pos + dir):
				var idx := _bucket_for(pos, type, dir)
				var face_color := Color.WHITE
				if idx == 0:
					face_color = _grass_color_for(pos)
				elif idx == 2:
					face_color = _stone_color_for(pos)
				elif idx == 10:
					face_color = _vein_color_for(pos)
				_add_face(surface_tools[idx], pos, dir, face_color)

	# Passe "non decouvert" - une seule face (le dessus) par colonne, grise,
	# pour representer ce qui n'a jamais ete explore au niveau de coupe
	# courant (pas de rendu detaille/colore pour tout ce qui n'est pas dans
	# "discovered"). Ne coute qu'une iteration sur les colonnes
	# (WIDTH*DEPTH), jamais sur la profondeur - c'est ce qui rend le
	# changement de niveau rapide meme a view_level eleve.
	for x in range(WIDTH):
		for z in range(DEPTH):
			var pos := Vector3i(x, view_level, z)
			if discovered.has(pos):
				continue  # deja traite avec sa vraie couleur dans la passe ci-dessus
			var type: int = grid.get(pos, BlockType.EMPTY)
			if type == BlockType.EMPTY:
				continue
			_add_face(surface_tools[11], pos, Vector3i(0, 1, 0), UNDISCOVERED_COLOR)

	# Materiau associe a chaque bucket (index dans surface_tools). Un
	# SurfaceTool sans aucune face ajoutee ne produit PAS de surface lors du
	# commit() (Godot ignore silencieusement les buckets vides), donc
	# l'indice de surface reellement obtenu dans le mesh final peut etre
	# INFERIEUR a l'indice du bucket d'origine des qu'un bucket precedent
	# est vide (ex : aucun mur en bois sur la carte -> bucket 4 vide -> tout
	# ce qui suit se decale). Assigner les materiaux a des indices fixes
	# 0-10 provoquerait donc "Index p_idx out of bounds" des qu'un type de
	# bloc est absent de la carte (cas frequent sur une carte fraiche/
	# petite). Chaque bucket est donc mappe a son materiau via un
	# dictionnaire, et surface_set_material n'est appele qu'apres coup, sur
	# le vrai indice de surface obtenu (compte a part, qui n'avance que
	# quand un commit() a effectivement ajoute une surface).
	var bucket_materials: Dictionary = _get_bucket_materials()

	var mesh := ArrayMesh.new()
	for bucket_idx in range(surface_tools.size()):
		var st: SurfaceTool = surface_tools[bucket_idx]
		var surfaces_before := mesh.get_surface_count()
		st.commit(mesh)
		if mesh.get_surface_count() > surfaces_before:
			# .get() avec repli sur StandardMaterial3D.new() (materiau
			# neutre) plutot qu'un acces direct - si _get_bucket_materials()
			# ne couvre pas ce bucket_idx, on evite un crash "Index p_idx
			# out of bounds" au profit d'un rendu degrade (couleur par
			# defaut) et d'un avertissement.
			var mat: Material = bucket_materials.get(bucket_idx)
			if mat == null:
				push_warning("VoxelMeshBuilder: aucun materiau pour le bucket %d, materiau par defaut utilise" % bucket_idx)
				mat = StandardMaterial3D.new()
			mesh.surface_set_material(surfaces_before, mat)

	mesh_instance.mesh = mesh
	vein_system.rebuild_pepites(view_level, discovered, Callable(self, "_is_face_exposed"), DIRECTIONS)


## Determine dans quelle surface (materiau + face) placer un bloc donne. Le
## dessus terre (herbe, bucket 0) et le dessus pierre (bucket 2) utilisent
## chacun un seul bucket a couleur variable par sommet (pas de damier clair/
## fonce). Un bloc de pierre qui est un filon (vein_grid) passe sur le
## bucket 10 (couleur variable), sur toutes ses faces (dessus ET parois),
## avant meme de regarder le type - un filon reste un filon peu importe la
## face.
func _bucket_for(pos: Vector3i, type: int, dir: Vector3i) -> int:
	var is_top := dir == Vector3i(0, 1, 0)

	if type == BlockType.STONE and vein_grid.has(pos):
		return 10

	if is_top:
		match type:
			BlockType.DIRT:
				return 0
			BlockType.STONE:
				return 2
			BlockType.WOOD_WALL:
				return 4
			BlockType.STONE_WALL:
				return 5
			BlockType.WATER:
				return 12
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
		BlockType.WATER:
			return 12
	return 6


## Assombrit une couleur (utilise pour les parois des trous/murs, effet
## d'ombrage simple sans veritable eclairage)
func _darken(color: Color) -> Color:
	return Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, color.a)


## Les 13 StandardMaterial3D ne sont pas recrees a chaque rebuild_mesh()
## (donc a chaque minage/construction) : seul le bucket 12 (eau/glace)
## depend d'un etat qui change reellement (is_frozen, voir
## TemperatureSystem.gd) - les 12 autres sont des couleurs fixes. Construits
## une seule fois puis mis en cache ; seule la couleur du bucket 12 est mise
## a jour a chaque appel.
func _get_bucket_materials() -> Dictionary:
	if _bucket_materials.is_empty():
		var dirt_dark := Color(0.58, 0.34, 0.10)  # garde pour bucket 6 (paroi terre)
		var stone_dark := Color(0.48, 0.50, 0.56)  # garde pour bucket 3 (inutilise) et bucket 7 (paroi)
		var wood_wall := Color(0.70, 0.46, 0.16)
		var stone_wall := Color(0.74, 0.76, 0.82)
		_bucket_materials = {
			0: _make_vertex_color_material(),
			1: _make_material(dirt_dark),  # inutilise (voir plus haut)
			2: _make_vertex_color_material(),
			3: _make_material(stone_dark),  # inutilise (voir plus haut)
			4: _make_material(wood_wall),
			5: _make_material(stone_wall),
			6: _make_material(_darken(dirt_dark)),
			7: _make_material(_darken(stone_dark)),
			8: _make_material(_darken(wood_wall)),
			9: _make_material(_darken(stone_wall)),
			10: _make_vertex_color_material(),
			11: _make_material(UNDISCOVERED_COLOR),  # gris uniforme, pas besoin de couleur par sommet
			12: _make_material(WATER_COLOR),
		}
	# L'eau devient de la glace (couleur claire) quand is_frozen est vrai -
	# seule couleur qui doit rester a jour a chaque appel, modifiee en place
	# plutot que de recreer le materiau.
	_bucket_materials[12].albedo_color = ICE_COLOR if is_frozen else WATER_COLOR
	return _bucket_materials


## Cree un materiau simple, dans la couleur donnee. Eclairage reel (mode par
## defaut de StandardMaterial3D, pas SHADING_MODE_UNSHADED) pour que le
## terrain reagisse au cycle jour/nuit (DayNightCycle.gd) - un materiau
## "unshaded" ignore totalement la lumiere/les ombres. roughness=1/
## metallic=0 evite les reflets speculaires pour garder un rendu plat/mat
## coherent avec le style low-poly du jeu, tout en recevant lumiere
## directionnelle + ombres + lumiere ambiante.
func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## Materiau pour le bucket 0 (herbe), qui lit la couleur par sommet (definie
## via SurfaceTool.set_color dans _add_face) au lieu d'une seule couleur
## fixe - c'est ce qui permet la variation continue par case. Meme passage
## a l'eclairage reel que _make_material ci-dessus.
func _make_vertex_color_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## Ajoute un quad (2 triangles) sur la face "dir" du bloc a la position "pos".
## face_color : couleur de sommet, utilisee uniquement par le bucket
## "herbe"/"pierre"/"filon" dont le materiau lit vertex_color_use_as_albedo ;
## ignoree par les autres materiaux, donc sans effet pour eux.
func _add_face(st: SurfaceTool, pos: Vector3i, dir: Vector3i, face_color: Color = Color.WHITE) -> void:
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

	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[0])
	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[1])
	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[2])

	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[0])
	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[2])
	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[3])
