extends Node3D
## Sprint 4 : quelques arbres de test places au hasard sur la carte,
## pour valider l'action "couper".
## Sprint 20 : remplace l'arbre unique (tronc + 1 sphere) par une
## construction plus realiste (racines evasees, tronc effile, branches,
## feuillage en grappes) qui varie selon l'espece (TreeSpecies.gd : chene,
## sapin, bouleau), chacune avec ses propres couleurs de tronc/branches/
## racines/feuilles et sa silhouette generale (touffue/conique/fine).
## Chaque arbre garde en metadonnee le type de bois qu'il donne a la coupe
## (voir Dwarf.gd/_complete_task), pour que le bois recolte corresponde a
## l'espece de l'arbre abattu.
## Sprint 24bis : branches plus grandes/nombreuses + vraies "feuilles" (petites
## plaques, voir _build_leaf_cluster) aux extremites des branches et sur le
## feuillage touffu/fin (pas sur le feuillage conique du sapin, qui represente
## deja des aiguilles).
## Sprint 24ter : arbres fruitiers (TreeSpecies.FRUIT_SPECIES) places a part
## des arbres de foret (voir _ready/fruit_tree_count) - meme construction que
## les autres arbres, plus des fruits (_build_fruits) recoltables via l'action
## "Cueillir" (voir ActionController.gd/TaskQueue.gd/Dwarf.gd). Rejoignent le
## groupe "cueillette" (comme les buissons a baies, voir BerryBush.gd) en plus
## du groupe "trees" (toujours coupables pour le bois).
## Sprint 27 : arbres juges trop petits - branches plus longues, feuillage
## (touffu/fin/conique) plus grand et etale plus haut au-dessus du tronc, pour
## une silhouette globale plus haute SANS toucher au tronc (`_build_trunk`
## inchangee pour "touffu"/"fin" : le tronc garde exactement la meme taille
## qu'avant, seule la couronne de branches/feuilles grandit et s'eleve). Le
## sapin (conique) est le seul a avoir sa hauteur totale legerement remontee
## dans TreeSpecies.gd, son tronc visuel restant tres court par construction
## (voir _build_trunk, formule inchangee).
##
## Sprint 34 (2026-07-03, perf map resize) : la construction "un Node3D +
## MeshInstance3D + materiau par brindille/feuille/branche/blob" tenait a
## peine sur la petite carte 20x20 (12+6 arbres = ~1850 noeuds), mais devenait
## ingerable a 100x100 avec la meme densite conservee (300+150 arbres =
## environ 45 000 noeuds/materiaux individuels rien que pour les arbres) - gros
## ralentissement (FPS bas, signale par Francois). Refonte : chaque arbre est
## TOUJOURS construit exactement comme avant (memes fonctions _build_roots/
## _build_trunk/_build_branches/_build_foliage*/_build_leaf_cluster, memes
## positions/rotations/tailles aleatoires, RIEN ne change dans la geometrie ni
## les probabilites) mais chaque piece cree est maintenant une simple
## MeshInstance3D TEMPORAIRE, taguee (voir _tag_part) avec son "type de piece"
## et sa "taille" - une fois l'arbre entierement construit, _harvest_and_clear
## parcourt ces pieces, recolte leur global_transform (calcule par GODOT
## lui-meme via la hierarchie de noeuds - aucun calcul de position/rotation
## refait a la main ici, donc fidele a 100% au rendu d'origine, zero risque
## d'erreur de transform) + couleur + taille, les enregistre comme instance
## dans un des 6 MultiMeshInstance3D partages par TOUTE la foret (un par type
## de piece : racines/tronc/branches/cones/boules de feuillage/petites
## feuilles - voir PartType), PUIS supprime les noeuds temporaires. Un arbre
## ne garde donc plus que son Node3D racine (position/rotation/groupe/
## metadonnees, utilise par ActionController.gd pour le clic Miner/Couper/
## Cueillir - qui ne fait QUE de la distance depuis tree.global_position,
## jamais de collision sur un mesh, donc aucun impact sur cette logique) et
## ses fruits (encore des noeuds individuels, recoltables un par un, tres peu
## nombreux). Resultat : ~1-6 noeuds par arbre au lieu de ~100.
##
## Astuce cle pour la "taille" : un MultiMesh partage plusieurs instances qui
## utilisent TOUTES le meme maillage de base (un cylindre/une sphere/une boite
## "unite", rayon/taille=1) - la taille REELLE de chaque piece (ex : rayon
## d'une boule de feuillage entre 0.38 et 0.55) est appliquee comme un
## FACTEUR D'ECHELLE LOCAL supplementaire (part_scale), compose AVANT le
## global_transform recolte (qui, lui, ne contient que position/rotation/
## echelle de l'ARBRE, jamais la taille propre du maillage d'origine).
##
## Coupe d'un arbre (Dwarf.gd, action "couper") : comme toute la geometrie
## vit desormais dans des MultiMesh PARTAGES entre tous les arbres, on ne peut
## plus se contenter de tree.queue_free() pour la faire disparaitre - voir
## hide_tree_visuals(), a appeler AVANT de liberer le noeud arbre.

const TreeSpecies := preload("res://scripts/data/materiaux/types/bois/TreeSpecies.gd")
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")

## Sprint 37bis (2026-07-03, correction bug signale par Francois : "il faut
## empecher les arbres et buissons dans l'eau") - reference a VoxelWorld pour
## rejeter les positions d'eau (voir _pick_dry_position) a la generation
## initiale ET a la repousse (item 16, _spawn_new_tree_and_apply reutilise
## _spawn_tree donc profite automatiquement de cette correction).
@onready var voxel_world: Node3D = %VoxelWorld

@export var grid_width: int = 100  # 2026-07-03 : map resize (etait 20)
@export var grid_depth: int = 100  # 2026-07-03 : map resize (etait 20)
@export var ground_level: float = 50.0  # sommet de la carte (HEIGHT, 2026-07-03 : map resize, etait 30)
@export var size_multiplier: float = 1.3  # 2026-07-02 : arbres agrandis de 30% (jauges nains/arbres/buissons rejustees)

# 2026-07-03 (map resize) : remplace les anciens tree_count/fruit_tree_count
# fixes (12 et 6, sur la carte 20x20=400 cases d'origine) par une VRAIE
# densite (nombre par 1000 cases), pour que le nombre d'arbres suive
# automatiquement la taille de la carte au lieu d'etre recalcule a la main a
# chaque redimensionnement futur. Valeurs choisies pour garder exactement la
# meme densite qu'avant : 12/400*1000 = 30, 6/400*1000 = 15.
@export var tree_density_per_1000_tiles: float = 30.0
@export var fruit_tree_density_per_1000_tiles: float = 15.0  # Sprint 24ter : 2 de chaque espece environ, densite equivalente

## Sprint 34 : un type par "piece" d'arbre, chacun associe a un
## MultiMeshInstance3D partage (voir _mmi) et un maillage de base "unite"
## (voir _build_shared_meshes).
enum PartType { ROOTS, TRUNK, BRANCH, CONE, BLOB, LEAF }

## Types de piece consideres comme "feuillage" - seuls ceux-la sont reteints
## a chaque changement de saison (voir apply_season_tint), exactement comme
## avant (le tronc/les racines/les branches/les fruits ne changent jamais de
## couleur avec la saison).
const _FOLIAGE_PART_TYPES := [PartType.CONE, PartType.BLOB, PartType.LEAF]

var _mmi: Dictionary = {}              # PartType -> MultiMeshInstance3D
var _pending_xforms: Dictionary = {}   # PartType -> Array[Transform3D]
var _pending_colors: Dictionary = {}   # PartType -> Array[Color]
# Sprint 33 (adapte Sprint 34) : couleur de BASE (avant teinte de saison) de
# chaque instance de feuillage, index-alignee avec le multimesh final -
# permet a apply_season_tint() de reteindre a partir de la couleur d'origine
# a chaque fois (jamais de la couleur deja teintee), donc aucune derive
# possible en changeant de saison plusieurs fois.
var _foliage_base_colors: Dictionary = {}  # PartType -> Array[Color]

# Teinte multiplicative appliquee par-dessus la couleur de base du feuillage,
# par saison. "ete" = neutre (couleurs d'origine, aucun changement). Valeurs
# choisies pour rester lisibles avec le rendu plat/mat du jeu (pas de vraie
# simulation de chute de feuilles, juste un changement de teinte).
const SEASON_FOLIAGE_TINT := {
	"ete": Color(1.0, 1.0, 1.0),
	"automne": Color(1.35, 0.85, 0.45),
	"hiver": Color(0.5, 0.5, 0.55),
	"printemps": Color(0.9, 1.15, 0.85),
}


func _ready() -> void:
	randomize()
	_build_shared_meshes()
	var tile_count: float = float(grid_width * grid_depth)
	var tree_count: int = int(round(tree_density_per_1000_tiles * tile_count / 1000.0))
	var fruit_tree_count: int = int(round(fruit_tree_density_per_1000_tiles * tile_count / 1000.0))
	for i in range(tree_count):
		_spawn_tree(TreeSpecies.random_species())
	for i in range(fruit_tree_count):
		_spawn_tree(TreeSpecies.random_fruit_species())
	_apply_pending_instances()


## Sprint 37 (backlog Phase 1 item 16, "repousse des arbres") : les arbres
## coupes (Dwarf.gd, action "couper") liberent leur noeud et quittent donc le
## groupe "trees" - on verifie periodiquement si la population est repassee
## sous la densite cible et on fait repousser UN arbre a la fois (evite un pic
## de perf si beaucoup ont ete coupes d'un coup). Pas de vraie simulation de
## croissance (pas d'arbre "jeune" qui grandit visuellement) : l'arbre apparait
## directement a sa taille adulte, comme a la generation initiale de la carte.
@export var regrow_check_interval_seconds: float = 20.0
var _regrow_timer: float = 0.0

func _process(delta: float) -> void:
	_regrow_timer += delta * DayNightCycleScript.game_speed
	if _regrow_timer < regrow_check_interval_seconds:
		return
	_regrow_timer = 0.0
	_maybe_regrow_tree()


func _maybe_regrow_tree() -> void:
	var tile_count: float = float(grid_width * grid_depth)
	var target_forest_count: int = int(round(tree_density_per_1000_tiles * tile_count / 1000.0))
	var target_fruit_count: int = int(round(fruit_tree_density_per_1000_tiles * tile_count / 1000.0))
	var current_forest_count := 0
	var current_fruit_count := 0
	for tree in get_tree().get_nodes_in_group("trees"):
		if String(tree.get_meta("fruit_resource", "")) != "":
			current_fruit_count += 1
		else:
			current_forest_count += 1

	if current_forest_count < target_forest_count:
		_spawn_new_tree_and_apply(TreeSpecies.random_species())
	elif current_fruit_count < target_fruit_count:
		_spawn_new_tree_and_apply(TreeSpecies.random_fruit_species())


## Fait pousser un seul arbre APRES la generation initiale, sans reappliquer
## _apply_pending_instances() sur la totalite des tableaux _pending_* : un
## arbre coupe a deja mis a zero sa transform directement dans le
## MultiMeshInstance3D (voir hide_tree_visuals), sans jamais toucher aux
## tableaux _pending_* - rejouer tout _apply_pending_instances() ecraserait
## donc ce zero et ferait "reapparaitre" l'arbre coupe. On ne pousse ici QUE
## les nouvelles instances de ce nouvel arbre (a partir de leur index de
## depart) dans les MultiMesh partages, en grandissant instance_count au
## besoin, sans jamais reecrire les instances existantes.
func _spawn_new_tree_and_apply(species: Dictionary) -> void:
	var start_indices: Dictionary = {}
	for part_type in _mmi.keys():
		start_indices[part_type] = _pending_xforms[part_type].size()

	_spawn_tree(species)

	for part_type in _mmi.keys():
		var mmi: MultiMeshInstance3D = _mmi[part_type]
		var xforms: Array = _pending_xforms[part_type]
		var colors: Array = _pending_colors[part_type]
		var new_count: int = xforms.size()
		if mmi.multimesh.instance_count < new_count:
			mmi.multimesh.instance_count = new_count
		for i in range(start_indices[part_type], new_count):
			mmi.multimesh.set_instance_transform(i, xforms[i])
			mmi.multimesh.set_instance_color(i, colors[i])


## Sprint 34 : cree les 6 MultiMeshInstance3D partages (un par PartType), avec
## leur maillage "unite" (rayon/taille=1, voir chaque _make_*_mesh) et un seul
## materiau a couleur-par-instance (meme principe que les pepites de filons
## de VoxelWorld.gd - use_colors=true + vertex_color_use_as_albedo=true).
func _build_shared_meshes() -> void:
	_mmi[PartType.ROOTS] = _make_mmi(_make_cylinder_mesh(0.16, 0.30, 1.0))
	_mmi[PartType.TRUNK] = _make_mmi(_make_cylinder_mesh(0.09, 0.16, 1.0))
	_mmi[PartType.BRANCH] = _make_mmi(_make_cylinder_mesh(0.03, 0.06, 1.0))
	_mmi[PartType.CONE] = _make_mmi(_make_cylinder_mesh(0.0, 1.0, 1.0))
	_mmi[PartType.BLOB] = _make_mmi(_make_sphere_mesh(1.0))
	_mmi[PartType.LEAF] = _make_mmi(_make_box_mesh(Vector3.ONE))
	for key in _mmi.keys():
		_pending_xforms[key] = []
		_pending_colors[key] = []
	for key in _FOLIAGE_PART_TYPES:
		_foliage_base_colors[key] = []


func _make_mmi(mesh: Mesh) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = MultiMesh.new()
	mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	mmi.multimesh.use_colors = true
	mmi.multimesh.mesh = mesh
	# Meme materiau "plat" que _flat_material ci-dessous, mais a couleur par
	# instance (vertex_color_use_as_albedo) au lieu d'une couleur fixe.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	mat.metallic = 0.0
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


## Sprint 37bis : tire une position au hasard en rejetant l'eau (voir
## VoxelWorld.is_water) - essais bornes par securite, repli sur la derniere
## position tiree si vraiment aucune case seche n'est trouvee (tres
## improbable, l'eau ne couvre qu'une petite partie de la carte).
func _pick_dry_position() -> Vector2:
	var x := randf_range(2.0, float(grid_width - 2))
	var z := randf_range(2.0, float(grid_depth - 2))
	var guard := 0
	while voxel_world != null and voxel_world.is_water(int(x), int(z)) and guard < 20:
		x = randf_range(2.0, float(grid_width - 2))
		z = randf_range(2.0, float(grid_depth - 2))
		guard += 1
	return Vector2(x, z)


## Sprint 38 (reliefs) : hauteur du sol (sommet de colonne + 1) a une position
## XZ donnee - meme principe que Dwarf.gd/_ground_y_at. Repli sur ground_level
## si voxel_world est introuvable ou hors carte.
func _ground_y_at(x: float, z: float) -> float:
	if voxel_world == null:
		return ground_level
	var top: int = voxel_world.get_top_block_y(int(floor(x)), int(floor(z)))
	if top < 0:
		return ground_level
	return float(top) + 1.0


func _spawn_tree(species: Dictionary) -> void:
	var pos := _pick_dry_position()
	var x := pos.x
	var z := pos.y

	# Petites variations aleatoires par instance (echelle + teinte), pour que
	# deux arbres de la meme espece ne soient jamais des clones parfaits.
	# size_multiplier applique en plus une taille de base plus grande a TOUS
	# les arbres (2026-07-02, demande explicite : arbres agrandis de 30%).
	var scale_jitter: float = randf_range(0.85, 1.15) * size_multiplier
	var tint_jitter: float = randf_range(0.9, 1.1)

	var tree := Node3D.new()
	tree.name = "Tree_%d" % get_child_count()
	# Sprint 38 (reliefs) : hauteur reelle de la colonne (sommet+1), plus
	# ground_level fixe - sinon un arbre plante sur une colline apparaissait
	# enfonce dans le sol (meme correction que Dwarf.gd/_ground_y_at).
	tree.position = Vector3(x, _ground_y_at(x, z), z)
	tree.rotation.y = randf_range(0.0, TAU)
	tree.scale = Vector3.ONE * scale_jitter
	tree.add_to_group("trees")
	tree.set_meta("wood_resource", species["wood_resource"])
	tree.set_meta("species_name", species["nom"])
	add_child(tree)

	var trunk_height: float = species["hauteur"]

	_build_roots(tree, species, tint_jitter)
	var trunk_visual_height: float = _build_trunk(tree, species, trunk_height, tint_jitter)
	_build_branches(tree, species, trunk_height, tint_jitter)
	_build_foliage(tree, species, trunk_height, trunk_visual_height, tint_jitter)

	# Sprint 24ter : arbre fruitier - ajoute les fruits + rend l'arbre
	# recoltable via l'action "Cueillir" (groupe/metadonnees partages avec
	# BerryBush.gd, voir Dwarf.gd/_complete_task pour la logique commune).
	# Les fruits restent des noeuds individuels (voir _build_fruits) - pas
	# touches par la conversion MultiMesh, recoltes un par un a la cueillette.
	if species.has("fruit_resource"):
		var fruit_count: int = species.get("fruit_count", 5)
		tree.add_to_group("cueillette")
		tree.set_meta("fruit_resource", species["fruit_resource"])
		tree.set_meta("fruits_left", fruit_count)
		_build_fruits(tree, species, trunk_height, fruit_count)

	# Sprint 34 : toute la geometrie decorative (racines/tronc/branches/
	# feuillage) vient d'etre construite comme des noeuds TEMPORAIRES sous
	# "tree" (fonctions ci-dessous inchangees) - on recolte maintenant leur
	# global_transform + couleur + taille pour les enregistrer dans les
	# MultiMeshInstance3D partages, puis on les supprime (voir
	# _harvest_and_clear). Seuls les fruits restent de vrais enfants de "tree".
	_harvest_and_clear(tree)


## Petite base evasee au pied du tronc (racines), pour eviter l'effet
## "poteau plante dans le sol" d'un simple cylindre droit
func _build_roots(tree: Node3D, species: Dictionary, tint: float) -> void:
	var roots := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.16
	mesh.bottom_radius = 0.30
	mesh.height = 0.22
	roots.mesh = mesh
	roots.position.y = 0.11
	var color: Color = species["racine_color"] * tint
	roots.set_surface_override_material(0, _flat_material(color))
	_tag_part(roots, PartType.ROOTS, color, Vector3(1.0, mesh.height, 1.0))
	tree.add_child(roots)


## Tronc effile (plus fin en haut qu'en bas), hauteur dependante de l'espece.
## Sprint 24quinquies : pour le sapin (feuillage conique), un vrai sapin n'a
## qu'un petit tronc visible avant que les branches/aiguilles ne commencent -
## le tronc visuel est donc beaucoup plus court que "trunk_height" (hauteur
## totale de l'arbre), le reste etant recouvert par le feuillage (voir
## _build_foliage_conique, qui recoit la hauteur reelle du tronc en retour).
## Renvoie la hauteur visuelle du tronc (= trunk_height pour les autres formes).
func _build_trunk(tree: Node3D, species: Dictionary, trunk_height: float, tint: float) -> float:
	var visual_height: float = trunk_height
	if species.get("forme", "touffu") == "conique":
		visual_height = max(trunk_height * 0.25, 0.18)

	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.09
	mesh.bottom_radius = 0.16
	mesh.height = visual_height
	trunk.mesh = mesh
	trunk.position.y = 0.22 + visual_height * 0.5
	var color: Color = species["tronc_color"] * tint
	trunk.set_surface_override_material(0, _flat_material(color))
	_tag_part(trunk, PartType.TRUNK, color, Vector3(1.0, visual_height, 1.0))
	tree.add_child(trunk)
	return visual_height


## Sprint 24bis : 3 a 5 branches (etait 2 a 4), plus longues/epaisses qu'avant
## pour etre bien visibles, partant du haut du tronc et reparties tout autour
## (angle Y aleatoire) pour un aspect moins symetrique/artificiel. Chacune
## porte une petite grappe de "feuilles" a son extremite (voir _build_leaf_cluster).
## Sprint 24quinquies : plus de branches du tout pour le sapin (feuillage
## conique) - le gros cone de feuillage represente deja toute la silhouette,
## des batons de branche qui depassent par-dessus n'ont pas de sens sur un
## vrai sapin (signale par l'utilisateur : "les branches depassent").
## Sprint 27 : branches plus longues (0.35-0.55 -> 0.5-0.8) et un peu plus
## nombreuses (3-5 -> 4-6), demarrant parfois legerement au-dessus du sommet
## du tronc (au lieu de toujours en-dessous) pour que la couronne s'eleve
## plus haut sans agrandir le tronc lui-meme. Grappes de feuilles aux
## extremites agrandies (4-6 -> 6-9 feuilles, spread 0.09 -> 0.12).
func _build_branches(tree: Node3D, species: Dictionary, trunk_height: float, tint: float) -> void:
	if species.get("forme", "touffu") == "conique":
		return
	var branch_count: int = randi_range(4, 6)
	var trunk_top_y: float = 0.22 + trunk_height
	var colors: Array = species["feuillage_colors"]
	for i in range(branch_count):
		var pivot := Node3D.new()
		pivot.position = Vector3(0, trunk_top_y + randf_range(-0.25, 0.15), 0)
		pivot.rotation.y = (TAU / float(branch_count)) * i + randf_range(-0.3, 0.3)
		tree.add_child(pivot)

		var branch := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.03
		mesh.bottom_radius = 0.06
		var branch_length: float = randf_range(0.5, 0.8)
		mesh.height = branch_length
		branch.mesh = mesh
		branch.position = Vector3(0, branch_length * 0.5, 0.12)
		branch.rotation.x = deg_to_rad(65)  # incline vers l'exterieur/le haut
		var branch_color: Color = species["branche_color"] * tint
		branch.set_surface_override_material(0, _flat_material(branch_color))
		_tag_part(branch, PartType.BRANCH, branch_color, Vector3(1.0, branch_length, 1.0))
		pivot.add_child(branch)

		# Ancre a l'extremite haute du cylindre (en espace local de la
		# branche) : herite automatiquement de toutes les rotations parent
		# (pivot + branche), pas besoin de recalculer la position monde a la main.
		var tip := Node3D.new()
		tip.position = Vector3(0, mesh.height * 0.5, 0)
		branch.add_child(tip)
		_build_leaf_cluster(tip, colors, tint, randi_range(6, 9), 0.12)


## Aiguille le bon type de feuillage selon la "forme" de l'espece
func _build_foliage(tree: Node3D, species: Dictionary, trunk_height: float, trunk_visual_height: float, tint: float) -> void:
	var top_y: float = 0.22 + trunk_height
	match species.get("forme", "touffu"):
		"conique":
			# Sprint 24quinquies : le feuillage part du sommet du (court) tronc
			# visuel, pas du sommet de la hauteur totale de l'arbre - il occupe
			# donc presque toute la silhouette, comme un vrai sapin.
			_build_foliage_conique(tree, species, 0.22 + trunk_visual_height, top_y, tint)
		"fin":
			_build_foliage_fin(tree, species, top_y, tint)
		_:
			_build_foliage_touffu(tree, species, top_y, tint)


## Feuillage touffu (chene, arbres fruitiers) : plusieurs spheres qui se
## chevauchent, placees de façon legerement asymetrique pour eviter la "boule
## parfaite". Sprint 24bis : chaque blob recoit en plus une petite grappe de
## "feuilles" (voir _build_leaf_cluster) a sa surface, pour un aspect moins
## "boule lisse" et plus feuillu de pres.
## Sprint 27 : blobs plus gros (0.32-0.46 -> 0.38-0.55) et un peu plus
## nombreux (3-4 -> 4-6), etales plus haut au-dessus du sommet du tronc
## (0.05-0.35 -> 0.05-0.65) pour une couronne plus haute et plus fournie,
## sans changer "top_y" (donc sans changer le tronc). Grappes de feuilles
## agrandies (5-8 -> 7-10).
func _build_foliage_touffu(tree: Node3D, species: Dictionary, top_y: float, tint: float) -> void:
	var colors: Array = species["feuillage_colors"]
	var cluster_count: int = randi_range(4, 6)
	for i in range(cluster_count):
		var blob := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = randf_range(0.38, 0.55)
		mesh.height = mesh.radius * 2.0
		blob.mesh = mesh
		blob.position = Vector3(
			randf_range(-0.26, 0.26),
			top_y + randf_range(0.05, 0.65),
			randf_range(-0.26, 0.26)
		)
		var blob_color: Color = colors[randi_range(0, colors.size() - 1)] * tint
		blob.set_surface_override_material(0, _flat_material(blob_color))
		_tag_part(blob, PartType.BLOB, blob_color, Vector3.ONE * mesh.radius)
		tree.add_child(blob)
		_build_leaf_cluster(blob, colors, tint, randi_range(7, 10), mesh.radius * 0.8)


## Feuillage conique (sapin) : Sprint 24quinquies - 4-5 cones empiles qui
## couvrent depuis le sommet du (court) tronc visuel jusqu'en haut de
## l'arbre (start_y -> top_y), plus large a la base et etroit en pointe,
## comme un vrai sapin (le tronc ne depasse presque pas du feuillage).
## Sprint 27 : un niveau de plus en moyenne (4-5 -> 5-6) et cones un peu plus
## larges a la base (0.42 -> 0.48) pour une silhouette plus fournie - la
## hauteur totale suit "top_y" (span), qui augmente via TreeSpecies.hauteur
## du sapin, le tronc visuel restant inchange (voir _build_trunk).
func _build_foliage_conique(tree: Node3D, species: Dictionary, start_y: float, top_y: float, tint: float) -> void:
	var colors: Array = species["feuillage_colors"]
	var levels: int = randi_range(5, 6)
	var span: float = max(top_y - start_y, 0.3)
	var level_height: float = span / float(levels) * 1.4  # chevauchement pour eviter les trous
	var y := start_y
	for i in range(levels):
		var t: float = float(i) / float(max(levels - 1, 1))  # 0 en bas, 1 en haut
		var cone := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = lerp(0.48, 0.10, t)
		mesh.height = level_height
		cone.mesh = mesh
		cone.position.y = y + mesh.height * 0.5
		var cone_color: Color = colors[i % colors.size()] * tint
		cone.set_surface_override_material(0, _flat_material(cone_color))
		# Maillage "unite" du cone : top_radius=0, bottom_radius=1, height=1
		# (voir _build_shared_meshes) - le rayon reel varie par niveau
		# (mesh.bottom_radius), donc l'echelle XZ suit ce rayon directement.
		_tag_part(cone, PartType.CONE, cone_color, Vector3(mesh.bottom_radius, mesh.height, mesh.bottom_radius))
		tree.add_child(cone)
		y += span / float(levels)


## Feuillage fin/eparse (bouleau) : quelques petites touffes legeres, moins
## denses que le chene, coherent avec un arbre plus elance. Sprint 24bis :
## meme ajout de grappes de "feuilles" que le feuillage touffu.
## Sprint 27 : blobs plus gros (0.20-0.28 -> 0.26-0.38) et un peu plus
## nombreux (2-3 -> 3-5), etales plus haut au-dessus du tronc (0.0-0.28 ->
## 0.0-0.55), grappes de feuilles agrandies (4-6 -> 6-8)
func _build_foliage_fin(tree: Node3D, species: Dictionary, top_y: float, tint: float) -> void:
	var colors: Array = species["feuillage_colors"]
	var cluster_count: int = randi_range(3, 5)
	for i in range(cluster_count):
		var blob := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = randf_range(0.26, 0.38)
		mesh.height = mesh.radius * 2.0
		blob.mesh = mesh
		blob.position = Vector3(
			randf_range(-0.22, 0.22),
			top_y + randf_range(0.0, 0.55),
			randf_range(-0.22, 0.22)
		)
		var blob_color: Color = colors[randi_range(0, colors.size() - 1)] * tint
		blob.set_surface_override_material(0, _flat_material(blob_color))
		_tag_part(blob, PartType.BLOB, blob_color, Vector3.ONE * mesh.radius)
		tree.add_child(blob)
		_build_leaf_cluster(blob, colors, tint, randi_range(6, 8), mesh.radius * 0.8)


## Sprint 24ter : fruits de l'arbre (arbres fruitiers uniquement, voir
## _spawn_tree) - petites spheres colorees dispersees pres du feuillage,
## nommees "Fruit_%d" (0..fruit_count-1) pour pouvoir en retirer une a la
## fois a la cueillette (voir Dwarf.gd/_complete_task, meme convention que
## BerryBush.gd/Berry_%d). Sprint 34 : PAS convertis en MultiMesh (contrairement
## a tout le reste de l'arbre) - ils doivent pouvoir disparaitre un par un a
## la cueillette, ce qu'un MultiMesh partage ne permet pas facilement ; leur
## nombre reste de toute facon tres faible (5-6 par arbre fruitier).
## Sprint 27 : plage verticale elargie (0.05-0.35 -> 0.05-0.65) pour rester
## coherente avec le feuillage touffu des arbres fruitiers, desormais etale
## plus haut (voir _build_foliage_touffu) - les fruits restent repartis dans
## le feuillage au lieu de sembler flotter en-dessous.
func _build_fruits(tree: Node3D, species: Dictionary, trunk_height: float, fruit_count: int) -> void:
	var top_y: float = 0.22 + trunk_height
	var mat := _flat_material(species["fruit_color"])
	for i in range(fruit_count):
		var fruit := MeshInstance3D.new()
		fruit.name = "Fruit_%d" % i
		var mesh := SphereMesh.new()
		mesh.radius = 0.06
		mesh.height = 0.12
		fruit.mesh = mesh
		fruit.position = Vector3(
			randf_range(-0.26, 0.26),
			top_y + randf_range(0.05, 0.65),
			randf_range(-0.26, 0.26)
		)
		fruit.set_surface_override_material(0, mat)
		tree.add_child(fruit)


## Sprint 24bis : petite grappe de "feuilles" (plaques plates tres fines,
## sans image/texture) autour d'un point donne - utilise aux extremites des
## branches et sur le feuillage touffu/fin, pour un aspect plus detaille que
## de simples boules de couleur.
func _build_leaf_cluster(parent: Node3D, colors: Array, tint: float, count: int, spread: float) -> void:
	for i in range(count):
		var leaf := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(randf_range(0.05, 0.08), 0.01, randf_range(0.03, 0.05))
		leaf.mesh = mesh
		leaf.position = Vector3(
			randf_range(-spread, spread),
			randf_range(-spread, spread),
			randf_range(-spread, spread)
		)
		leaf.rotation = Vector3(randf_range(-0.5, 0.5), randf_range(0.0, TAU), randf_range(-0.5, 0.5))
		var leaf_color: Color = colors[randi_range(0, colors.size() - 1)] * tint
		leaf.set_surface_override_material(0, _flat_material(leaf_color))
		_tag_part(leaf, PartType.LEAF, leaf_color, mesh.size)
		parent.add_child(leaf)


## Sprint 34 : marque une MeshInstance3D temporaire comme "piece a recolter"
## (voir _harvest_and_clear) - part_type route vers le bon MultiMeshInstance3D
## partage, part_color est la couleur finale de cette piece (deja multipliee
## par la teinte de l'arbre), part_scale est le facteur d'echelle a appliquer
## au maillage "unite" du MultiMesh pour retrouver la taille reelle voulue
## (rayon/hauteur/dimensions d'origine de cette piece precise).
func _tag_part(node: MeshInstance3D, part_type: int, color: Color, scale: Vector3) -> void:
	node.set_meta("part_type", part_type)
	node.set_meta("part_color", color)
	node.set_meta("part_scale", scale)


## Sprint 34 : parcourt tous les descendants de "tree" tagues via _tag_part
## (racines/tronc/branches/feuillage - jamais les fruits, qui n'ont pas cette
## meta), recolte leur global_transform (calcule par Godot via la hierarchie
## de noeuds temporaire ci-dessus - aucun calcul de position/rotation refait a
## la main) combine a part_scale (le global_transform seul ne capture pas la
## taille propre du maillage d'origine, seulement position/rotation/echelle
## des noeuds), et enregistre une instance en attente dans le
## MultiMeshInstance3D partage correspondant (voir _apply_pending_instances,
## appele une seule fois a la fin de _ready). Retient aussi, par arbre, la
## liste des (type, index) d'instances lui appartenant (voir hide_tree_visuals)
## puis supprime tous les enfants non-fruits de "tree" (les conteneurs
## temporaires - pivots, extremites de branche - n'ont plus d'utilite une fois
## leurs descendants recoltes, et sont liberes en cascade avec leur parent).
func _harvest_and_clear(tree: Node3D) -> void:
	var parts: Array = []
	_collect_tagged_parts(tree, parts)

	var refs: Array = []
	for node in parts:
		var part_type: int = node.get_meta("part_type")
		var color: Color = node.get_meta("part_color")
		var part_scale: Vector3 = node.get_meta("part_scale")
		var xform: Transform3D = node.global_transform * Transform3D(Basis().scaled(part_scale), Vector3.ZERO)

		_pending_xforms[part_type].append(xform)
		_pending_colors[part_type].append(color)
		if part_type in _FOLIAGE_PART_TYPES:
			_foliage_base_colors[part_type].append(color)
		refs.append([part_type, _pending_xforms[part_type].size() - 1])

	tree.set_meta("visual_refs", refs)

	for child in tree.get_children():
		if not (child.name as String).begins_with("Fruit_"):
			child.queue_free()


## Remplit "out" avec tous les descendants de "node" tagues via _tag_part
## (has_meta("part_type")), quelle que soit leur profondeur - les conteneurs
## intermediaires (pivots de branche, extremites) n'ont pas cette meta et
## sont simplement traverses sans etre ajoutes.
func _collect_tagged_parts(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child.has_meta("part_type"):
			out.append(child)
		_collect_tagged_parts(child, out)


## Sprint 34 : applique une seule fois, apres avoir genere TOUS les arbres,
## les instances en attente (voir _harvest_and_clear) a chaque
## MultiMeshInstance3D partage - evite de redimensionner les tableaux du
## MultiMesh arbre par arbre.
func _apply_pending_instances() -> void:
	for part_type in _mmi.keys():
		var mmi: MultiMeshInstance3D = _mmi[part_type]
		var xforms: Array = _pending_xforms[part_type]
		var colors: Array = _pending_colors[part_type]
		mmi.multimesh.instance_count = xforms.size()
		for i in range(xforms.size()):
			mmi.multimesh.set_instance_transform(i, xforms[i])
			mmi.multimesh.set_instance_color(i, colors[i])


## Materiau plat (visuellement "flat" = pas de texture/reflet), coherent
## avec le style du reste du jeu (terrain, decorations de sol : voir
## VoxelWorld._make_material). 2026-07-02 : passe de SHADING_MODE_UNSHADED a
## l'eclairage reel pour que les arbres reagissent au cycle jour/nuit
## (DayNightCycle.gd) - meme raison que VoxelWorld._make_material.
## roughness=1/metallic=0 garde l'aspect plat/mat, sans reflet.
## Sprint 34 : ce materiau reste utilise le temps de la construction
## temporaire de chaque piece (voir _build_* ci-dessus), mais ne survit plus -
## la piece est recoltee puis liberee (_harvest_and_clear) avant le premier
## rendu ; la couleur reelle affichee au final vient de la couleur par
## instance du MultiMesh partage (voir _tag_part/part_color).
func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## Reteinte tout le feuillage (CONE/BLOB/LEAF) selon la saison donnee - appele
## par SeasonSystem.gd a chaque changement de saison. Chaque instance repart
## de sa couleur de base d'origine (_foliage_base_colors, jamais de la
## couleur deja teintee), donc aucune derive/accumulation possible en
## changeant de saison plusieurs fois. Sprint 34 : remplace l'ancien mecanisme
## par materiau (un StandardMaterial3D par piece) par une mise a jour directe
## de la couleur par instance des MultiMeshInstance3D partages - plus rapide
## (pas de creation de materiau) et coherent avec le reste de la refonte.
func apply_season_tint(season_id: String) -> void:
	var tint: Color = SEASON_FOLIAGE_TINT.get(season_id, Color(1.0, 1.0, 1.0))
	for part_type in _FOLIAGE_PART_TYPES:
		var mmi: MultiMeshInstance3D = _mmi[part_type]
		var base_colors: Array = _foliage_base_colors[part_type]
		for i in range(base_colors.size()):
			mmi.multimesh.set_instance_color(i, base_colors[i] * tint)


## Sprint 34 : rend invisibles toutes les instances de mesh partagees
## appartenant a "tree" (racines/tronc/branches/feuillage), SANS toucher aux
## instances des AUTRES arbres (chaque instance est mise a l'echelle zero
## individuellement via son propre index, pas de reconstruction du tableau
## complet). A appeler AVANT tree.queue_free() quand un arbre est coupe (voir
## Dwarf.gd/_process_work, action "couper") - sinon le tronc/les branches/le
## feuillage de l'arbre coupe resteraient visibles pour toujours (ils ne sont
## plus des enfants du noeud "tree" depuis la refonte Sprint 34, donc
## tree.queue_free() seul ne les affecte plus du tout).
func hide_tree_visuals(tree: Node3D) -> void:
	if not tree.has_meta("visual_refs"):
		return
	var refs: Array = tree.get_meta("visual_refs")
	var zero_xform := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for ref in refs:
		var part_type: int = ref[0]
		var idx: int = ref[1]
		_mmi[part_type].multimesh.set_instance_transform(idx, zero_xform)


## Sprint 85 (2026-07-04, demande explicite de Francois : "quand je descends
## d'un niveau, les arbres et buissons du niveau superieur restent affiches -
## il faut les faire disparaitre completement") - appele par CameraRig a
## chaque changement de niveau de vue (meme moment que
## VoxelWorld.set_view_level), en plus de ce dernier, jamais a sa place.
## Un arbre est cache des que le BLOC de sol sur lequel il repose (indice
## entier, tree.position.y - 1.0, meme convention que tree.position.y =
## get_top_block_y+1.0 dans _ground_y_at) est strictement au-dessus du niveau
## de vue - exactement la meme regle que VoxelWorld ("pos.y > view_level" =
## cache). Pour reafficher un arbre, on restaure sa transform d'ORIGINE (pas
## de recalcul) depuis _pending_xforms : ce tableau, remplit une seule fois
## par _harvest_and_clear/_apply_pending_instances, reste en memoire pour
## toute la duree de vie de Forest.gd (jamais vide), donc aucun stockage
## supplementaire n'est necessaire. Un arbre coupe (hide_tree_visuals suivi
## de tree.queue_free(), voir Dwarf.gd) est libere immediatement et ne fait
## donc plus partie du groupe "trees" - pas de risque de le "reafficher" par
## erreur ici.
## Les fruits (seuls enfants restants de "tree", noms "Fruit_*", pas geres par
## le MultiMesh partage) sont bascules directement via leur propre "visible".
func update_view_level(level: int) -> void:
	var zero_xform := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for tree in get_tree().get_nodes_in_group("trees"):
		var ground_block_y: float = tree.position.y - 1.0
		var hidden: bool = ground_block_y > float(level)
		if tree.has_meta("visual_refs"):
			var refs: Array = tree.get_meta("visual_refs")
			for ref in refs:
				var part_type: int = ref[0]
				var idx: int = ref[1]
				if hidden:
					_mmi[part_type].multimesh.set_instance_transform(idx, zero_xform)
				else:
					_mmi[part_type].multimesh.set_instance_transform(idx, _pending_xforms[part_type][idx])
		for child in tree.get_children():
			if (child.name as String).begins_with("Fruit_"):
				child.visible = not hidden
