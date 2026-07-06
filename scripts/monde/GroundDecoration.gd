extends Node3D
## Sprint 19 : decoration legere du sol (touffes d'herbe, fleurs, petits
## cailloux) pour casser la monotonie visuelle du damier de terre. Purement
## decoratif (aucune interaction, contrairement aux buissons a baies) :
## generee une seule fois au demarrage, a partir de l'etat initial du terrain
## (une decoration ne disparait pas si le bloc en-dessous est mine ensuite -
## limitation connue, acceptable pour l'instant vu la faible densite).
##
## La couleur de base de l'herbe/des fleurs depend du climat de la carte
## (ClimateDefinitions.gd). Un seul climat existe reellement pour l'instant
## (tempere), mais la structure est prete a en accueillir d'autres plus tard
## (climate_id est deja un champ expose, pret a devenir un vrai choix de
## carte quand un systeme de climats/saisons existera).
##
## Sprint 34 (2026-07-03, perf map resize) : meme probleme et meme remede que
## Forest.gd (voir ses commentaires pour le detail de la technique) - chaque
## decoration etait un Node3D + 1-5 MeshInstance3D/materiaux individuels ;
## a 100x100 avec decoration_chance=0.24 ca representait environ 2400
## decorations x ~3 noeuds = ~7200 noeuds. Comme ces decorations n'ont AUCUNE
## interaction (jamais cliquees, jamais retirees individuellement - voir
## docstring ci-dessus), c'est le cas le plus simple : construction temporaire
## inchangee (_spawn_grass_tuft/_spawn_flower/_spawn_pebble), recolte du
## global_transform + couleur + taille dans _harvest_and_clear, instances
## dans des MultiMeshInstance3D partages (voir PartType), et PAS besoin d'un
## equivalent de hide_tree_visuals() puisque rien n'est jamais retire.
##
## 2026-07-06 (revue de code, paquet E, I39 - "428 lignes cumulant 4
## responsabilites") : evalue et volontairement NON decoupe en plusieurs
## fichiers. Generation initiale / cycle des saisons / niveau de vue /
## suppression au minage partagent tous le meme etat par-instance
## (_pending_xforms/_pending_colors/_pending_ground_y/_removed_instances/
## _pending_printemps_seulement/_pending_masque_en_ete) et se combinent dans
## UNE SEULE fonction critique (_refresh_all_visibility) qui doit connaitre
## simultanement retrait/niveau de vue/saison pour decider de la visibilite
## d'une instance. Un decoupage en plusieurs fichiers obligerait a faire
## circuler ces 7 dictionnaires entre scripts, pour un gain de lisibilite
## marginal et un risque reel de regression dans une logique de visibilite
## deja fragile par le passe (meme famille de bugs que Forest.gd/
## BerryBushes.gd, qui ont le meme motif saison+niveau de vue combines et ne
## sont eux non plus jamais decoupes pour cette raison).

const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")
## Sprint 34bis : uniquement pour lire VoxelWorldScript.world_gen_start_ms
## (mesure de duree de generation, voir ce champ dans VoxelWorld.gd) - ce
## script est le dernier "lourd" a finir son _ready() (voir ordre des noeuds
## dans Main.tscn : VoxelWorld -> Forest -> SeasonSystem -> BerryBushes ->
## GroundDecoration), donc le bon endroit pour afficher la duree totale.
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")
## Sprint 34ter : pour afficher aussi le temps ecoule depuis le tout debut de
## la scene (voir DayNightCycle.scene_start_ms), pas seulement depuis le
## debut de VoxelWorld - utile pour situer la generation du monde dans le
## temps de chargement total (voir aussi CharacterSheetUI.gd, qui affiche le
## temps total a la toute fin du chargement).
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")

@export var grid_width: int = 100  # 2026-07-03 : map resize (etait 20)
@export var grid_depth: int = 100  # 2026-07-03 : map resize (etait 20)
@export var climate_id: String = "tempere"
@export var decoration_chance: float = 0.24  # Sprint 24 : densite doublee (etait 0.12, jugee trop faible)

@onready var voxel_world: Node3D = %VoxelWorld

## Un type par "piece" de decoration, chacun associe a un MultiMeshInstance3D
## partage (voir _mmi) et un maillage de base "unite" (voir _build_shared_meshes).
enum PartType { GRASS_BLADE, FLOWER_STEM, FLOWER_BLOOM, PEBBLE }

## 2026-07-06 (meme correctif que Forest.gd, voir ses commentaires pour le
## detail complet) : cacher une instance de MultiMesh avec une echelle
## Vector3.ZERO PILE (Basis totalement degenere) peut corrompre le rendu de
## TOUT le MultiMesh concerne avec un materiau a eclairage reel - jamais
## reproduit ici, mais meme code a risque (voir les deux fonctions plus bas
## qui construisent zero_xform) - corrige preventivement.
const HIDDEN_INSTANCE_SCALE := 0.0001

var _mmi: Dictionary = {}              # PartType -> MultiMeshInstance3D
var _pending_xforms: Dictionary = {}   # PartType -> Array[Transform3D]
var _pending_colors: Dictionary = {}   # PartType -> Array[Color]
## Sprint 87 (2026-07-04, demande explicite de Francois : "les decorations
## (fleurs etc) doivent disparaitre aussi" en descendant de niveau, comme les
## arbres/buissons - voir Forest.gd/update_view_level) - contrairement aux
## arbres/buissons, une decoration n'a PAS de noeud persistant (root.queue_free()
## dans _harvest_and_clear, aucun groupe) : le bloc de sol de chaque instance
## est donc retenu ici, en parallele de _pending_xforms/_pending_colors (meme
## index), pour permettre update_view_level plus bas.
var _pending_ground_y: Dictionary = {}  # PartType -> Array[float]
var _view_level: int = 999999  # tres haut par defaut = rien de cache avant le premier appel de CameraRig
## 2026-07-05 (correctif bug signale par Francois : "quand on mine un bloc qui
## a de la decoration, celle-ci ne disparait pas") - meme index que les
## tableaux ci-dessus. Une fois une instance marquee retiree ici,
## update_view_level ne doit plus jamais la reafficher (voir plus bas).
var _removed_instances: Dictionary = {}  # PartType -> Array[bool]

# 2026-07-05 (cycle des saisons, demande explicite de Francois - printemps :
# "plus de fleurs de decorations" ; ete : "disparition de 30% des
# decorations") : comme toute la decoration est generee UNE fois au demarrage
# (voir docstring en tete de fichier - jamais de vraie regeneration dynamique),
# ces deux effets sont obtenus en taguant CHAQUE decoration (au moment de sa
# creation, une fois pour toutes ses pieces - voir _harvest_and_clear) avec
# deux booleens independants plutot qu'en creant/detruisant des instances a
# chaque changement de saison :
# - "printemps_seulement" (fleurs uniquement, ~40% des fleurs generees) :
#   cachees sauf au printemps -> "plus de fleurs" au printemps par rapport aux
#   autres saisons (fleurs de base toujours visibles + bonus printemps).
# - "masque_en_ete" (les 4 types de decoration, ~30% independamment) : cachees
#   uniquement en ete -> "disparition de 30% des decorations" en ete.
# Ni l'automne ni l'hiver ne sont mentionnes pour la decoration : aucun des
# deux booleens n'y a d'effet (densite pleine, comme avant ce cycle).
const ETE_MASQUE_FRACTION := 0.30
const PRINTEMPS_FLEUR_BONUS_FRACTION := 0.4
var _pending_printemps_seulement: Dictionary = {}  # PartType -> Array[bool]
var _pending_masque_en_ete: Dictionary = {}        # PartType -> Array[bool]
var _season_id: String = "ete"


func _ready() -> void:
	# 2026-07-05 (revue de code, item F026) : garde de coherence avec
	# Forest.gd/BerryBushes.gd, qui se protegent deja contre un %VoxelWorld
	# introuvable - evite un crash null-reference si ce noeud unique venait a
	# manquer dans la scene.
	if voxel_world == null:
		return
	# 2026-07-05 (revue de code, item F010) : grid_width/grid_depth dupliques
	# en dur (aucune garde-fou automatique auparavant) - avertissement si
	# desynchronise de VoxelWorld.gd, sans changer le comportement.
	if grid_width != VoxelWorldScript.WIDTH or grid_depth != VoxelWorldScript.DEPTH:
		push_warning("GroundDecoration.grid_width/grid_depth (%d/%d) desynchronise de VoxelWorld.WIDTH/DEPTH (%d/%d)" % [grid_width, grid_depth, VoxelWorldScript.WIDTH, VoxelWorldScript.DEPTH])
	# 2026-07-05 (correctif revue de code C5, meme cause que C2-C4/C6/I9) :
	# randomize() retire - reinitialisait le generateur aleatoire global de
	# facon non deterministe, APRES que VoxelWorld._ready() ait deja fixe sa
	# graine (seed(active_seed)). GroundDecoration.gd est declare apres
	# VoxelWorld dans Main.tscn : le generateur global est deja correctement
	# initialise ici - rend desormais la position des decorations de sol
	# reproductible par graine.
	_build_shared_meshes()
	var climate: Dictionary = ClimateDefs.get_climate(climate_id)
	for x in range(grid_width):
		for z in range(grid_depth):
			if randf() > decoration_chance:
				continue
			if not voxel_world.is_dirt_top(x, z):
				continue
			var top_y: int = voxel_world.get_top_block_y(x, z)
			_spawn_decoration(x, top_y + 1, z, climate)
	_apply_pending_instances()

	# Sprint 34bis : affiche dans la console Godot la duree totale de
	# generation du monde (depuis le tout debut de VoxelWorld._ready() jusqu'a
	# la fin de ce script, le dernier "lourd" a s'executer) - pour mesurer
	# precisement le temps de lancement signale par Francois comme long.
	var elapsed_ms: int = Time.get_ticks_msec() - VoxelWorldScript.world_gen_start_ms
	print("[Perf] Generation du monde (100x100x50) terminee en %.1f s" % (elapsed_ms / 1000.0))
	# Sprint 34ter : deuxieme mesure, depuis le tout debut de la scene (voir
	# DayNightCycle.scene_start_ms) - permet de voir combien de temps s'est
	# deja ecoule quand la generation du monde se termine, par rapport au
	# temps total affiche par CharacterSheetUI.gd a la toute fin.
	var elapsed_since_scene_start_ms: int = Time.get_ticks_msec() - DayNightCycleScript.scene_start_ms
	print("[Perf] Temps ecoule depuis le debut de la scene : %.1f s" % (elapsed_since_scene_start_ms / 1000.0))


## Sprint 34 : cree les 4 MultiMeshInstance3D partages (un par PartType), avec
## leur maillage "unite" et un seul materiau a couleur-par-instance (meme
## principe que Forest.gd/VoxelWorld.gd - use_colors=true +
## vertex_color_use_as_albedo=true). cull_mode desactive pour tous (l'original
## ne le faisait que pour les brins d'herbe fins, mais le desactiver aussi
## pour les formes pleines - tige/bouton/caillou - ne change rien a leur
## rendu, vu de l'exterieur d'une forme convexe pleine).
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


func _make_cylinder_mesh(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	return mesh


func _make_sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
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
		blade.mesh = mesh
		blade.position = Vector3(randf_range(-0.08, 0.08), mesh.height * 0.5, randf_range(-0.08, 0.08))
		blade.rotation.z = randf_range(-0.3, 0.3)
		var color: Color = variations[randi_range(0, variations.size() - 1)]
		_tag_part(blade, PartType.GRASS_BLADE, color, Vector3(1.0, mesh.height, 1.0))
		tuft.add_child(blade)

	# 2026-07-05 (cycle des saisons, ete : "disparition de 30% des
	# decorations") : tire UNE fois par touffe (pas par brin) pour que toute
	# la touffe apparaisse/disparaisse ensemble.
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
	stem.mesh = stem_mesh
	stem.position.y = 0.09
	var stem_color := Color(0.3, 0.5, 0.2)
	_tag_part(stem, PartType.FLOWER_STEM, stem_color, Vector3(1.0, stem_mesh.height, 1.0))
	flower.add_child(stem)

	var bloom := MeshInstance3D.new()
	var bloom_mesh := SphereMesh.new()
	bloom_mesh.radius = 0.05
	bloom_mesh.height = 0.1
	bloom.mesh = bloom_mesh
	bloom.position.y = 0.2
	var fleurs: Array = climate.get("fleurs", [Color.WHITE])
	var bloom_color: Color = fleurs[randi_range(0, fleurs.size() - 1)]
	_tag_part(bloom, PartType.FLOWER_BLOOM, bloom_color, Vector3.ONE * bloom_mesh.radius)
	flower.add_child(bloom)

	# 2026-07-05 (cycle des saisons, printemps : "plus de fleurs de
	# decorations") : ~40% des fleurs generees (tige+bouton ensemble) sont
	# cachees sauf au printemps - voir la doc de PRINTEMPS_FLEUR_BONUS_FRACTION
	# plus haut. Egalement soumises a "masque_en_ete" comme toute decoration.
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


## Sprint 34 : marque une MeshInstance3D temporaire comme "piece a recolter"
## (voir _harvest_and_clear) - meme principe que Forest.gd/_tag_part.
func _tag_part(node: MeshInstance3D, part_type: int, color: Color, part_scale: Vector3) -> void:
	node.set_meta("part_type", part_type)
	node.set_meta("part_color", color)
	node.set_meta("part_scale", part_scale)


## Sprint 34 : recolte le global_transform + couleur + taille de toutes les
## pieces taguees sous "root" (voir Forest.gd/_harvest_and_clear pour le
## detail de la technique - identique ici), les enregistre en attente dans le
## MultiMeshInstance3D partage correspondant, puis supprime "root" entier (pas
## besoin de garder de noeud racine ici, contrairement aux arbres - une
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
		# Sprint 87 : voir declaration de "_pending_ground_y" plus haut -
		# necessaire ici puisque "root" est libere juste apres (aucun noeud
		# ne survit pour retenir cette information autrement).
		_pending_ground_y[part_type].append(ground_block_y)
		_removed_instances[part_type].append(false)
		# 2026-07-05 (cycle des saisons) : voir declaration plus haut - memes
		# valeurs pour TOUTES les pieces d'une meme decoration (tirees UNE
		# fois par decoration cote appelant, jamais par piece individuelle).
		_pending_printemps_seulement[part_type].append(printemps_seulement)
		_pending_masque_en_ete[part_type].append(masque_en_ete)
	root.queue_free()


## Remplit "out" avec tous les descendants de "node" tagues via _tag_part.
func _collect_tagged_parts(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child.has_meta("part_type"):
			out.append(child)
		_collect_tagged_parts(child, out)


## Sprint 34 : applique une seule fois, apres avoir genere TOUTE la
## decoration, les instances en attente a chaque MultiMeshInstance3D partage.
func _apply_pending_instances() -> void:
	for part_type in _mmi.keys():
		var mmi: MultiMeshInstance3D = _mmi[part_type]
		var xforms: Array = _pending_xforms[part_type]
		var colors: Array = _pending_colors[part_type]
		mmi.multimesh.instance_count = xforms.size()
		for i in range(xforms.size()):
			mmi.multimesh.set_instance_transform(i, xforms[i])
			mmi.multimesh.set_instance_color(i, colors[i])


## Sprint 87 (2026-07-04, demande explicite de Francois : "les decorations
## (fleurs etc) doivent disparaitre aussi" en descendant de niveau) - appele
## par CameraRig a chaque changement de niveau de vue, comme pour Forest.gd/
## BerryBushes.gd. Contrairement a ces 2 scripts, il n'y a ici aucun noeud
## par decoration a interroger (voir _harvest_and_clear, "root" est libere
## immediatement) : chaque instance de chaque MultiMesh partage est donc
## cachee/reaffichee directement, en comparant son bloc de sol
## (_pending_ground_y[part_type][i], retenu a la creation) au niveau de vue -
## meme convention que VoxelWorld ("y > view_level" = cache). _pending_xforms
## reste en memoire (jamais vide) apres _apply_pending_instances, donc la
## transform d'origine est toujours disponible pour la restauration.
func update_view_level(level: int) -> void:
	_view_level = level
	_refresh_all_visibility()


## 2026-07-05 (cycle des saisons) : appele par SeasonSystem.gd a chaque
## changement de saison - meme mecanisme que update_view_level (voir plus
## haut), factorise dans _refresh_all_visibility pour combiner les TROIS
## raisons independantes de cacher une instance (retiree par minage / au-dessus
## du niveau de vue / masquee par la saison) sans qu'elles se marchent dessus.
func apply_season(season_id: String) -> void:
	_season_id = season_id
	_refresh_all_visibility()


## Combine les 3 conditions de visibilite (voir update_view_level/apply_season
## ci-dessus) et met a jour les transforms de TOUTES les instances - appele
## par les deux, jamais directement.
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
			# 2026-07-05 (correctif "decoration ne disparait pas au minage") :
			# une instance retiree (voir remove_decoration_at) reste cachee
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


## 2026-07-05 (correctif bug signale par Francois : "quand on mine un bloc qui
## a de la decoration, celle-ci ne disparait pas") - appelee par Dwarf.gd/
## _complete_task ("miner") juste apres VoxelWorld.remove_block. Contrairement
## aux arbres/buissons, une decoration n'a pas de noeud propre a liberer :
## on retrouve la/les instance(s) concernee(s) par leur position au sol
## (floor(origin.x/z), meme convention que le placement en grille, voir
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
