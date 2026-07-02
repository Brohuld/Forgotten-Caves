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

const TreeSpecies := preload("res://scripts/data/materiaux/types/bois/TreeSpecies.gd")

@export var grid_width: int = 20
@export var grid_depth: int = 20
@export var ground_level: float = 30.0  # sommet de la carte (HEIGHT, Sprint 23 : 10 -> 30)
@export var tree_count: int = 12
@export var fruit_tree_count: int = 6  # Sprint 24ter : 2 de chaque espece environ
@export var size_multiplier: float = 1.3  # 2026-07-02 : arbres agrandis de 30% (jauges nains/arbres/buissons rejustees)


func _ready() -> void:
	randomize()
	for i in range(tree_count):
		_spawn_tree(TreeSpecies.random_species())
	for i in range(fruit_tree_count):
		_spawn_tree(TreeSpecies.random_fruit_species())


func _spawn_tree(species: Dictionary) -> void:
	var x := randf_range(2.0, float(grid_width - 2))
	var z := randf_range(2.0, float(grid_depth - 2))

	# Petites variations aleatoires par instance (echelle + teinte), pour que
	# deux arbres de la meme espece ne soient jamais des clones parfaits.
	# size_multiplier applique en plus une taille de base plus grande a TOUS
	# les arbres (2026-07-02, demande explicite : arbres agrandis de 30%).
	var scale_jitter: float = randf_range(0.85, 1.15) * size_multiplier
	var tint_jitter: float = randf_range(0.9, 1.1)

	var tree := Node3D.new()
	tree.name = "Tree_%d" % get_child_count()
	tree.position = Vector3(x, ground_level, z)
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
	# BerryBush.gd, voir Dwarf.gd/_complete_task pour la logique commune)
	if species.has("fruit_resource"):
		var fruit_count: int = species.get("fruit_count", 5)
		tree.add_to_group("cueillette")
		tree.set_meta("fruit_resource", species["fruit_resource"])
		tree.set_meta("fruits_left", fruit_count)
		_build_fruits(tree, species, trunk_height, fruit_count)


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
	roots.set_surface_override_material(0, _flat_material(species["racine_color"] * tint))
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
	trunk.set_surface_override_material(0, _flat_material(species["tronc_color"] * tint))
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
		branch.set_surface_override_material(0, _flat_material(species["branche_color"] * tint))
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
		blob.set_surface_override_material(0, _flat_material(colors[randi_range(0, colors.size() - 1)] * tint))
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
		cone.set_surface_override_material(0, _flat_material(colors[i % colors.size()] * tint))
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
		blob.set_surface_override_material(0, _flat_material(colors[randi_range(0, colors.size() - 1)] * tint))
		tree.add_child(blob)
		_build_leaf_cluster(blob, colors, tint, randi_range(6, 8), mesh.radius * 0.8)


## Sprint 24ter : fruits de l'arbre (arbres fruitiers uniquement, voir
## _spawn_tree) - petites spheres colorees dispersees pres du feuillage,
## nommees "Fruit_%d" (0..fruit_count-1) pour pouvoir en retirer une a la
## fois a la cueillette (voir Dwarf.gd/_complete_task, meme convention que
## BerryBush.gd/Berry_%d).
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
		leaf.set_surface_override_material(0, _flat_material(colors[randi_range(0, colors.size() - 1)] * tint))
		parent.add_child(leaf)


## Materiau plat (visuellement "flat" = pas de texture/reflet), coherent
## avec le style du reste du jeu (terrain, decorations de sol : voir
## VoxelWorld._make_material). 2026-07-02 : passe de SHADING_MODE_UNSHADED a
## l'eclairage reel pour que les arbres reagissent au cycle jour/nuit
## (DayNightCycle.gd) - meme raison que VoxelWorld._make_material.
## roughness=1/metallic=0 garde l'aspect plat/mat, sans reflet.
func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat
