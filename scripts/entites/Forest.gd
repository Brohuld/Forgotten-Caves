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
## que les autres, plus des fruits (ForestGeometryBuilder.build_fruits) recoltables via l'action
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
##
## Construction geometrique (racines/tronc/branches/feuillage/fruits)
## extraite dans ForestGeometryBuilder.gd (revue de code C20, 2026-07-11) -
## fonctions statiques, Forest.gd garde la propriete de tout l'etat partage
## et passe un Callable (_record_part) pour l'enregistrement des instances.

const TreeSpecies := preload("res://scripts/data/materiaux/types/bois/TreeSpecies.gd")
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")
const HoverableScript := preload("res://scripts/systemes/Hoverable.gd")
const ViewLevelIndexScript := preload("res://scripts/systemes/ViewLevelIndex.gd")
const ForestGeometryBuilderScript := preload("res://scripts/entites/ForestGeometryBuilder.gd")

## Rayon/hauteur du collider de detection souris (voir Hoverable.gd) -
## approximatif (englobe tronc + feuillage), pas besoin d'etre pixel-parfait :
## l'important est qu'il ne deborde pas sur les cases voisines (voir
## PointerResolver, feedback Francois 2026-07-10 sur les tas pres d'une
## berge). Herite de tree.scale (variation par instance/espece) puisque le
## collider est un enfant direct de "tree".
const TREE_HOVER_RADIUS := 0.9

## Reference a VoxelWorld pour rejeter les positions d'eau (voir
## _pick_dry_position) a la generation initiale ET a la repousse
## (_spawn_new_tree_and_apply reutilise _spawn_tree donc en profite
## automatiquement).
@onready var voxel_world: Node3D = %VoxelWorld

## Lit directement VoxelWorld.WIDTH/DEPTH/HEIGHT au lieu d'un nombre
## duplique en dur - desynchronisation avec la taille reelle de la carte
## structurellement impossible. WIDTH/DEPTH ne sont plus des const cote
## VoxelWorld (reglables depuis StartMenu.gd) - grid_width/grid_depth ne
## peuvent donc plus l'etre non plus ici (mais restent figes une fois lus,
## la taille de carte ne change jamais en cours de partie).
var grid_width: int = VoxelWorldScript.WIDTH
var grid_depth: int = VoxelWorldScript.DEPTH
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
## (roughness=1.0, pas SHADING_MODE_UNSHADED - voir ForestGeometryBuilder.make_mmi) : Godot
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

## Index niveau de sol -> arbres a ce niveau (int -> Array[Node3D]), rempli
## dans _spawn_tree (generation initiale ET regrowth via
## _spawn_new_tree_and_apply, qui reutilise _spawn_tree - un seul point de
## remplissage suffit donc pour les deux). Le bloc de sol d'un arbre ne
## change jamais apres sa creation (tree.position fixe). Permet a
## update_view_level de ne toucher QUE les arbres dont le niveau de sol se
## trouve entre l'ancien et le nouveau niveau de vue, au lieu de rebalayer
## TOUS les arbres de la carte a chaque cran de molette (voir
## _apply_view_level_delta, perf 2026-07-08). Un arbre coupe (queue_free) est
## simplement ignore a la lecture via is_instance_valid - pas besoin de le
## retirer activement du bucket.
var _level_buckets: Dictionary = {}  # int -> Array[Node3D]
## -1 = pas encore initialise. Voir doc de update_view_level : le tout
## premier appel fait un scan complet classique, tous les suivants passent
## par _apply_view_level_delta.
var _last_view_level: int = -1

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
## maillage "unite" (rayon/taille=1, voir ForestGeometryBuilder.make_*_mesh)
## et un seul materiau a couleur-par-instance (meme principe que les pepites
## de filons de VoxelWorld.gd - use_colors=true + vertex_color_use_as_albedo=true).
func _build_shared_meshes() -> void:
	var G := ForestGeometryBuilderScript
	_mmi[PartType.ROOTS] = G.make_mmi(G.make_cylinder_mesh(0.16, 0.30, 1.0, TREE_CYLINDER_RADIAL_SEGMENTS), self)
	_mmi[PartType.TRUNK] = G.make_mmi(G.make_cylinder_mesh(0.09, 0.16, 1.0, TREE_CYLINDER_RADIAL_SEGMENTS), self)
	_mmi[PartType.BRANCH] = G.make_mmi(G.make_cylinder_mesh(0.03, 0.06, 1.0, TREE_CYLINDER_RADIAL_SEGMENTS), self)
	_mmi[PartType.CONE] = G.make_mmi(G.make_cylinder_mesh(0.0, 1.0, 1.0, TREE_CYLINDER_RADIAL_SEGMENTS), self)
	_mmi[PartType.BLOB] = G.make_mmi(G.make_sphere_mesh(1.0, TREE_SPHERE_RADIAL_SEGMENTS, TREE_SPHERE_RINGS), self)
	_mmi[PartType.LEAF] = G.make_mmi(G.make_box_mesh(Vector3.ONE), self)
	# Transparence activee UNIQUEMENT sur les materiaux BLOB/LEAF (chacun un
	# materiau distinct, voir ForestGeometryBuilder.make_mmi) - jamais sur CONE (sapin) ni sur les
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


## Tire une position au hasard en rejetant l'eau (voir VoxelWorld.is_water)
## - essais bornes par securite, repli sur la derniere position tiree si
## vraiment aucune case seche n'est trouvee (tres improbable, l'eau ne
## couvre qu'une petite partie de la carte).
func _pick_dry_position() -> Vector2:
	# Flux GameRandom dedie ("arbres_geometrie") plutot que le RNG global -
	# reproductibilite par graine isolee des autres systemes (corrige I86
	# 2026-07-11, voir doc GameRandom.gd). Distinct du flux "arbres_especes"
	# deja utilise par TreeSpecies.random_species()/random_fruit_species().
	var rng: RandomNumberGenerator = GameRandom.get_rng("arbres_geometrie")
	var x := rng.randf_range(2.0, float(grid_width - 2))
	var z := rng.randf_range(2.0, float(grid_depth - 2))
	var guard := 0
	while voxel_world != null and voxel_world.is_water(int(x), int(z)) and guard < 20:
		x = rng.randf_range(2.0, float(grid_width - 2))
		z = rng.randf_range(2.0, float(grid_depth - 2))
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
	var rng: RandomNumberGenerator = GameRandom.get_rng("arbres_geometrie")
	var scale_jitter: float = rng.randf_range(0.85, 1.15) * size_multiplier * species.get("echelle_base", 1.0)
	var tint_jitter: float = rng.randf_range(0.9, 1.1)

	var tree := Node3D.new()
	tree.name = "Tree_%d" % get_child_count()
	# Hauteur reelle de la colonne (sommet+1), pas ground_level fixe - sinon
	# un arbre plante sur une colline apparaitrait enfonce dans le sol.
	tree.position = Vector3(x, _ground_y_at(x, z), z)
	tree.rotation.y = rng.randf_range(0.0, TAU)
	tree.scale = Vector3.ONE * scale_jitter
	tree.add_to_group("trees")
	tree.set_meta("wood_resource", species["wood_resource"])
	tree.set_meta("species_name", species["nom"])
	tree.set_meta("hover_kind", "gatherable")  # voir EntityDescriptions.describe_by_kind
	add_child(tree)

	# Collider de detection souris (voir Hoverable.gd) - englobe tronc +
	# feuillage, centre a mi-hauteur de l'espece. Herite de tree.scale.
	var hover_shape := CylinderShape3D.new()
	hover_shape.radius = TREE_HOVER_RADIUS
	hover_shape.height = species.get("hauteur", 3.0)
	HoverableScript.attach(tree, hover_shape, Vector3(0, hover_shape.height * 0.5, 0))

	# Index par niveau de sol via ViewLevelIndex.gd (voir doc de
	# _level_buckets) - couvre aussi le regrowth (_maybe_regrow_tree ->
	# _spawn_new_tree_and_apply -> _spawn_tree).
	var _ground_lvl: int = int(tree.position.y - 1.0)
	ViewLevelIndexScript.register(_level_buckets, tree, _ground_lvl)

	# Transform de reference pour toute la geometrie de cet arbre, lu UNE
	# fois ici (tree est deja dans l'arbre de scene, position/rotation/scale
	# deja appliques ci-dessus) - chaque piece compose ensuite ses propres
	# decalages locaux par-dessus via multiplication de Transform3D, sans
	# jamais creer le moindre noeud Godot.
	var tree_xform: Transform3D = tree.global_transform

	var trunk_height: float = species["hauteur"]
	var refs: Array = []
	var record_fn := Callable(self, "_record_part")
	var G := ForestGeometryBuilderScript

	G.build_roots(refs, tree_xform, species, tint_jitter, PartType.ROOTS, record_fn)
	var trunk_visual_height: float = G.build_trunk(refs, tree_xform, species, trunk_height, tint_jitter, PartType.TRUNK, record_fn)
	G.build_branches(refs, tree_xform, species, trunk_height, tint_jitter, PartType.BRANCH, PartType.LEAF, record_fn)
	# build_foliage renvoie la liste des blobs de feuillage reellement crees
	# (position + rayon), pour que build_fruits puisse ancrer chaque fruit a
	# la surface d'un blob existant plutot qu'a une position theorique qui
	# pourrait tomber hors du feuillage reel (arrangement des blobs
	# asymetrique/aleatoire).
	var blob_data: Array = G.build_foliage(refs, tree_xform, species, trunk_height, trunk_visual_height, tint_jitter, PartType.CONE, PartType.BLOB, PartType.LEAF, record_fn)

	_spawn_fruits_if_applicable(tree, species, trunk_height, blob_data)

	# refs liste (type, index) pour chaque piece de CET arbre dans les
	# MultiMesh partages (voir hide_tree_visuals/update_view_level) - aucun
	# noeud temporaire a recolter/detruire, chaque build_* de
	# ForestGeometryBuilder.gd a deja enregistre ses instances directement
	# via record_fn (-> _record_part).
	tree.set_meta("visual_refs", refs)


## Arbre fruitier : ajoute les fruits + rend l'arbre recoltable via l'action
## "Cueillir" (groupe/metadonnees partages avec BerryBush.gd, voir
## Dwarf.gd/_complete_task pour la logique commune). Les fruits restent des
## noeuds individuels (voir ForestGeometryBuilder.build_fruits) - pas touches
## par la conversion MultiMesh, recoltes un par un a la cueillette. Ne fait
## rien si l'espece n'est pas fruitiere (pas de cle "fruit_resource").
func _spawn_fruits_if_applicable(tree: Node3D, species: Dictionary, trunk_height: float, blob_data: Array) -> void:
	if not species.has("fruit_resource"):
		return
	var fruit_count: int = species.get("fruit_count", 5)
	tree.add_to_group("cueillette")
	tree.set_meta("fruit_resource", species["fruit_resource"])
	tree.set_meta("fruits_left", fruit_count)
	ForestGeometryBuilderScript.build_fruits(tree, species, trunk_height, fruit_count, blob_data, TREE_SPHERE_RADIAL_SEGMENTS, TREE_SPHERE_RINGS)


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


## Perf (2026-07-08) : le tout premier appel fait un scan complet classique
## (_apply_view_level_full, identique au comportement d'avant l'indexation).
## Tous les appels suivants (donc chaque cran de molette) passent par
## _apply_view_level_delta, qui ne touche que les arbres dont le niveau de
## sol se trouve entre l'ancien et le nouveau niveau de vue via
## _level_buckets, au lieu de rebalayer tout le groupe "trees".
func update_view_level(level: int) -> void:
	if _last_view_level == -1:
		_apply_view_level_full(level)
	else:
		_apply_view_level_delta(_last_view_level, level)
	_last_view_level = level


## Bascule un seul arbre cache/visible selon "hidden" (facteur commun entre
## le scan complet et le scan incremental).
func _apply_tree_visibility(tree: Node3D, hidden: bool, zero_xform: Transform3D) -> void:
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
	# Le collider de survol (voir Hoverable.gd) doit suivre la meme regle que
	# le visuel MultiMesh ci-dessus - sinon un arbre cache par la coupe
	# resterait detectable par le survol/ciblage.
	HoverableScript.set_enabled(tree, not hidden)


## Scan complet (tous les arbres du groupe "trees") - utilise uniquement pour
## le tout premier appel de update_view_level (voir sa doc). Regle de seuil
## et parcours factorises dans ViewLevelIndex.gd (voir sa doc) - seule la
## bascule visuelle (_apply_tree_visibility) reste specifique a ce fichier.
func _apply_view_level_full(level: int) -> void:
	var zero_xform := Transform3D(Basis().scaled(Vector3.ONE * HIDDEN_INSTANCE_SCALE), Vector3.ZERO)
	var trees: Array = get_tree().get_nodes_in_group("trees")
	var ground_y_fn := func(tree): return int(tree.position.y - 1.0)
	var apply_fn := func(tree, hidden): _apply_tree_visibility(tree, hidden, zero_xform)
	ViewLevelIndexScript.full_scan(trees, level, ground_y_fn, apply_fn)


## Scan incremental : ne touche que les arbres dont le niveau de sol se
## trouve entre l'ancien et le nouveau niveau de vue (voir doc de
## _level_buckets et de ViewLevelIndex.delta_scan).
func _apply_view_level_delta(old_level: int, new_level: int) -> void:
	var zero_xform := Transform3D(Basis().scaled(Vector3.ONE * HIDDEN_INSTANCE_SCALE), Vector3.ZERO)
	var apply_fn := func(tree, hidden):
		if is_instance_valid(tree):
			_apply_tree_visibility(tree, hidden, zero_xform)
	ViewLevelIndexScript.delta_scan(_level_buckets, old_level, new_level, apply_fn)
