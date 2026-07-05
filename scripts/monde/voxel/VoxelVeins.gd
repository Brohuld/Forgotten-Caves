extends RefCounted
## Decoupage de VoxelWorld.gd (2026-07-05, revue de code item C1 : fichier
## trop long / fonctions trop longues). Regroupe tout ce qui concerne les
## filons de metaux/pierres precieuses : bruit de placement, choix du
## materiau (_maybe_place_vein), et les pepites 3D incrustees sur les blocs
## de filon exposes (Sprint 23sexies, voir _rebuild_vein_pepites d'origine).
##
## Relocalisation pure : aucune logique changee, seulement deplacee. Instancie
## et garde par VoxelWorld.gd (var vein_system), qui porte desormais lui-meme
## l'etat (vein_grid/vein_noises/metal_pepites/gem_pepites) - VoxelWorld.gd
## delegue via des methodes (setup_vein_noises/setup_pepites_nodes/
## maybe_place_vein/rebuild_pepites) au lieu d'exposer directement ces
## dictionnaires/noeuds partout dans le fichier.
##
## Ce module NE prend jamais de reference typee vers VoxelWorld.gd lui-meme
## (pas de "world: VoxelWorld") : la vraie raison de ce decoupage est
## d'eviter le meme piege deja rencontre dans ce projet (voir
## WaterfallShapes.gd : un acces direct "voxel_world.WATER_COLOR" via une
## reference typee generique avait deja plante) - les quelques informations
## dont ce module a besoin depuis VoxelWorld (view_level, discovered,
## _is_face_exposed) sont passees en parametres simples (Dictionary/int/
## Callable), jamais via une reference typee croisee entre les deux scripts.

const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")

# Sprint 23 : seuil de bruit (0..1, plus c'est haut plus c'est rare) au-dela
# duquel un bloc de pierre devient un filon, par palier de rarete.
const RARITY_THRESHOLDS := {
	"commun": 0.45,
	"rare": 0.65,
	"tres_rare": 0.80,
}

# Sprint 23sexies : nombre de pepites 3D generees par bloc de filon visible
# (voir rebuild_pepites) - densite "beaucoup" choisie explicitement.
const PEPITE_COUNT_MIN := 6
const PEPITE_COUNT_MAX := 9

# Sprint 23sexies : rayon de base d'une pepite (unite = 1 bloc), multiplie par
# un facteur de rarete puis par une petite variation aleatoire par pepite.
const PEPITE_BASE_RADIUS := 0.09
const PEPITE_RARITY_SCALE := {
	"commun": 0.9,
	"rare": 1.15,
	"tres_rare": 1.4,
}

# Sprint 23 : filons. Cle = Vector3i (position bloc, toujours un bloc
# BlockType.STONE), valeur = id du materiau (voir MetalTypes.gd/GemTypes.gd).
var vein_grid: Dictionary = {}

# Sprint 23 : un bruit 3D independant par materiau de filon (metal/pierre
# precieuse), cle = id du materiau. Des seeds differentes evitent que tous
# les materiaux se superposent aux memes endroits.
var vein_noises: Dictionary = {}

# Sprint 23sexies : les deux MultiMeshInstance3D qui portent toutes les
# pepites (un pour les metaux, un pour les pierres precieuses).
var metal_pepites: MultiMeshInstance3D
var gem_pepites: MultiMeshInstance3D


## Cree un bruit 3D par materiau de filon (voir vein_noises). Frequence assez
## basse pour former des petits amas coherents plutot qu'un bruit poivre-et-
## sel bloc par bloc.
func setup_vein_noises() -> void:
	for entry in VeinMaterials.all():
		var n := FastNoiseLite.new()
		n.seed = randi()
		n.frequency = 0.16
		vein_noises[entry["id"]] = n


## Sprint 23sexies : cree les deux MultiMeshInstance3D qui portent les pepites
## (metaux/pierres precieuses), avec leur mesh et leur materiau. "parent" =
## le noeud VoxelWorld, auquel les deux MultiMeshInstance3D sont ajoutes.
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


## Sprint 23sexies : mesh d'une pepite - une SphereMesh integree au moteur,
## avec peu de segments pour les pierres precieuses (aspect a facettes) et
## beaucoup de segments pour les metaux (aspect rond/lisse).
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


## Sprint 23sexies : materiau des pepites - couleur par instance, avec un vrai
## eclairage. Metaux : reflets metalliques. Pierres precieuses : surface
## lisse/brillante + leger scintillement (emission).
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
func maybe_place_vein(pos: Vector3i, veins: Array) -> void:
	for entry in veins:
		var id: String = entry["id"]
		var threshold: float = RARITY_THRESHOLDS.get(entry["rarete"], 0.7)
		var noise: FastNoiseLite = vein_noises[id]
		var n: float = noise.get_noise_3d(float(pos.x), float(pos.y), float(pos.z))  # -1..1
		if n > threshold:
			vein_grid[pos] = id
			return


## Sprint 23sexies : recalcule entierement les pepites (metaux/pierres
## precieuses) a partir de vein_grid. Ne place des pepites que sur les blocs
## de filon qui ont au moins une face exposee. "is_face_exposed" est un
## Callable lie a VoxelWorld._is_face_exposed (passe en parametre plutot
## qu'une reference typee croisee, voir note en tete de fichier).
func rebuild_pepites(view_level: int, discovered: Dictionary, is_face_exposed: Callable, directions: Array) -> void:
	var metal_transforms: Array = []
	var metal_colors: Array = []
	var gem_transforms: Array = []
	var gem_colors: Array = []

	for pos in vein_grid.keys():
		if pos.y > view_level:
			continue
		# Sprint 35 : un filon jamais decouvert ne doit pas laisser deviner sa
		# presence via ses pepites.
		if not discovered.has(pos):
			continue
		var exposed_dir: Vector3i = Vector3i.ZERO
		var found_exposed := false
		for dir in directions:
			if is_face_exposed.call(pos + dir):
				exposed_dir = dir
				found_exposed = true
				break
		if not found_exposed:
			continue

		var material_id: String = vein_grid[pos]
		var material: Dictionary = VeinMaterials.get_type(material_id)
		var couleur: Color = material.get("couleur", Color(0.5, 0.5, 0.5))
		var rarete: String = material.get("rarete", "commun")
		var rarity_scale: float = PEPITE_RARITY_SCALE.get(rarete, 1.0)
		var is_metal: bool = VeinMaterials.is_metal(material_id)

		var block_seed: int = _seed_for_pos(pos)
		var count_rng := RandomNumberGenerator.new()
		count_rng.seed = block_seed
		var count: int = count_rng.randi_range(PEPITE_COUNT_MIN, PEPITE_COUNT_MAX)

		for i in range(count):
			var rng := RandomNumberGenerator.new()
			rng.seed = block_seed + i * 97
			var offset := _biased_local_offset(rng, exposed_dir)
			var world_pos := Vector3(pos.x, pos.y, pos.z) + offset
			var radius: float = PEPITE_BASE_RADIUS * rarity_scale * rng.randf_range(0.85, 1.15)
			var pepite_basis := Basis.from_euler(Vector3(
				rng.randf_range(0, TAU), rng.randf_range(0, TAU), rng.randf_range(0, TAU)
			)).scaled(Vector3.ONE * radius)
			var xform := Transform3D(pepite_basis, world_pos)

			if is_metal:
				metal_transforms.append(xform)
				metal_colors.append(couleur)
			else:
				gem_transforms.append(xform)
				gem_colors.append(couleur)

	_apply_pepite_instances(metal_pepites, metal_transforms, metal_colors)
	_apply_pepite_instances(gem_pepites, gem_transforms, gem_colors)


## Sprint 23sexies : applique une liste de transforms/couleurs a un
## MultiMeshInstance3D (redimensionne d'abord instance_count, puis remplit)
func _apply_pepite_instances(mmi: MultiMeshInstance3D, transforms: Array, colors: Array) -> void:
	mmi.multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		mmi.multimesh.set_instance_transform(i, transforms[i])
		mmi.multimesh.set_instance_color(i, colors[i])


## Sprint 23sexies : seed deterministe a partir d'une position de bloc - les
## pepites d'un bloc donne restent toujours les memes d'un rebuild a l'autre.
func _seed_for_pos(pos: Vector3i) -> int:
	return pos.x * 73856093 ^ pos.y * 19349663 ^ pos.z * 83492791


## Sprint 23sexies : position locale (0..1 dans le bloc) d'une pepite, tiree au
## sort mais poussee vers la face exposee "dir" pour que la pepite affleure/
## depasse legerement de cette face au lieu d'etre cachee a l'interieur du bloc.
func _biased_local_offset(rng: RandomNumberGenerator, dir: Vector3i) -> Vector3:
	var v := Vector3(rng.randf_range(0.25, 0.75), rng.randf_range(0.25, 0.75), rng.randf_range(0.25, 0.75))
	if dir.x != 0:
		v.x = 0.5 + sign(dir.x) * rng.randf_range(0.38, 0.55)
	if dir.y != 0:
		v.y = 0.5 + sign(dir.y) * rng.randf_range(0.38, 0.55)
	if dir.z != 0:
		v.z = 0.5 + sign(dir.z) * rng.randf_range(0.38, 0.55)
	return v
