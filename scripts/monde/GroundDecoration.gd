extends Node3D
## Decoration legere du sol (touffes d'herbe, fleurs, petits cailloux) pour
## casser la monotonie visuelle du damier de terre. Purement decoratif
## (aucune interaction, contrairement aux buissons a baies) : generee une
## seule fois au demarrage, a partir de l'etat initial du terrain (une
## decoration ne disparait pas si le bloc en-dessous est mine ensuite - voir
## remove_decoration_at pour la seule exception geree explicitement).
##
## La couleur de base de l'herbe/des fleurs depend du climat de la carte
## (ClimateDefinitions.gd). Un seul climat existe reellement pour l'instant
## (tempere), mais la structure est prete a en accueillir d'autres plus tard
## (climate_id est deja un champ expose).
##
## Comme Forest.gd/BerryBushes.gd, chaque decoration est construite comme un
## Node3D temporaire (permet de laisser Godot calculer le global_transform
## de chaque piece via la hierarchie normale), dont le global_transform +
## couleur + taille sont ensuite recoltes dans des MultiMeshInstance3D
## partages (voir PartType) avant que le noeud temporaire soit libere.
## Contrairement aux arbres/buissons, aucune decoration n'a d'interaction
## individuelle (jamais cliquee, jamais retiree une par une) : pas besoin
## d'un equivalent de hide_tree_visuals(), rien n'est jamais retire piece
## par piece.
##
## Ce fichier cumule volontairement generation initiale / cycle des saisons
## / niveau de vue / suppression au minage dans un seul endroit plutot que
## d'etre decoupe : ces quatre responsabilites partagent le meme etat
## par-instance (_pending_xforms/_pending_colors/_pending_ground_y/
## _removed_instances/_pending_printemps_seulement/_pending_masque_en_ete)
## et se combinent dans une seule fonction critique (_refresh_all_visibility)
## qui doit connaitre simultanement retrait/niveau de vue/saison pour
## decider de la visibilite d'une instance. Un decoupage en plusieurs
## fichiers obligerait a faire circuler ces dictionnaires entre scripts,
## pour un gain de lisibilite marginal face au risque de regression dans
## une logique de visibilite deja delicate (meme motif saison+niveau de vue
## combines que Forest.gd/BerryBushes.gd, eux aussi non decoupes pour cette
## raison).

const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")
## Pour lire VoxelWorldScript.world_gen_start_ms (mesure de duree de
## generation) - ce script est le dernier "lourd" a finir son _ready() (voir
## ordre des noeuds dans Main.tscn : VoxelWorld -> Forest -> SeasonSystem ->
## BerryBushes -> GroundDecoration), donc le bon endroit pour afficher la
## duree totale.
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")
## Pour afficher aussi le temps ecoule depuis le tout debut de la scene
## (voir DayNightCycle.scene_start_ms), pas seulement depuis le debut de
## VoxelWorld - utile pour situer la generation du monde dans le temps de
## chargement total (voir aussi CharacterSheetUI.gd, qui affiche le temps
## total a la toute fin du chargement).
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")

## Lit directement VoxelWorld.WIDTH/DEPTH au lieu d'un nombre duplique en dur.
const grid_width := VoxelWorldScript.WIDTH
const grid_depth := VoxelWorldScript.DEPTH
@export var climate_id: String = "tempere"
@export var decoration_chance: float = 0.24

@onready var voxel_world: Node3D = %VoxelWorld

## Un type par "piece" de decoration, chacun associe a un MultiMeshInstance3D
## partage (voir _mmi) et un maillage de base "unite" (voir _build_shared_meshes).
enum PartType { GRASS_BLADE, FLOWER_STEM, FLOWER_BLOOM, PEBBLE }

## Cacher une instance de MultiMesh avec une echelle Vector3.ZERO pile
## (Basis totalement degenere) peut corrompre le rendu de tout le MultiMesh
## sous un materiau a eclairage reel - une echelle non nulle mais infime
## evite ce risque (voir les deux fonctions plus bas qui construisent
## zero_xform).
const HIDDEN_INSTANCE_SCALE := 0.0001

var _mmi: Dictionary = {}              # PartType -> MultiMeshInstance3D
var _pending_xforms: Dictionary = {}   # PartType -> Array[Transform3D]
var _pending_colors: Dictionary = {}   # PartType -> Array[Color]
## Contrairement aux arbres/buissons, une decoration n'a PAS de noeud
## persistant (root.queue_free() dans _harvest_and_clear, aucun groupe) : le
## bloc de sol de chaque instance est donc retenu ici, en parallele de
## _pending_xforms/_pending_colors (meme index), pour permettre
## update_view_level plus bas.
var _pending_ground_y: Dictionary = {}  # PartType -> Array[float]
var _view_level: int = 999999  # tres haut par defaut = rien de cache avant le premier appel de CameraRig
## Meme index que les tableaux ci-dessus. Une fois une instance marquee
## retiree ici, update_view_level ne doit plus jamais la reafficher (voir
## plus bas).
var _removed_instances: Dictionary = {}  # PartType -> Array[bool]

# Comme toute la decoration est generee UNE fois au demarrage (jamais de
# vraie regeneration dynamique), l'effet saisonnier est obtenu en taguant
# CHAQUE decoration (au moment de sa creation, une fois pour toutes ses
# pieces - voir _harvest_and_clear) avec deux booleens independants plutot
# qu'en creant/detruisant des instances a chaque changement de saison :
# - "printemps_seulement" (fleurs uniquement, ~40% des fleurs generees) :
#   cachees sauf au printemps -> plus de fleurs visibles au printemps que
#   les autres saisons (fleurs de base toujours visibles + bonus printemps).
# - "masque_en_ete" (les 4 types de decoration, ~30% independamment) :
#   cachees uniquement en ete -> une partie des decorations disparait en ete.
# Ni l'automne ni l'hiver n'ont d'effet sur la decoration : densite pleine,
# comme le reste de l'annee.
const ETE_MASQUE_FRACTION := 0.30
const PRINTEMPS_FLEUR_BONUS_FRACTION := 0.4
var _pending_printemps_seulement: Dictionary = {}  # PartType -> Array[bool]
var _pending_masque_en_ete: Dictionary = {}        # PartType -> Array[bool]
var _season_id: String = "ete"

## Le decoupage par paquets (await, voir _ready) casse la garantie implicite
## de Godot comme quoi le _ready() d'un noeud precedent dans la scene finit
## toujours avant celui du noeud suivant. SeasonSystem.gd doit donc attendre
## explicitement ce signal avant son premier appel a apply_season(). Mis a
## true aussi sur le retour anticipe ci-dessous (%VoxelWorld introuvable)
## pour ne jamais laisser SeasonSystem.gd attendre indefiniment un signal
## qui ne serait jamais emis.
signal generation_finished
var generation_done: bool = false

## Nombre de decorations construites avant de rendre la main au moteur
## (await process_frame). Chaque await coute au moins une frame complete
## (16-30ms) - yield tous les BATCH_SIZE decorations REELLEMENT posees
## (comme Forest.gd/BerryBushes.gd), pas une fois par ligne de la grille
## scannee : yielder par ligne fait autant d'attentes que la largeur de la
## carte, meme si la plupart des lignes n'ont pose aucune decoration
## (decoration_chance << 1), ce qui degrade fortement le temps de
## chargement sans reduire le risque de gel (le scan d'une ligne est deja
## tres rapide, ce n'est jamais lui qui bloquait visiblement le rendu).
const BATCH_SIZE := 300


func _ready() -> void:
	# Garde de coherence avec Forest.gd/BerryBushes.gd, qui se protegent
	# deja contre un %VoxelWorld introuvable - evite un crash null-reference
	# si ce noeud unique venait a manquer dans la scene.
	if voxel_world == null:
		generation_done = true
		generation_finished.emit()
		return
	# Le generateur aleatoire global est deja correctement initialise a ce
	# point (VoxelWorld._ready(), declare avant ce script dans Main.tscn, a
	# deja fixe sa graine) - pas de randomize() ici, ce qui rend la position
	# des decorations de sol reproductible par graine.
	if OS.is_debug_build():
		print("[Perf] GroundDecoration (decos sol) : debut a %.1f s depuis le debut de la scene" % ((Time.get_ticks_msec() - DayNightCycleScript.scene_start_ms) / 1000.0))
	_build_shared_meshes()
	var climate: Dictionary = ClimateDefs.get_climate(climate_id)
	# Cette double boucle scanne grid_width x grid_depth cases dans un seul
	# appel synchrone de _ready() - le scan lui-meme (RNG + lecture de
	# tableau par case) est tres rapide, donc on ne rend la main au moteur
	# que tous les BATCH_SIZE decorations REELLEMENT posees (voir sa doc),
	# pas a chaque ligne scannee.
	var spawned := 0
	for x in range(grid_width):
		for z in range(grid_depth):
			if randf() > decoration_chance:
				continue
			if not voxel_world.is_dirt_top(x, z):
				continue
			var top_y: int = voxel_world.get_top_block_y(x, z)
			_spawn_decoration(x, top_y + 1, z, climate)
			spawned += 1
			if spawned % BATCH_SIZE == 0:
				await get_tree().process_frame
	_apply_pending_instances()

	# Duree totale de generation du monde (depuis le tout debut de
	# VoxelWorld._ready() jusqu'a la fin de ce script, le dernier "lourd" a
	# s'executer). Note : Forest.gd/BerryBushes.gd generent aussi par
	# paquets (await process_frame) en parallele de ce script - ce chrono
	# mesure donc la fin du scan de CE script, pas forcement le moment exact
	# ou Forest/BerryBushes ont eux aussi fini.
	if OS.is_debug_build():
		var elapsed_ms: int = Time.get_ticks_msec() - VoxelWorldScript.world_gen_start_ms
		print("[Perf] GroundDecoration (decos sol) : fin, monde (%dx%dx%d) genere en %.1f s (depuis le debut de VoxelWorld)" % [grid_width, grid_depth, VoxelWorldScript.HEIGHT, elapsed_ms / 1000.0])
		# Deuxieme mesure, depuis le tout debut de la scene (voir
		# DayNightCycle.scene_start_ms) - permet de voir combien de temps
		# s'est deja ecoule quand la generation du monde se termine, par
		# rapport au temps total affiche par CharacterSheetUI.gd a la toute
		# fin.
		var elapsed_since_scene_start_ms: int = Time.get_ticks_msec() - DayNightCycleScript.scene_start_ms
		print("[Perf] GroundDecoration (decos sol) : %.1f s depuis le debut de la scene" % (elapsed_since_scene_start_ms / 1000.0))
	generation_done = true
	generation_finished.emit()


## Cree les 4 MultiMeshInstance3D partages (un par PartType), avec leur
## maillage "unite" et un seul materiau a couleur-par-instance (meme
## principe que Forest.gd/VoxelWorld.gd). cull_mode desactive pour tous
## (necessaire pour les brins d'herbe fins ; le desactiver aussi pour les
## formes pleines - tige/bouton/caillou - ne change rien a leur rendu, vu de
## l'exterieur d'une forme convexe pleine).
func _build_shared_meshes() -> void:
	_mmi[PartType.GRASS_BLADE] = _make_mmi(_make_cylinder_mesh(0.01, 0.03, 1.0))
	_mmi[PartType.FLOWER_STEM] = _make_mmi(_make_cylinder_mesh(0.012, 0.016, 1.0))
	_mmi[PartType.FLOWER_BLOOM] = _make_mmi(_make_sphere_mesh(1.0))
	_mmi[PartType.PEBBLE] = _make_mmi(_make_box_mesh(Vector3.ONE))
	for key in _mmi.keys():
		_pending_xforms[key] = []
		_pending_colors[key] = []
		_pending_ground_y[key] = []
		_removed_instances[key] = []
		_pending_printemps_seulement[key] = []
		_pending_masque_en_ete[key] = []


func _make_mmi(mesh: Mesh) -> MultiMeshInstance3D:
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
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = mat
	add_child(mmi)
	return mmi


## radial_segments par defaut de Godot (64) concu pour un objet unique bien
## visible - beaucoup trop detaille pour ces toutes petites decorations
## (herbe/fleurs/cailloux) instanciees par milliers via MultiMesh sur toute
## la carte. Meme principe que TREE_SPHERE_RADIAL_SEGMENTS dans Forest.gd/
## BERRY_SPHERE_RADIAL_SEGMENTS dans BerryBushes.gd.
const DECORATION_RADIAL_SEGMENTS := 6
const DECORATION_RINGS := 4


func _make_cylinder_mesh(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = DECORATION_RADIAL_SEGMENTS
	return mesh


func _make_sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = DECORATION_RADIAL_SEGMENTS
	mesh.rings = DECORATION_RINGS
	return mesh


func _make_box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## Choisit un type de decoration au hasard (davantage d'herbe que de fleurs,
## et un peu de cailloux) et le fait apparaitre a la position donnee
func _spawn_decoration(x: int, y: int, z: int, climate: Dictionary) -> void:
	var roll := randf()
	if roll < 0.45:
		_spawn_grass_tuft(x, y, z, climate)
	elif roll < 0.85:
		_spawn_flower(x, y, z, climate)
	else:
		_spawn_pebble(x, y, z)


## Petite touffe de 3 a 5 brins d'herbe fins, teintee avec une variation
## aleatoire de la couleur de base du climat
func _spawn_grass_tuft(x: int, y: int, z: int, climate: Dictionary) -> void:
	var tuft := Node3D.new()
	tuft.position = Vector3(x + randf_range(0.2, 0.8), y, z + randf_range(0.2, 0.8))
	tuft.rotation.y = randf_range(0.0, TAU)
	add_child(tuft)

	var variations: Array = climate.get("herbe_variations", [climate.get("herbe_base", Color.GREEN)])
	var blade_count: int = randi_range(3, 5)
	for i in range(blade_count):
		var blade := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.01
		mesh.bottom_radius = 0.03
		mesh.height = randf_range(0.12, 0.22)
		mesh.radial_segments = DECORATION_RADIAL_SEGMENTS
		blade.mesh = mesh
		blade.position = Vector3(randf_range(-0.08, 0.08), mesh.height * 0.5, randf_range(-0.08, 0.08))
		blade.rotation.z = randf_range(-0.3, 0.3)
		var color: Color = variations[randi_range(0, variations.size() - 1)]
		_tag_part(blade, PartType.GRASS_BLADE, color, Vector3(1.0, mesh.height, 1.0))
		tuft.add_child(blade)

	# Tire UNE fois par touffe (pas par brin) pour que toute la touffe
	# apparaisse/disparaisse ensemble en ete.
	_harvest_and_clear(tuft, float(y) - 1.0, false, randf() < ETE_MASQUE_FRACTION)


## Petite fleur (tige + bouton), couleur choisie au hasard parmi les
## "especes" du climat (une couleur = une espece, approche volontairement
## simple pour l'instant)
func _spawn_flower(x: int, y: int, z: int, climate: Dictionary) -> void:
	var flower := Node3D.new()
	flower.position = Vector3(x + randf_range(0.25, 0.75), y, z + randf_range(0.25, 0.75))
	add_child(flower)

	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.012
	stem_mesh.bottom_radius = 0.016
	stem_mesh.height = 0.18
	stem_mesh.radial_segments = DECORATION_RADIAL_SEGMENTS
	stem.mesh = stem_mesh
	stem.position.y = 0.09
	var stem_color := Color(0.3, 0.5, 0.2)
	_tag_part(stem, PartType.FLOWER_STEM, stem_color, Vector3(1.0, stem_mesh.height, 1.0))
	flower.add_child(stem)

	var bloom := MeshInstance3D.new()
	var bloom_mesh := SphereMesh.new()
	bloom_mesh.radius = 0.05
	bloom_mesh.height = 0.1
	bloom_mesh.radial_segments = DECORATION_RADIAL_SEGMENTS
	bloom_mesh.rings = DECORATION_RINGS
	bloom.mesh = bloom_mesh
	bloom.position.y = 0.2
	var fleurs: Array = climate.get("fleurs", [Color.WHITE])
	var bloom_color: Color = fleurs[randi_range(0, fleurs.size() - 1)]
	_tag_part(bloom, PartType.FLOWER_BLOOM, bloom_color, Vector3.ONE * bloom_mesh.radius)
	flower.add_child(bloom)

	# ~40% des fleurs generees (tige+bouton ensemble) sont cachees sauf au
	# printemps - voir la doc de PRINTEMPS_FLEUR_BONUS_FRACTION plus haut.
	# Egalement soumises a "masque_en_ete" comme toute decoration.
	var printemps_seulement: bool = randf() < PRINTEMPS_FLEUR_BONUS_FRACTION
	_harvest_and_clear(flower, float(y) - 1.0, printemps_seulement, randf() < ETE_MASQUE_FRACTION)


## Petit caillou gris, taille/teinte/rotation legerement aleatoires
func _spawn_pebble(x: int, y: int, z: int) -> void:
	var pebble := Node3D.new()
	pebble.position = Vector3(x, y, z)
	add_child(pebble)

	var mesh_part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var size: float = randf_range(0.06, 0.14)
	mesh.size = Vector3(size, size * 0.6, size * randf_range(0.8, 1.2))
	mesh_part.mesh = mesh
	mesh_part.position = Vector3(randf_range(0.2, 0.8), size * 0.3, randf_range(0.2, 0.8))
	mesh_part.rotation.y = randf_range(0.0, TAU)
	var shade: float = randf_range(0.45, 0.62)
	var color := Color(shade, shade, shade * 1.02)
	_tag_part(mesh_part, PartType.PEBBLE, color, mesh.size)
	pebble.add_child(mesh_part)

	_harvest_and_clear(pebble, float(y) - 1.0, false, randf() < ETE_MASQUE_FRACTION)


## Marque une MeshInstance3D temporaire comme "piece a recolter" (voir
## _harvest_and_clear).
func _tag_part(node: MeshInstance3D, part_type: int, color: Color, part_scale: Vector3) -> void:
	node.set_meta("part_type", part_type)
	node.set_meta("part_color", color)
	node.set_meta("part_scale", part_scale)


## Recolte le global_transform + couleur + taille de toutes les pieces
## taguees sous "root", les enregistre en attente dans le
## MultiMeshInstance3D partage correspondant, puis supprime "root" entier
## (pas besoin de garder de noeud racine ici, contrairement aux arbres - une
## decoration n'a ni groupe ni metadonnee ni logique de suppression future).
func _harvest_and_clear(root: Node3D, ground_block_y: float, printemps_seulement: bool = false, masque_en_ete: bool = false) -> void:
	var parts: Array = []
	_collect_tagged_parts(root, parts)
	for node in parts:
		var part_type: int = node.get_meta("part_type")
		var color: Color = node.get_meta("part_color")
		var part_scale: Vector3 = node.get_meta("part_scale")
		var xform: Transform3D = node.global_transform * Transform3D(Basis().scaled(part_scale), Vector3.ZERO)
		_pending_xforms[part_type].append(xform)
		_pending_colors[part_type].append(color)
		# Necessaire ici puisque "root" est libere juste apres (aucun noeud
		# ne survit pour retenir cette information autrement) - voir
		# declaration de "_pending_ground_y" plus haut.
		_pending_ground_y[part_type].append(ground_block_y)
		_removed_instances[part_type].append(false)
		# Memes valeurs pour TOUTES les pieces d'une meme decoration (tirees
		# UNE fois par decoration cote appelant, jamais par piece
		# individuelle).
		_pending_printemps_seulement[part_type].append(printemps_seulement)
		_pending_masque_en_ete[part_type].append(masque_en_ete)
	root.queue_free()


## Remplit "out" avec tous les descendants de "node" tagues via _tag_part.
func _collect_tagged_parts(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child.has_meta("part_type"):
			out.append(child)
		_collect_tagged_parts(child, out)


## Applique une seule fois, apres avoir genere TOUTE la decoration, les
## instances en attente a chaque MultiMeshInstance3D partage.
func _apply_pending_instances() -> void:
	for part_type in _mmi.keys():
		var mmi: MultiMeshInstance3D = _mmi[part_type]
		var xforms: Array = _pending_xforms[part_type]
		var colors: Array = _pending_colors[part_type]
		mmi.multimesh.instance_count = xforms.size()
		for i in range(xforms.size()):
			mmi.multimesh.set_instance_transform(i, xforms[i])
			mmi.multimesh.set_instance_color(i, colors[i])


## Appele par CameraRig a chaque changement de niveau de vue, comme pour
## Forest.gd/BerryBushes.gd. Contrairement a ces 2 scripts, il n'y a ici
## aucun noeud par decoration a interroger (voir _harvest_and_clear, "root"
## est libere immediatement) : chaque instance de chaque MultiMesh partage
## est donc cachee/reaffichee directement, en comparant son bloc de sol
## (_pending_ground_y[part_type][i], retenu a la creation) au niveau de vue
## - meme convention que VoxelWorld ("y > view_level" = cache).
## _pending_xforms reste en memoire (jamais vide) apres
## _apply_pending_instances, donc la transform d'origine est toujours
## disponible pour la restauration.
func update_view_level(level: int) -> void:
	_view_level = level
	_refresh_all_visibility()


## Appele par SeasonSystem.gd a chaque changement de saison - meme
## mecanisme que update_view_level, factorise dans _refresh_all_visibility
## pour combiner les TROIS raisons independantes de cacher une instance
## (retiree par minage / au-dessus du niveau de vue / masquee par la
## saison) sans qu'elles se marchent dessus.
func apply_season(season_id: String) -> void:
	_season_id = season_id
	_refresh_all_visibility()


## Combine les 3 conditions de visibilite (voir update_view_level/
## apply_season ci-dessus) et met a jour les transforms de TOUTES les
## instances - appele par les deux, jamais directement.
func _refresh_all_visibility() -> void:
	var zero_xform := Transform3D(Basis().scaled(Vector3.ONE * HIDDEN_INSTANCE_SCALE), Vector3.ZERO)
	for part_type in _mmi.keys():
		var mmi: MultiMeshInstance3D = _mmi[part_type]
		var xforms: Array = _pending_xforms[part_type]
		var ground_ys: Array = _pending_ground_y[part_type]
		var removed: Array = _removed_instances[part_type]
		var printemps_seulement: Array = _pending_printemps_seulement[part_type]
		var masque_en_ete: Array = _pending_masque_en_ete[part_type]
		for i in range(xforms.size()):
			# Une instance retiree (voir remove_decoration_at) reste cachee
			# quel que soit le niveau de vue - ne jamais la restaurer.
			var hidden: bool = removed[i] or ground_ys[i] > float(_view_level)
			if not hidden and printemps_seulement[i] and _season_id != "printemps":
				hidden = true
			if not hidden and masque_en_ete[i] and _season_id == "ete":
				hidden = true
			if hidden:
				mmi.multimesh.set_instance_transform(i, zero_xform)
			else:
				mmi.multimesh.set_instance_transform(i, xforms[i])


## Appelee par Dwarf.gd/_complete_task ("miner") juste apres
## VoxelWorld.remove_block. Contrairement aux arbres/buissons, une
## decoration n'a pas de noeud propre a liberer : on retrouve la/les
## instance(s) concernee(s) par leur position au sol (floor(origin.x/z),
## meme convention que le placement en grille, voir
## _spawn_grass_tuft/_spawn_flower/_spawn_pebble) et on les met a l'echelle
## zero de façon PERMANENTE (voir _removed_instances/update_view_level).
func remove_decoration_at(bx: int, bz: int) -> void:
	var zero_xform := Transform3D(Basis().scaled(Vector3.ONE * HIDDEN_INSTANCE_SCALE), Vector3.ZERO)
	for part_type in _mmi.keys():
		var mmi: MultiMeshInstance3D = _mmi[part_type]
		var xforms: Array = _pending_xforms[part_type]
		var removed: Array = _removed_instances[part_type]
		for i in range(xforms.size()):
			if removed[i]:
				continue
			var origin: Vector3 = xforms[i].origin
			if int(floor(origin.x)) == bx and int(floor(origin.z)) == bz:
				mmi.multimesh.set_instance_transform(i, zero_xform)
				removed[i] = true
