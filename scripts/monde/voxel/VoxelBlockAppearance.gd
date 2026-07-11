extends RefCounted
## Primitives PURES de geometrie (quads/boites) et de couleur (bruit/
## penombre/AO) - extrait de VoxelMeshBuilder.gd (revue de code C23,
## 2026-07-11 : fichier a 1609 lignes, le plus long du depot). Fonctions
## STATIQUES, aucun etat propre.
##
## SCOPE VOLONTAIREMENT PARTIEL (deviation signalee) : seules les fonctions
## qui ne touchent JAMAIS au cache par couche/chunk (_layer_*, _boundary_
## mesh_cache, _cache_populated...) sont deplacees ici - la logique de bucket
## (_bucket_for/_paroi_bucket_for/_sol_bucket_and_color_for/_stair_color_for,
## qui fait correspondre chaque BlockType a un indice de bucket) et toute
## l'orchestration de cache restent dans VoxelMeshBuilder.gd : les deplacer
## aurait force soit une 3e copie de l'enum BlockType (deja duplique une fois
## depuis VoxelWorld.gd, risque de desynchronisation type C19), soit une
## explosion du nombre de parametres, pour un gain de lisibilite limite sur
## le fichier qui vient d'etre retravaille cette meme session (cache par
## (Y, CHUNK)) - juge trop risque pour une premiere passe.
##
## Toutes les constantes de couleur/reglage (PENOMBRE_FACTOR, SNOW_COLOR,
## STONE_BASE, DIRT_UNDERGROUND_BASE) restent definies UNE SEULE FOIS dans
## VoxelMeshBuilder.gd et sont passees en parametre ici, plutot que
## dupliquees - meme principe que Forest.gd/ForestGeometryBuilder.gd.

const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")


## Vrai si la case n'a plus de ciel ouvert au-dessus (encore un bloc plein
## entre elle et le sommet reel de la colonne) - voir
## VoxelMeshBuilder._is_underground pour le contexte complet.
static func is_underground(pos: Vector3i, get_top_block_y_fn: Callable) -> bool:
	return pos.y < get_top_block_y_fn.call(pos.x, pos.z)


## Assombrit une couleur de materiau DEJA calculee sans en changer la teinte -
## voir VoxelMeshBuilder._apply_penombre.
static func apply_penombre(color: Color, penombre_factor: float) -> Color:
	return Color(color.r * penombre_factor, color.g * penombre_factor, color.b * penombre_factor, color.a)


## Bruit continu (+/- ~12% de luminosite) applique a une couleur de base -
## voir VoxelMeshBuilder._noise_modulated_color. Pur (aucune notion de neige/
## climat ici depuis le passage a 2 couleurs distinctes - voir
## grass_color_for/stone_color_for) : n'a donc plus besoin de
## get_top_block_y_fn, contrairement a avant (perf 2026-07-11 - un appel de
## moins par calcul de couleur).
static func noise_modulated_color(base: Color, noise: FastNoiseLite, pos: Vector3i) -> Color:
	var n: float = noise.get_noise_2d(float(pos.x), float(pos.z))  # -1..1
	var factor: float = 1.0 + n * 0.12
	return Color(
		clamp(base.r * factor, 0.0, 1.0),
		clamp(base.g * factor, 0.0, 1.0),
		clamp(base.b * factor, 0.0, 1.0),
		base.a
	)


## Couleur de l'herbe (dessus terre) - voir VoxelMeshBuilder._grass_color_for.
## "has_snow" (bool, plus un lerp continu par snow_coverage - perf 2026-07-11,
## voir doc de TemperatureSystem.SNOW_VISIBLE_THRESHOLD) : bascule vers
## "frozen_base" (meme bruit applique que la couleur normale, juste une autre
## base) au lieu de melanger progressivement vers du blanc a chaque frame -
## c'est ce changement de frequence de declenchement qui resout le freeze
## periodique (voir memoire regression I89).
static func grass_color_for(pos: Vector3i, terrain_noise: FastNoiseLite, climate_id: String, season_id: String, has_snow: bool, get_top_block_y_fn: Callable, dirt_underground_base: Color, penombre_factor: float, frozen_base: Color) -> Color:
	if is_underground(pos, get_top_block_y_fn):
		return apply_penombre(noise_modulated_color(dirt_underground_base, terrain_noise, pos), penombre_factor)
	var base: Color = frozen_base if has_snow else ClimateDefs.get_terrain_color(climate_id, season_id)
	return noise_modulated_color(base, terrain_noise, pos)


## Couleur de la pierre (dessus) - voir VoxelMeshBuilder._stone_color_for.
## Restructuree pour brancher sur is_underground EN PREMIER (comme
## grass_color_for ci-dessus, perf/coherence 2026-07-11) : la pierre
## souterraine ne doit jamais recevoir la variante "gelee" (pas de ciel pour
## neiger), seule la vraie surface exterieure en beneficie.
static func stone_color_for(pos: Vector3i, stone_noise: FastNoiseLite, has_snow: bool, get_top_block_y_fn: Callable, stone_base: Color, frozen_base: Color, penombre_factor: float) -> Color:
	if is_underground(pos, get_top_block_y_fn):
		return apply_penombre(noise_modulated_color(stone_base, stone_noise, pos), penombre_factor)
	var base: Color = frozen_base if has_snow else stone_base
	return noise_modulated_color(base, stone_noise, pos)


## Couleur UNIFORME du dessus d'un CUBE a la couche-frontiere - voir
## VoxelMeshBuilder._cube_top_color_for. "stone_type" = valeur entiere de
## BlockType.STONE (passee par l'appelant, jamais un enum duplique ici).
## Ne recoit JAMAIS la variante "gelee" (simplifie 2026-07-11, coherent avec
## sa propre doc "JAMAIS la teinte herbe/climat" - la fuite de neige vers ce
## dessus de CUBE etait un effet de bord de l'ancien melange generique dans
## noise_modulated_color, pas une intention delibree).
static func cube_top_color_for(pos: Vector3i, type: int, stone_type: int, stone_noise: FastNoiseLite, terrain_noise: FastNoiseLite, stone_base: Color, dirt_underground_base: Color, penombre_factor: float) -> Color:
	if type == stone_type:
		return apply_penombre(noise_modulated_color(stone_base, stone_noise, pos), penombre_factor)
	return apply_penombre(noise_modulated_color(dirt_underground_base, terrain_noise, pos), penombre_factor)


## Assombrissement d'arete/coin ("AO") sans geometrie supplementaire - voir
## VoxelMeshBuilder._ao_darken.
static func ao_darken(color: Color, pos: Vector3i, get_top_block_y_fn: Callable) -> Color:
	var here_top: int = get_top_block_y_fn.call(pos.x, pos.z)
	var lower_count := 0
	for dir2d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n_top: int = get_top_block_y_fn.call(pos.x + dir2d.x, pos.z + dir2d.y)
		if n_top < here_top:
			lower_count += 1
	var edge_factor: float = 1.0 - float(lower_count) * 0.08
	var h: int = (pos.x * 92837111) ^ (pos.z * 689287499)
	h = (h ^ (h >> 13)) * 1274126177
	var cell_factor: float = 0.90 + float(h & 0xFFFF) / 65535.0 * 0.2  # 0.90..1.10, discret par case
	var factor: float = edge_factor * cell_factor
	return Color(color.r * factor, color.g * factor, color.b * factor, color.a)


## Couleur d'un bloc de filon - voir VoxelMeshBuilder._vein_color_for.
static func vein_color_for(pos: Vector3i, vein_grid: Dictionary) -> Color:
	if not vein_grid.has(pos):
		return Color(0.5, 0.5, 0.5)
	var material: Dictionary = VeinMaterials.get_type(vein_grid[pos])
	return material.get("couleur", Color(0.5, 0.5, 0.5))


## Assombrit une couleur (parois de trous/murs) - voir VoxelMeshBuilder._darken.
static func darken(color: Color) -> Color:
	return Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, color.a)


## Materiau eclaire simple - voir VoxelMeshBuilder._make_material.
static func make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## Variante non eclairee - voir VoxelMeshBuilder._make_unshaded_material.
static func make_unshaded_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Materiau a couleur par sommet (herbe/pierre/filon) - voir
## VoxelMeshBuilder._make_vertex_color_material.
static func make_vertex_color_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## Variante non eclairee de make_vertex_color_material - voir
## VoxelMeshBuilder._make_unshaded_vertex_color_material.
static func make_unshaded_vertex_color_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Ajoute un quad (2 triangles) sur la face "dir" du bloc a "pos" - voir
## VoxelMeshBuilder._add_face.
static func add_face(st: SurfaceTool, pos: Vector3i, dir: Vector3i, face_color: Color = Color.WHITE) -> void:
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


## Variante de add_face pour une face bornee a [y0,y1] - voir
## VoxelMeshBuilder._add_face_y_range.
static func add_face_y_range(st: SurfaceTool, pos: Vector3i, dir: Vector3i, y0: float, y1: float, face_color: Color = Color.WHITE) -> void:
	var p := Vector3(pos.x, pos.y, pos.z)
	var verts: Array

	if dir == Vector3i(1, 0, 0):
		verts = [p + Vector3(1, y0, 0), p + Vector3(1, y1, 0), p + Vector3(1, y1, 1), p + Vector3(1, y0, 1)]
	elif dir == Vector3i(-1, 0, 0):
		verts = [p + Vector3(0, y0, 1), p + Vector3(0, y1, 1), p + Vector3(0, y1, 0), p + Vector3(0, y0, 0)]
	elif dir == Vector3i(0, 1, 0):
		verts = [p + Vector3(0, y1, 0), p + Vector3(0, y1, 1), p + Vector3(1, y1, 1), p + Vector3(1, y1, 0)]
	elif dir == Vector3i(0, -1, 0):
		verts = [p + Vector3(1, y0, 0), p + Vector3(1, y0, 1), p + Vector3(0, y0, 1), p + Vector3(0, y0, 0)]
	elif dir == Vector3i(0, 0, 1):
		verts = [p + Vector3(1, y0, 1), p + Vector3(1, y1, 1), p + Vector3(0, y1, 1), p + Vector3(0, y0, 1)]
	else: # Vector3i(0, 0, -1)
		verts = [p + Vector3(0, y0, 0), p + Vector3(0, y1, 0), p + Vector3(1, y1, 0), p + Vector3(1, y0, 0)]

	var normal := Vector3(dir.x, dir.y, dir.z)
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(face_color)
		st.set_normal(normal)
		st.add_vertex(verts[idx])


## Ajoute les 6 faces d'une "boite partielle" a l'interieur d'une case - voir
## VoxelMeshBuilder._add_box_faces.
static func add_box_faces(st: SurfaceTool, pos: Vector3i, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, color: Color) -> void:
	var p := Vector3(pos.x, pos.y, pos.z)
	var faces := [
		[Vector3(1, 0, 0), [p + Vector3(x1, y0, z0), p + Vector3(x1, y1, z0), p + Vector3(x1, y1, z1), p + Vector3(x1, y0, z1)]],
		[Vector3(-1, 0, 0), [p + Vector3(x0, y0, z1), p + Vector3(x0, y1, z1), p + Vector3(x0, y1, z0), p + Vector3(x0, y0, z0)]],
		[Vector3(0, 1, 0), [p + Vector3(x0, y1, z0), p + Vector3(x0, y1, z1), p + Vector3(x1, y1, z1), p + Vector3(x1, y1, z0)]],
		[Vector3(0, -1, 0), [p + Vector3(x1, y0, z0), p + Vector3(x1, y0, z1), p + Vector3(x0, y0, z1), p + Vector3(x0, y0, z0)]],
		[Vector3(0, 0, 1), [p + Vector3(x1, y0, z1), p + Vector3(x1, y1, z1), p + Vector3(x0, y1, z1), p + Vector3(x0, y0, z1)]],
		[Vector3(0, 0, -1), [p + Vector3(x0, y0, z0), p + Vector3(x0, y1, z0), p + Vector3(x1, y1, z0), p + Vector3(x1, y0, z0)]],
	]
	for face in faces:
		var normal: Vector3 = face[0]
		var verts: Array = face[1]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(color)
			st.set_normal(normal)
			st.add_vertex(verts[idx])
