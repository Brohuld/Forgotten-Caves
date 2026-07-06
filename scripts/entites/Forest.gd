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
## 2026-07-05 (revue de code, item F010) : uniquement pour le garde-fou de
## _ready() ci-dessous (grid_width/grid_depth dupliques ci-dessous).
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")

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

## 2026-07-06 (regression "tous les troncs ont disparu apres avoir coupe UN
## arbre") : hide_tree_visuals()/update_view_level() cachaient une instance en
## mettant son echelle a Vector3.ZERO PILE (Basis totalement degenere,
## determinant=0). Avec un materiau a eclairage REEL (roughness=1.0, voir
## _make_mmi - pas SHADING_MODE_UNSHADED), Godot calcule une matrice de
## normales par instance a partir de sa transform ; une base totalement
## degeneree produit un resultat non-inversible (NaN/Inf) qui peut corrompre
## le rendu de TOUT le lot d'instances du MultiMesh concerne (pas seulement
## celle qu'on voulait cacher) - exactement le symptome observe : couper un
## chene a fait disparaitre TOUS les troncs/racines/branches/feuillage BLOB+LEAF
## de la carte (tous les part_types que ce chene utilisait), mais PAS les
## cones (sapins, jamais touches puisque ce chene n'en a pas) ni les fruits
## (noeuds independants, pas dans un MultiMesh). Fix : une echelle
## MINUSCULE mais JAMAIS EXACTEMENT ZERO (base non-degeneree, determinant
## non-nul) - invisible a l'oeil, mais n'expose plus Godot au calcul sur une
## matrice singuliere.
const HIDDEN_INSTANCE_SCALE := 0.0001

## Types de piece consideres comme "feuillage" - seuls ceux-la sont reteints
## a chaque changement de saison (voir apply_season_tint), exactement comme
## avant (le tronc/les racines/les branches/les fruits ne changent jamais de
## couleur avec la saison).
const _FOLIAGE_PART_TYPES := [PartType.CONE, PartType.BLOB, PartType.LEAF]

var _mmi: Dictionary = {}              # PartType -> MultiMeshInstance3D
var _pending_xforms: Dictionary = {}   # PartType -> Array[Transform3D] (transform D'ORIGINE au moment du spawn, jamais modifie ensuite)
var _pending_colors: Dictionary = {}   # PartType -> Array[Color]
## 2026-07-06 (regression "repousse d'arbre efface les autres arbres") :
## contrairement a _pending_xforms (toujours la transform D'ORIGINE), ce
## tableau retient la transform REELLEMENT AFFICHEE en ce moment pour chaque
## instance (visible normalement, cachee via HIDDEN_INSTANCE_SCALE si l'arbre
## a ete coupe, ou cachee/restauree selon le niveau de vue - voir
## hide_tree_visuals/update_view_level, qui ecrivent desormais ICI en plus du
## MultiMesh lui-meme). Necessaire car Godot reinitialise TOUTES les
## instances existantes d'un MultiMesh a leur valeur par defaut des que son
## "instance_count" est agrandi (comportement documente du moteur, confirme
## sur le tracker officiel, issue #76180) - _spawn_new_tree_and_apply doit
## donc reappliquer explicitement CET etat (pas _pending_xforms, qui ferait
## reapparaitre a tort un arbre coupe) sur TOUTES les instances a chaque fois
## qu'un agrandissement se produit, pas seulement sur les nouvelles.
var _live_xforms: Dictionary = {}      # PartType -> Array[Transform3D]
## Meme principe que _live_xforms, mais pour la couleur actuellement affichee
## (peut differer de _pending_colors a cause de la teinte de saison sur le
## feuillage - voir apply_season_tint/_tinted_foliage_color).
var _live_colors: Dictionary = {}      # PartType -> Array[Color]
## Derniere saison appliquee (voir apply_season_tint) - retenue ici pour que
## _spawn_new_tree_and_apply puisse recalculer la bonne teinte de feuillage
## apres un agrandissement, sans dependre de SeasonSystem.gd.
var _current_season_id: String = "ete"
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
# 2026-07-05 (cycle des saisons, demande explicite de Francois - automne :
# "les feuilles des arbres prennent une teinte rouge en plus de la couleur de
# base - SAUF pour les sapins" ; hiver : "les arbres perdent presque toutes
# leurs feuilles, SAUF les sapins" ; printemps : "TOUS les arbres ont des
# feuilles plus claires") : deux tables desormais, une pour BLOB/LEAF (chene/
# bouleau/arbres fruitiers - tous "sauf les sapins") et une pour CONE (sapin
# uniquement) qui reste vert toute l'annee sauf au printemps (seule saison ou
# "tous les arbres" sont concernes, sapin inclus). Le canal alpha de
# SEASON_FOLIAGE_TINT["hiver"] (0.12, tres faible) fait "tomber les feuilles"
# via la transparence du materiau (voir _build_shared_meshes, transparency
# active UNIQUEMENT sur BLOB/LEAF) plutot qu'en cachant des instances via leur
# transform - ce qui aurait entre en conflit avec update_view_level()/
# hide_tree_visuals(), qui remettent en permanence les transforms d'origine
# independamment de la saison (voir leurs docstrings).
const SEASON_FOLIAGE_TINT := {  # BLOB + LEAF (chene/bouleau/arbres fruitiers)
	"ete": Color(1.0, 1.0, 1.0, 1.0),
	"hiver": Color(0.55, 0.5, 0.48, 0.12),
	"printemps": Color(1.15, 1.2, 1.05, 1.0),
}
# 2026-07-06 (Francois : "les arbres... ne sont pas assez rouges en automne,
# surtout les chenes") : une teinte MULTIPLICATIVE (couleur * facteur) ne peut
# pas faire dominer le rouge quand la couleur de base est deja tres sombre et
# tres verte (chene : Color(0.04, 0.16, 0.06) - meme multipliee par un grand
# facteur rouge, le canal vert de depart reste plus fort). L'automne utilise
# donc un MELANGE (lerp) vers une couleur cible rouge/orange, qui garantit un
# resultat rouge quelle que soit la couleur de depart - voir apply_season_tint.
const AUTOMNE_LEAF_TARGET := Color(0.55, 0.10, 0.05)
const AUTOMNE_LEAF_STRENGTH := 0.65
const SEASON_CONE_TINT := {  # CONE (sapin uniquement) - jamais rougi/transparent
	"ete": Color(1.0, 1.0, 1.0),
	"automne": Color(1.0, 1.0, 1.0),
	"hiver": Color(1.0, 1.0, 1.0),
	"printemps": Color(1.08, 1.12, 1.05),
}


func _ready() -> void:
	# 2026-07-05 (revue de code, item F010) : grid_width/grid_depth/ground_level
	# dupliques en dur (aucune garde-fou automatique auparavant) - avertissement
	# si desynchronise de VoxelWorld.gd, sans changer le comportement.
	if grid_width != VoxelWorldScript.WIDTH or grid_depth != VoxelWorldScript.DEPTH or not is_equal_approx(ground_level, float(VoxelWorldScript.HEIGHT)):
		push_warning("Forest.grid_width/grid_depth/ground_level (%d/%d/%.1f) desynchronise de VoxelWorld (%d/%d/%d)" % [grid_width, grid_depth, ground_level, VoxelWorldScript.WIDTH, VoxelWorldScript.DEPTH, VoxelWorldScript.HEIGHT])
	# 2026-07-05 (correctif revue de code C3, meme cause que C2/C4-C6/I9) :
	# randomize() retire - reinitialisait le generateur aleatoire global de
	# facon non deterministe, APRES que VoxelWorld._ready() ait deja fixe sa
	# graine (seed(active_seed)) pour toute la carte. Forest.gd est declare
	# apres VoxelWorld dans Main.tscn : le generateur global est deja
	# correctement initialise ici, pas besoin de le reinitialiser - c'est
	# justement ce qui rend desormais la position des arbres reproductible
	# par graine (voir menu de demarrage/StartMenu.gd).
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


## Fait pousser un seul arbre APRES la generation initiale.
## 2026-07-06 (regression "repousse d'arbre efface les autres arbres",
## corrigee) : la version precedente de cette fonction supposait qu'agrandir
## "multimesh.instance_count" pour loger les nouvelles instances de CE nouvel
## arbre n'affectait jamais les instances deja existantes des AUTRES arbres.
## FAUX - confirme sur le tracker officiel de Godot (issue #76180) : chaque
## fois que "instance_count" est agrandi, Godot reinitialise TOUTES les
## instances existantes de ce MultiMesh a leur valeur par defaut (transform
## identite, couleur blanche). Symptome observe : couper un arbre declenchait
## une repousse ~20s plus tard (_maybe_regrow_tree), qui agrandissait au
## besoin les MultiMesh racines/tronc/branches/cones/feuillage - UNIQUEMENT
## ceux dont l'espece du nouvel arbre a besoin (ex : un sapin n'ajoute rien a
## BLOB/LEAF) - effacant instantanement TOUS les troncs/racines/branches (ou
## cones) de la carte entiere pour les types agrandis, alors que les types NON
## agrandis restaient intacts (feuillage boules/petites feuilles, si le nouvel
## arbre etait un sapin).
## Fix : des qu'un agrandissement est necessaire pour un type de piece donne,
## on reapplique EXPLICITEMENT l'etat REEL actuel de TOUTES ses instances
## (pas seulement celles du nouvel arbre) a partir de _live_xforms/
## _live_colors - qui retiennent en permanence, pour chaque instance, sa
## transform/couleur veritablement affichee en ce moment (visible normalement,
## cachee par une coupe, ou cachee/restauree par le niveau de vue - voir
## hide_tree_visuals/update_view_level, qui ecrivent desormais aussi dans ces
## deux tableaux). Si aucun agrandissement n'est necessaire pour un type
## donne, on se contente comme avant de n'ecrire QUE les nouvelles instances
## (chemin rapide, aucun risque - Godot ne touche a rien tant que
## "instance_count" ne change pas).
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
	# 2026-07-05 (cycle des saisons, hiver : "les arbres perdent presque toutes
	# leurs feuilles, sauf les sapins") : transparence activee UNIQUEMENT sur
	# les materiaux BLOB/LEAF (chacun un materiau distinct, voir _make_mmi) -
	# jamais sur CONE (sapin) ni sur les autres pieces. L'alpha de la teinte
	# hiver (SEASON_FOLIAGE_TINT, tres faible) rendra ces feuilles quasiment
	# invisibles sans toucher a leur transform - voir sa doc plus haut pour la
	# raison (conflit evite avec update_view_level()/hide_tree_visuals()).
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
	# 2026-07-05 (Francois : "augmenter de 20% les chenes en hauteur et
	# largeur") : echelle_base est un multiplicateur PAR ESPECE (1.0 si absent,
	# voir TreeSpecies.gd) applique en plus - grandit tronc/feuilles/branches/
	# racines proportionnellement pour cette espece uniquement.
	var scale_jitter: float = randf_range(0.85, 1.15) * size_multiplier * species.get("echelle_base", 1.0)
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
	# 2026-07-05 (signale par Francois : fruits mal repartis / suspendus dans
	# le vide) : _build_foliage renvoie desormais la liste des blobs de
	# feuillage reellement crees (position + rayon), pour que _build_fruits
	# puisse ancrer chaque fruit a la surface d'un blob existant plutot qu'a
	# une position theorique qui pouvait tomber hors du feuillage reel
	# (arrangement des blobs asymetrique/aleatoire).
	var blob_data: Array = _build_foliage(tree, species, trunk_height, trunk_visual_height, tint_jitter)

	_spawn_fruits_if_applicable(tree, species, trunk_height, blob_data)

	# Sprint 34 : toute la geometrie decorative (racines/tronc/branches/
	# feuillage) vient d'etre construite comme des noeuds TEMPORAIRES sous
	# "tree" (fonctions ci-dessous inchangees) - on recolte maintenant leur
	# global_transform + couleur + taille pour les enregistrer dans les
	# MultiMeshInstance3D partages, puis on les supprime (voir
	# _harvest_and_clear). Seuls les fruits restent de vrais enfants de "tree".
	_harvest_and_clear(tree)


## 2026-07-06 (revue de code, paquet E, I57) : extrait de _spawn_tree() -
## Sprint 24ter, arbre fruitier - ajoute les fruits + rend l'arbre recoltable
## via l'action "Cueillir" (groupe/metadonnees partages avec BerryBush.gd,
## voir Dwarf.gd/_complete_task pour la logique commune). Les fruits restent
## des noeuds individuels (voir _build_fruits) - pas touches par la
## conversion MultiMesh, recoltes un par un a la cueillette. Ne fait rien si
## l'espece n'est pas fruitiere (pas de cle "fruit_resource").
func _spawn_fruits_if_applicable(tree: Node3D, species: Dictionary, trunk_height: float, blob_data: Array) -> void:
	if not species.has("fruit_resource"):
		return
	var fruit_count: int = species.get("fruit_count", 5)
	tree.add_to_group("cueillette")
	tree.set_meta("fruit_resource", species["fruit_resource"])
	tree.set_meta("fruits_left", fruit_count)
	_build_fruits(tree, species, trunk_height, fruit_count, blob_data)


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
		# 2026-07-05 (Francois : "diminuer l'espace entre la racine des sapins
		# et le bas des feuilles") : fraction de tronc visible reduite (etait
		# 0.25) - le feuillage conique demarre juste au-dessus (voir
		# _build_foliage, start_y = 0.22 + trunk_visual_height), donc un tronc
		# visuel plus court rapproche le bas des feuilles des racines.
		visual_height = max(trunk_height * 0.12, 0.18)

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
## Renvoie la liste des blobs de feuillage crees (Array de {"position":
## Vector3, "radius": float}, coordonnees locales a "tree") - vide pour le
## feuillage conique (sapin, jamais un arbre fruitier). Utilise par
## _build_fruits pour ancrer les fruits a de vrais blobs (voir plus bas).
func _build_foliage(tree: Node3D, species: Dictionary, trunk_height: float, trunk_visual_height: float, tint: float) -> Array:
	var top_y: float = 0.22 + trunk_height
	match species.get("forme", "touffu"):
		"conique":
			# Sprint 24quinquies : le feuillage part du sommet du (court) tronc
			# visuel, pas du sommet de la hauteur totale de l'arbre - il occupe
			# donc presque toute la silhouette, comme un vrai sapin.
			_build_foliage_conique(tree, species, 0.22 + trunk_visual_height, top_y, tint)
			return []
		"fin":
			return _build_foliage_fin(tree, species, top_y, tint)
		_:
			return _build_foliage_touffu(tree, species, top_y, tint)


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
func _build_foliage_touffu(tree: Node3D, species: Dictionary, top_y: float, tint: float) -> Array:
	# 2026-07-05 (Francois : "augmente la taille du feuillage" du chene) :
	# facteur par espece (voir TreeSpecies.gd/feuillage_echelle, 1.0 par defaut
	# donc AUCUN changement pour les arbres fruitiers, qui partagent cette
	# meme fonction) applique aux rayons des blobs et a leur etalement
	# horizontal (xz_spread) - pas a la plage verticale (y_min/y_max), qui
	# reste fixee par rapport a "top_y" (sommet du tronc, inchange).
	var echelle: float = species.get("feuillage_echelle", 1.0)
	return _build_blob_foliage(tree, species, top_y, tint, 4, 6, 0.38 * echelle, 0.55 * echelle, 0.26 * echelle, 0.05, 0.65, 7, 10)


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
func _build_foliage_fin(tree: Node3D, species: Dictionary, top_y: float, tint: float) -> Array:
	return _build_blob_foliage(tree, species, top_y, tint, 3, 5, 0.26, 0.38, 0.22, 0.0, 0.55, 6, 8)


## 2026-07-05 (revue de code, item F022) : logique commune a
## _build_foliage_touffu (chene/arbres fruitiers) et _build_foliage_fin
## (bouleau) - meme construction (blobs spheriques + grappes de feuilles a
## leur surface), seuls les nombres/tailles/plages different par espece.
## Meme comportement qu'avant.
func _build_blob_foliage(tree: Node3D, species: Dictionary, top_y: float, tint: float,
		cluster_count_min: int, cluster_count_max: int,
		radius_min: float, radius_max: float,
		xz_spread: float, y_min: float, y_max: float,
		leaf_count_min: int, leaf_count_max: int) -> Array:
	var colors: Array = species["feuillage_colors"]
	var cluster_count: int = randi_range(cluster_count_min, cluster_count_max)
	var blob_data: Array = []
	for i in range(cluster_count):
		var blob := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = randf_range(radius_min, radius_max)
		mesh.height = mesh.radius * 2.0
		blob.mesh = mesh
		blob.position = Vector3(
			randf_range(-xz_spread, xz_spread),
			top_y + randf_range(y_min, y_max),
			randf_range(-xz_spread, xz_spread)
		)
		var blob_color: Color = colors[randi_range(0, colors.size() - 1)] * tint
		blob.set_surface_override_material(0, _flat_material(blob_color))
		_tag_part(blob, PartType.BLOB, blob_color, Vector3.ONE * mesh.radius)
		tree.add_child(blob)
		_build_leaf_cluster(blob, colors, tint, randi_range(leaf_count_min, leaf_count_max), mesh.radius * 0.8)
		blob_data.append({"position": blob.position, "radius": mesh.radius})
	return blob_data


## Sprint 24ter : fruits de l'arbre (arbres fruitiers uniquement, voir
## _spawn_tree) - petites spheres colorees dispersees pres du feuillage,
## nommees "Fruit_%d" (0..fruit_count-1) pour pouvoir en retirer une a la
## fois a la cueillette (voir Dwarf.gd/_complete_task, meme convention que
## BerryBush.gd/Berry_%d). Sprint 34 : PAS convertis en MultiMesh (contrairement
## a tout le reste de l'arbre) - ils doivent pouvoir disparaitre un par un a
## la cueillette, ce qu'un MultiMesh partage ne permet pas facilement ; leur
## nombre reste de toute facon tres faible (5-6 par arbre fruitier).
## 2026-07-05 (4e correction, meme jour - Francois : "la repartition
## reguliere autour de l'arbre n'a pas marche (ou est cachee)" + "certains
## fruits sont trop loin des feuilles et suspendus dans le vide") : la
## couronne theorique (distance fixe 0.42-0.62 autour du tronc) ne suit pas
## la forme reelle du feuillage, qui est un amas de blobs places de facon
## asymetrique/aleatoire (voir _build_blob_foliage) - certaines directions
## n'ont pas de feuillage a cette distance (fruit flottant), d'autres en ont
## beaucoup (fruits caches derriere). Chaque fruit est desormais ancre a la
## surface d'un blob de feuillage REELLEMENT cree (choisi au hasard parmi
## "blob_data", position/rayon renvoyes par _build_foliage), avec une petite
## marge (0.85-1.05x le rayon) pour rester visible en depassant un peu.
func _build_fruits(tree: Node3D, species: Dictionary, trunk_height: float, fruit_count: int, blob_data: Array) -> void:
	var top_y: float = 0.22 + trunk_height
	var mat := _flat_material(species["fruit_color"])
	var fruit_radius: float = species.get("fruit_radius", 0.13)
	# 2026-07-05 (5e correction, meme jour - Francois : "quasiment aucun fruit
	# d'un cote") : le choix d'un blob au hasard PAR fruit (randi_range) pouvait,
	# avec seulement 4-6 blobs, en tirer certains 4-5 fois et d'autres jamais -
	# tous les fruits se retrouvaient alors regroupes sur 1-2 blobs voisins,
	# donc du meme cote de l'arbre. Repartition en "tourniquet" (chaque blob
	# melange puis pris a son tour) pour garantir que TOUS les blobs recoivent
	# un nombre de fruits equilibre, quel que soit fruit_count.
	var blobs_shuffled: Array = blob_data.duplicate()
	blobs_shuffled.shuffle()
	for i in range(fruit_count):
		var fruit := MeshInstance3D.new()
		fruit.name = "Fruit_%d" % i
		var mesh := SphereMesh.new()
		mesh.radius = fruit_radius
		mesh.height = fruit_radius * 2.0
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
			# 2026-07-05 (Francois n'est pas d'accord avec l'explication
			# "occlusion normale" donnee precedemment - il veut des fruits
			# tout autour de CHAQUE blob, a une hauteur aleatoire par rapport
			# au blob, pas juste biaises vers le bas) : elevation desormais
			# sur toute la sphere (-90..+90 degres), pas seulement -70..+25.
			var az := randf_range(0.0, TAU)
			var elev := randf_range(deg_to_rad(-90.0), deg_to_rad(90.0))
			var dir := Vector3(cos(elev) * cos(az), sin(elev), cos(elev) * sin(az))
			var dist := blob_radius * randf_range(0.85, 1.05)
			fruit.position = blob_pos + dir * dist
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
func _tag_part(node: MeshInstance3D, part_type: int, color: Color, part_scale: Vector3) -> void:
	node.set_meta("part_type", part_type)
	node.set_meta("part_color", color)
	node.set_meta("part_scale", part_scale)


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
		# 2026-07-06 (regression "repousse d'arbre efface les autres arbres") :
		# _live_xforms/_live_colors retiennent l'etat REELLEMENT affiche (ici,
		# celui d'un arbre qui vient d'etre plante : visible, teinte de saison
		# courante deja appliquee si feuillage) - voir la doc de _live_xforms.
		_live_xforms[part_type].append(xform)
		if part_type in _FOLIAGE_PART_TYPES:
			_live_colors[part_type].append(_tinted_foliage_color(part_type, color, _current_season_id))
		else:
			_live_colors[part_type].append(color)
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
	_current_season_id = season_id
	for part_type in _FOLIAGE_PART_TYPES:
		var mmi: MultiMeshInstance3D = _mmi[part_type]
		var base_colors: Array = _foliage_base_colors[part_type]
		for i in range(base_colors.size()):
			var final_color: Color = _tinted_foliage_color(part_type, base_colors[i], season_id)
			mmi.multimesh.set_instance_color(i, final_color)
			_live_colors[part_type][i] = final_color


## 2026-07-06 (regression "repousse d'arbre efface les autres arbres") :
## extrait de apply_season_tint() pour etre reutilisable par
## _spawn_new_tree_and_apply (qui doit pouvoir recalculer la couleur actuelle
## de chaque instance de feuillage apres un agrandissement de MultiMesh, sans
## dupliquer cette logique). Comportement de calcul strictement identique a
## avant.
func _tinted_foliage_color(part_type: int, base_color: Color, season_id: String) -> Color:
	# 2026-07-05 (cycle des saisons, "sauf les sapins" en automne/hiver) :
	# CONE (sapin) suit sa propre table, jamais SEASON_FOLIAGE_TINT/l'automne.
	if part_type == PartType.CONE:
		var cone_tint: Color = SEASON_CONE_TINT.get(season_id, Color(1.0, 1.0, 1.0))
		return base_color * cone_tint
	# 2026-07-06 : l'automne n'est plus dans SEASON_FOLIAGE_TINT (voir sa
	# declaration) - traite a part ci-dessous via un lerp vers du rouge/orange.
	if season_id == "automne":
		return base_color.lerp(AUTOMNE_LEAF_TARGET, AUTOMNE_LEAF_STRENGTH)
	var tint: Color = SEASON_FOLIAGE_TINT.get(season_id, Color(1.0, 1.0, 1.0, 1.0))
	return base_color * tint


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
	var zero_xform := Transform3D(Basis().scaled(Vector3.ONE * HIDDEN_INSTANCE_SCALE), Vector3.ZERO)
	for ref in refs:
		var part_type: int = ref[0]
		var idx: int = ref[1]
		_mmi[part_type].multimesh.set_instance_transform(idx, zero_xform)
		# 2026-07-06 (regression "repousse d'arbre efface les autres arbres") :
		# retient l'etat "cache" ici aussi, sinon _spawn_new_tree_and_apply
		# ferait REAPPARAITRE cet arbre coupe au prochain agrandissement du
		# MultiMesh (voir doc de _live_xforms).
		_live_xforms[part_type][idx] = zero_xform


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
## 2026-07-06 (correctif bug "les fruits ne disparaissent pas en hiver") :
## SeasonSystem.gd cachait bien les fruits (visible=false) au debut de
## l'hiver, MAIS appelait ensuite update_view_level() pour reconcilier avec
## le niveau de vue courant - et cette fonction remettait "visible = not
## hidden" SANS savoir que c'etait l'hiver, annulant donc immediatement le
## masquage. update_view_level() doit desormais lui-meme connaitre l'etat
## hiver (voir set_winter_fruits_hidden), pour rester correct quel que soit
## qui l'appelle et dans quel ordre (changement de niveau de vue OU de saison).
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
				# 2026-07-06 (regression "repousse d'arbre efface les autres
				# arbres") : _live_xforms mis a jour ici aussi (voir sa doc).
				if hidden:
					_mmi[part_type].multimesh.set_instance_transform(idx, zero_xform)
					_live_xforms[part_type][idx] = zero_xform
				else:
					_mmi[part_type].multimesh.set_instance_transform(idx, _pending_xforms[part_type][idx])
					_live_xforms[part_type][idx] = _pending_xforms[part_type][idx]
		for child in tree.get_children():
			if (child.name as String).begins_with("Fruit_"):
				child.visible = not hidden and not _winter_fruits_hidden
