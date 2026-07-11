extends RefCounted
## Construction geometrique PURE d'un arbre (racines/tronc/branches/feuillage/
## fruits) - extrait de Forest.gd (revue de code C20, 2026-07-11 : fichier a
## 959 lignes) pour separer "a quoi ressemble un arbre" du cycle de vie
## (spawn/repousse/coupe/saison/niveau de vue), qui reste dans Forest.gd.
##
## Fonctions STATIQUES, aucun etat propre - Forest.gd garde la PROPRIETE de
## tout l'etat partage (MultiMeshInstance3D, tableaux d'instances en attente/
## affichees). Chaque fonction qui doit enregistrer une piece recoit un
## "record_fn: Callable" (lie a Forest._record_part) au lieu d'ecrire
## directement dans les dictionnaires de Forest.gd - permet de deplacer le
## CODE sans deplacer l'ETAT ni changer l'ordre reel des appels (important
## pour la reproductibilite par graine, voir Forest.gd/_spawn_tree).
##
## build_fruits() ne prend pas de record_fn : les fruits restent des noeuds
## Godot individuels (jamais convertis en MultiMesh, voir doc de Forest.gd),
## logique inchangee, deplacee telle quelle.
##
## Chaque fonction qui enregistre une piece recoit le(s) PartType concerne(s)
## en parametre entier (part_type_xxx), plutot que de dupliquer l'enum
## PartType de Forest.gd ici (evite exactement le piege deja releve ailleurs
## dans la revue de code - enum duplique a la main, desynchronisation
## possible sans erreur visible, voir VoxelMeshBuilder.BlockType).


static func make_cylinder_mesh(top_radius: float, bottom_radius: float, height: float, radial_segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	return mesh


static func make_sphere_mesh(radius: float, radial_segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	return mesh


static func make_box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## Cree un MultiMeshInstance3D a couleur-par-instance et l'ajoute a "parent" -
## meme materiau "plat" (roughness=1/metallic=0) que le reste du rendu.
static func make_mmi(mesh: Mesh, parent: Node3D) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = MultiMesh.new()
	mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	mmi.multimesh.use_colors = true
	mmi.multimesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	mat.metallic = 0.0
	mmi.material_override = mat
	parent.add_child(mmi)
	return mmi


## Petite base evasee au pied du tronc (racines).
static func build_roots(refs: Array, tree_xform: Transform3D, species: Dictionary, tint: float, part_type_roots: int, record_fn: Callable) -> void:
	var mesh_height := 0.22
	var local_xform := Transform3D(Basis(), Vector3(0, 0.11, 0))
	var color: Color = species["racine_color"] * tint
	record_fn.call(refs, tree_xform * local_xform, part_type_roots, color, Vector3(1.0, mesh_height, 1.0))


## Tronc effile - hauteur dependante de l'espece. Pour le sapin (feuillage
## conique), le tronc visuel est plus court que trunk_height (le reste est
## recouvert par le feuillage, voir build_foliage_conique). Renvoie la
## hauteur visuelle du tronc (= trunk_height pour les autres formes).
static func build_trunk(refs: Array, tree_xform: Transform3D, species: Dictionary, trunk_height: float, tint: float, part_type_trunk: int, record_fn: Callable) -> float:
	var visual_height: float = trunk_height
	if species.get("forme", "touffu") == "conique":
		visual_height = max(trunk_height * 0.12, 0.18)

	var local_xform := Transform3D(Basis(), Vector3(0, 0.22 + visual_height * 0.5, 0))
	var color: Color = species["tronc_color"] * tint
	record_fn.call(refs, tree_xform * local_xform, part_type_trunk, color, Vector3(1.0, visual_height, 1.0))
	return visual_height


## 3 a 6 branches partant du haut du tronc, chacune avec une grappe de
## "feuilles" a son extremite. Aucune branche pour le sapin (feuillage
## conique). L'ordre des tirages aleatoires doit rester stable (graine).
static func build_branches(refs: Array, tree_xform: Transform3D, species: Dictionary, trunk_height: float, tint: float, part_type_branch: int, part_type_leaf: int, record_fn: Callable) -> void:
	if species.get("forme", "touffu") == "conique":
		return
	# Flux GameRandom dedie ("arbres_geometrie", meme flux que Forest.gd) -
	# reproductibilite par graine isolee des autres systemes (corrige I86
	# 2026-07-11, voir doc GameRandom.gd). L'autoload GameRandom est
	# accessible directement meme depuis une fonction statique.
	var rng: RandomNumberGenerator = GameRandom.get_rng("arbres_geometrie")
	var branch_count: int = rng.randi_range(4, 6)
	var trunk_top_y: float = 0.22 + trunk_height
	var colors: Array = species["feuillage_colors"]
	for i in range(branch_count):
		var pivot_y: float = trunk_top_y + rng.randf_range(-0.25, 0.15)
		var pivot_angle: float = (TAU / float(branch_count)) * i + rng.randf_range(-0.3, 0.3)
		var pivot_xform: Transform3D = tree_xform * Transform3D(Basis.from_euler(Vector3(0, pivot_angle, 0)), Vector3(0, pivot_y, 0))

		var branch_length: float = rng.randf_range(0.5, 0.8)
		var branch_xform: Transform3D = pivot_xform * Transform3D(Basis.from_euler(Vector3(deg_to_rad(65), 0, 0)), Vector3(0, branch_length * 0.5, 0.12))
		var branch_color: Color = species["branche_color"] * tint
		record_fn.call(refs, branch_xform, part_type_branch, branch_color, Vector3(1.0, branch_length, 1.0))

		var tip_xform: Transform3D = branch_xform * Transform3D(Basis(), Vector3(0, branch_length * 0.5, 0))
		build_leaf_cluster(refs, tip_xform, colors, tint, rng.randi_range(6, 9), 0.12, part_type_leaf, record_fn)


## Aiguille le bon type de feuillage selon la "forme" de l'espece. Renvoie la
## liste des blobs de feuillage crees (Array de {"position": Vector3,
## "radius": float}, coordonnees locales a "tree") - vide pour le feuillage
## conique (sapin, jamais un arbre fruitier). Utilise par build_fruits pour
## ancrer chaque fruit a un vrai blob.
static func build_foliage(refs: Array, tree_xform: Transform3D, species: Dictionary, trunk_height: float, trunk_visual_height: float, tint: float, part_type_cone: int, part_type_blob: int, part_type_leaf: int, record_fn: Callable) -> Array:
	var top_y: float = 0.22 + trunk_height
	match species.get("forme", "touffu"):
		"conique":
			build_foliage_conique(refs, tree_xform, species, 0.22 + trunk_visual_height, top_y, tint, part_type_cone, record_fn)
			return []
		"fin":
			return build_foliage_fin(refs, tree_xform, species, top_y, tint, part_type_blob, part_type_leaf, record_fn)
		_:
			return build_foliage_touffu(refs, tree_xform, species, top_y, tint, part_type_blob, part_type_leaf, record_fn)


## Feuillage touffu (chene, arbres fruitiers) : spheres qui se chevauchent,
## placees legerement asymetriquement, chacune avec une petite grappe de
## "feuilles" a sa surface.
static func build_foliage_touffu(refs: Array, tree_xform: Transform3D, species: Dictionary, top_y: float, tint: float, part_type_blob: int, part_type_leaf: int, record_fn: Callable) -> Array:
	var echelle: float = species.get("feuillage_echelle", 1.0)
	return build_blob_foliage(refs, tree_xform, species, top_y, tint, 4, 6, 0.38 * echelle, 0.55 * echelle, 0.26 * echelle, 0.05, 0.65, 7, 10, part_type_blob, part_type_leaf, record_fn)


## Feuillage conique (sapin) : 5-6 cones empiles du sommet du tronc visuel
## jusqu'en haut de l'arbre.
static func build_foliage_conique(refs: Array, tree_xform: Transform3D, species: Dictionary, start_y: float, top_y: float, tint: float, part_type_cone: int, record_fn: Callable) -> void:
	var colors: Array = species["feuillage_colors"]
	# Voir doc de build_branches ci-dessus (flux GameRandom "arbres_geometrie").
	var levels: int = GameRandom.get_rng("arbres_geometrie").randi_range(5, 6)
	var span: float = max(top_y - start_y, 0.3)
	var level_height: float = span / float(levels) * 1.4
	var y := start_y
	for i in range(levels):
		var t: float = float(i) / float(max(levels - 1, 1))
		var bottom_radius: float = lerp(0.48, 0.10, t)
		var local_xform := Transform3D(Basis(), Vector3(0, y + level_height * 0.5, 0))
		var cone_color: Color = colors[i % colors.size()] * tint
		record_fn.call(refs, tree_xform * local_xform, part_type_cone, cone_color, Vector3(bottom_radius, level_height, bottom_radius))
		y += span / float(levels)


## Feuillage fin/eparse (bouleau) : touffes plus petites/moins denses que le
## chene.
static func build_foliage_fin(refs: Array, tree_xform: Transform3D, species: Dictionary, top_y: float, tint: float, part_type_blob: int, part_type_leaf: int, record_fn: Callable) -> Array:
	return build_blob_foliage(refs, tree_xform, species, top_y, tint, 3, 5, 0.26, 0.38, 0.22, 0.0, 0.55, 6, 8, part_type_blob, part_type_leaf, record_fn)


## Logique commune a build_foliage_touffu/build_foliage_fin - seuls les
## nombres/tailles/plages different par espece. "blob_data" renvoie une
## position LOCALE a l'arbre (utilisee par build_fruits).
static func build_blob_foliage(refs: Array, tree_xform: Transform3D, species: Dictionary, top_y: float, tint: float,
		cluster_count_min: int, cluster_count_max: int,
		radius_min: float, radius_max: float,
		xz_spread: float, y_min: float, y_max: float,
		leaf_count_min: int, leaf_count_max: int, part_type_blob: int, part_type_leaf: int, record_fn: Callable) -> Array:
	var colors: Array = species["feuillage_colors"]
	# Voir doc de build_branches ci-dessus (flux GameRandom "arbres_geometrie").
	var rng: RandomNumberGenerator = GameRandom.get_rng("arbres_geometrie")
	var cluster_count: int = rng.randi_range(cluster_count_min, cluster_count_max)
	var blob_data: Array = []
	for i in range(cluster_count):
		var radius: float = rng.randf_range(radius_min, radius_max)
		var blob_local_pos := Vector3(
			rng.randf_range(-xz_spread, xz_spread),
			top_y + rng.randf_range(y_min, y_max),
			rng.randf_range(-xz_spread, xz_spread)
		)
		var blob_xform: Transform3D = tree_xform * Transform3D(Basis(), blob_local_pos)
		var blob_color: Color = colors[rng.randi_range(0, colors.size() - 1)] * tint
		record_fn.call(refs, blob_xform, part_type_blob, blob_color, Vector3.ONE * radius)
		build_leaf_cluster(refs, blob_xform, colors, tint, rng.randi_range(leaf_count_min, leaf_count_max), radius * 0.8, part_type_leaf, record_fn)
		blob_data.append({"position": blob_local_pos, "radius": radius})
	return blob_data


## Petite grappe de "feuilles" (plaques plates fines) autour d'un point donne.
## Ordre des tirages (taille, position, rotation, couleur) fixe (graine).
static func build_leaf_cluster(refs: Array, parent_xform: Transform3D, colors: Array, tint: float, count: int, spread: float, part_type_leaf: int, record_fn: Callable) -> void:
	# Voir doc de build_branches ci-dessus (flux GameRandom "arbres_geometrie").
	var rng: RandomNumberGenerator = GameRandom.get_rng("arbres_geometrie")
	for i in range(count):
		var leaf_size := Vector3(rng.randf_range(0.05, 0.08), 0.01, rng.randf_range(0.03, 0.05))
		var leaf_pos := Vector3(
			rng.randf_range(-spread, spread),
			rng.randf_range(-spread, spread),
			rng.randf_range(-spread, spread)
		)
		var leaf_rot := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, TAU), rng.randf_range(-0.5, 0.5))
		var leaf_color: Color = colors[rng.randi_range(0, colors.size() - 1)] * tint
		var leaf_local := Transform3D(Basis.from_euler(leaf_rot), leaf_pos)
		record_fn.call(refs, parent_xform * leaf_local, part_type_leaf, leaf_color, leaf_size)


## Fruits de l'arbre (arbres fruitiers uniquement) - petites spheres colorees
## dispersees pres du feuillage, nommees "Fruit_%d". PAS convertis en
## MultiMesh (doivent disparaitre un par un a la cueillette) - noeuds
## individuels ajoutes directement a "tree". Chaque fruit est ancre a la
## surface d'un blob de feuillage REELLEMENT cree (blob_data), avec une
## petite marge pour rester visible en depassant un peu.
static func build_fruits(tree: Node3D, species: Dictionary, trunk_height: float, fruit_count: int, blob_data: Array, sphere_radial_segments: int, sphere_rings: int) -> void:
	var top_y: float = 0.22 + trunk_height
	var mat := flat_material(species["fruit_color"])
	var fruit_radius: float = species.get("fruit_radius", 0.13)
	# Voir doc de build_branches ci-dessus (flux GameRandom "arbres_geometrie").
	var rng: RandomNumberGenerator = GameRandom.get_rng("arbres_geometrie")
	# Repartition en "tourniquet" (tous les blobs melanges puis pris a leur
	# tour) plutot qu'un tirage au hasard par fruit - garantit une repartition
	# equilibree meme avec peu de blobs (4-6) et beaucoup de fruits.
	# Fisher-Yates a la main avec "rng" plutot qu'Array.shuffle() (qui pioche
	# dans le RNG global de Godot, pas dans le flux GameRandom dedie - meme
	# piege que randf()/randi() ici, corrige I86 2026-07-11).
	var blobs_shuffled: Array = blob_data.duplicate()
	for i in range(blobs_shuffled.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = blobs_shuffled[i]
		blobs_shuffled[i] = blobs_shuffled[j]
		blobs_shuffled[j] = tmp
	for i in range(fruit_count):
		var fruit := MeshInstance3D.new()
		fruit.name = "Fruit_%d" % i
		var mesh := SphereMesh.new()
		mesh.radius = fruit_radius
		mesh.height = fruit_radius * 2.0
		mesh.radial_segments = sphere_radial_segments
		mesh.rings = sphere_rings
		fruit.mesh = mesh
		if blobs_shuffled.is_empty():
			var angle := rng.randf_range(0.0, TAU)
			fruit.position = Vector3(
				cos(angle) * 0.5,
				top_y + rng.randf_range(-0.05, 0.65),
				sin(angle) * 0.5
			)
		else:
			var blob: Dictionary = blobs_shuffled[i % blobs_shuffled.size()]
			var blob_pos: Vector3 = blob["position"]
			var blob_radius: float = blob["radius"]
			var az := rng.randf_range(0.0, TAU)
			var elev := rng.randf_range(deg_to_rad(-90.0), deg_to_rad(90.0))
			var dir := Vector3(cos(elev) * cos(az), sin(elev), cos(elev) * sin(az))
			var dist := blob_radius * rng.randf_range(0.85, 1.05)
			fruit.position = blob_pos + dir * dist
		fruit.set_surface_override_material(0, mat)
		tree.add_child(fruit)


## Materiau plat (pas de texture/reflet), eclairage reel - utilise uniquement
## par build_fruits (seule piece d'arbre restee un vrai noeud/materiau).
static func flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat
