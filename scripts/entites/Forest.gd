extends Node3D
## Genere les arbres de la carte (foret + arbres fruitiers) et gere leur
## cycle de vie (coupe, repousse, teinte saisonniere, visibilite selon le
## niveau de vue). Chaque arbre varie selon son espece (TreeSpecies.gd :
## chene/sapin/bouleau pour la foret, pommier/oranger/cerisier pour les
## fruitiers), chacune avec ses propres couleurs de tronc/branches/racines/
## feuilles et sa silhouette generale (touffue/conique/fine). Chaque arbre
## garde en metadonnee le type de bois qu'il donne a la coupe (voir
## Dwarf.gd/_complete_task), pour que le bois recolte corresponde a
## l'espece de l'arbre abattu. Les arbres fruitiers (TreeSpecies.FRUIT_SPECIES)
## sont places a part des arbres de foret (voir _ready) - meme construction
## que les autres, plus des fruits (_build_fruits) recoltables via l'action
## "Cueillir". Ils rejoignent le groupe "cueillette" (comme les buissons a
## baies, voir BerryBush.gd) en plus du groupe "trees" (toujours coupables
## pour le bois).
##
## Architecture geometrique : toute la geometrie fusionnee d'un arbre
## (racines/tronc/branches/cones/blobs de feuillage/petites feuilles) est
## stockee dans 6 MultiMeshInstance3D PARTAGES entre tous les arbres de la
## carte (un par PartType, voir _build_shared_meshes), plutot que par des
## noeuds Godot individuels par piece - un seul arbre peut compter des
## dizaines de pieces, et la carte en contient plusieurs milliers. La
## position/rotation de chaque piece est calculee comme un Transform3D
## COMPOSE a la main (parent_xform * Transform3D(rotation, position)),
## exactement la meme composition que Godot applique lui-meme en interne
## pour calculer le global_transform d'un noeud enfant - _record_part()
## applique ensuite l'echelle reelle de la piece (part_scale) et enregistre
## directement l'instance dans les tableaux _pending_xforms/_live_xforms.
## Seuls le Node3D racine de chaque arbre (position/rotation/groupe/
## metadonnees) et ses fruits (encore des noeuds individuels, recoltables
## un par un) restent de vrais noeuds Godot.
##
## Astuce cle pour la "taille" : un MultiMesh partage plusieurs instances qui
## utilisent TOUTES le meme maillage de base (un cylindre/une sphere/une boite
## "unite", rayon/taille=1) - la taille REELLE de chaque piece (ex : rayon
## d'une boule de feuillage entre 0.38 et 0.55) est appliquee comme un
## FACTEUR D'ECHELLE LOCAL supplementaire (part_scale), compose APRES le
## transform recolte (qui, lui, ne contient que position/rotation/echelle de
## l'ARBRE et de la hierarchie de pieces, jamais la taille propre du maillage
## d'origine) - voir _record_part.
##
## Coupe d'un arbre (Dwarf.gd, action "couper") : comme toute la geometrie
## vit dans des MultiMesh PARTAGES entre tous les arbres, on ne peut pas se
## contenter de tree.queue_free() pour la faire disparaitre - voir
## hide_tree_visuals(), a appeler AVANT de liberer le noeud arbre.

const TreeSpecies := preload("res://scripts/data/materiaux/types/bois/TreeSpecies.gd")
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")

## Reference a VoxelWorld pour rejeter les positions d'eau (voir
## _pick_dry_position) a la generation initiale ET a la repousse
## (_spawn_new_tree_and_apply reutilise _spawn_tree donc en profite
## automatiquement).
@onready var voxel_world: Node3D = %VoxelWorld

## Lit directement VoxelWorld.WIDTH/DEPTH/HEIGHT au lieu d'un nombre
## duplique en dur - desynchronisation avec la taille reelle de la carte
## structurellement impossible.
const grid_width := VoxelWorldScript.WIDTH
const grid_depth := VoxelWorldScript.DEPTH
const ground_level := float(VoxelWorldScript.HEIGHT)  # sommet de la carte
@export var size_multiplier: float = 1.3

## Densite exprimee par 1000 cases plutot qu'un nombre fixe, pour que le
## nombre d'arbres suive automatiquement la taille de la carte.
@export var tree_density_per_1000_tiles: float = 30.0
@export var fruit_tree_density_per_1000_tiles: float = 15.0

## Un type par "piece" d'arbre, chacun associe a un MultiMeshInstance3D
## partage (voir _mmi) et un maillage de base "unite" (voir
## _build_shared_meshes).
enum PartType { ROOTS, TRUNK, BRANCH, CONE, BLOB, LEAF }

## Cacher une instance en mettant son echelle a Vector3.ZERO PILE (Basis
## totalement degenere, determinant=0) peut corrompre le rendu de TOUT le
## lot d'instances du MultiMesh concerne sous un materiau a eclairage reel
## (roughness=1.0, pas SHADING_MODE_UNSHADED - voir _make_mmi) : Godot
## calcule une matrice de normales par instance a partir de sa transform, et
## une base totalement degeneree produit un resultat non-inversible (NaN/
## Inf). Une echelle MINUSCULE mais jamais exactement zero (base non-
## degeneree, determinant non-nul) reste invisible a l'oeil sans exposer
## Godot a ce calcul sur une matrice singuliere.
const HIDDEN_INSTANCE_SCALE := 0.0001

## Types de piece consideres comme "feuillage" - seuls ceux-la sont reteints
## a chaque changement de saison (voir apply_season_tint) ; le tronc/les
## racines/les branches/les fruits ne changent jamais de couleur avec la
## saison.
const _FOLIAGE_PART_TYPES := [PartType.CONE, PartType.BLOB, PartType.LEAF]

var _mmi: Dictionary = {}              # PartType -> MultiMeshInstance3D
var _pending_xforms: Dictionary = {}   # PartType -> Array[Transform3D] (transform D'ORIGINE au moment du spawn, jamais modifie ensuite)
var _pending_colors: Dictionary = {}   # PartType -> Array[Color]
## Contrairement a _pending_xforms (toujours la transform D'ORIGINE), ce
## tableau retient la transform REELLEMENT AFFICHEE en ce moment pour
## chaque instance (visible normalement, cachee via HIDDEN_INSTANCE_SCALE
## si l'arbre a ete coupe, ou cachee/restauree selon le niveau de vue -
## voir hide_tree_visuals/update_view_level, qui ecrivent ici en plus du
## MultiMesh lui-meme). Necessaire car Godot reinitialise TOUTES les
## instances existantes d'un MultiMesh a leur valeur par defaut des que son
## "instance_count" est agrandi (comportement documente du moteur, issue
## officielle #76180) - _spawn_new_tree_and_apply doit donc reappliquer
## explicitement cet etat (pas _pending_xforms, qui ferait reapparaitre a
## tort un arbre coupe) sur TOUTES les instances a chaque fois qu'un
## agrandissement se produit, pas seulement sur les nouvelles.
var _live_xforms: Dictionary = {}      # PartType -> Array[Transform3D]
## Meme principe que _live_xforms, mais pour la couleur actuellement
## affichee (peut differer de _pending_colors a cause de la teinte de
## saison sur le feuillage - voir apply_season_tint/_tinted_foliage_color).
var _live_colors: Dictionary = {}      # PartType -> Array[Color]
## Derniere saison appliquee (voir apply_season_tint) - retenue ici pour que
## _spawn_new_tree_and_apply puisse recalculer la bonne teinte de feuillage
## apres un agrandissement, sans dependre de SeasonSystem.gd.
var _current_season_id: String = "ete"
# Couleur de BASE (avant teinte de saison) de chaque instance de feuillage,
# index-alignee avec le multimesh final - permet a apply_season_tint() de
# reteindre a partir de la couleur d'origine a chaque fois (jamais de la
# couleur deja teintee), donc aucune derive possible en changeant de saison
# plusieurs fois.
var _foliage_base_colors: Dictionary = {}  # PartType -> Array[Color]

# Teinte multiplicative appliquee par-dessus la couleur de base du
# feuillage, par saison. "ete" = neutre (couleurs d'origine, aucun
# changement). Deux tables : une pour BLOB/LEAF (chene/bouleau/arbres
# fruitiers - "tous sauf les sapins") et une pour CONE (sapin uniquement)
# qui reste vert toute l'annee sauf au printemps (seule saison ou tous les
# arbres, sapin inclus, sont concernes). Le canal alpha de
# SEASON_FOLIAGE_TINT["hiver"] (0.12, tres faible) fait "tomber les
# feuilles" via la transparence du materiau (voir _build_shared_meshes,
# transparence active UNIQUEMENT sur BLOB/LEAF) plutot qu'en cachant des
# instances via leur transform - ce qui entrerait en conflit avec
# update_view_level()/hide_tree_visuals(), qui remettent en permanence les
# transforms d'origine independamment de la saison.
const SEASON_FOLIAGE_TINT := {  # BLOB + LEAF (chene/bouleau/arbres fruitiers)
	"ete": Color(1.0, 1.0, 1.0, 1.0),
	"hiver": Color(0.55, 0.5, 0.48, 0.12),
	"printemps": Color(1.15, 1.2, 1.05, 1.0),
}
# Une teinte MULTIPLICATIVE (couleur * facteur) ne peut pas faire dominer le
# rouge quand la couleur de base est deja tres sombre et tres verte (chene :
# Color(0.04, 0.16, 0.06) - meme multipliee par un grand facteur rouge, le
# canal vert de depart reste plus fort). L'automne utilise donc un MELANGE
# (lerp) vers une couleur cible rouge/orange, qui garantit un resultat rouge
# quelle que soit la couleur de depart - voir apply_season_tint.
const AUTOMNE_LEAF_TARGET := Color(0.55, 0.10, 0.05)
const AUTOMNE_LEAF_STRENGTH := 0.65
const SEASON_CONE_TINT := {  # CONE (sapin uniquement) - jamais rougi/transparent
	"ete": Color(1.0, 1.0, 1.0),
	"automne": Color(1.0, 1.0, 1.0),
	"hiver": Color(1.0, 1.0, 1.0),
	"printemps": Color(1.08, 1.12, 1.05),
}


## Nombre d'arbres construits avant de rendre la main au moteur (await
## process_frame) - laisse une image s'afficher regulierement pendant la
## generation (plusieurs milliers d'arbres) au lieu d'un seul gros blocage
## synchrone. Chaque await coute au moins une frame complete (16-30ms) : une
## valeur trop basse (25) multiplie inutilement le nombre de pauses et
## degrade le temps de chargement total sans benefice visuel supplementaire -
## releve a 150 pour reduire nettement le nombre d'attentes tout en gardant
## des pauses assez frequentes pour eviter un gel visible sur une tres grande
## carte.
const BATCH_SIZE := 150

## Le decoupage par paquets (await) casse la garantie implicite de Godot
## comme quoi le _ready() d'un noeud precedent dans la scene finit toujours
## avant celui du noeud suivant. Les appelants qui dependent de la
## generation terminee (SeasonSystem.gd) doivent attendre explicitement ce
## signal avant leur premier appel a apply_season_tint().
signal generation_finished
var generation_done: bool = false

func _ready() -> void:
	# Le generateur aleatoire global est deja correctement initialise a ce
	# point (VoxelWorld._ready(), declare avant Forest dans Main.tscn, a
	# deja fixe sa graine) - pas de randomize() ici, ce qui rend la
	# position des arbres reproductible par graine (voir StartMenu.gd).
	if OS.is_debug_build():
		print("[Perf] Forest (arbres) : debut a %.1f s depuis le debut de la scene" % ((Time.get_ticks_msec() - DayNightCycleScript.scene_start_ms) / 1000.0))
	_build_shared_meshes()
	var tile_count: float = float(grid_width * grid_depth)
	var tree_count: int = int(round(tree_density_per_1000_tiles * tile_count / 1000.0))
	var fruit_tree_count: int = int(round(fruit_tree_density_per_1000_tiles * tile_count / 1000.0))
	var spawned := 0
	for i in range(tree_count):
		_spawn_tree(TreeSpecies.random_species())
		spawned += 1
		if spawned % BATCH_SIZE == 0:
			await get_tree().process_frame
	for i in range(fruit_tree_count):
		_spawn_tree(TreeSpecies.random_fruit_species())
		spawned += 1
		if spawned % BATCH_SIZE == 0:
			await get_tree().process_frame
	_apply_pending_instances()
	if OS.is_debug_build():
		print("[Perf] Forest (arbres) : fin (%d arbres) a %.1f s depuis le debut de la scene" % [spawned, (Time.get_ticks_msec() - DayNightCycleScript.scene_start_ms) / 1000.0])
	generation_done = true
	generation_finished.emit()


## Les arbres coupes (Dwarf.gd, action "couper") liberent leur noeud et
## quittent donc le groupe "trees" - on verifie periodiquement si la
## population est repassee sous la densite cible et on fait repousser UN
## arbre a la fois (evite un pic de perf si beaucoup ont ete coupes d'un
## coup). Pas de vraie simulation de croissance (pas d'arbre "jeune" qui
## grandit visuellement) : l'arbre apparait directement a sa taille adulte,
## comme a la generation initiale de la carte.
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


## Fait pousser un seul arbre APRES la generation initiale.
## Agrandir "multimesh.instance_count" pour loger les nouvelles instances
## d'un nouvel arbre reinitialise TOUTES les instances DEJA EXISTANTES de ce
## MultiMesh a leur valeur par defaut (transform identite, couleur blanche -
## comportement documente du moteur, issue officielle #76180), y compris
## celles des autres arbres. Des qu'un agrandissement est necessaire pour un
## type de piece donne, on reapplique donc EXPLICITEMENT l'etat REEL actuel
## de TOUTES ses instances (pas seulement celles du nouvel arbre) a partir
## de _live_xforms/_live_colors, qui retiennent en permanence, pour chaque
## instance, sa transform/couleur veritablement affichee (visible
## normalement, cachee par une coupe, ou cachee/restauree par le niveau de
## vue - voir hide_tree_visuals/update_view_level, qui ecrivent aussi dans
## ces deux tableaux). Si aucun agrandissement n'est necessaire pour un type
## donne, on se contente de n'ecrire QUE les nouvelles instances (chemin
## rapide, aucun risque - Godot ne touche a rien tant que "instance_count"
## ne change pas).
func _spawn_new_tree_and_apply(species: Dictionary) -> void:
	var start_indices: Dictionary = {}
	for part_type in _mmi.keys():
		start_indices[part_type] = _pending_xforms[part_type].size()

	_spawn_tree(species)

	for part_type in _mmi.keys():
		var mmi: MultiMeshInstance3D = _mmi[part_type]
		var new_count: int = _pending_xforms[part_type].size()
		if mmi.multimesh.instance_count < new_count:
			mmi.multimesh.instance_count = new_count
			# Agrandissement reel : Godot vient de reinitialiser TOUTES les
			# instances de ce MultiMesh (0..new_count-1, y compris celles des
			# autres arbres et la toute nouvelle) - on reapplique donc tout,
			# a partir de l'etat REEL retenu dans _live_xforms/_live_colors.
			var live_xforms: Array = _live_xforms[part_type]
			var live_colors: Array = _live_colors[part_type]
			for i in range(new_count):
				mmi.multimesh.set_instance_transform(i, live_xforms[i])
				mmi.multimesh.set_instance_color(i, live_colors[i])
		else:
			# Pas d'agrandissement necessaire : les instances existantes ne
			# sont pas touchees par Godot, on ne pousse que les nouvelles.
			var xforms: Array = _pending_xforms[part_type]
			var live_colors: Array = _live_colors[part_type]
			for i in range(start_indices[part_type], new_count):
				mmi.multimesh.set_instance_transform(i, xforms[i])
				mmi.multimesh.set_instance_color(i, live_colors[i])


## Cree les 6 MultiMeshInstance3D partages (un par PartType), avec leur
## maillage "unite" (rayon/taille=1, voir chaque _make_*_mesh) et un seul
## materiau a couleur-par-instance (meme principe que les pepites de filons
## de VoxelWorld.gd - use_colors=true + vertex_color_use_as_albedo=true).
func _build_shared_meshes() -> void:
	_mmi[PartType.ROOTS] = _make_mmi(_make_cylinder_mesh(0.16, 0.30, 1.0))
	_mmi[PartType.TRUNK] = _make_mmi(_make_cylinder_mesh(0.09, 0.16, 1.0))
	_mmi[PartType.BRANCH] = _make_mmi(_make_cylinder_mesh(0.03, 0.06, 1.0))
	_mmi[PartType.CONE] = _make_mmi(_make_cylinder_mesh(0.0, 1.0, 1.0))
	_mmi[PartType.BLOB] = _make_mmi(_make_sphere_mesh(1.0))
	_mmi[PartType.LEAF] = _make_mmi(_make_box_mesh(Vector3.ONE))
	# Transparence activee UNIQUEMENT sur les materiaux BLOB/LEAF (chacun un
	# materiau distinct, voir _make_mmi) - jamais sur CONE (sapin) ni sur les
	# autres pieces. L'alpha de la teinte hiver (SEASON_FOLIAGE_TINT, tres
	# faible) rend ces feuilles quasiment invisibles sans toucher a leur
	# transform (evite un conflit avec update_view_level()/hide_tree_visuals()).
	for part_type in [PartType.BLOB, PartType.LEAF]:
		var mat: StandardMaterial3D = _mmi[part_type].material_override
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for key in _mmi.keys():
		_pending_xforms[key] = []
		_pending_colors[key] = []
		_live_xforms[key] = []
		_live_colors[key] = []
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


## radial_segments/rings par defaut de Godot (64/32) sont concus pour un
## objet unique bien visible - beaucoup trop detailles pour une forme
## instanciee des milliers de fois via MultiMesh (une par piece d'arbre, sur
## toute la carte) et vue de loin. Reduit ici a une valeur largement
## suffisante visuellement (aucune difference perceptible a l'echelle d'un
## arbre) mais des dizaines de fois moins couteuse en triangles - c'etait la
## cause principale de l'effondrement du framerate sur une grande carte (des
## millions de triangles gaspilles sur du feuillage jamais vu de pres). Meme
## principe deja applique correctement aux pepites de filon, voir
## VoxelVeins.gd/_make_pepite_mesh.
const TREE_CYLINDER_RADIAL_SEGMENTS := 8
const TREE_SPHERE_RADIAL_SEGMENTS := 8
const TREE_SPHERE_RINGS := 5


func _make_cylinder_mesh(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = TREE_CYLINDER_RADIAL_SEGMENTS
	return mesh


func _make_sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = TREE_SPHERE_RADIAL_SEGMENTS
	mesh.rings = TREE_SPHERE_RINGS
	return mesh


func _make_box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## Tire une position au hasard en rejetant l'eau (voir VoxelWorld.is_water)
## - essais bornes par securite, repli sur la derniere position tiree si
## vraiment aucune case seche n'est trouvee (tres improbable, l'eau ne
## couvre qu'une petite partie de la carte).
func _pick_dry_position() -> Vector2:
	var x := randf_range(2.0, float(grid_width - 2))
	var z := randf_range(2.0, float(grid_depth - 2))
	var guard := 0
	while voxel_world != null and voxel_world.is_water(int(x), int(z)) and guard < 20:
		x = randf_range(2.0, float(grid_width - 2))
		z = randf_range(2.0, float(grid_depth - 2))
		guard += 1
	return Vector2(x, z)


## Hauteur du sol (sommet de colonne + 1) a une position XZ donnee - meme
## principe que Dwarf.gd/_ground_y_at. Repli sur ground_level si
## voxel_world est introuvable ou hors carte.
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
	# size_multiplier applique en plus une taille de base commune a TOUS les
	# arbres ; echelle_base est un multiplicateur PAR ESPECE (1.0 si absent,
	# voir TreeSpecies.gd) applique en plus - grandit tronc/feuilles/branches/
	# racines proportionnellement pour cette espece uniquement.
	var scale_jitter: float = randf_range(0.85, 1.15) * size_multiplier * species.get("echelle_base", 1.0)
	var tint_jitter: float = randf_range(0.9, 1.1)

	var tree := Node3D.new()
	tree.name = "Tree_%d" % get_child_count()
	# Hauteur reelle de la colonne (sommet+1), pas ground_level fixe - sinon
	# un arbre plante sur une colline apparaitrait enfonce dans le sol.
	tree.position = Vector3(x, _ground_y_at(x, z), z)
	tree.rotation.y = randf_range(0.0, TAU)
	tree.scale = Vector3.ONE * scale_jitter
	tree.add_to_group("trees")
	tree.set_meta("wood_resource", species["wood_resource"])
	tree.set_meta("species_name", species["nom"])
	add_child(tree)

	# Transform de reference pour toute la geometrie de cet arbre, lu UNE
	# fois ici (tree est deja dans l'arbre de scene, position/rotation/scale
	# deja appliques ci-dessus) - chaque piece compose ensuite ses propres
	# decalages locaux par-dessus via multiplication de Transform3D, sans
	# jamais creer le moindre noeud Godot.
	var tree_xform: Transform3D = tree.global_transform

	var trunk_height: float = species["hauteur"]
	var refs: Array = []

	_build_roots(refs, tree_xform, species, tint_jitter)
	var trunk_visual_height: float = _build_trunk(refs, tree_xform, species, trunk_height, tint_jitter)
	_build_branches(refs, tree_xform, species, trunk_height, tint_jitter)
	# _build_foliage renvoie la liste des blobs de feuillage reellement crees
	# (position + rayon), pour que _build_fruits puisse ancrer chaque fruit a
	# la surface d'un blob existant plutot qu'a une position theorique qui
	# pourrait tomber hors du feuillage reel (arrangement des blobs
	# asymetrique/aleatoire).
	var blob_data: Array = _build_foliage(refs, tree_xform, species, trunk_height, trunk_visual_height, tint_jitter)

	_spawn_fruits_if_applicable(tree, species, trunk_height, blob_data)

	# refs liste (type, index) pour chaque piece de CET arbre dans les
	# MultiMesh partages (voir hide_tree_visuals/update_view_level) - aucun
	# noeud temporaire a recolter/detruire, chaque _build_* ci-dessus a deja
	# enregistre ses instances directement via _record_part.
	tree.set_meta("visual_refs", refs)


## Arbre fruitier : ajoute les fruits + rend l'arbre recoltable via l'action
## "Cueillir" (groupe/metadonnees partages avec BerryBush.gd, voir
## Dwarf.gd/_complete_task pour la logique commune). Les fruits restent des
## noeuds individuels (voir _build_fruits) - pas touches par la conversion
## MultiMesh, recoltes un par un a la cueillette. Ne fait rien si l'espece
## n'est pas fruitiere (pas de cle "fruit_resource").
func _spawn_fruits_if_applicable(tree: Node3D, species: Dictionary, trunk_height: float, blob_data: Array) -> void:
	if not species.has("fruit_resource"):
		return
	var fruit_count: int = species.get("fruit_count", 5)
	tree.add_to_group("cueillette")
	tree.set_meta("fruit_resource", species["fruit_resource"])
	tree.set_meta("fruits_left", fruit_count)
	_build_fruits(tree, species, trunk_height, fruit_count, blob_data)


## Petite base evasee au pied du tronc (racines), pour eviter l'effet
## "poteau plante dans le sol" d'un simple cylindre droit.
func _build_roots(refs: Array, tree_xform: Transform3D, species: Dictionary, tint: float) -> void:
	var mesh_height := 0.22
	var local_xform := Transform3D(Basis(), Vector3(0, 0.11, 0))
	var color: Color = species["racine_color"] * tint
	_record_part(refs, tree_xform * local_xform, PartType.ROOTS, color, Vector3(1.0, mesh_height, 1.0))


## Tronc effile (plus fin en haut qu'en bas), hauteur dependante de l'espece.
## Pour le sapin (feuillage conique), un vrai sapin n'a qu'un petit tronc
## visible avant que les branches/aiguilles ne commencent - le tronc visuel
## est donc beaucoup plus court que "trunk_height" (hauteur totale de
## l'arbre), le reste etant recouvert par le feuillage (voir
## _build_foliage_conique, qui recoit la hauteur reelle du tronc en retour).
## Renvoie la hauteur visuelle du tronc (= trunk_height pour les autres formes).
func _build_trunk(refs: Array, tree_xform: Transform3D, species: Dictionary, trunk_height: float, tint: float) -> float:
	var visual_height: float = trunk_height
	if species.get("forme", "touffu") == "conique":
		visual_height = max(trunk_height * 0.12, 0.18)

	var local_xform := Transform3D(Basis(), Vector3(0, 0.22 + visual_height * 0.5, 0))
	var color: Color = species["tronc_color"] * tint
	_record_part(refs, tree_xform * local_xform, PartType.TRUNK, color, Vector3(1.0, visual_height, 1.0))
	return visual_height


## 3 a 6 branches partant du haut du tronc et reparties tout autour (angle Y
## aleatoire) pour un aspect moins symetrique/artificiel. Chacune porte une
## petite grappe de "feuilles" a son extremite (voir _build_leaf_cluster).
## Pas de branches du tout pour le sapin (feuillage conique) - le gros cone
## de feuillage represente deja toute la silhouette, des batons de branche
## qui depasseraient par-dessus n'auraient pas de sens sur un vrai sapin.
## Pivot/branche/extremite sont des Transform3D composes a la main (meme
## hierarchie qu'une construction par noeuds) : decalage Y du pivot, puis
## angle du pivot, puis longueur de branche, puis nombre de feuilles - cet
## ordre de tirages aleatoires doit rester stable pour que la generation par
## graine reste reproductible.
func _build_branches(refs: Array, tree_xform: Transform3D, species: Dictionary, trunk_height: float, tint: float) -> void:
	if species.get("forme", "touffu") == "conique":
		return
	var branch_count: int = randi_range(4, 6)
	var trunk_top_y: float = 0.22 + trunk_height
	var colors: Array = species["feuillage_colors"]
	for i in range(branch_count):
		var pivot_y: float = trunk_top_y + randf_range(-0.25, 0.15)
		var pivot_angle: float = (TAU / float(branch_count)) * i + randf_range(-0.3, 0.3)
		var pivot_xform: Transform3D = tree_xform * Transform3D(Basis.from_euler(Vector3(0, pivot_angle, 0)), Vector3(0, pivot_y, 0))

		var branch_length: float = randf_range(0.5, 0.8)
		var branch_xform: Transform3D = pivot_xform * Transform3D(Basis.from_euler(Vector3(deg_to_rad(65), 0, 0)), Vector3(0, branch_length * 0.5, 0.12))
		var branch_color: Color = species["branche_color"] * tint
		_record_part(refs, branch_xform, PartType.BRANCH, branch_color, Vector3(1.0, branch_length, 1.0))

		# Ancre a l'extremite haute de la branche (en espace local de la
		# branche) : herite automatiquement de toutes les rotations parent
		# (pivot + branche) via la composition de Transform3D ci-dessus, pas
		# besoin de recalculer la position monde a la main.
		var tip_xform: Transform3D = branch_xform * Transform3D(Basis(), Vector3(0, branch_length * 0.5, 0))
		_build_leaf_cluster(refs, tip_xform, colors, tint, randi_range(6, 9), 0.12)


## Aiguille le bon type de feuillage selon la "forme" de l'espece.
## Renvoie la liste des blobs de feuillage crees (Array de {"position":
## Vector3, "radius": float}, coordonnees locales a "tree") - vide pour le
## feuillage conique (sapin, jamais un arbre fruitier). Utilise par
## _build_fruits pour ancrer les fruits a de vrais blobs (voir plus bas).
func _build_foliage(refs: Array, tree_xform: Transform3D, species: Dictionary, trunk_height: float, trunk_visual_height: float, tint: float) -> Array:
	var top_y: float = 0.22 + trunk_height
	match species.get("forme", "touffu"):
		"conique":
			# Le feuillage part du sommet du (court) tronc visuel, pas du
			# sommet de la hauteur totale de l'arbre - il occupe donc presque
			# toute la silhouette, comme un vrai sapin.
			_build_foliage_conique(refs, tree_xform, species, 0.22 + trunk_visual_height, top_y, tint)
			return []
		"fin":
			return _build_foliage_fin(refs, tree_xform, species, top_y, tint)
		_:
			return _build_foliage_touffu(refs, tree_xform, species, top_y, tint)


## Feuillage touffu (chene, arbres fruitiers) : plusieurs spheres qui se
## chevauchent, placees de façon legerement asymetrique pour eviter la
## "boule parfaite". Chaque blob recoit en plus une petite grappe de
## "feuilles" (voir _build_leaf_cluster) a sa surface, pour un aspect moins
## "boule lisse" et plus feuillu de pres.
func _build_foliage_touffu(refs: Array, tree_xform: Transform3D, species: Dictionary, top_y: float, tint: float) -> Array:
	# Facteur par espece (voir TreeSpecies.gd/feuillage_echelle, 1.0 par
	# defaut donc aucun changement pour les arbres fruitiers, qui partagent
	# cette meme fonction) applique aux rayons des blobs et a leur etalement
	# horizontal (xz_spread) - pas a la plage verticale (y_min/y_max), qui
	# reste fixee par rapport a "top_y" (sommet du tronc).
	var echelle: float = species.get("feuillage_echelle", 1.0)
	return _build_blob_foliage(refs, tree_xform, species, top_y, tint, 4, 6, 0.38 * echelle, 0.55 * echelle, 0.26 * echelle, 0.05, 0.65, 7, 10)


## Feuillage conique (sapin) : 5-6 cones empiles qui couvrent depuis le
## sommet du (court) tronc visuel jusqu'en haut de l'arbre (start_y ->
## top_y), plus large a la base et etroit en pointe, comme un vrai sapin (le
## tronc ne depasse presque pas du feuillage).
func _build_foliage_conique(refs: Array, tree_xform: Transform3D, species: Dictionary, start_y: float, top_y: float, tint: float) -> void:
	var colors: Array = species["feuillage_colors"]
	var levels: int = randi_range(5, 6)
	var span: float = max(top_y - start_y, 0.3)
	var level_height: float = span / float(levels) * 1.4  # chevauchement pour eviter les trous
	var y := start_y
	for i in range(levels):
		var t: float = float(i) / float(max(levels - 1, 1))  # 0 en bas, 1 en haut
		var bottom_radius: float = lerp(0.48, 0.10, t)
		var local_xform := Transform3D(Basis(), Vector3(0, y + level_height * 0.5, 0))
		var cone_color: Color = colors[i % colors.size()] * tint
		# Maillage "unite" du cone : top_radius=0, bottom_radius=1, height=1
		# (voir _build_shared_meshes) - le rayon reel varie par niveau
		# (bottom_radius), donc l'echelle XZ suit ce rayon directement.
		_record_part(refs, tree_xform * local_xform, PartType.CONE, cone_color, Vector3(bottom_radius, level_height, bottom_radius))
		y += span / float(levels)


## Feuillage fin/eparse (bouleau) : quelques petites touffes legeres, moins
## denses que le chene, coherent avec un arbre plus elance. Meme ajout de
## grappes de "feuilles" que le feuillage touffu.
func _build_foliage_fin(refs: Array, tree_xform: Transform3D, species: Dictionary, top_y: float, tint: float) -> Array:
	return _build_blob_foliage(refs, tree_xform, species, top_y, tint, 3, 5, 0.26, 0.38, 0.22, 0.0, 0.55, 6, 8)


## Logique commune a _build_foliage_touffu (chene/arbres fruitiers) et
## _build_foliage_fin (bouleau) - meme construction (blobs spheriques +
## grappes de feuilles a leur surface), seuls les nombres/tailles/plages
## different par espece. "blob_data" renvoie une position LOCALE a l'arbre
## (utilisee par _build_fruits).
func _build_blob_foliage(refs: Array, tree_xform: Transform3D, species: Dictionary, top_y: float, tint: float,
		cluster_count_min: int, cluster_count_max: int,
		radius_min: float, radius_max: float,
		xz_spread: float, y_min: float, y_max: float,
		leaf_count_min: int, leaf_count_max: int) -> Array:
	var colors: Array = species["feuillage_colors"]
	var cluster_count: int = randi_range(cluster_count_min, cluster_count_max)
	var blob_data: Array = []
	for i in range(cluster_count):
		var radius: float = randf_range(radius_min, radius_max)
		var blob_local_pos := Vector3(
			randf_range(-xz_spread, xz_spread),
			top_y + randf_range(y_min, y_max),
			randf_range(-xz_spread, xz_spread)
		)
		var blob_xform: Transform3D = tree_xform * Transform3D(Basis(), blob_local_pos)
		var blob_color: Color = colors[randi_range(0, colors.size() - 1)] * tint
		_record_part(refs, blob_xform, PartType.BLOB, blob_color, Vector3.ONE * radius)
		_build_leaf_cluster(refs, blob_xform, colors, tint, randi_range(leaf_count_min, leaf_count_max), radius * 0.8)
		blob_data.append({"position": blob_local_pos, "radius": radius})
	return blob_data


## Fruits de l'arbre (arbres fruitiers uniquement, voir _spawn_tree) -
## petites spheres colorees dispersees pres du feuillage, nommees "Fruit_%d"
## (0..fruit_count-1) pour pouvoir en retirer une a la fois a la cueillette
## (voir Dwarf.gd/_complete_task, meme convention que BerryBush.gd/Berry_%d).
## PAS convertis en MultiMesh (contrairement a tout le reste de l'arbre) :
## ils doivent pouvoir disparaitre un par un a la cueillette, ce qu'un
## MultiMesh partage ne permet pas facilement ; leur nombre reste de toute
## facon tres faible (5-6 par arbre fruitier).
## Chaque fruit est ancre a la surface d'un blob de feuillage REELLEMENT
## cree (choisi parmi "blob_data", position/rayon renvoyes par
## _build_foliage), avec une petite marge (0.85-1.05x le rayon) pour rester
## visible en depassant un peu - une couronne theorique a distance fixe
## autour du tronc ne suivrait pas la forme reelle du feuillage (amas de
## blobs places de facon asymetrique/aleatoire), laissant certains fruits
## flotter dans le vide et d'autres caches derriere le feuillage.
func _build_fruits(tree: Node3D, species: Dictionary, trunk_height: float, fruit_count: int, blob_data: Array) -> void:
	var top_y: float = 0.22 + trunk_height
	var mat := _flat_material(species["fruit_color"])
	var fruit_radius: float = species.get("fruit_radius", 0.13)
	# Le choix d'un blob au hasard PAR fruit (randi_range) pourrait, avec
	# seulement 4-6 blobs, en tirer certains 4-5 fois et d'autres jamais -
	# tous les fruits se retrouveraient alors regroupes sur 1-2 blobs
	# voisins, donc du meme cote de l'arbre. Repartition en "tourniquet"
	# (chaque blob melange puis pris a son tour) garantit que TOUS les blobs
	# recoivent un nombre de fruits equilibre, quel que soit fruit_count.
	var blobs_shuffled: Array = blob_data.duplicate()
	blobs_shuffled.shuffle()
	for i in range(fruit_count):
		var fruit := MeshInstance3D.new()
		fruit.name = "Fruit_%d" % i
		var mesh := SphereMesh.new()
		mesh.radius = fruit_radius
		mesh.height = fruit_radius * 2.0
		# Segments reduits (voir TREE_SPHERE_RADIAL_SEGMENTS/_RINGS plus haut) -
		# ces fruits sont individuels (pas de MultiMesh possible ici, voir
		# commentaire au-dessus de cette fonction), donc chacun est deja un
		# MeshInstance3D/draw call a part entiere ; inutile d'ajouter des
		# milliers de triangles superflus par-dessus.
		mesh.radial_segments = TREE_SPHERE_RADIAL_SEGMENTS
		mesh.rings = TREE_SPHERE_RINGS
		fruit.mesh = mesh
		if blobs_shuffled.is_empty():
			# Filet de securite si jamais aucun blob n'a ete cree (ne devrait
			# pas arriver pour un arbre fruitier, "touffu" par construction).
			var angle := randf_range(0.0, TAU)
			fruit.position = Vector3(
				cos(angle) * 0.5,
				top_y + randf_range(-0.05, 0.65),
				sin(angle) * 0.5
			)
		else:
			var blob: Dictionary = blobs_shuffled[i % blobs_shuffled.size()]
			var blob_pos: Vector3 = blob["position"]
			var blob_radius: float = blob["radius"]
			# Elevation sur toute la sphere du blob (-90..+90 degres), pas
			# seulement le dessous, pour repartir les fruits tout autour de
			# chaque blob plutot que biaises vers le bas.
			var az := randf_range(0.0, TAU)
			var elev := randf_range(deg_to_rad(-90.0), deg_to_rad(90.0))
			var dir := Vector3(cos(elev) * cos(az), sin(elev), cos(elev) * sin(az))
			var dist := blob_radius * randf_range(0.85, 1.05)
			fruit.position = blob_pos + dir * dist
		fruit.set_surface_override_material(0, mat)
		tree.add_child(fruit)


## Petite grappe de "feuilles" (plaques plates tres fines, sans image/
## texture) autour d'un point donne - utilise aux extremites des branches et
## sur le feuillage touffu/fin, pour un aspect plus detaille que de simples
## boules de couleur. Taille/position/rotation sont calculees dans un ordre
## fixe (mesh.size, puis position, puis rotation, puis couleur) qui doit
## rester stable pour la generation par graine.
func _build_leaf_cluster(refs: Array, parent_xform: Transform3D, colors: Array, tint: float, count: int, spread: float) -> void:
	for i in range(count):
		var leaf_size := Vector3(randf_range(0.05, 0.08), 0.01, randf_range(0.03, 0.05))
		var leaf_pos := Vector3(
			randf_range(-spread, spread),
			randf_range(-spread, spread),
			randf_range(-spread, spread)
		)
		var leaf_rot := Vector3(randf_range(-0.5, 0.5), randf_range(0.0, TAU), randf_range(-0.5, 0.5))
		var leaf_color: Color = colors[randi_range(0, colors.size() - 1)] * tint
		var leaf_local := Transform3D(Basis.from_euler(leaf_rot), leaf_pos)
		_record_part(refs, parent_xform * leaf_local, PartType.LEAF, leaf_color, leaf_size)


## Enregistre une piece d'arbre directement dans le MultiMeshInstance3D
## partage correspondant, sans jamais passer par un Node3D temporaire.
## "global_xform" est le Transform3D deja compose a la main par l'appelant
## (tree_xform * ... * local_xform, meme composition que Godot applique
## lui-meme pour un noeud enfant). "part_scale" est le facteur d'echelle a
## appliquer au maillage "unite" du MultiMesh pour retrouver la taille
## reelle voulue (rayon/hauteur/dimensions d'origine de cette piece precise)
## - applique APRES global_xform. L'instance est mise en attente (voir
## _apply_pending_instances, appele une seule fois a la fin de _ready) et
## (type, index) est ajoute a "refs" (liste des instances de CET arbre, voir
## hide_tree_visuals).
func _record_part(refs: Array, global_xform: Transform3D, part_type: int, color: Color, part_scale: Vector3) -> void:
	var xform: Transform3D = global_xform * Transform3D(Basis().scaled(part_scale), Vector3.ZERO)

	_pending_xforms[part_type].append(xform)
	_pending_colors[part_type].append(color)
	if part_type in _FOLIAGE_PART_TYPES:
		_foliage_base_colors[part_type].append(color)
	# _live_xforms/_live_colors retiennent l'etat REELLEMENT affiche (ici,
	# celui d'un arbre qui vient d'etre plante : visible, teinte de saison
	# courante deja appliquee si feuillage) - voir la doc de _live_xforms.
	_live_xforms[part_type].append(xform)
	if part_type in _FOLIAGE_PART_TYPES:
		_live_colors[part_type].append(_tinted_foliage_color(part_type, color, _current_season_id))
	else:
		_live_colors[part_type].append(color)
	refs.append([part_type, _pending_xforms[part_type].size() - 1])


## Applique une seule fois, apres avoir genere TOUS les arbres, les
## instances en attente (voir _record_part) a chaque MultiMeshInstance3D
## partage - evite de redimensionner les tableaux du MultiMesh arbre par
## arbre.
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
## VoxelWorld._make_material). Eclairage reel (pas SHADING_MODE_UNSHADED)
## pour que les arbres reagissent au cycle jour/nuit (DayNightCycle.gd) ;
## roughness=1/metallic=0 garde l'aspect plat/mat, sans reflet.
## Depuis le passage a des MultiMesh partages, ce materiau n'est plus
## utilise QUE par _build_fruits (les fruits restent de vrais noeuds) -
## toutes les autres pieces (racines/tronc/branches/cones/blobs/feuilles)
## n'ont plus jamais de noeud ni de materiau propre ; leur couleur reelle
## vient directement de la couleur par instance du MultiMesh partage (voir
## _record_part/part_color).
func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## Reteinte tout le feuillage (CONE/BLOB/LEAF) selon la saison donnee -
## appele par SeasonSystem.gd a chaque changement de saison. Chaque instance
## repart de sa couleur de base d'origine (_foliage_base_colors, jamais de
## la couleur deja teintee), donc aucune derive/accumulation possible en
## changeant de saison plusieurs fois. Mise a jour directe de la couleur par
## instance des MultiMeshInstance3D partages (pas de creation de materiau
## par piece).
func apply_season_tint(season_id: String) -> void:
	_current_season_id = season_id
	for part_type in _FOLIAGE_PART_TYPES:
		var mmi: MultiMeshInstance3D = _mmi[part_type]
		var base_colors: Array = _foliage_base_colors[part_type]
		for i in range(base_colors.size()):
			var final_color: Color = _tinted_foliage_color(part_type, base_colors[i], season_id)
			mmi.multimesh.set_instance_color(i, final_color)
			_live_colors[part_type][i] = final_color


## Extrait de apply_season_tint() pour etre reutilisable par
## _spawn_new_tree_and_apply (qui doit pouvoir recalculer la couleur
## actuelle de chaque instance de feuillage apres un agrandissement de
## MultiMesh, sans dupliquer cette logique).
func _tinted_foliage_color(part_type: int, base_color: Color, season_id: String) -> Color:
	# CONE (sapin) suit sa propre table, jamais SEASON_FOLIAGE_TINT/l'automne
	# - le sapin ne perd pas ses aiguilles/ne rougit pas comme les feuillus.
	if part_type == PartType.CONE:
		var cone_tint: Color = SEASON_CONE_TINT.get(season_id, Color(1.0, 1.0, 1.0))
		return base_color * cone_tint
	# L'automne n'est pas dans SEASON_FOLIAGE_TINT (voir sa declaration) -
	# traite a part ci-dessous via un lerp vers du rouge/orange.
	if season_id == "automne":
		return base_color.lerp(AUTOMNE_LEAF_TARGET, AUTOMNE_LEAF_STRENGTH)
	var tint: Color = SEASON_FOLIAGE_TINT.get(season_id, Color(1.0, 1.0, 1.0, 1.0))
	return base_color * tint


## Rend invisibles toutes les instances de mesh partagees appartenant a
## "tree" (racines/tronc/branches/feuillage), SANS toucher aux instances
## des AUTRES arbres (chaque instance est mise a l'echelle zero
## individuellement via son propre index, pas de reconstruction du tableau
## complet). A appeler AVANT tree.queue_free() quand un arbre est coupe
## (voir Dwarf.gd/_process_work, action "couper") - sinon le tronc/les
## branches/le feuillage de l'arbre coupe resteraient visibles pour
## toujours (ils ne sont plus des enfants du noeud "tree" depuis le passage
## aux MultiMesh partages, donc tree.queue_free() seul ne les affecte plus
## du tout).
func hide_tree_visuals(tree: Node3D) -> void:
	if not tree.has_meta("visual_refs"):
		return
	var refs: Array = tree.get_meta("visual_refs")
	var zero_xform := Transform3D(Basis().scaled(Vector3.ONE * HIDDEN_INSTANCE_SCALE), Vector3.ZERO)
	for ref in refs:
		var part_type: int = ref[0]
		var idx: int = ref[1]
		_mmi[part_type].multimesh.set_instance_transform(idx, zero_xform)
		# Retient l'etat "cache" ici aussi, sinon _spawn_new_tree_and_apply
		# ferait REAPPARAITRE cet arbre coupe au prochain agrandissement du
		# MultiMesh (voir doc de _live_xforms).
		_live_xforms[part_type][idx] = zero_xform


## Appele par CameraRig a chaque changement de niveau de vue (meme moment
## que VoxelWorld.set_view_level), en plus de ce dernier, jamais a sa place.
## Un arbre est cache des que le BLOC de sol sur lequel il repose (indice
## entier, tree.position.y - 1.0, meme convention que tree.position.y =
## get_top_block_y+1.0 dans _ground_y_at) est strictement au-dessus du
## niveau de vue - exactement la meme regle que VoxelWorld ("pos.y >
## view_level" = cache). Pour reafficher un arbre, on restaure sa transform
## d'ORIGINE (pas de recalcul) depuis _pending_xforms : ce tableau, rempli
## une seule fois par _record_part/_apply_pending_instances, reste en
## memoire pour toute la duree de vie de Forest.gd (jamais vide), donc
## aucun stockage supplementaire n'est necessaire. Un arbre coupe
## (hide_tree_visuals suivi de tree.queue_free(), voir Dwarf.gd) est libere
## immediatement et ne fait donc plus partie du groupe "trees" - pas de
## risque de le "reafficher" par erreur ici.
## Les fruits (seuls enfants restants de "tree", noms "Fruit_*", pas geres
## par le MultiMesh partage) sont bascules directement via leur propre
## "visible". update_view_level() doit connaitre l'etat hiver (voir
## set_winter_fruits_hidden) pour rester correct quel que soit qui l'appelle
## et dans quel ordre (changement de niveau de vue OU de saison) - sinon un
## appel a update_view_level() apres que SeasonSystem.gd ait cache les
## fruits pour l'hiver les reafficherait a tort.
var _winter_fruits_hidden: bool = false

func set_winter_fruits_hidden(hidden: bool) -> void:
	_winter_fruits_hidden = hidden


func update_view_level(level: int) -> void:
	var zero_xform := Transform3D(Basis().scaled(Vector3.ONE * HIDDEN_INSTANCE_SCALE), Vector3.ZERO)
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
					_live_xforms[part_type][idx] = zero_xform
				else:
					_mmi[part_type].multimesh.set_instance_transform(idx, _pending_xforms[part_type][idx])
					_live_xforms[part_type][idx] = _pending_xforms[part_type][idx]
		for child in tree.get_children():
			if (child.name as String).begins_with("Fruit_"):
				child.visible = not hidden and not _winter_fruits_hidden
