extends RefCounted
## Gere tout ce qui concerne les filons de metaux/pierres precieuses :
## bruit de placement, choix du materiau (_maybe_place_vein), et les pepites
## 3D incrustees sur les blocs de filon exposes (_rebuild_vein_pepites).
##
## Instancie et garde par VoxelWorld.gd (var vein_system), qui porte
## l'etat (vein_grid/vein_noises/metal_pepites/gem_pepites) - VoxelWorld.gd
## delegue via des methodes (setup_vein_noises/setup_pepites_nodes/
## maybe_place_vein/remove_vein/rebuild_pepites) au lieu d'exposer directement
## ces dictionnaires/noeuds partout dans le fichier.
##
## Ce module ne prend jamais de reference typee vers VoxelWorld.gd lui-meme
## (pas de "world: VoxelWorld") pour eviter le piege des references croisees
## typees entre scripts (voir WaterfallShapes.gd) : les quelques informations
## dont ce module a besoin depuis VoxelWorld (view_level, discovered,
## _is_face_exposed) sont passees en parametres simples (Dictionary/int/
## Callable).

const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")

# Seuil de bruit (0..1, plus c'est haut plus c'est rare) au-dela duquel un
# bloc de pierre devient un filon, par palier de rarete.
const RARITY_THRESHOLDS := {
	"commun": 0.45,
	"rare": 0.65,
	"tres_rare": 0.80,
}

# Nombre de pepites 3D generees par bloc de filon visible (voir
# rebuild_pepites) - densite volontairement haute pour un effet visuel riche.
const PEPITE_COUNT_MIN := 6
const PEPITE_COUNT_MAX := 9

# Rayon de base d'une pepite (unite = 1 bloc), multiplie par un facteur de
# rarete puis par une petite variation aleatoire par pepite.
const PEPITE_BASE_RADIUS := 0.09
const PEPITE_RARITY_SCALE := {
	"commun": 0.9,
	"rare": 1.15,
	"tres_rare": 1.4,
}

# Filons. Cle = Vector3i (position bloc, toujours un bloc BlockType.STONE),
# valeur = id du materiau (voir MetalTypes.gd/GemTypes.gd). Mutations
# TOUJOURS via maybe_place_vein (ajout) et remove_vein (retrait) - jamais un
# acces direct depuis VoxelWorld.gd - pour que vein_grid_by_xz (index) et
# _visible_veins (cache, voir plus bas) restent a jour sans effort ailleurs.
var vein_grid: Dictionary = {}

# Index PAR COLONNE de vein_grid (Vector2i(x,z) -> Dictionary[Vector3i, true])
# - fix perf 2026-07-11 (Francois : "tu refais le fix sur les filons ?" une
# fois le fix definitif (Y, CHUNK) de VoxelMeshBuilder.gd valide en jeu, voir
# memoire regression "terrain transparent"). Meme principe que
# VoxelWorld.discovered_by_xz/sol_grid_by_xz : permet a rebuild_pepites() de
# ne reexaminer que les filons d'une zone bornee (dirty box +-1) au lieu de
# TOUT vein_grid a chaque minage.
var vein_grid_by_xz: Dictionary = {}

# Un bruit 3D independant par materiau de filon (metal/pierre precieuse),
# cle = id du materiau. Des seeds differentes evitent que tous les materiaux
# se superposent aux memes endroits.
var vein_noises: Dictionary = {}

# Les deux MultiMeshInstance3D qui portent toutes les pepites (un pour les
# metaux, un pour les pierres precieuses).
var metal_pepites: MultiMeshInstance3D
var gem_pepites: MultiMeshInstance3D

# Cache PERSISTANT des filons actuellement VISIBLES (voir rebuild_pepites) -
# Vector3i (position du filon) -> {"is_metal": bool, "color": Color,
# "transforms": Array[Transform3D]}. La geometrie d'un filon ne change JAMAIS
# une fois calculee (seed deterministe, voir _seed_for_pos) - seule sa
# VISIBILITE (discovered/view_level/face exposee) change au fil du jeu, donc
# inutile de la recalculer tant qu'un filon reste visible d'un rebuild a
# l'autre. Rempli/vide de facon incrementale par rebuild_pepites, jamais
# reconstruit en bloc (sauf balayage complet, voir sa doc).
var _visible_veins: Dictionary = {}

# view_level lors du dernier rebuild_pepites - un changement de niveau de vue
# peut modifier la visibilite de N'IMPORTE QUEL filon deja decouvert (pas
# seulement ceux d'une zone sale), donc force un balayage complet la
# prochaine fois qu'il change (voir rebuild_pepites). -1 au depart : le tout
# premier appel est toujours complet.
var _last_view_level: int = -1


## Cree un bruit 3D par materiau de filon (voir vein_noises). Frequence assez
## basse pour former des petits amas coherents plutot qu'un bruit poivre-et-
## sel bloc par bloc. Flux GameRandom dedie "filons_bruit" (voir GameRandom.gd)
## pour rester deterministe/reproductible d'une partie a l'autre.
func setup_vein_noises() -> void:
	var rng: RandomNumberGenerator = GameRandom.get_rng("filons_bruit")
	for entry in VeinMaterials.all():
		var n := FastNoiseLite.new()
		n.seed = rng.randi()
		n.frequency = 0.16
		vein_noises[entry["id"]] = n


## Cree les deux MultiMeshInstance3D qui portent les pepites (metaux/pierres
## precieuses), avec leur mesh et leur materiau. "parent" = le noeud
## VoxelWorld, auquel les deux MultiMeshInstance3D sont ajoutes.
func setup_pepites_nodes(parent: Node3D) -> void:
	metal_pepites = MultiMeshInstance3D.new()
	metal_pepites.multimesh = MultiMesh.new()
	metal_pepites.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	metal_pepites.multimesh.use_colors = true
	metal_pepites.multimesh.mesh = _make_pepite_mesh(true)
	metal_pepites.material_override = _make_pepite_material(true)
	parent.add_child(metal_pepites)

	gem_pepites = MultiMeshInstance3D.new()
	gem_pepites.multimesh = MultiMesh.new()
	gem_pepites.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	gem_pepites.multimesh.use_colors = true
	gem_pepites.multimesh.mesh = _make_pepite_mesh(false)
	gem_pepites.material_override = _make_pepite_material(false)
	parent.add_child(gem_pepites)


## Mesh d'une pepite - une SphereMesh integree au moteur, avec peu de segments
## pour les pierres precieuses (aspect a facettes) et beaucoup de segments
## pour les metaux (aspect rond/lisse).
func _make_pepite_mesh(is_metal: bool) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	if is_metal:
		mesh.radial_segments = 10
		mesh.rings = 6
	else:
		mesh.radial_segments = 5
		mesh.rings = 3
	return mesh


## Materiau des pepites - couleur par instance, avec un vrai eclairage.
## Metaux : reflets metalliques. Pierres precieuses : surface lisse/brillante
## + leger scintillement (emission).
func _make_pepite_material(is_metal: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	if is_metal:
		mat.metallic = 0.85
		mat.roughness = 0.25
	else:
		mat.metallic = 0.0
		mat.roughness = 0.05
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.97, 0.85)
		mat.emission_energy_multiplier = 0.15
	return mat


## Tire au sort si la case de pierre "pos" devient un filon. Parcourt les
## materiaux du plus rare au plus commun et s'arrete au premier qui "matche".
## Maintient vein_grid_by_xz (voir sa doc) en meme temps que vein_grid.
func maybe_place_vein(pos: Vector3i, veins: Array) -> void:
	for entry in veins:
		var id: String = entry["id"]
		# Si "id" n'a pas ete enregistre via setup_vein_noises() (materiau
		# absent/mal configure), on l'ignore avec un avertissement plutot que
		# de planter.
		if not vein_noises.has(id):
			push_warning("VoxelVeins: materiau de filon inconnu '%s' (non enregistre via setup_vein_noises)" % id)
			continue
		var threshold: float = RARITY_THRESHOLDS.get(entry["rarete"], 0.7)
		var noise: FastNoiseLite = vein_noises[id]
		var n: float = noise.get_noise_3d(float(pos.x), float(pos.y), float(pos.z))  # -1..1
		if n > threshold:
			vein_grid[pos] = id
			var col := Vector2i(pos.x, pos.z)
			if not vein_grid_by_xz.has(col):
				vein_grid_by_xz[col] = {}
			vein_grid_by_xz[col][pos] = true
			return


## Retire le filon a "pos" (mine par le joueur) - renvoie son id (ou "" si
## aucun filon ici). SEUL point d'acces en ecriture pour un retrait : purge
## vein_grid, vein_grid_by_xz ET _visible_veins (le filon vient de disparaitre
## de la carte, ses pepites ne doivent plus jamais s'afficher, meme si un
## futur rebuild_pepites restreint ne repasse plus par cette position - voir
## sa doc). Appele par VoxelWorld._remove_block_silent au lieu d'un acces
## direct a vein_system.vein_grid (encapsulation, perf 2026-07-11).
func remove_vein(pos: Vector3i) -> String:
	if not vein_grid.has(pos):
		return ""
	var vid: String = vein_grid[pos]
	vein_grid.erase(pos)
	var col := Vector2i(pos.x, pos.z)
	if vein_grid_by_xz.has(col):
		vein_grid_by_xz[col].erase(pos)
	_visible_veins.erase(pos)
	return vid


## Recalcule les pepites (metaux/pierres precieuses) visibles a partir de
## vein_grid. Ne place des pepites que sur les blocs de filon qui ont au
## moins une face exposee, sont decouverts, et sont a/au-dessus du niveau de
## vue courant. "is_face_exposed" est un Callable lie a
## VoxelWorld._is_face_exposed (passe en parametre plutot qu'une reference
## typee croisee, voir note en tete de fichier).
##
## dirty_y/x/z_min/max (memes valeurs que VoxelMeshBuilder._build_layer_cache,
## voir sa doc) : perf 2026-07-11, mesure Francois ("veins=103.6ms" sur un
## TOTAL de ~162ms) - balayer vein_grid.keys() EN ENTIER (tous les filons deja
## decouverts, potentiellement des milliers sur une grande carte) a CHAQUE
## minage, pour ne finalement (re)trouver visibles qu'une poignee de filons
## nouveaux/masques, etait le vrai cout. Desormais : si une zone sale est
## fournie ET que view_level n'a pas change depuis le dernier appel, SEULS les
## filons de cette zone (elargie de 1 case, une face peut s'exposer/se cacher
## a cause d'un voisin tout juste mine) sont re-examines - _visible_veins
## (cache persistant, voir sa doc) conserve l'etat des autres filons
## INCHANGE. Un changement de view_level force un balayage complet (la
## visibilite de N'IMPORTE QUEL filon deja decouvert peut alors changer,
## impossible a borner par zone). Meme principe de zone-a-granularite-fixe
## que le fix (Y, CHUNK) de VoxelMeshBuilder.gd (voir sa doc CHUNK_SIZE) :
## la geometrie finale des MultiMesh est reconstruite a partir de
## _visible_veins.values() (borne au nombre de filons VISIBLES, pas au total
## de vein_grid).
func rebuild_pepites(view_level: int, discovered: Dictionary, is_face_exposed: Callable, directions: Array,
		dirty_y_min: int = -1, dirty_y_max: int = -1,
		dirty_x_min: int = -1, dirty_x_max: int = -1, dirty_z_min: int = -1, dirty_z_max: int = -1) -> void:
	var restrict: bool = dirty_x_min != -1 and view_level == _last_view_level
	_last_view_level = view_level

	var candidates: Array
	if restrict:
		# Zone elargie de 1 case en X/Z/Y : le mineur ne revele jamais un
		# voisin au-dela de cette marge (voir VoxelWorld._remove_block_silent,
		# DIRECTIONS + HORIZONTAL_DIAGONALS), donc aucune exposition de filon
		# en dehors ne peut avoir change.
		var x0: int = dirty_x_min - 1
		var x1: int = dirty_x_max + 1
		var z0: int = dirty_z_min - 1
		var z1: int = dirty_z_max + 1
		var y0: int = dirty_y_min - 1
		var y1: int = dirty_y_max + 1
		var seen: Dictionary = {}
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				var col := Vector2i(x, z)
				if not vein_grid_by_xz.has(col):
					continue
				for pos in (vein_grid_by_xz[col] as Dictionary).keys():
					if pos.y < y0 or pos.y > y1:
						continue
					seen[pos] = true
		candidates = seen.keys()
	else:
		candidates = vein_grid.keys()

	for pos in candidates:
		if not vein_grid.has(pos):
			# Filon deja retire (voir remove_vein) - defensif, ne devrait
			# normalement plus arriver ici (remove_vein purge deja
			# _visible_veins directement).
			_visible_veins.erase(pos)
			continue
		if pos.y > view_level or not discovered.has(pos):
			_visible_veins.erase(pos)
			continue
		var exposed: Array = _find_exposed_dir(pos, is_face_exposed, directions)
		if not exposed[0]:
			_visible_veins.erase(pos)
			continue
		if not _visible_veins.has(pos):
			_visible_veins[pos] = _compute_pepite_geometry(pos, vein_grid[pos], exposed[1])
		# Deja visible : la geometrie (seed deterministe par bloc, voir
		# _seed_for_pos) ne change jamais - rien a refaire.

	var metal_transforms: Array = []
	var metal_colors: Array = []
	var gem_transforms: Array = []
	var gem_colors: Array = []
	for pos in _visible_veins.keys():
		var entry: Dictionary = _visible_veins[pos]
		var target_transforms: Array = metal_transforms if entry["is_metal"] else gem_transforms
		var target_colors: Array = metal_colors if entry["is_metal"] else gem_colors
		for xform in (entry["transforms"] as Array):
			target_transforms.append(xform)
			target_colors.append(entry["color"])

	_apply_pepite_instances(metal_pepites, metal_transforms, metal_colors)
	_apply_pepite_instances(gem_pepites, gem_transforms, gem_colors)


## Premiere direction (parmi "directions") ou le voisin de "pos" est vide -
## factorise entre rebuild_pepites (visibilite) et _compute_pepite_geometry
## (biais visuel vers la face exposee). Renvoie [true, dir] si trouve, sinon
## [false, Vector3i.ZERO] (le 2e element est alors sans signification).
func _find_exposed_dir(pos: Vector3i, is_face_exposed: Callable, directions: Array) -> Array:
	for dir in directions:
		if is_face_exposed.call(pos + dir):
			return [true, dir]
	return [false, Vector3i.ZERO]


## Calcule (une seule fois par filon, voir _visible_veins) la geometrie
## figee d'un filon visible : couleur + liste de Transform3D de ses pepites.
## Extrait de l'ancienne rebuild_pepites monolithique (perf 2026-07-11) -
## logique de tirage au sort inchangee (meme seed deterministe par bloc).
func _compute_pepite_geometry(pos: Vector3i, material_id: String, exposed_dir: Vector3i) -> Dictionary:
	var material: Dictionary = VeinMaterials.get_type(material_id)
	var couleur: Color = material.get("couleur", Color(0.5, 0.5, 0.5))
	var rarete: String = material.get("rarete", "commun")
	var rarity_scale: float = PEPITE_RARITY_SCALE.get(rarete, 1.0)
	var is_metal: bool = VeinMaterials.is_metal(material_id)

	var block_seed: int = _seed_for_pos(pos)
	var count_rng := RandomNumberGenerator.new()
	count_rng.seed = block_seed
	var count: int = count_rng.randi_range(PEPITE_COUNT_MIN, PEPITE_COUNT_MAX)

	var transforms: Array = []
	for i in range(count):
		var rng := RandomNumberGenerator.new()
		rng.seed = block_seed + i * 97
		var offset := _biased_local_offset(rng, exposed_dir)
		var world_pos := Vector3(pos.x, pos.y, pos.z) + offset
		var radius: float = PEPITE_BASE_RADIUS * rarity_scale * rng.randf_range(0.85, 1.15)
		var pepite_basis := Basis.from_euler(Vector3(
			rng.randf_range(0, TAU), rng.randf_range(0, TAU), rng.randf_range(0, TAU)
		)).scaled(Vector3.ONE * radius)
		transforms.append(Transform3D(pepite_basis, world_pos))

	return {"is_metal": is_metal, "color": couleur, "transforms": transforms}


## Applique une liste de transforms/couleurs a un MultiMeshInstance3D
## (redimensionne d'abord instance_count, puis remplit).
func _apply_pepite_instances(mmi: MultiMeshInstance3D, transforms: Array, colors: Array) -> void:
	mmi.multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		mmi.multimesh.set_instance_transform(i, transforms[i])
		mmi.multimesh.set_instance_color(i, colors[i])


## Seed deterministe a partir d'une position de bloc - les pepites d'un bloc
## donne restent toujours les memes d'un rebuild a l'autre.
func _seed_for_pos(pos: Vector3i) -> int:
	return pos.x * 73856093 ^ pos.y * 19349663 ^ pos.z * 83492791


## Position locale (0..1 dans le bloc) d'une pepite, tiree au sort mais
## poussee vers la face exposee "dir" pour que la pepite affleure/depasse
## legerement de cette face au lieu d'etre cachee a l'interieur du bloc.
func _biased_local_offset(rng: RandomNumberGenerator, dir: Vector3i) -> Vector3:
	var v := Vector3(rng.randf_range(0.25, 0.75), rng.randf_range(0.25, 0.75), rng.randf_range(0.25, 0.75))
	if dir.x != 0:
		v.x = 0.5 + sign(dir.x) * rng.randf_range(0.38, 0.55)
	if dir.y != 0:
		v.y = 0.5 + sign(dir.y) * rng.randf_range(0.38, 0.55)
	if dir.z != 0:
		v.z = 0.5 + sign(dir.z) * rng.randf_range(0.38, 0.55)
	return v
