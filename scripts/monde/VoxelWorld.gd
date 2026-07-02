extends Node3D
## Sprint 1 : genere une petite carte de test plate (terre sur pierre)
## et construit un mesh unique par materiau, en ne dessinant que les
## faces exposees (culling des faces cachees / internes).
## Sprint 21 : le dessus "terre" (l'herbe) n'utilise plus le damier
## clair/fonce mais une couleur de base par climat/saison (ClimateDefinitions),
## avec une legere variation continue par case (bruit) pour casser la
## monotonie sans redessiner un motif regulier. Le damier reste inchange
## pour la pierre (utile pour reperer les trous mines) et pour les murs.
## Sprint 23 : profondeur agrandie (voir HEIGHT) + filons de metaux/pierres
## precieuses generes aleatoirement dans la pierre (jamais dans la terre,
## niveaux 1-3), visibles a l'oeil (couleur du filon, voir _vein_color_for).
## Note : le Sprint 23quater avait tente une texture d'atlas pour les filons,
## mais provoquait des blocs blancs non resolus (texture non affichee malgre
## un preload valide) - revert complet au Sprint 23ter (couleur unie par
## materiau) le temps de comprendre la vraie cause.
## Sprint 23sexies : ajout de "pepites" 3D (petites spheres) incrustees sur les
## faces exposees des blocs de filon, en plus de la couleur de fond - rondes et
## lisses pour les metaux (metallic/roughness), a facettes (maillage a peu de
## segments, orientation aleatoire) et legerement lumineuses pour les pierres
## precieuses. Aucune image/texture/shader : uniquement des SphereMesh integres
## au moteur + MultiMeshInstance3D + couleur par instance (meme principe que la
## couleur par sommet utilisee pour l'herbe/la pierre/les filons), pour eviter
## de retomber sur le bug de blocs blancs du Sprint 23quater.

const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")
const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")

# Dimensions de la carte de test (on agrandira vers 200x200x100 plus tard)
const WIDTH := 20   # axe X
const DEPTH := 20   # axe Z
const HEIGHT := 30  # axe Y (hauteur totale, y=0 = fond) - Sprint 23 : 10 -> 30 pour laisser de la place aux filons

# Nombre de niveaux de terre en surface (le reste en dessous = pierre)
const DIRT_HEIGHT := 3

# Sprint 23 : seuil de bruit (0..1, plus c'est haut plus c'est rare) au-dela
# duquel un bloc de pierre devient un filon, par palier de rarete. Valeurs de
# depart raisonnables, a ajuster apres avoir vu le resultat en jeu.
const RARITY_THRESHOLDS := {
	"commun": 0.45,
	"rare": 0.65,
	"tres_rare": 0.80,
}

# Marge au-dessus du terrain pour pouvoir construire des murs en hauteur (Sprint 7)
const BUILD_CEILING := HEIGHT + 10

enum BlockType { EMPTY, DIRT, STONE, WOOD_WALL, STONE_WALL }

# Grille du monde : cle = Vector3i (position bloc), valeur = BlockType
var grid: Dictionary = {}

# Sprint 23 : filons. Cle = Vector3i (position bloc, toujours un bloc
# BlockType.STONE), valeur = id du materiau (voir MetalTypes.gd/GemTypes.gd).
# Dictionnaire separe plutot qu'un nouveau BlockType par materiau : evite de
# faire exploser l'enum BlockType et le systeme de buckets pour chaque metal/
# pierre precieuse (voir _bucket_for/_vein_color_for : un seul bucket
# supplementaire, colore par sommet, sert pour tous les materiaux).
var vein_grid: Dictionary = {}

# 6 directions possibles autour d'un bloc (droite/gauche/haut/bas/avant/arriere)
const DIRECTIONS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


var mesh_instance: MeshInstance3D

# Sprint 23bis : niveau de "coupe" visible (correction du systeme de niveaux
## de CameraRig.gd, qui ne faisait jusqu'ici que deplacer la camera sans rien
## cacher du terrain - inutile pour voir un niveau souterrain puisque tout est
## plein). Tout bloc strictement au-dessus de view_level n'est pas dessine du
## tout, et le dessus des blocs exactement a view_level est toujours dessine
## (meme si un bloc existait juste au-dessus dans la grille), ce qui revele
## une coupe horizontale complete du niveau courant, avec ses couleurs
## (damier pierre, filons...). Pilote par CameraRig.set_view_level().
var view_level: int = HEIGHT - 1

# Sprint 21 : climat/saison utilises pour la couleur du terrain (voir
# ClimateDefinitions.gd). Une seule saison geree pour l'instant, mais ces
# exports permettent deja de changer de climat/saison sans toucher au code.
@export var climate_id: String = "tempere"
@export var season_id: String = "ete"

# Bruit utilise pour la variation subtile de couleur de l'herbe, case par
# case (voir _grass_color_for). Frequence basse => variation douce/continue,
# tres different d'un damier ou d'un bruit purement aleatoire par case.
var terrain_noise := FastNoiseLite.new()

# Sprint 23ter : meme principe que terrain_noise, mais pour la pierre (voir
# _stone_color_for). Bruit separe pour que les variations de l'herbe et de la
# pierre ne soient pas correlees (pas la meme "forme" de variation).
var stone_noise := FastNoiseLite.new()

# Sprint 23ter : couleur de base unique de la pierre (remplace l'ancien
# damier clair/fonce - voir _stone_color_for/_bucket_for). Un niveau de pierre
# donne doit avoir un materiau uniforme, les filons etant la seule exception
## visible (comme demande explicitement : "un materiau uniforme par niveau,
## avec des exceptions aleatoires" pour les filons).
const STONE_BASE := Color(0.58, 0.60, 0.66)

# Sprint 23 : un bruit 3D independant par materiau de filon (metal/pierre
# precieuse), cle = id du materiau. Des seeds differentes evitent que tous
# les materiaux se superposent aux memes endroits.
var vein_noises: Dictionary = {}

# Sprint 23sexies : nombre de pepites 3D generees par bloc de filon visible
# (voir _rebuild_vein_pepites) - densite "beaucoup" choisie explicitement.
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

# Sprint 23sexies : les deux MultiMeshInstance3D qui portent toutes les
# pepites (un pour les metaux, un pour les pierres precieuses) - un seul
# noeud par categorie, la couleur de chaque pepite est portee par une couleur
# d'instance (meme principe que la couleur par sommet du reste du terrain).
var metal_pepites: MultiMeshInstance3D
var gem_pepites: MultiMeshInstance3D


func _ready() -> void:
	terrain_noise.seed = randi()
	terrain_noise.frequency = 0.18
	stone_noise.seed = randi()
	stone_noise.frequency = 0.18
	_setup_vein_noises()
	generate_flat_terrain()
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	_setup_vein_pepites_nodes()
	rebuild_mesh()


## Sprint 23bis : change le niveau de "coupe" visible (voir view_level) et
## reconstruit le mesh en consequence. Appele par CameraRig a chaque
## changement de niveau (molette de la souris).
func set_view_level(level: int) -> void:
	view_level = clampi(level, 0, HEIGHT - 1)
	rebuild_mesh()


## Cree un bruit 3D par materiau de filon (voir vein_noises). Frequence assez
## basse pour former des petits amas coherents (des "poches" de quelques
## blocs) plutot qu'un bruit poivre-et-sel bloc par bloc.
func _setup_vein_noises() -> void:
	for entry in VeinMaterials.all():
		var n := FastNoiseLite.new()
		n.seed = randi()
		n.frequency = 0.16
		vein_noises[entry["id"]] = n


## Sprint 23sexies : cree les deux MultiMeshInstance3D qui portent les pepites
## (metaux/pierres precieuses), avec leur mesh et leur materiau. Appele une
## seule fois dans _ready() ; le contenu (nombre/position/couleur des pepites)
## est ensuite recalcule a chaque rebuild_mesh() via _rebuild_vein_pepites().
func _setup_vein_pepites_nodes() -> void:
	metal_pepites = MultiMeshInstance3D.new()
	metal_pepites.multimesh = MultiMesh.new()
	metal_pepites.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	metal_pepites.multimesh.use_colors = true
	metal_pepites.multimesh.mesh = _make_pepite_mesh(true)
	metal_pepites.material_override = _make_pepite_material(true)
	add_child(metal_pepites)

	gem_pepites = MultiMeshInstance3D.new()
	gem_pepites.multimesh = MultiMesh.new()
	gem_pepites.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	gem_pepites.multimesh.use_colors = true
	gem_pepites.multimesh.mesh = _make_pepite_mesh(false)
	gem_pepites.material_override = _make_pepite_material(false)
	add_child(gem_pepites)


## Sprint 23sexies : mesh d'une pepite - une SphereMesh integree au moteur,
## avec peu de segments pour les pierres precieuses (aspect a facettes, comme
## une pierre taillee) et beaucoup de segments pour les metaux (aspect rond/
## lisse, comme une pepite brute). Le rayon reel est applique par instance via
## l'echelle de la transform (voir _rebuild_vein_pepites), donc rayon=1 ici.
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


## Sprint 23sexies : materiau des pepites - couleur par instance (comme la
## couleur par sommet du reste du terrain), mais cette fois avec un vrai
## eclairage (pas "unshaded") pour que metallic/roughness/emission aient un
## effet visible. Metaux : reflets metalliques. Pierres precieuses : surface
## lisse/brillante + leger scintillement (emission) independant de la couleur.
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


## Renvoie le y du bloc le plus haut (non vide) de la colonne (x,z), -1 si vide.
## Cherche jusqu'a BUILD_CEILING pour tenir compte des murs construits en hauteur.
func get_top_block_y(x: int, z: int) -> int:
	for y in range(BUILD_CEILING - 1, -1, -1):
		if get_block(Vector3i(x, y, z)) != BlockType.EMPTY:
			return y
	return -1


## Indique si on peut encore construire en hauteur sur cette colonne
func can_build(x: int, z: int) -> bool:
	return get_top_block_y(x, z) + 1 < BUILD_CEILING


## Indique si le sommet de la colonne (x,z) est de la terre (Sprint 19 :
## utilise pour placer les decorations de sol, on ne decore que l'herbe/terre,
## pas la pierre nue ni les murs construits). Renvoie un bool plutot que
## d'exposer l'enum BlockType, pour eviter le probleme de typage deja
## rencontre (voir Dwarf.gd/ActionController.gd : un script qui recupere
## %VoxelWorld via un type generique Node3D ne peut pas resoudre un enum
## defini uniquement dans ce script).
func is_dirt_top(x: int, z: int) -> bool:
	var y: int = get_top_block_y(x, z)
	if y < 0:
		return false
	return get_block(Vector3i(x, y, z)) == BlockType.DIRT


## Sprint 25 : type + materiau du bloc du sommet de la colonne (x,z), pour la
## fenetre d'info au clic (voir ActionController._describe_block). Renvoie des
## chaines ("terre"/"pierre"/"mur_bois"/"mur_pierre"/"vide") plutot que l'enum
## BlockType, meme raison que is_dirt_top ci-dessus (l'enum n'est pas resolvable
## depuis un script qui recupere %VoxelWorld via un type generique Node3D).
func get_block_info(x: int, z: int) -> Dictionary:
	var y: int = get_top_block_y(x, z)
	if y < 0:
		return {"type": "vide", "materiau": ""}
	var pos := Vector3i(x, y, z)
	var type: int = get_block(pos)
	var materiau: String = ""
	if type == BlockType.STONE and vein_grid.has(pos):
		materiau = vein_grid[pos]
	var type_id: String
	match type:
		BlockType.DIRT:
			type_id = "terre"
		BlockType.STONE:
			type_id = "pierre"
		BlockType.WOOD_WALL:
			type_id = "mur_bois"
		BlockType.STONE_WALL:
			type_id = "mur_pierre"
		_:
			type_id = "vide"
	return {"type": type_id, "materiau": materiau}


## Construit un mur (bois, pierre ou terre) au sommet de la colonne (x,z), en
## empilant sur ce qui existe deja (fonctionne aussi bien pour reboucher
## un trou mine que pour construire en hauteur sur un sol plein)
func build_block(x: int, z: int, material: String) -> void:
	var target_y := get_top_block_y(x, z) + 1
	if target_y >= BUILD_CEILING:
		return
	var type: int
	match material:
		"bois":
			type = BlockType.WOOD_WALL
		"pierre":
			type = BlockType.STONE_WALL
		"terre":
			type = BlockType.DIRT  # reutilise le type terre : mine, ca redonne bien "terre"
		_:
			type = BlockType.WOOD_WALL
	grid[Vector3i(x, target_y, z)] = type
	rebuild_mesh()


## Retire un bloc de la grille (mine/creuse), reconstruit le mesh, et renvoie
## le nom de la ressource obtenue ("terre", "pierre", ou l'id d'un filon comme
## "fer"/"rubis" - Sprint 23) ou "" si rien a miner
func remove_block(x: int, y: int, z: int) -> String:
	var pos := Vector3i(x, y, z)
	if not grid.has(pos):
		return ""
	var type: int = grid[pos]
	grid.erase(pos)
	var vein_id: String = ""
	if vein_grid.has(pos):
		vein_id = vein_grid[pos]
		vein_grid.erase(pos)
	rebuild_mesh()
	if vein_id != "":
		return vein_id
	if type == BlockType.DIRT:
		return "terre"
	elif type == BlockType.STONE:
		return "pierre"
	return ""


## Remplit la grille : pierre en bas, terre au-dessus (terrain plat pour
## l'instant). Sprint 23 : la terre reste limitee aux DIRT_HEIGHT niveaux du
## haut (niveaux 1-3 depuis la surface) ; dans la pierre en dessous, chaque
## bloc a une chance (par materiau, voir vein_noises/RARITY_THRESHOLDS) de
## devenir un filon plutot que de la pierre nue.
func generate_flat_terrain() -> void:
	var veins: Array = VeinMaterials.all()  # deja triee du plus rare au plus commun
	for x in range(WIDTH):
		for z in range(DEPTH):
			for y in range(HEIGHT):
				var type := BlockType.STONE
				if y >= HEIGHT - DIRT_HEIGHT:
					type = BlockType.DIRT
				var pos := Vector3i(x, y, z)
				grid[pos] = type
				if type == BlockType.STONE:
					_maybe_place_vein(pos, veins)


## Tire au sort si la case de pierre "pos" devient un filon. Parcourt les
## materiaux du plus rare au plus commun et s'arrete au premier qui "matche"
## (evite qu'un materiau commun ne prenne la place d'un materiau rare sur le
## meme bloc, chacun ayant son propre bruit independant).
func _maybe_place_vein(pos: Vector3i, veins: Array) -> void:
	for entry in veins:
		var id: String = entry["id"]
		var threshold: float = RARITY_THRESHOLDS.get(entry["rarete"], 0.7)
		var noise: FastNoiseLite = vein_noises[id]
		var n: float = noise.get_noise_3d(float(pos.x), float(pos.y), float(pos.z))  # -1..1
		if n > threshold:
			vein_grid[pos] = id
			return


## Renvoie le type de bloc a une position, EMPTY si hors de la carte
func get_block(pos: Vector3i) -> int:
	return grid.get(pos, BlockType.EMPTY)


## Sprint 23bis : une face est exposee (donc dessinee) si la case voisine est
## soit reellement vide (comportement d'origine), soit au-dessus du niveau de
## coupe visible (view_level) - dans ce cas elle n'est pas dessinee non plus,
## donc pour ce qu'on affiche, elle "n'existe pas" et la face doit apparaitre.
## C'est ce qui revele le dessus colore de chaque bloc au niveau courant.
func _is_face_exposed(neighbor_pos: Vector3i) -> bool:
	if neighbor_pos.y > view_level:
		return true
	return get_block(neighbor_pos) == BlockType.EMPTY


## Sprint 21 : couleur de l'herbe (dessus terre) a une position donnee,
## couleur de base du climat/saison actuels modulee par un bruit continu
## (+/- environ 12% de luminosite), pour une variation douce case par case
## au lieu du damier clair/fonce utilise auparavant.
func _grass_color_for(pos: Vector3i) -> Color:
	var base: Color = ClimateDefs.get_terrain_color(climate_id, season_id)
	var n: float = terrain_noise.get_noise_2d(float(pos.x), float(pos.z))  # -1..1
	var factor: float = 1.0 + n * 0.12
	return Color(
		clamp(base.r * factor, 0.0, 1.0),
		clamp(base.g * factor, 0.0, 1.0),
		clamp(base.b * factor, 0.0, 1.0),
		base.a
	)


## Sprint 23ter : couleur de la pierre (dessus) a une position donnee - couleur
## de base unique (STONE_BASE) moduleee par un bruit continu (+/- ~12% de
## luminosite), remplace l'ancien damier clair/fonce a deux tons. Meme
## technique que _grass_color_for, sur le meme principe : un materiau uniforme
## par niveau, les filons restant la seule vraie exception de couleur.
func _stone_color_for(pos: Vector3i) -> Color:
	var n: float = stone_noise.get_noise_2d(float(pos.x), float(pos.z))  # -1..1
	var factor: float = 1.0 + n * 0.12
	return Color(
		clamp(STONE_BASE.r * factor, 0.0, 1.0),
		clamp(STONE_BASE.g * factor, 0.0, 1.0),
		clamp(STONE_BASE.b * factor, 0.0, 1.0),
		STONE_BASE.a
	)


## Sprint 23 : couleur d'un bloc de filon (metal/pierre precieuse) a une
## position donnee, recuperee depuis MetalTypes/GemTypes via VeinMaterials.
## Couleur neutre de secours si jamais la position n'est plus dans vein_grid
## (ne devrait pas arriver, garde par securite).
func _vein_color_for(pos: Vector3i) -> Color:
	if not vein_grid.has(pos):
		return Color(0.5, 0.5, 0.5)
	var material: Dictionary = VeinMaterials.get_type(vein_grid[pos])
	return material.get("couleur", Color(0.5, 0.5, 0.5))


## Construit un seul mesh avec une surface par materiau, en n'ajoutant une
## face que si le bloc voisin dans cette direction est vide (culling des
## faces cachees). Sprint 10 : les faces verticales/du dessous (parois d'un
## trou mine ou d'un mur) sont assombries par rapport aux faces du dessus,
## pour bien distinguer un creux (paroi sombre visible) d'une simple
## variation de couleur de surface. Sprint 21 : le dessus terre (bucket 0,
## l'herbe) n'est plus un damier clair/fonce mais une couleur par climat/
## saison + variation de bruit par case, appliquee via des couleurs de
## sommet (voir _grass_color_for et _add_face). Le bucket 1 (ancien "terre
## fonce" du damier) n'est plus utilise pour l'instant mais reste reserve
## (evite de renumeroter tous les autres buckets). Sprint 23 : bucket 10
## ajoute pour les filons (metal/pierre precieuse), colore par sommet comme
## l'herbe, mais applique a toutes les faces du bloc (dessus ET parois) pour
## que le filon reste visible/reperable une fois une paroi exposee. Sprint
## 23bis : les blocs strictement au-dessus de view_level ne sont pas dessines
## du tout, et leur "absence" compte comme une face exposee pour le bloc
## juste en dessous (voir _is_face_exposed) - c'est ce qui revele une coupe
## horizontale complete et coloree du niveau courant (comme un Dwarf Fortress),
## au lieu de se contenter de deplacer la camera a l'interieur de la roche pleine.
## Sprint 23ter : le dessus pierre (bucket 2) suit maintenant le meme principe
## que l'herbe (bucket 0) - couleur uniforme (STONE_BASE) + bruit, au lieu de
## l'ancien damier clair/fonce a deux tons (bucket 3 devient inutilise, meme
## traitement que le bucket 1 pour l'herbe).
func rebuild_mesh() -> void:
	# 11 buckets : 0-3 = dessus terre/pierre (0=herbe couleur variable, 1=inutilise,
	# 2=pierre couleur variable, 3=inutilise), 4-5 = dessus mur bois/pierre,
	# 6-9 = parois assombries (terre, pierre, mur bois, mur pierre),
	# 10 = filon (metal/pierre precieuse, toutes faces, couleur variable).
	var surface_tools: Array = []
	for i in range(11):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface_tools.append(st)

	for pos in grid.keys():
		if pos.y > view_level:
			continue  # au-dessus du niveau visible : pas dessine du tout (vue en coupe)
		var type: int = grid[pos]
		if type == BlockType.EMPTY:
			continue
		for dir in DIRECTIONS:
			if _is_face_exposed(pos + dir):
				var idx := _bucket_for(pos, type, dir)
				var face_color := Color.WHITE
				if idx == 0:
					face_color = _grass_color_for(pos)
				elif idx == 2:
					face_color = _stone_color_for(pos)
				elif idx == 10:
					face_color = _vein_color_for(pos)
				_add_face(surface_tools[idx], pos, dir, face_color)

	# Sprint 13 : palette plus vive/saturee (direction "BD"), sur le meme
	# principe qu'avant (damier clair/fonce + parois assombries)
	var dirt_dark := Color(0.58, 0.34, 0.10)  # garde pour bucket 6 (paroi terre)
	var stone_dark := Color(0.48, 0.50, 0.56)  # garde pour bucket 3 (inutilise) et bucket 7 (paroi)
	var wood_wall := Color(0.70, 0.46, 0.16)
	var stone_wall := Color(0.74, 0.76, 0.82)

	# Sprint 24octies : materiau associe a chaque bucket (index dans
	# surface_tools). Un SurfaceTool sans aucune face ajoutee ne produit PAS
	# de surface lors du commit() (Godot ignore silencieusement les buckets
	# vides), donc l'indice de surface reellement obtenu dans le mesh final
	# peut etre INFERIEUR a l'indice du bucket d'origine des qu'un bucket
	# precedent est vide (ex : aucun mur en bois sur la carte -> bucket 4
	# vide -> tout ce qui suit se decale). Assigner les materiaux a des
	# indices fixes 0-10 provoquait donc "Index p_idx out of bounds" des
	# qu'un type de bloc etait absent de la carte (cas frequent sur une
	# carte fraiche/petite). On mappe maintenant chaque bucket a son
	# materiau via un dictionnaire, et on n'appelle surface_set_material
	# qu'apres coup, sur le vrai indice de surface obtenu (compte a part,
	# qui n'avance que quand un commit() a effectivement ajoute une surface).
	var bucket_materials := {
		0: _make_vertex_color_material(),
		1: _make_material(dirt_dark),  # inutilise (voir plus haut)
		2: _make_vertex_color_material(),
		3: _make_material(stone_dark),  # inutilise (voir plus haut)
		4: _make_material(wood_wall),
		5: _make_material(stone_wall),
		6: _make_material(_darken(dirt_dark)),
		7: _make_material(_darken(stone_dark)),
		8: _make_material(_darken(wood_wall)),
		9: _make_material(_darken(stone_wall)),
		10: _make_vertex_color_material(),
	}

	var mesh := ArrayMesh.new()
	for bucket_idx in range(surface_tools.size()):
		var st: SurfaceTool = surface_tools[bucket_idx]
		var surfaces_before := mesh.get_surface_count()
		st.commit(mesh)
		if mesh.get_surface_count() > surfaces_before:
			mesh.surface_set_material(surfaces_before, bucket_materials[bucket_idx])

	mesh_instance.mesh = mesh
	_rebuild_vein_pepites()


## Determine dans quelle surface (materiau + face) placer un bloc donne.
## Sprint 21 : le dessus terre (herbe) n'utilise plus qu'un seul bucket (0,
## couleur variable par sommet), le damier clair/fonce est retire pour ce cas.
## Sprint 23ter : meme traitement pour le dessus pierre (bucket 2, couleur
## variable) - retire de l'ancien damier clair/fonce a deux tons, pour que
## chaque niveau ait un materiau de pierre uniforme (les filons restant la
## seule exception de couleur, voir plus bas).
## Sprint 23 : un bloc de pierre qui est un filon (vein_grid) passe sur le
## bucket 10 (couleur variable), sur toutes ses faces (dessus ET parois),
## avant meme de regarder le type - un filon reste un filon peu importe la face.
func _bucket_for(pos: Vector3i, type: int, dir: Vector3i) -> int:
	var is_top := dir == Vector3i(0, 1, 0)

	if type == BlockType.STONE and vein_grid.has(pos):
		return 10

	if is_top:
		match type:
			BlockType.DIRT:
				return 0
			BlockType.STONE:
				return 2
			BlockType.WOOD_WALL:
				return 4
			BlockType.STONE_WALL:
				return 5
		return 0

	match type:
		BlockType.DIRT:
			return 6
		BlockType.STONE:
			return 7
		BlockType.WOOD_WALL:
			return 8
		BlockType.STONE_WALL:
			return 9
	return 6


## Assombrit une couleur (utilise pour les parois des trous/murs, effet
## d'ombrage simple sans veritable eclairage)
func _darken(color: Color) -> Color:
	return Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, color.a)


## Cree un materiau simple, dans la couleur donnee.
## 2026-07-02 : passe de SHADING_MODE_UNSHADED a l'eclairage reel (mode par
## defaut de StandardMaterial3D) pour que le terrain reagisse enfin au cycle
## jour/nuit (DayNightCycle.gd) - un materiau "unshaded" ignore totalement
## la lumiere/les ombres, ce qui rendait la carte aussi lumineuse en pleine
## nuit qu'en plein jour et empechait toute ombre portee de s'afficher.
## roughness=1/metallic=0 evite les reflets speculaires pour garder un rendu
## plat/mat coherent avec le style low-poly du jeu, tout en recevant
## lumiere directionnelle + ombres + lumiere ambiante.
func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## Sprint 21 : materiau pour le bucket 0 (herbe), qui lit la couleur par
## sommet (definie via SurfaceTool.set_color dans _add_face) au lieu d'une
## seule couleur fixe - c'est ce qui permet la variation continue par case.
## 2026-07-02 : meme passage a l'eclairage reel que _make_material ci-dessus.
func _make_vertex_color_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## Ajoute un quad (2 triangles) sur la face "dir" du bloc a la position "pos".
## face_color : couleur de sommet (Sprint 21, utilisee uniquement par le
## bucket "herbe"/"pierre"/"filon" dont le materiau lit vertex_color_use_as_albedo ;
## ignoree par les autres materiaux, donc sans effet pour eux).
func _add_face(st: SurfaceTool, pos: Vector3i, dir: Vector3i, face_color: Color = Color.WHITE) -> void:
	var p := Vector3(pos.x, pos.y, pos.z)
	var verts: Array

	if dir == Vector3i(1, 0, 0):
		verts = [p + Vector3(1, 0, 0), p + Vector3(1, 1, 0), p + Vector3(1, 1, 1), p + Vector3(1, 0, 1)]
	elif dir == Vector3i(-1, 0, 0):
		verts = [p + Vector3(0, 0, 1), p + Vector3(0, 1, 1), p + Vector3(0, 1, 0), p + Vector3(0, 0, 0)]
	elif dir == Vector3i(0, 1, 0):
		verts = [p + Vector3(0, 1, 0), p + Vector3(0, 1, 1), p + Vector3(1, 1, 1), p + Vector3(1, 1, 0)]
	elif dir == Vector3i(0, -1, 0):
		verts = [p + Vector3(1, 0, 0), p + Vector3(1, 0, 1), p + Vector3(0, 0, 1), p + Vector3(0, 0, 0)]
	elif dir == Vector3i(0, 0, 1):
		verts = [p + Vector3(1, 0, 1), p + Vector3(1, 1, 1), p + Vector3(0, 1, 1), p + Vector3(0, 0, 1)]
	else: # Vector3i(0, 0, -1)
		verts = [p + Vector3(0, 0, 0), p + Vector3(0, 1, 0), p + Vector3(1, 1, 0), p + Vector3(1, 0, 0)]

	var normal := Vector3(dir.x, dir.y, dir.z)

	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[0])
	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[1])
	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[2])

	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[0])
	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[2])
	st.set_color(face_color)
	st.set_normal(normal)
	st.add_vertex(verts[3])


## Sprint 23sexies : recalcule entierement les pepites (metaux/pierres
## precieuses) a partir de vein_grid - appele a la fin de rebuild_mesh(), donc
## a chaque fois que le terrain change (miner/construire/changer de niveau).
## Ne place des pepites que sur les blocs de filon qui ont au moins une face
## exposee (meme logique que le reste du terrain, voir _is_face_exposed) - un
## filon entierement enterre/hors vue n'a pas de pepites.
func _rebuild_vein_pepites() -> void:
	var metal_transforms: Array = []
	var metal_colors: Array = []
	var gem_transforms: Array = []
	var gem_colors: Array = []

	for pos in vein_grid.keys():
		if pos.y > view_level:
			continue
		var exposed_dir: Vector3i = Vector3i.ZERO
		var found_exposed := false
		for dir in DIRECTIONS:
			if _is_face_exposed(pos + dir):
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
## pepites d'un bloc donne restent toujours les memes d'un rebuild a l'autre
## (miner/construire ailleurs ne doit pas faire "sauter" les pepites existantes)
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
