extends Node3D
## Prototype ISOLE (aucune dependance au jeu principal pour la logique
## CUBE+SOL elle-meme - VoxelWorld.gd/VoxelMeshBuilder.gd ne sont ni touches
## ni utilises ici) pour valider le modele CUBE+SOL a part : carte 50x50 avec
## relief (collines, hauteur max HILL_MAX_HEIGHT) - la SURFACE de chaque
## colonne (CUBE vide, SOL en herbe verte) est a _hill_height_at(x,z), PAS un
## niveau 0 fixe. 10 niveaux de sous-sol en dessous de CETTE surface (terre
## puis pierre/filons - voir generate_flat_terrain).
##
## Chaque bloc = EXACTEMENT DEUX elements - un CUBE et un SOL fin A LA BASE du
## CUBE, qui se partagent le MEME espace vertical [Y, Y+1] SANS jamais se
## chevaucher : SOL = tranche du bas (hauteur SOL_THICKNESS), CUBE = tout le
## reste au-dessus (hauteur 1-SOL_THICKNESS).
##
## RENDU (Francois 2026-07-10, "on va de-risquer le rendu par couche avant de
## retenter le jeu principal") : depuis cette etape, CUBE et SOL ne sont plus
## des BoxMesh natifs individuels (un par bloc) - c'est un SEUL mesh combine
## pour toute la carte, construit a la main (quads via SurfaceTool, meme
## technique que VoxelMeshBuilder.gd du jeu principal), avec culling des
## faces cachees (une face n'est dessinee que si le voisin correspondant est
## vide) - voir _add_cube_faces/_add_sol_faces/_build_blocks. Objectif :
## verifier que cette technique (nécessaire a l'echelle 100-250 du jeu
## principal, un noeud par bloc ne tenant pas) reproduit fidelement le rendu
## precedent. SEULE EXCEPTION : le CUBE des blocs de cascade (cascade_marks),
## qui reste un MeshInstance3D individuel reutilisant le quart de cylindre
## deja construit/valide dans WaterfallShapes.gd du jeu principal (geometrie
## courbe, pas exprimable simplement en quads culles).
## Camera orbitale a la souris (voir les variables orbit_*) pour inspecter le
## resultat en 3D. Construction etape par etape - ne pas anticiper la suite.
##
## Filons metal/pierres precieuses (Francois 2026-07-09, "reprends le code du
## projet principal pour les proportions") : VoxelVeins.gd + VeinMaterials.gd
## sont reutilises TELS QUELS (memes seuils de rarete/memes couleurs/meme
## bruit) plutot que de redupliquer ces proportions a la main ici - ces 2
## scripts n'ont aucune dependance a VoxelWorld.gd (voir leur propre doc de
## tete), rien a adapter pour les reutiliser dans un prototype isole.
##
## Lacs/rivieres (Francois 2026-07-10, "reprends les regles de generation
## des lacs et rivieres dans le projet principal") : VoxelHydrology.gd est
## reutilise TEL QUEL (memes lacs/rivieres/paliers de relief), meme raison
## que VoxelVeins.gd - aucune dependance a VoxelWorld.gd. Eau = bloc CUBE+SOL
## comme les autres, materiau EAU (CUBE=SOL=eau, decision Francois 2026-07-08
## - pas de lit terre/pierre distinct sous l'eau).

const VoxelVeinsScript := preload("res://scripts/monde/voxel/VoxelVeins.gd")
const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
const VoxelHydrologyScript := preload("res://scripts/monde/voxel/VoxelHydrology.gd")
## Reutilise UNIQUEMENT _build_quarter_cylinder_mesh() (geometrie deja geree/
## validee, voir [[project_forgotten_caves_waterfall_shape_spec]]) - jamais
## ajoute a l'arbre de scene, juste une "fabrique" de maillage instanciee une
## fois dans _build_blocks() puis liberee (voir son .free() la-bas).
const WaterfallShapesScript := preload("res://scripts/monde/WaterfallShapes.gd")

enum BlockType { EMPTY, DIRT, STONE, WATER }

const WIDTH := 50
const DEPTH := 50
const SOL_THICKNESS := 0.1  # "1 pixel" de hauteur - fine tranche visuelle

## Sous-sol : 10 niveaux fixes sous la SURFACE DE CHAQUE COLONNE (voir
## _hill_height_at - la SURFACE n'est plus un niveau 0 unique depuis le
## relief, elle varie par colonne) - les DIRT_HEIGHT premiers en terre
## (meme valeur que VoxelWorld.gd), le reste en pierre (avec filons, voir
## generate_flat_terrain).
const SUBSOIL_DEPTH := 10
const DIRT_HEIGHT := 3

## Relief (Francois 2026-07-10, "hauteur max = 3") : bruit tres basse
## frequence (meme esprit que VoxelWorld.hill_noise) remis a l'echelle
## 0..HILL_MAX_HEIGHT et arrondi - voir _hill_height_at. Plus haut niveau
## POSSIBLE sur toute la carte, utilise comme borne de scan par
## _is_sol_exposed_to_light (chaque colonne a sa PROPRE surface, potentiel-
## lement plus basse, mais rien n'existe jamais au-dessus de cette borne).
const HILL_MAX_HEIGHT := 3
var hill_noise := FastNoiseLite.new()

var grid: Dictionary = {}      # Vector3i -> BlockType, le CUBE
var sol_grid: Dictionary = {}  # Vector3i -> BlockType, le SOL (meme materiau que le CUBE ici - voir generate_flat_terrain)

## Marque UNIQUEMENT les positions ajoutees par la boucle "cascades" (voir
## generate_flat_terrain) - couleur VIOLETTE temporaire (Francois 2026-07-10,
## "pour que je comprenne comment tu representes a l'ecran"), a retirer une
## fois la forme definitive validee. N'affecte pas block_type (grid/sol_grid
## restent BlockType.WATER comme avant) - seulement le rendu (_cube_color_for).
var cascade_marks: Dictionary = {}  # Vector3i -> true

## Terre/herbe (memes teintes que les etapes precedentes) + pierre (meme
## teinte de base que VoxelMeshBuilder.STONE_BASE dans le jeu principal). Les
## filons, eux, prennent leur couleur directement depuis VeinMaterials (voir
## _cube_color_for) - pas de constante ici, ce serait dupliquer ces couleurs.
const DIRT_COLOR := Color(0.45, 0.30, 0.15)
const GRASS_COLOR := Color(0.30, 0.65, 0.20)
const STONE_COLOR := Color(0.58, 0.60, 0.66)
const SOL_UNDERGROUND_DARKEN := 0.75
## Meme couleur de base que VoxelMeshBuilder.WATER_COLOR dans le jeu
## principal. Dans le prototype, le SOL d'eau est neanmoins assombri comme
## tout autre materiau (regle de test generale, voir _sol_color_for) - donc
## CUBE et SOL d'un bloc d'eau restent visuellement distincts, meme si le
## jeu principal n'a pas cette nuance.
const WATER_COLOR := Color(0.45, 0.80, 0.98)
## Couleur DEBUG temporaire des blocs de cascade (Francois 2026-07-10, "on va
## définir la couleur du CUBE cascade en VIOLET") - distincte de WATER_COLOR
## le temps de valider la zone couverte par l'algorithme, voir cascade_marks.
const CASCADE_COLOR := Color(0.55, 0.15, 0.75)

## Navigation camera : orbite autour du centre de la carte. Clic MOLETTE +
## deplacement de la souris = tourner (yaw/pitch) ; molette (scroll) = zoom.
var cam: Camera3D
var orbit_target: Vector3
var orbit_yaw: float = 0.0
var orbit_pitch: float = -0.5  # radians, legerement plongeant au depart
var orbit_distance: float = 55.0
const ORBIT_SENSITIVITY := 0.01
const ZOOM_STEP := 3.0
const MIN_DISTANCE := 5.0
const MAX_DISTANCE := 150.0

## Filons - meme systeme que VoxelWorld.gd (var vein_system), voir doc de
## tete. Cache de materiaux Godot par couleur (voir _material_for_color) pour
## eviter de creer un StandardMaterial3D par bloc individuel.
var vein_system: VoxelVeinsScript = VoxelVeinsScript.new()
var _material_cache: Dictionary = {}  # Color -> StandardMaterial3D

## Lacs/rivieres - meme systeme que VoxelWorld.gd (var hydrology), voir doc
## de tete. water_noise sert au contour irregulier des lacs (voir
## VoxelHydrology._place_lakes) - meme frequence que le jeu principal.
var hydrology: VoxelHydrologyScript = VoxelHydrologyScript.new()
var water_noise := FastNoiseLite.new()

## Graine constante (Francois 2026-07-10, "on utilise une seed 123456
## constante... pour retester le proto a seed constante") - appelee
## explicitement avant tout get_rng(), pour que le resultat soit reproductible
## d'un lancement a l'autre (meme mecanisme que le seed de partie de
## VoxelWorld.gd/_ready(), juste une valeur fixe ici plutot que saisie au menu).
const PROTOTYPE_SEED := 123456


func _ready() -> void:
	GameRandom.setup(PROTOTYPE_SEED)
	var terrain_rng: RandomNumberGenerator = GameRandom.get_rng("terrain")
	hill_noise.seed = terrain_rng.randi()
	hill_noise.frequency = 0.02  # tres basse - relief doux, pas de "dents de scie"
	water_noise.seed = terrain_rng.randi()
	water_noise.frequency = 0.15
	vein_system.setup_vein_noises()
	# DEBUG TEMPORAIRE (Francois 2026-07-10, "on va simplifier. trace une
	# couche unique de terre. rien d'autre.") : bug de rendu ("des layers
	# vides entre chaque layer normale") observe avec la generation complete
	# (relief/eau/sous-sol/filons/cascades) - on isole le probleme en
	# revenant a la carte la plus simple possible (une seule couche de
	# terre, plate), pour verifier si le bug vient du RENDU par couche
	# lui-meme ou de la complexite de la donnee generee. Remettre
	# "generate_flat_terrain()" une fois le bug de rendu resolu.
	_generate_single_dirt_layer()
	_build_blocks()
	_setup_scene()


## DEBUG TEMPORAIRE (voir _ready) : carte la plus simple possible - DEUX
## couches empilees (y=0 et y=-1), CUBE et SOL en terre partout, rien d'autre
## (pas de relief, pas d'eau, pas de filons, pas de cascade). Sert
## uniquement a isoler le bug de rendu ("layers vides entre chaque layer") de
## toute la complexite de generate_flat_terrain() - une seule couche (y=0)
## ne suffisait pas a le reproduire/verifier, Francois a demande une 2e
## couche en dessous.
func _generate_single_dirt_layer() -> void:
	for x in range(WIDTH):
		for z in range(DEPTH):
			for y in [0, -1]:
				var pos := Vector3i(x, y, z)
				grid[pos] = BlockType.DIRT
				sol_grid[pos] = BlockType.DIRT


## Hauteur de colline (0..HILL_MAX_HEIGHT) a une colonne (x,z) - meme
## principe que VoxelWorld._hill_height_at : bruit -1..1 remis a l'echelle
## 0..1 puis multiplie par HILL_MAX_HEIGHT et arrondi.
func _hill_height_at(x: int, z: int) -> int:
	var n: float = hill_noise.get_noise_2d(float(x), float(z))
	var t: float = (n + 1.0) * 0.5
	return int(round(t * HILL_MAX_HEIGHT))


## SURFACE (niveau = _hill_height_at(x,z), sauf override par lac/riviere -
## voir hill_overrides ci-dessous - PAS un 0 fixe depuis le relief).
##
## Regle corrigee (Francois 2026-07-10, "l'eau est tracee SOUS la surface,
## et le SOL de surface correspondant est supprime" - erreur precedente :
## l'eau etait construite AU NIVEAU de la surface, un cran trop haut) : le
## CUBE reste TOUJOURS vide au niveau de surface (colonne seche OU colonne
## d'eau) - seule la colonne SECHE y pose un SOL (herbe). Une colonne d'eau
## n'a AUCUN SOL a ce niveau (supprime, pas de "sol flottant" au-dessus de
## l'eau) : l'eau commence UN NIVEAU EN DESSOUS de la surface, exactement
## comme le CUBE souterrain d'une colonne seche - la surface de l'eau
## affleure donc exactement a la meme hauteur que le sol seche voisin.
##
## SOUS-SOL (les SUBSOIL_DEPTH niveaux EN DESSOUS de la surface, immerges ou
## non) : CUBE plein sur chaque niveau (eau sur les water_depth premiers
## niveaux d'une colonne d'eau, terre pour les DIRT_HEIGHT premiers niveaux
## SINON, pierre ensuite - le lit terre/pierre existe qu'il soit immerge ou
## non, voir _place_lakes/_place_river), SOL = MEME materiau que le CUBE
## (regle par defaut du modele CUBE+SOL). Les filons sont tires via
## vein_system.maybe_place_vein.
##
## hill_overrides (lacs aplatis, rivieres en paliers) est PRIORITAIRE sur le
## bruit de relief brut - meme regle que VoxelWorld.generate_flat_terrain.
##
## CASCADES (Francois 2026-07-10) : voir le second bloc de boucle en bas de
## cette fonction - "waterfalls" ajoute un mur d'eau vertical en plus, sur les
## colonnes de transition entre un palier haut et un palier bas.
func generate_flat_terrain() -> void:
	var veins: Array = VeinMaterials.all()
	var water_info: Dictionary = hydrology.compute_water_columns(water_noise, Callable(self, "_hill_height_at"), WIDTH, DEPTH)
	var water_cols: Dictionary = water_info["cols"]
	var hill_overrides: Dictionary = water_info["hill_overrides"]

	for x in range(WIDTH):
		for z in range(DEPTH):
			var pos2d := Vector2i(x, z)
			var water_depth: int = water_cols.get(pos2d, 0)
			var surface_y: int = hill_overrides.get(pos2d, _hill_height_at(x, z))

			if water_depth == 0:
				# SURFACE SECHE : CUBE vide (rien ecrit dans "grid"), SOL = herbe.
				sol_grid[Vector3i(x, surface_y, z)] = BlockType.DIRT
			# SURFACE D'UNE COLONNE D'EAU : CUBE vide ICI AUSSI, et AUCUN SOL
			# (supprime) - l'eau ne commence qu'au niveau juste en dessous,
			# voir la boucle suivante (layer 1).

			for layer in range(1, SUBSOIL_DEPTH + 1):
				var pos := Vector3i(x, surface_y - layer, z)
				var block_type: int
				if layer <= water_depth:
					block_type = BlockType.WATER
				else:
					block_type = BlockType.DIRT if layer <= DIRT_HEIGHT else BlockType.STONE
				grid[pos] = block_type
				sol_grid[pos] = block_type
				if block_type == BlockType.STONE:
					vein_system.maybe_place_vein(pos, veins)

	# CASCADES : "waterfalls" (VoxelHydrology.compute_water_columns) donne,
	# par colonne de transition riviere, un "top"/"bottom" exprimes dans le
	# repere du jeu principal (decale de hydrology.HEIGHT-1, un offset fixe
	# PROPRE a VoxelHydrology.gd - jamais duplique en dur ici, meme categorie
	# de bug que C19/WIDTH-DEPTH). Ramenes dans NOTRE repere (surface_y
	# direct, sans offset), on pose un mur vertical CUBE+SOL=eau entre
	# "bottom" et "top" inclus, SUR LA MEME COLONNE que le bassin du bas deja
	# rempli ci-dessus (vient s'ajouter, ne le remplace pas).
	#
	# "top" brut = surface_y (sec) du palier SUPERIEUR - mais par notre regle
	# "l'eau commence un niveau SOUS la surface" (meme regle que toute colonne
	# d'eau, voir plus haut), ce niveau de surface lui-meme ne doit jamais etre
	# de l'eau. D'ou le "-1" : la cascade doit s'arreter au niveau d'eau le
	# plus haut du palier superieur, pas a sa surface seche (bug corrige
	# 2026-07-10 : "la cascade fait 2 de hauteur au lieu d'1" - un niveau en
	# trop en haut).
	#
	# "bank_faces" (berges a reveler comme une falaise) n'est PAS utilise ici
	# : c'est une aide au brouillard de guerre du jeu principal (reveler un
	# terrain deja genere mais cache) - le prototype n'a pas de brouillard de
	# guerre, tout est deja rendu sans condition (voir _build_blocks).
	var waterfalls: Dictionary = water_info["waterfalls"]
	var height_offset: int = hydrology.HEIGHT - 1
	for pos2d in waterfalls:
		var fall: Dictionary = waterfalls[pos2d]
		var top: int = int(fall["top"]) - height_offset - 1
		var bottom: int = int(fall["bottom"]) - height_offset
		for y in range(bottom, top + 1):
			var pos := Vector3i(pos2d.x, y, pos2d.y)  # Vector2i.y = coordonnee Z ici (pas de champ .z sur Vector2i)
			grid[pos] = BlockType.WATER
			sol_grid[pos] = BlockType.WATER
			cascade_marks[pos] = true


func get_sol(pos: Vector3i) -> int:
	return sol_grid.get(pos, BlockType.EMPTY)


## Couleur du CUBE a une position - filon (vein_system.vein_grid) prioritaire
## sur la couleur de pierre generique, meme logique que
## VoxelMeshBuilder._bucket_for/_vein_color_for dans le jeu principal. L'eau
## est verifiee en premier (jamais de filon dans l'eau).
func _cube_color_for(pos: Vector3i, block_type: int) -> Color:
	if cascade_marks.has(pos):
		return CASCADE_COLOR
	if block_type == BlockType.WATER:
		return WATER_COLOR
	if block_type == BlockType.STONE and vein_system.vein_grid.has(pos):
		var material: Dictionary = VeinMaterials.get_type(vein_system.vein_grid[pos])
		return material.get("couleur", STONE_COLOR)
	if block_type == BlockType.STONE:
		return STONE_COLOR
	return DIRT_COLOR


## Regle (Francois 2026-07-10, a preciser) : "le SOL de la SURFACE est en
## terre" ET "la terre exposee a la lumiere a un sous-type herbe qui a sa
## propre representation verte" - herbe n'est PAS un BlockType a part (le
## SOL reste sol_grid[pos] = BlockType.DIRT partout, voir
## generate_flat_terrain), seulement une couleur de rendu declenchee par
## l'EXPOSITION A LA LUMIERE (voir _is_sol_exposed_to_light), jamais un Y
## code en dur - la meme logique doit continuer a marcher plus tard si la
## SURFACE cesse d'etre plate (relief, trou creuse...). L'eau suit la MEME
## regle generale que tout autre materiau (Francois 2026-07-10 : "les blocs
## sont TOUJOURS constitues de CUBE + SOL en materiau = Eau, avec SOL plus
## sombre provisoirement pour les tests") - pas de cas particulier : son CUBE
## est non-vide, donc _is_sol_exposed_to_light echoue toujours pour elle
## (jamais "herbe"), et son SOL est assombri comme les autres materiaux.
func _sol_color_for(pos: Vector3i) -> Color:
	var block_type: int = grid.get(pos, BlockType.EMPTY)
	if _is_sol_exposed_to_light(pos):
		return GRASS_COLOR
	var base: Color = _cube_color_for(pos, block_type)
	return Color(base.r * SOL_UNDERGROUND_DARKEN, base.g * SOL_UNDERGROUND_DARKEN, base.b * SOL_UNDERGROUND_DARKEN)


## Un SOL est expose a la lumiere si RIEN ne le couvre : ni le CUBE de son
## PROPRE niveau (meme bloc, juste au-dessus de lui - voir _build_blocks),
## ni aucun CUBE plein a un niveau plus haut dans la meme colonne. Scanne
## jusqu'a HILL_MAX_HEIGHT (le plus haut niveau POSSIBLE sur toute la carte,
## voir sa doc) - suffisant meme si CETTE colonne a une surface plus basse,
## rien n'existe jamais au-dessus de HILL_MAX_HEIGHT de toute facon.
func _is_sol_exposed_to_light(pos: Vector3i) -> bool:
	if grid.get(pos, BlockType.EMPTY) != BlockType.EMPTY:
		return false
	for y in range(pos.y + 1, HILL_MAX_HEIGHT + 1):
		if grid.get(Vector3i(pos.x, y, pos.z), BlockType.EMPTY) != BlockType.EMPTY:
			return false
	return true


## Un seul StandardMaterial3D par couleur distincte (terre/pierre/herbe/
## chaque materiau de filon - un petit nombre fixe), reutilise entre toutes
## les instances de cette couleur plutot qu'un materiau par bloc.
func _material_for_color(color: Color) -> StandardMaterial3D:
	if _material_cache.has(color):
		return _material_cache[color]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	# Chaque face dessinee a la main (voir _add_cell_face) n'est visible que
	# d'UN SEUL cote par defaut dans Godot - desactive cette limite (meme
	# reglage que VoxelMeshBuilder.gd du jeu principal) pour que les 6 cotes
	# de chaque CUBE/SOL restent visibles quel que soit le cote d'ou on
	# regarde, sans avoir a garantir un ordre de sommets parfait partout.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material_cache[color] = mat
	return mat


## Point d'entree du rendu. Parcourt tous les niveaux de HILL_MAX_HEIGHT (le
## plus haut sommet POSSIBLE, voir sa doc) a -SUBSOIL_DEPTH (le plus bas
## sous-sol possible, colonne la plus basse) - grid/get_sol renvoient
## simplement EMPTY hors de la plage reelle d'une colonne donnee, rien ne se
## dessine a tort. Le CUBE de cascade (quart de cylindre) reste un
## MeshInstance3D individuel (voir doc de tete du fichier) ; tout le reste
## (CUBE normal + SOL, cascade INCLUSE) part dans le mesh combine unique
## construit par _add_cube_faces/_add_sol_faces puis _commit_combined_mesh.
func _build_blocks() -> void:
	var shape_builder := WaterfallShapesScript.new()
	var cascade_mesh: ArrayMesh = shape_builder._build_quarter_cylinder_mesh(1.0, 1.0, 16, StandardMaterial3D.new())
	shape_builder.free()  # jamais ajoute a l'arbre - juste utilise comme fabrique de maillage, voir sa doc

	var surface_tools: Dictionary = {}  # Color -> SurfaceTool, un seul mesh combine (voir _commit_combined_mesh)

	for x in range(WIDTH):
		for z in range(DEPTH):
			for y in range(HILL_MAX_HEIGHT, -SUBSOIL_DEPTH - 1, -1):
				var pos := Vector3i(x, y, z)
				var block_type: int = grid.get(pos, BlockType.EMPTY)
				if block_type != BlockType.EMPTY:
					if cascade_marks.has(pos):
						# Rayon=1, position "posee au sol/collee au bloc superieur" -
						# voir historique de cette geometrie dans la memoire projet.
						var cube_mat := _material_for_color(_cube_color_for(pos, block_type))
						_add_box(cascade_mesh, cube_mat, Vector3(pos.x, pos.y + SOL_THICKNESS, pos.z + 0.5))
					else:
						_add_cube_faces(surface_tools, pos, block_type)
				if get_sol(pos) != BlockType.EMPTY:
					_add_sol_faces(surface_tools, pos, block_type)

	_commit_combined_mesh(surface_tools)


## "mesh: Mesh" (pas "BoxMesh") - accepte aussi le quart de cylindre
## (ArrayMesh) des blocs de cascade. Reste utilise UNIQUEMENT pour cette
## exception (geometrie courbe) - tout le reste passe par le mesh combine.
func _add_box(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	mesh_instance.position = pos
	add_child(mesh_instance)


## CUBE d'un bloc NON-cascade (occupe [Y+SOL_THICKNESS, Y+1], voir doc de
## tete) : jusqu'a 5 faces (jamais la face du DESSOUS - toujours cachee par
## le SOL du MEME bloc, qui est TOUJOURS non-vide des que le CUBE l'est, voir
## generate_flat_terrain : grid[pos] et sol_grid[pos] sont toujours ecrits
## ensemble). Face laterale/dessus exposee <=> le CUBE voisin dans cette
## direction est vide (culling, meme principe que
## VoxelMeshBuilder._is_face_exposed).
func _add_cube_faces(surface_tools: Dictionary, pos: Vector3i, block_type: int) -> void:
	var color: Color = _cube_color_for(pos, block_type)
	var st: SurfaceTool = _get_surface_tool(surface_tools, color)
	var y0: float = pos.y + SOL_THICKNESS
	var y1: float = pos.y + 1.0
	for dir in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if grid.get(pos + dir, BlockType.EMPTY) == BlockType.EMPTY:
			_add_cell_face(st, pos, dir, y0, y1, color)


## SOL d'un bloc (occupe [Y, Y+SOL_THICKNESS], voir doc de tete) - s'applique
## a TOUS les blocs, cascade incluse (contrairement au CUBE, le SOL est
## toujours une fine tranche plate, jamais courbe). Faces laterales : exposee
## si le SOL voisin (get_sol, PAS grid) est vide. Face du DESSUS : exposee
## uniquement si RIEN ne la couvre au meme point (block_type vide) - c'est la
## vraie surface praticable (herbe, fond d'un lac...). Face du DESSOUS :
## exposee si le CUBE juste en dessous (Y-1) est vide (cas rare avec la
## generation actuelle - jamais de sous-sol vide - mais correct par
## construction, utile plus tard pour "creuser").
func _add_sol_faces(surface_tools: Dictionary, pos: Vector3i, block_type: int) -> void:
	var color: Color = _sol_color_for(pos)
	var st: SurfaceTool = _get_surface_tool(surface_tools, color)
	var y0: float = pos.y
	var y1: float = pos.y + SOL_THICKNESS
	for dir in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if get_sol(pos + dir) == BlockType.EMPTY:
			_add_cell_face(st, pos, dir, y0, y1, color)
	if block_type == BlockType.EMPTY:
		_add_cell_face(st, pos, Vector3i(0, 1, 0), y0, y1, color)
	if grid.get(pos + Vector3i(0, -1, 0), BlockType.EMPTY) == BlockType.EMPTY:
		_add_cell_face(st, pos, Vector3i(0, -1, 0), y0, y1, color)


## Un SurfaceTool par couleur distincte rencontree (petit nombre fixe -
## terre/herbe/pierre/eau/filons/leurs variantes assombries de SOL), cree a
## la demande et reutilise pour toutes les faces de cette couleur - meme
## esprit que _material_for_color, applique ici au "bucket" de geometrie
## plutot qu'au materiau.
func _get_surface_tool(surface_tools: Dictionary, color: Color) -> SurfaceTool:
	if surface_tools.has(color):
		return surface_tools[color]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface_tools[color] = st
	return st


## Ajoute UNE face (quad = 2 triangles) d'une boite qui occupe TOUJOURS toute
## la largeur/profondeur de la case (X et Z de 0 a 1) mais seulement une
## tranche verticale [y0, y1] - suffisant pour CUBE (y0=SOL_THICKNESS, y1=1)
## ET SOL (y0=0, y1=SOL_THICKNESS), les deux ayant toujours la pleine
## largeur/profondeur (seule la hauteur differe, voir doc de tete). Vertices/
## normales/enroulement repris TELS QUELS de VoxelMeshBuilder._add_face (jeu
## principal), juste parametres sur y0/y1 au lieu de 0/1 fixes - reduit le
## risque d'erreur sur une geometrie deja validee ailleurs.
func _add_cell_face(st: SurfaceTool, pos: Vector3i, dir: Vector3i, y0: float, y1: float, color: Color) -> void:
	var p := Vector3(pos.x, pos.y, pos.z)
	var verts: Array

	if dir == Vector3i(1, 0, 0):
		verts = [p + Vector3(1, y0, 0), p + Vector3(1, y1, 0), p + Vector3(1, y1, 1), p + Vector3(1, y0, 1)]
	elif dir == Vector3i(-1, 0, 0):
		verts = [p + Vector3(0, y0, 1), p + Vector3(0, y1, 1), p + Vector3(0, y1, 0), p + Vector3(0, y0, 0)]
	elif dir == Vector3i(0, 1, 0):
		verts = [p + Vector3(0, y1, 0), p + Vector3(0, y1, 1), p + Vector3(1, y1, 1), p + Vector3(1, y1, 0)]
	elif dir == Vector3i(0, -1, 0):
		verts = [p + Vector3(1, y0, 0), p + Vector3(1, y0, 1), p + Vector3(0, y0, 1), p + Vector3(0, y0, 0)]
	elif dir == Vector3i(0, 0, 1):
		verts = [p + Vector3(1, y0, 1), p + Vector3(1, y1, 1), p + Vector3(0, y1, 1), p + Vector3(0, y0, 1)]
	else: # Vector3i(0, 0, -1)
		verts = [p + Vector3(0, y0, 0), p + Vector3(0, y1, 0), p + Vector3(1, y1, 0), p + Vector3(1, y0, 0)]

	var normal := Vector3(dir.x, dir.y, dir.z)
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(verts[idx])


## Assemble tous les SurfaceTool (un par couleur) dans un seul ArrayMesh porte
## par un seul MeshInstance3D pour toute la carte - remplace les centaines de
## milliers de noeuds individuels d'avant. Un SurfaceTool sans face ajoutee ne
## produit aucune surface au commit() (Godot l'ignore silencieusement) - donc
## l'indice de surface reellement obtenu peut etre inferieur a l'indice
## d'origine des qu'une couleur precedente n'a produit aucune face ; d'ou
## "surfaces_before" pour assigner le materiau au BON indice (meme technique
## que VoxelMeshBuilder._rebuild_mesh_body/_get_bucket_materials).
func _commit_combined_mesh(surface_tools: Dictionary) -> void:
	var mesh := ArrayMesh.new()
	for color in surface_tools.keys():
		var st: SurfaceTool = surface_tools[color]
		var surfaces_before: int = mesh.get_surface_count()
		st.commit(mesh)
		if mesh.get_surface_count() > surfaces_before:
			mesh.surface_set_material(surfaces_before, _material_for_color(color))

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	add_child(mesh_instance)


## Camera orbitale (voir doc pres des variables orbit_*) + lumiere
## directionnelle, pour voir la carte au lancement de la scene.
func _setup_scene() -> void:
	cam = Camera3D.new()
	add_child(cam)
	orbit_target = Vector3(WIDTH / 2.0, 0.0, DEPTH / 2.0)
	cam.current = true
	_update_camera_transform()

	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-45, -45, 0)
	light.light_energy = 1.1

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	env_node.environment = env
	add_child(env_node)


## Clic MOLETTE + deplacement souris = orbite (yaw/pitch) autour du centre de
## la carte. Molette (scroll haut/bas) = zoom (rapproche/eloigne, borne entre
## MIN_DISTANCE et MAX_DISTANCE).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		orbit_yaw -= event.relative.x * ORBIT_SENSITIVITY
		orbit_pitch = clamp(orbit_pitch - event.relative.y * ORBIT_SENSITIVITY, -1.5, -0.05)
		_update_camera_transform()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = clamp(orbit_distance - ZOOM_STEP, MIN_DISTANCE, MAX_DISTANCE)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = clamp(orbit_distance + ZOOM_STEP, MIN_DISTANCE, MAX_DISTANCE)
			_update_camera_transform()


## Recalcule la position de la camera a partir de orbit_yaw/orbit_pitch/
## orbit_distance (coordonnees spheriques autour de orbit_target), et la
## fait regarder vers ce meme point.
func _update_camera_transform() -> void:
	var offset := Vector3(
		cos(orbit_pitch) * sin(orbit_yaw),
		sin(-orbit_pitch),
		cos(orbit_pitch) * cos(orbit_yaw)
	) * orbit_distance
	cam.position = orbit_target + offset
	cam.look_at(orbit_target, Vector3.UP)
