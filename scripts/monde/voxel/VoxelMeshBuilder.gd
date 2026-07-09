extends RefCounted
## Construction du mesh du terrain : culling des faces cachees, choix du
## "bucket" (materiau/couleur) par bloc, couleurs herbe/pierre/filon, ajout
## des quads.
##
## "rebuild(...)" copie les parametres recus dans ses propres membres (memes
## noms qu'un acces direct aux champs de VoxelWorld.gd : grid, discovered,
## view_level, WIDTH, DEPTH, DIRECTIONS, is_frozen, snow_coverage,
## climate_id, season_id, terrain_noise, stone_noise, mesh_instance), puis
## reconstruit le mesh. Deux adaptations par rapport a un acces direct aux
## champs de VoxelWorld : _is_face_exposed n'appelle plus VoxelWorld.get_block()
## (inutile, ce module a deja "grid") et _grass_color_for/_stone_color_for
## appellent get_top_block_y via un Callable (cette fonction reste sur
## VoxelWorld, pas dupliquee ici - evite un ecart si sa logique change un jour).
##
## Ce module ne prend jamais de reference typee vers VoxelWorld.gd lui-meme
## (meme raison que VoxelVeins.gd, voir sa note en tete de fichier - une
## reference typee generique ne resout pas un acces direct du type
## "voxel_world.WATER_COLOR").

const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")
const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
const VoxelVeinsScript := preload("res://scripts/monde/voxel/VoxelVeins.gd")

# Duplique de l'enum BlockType de VoxelWorld.gd (memes valeurs/ordre exacts -
# EMPTY=0, DIRT=1, STONE=2, WOOD_WALL=3, STONE_WALL=4, WATER=5). Necessaire
# car un enum defini dans un script ne se resout pas depuis un autre script
# sans creer une reference typee croisee (voir note en tete de fichier) - les
# entiers stockes dans "grid" restent valides quel que soit l'enum utilise
# pour les nommer. ATTENTION : si le BlockType de VoxelWorld.gd change un
# jour (ajout/retrait/reordonnancement), reproduire le changement ici.
enum BlockType { EMPTY, DIRT, STONE, WOOD_WALL, STONE_WALL, WATER }

const UNDISCOVERED_COLOR := Color(0.5, 0.5, 0.5)
const WATER_COLOR := Color(0.45, 0.80, 0.98)
const ICE_COLOR := Color(0.78, 0.88, 0.94)
const SNOW_COLOR := Color(0.95, 0.96, 0.98)
const STONE_BASE := Color(0.58, 0.60, 0.66)
## Terre en sous-sol (voir _is_underground) : couleur fixe, PAS teintee par
## climat/saison (contrairement a la terre exposee au ciel, voir
## _grass_color_for) - une case creusee ou de la roche jamais minee en
## profondeur n'a pas de raison de changer avec les saisons. Meme esprit que
## STONE_BASE : un materiau uniforme (+ bruit), pas de variation climatique.
const DIRT_UNDERGROUND_BASE := Color(0.40, 0.28, 0.16)
## Facteur d'assombrissement "penombre" applique a la couleur NATURELLE du
## materiau (terre/pierre, voir _apply_penombre) pour tout ce qui est
## sous-sol - ne remplace jamais la couleur du materiau par une teinte
## generique, seulement sa luminosite (important pour la pierre : la
## couleur doit rester lisible si different types de pierre a l'avenir,
## feedback Francois 2026-07-08).
const PENOMBRE_FACTOR := 0.6
const WOOD_WALL_COLOR := Color(0.70, 0.46, 0.16)
const STONE_WALL_COLOR := Color(0.74, 0.76, 0.82)
## Repli uniquement (voir _stair_color_for) - une plaque d'escalier reprend
## normalement la couleur du materiau qu'elle traverse (terre/pierre/mur,
## comme une paroi minee normale), jamais une couleur arbitraire. Ce repli ne
## sert que pour un materiau inattendu (ex: eau, cas limite non prevu).
const STAIR_COLOR := Color(0.62, 0.48, 0.30)

# Membres copies depuis VoxelWorld.gd a chaque appel de rebuild() (voir
# commentaire de tete). Noms EN MAJUSCULES (WIDTH/DEPTH/DIRECTIONS) volontai-
# rement gardes tels quels (pas la convention habituelle pour un "var") pour
# que le corps des fonctions ci-dessous reste identique, caractere pour
# caractere, a un acces direct aux champs de VoxelWorld.gd - minimise le
# risque d'erreur de transcription sur du code deja tres retravaille.
var grid: Dictionary
var discovered: Dictionary
var vein_grid: Dictionary
var vein_system: VoxelVeinsScript
## Escaliers (voir VoxelWorld.stair_grid) : Vector3i -> {"piece":
## "bas"/"haut"/"hautbas", "material": BlockType}.
var stair_grid: Dictionary
var view_level: int
var WIDTH: int
var DEPTH: int
var is_frozen: bool
var snow_coverage: float
var climate_id: String
var season_id: String
var terrain_noise: FastNoiseLite
## Cache des 13 materiaux de bucket - voir _get_bucket_materials plus bas.
var _bucket_materials: Dictionary = {}
var stone_noise: FastNoiseLite
var DIRECTIONS: Array
var mesh_instance: MeshInstance3D
var get_top_block_y: Callable
## Materiau du SOL a une position donnee (voir VoxelWorld.get_sol, memoire
## "Modele CUBE+SOL" 2026-07-08) - utilise par _add_boundary_cube_faces pour
## colorer la face du dessus a la couche-frontiere avec le VRAI materiau du
## SOL plutot que le capuchon sombre generique d'avant.
var get_sol: Callable

## Cache de geometrie PAR COUCHE Y (perf 2026-07-08, diagnostic mesure : la
## passe "discovered" a elle seule coutait 183-467 ms par changement de
## niveau de vue sur une carte avec 117 138 blocs decouverts, l'essentiel du
## temps total). Constat cle : un bloc a Y strictement EN DESSOUS du niveau
## de coupe (view_level) a des faces laterales/dessous ET un dessus "naturel"
## (expose seulement si le voisin du dessus est reellement vide) qui NE
## DEPENDENT PAS de la valeur exacte de view_level - seulement de si le bloc
## est bien <= view_level. Seule la couche EXACTEMENT au niveau de coupe a un
## dessus special "toujours revele en coupe" (voir _is_face_exposed). On peut
## donc mettre en cache, PAR VALEUR DE Y, deux petits ArrayMesh par bucket :
## - _layer_sides_bottom[y][bucket] : faces laterales + dessous (toujours
##   reutilisables telles quelles, y compris pour la couche-frontiere).
## - _layer_natural_top[y][bucket] : dessus "naturel" (reutilisable
##   uniquement pour un Y strictement EN DESSOUS de view_level - jamais pour
##   la couche-frontiere, qui n'affiche JAMAIS de dessus, voir
##   _add_boundary_cube_faces).
## Un changement de NIVEAU DE VUE ne fait donc plus que recoller des morceaux
## deja calcules (SurfaceTool.append_from, operation native rapide) au lieu
## de tout reparcourir. Le cache est invalide UNIQUEMENT quand la geometrie
## ou les couleurs baked dedans changent reellement : mutation de grille
## (minage/construction, voir p_grid_changed) OU changement de climat/saison/
## neige (qui changent les couleurs herbe/pierre baked par sommet - voir
## _grass_color_for/_stone_color_for) - VoxelWorld.rebuild_mesh() passe
## p_grid_changed=false UNIQUEMENT depuis set_view_level(), tous ses autres
## appelants (build_block/remove_block/set_climate_state/generation initiale/
## SeasonSystem.gd) gardent le comportement par defaut (invalidation).
var _layer_sides_bottom: Dictionary = {}  # int y -> Dictionary[bucket_idx -> ArrayMesh]
var _layer_natural_top: Dictionary = {}   # int y -> Dictionary[bucket_idx -> ArrayMesh]
## Positions decouvertes non-vides, regroupees par Y (construit en meme
## temps que le cache ci-dessus) - permet a _add_boundary_cube_faces de ne
## reparcourir QUE la couche-frontiere (quelques milliers de blocs en
## moyenne) au lieu de tout "discovered" (117 138 dans l'exemple mesure).
var _layer_positions: Dictionary = {}     # int y -> Array[Vector3i]
## Cache des plaques d'escalier, meme principe que _layer_sides_bottom :
## bucket 13 (eclaire) ou 19 (non eclaire, voir _is_underground). Construit
## dans _build_layer_cache() a partir de stair_grid (independant de
## "discovered" - un escalier deja creuse est par definition deja connu).
var _layer_stairs: Dictionary = {}        # int y -> Dictionary[bucket_idx -> ArrayMesh]
var _cache_populated: bool = false


## Invalide le cache par couche (voir sa doc) - a appeler des que la
## geometrie/les couleurs qu'il contient ne sont plus a jour. Le prochain
## _rebuild_mesh_body() le reconstruira integralement (meme cout qu'un
## rebuild complet classique), une seule fois, meme si plusieurs changements
## de niveau de vue suivent avant la prochaine mutation reelle.
func invalidate_cache() -> void:
	_layer_sides_bottom.clear()
	_layer_natural_top.clear()
	_layer_positions.clear()
	_layer_stairs.clear()
	_cache_populated = false


## Point d'entree, appele par VoxelWorld.rebuild_mesh() (facade fine).
## Recopie l'etat necessaire puis reconstruit le mesh (voir _rebuild_mesh_body).
## p_grid_changed (true par defaut, comportement historique) : si vrai, le
## cache par couche est invalide avant reconstruction (voir sa doc) - a
## laisser a true partout SAUF depuis VoxelWorld.set_view_level(), le seul
## appelant qui ne fait QUE changer le niveau de vue sans toucher
## grid/discovered/climat/saison/neige.
func rebuild(p_grid: Dictionary, p_discovered: Dictionary, p_vein_system: VoxelVeinsScript,
		p_view_level: int, p_width: int, p_depth: int, p_is_frozen: bool,
		p_snow_coverage: float, p_climate_id: String, p_season_id: String,
		p_terrain_noise: FastNoiseLite, p_stone_noise: FastNoiseLite,
		p_directions: Array, p_mesh_instance: MeshInstance3D,
		p_get_top_block_y: Callable, p_stair_grid: Dictionary, p_grid_changed: bool = true,
		p_get_sol: Callable = Callable()) -> void:
	grid = p_grid
	discovered = p_discovered
	vein_system = p_vein_system
	vein_grid = p_vein_system.vein_grid
	stair_grid = p_stair_grid
	view_level = p_view_level
	WIDTH = p_width
	DEPTH = p_depth
	is_frozen = p_is_frozen
	snow_coverage = p_snow_coverage
	climate_id = p_climate_id
	season_id = p_season_id
	terrain_noise = p_terrain_noise
	stone_noise = p_stone_noise
	DIRECTIONS = p_directions
	mesh_instance = p_mesh_instance
	get_top_block_y = p_get_top_block_y
	get_sol = p_get_sol
	if p_grid_changed:
		invalidate_cache()
	_rebuild_mesh_body()


## Une face est exposee (donc dessinee) si la case voisine est soit
## reellement vide, soit au-dessus du niveau de coupe visible (view_level) -
## dans ce cas elle n'est pas dessinee non plus, donc pour ce qu'on affiche,
## elle "n'existe pas" et la face doit apparaitre. C'est ce qui revele le
## dessus colore de chaque bloc au niveau courant.
func _is_face_exposed(neighbor_pos: Vector3i) -> bool:
	if neighbor_pos.y > view_level:
		return true
	return grid.get(neighbor_pos, BlockType.EMPTY) == BlockType.EMPTY


## Couleur de l'herbe (dessus terre) a une position donnee. Exposee au ciel :
## couleur de base du climat/saison actuels moduleee par un bruit continu
## (+/- environ 12% de luminosite), variation douce case par case au lieu
## d'un damier clair/fonce. Sous-sol (voir _is_underground) : le climat/la
## saison n'ont pas de sens pour une case jamais exposee au ciel - couleur
## de terre fixe (DIRT_UNDERGROUND_BASE) assombrie en "penombre" a la place
## (feedback Francois 2026-07-08).
func _grass_color_for(pos: Vector3i) -> Color:
	if _is_underground(pos):
		return _apply_penombre(_noise_modulated_color(DIRT_UNDERGROUND_BASE, terrain_noise, pos))
	var base: Color = ClimateDefs.get_terrain_color(climate_id, season_id)
	return _noise_modulated_color(base, terrain_noise, pos)


## Couleur de la pierre (dessus) a une position donnee - couleur de base
## unique (STONE_BASE) moduleee par un bruit continu (+/- ~12% de
## luminosite). Meme technique que _grass_color_for : un materiau uniforme
## par niveau, les filons restant la seule vraie exception de couleur. Deja
## independante du climat/de la saison (rien a retirer sous terre) - mais
## assombrie en "penombre" comme la terre pour marquer visuellement le
## sous-sol (feedback Francois 2026-07-08 : garder la couleur du materiau,
## juste plus sombre - important pour de futures pierres de couleurs
## differentes).
func _stone_color_for(pos: Vector3i) -> Color:
	var color: Color = _noise_modulated_color(STONE_BASE, stone_noise, pos)
	if _is_underground(pos):
		return _apply_penombre(color)
	return color


## Vrai si la case n'a plus de ciel ouvert au-dessus (encore un bloc plein
## entre elle et le sommet reel de la colonne) - definition de "sous-sol"
## utilisee pour la penombre (_apply_penombre), choisie par Francois
## 2026-07-08 : couvre aussi bien une poche fraichement minee que de la
## roche jamais decouverte en profondeur, sans notion de hauteur fixe.
func _is_underground(pos: Vector3i) -> bool:
	return pos.y < get_top_block_y.call(pos.x, pos.z)


## Assombrit une couleur de materiau DEJA calculee (PENOMBRE_FACTOR) sans en
## changer la teinte - ne remplace jamais par une couleur generique, pour
## rester correct avec de futurs materiaux de couleurs differentes.
func _apply_penombre(color: Color) -> Color:
	return Color(color.r * PENOMBRE_FACTOR, color.g * PENOMBRE_FACTOR, color.b * PENOMBRE_FACTOR, color.a)


## Logique commune a _grass_color_for/_stone_color_for (les 2 partagent le
## meme calcul de bruit + voile de neige, seule la couleur/le bruit de base
## different). Bruit continu (+/- ~12% de luminosite) puis voile de neige,
## uniquement sur la vraie surface exterieure - pas sur un dessus de terre
## mis a jour au fond d'un trou mine, ou il n'y a pas de ciel pour neiger.
## Compare au sommet REEL de CETTE colonne (get_top_block_y), pas HEIGHT-1
## fixe - sinon les sommets de colline (plus hauts que HEIGHT-1) ne
## recevraient jamais de neige.
func _noise_modulated_color(base: Color, noise: FastNoiseLite, pos: Vector3i) -> Color:
	var n: float = noise.get_noise_2d(float(pos.x), float(pos.z))  # -1..1
	var factor: float = 1.0 + n * 0.12
	var color := Color(
		clamp(base.r * factor, 0.0, 1.0),
		clamp(base.g * factor, 0.0, 1.0),
		clamp(base.b * factor, 0.0, 1.0),
		base.a
	)
	if snow_coverage > 0.0 and pos.y == get_top_block_y.call(pos.x, pos.z):
		color = color.lerp(SNOW_COLOR, snow_coverage)
	return color


## Couleur d'une plaque d'escalier a une position donnee, a partir du
## BlockType qui occupait cette case AVANT le creusage (voir
## VoxelWorld.stair_grid) - reprend la meme couleur qu'un bloc normal de ce
## materiau (herbe/terre variable, pierre variable, mur bois/pierre fixe),
## comme une paroi minee. Pas de distinction dessus/paroi ici (contrairement
## a _bucket_for) : les 6 faces de la plaque partagent la meme couleur,
## simplification volontaire de cette premiere passe.
func _stair_color_for(pos: Vector3i, block_type: int) -> Color:
	match block_type:
		BlockType.DIRT:
			return _grass_color_for(pos)
		BlockType.STONE:
			return _stone_color_for(pos)
		BlockType.WOOD_WALL:
			return WOOD_WALL_COLOR
		BlockType.STONE_WALL:
			return STONE_WALL_COLOR
		_:
			return STAIR_COLOR  # repli (eau ou cas imprevu)


## Couleur d'un bloc de filon (metal/pierre precieuse) a une position
## donnee, recuperee depuis MetalTypes/GemTypes via VeinMaterials. Couleur
## neutre de secours si jamais la position n'est plus dans vein_grid (ne
## devrait pas arriver, garde par securite).
func _vein_color_for(pos: Vector3i) -> Color:
	if not vein_grid.has(pos):
		return Color(0.5, 0.5, 0.5)
	var material: Dictionary = VeinMaterials.get_type(vein_grid[pos])
	return material.get("couleur", Color(0.5, 0.5, 0.5))


## Construit un seul mesh avec une surface par materiau, en n'ajoutant une
## face que si le bloc voisin dans cette direction est vide (culling des
## faces cachees). Les faces verticales/du dessous (parois d'un trou mine ou
## d'un mur) sont assombries par rapport aux faces du dessus, pour bien
## distinguer un creux (paroi sombre visible) d'une simple variation de
## couleur de surface. Le dessus terre (bucket 0, l'herbe) et le dessus
## pierre (bucket 2) utilisent une couleur par climat/saison + variation de
## bruit par case, appliquee via des couleurs de sommet (voir
## _grass_color_for/_stone_color_for et _add_face) plutot qu'un damier
## clair/fonce ; les buckets 1 et 3 (ancien damier) restent reserves mais
## inutilises, pour eviter de renumeroter les autres buckets. Le bucket 10
## est reserve aux filons (metal/pierre precieuse), colore par sommet comme
## l'herbe, mais applique a toutes les faces du bloc (dessus ET parois) pour
## que le filon reste visible/reperable une fois une paroi exposee. Les
## blocs strictement au-dessus de view_level ne sont pas dessines du tout,
## et leur "absence" compte comme une face exposee pour le bloc juste en
## dessous (voir _is_face_exposed) - c'est ce qui revele une coupe
## horizontale complete et coloree du niveau courant, au lieu de se
## contenter de deplacer la camera a l'interieur de la roche pleine.
func _rebuild_mesh_body() -> void:
	# 21 buckets : 0-3 = dessus terre/pierre (0=herbe couleur variable, 1=inutilise,
	# 2=pierre couleur variable, 3=inutilise), 4-5 = dessus mur bois/pierre,
	# 6-9 = parois assombries ECLAIREES (terre, pierre, mur bois, mur pierre -
	# paroi tout juste creusee, encore exposee au soleil), 10 = filon ECLAIRE
	# (metal/pierre precieuse, toutes faces, couleur variable),
	# 11 = bloc non decouvert (gris uniforme NON ECLAIRE, voir "discovered"),
	# 12 = eau (couleur unie WATER_COLOR, toutes faces), 13 = plaque
	# d'escalier ECLAIREE (voir stair_grid, couleur variable par sommet -
	# reprend le materiau creuse, voir _stair_color_for), 14-17 = memes parois
	# que 6-9 mais NON ECLAIREES (variante "sous plafond", voir
	# _is_underground/_paroi_bucket_for), 18 = filon NON ECLAIRE, 19 = plaque
	# d'escalier NON ECLAIREE. Les variantes "NON ECLAIREE" (materiau
	# unshaded, voir _make_unshaded_material) servent aux blocs veritablement
	# sous un plafond (Francois 2026-07-08 : le soleil du cycle jour/nuit ne
	# doit pas affecter un bloc qui n'y est jamais expose). 20 = inutilise
	# (ancien bucket DEBUG SOL magenta, retire 2026-07-10 - voir
	# _sol_bucket_and_color_for).
	var surface_tools: Array = []
	for i in range(21):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface_tools.append(st)

	# Cache par couche Y (voir sa doc plus haut) : reconstruit integralement
	# UNE SEULE FOIS par mutation reelle (grid_changed=true, voir rebuild()),
	# jamais a cause d'un simple changement de niveau de vue - c'est le coeur
	# du gain de perf (2026-07-08).
	if not _cache_populated:
		_build_layer_cache()

	# Recompose la geometrie "sous la coupe" a partir du cache : pour chaque
	# couche Y strictement en dessous de view_level, on recolle les faces
	# laterales/dessous ET le dessus "naturel" deja calcules
	# (SurfaceTool.append_from = copie native rapide, pas de recalcul).
	var identity := Transform3D.IDENTITY
	for y in _layer_sides_bottom.keys():
		if y >= view_level:
			continue
		var sb: Dictionary = _layer_sides_bottom[y]
		for bucket_idx in sb.keys():
			surface_tools[bucket_idx].append_from(sb[bucket_idx], 0, identity)
		if _layer_natural_top.has(y):
			var nt: Dictionary = _layer_natural_top[y]
			for bucket_idx in nt.keys():
				surface_tools[bucket_idx].append_from(nt[bucket_idx], 0, identity)

	# Couche-frontiere (y == view_level) : CUBE complet (parois + dessous +
	# le VRAI materiau du SOL sur la face du dessus, voir get_sol/modele
	# CUBE+SOL 2026-07-09) - plus l'ancien "capuchon" generique. Recalcule
	# frais et INCONDITIONNEL (pas juste les faces naturellement
	# exposees du cache _layer_sides_bottom - un bloc de terrain intact,
	# entoure d'autres blocs pleins, doit quand meme montrer ses parois pour
	# se distinguer visuellement comme un cube, pas fusionner en un plan
	# continu). Borne a cette seule couche (_layer_positions), jamais tout
	# "discovered" - voir _add_boundary_cube_faces.
	_add_boundary_cube_faces(surface_tools)

	# RETIRE 2026-07-10 (Francois : "je ne vois pas du tout a quoi servent ces
	# murs. oui enleve ca. on verra pour les trous ensuite") - la passe
	# "parois au-dessus de la coupe" (ajoutee 2026-07-08 pour qu'un trou/
	# escalier creuse garde ses murs visibles quand on baisse la vue sous son
	# niveau) partait de l'hypothese fausse qu'"un bloc de terrain plein
	# normal n'a jamais de voisin lateral vide" - une falaise/berge NATURELLE
	# (jamais minee, voir "is_river_bank_face"/generate_flat_terrain) a
	# pourtant un vrai voisin vide sur le cote, donc ses murs se
	# retrouvaient affiches meme tres au-dessus de la coupe, revelant a tort
	# la forme du relief non explore. Rien ne distinguait "voisin vide car
	# creuse" de "voisin vide car relief naturel" - retire en attendant une
	# vraie solution pour le cas des trous (regression assumee pour
	# l'instant, voir [[project_forgotten_caves_cube_sol_model]]).

	# Plaques d'escalier : pas de distinction couche-frontiere/naturelle (leur
	# geometrie deja partielle - demi-plaque ou plaque fine - montre
	# honnetement le dessus/dessous reel, pas besoin de "reveler en coupe"
	# comme pour un bloc plein), simple recollage pour TOUTE couche connue -
	# y compris au-dessus de la coupe (meme raisonnement que les parois
	# ci-dessus : un escalier deja creuse est par definition deja connu, le
	# montrer meme au-dessus de view_level corrige le meme bug "vu du dessus
	# mais pas de profil").
	for y in _layer_stairs.keys():
		var stairs_at_y: Dictionary = _layer_stairs[y]
		for bucket_idx in stairs_at_y.keys():
			surface_tools[bucket_idx].append_from(stairs_at_y[bucket_idx], 0, identity)

	# Passe "non decouvert" - CUBE complet (6 faces, dessus inclus), gris
	# uniforme, pour representer ce qui n'a jamais ete explore au niveau de
	# coupe courant comme un vrai volume opaque (feedback Francois
	# 2026-07-08). Inconditionnel (pas d'exposition naturelle a verifier) :
	# un bloc de roche entoure d'autre roche - le cas general - doit quand
	# meme montrer ses parois pour se distinguer comme un cube, pas fusionner
	# en un plan gris continu. Le dessus est inclus ici (contrairement a la
	# couche-frontiere decouverte) car le bucket 11 est TOUJOURS gris uniforme
	# et NON ECLAIRE (voir _get_bucket_materials) - il ne peut jamais etre
	# confondu avec un vrai sol praticable, donc pas besoin de le masquer
	# comme pour les blocs decouverts. Toujours borne a WIDTH*DEPTH*6
	# verifications (jamais la profondeur), donc le changement de niveau
	# reste rapide meme a view_level eleve.
	for x in range(WIDTH):
		for z in range(DEPTH):
			var pos := Vector3i(x, view_level, z)
			if discovered.has(pos):
				continue  # deja traite avec sa vraie couleur dans la passe ci-dessus
			var type: int = grid.get(pos, BlockType.EMPTY)
			if type == BlockType.EMPTY:
				continue
			for dir in DIRECTIONS:
				_add_face(surface_tools[11], pos, dir, UNDISCOVERED_COLOR)

	# Materiau associe a chaque bucket (index dans surface_tools). Un
	# SurfaceTool sans aucune face ajoutee ne produit PAS de surface lors du
	# commit() (Godot ignore silencieusement les buckets vides), donc
	# l'indice de surface reellement obtenu dans le mesh final peut etre
	# INFERIEUR a l'indice du bucket d'origine des qu'un bucket precedent
	# est vide (ex : aucun mur en bois sur la carte -> bucket 4 vide -> tout
	# ce qui suit se decale). Assigner les materiaux a des indices fixes
	# 0-10 provoquerait donc "Index p_idx out of bounds" des qu'un type de
	# bloc est absent de la carte (cas frequent sur une carte fraiche/
	# petite). Chaque bucket est donc mappe a son materiau via un
	# dictionnaire, et surface_set_material n'est appele qu'apres coup, sur
	# le vrai indice de surface obtenu (compte a part, qui n'avance que
	# quand un commit() a effectivement ajoute une surface).
	var bucket_materials: Dictionary = _get_bucket_materials()

	var mesh := ArrayMesh.new()
	for bucket_idx in range(surface_tools.size()):
		var st: SurfaceTool = surface_tools[bucket_idx]
		var surfaces_before := mesh.get_surface_count()
		st.commit(mesh)
		if mesh.get_surface_count() > surfaces_before:
			# .get() avec repli sur StandardMaterial3D.new() (materiau
			# neutre) plutot qu'un acces direct - si _get_bucket_materials()
			# ne couvre pas ce bucket_idx, on evite un crash "Index p_idx
			# out of bounds" au profit d'un rendu degrade (couleur par
			# defaut) et d'un avertissement.
			var mat: Material = bucket_materials.get(bucket_idx)
			if mat == null:
				push_warning("VoxelMeshBuilder: aucun materiau pour le bucket %d, materiau par defaut utilise" % bucket_idx)
				mat = StandardMaterial3D.new()
			mesh.surface_set_material(surfaces_before, mat)

	mesh_instance.mesh = mesh
	vein_system.rebuild_pepites(view_level, discovered, Callable(self, "_is_face_exposed"), DIRECTIONS)


## Reconstruit integralement le cache par couche Y (voir sa doc) a partir de
## "discovered" - le seul endroit ou ce dictionnaire est encore parcouru en
## entier. Appele uniquement quand le cache est vide (premier appel, ou
## apres invalidate_cache() suite a une mutation reelle) - JAMAIS a cause
## d'un simple changement de niveau de vue.
func _build_layer_cache() -> void:
	# SurfaceTool actifs pendant la construction, un par (y, bucket) et par
	# categorie (laterales+dessous / dessus naturel) - convertis en ArrayMesh
	# figes a la toute fin, une fois tous les blocs traites.
	var active_sb: Dictionary = {}  # y -> Dictionary[bucket_idx -> SurfaceTool]
	var active_nt: Dictionary = {}  # y -> Dictionary[bucket_idx -> SurfaceTool]

	for pos in discovered.keys():
		var type: int = grid.get(pos, BlockType.EMPTY)
		if type == BlockType.EMPTY:
			continue
		var y: int = pos.y
		if not _layer_positions.has(y):
			_layer_positions[y] = []
			active_sb[y] = {}
			active_nt[y] = {}
		_layer_positions[y].append(pos)
		for dir in DIRECTIONS:
			# Exposition "naturelle" (independante de view_level, voir doc du
			# cache) : le voisin est reellement vide, sans tenir compte d'un
			# quelconque niveau de coupe - valide car ce cache ne sert jamais
			# pour la couche-frontiere (traitee a part, voir
			# _add_boundary_cube_faces).
			var neighbor_pos: Vector3i = pos + dir
			if grid.get(neighbor_pos, BlockType.EMPTY) != BlockType.EMPTY:
				continue
			var idx := _bucket_for(pos, type, dir)
			var face_color := Color.WHITE
			if idx == 0:
				face_color = _grass_color_for(pos)
			elif idx == 2:
				face_color = _stone_color_for(pos)
			elif idx == 10 or idx == 18:
				face_color = _vein_color_for(pos)
			# "dir" vient d'une boucle "for dir in DIRECTIONS" non typee (Array
			# generique, voir champ DIRECTIONS) : le comparer directement avec
			# ":=" empeche l'inference de type statique de Godot ("Cannot
			# infer the type..."), d'ou le type explicite "bool" ici (meme
			# comparaison que dans _bucket_for, ou "dir" est en revanche un
			# parametre type Vector3i - pas de probleme la-bas).
			var is_top: bool = dir == Vector3i(0, 1, 0)
			var bucket_dict: Dictionary = active_nt[y] if is_top else active_sb[y]
			if not bucket_dict.has(idx):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				bucket_dict[idx] = st
			_add_face(bucket_dict[idx], pos, dir, face_color)

	for y in active_sb.keys():
		var sb_meshes: Dictionary = {}
		for bucket_idx in active_sb[y].keys():
			var mesh := ArrayMesh.new()
			(active_sb[y][bucket_idx] as SurfaceTool).commit(mesh)
			sb_meshes[bucket_idx] = mesh
		_layer_sides_bottom[y] = sb_meshes
	for y in active_nt.keys():
		var nt_meshes: Dictionary = {}
		for bucket_idx in active_nt[y].keys():
			var mesh := ArrayMesh.new()
			(active_nt[y][bucket_idx] as SurfaceTool).commit(mesh)
			nt_meshes[bucket_idx] = mesh
		_layer_natural_top[y] = nt_meshes

	# Plaques d'escalier : independant de "discovered" (un escalier deja
	# creuse est par definition deja connu du joueur), un seul SurfaceTool par
	# couche Y (un seul bucket 13, mais couleur variable par sommet - voir
	# _stair_color_for, meme principe que herbe/pierre/filon).
	#
	# Moitie ELOIGNEE du bloc (x 0.5..1) : totalement VIDE, aucune geometrie -
	# un vrai trou (on voit a travers, vers les blocs/niveaux en dessous),
	# feedback Francois 2026-07-08 ("vu du dessus l'escalier ne marche
	# toujours pas" - le mur plein d'avant cachait le trou).
	#
	# Moitie PROCHE (x 0..0.5) : sa LARGEUR (X, 0..0.5) reste CONSTANTE sur
	# toute la marche - les 4 bandes (STEP_COUNT) sont decoupees le long de
	# Z, la LONGUEUR du bloc (0..1 entier, pas juste le demi-bloc), qui est
	# l'axe de progression de l'escalier (feedback Francois 2026-07-08 : les
	# marches doivent suivre la longueur, pas la largeur - 2 tentatives
	# precedentes decoupaient X, la largeur, par erreur). Chaque bande plus
	# haute que la precedente -> palier bas (bande la plus proche en Z,
	# hauteur 0..0.25), 2 marches intermediaires, palier haut (bande la
	# plus eloignee en Z, hauteur 0..1). Meme decoupage pour TOUTES les
	# cases, quelle que soit leur "piece" (bas/haut/hautbas, conservee dans
	# stair_grid mais pas utilisee ici). Empilees, les paliers hauts d'un
	# niveau touchent les paliers bas du niveau du dessous -> silhouette
	# d'escalier continue en coupe, cote oppose au trou. La colonne garde
	# le meme x/z a chaque niveau (voir doc de stair_grid), ce n'est PAS une
	# rampe walkable, juste une representation lisible.
	# Bucket 13 (eclaire) ou 19 (non eclaire, voir _is_underground) selon si
	# CETTE case d'escalier est vraiment sous un plafond ou encore exposee au
	# soleil (haut d'un escalier tout juste creuse depuis la surface) -
	# Francois 2026-07-08. Un y peut donc desormais contenir les 2 buckets a
	# la fois (ex : escalier qui traverse la limite surface/sous-sol).
	const STEP_COUNT := 4
	var active_stairs: Dictionary = {}  # y -> Dictionary[bucket_idx -> SurfaceTool]
	for pos in stair_grid.keys():
		var y: int = pos.y
		var stair_bucket := 19 if _is_underground(pos) else 13
		if not active_stairs.has(y):
			active_stairs[y] = {}
		if not active_stairs[y].has(stair_bucket):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			active_stairs[y][stair_bucket] = st
		var entry: Dictionary = stair_grid[pos]
		var block_type: int = entry.get("material", BlockType.STONE)
		var stair_color: Color = _stair_color_for(pos, block_type)
		for i in range(STEP_COUNT):
			var z0: float = float(i) / STEP_COUNT
			var z1: float = float(i + 1) / STEP_COUNT
			var step_top: float = float(i + 1) / STEP_COUNT
			_add_box_faces(active_stairs[y][stair_bucket], pos, 0.0, 0.5, 0.0, step_top, z0, z1, stair_color)
	for y in active_stairs.keys():
		var stair_meshes: Dictionary = {}
		for bucket_idx in active_stairs[y].keys():
			var mesh := ArrayMesh.new()
			(active_stairs[y][bucket_idx] as SurfaceTool).commit(mesh)
			stair_meshes[bucket_idx] = mesh
		_layer_stairs[y] = stair_meshes

	_cache_populated = true


## Ajoute le CUBE (parois + dessous + SOL en guise de dessus) des blocs
## decouverts EXACTEMENT au niveau de vue courant - utilise _layer_positions
## pour ne parcourir QUE cette couche (quelques milliers de blocs en moyenne)
## au lieu de tout "discovered". Inconditionnel (les faces sont ajoutees
## meme si le voisin correspondant est plein) : un bloc de terrain intact,
## entoure d'autres blocs pleins, doit quand meme se distinguer comme un
## cube (Francois 2026-07-08 : "il n'y a que le SOL qui s'affiche au lieu
## d'un cube"). Le dessus utilise maintenant le VRAI materiau du SOL (voir
## get_sol/_sol_bucket_and_color_for, modele CUBE+SOL 2026-07-09) au lieu de
## l'ancien "capuchon" sombre generique.
func _add_boundary_cube_faces(surface_tools: Array) -> void:
	if not _layer_positions.has(view_level):
		return
	for pos in _layer_positions[view_level]:
		var type: int = grid.get(pos, BlockType.EMPTY)
		if type == BlockType.EMPTY:
			continue
		for dir in DIRECTIONS:
			if dir == Vector3i(0, 1, 0):
				var sol_info: Array = _sol_bucket_and_color_for(pos)
				_add_face(surface_tools[sol_info[0]], pos, dir, sol_info[1])
				continue
			var idx := _bucket_for(pos, type, dir)
			var face_color := Color.WHITE
			if idx == 10 or idx == 18:
				face_color = _vein_color_for(pos)
			_add_face(surface_tools[idx], pos, dir, face_color)


## Determine dans quelle surface (materiau + face) placer un bloc donne. Le
## dessus terre (herbe, bucket 0) et le dessus pierre (bucket 2) utilisent
## chacun un seul bucket a couleur variable par sommet (pas de damier clair/
## fonce). Un bloc de pierre qui est un filon (vein_grid) passe sur le
## bucket 10 (ou 18 sous plafond, voir _is_underground), sur toutes ses faces
## (dessus ET parois), avant meme de regarder le type - un filon reste un
## filon peu importe la face. Les parois (pas is_top) delegue a
## _paroi_bucket_for, qui choisit entre variante eclairee/non eclairee.
func _bucket_for(pos: Vector3i, type: int, dir: Vector3i) -> int:
	var is_top := dir == Vector3i(0, 1, 0)

	if type == BlockType.STONE and vein_grid.has(pos):
		if not is_top and _is_underground(pos):
			return 18
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
			BlockType.WATER:
				return 12
		return 0

	return _paroi_bucket_for(pos, type)


## Bucket "paroi" (parois laterales + dessous, jamais un vrai dessus) pour un
## bloc donne - dedouble en variante NON ECLAIREE (14-17) si le bloc est
## veritablement sous un plafond (_is_underground), variante ECLAIREE (6-9)
## sinon (paroi tout juste creusee en surface, encore exposee au soleil -
## Francois 2026-07-08). Utilisee par _bucket_for pour les vraies faces
## laterales/dessous.
func _paroi_bucket_for(pos: Vector3i, type: int) -> int:
	var underground := _is_underground(pos)
	match type:
		BlockType.DIRT:
			return 14 if underground else 6
		BlockType.STONE:
			return 15 if underground else 7
		BlockType.WOOD_WALL:
			return 16 if underground else 8
		BlockType.STONE_WALL:
			return 17 if underground else 9
		BlockType.WATER:
			return 12
	return 14 if underground else 6


## Bucket + couleur pour la face du dessus a la couche-frontiere (voir
## _add_boundary_cube_faces), a partir du VRAI materiau du SOL (get_sol,
## modele CUBE+SOL 2026-07-09). Buckets materiau NORMAUX (2026-07-10,
## Francois : "enleve le magenta des discovered - on doit voir le CUBE et
## son materiau, pas plus") - meme mapping que _bucket_for pour un dessus
## normal, le tag DEBUG_SOL_TINT/bucket 20 est retire (modele CUBE+SOL
## confirme en jeu).
func _sol_bucket_and_color_for(pos: Vector3i) -> Array:
	var sol_type: int = get_sol.call(pos)
	if sol_type == BlockType.STONE and vein_grid.has(pos):
		return [10, _vein_color_for(pos)]
	match sol_type:
		BlockType.DIRT:
			return [0, _grass_color_for(pos)]
		BlockType.STONE:
			return [2, _stone_color_for(pos)]
		BlockType.WOOD_WALL:
			return [4, WOOD_WALL_COLOR]
		BlockType.STONE_WALL:
			return [5, STONE_WALL_COLOR]
		BlockType.WATER:
			return [12, WATER_COLOR]
	return [11, UNDISCOVERED_COLOR]


## Assombrit une couleur (utilise pour les parois des trous/murs, effet
## d'ombrage simple sans veritable eclairage)
func _darken(color: Color) -> Color:
	return Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, color.a)


## Les StandardMaterial3D ne sont pas recrees a chaque rebuild_mesh() (donc a
## chaque minage/construction) : seul le bucket 12 (eau/glace) depend d'un
## etat qui change reellement (is_frozen, voir TemperatureSystem.gd) - tous
## les autres sont des couleurs fixes. Construits une seule fois puis mis en
## cache ; seule la couleur du bucket 12 est mise a jour a chaque appel.
## Buckets 14-19 : variantes NON ECLAIREES (unshaded) des buckets paroi/
## filon/escalier (6-9/10/13), utilisees pour un bloc veritablement sous un
## plafond (_is_underground, voir _paroi_bucket_for) - le
## bucket 11 (non decouvert) est lui aussi TOUJOURS non eclaire (par
## definition quasi toujours sous plafond, voir "discovered") - Francois
## 2026-07-08 : le soleil du cycle jour/nuit ne doit pas affecter un bloc qui
## n'y est jamais expose.
func _get_bucket_materials() -> Dictionary:
	if _bucket_materials.is_empty():
		var dirt_dark := Color(0.58, 0.34, 0.10)  # garde pour bucket 6 (paroi terre)
		var stone_dark := Color(0.48, 0.50, 0.56)  # garde pour bucket 3 (inutilise) et bucket 7 (paroi)
		_bucket_materials = {
			0: _make_vertex_color_material(),
			1: _make_material(dirt_dark),  # inutilise (voir plus haut)
			2: _make_vertex_color_material(),
			3: _make_material(stone_dark),  # inutilise (voir plus haut)
			4: _make_material(WOOD_WALL_COLOR),
			5: _make_material(STONE_WALL_COLOR),
			6: _make_material(_darken(dirt_dark)),
			7: _make_material(_darken(stone_dark)),
			8: _make_material(_darken(WOOD_WALL_COLOR)),
			9: _make_material(_darken(STONE_WALL_COLOR)),
			10: _make_vertex_color_material(),
			11: _make_unshaded_material(UNDISCOVERED_COLOR),  # gris uniforme, jamais eclaire
			12: _make_material(WATER_COLOR),
			13: _make_vertex_color_material(),  # couleur variable par sommet, voir _stair_color_for
			14: _make_unshaded_material(_darken(dirt_dark)),
			15: _make_unshaded_material(_darken(stone_dark)),
			16: _make_unshaded_material(_darken(WOOD_WALL_COLOR)),
			17: _make_unshaded_material(_darken(STONE_WALL_COLOR)),
			18: _make_unshaded_vertex_color_material(),
			19: _make_unshaded_vertex_color_material(),
			20: _make_unshaded_vertex_color_material(),  # inutilise (ancien bucket DEBUG SOL)
		}
	# L'eau devient de la glace (couleur claire) quand is_frozen est vrai -
	# seule couleur qui doit rester a jour a chaque appel, modifiee en place
	# plutot que de recreer le materiau.
	_bucket_materials[12].albedo_color = ICE_COLOR if is_frozen else WATER_COLOR
	return _bucket_materials


## Cree un materiau simple, dans la couleur donnee. Eclairage reel (mode par
## defaut de StandardMaterial3D, pas SHADING_MODE_UNSHADED) pour que le
## terrain reagisse au cycle jour/nuit (DayNightCycle.gd) - un materiau
## "unshaded" ignore totalement la lumiere/les ombres. roughness=1/
## metallic=0 evite les reflets speculaires pour garder un rendu plat/mat
## coherent avec le style low-poly du jeu, tout en recevant lumiere
## directionnelle + ombres + lumiere ambiante.
func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## Variante NON ECLAIREE de _make_material - meme reglages, mais
## shading_mode=UNSHADED : la couleur reste fixe quelle que soit l'heure/la
## position du soleil (DayNightCycle.gd), pour un bloc veritablement sous un
## plafond qui ne devrait jamais recevoir de lumiere naturelle (Francois
## 2026-07-08, voir _is_underground).
func _make_unshaded_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Materiau pour le bucket 0 (herbe), qui lit la couleur par sommet (definie
## via SurfaceTool.set_color dans _add_face) au lieu d'une seule couleur
## fixe - c'est ce qui permet la variation continue par case. Meme passage
## a l'eclairage reel que _make_material ci-dessus.
func _make_vertex_color_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## Variante NON ECLAIREE de _make_vertex_color_material (buckets 18/19 -
## filon/escalier sous plafond, voir _is_underground) - meme lecture de la
## couleur par sommet, mais insensible au soleil/cycle jour-nuit.
func _make_unshaded_vertex_color_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Ajoute un quad (2 triangles) sur la face "dir" du bloc a la position "pos".
## face_color : couleur de sommet, utilisee uniquement par le bucket
## "herbe"/"pierre"/"filon" dont le materiau lit vertex_color_use_as_albedo ;
## ignoree par les autres materiaux, donc sans effet pour eux.
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


## Ajoute les 6 faces d'une "boite partielle" a l'interieur d'une case,
## bornee a [x0,x1] x [y0,y1] x [z0,z1] (chaque borne entre 0 et 1) -
## utilise pour les 4 sous-boites (bandes) de chaque case d'escalier (voir
## _build_layer_cache). Meme construction que _add_face mais
## parametree sur les 3 axes au lieu de 0..1 fixe, et dessine les 6
## directions d'un coup (pas de culling - une sous-boite isolee n'a
## normalement pas de voisin plein contre lequel se cacher).
func _add_box_faces(st: SurfaceTool, pos: Vector3i, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, color: Color) -> void:
	var p := Vector3(pos.x, pos.y, pos.z)
	var faces := [
		[Vector3(1, 0, 0), [p + Vector3(x1, y0, z0), p + Vector3(x1, y1, z0), p + Vector3(x1, y1, z1), p + Vector3(x1, y0, z1)]],
		[Vector3(-1, 0, 0), [p + Vector3(x0, y0, z1), p + Vector3(x0, y1, z1), p + Vector3(x0, y1, z0), p + Vector3(x0, y0, z0)]],
		[Vector3(0, 1, 0), [p + Vector3(x0, y1, z0), p + Vector3(x0, y1, z1), p + Vector3(x1, y1, z1), p + Vector3(x1, y1, z0)]],
		[Vector3(0, -1, 0), [p + Vector3(x1, y0, z0), p + Vector3(x1, y0, z1), p + Vector3(x0, y0, z1), p + Vector3(x0, y0, z0)]],
		[Vector3(0, 0, 1), [p + Vector3(x1, y0, z1), p + Vector3(x1, y1, z1), p + Vector3(x0, y1, z1), p + Vector3(x0, y0, z1)]],
		[Vector3(0, 0, -1), [p + Vector3(x0, y0, z0), p + Vector3(x0, y1, z0), p + Vector3(x1, y1, z0), p + Vector3(x1, y0, z0)]],
	]
	for face in faces:
		var normal: Vector3 = face[0]
		var verts: Array = face[1]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(color)
			st.set_normal(normal)
			st.add_vertex(verts[idx])
