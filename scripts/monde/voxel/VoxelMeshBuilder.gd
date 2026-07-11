extends RefCounted
## Construction du mesh du terrain : culling des faces cachees, choix du
## "bucket" (materiau/couleur) par bloc, couleurs herbe/pierre/filon, ajout
## des quads.
##
## "rebuild(...)" copie les parametres recus dans ses propres membres (memes
## noms qu'un acces direct aux champs de VoxelWorld.gd : grid, discovered,
## view_level, WIDTH, DEPTH, DIRECTIONS, is_frozen, has_snow,
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
## Primitives geometrie/couleur PURES (aucun etat de cache) - extraites vers
## VoxelBlockAppearance.gd (revue de code C23, 2026-07-11 : deplacement
## PARTIEL volontaire, voir sa doc de tete - le decoupage par bucket et toute
## l'orchestration de cache restent ici).
const VoxelBlockAppearanceScript := preload("res://scripts/monde/voxel/VoxelBlockAppearance.gd")

# Duplique de l'enum BlockType de VoxelWorld.gd (memes valeurs/ordre exacts -
# EMPTY=0, DIRT=1, STONE=2, WOOD_WALL=3, STONE_WALL=4, WATER=5). Necessaire
# car un enum defini dans un script ne se resout pas depuis un autre script
# sans creer une reference typee croisee (voir note en tete de fichier) - les
# entiers stockes dans "grid" restent valides quel que soit l'enum utilise
# pour les nommer. ATTENTION : si le BlockType de VoxelWorld.gd change un
# jour (ajout/retrait/reordonnancement), reproduire le changement ici.
enum BlockType { EMPTY, DIRT, STONE, WOOD_WALL, STONE_WALL, WATER }

## Modele CUBE+SOL (memoire project_forgotten_caves_cube_sol_model.md,
## section 2) : a la couche-frontiere (_add_boundary_cube_faces), un bloc se
## dessine en 2 boites empilees dans le meme [Y,Y+1] - SOL_THICKNESS =
## fraction (0..1) occupee par la boite SOL au bas de la case, le CUBE
## occupant le reste au-dessus. SOL_DARKEN_FACTOR = assombrissement du SOL
## par rapport au CUBE (regle "penombre" du modele, jamais une couleur
## inventee). Uniquement utilise a la couche-frontiere - ailleurs (surface
## intacte, sol d'un trou vu de loin) SOL et CUBE partagent le meme materiau
## hors coupe, donc une seule boite suffit visuellement.
const SOL_THICKNESS := 0.2
const SOL_DARKEN_FACTOR := 0.65

## Les 4 directions horizontales (hors haut/bas) - utilisees par
## _emit_sol_only_box pour culler les faces laterales d'une boite SOL cachees
## par une case voisine (perf 2026-07-11 : cette boucle - 40261 cases mesurees
## - dessinait ses 6 faces sans jamais verifier les voisins, contrairement aux
## CUBE qui font deja ce culling - voir memoire freeze/perf rebuild complet).
const HORIZONTAL_DIRECTIONS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

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

## Taille (en colonnes) d'un "chunk" pour le cache de geometrie par couche Y
## (voir _layer_sides_bottom et consorts) - fix definitif 2026-07-10 de la
## regression "terrain transparent" (memoire) : une 1ere tentative de
## restreindre la reconstruction par colonne, SANS repartitionner le cache
## lui-meme (qui restait agrege par NIVEAU Y entier, toutes colonnes
## confondues), effacait un niveau Y complet puis ne le remplissait qu'avec
## les quelques colonnes mutees - le reste de la carte a ce niveau perdait sa
## geometrie. Desormais, le cache est partitionne par (Y, CHUNK) : une
## mutation invalide/reconstruit toujours un ou plusieurs chunks ENTIERS
## (jamais une sous-boite arbitraire), donc jamais de "trou" de geometrie.
## 16 = compromis (WIDTH/DEPTH=250 -> ~16x16=256 chunks) entre le nombre de
## MeshInstance3D generes (voir _layer_mesh_instances) et le cout de
## reconstruction d'un chunk entier (jusqu'a 16*16=256 colonnes, tres
## largement moins que WIDTH*DEPTH=62 500).
const CHUNK_SIZE := 16

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
## Bool, pas un float continu depuis 2026-07-11 (voir doc de
## TemperatureSystem.SNOW_VISIBLE_THRESHOLD) : "y a-t-il de la neige visible
## en ce moment", pas "combien" - le degrade continu couteux a ete remplace
## par 2 couleurs distinctes (voir VoxelBlockAppearance.grass_color_for/
## stone_color_for).
var has_snow: bool
var climate_id: String
var season_id: String
var terrain_noise: FastNoiseLite
## Cache des 13 materiaux de bucket - voir _get_bucket_materials plus bas.
var _bucket_materials: Dictionary = {}
var stone_noise: FastNoiseLite
var DIRECTIONS: Array
var mesh_instance: MeshInstance3D
var get_top_block_y: Callable
## Cache TEMPORAIRE de get_top_block_y, actif SEULEMENT le temps d'un appel a
## _build_boundary_mesh() OU _build_layer_cache() (voir leur doc) - perf
## 2026-07-11 v2/v3, I89. Different d'un essai precedent (cache persistant
## dans VoxelWorld.gd, annule le meme jour : regression severe sur la
## molette) : celui-la couvrait AUSSI la boucle "SOL" (dans les deux
## fonctions), qui ne visite chaque colonne qu'UNE FOIS (aucun gain, cout de
## Dictionary pur ajoute a un passage deja fait une seule fois). Ici la
## portee reste reduite a chaque fonction individuellement, mais couvre
## desormais aussi _build_layer_cache() (v3, apres regression confirmee -
## freeze periodique ~2.3s a chaque appel PLEINE CARTE de set_climate_state,
## voir memoire) : sa passe "naturelle" (couleur des faces exposees de TOUT
## "discovered") appelle _ao_darken()/_grass_color_for()/_stone_color_for()
## pour chaque bloc ET ses 4 voisins - memes colonnes reinterrogees par des
## blocs adjacents, meme recouvrement reel que dans _build_boundary_mesh().
## Vide et repeuple a CHAQUE appel de l'une ou l'autre fonction, jamais
## persiste entre deux reconstructions ni partage entre les deux fonctions -
## donc aucun risque de valeur perimee.
var _scoped_top_cache: Dictionary = {}
## Vraie Callable (VoxelWorld.get_top_block_y) sauvegardee le temps du cache
## temporaire ci-dessus - voir _cached_top_scoped/_build_boundary_mesh/
## _build_layer_cache.
var _scoped_top_real_fn: Callable
## Materiau du SOL a une position donnee (voir VoxelWorld.get_sol, memoire
## "Modele CUBE+SOL" 2026-07-08) - utilise par _add_boundary_cube_faces pour
## colorer la face du dessus a la couche-frontiere avec le VRAI materiau du
## SOL plutot que le capuchon sombre generique d'avant.
var get_sol: Callable
## Positions SOL explicitement figees (voir VoxelWorld.sol_grid, regle
## Francois 2026-07-10 : "la couche de terre de surface... c'est un objet
## reel") - independantes du sommet courant de leur colonne, contrairement au
## SOL "dynamique" de fond de trou (voir _build_layer_cache/
## _add_boundary_sol_only_faces, qui utilisent celle-ci EN PLUS de la regle
## dynamique top_y+1, pas a sa place).
var sol_grid: Dictionary = {}
## Index de VoxelWorld.sol_grid PAR COLONNE (voir sa doc dans VoxelWorld.gd)
## - perf 2026-07-10 : evite un balayage complet de sol_grid (jusqu'a ~62 500
## entrees) dans _build_layer_cache() quand la reconstruction est restreinte
## a quelques chunks (voir CHUNK_SIZE/_dirty_chunk_keys). Utilise pour
## reconstruire un CHUNK ENTIER a la fois, jamais une sous-boite de colonnes
## (voir memoire sur la regression "terrain transparent").
var sol_grid_by_xz: Dictionary = {}
## Index de "discovered" PAR COLONNE (voir doc dans VoxelWorld.gd) - meme
## raison de perf/meme usage, pour la boucle principale de
## _build_layer_cache().
var discovered_by_xz: Dictionary = {}

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
##
## PARTITIONNE PAR (Y, CHUNK) depuis le fix definitif 2026-07-10 (voir
## CHUNK_SIZE) : y -> chunk (Vector2i, voir _chunk_key) -> bucket_idx ->
## ArrayMesh. Chaque entree ne couvre QUE les colonnes de ce chunk - c'est ce
## qui permet d'invalider/reconstruire un chunk entier sans jamais toucher
## aux autres colonnes du meme niveau Y (voir memoire "terrain transparent").
var _layer_sides_bottom: Dictionary = {}  # y -> chunk -> Dictionary[bucket_idx -> ArrayMesh]
var _layer_natural_top: Dictionary = {}   # y -> chunk -> Dictionary[bucket_idx -> ArrayMesh]
## Positions decouvertes non-vides, regroupees par (Y, CHUNK) (construit en
## meme temps que le cache ci-dessus) - permet a _add_boundary_cube_faces de
## ne reparcourir QUE la couche-frontiere (quelques milliers de blocs en
## moyenne) au lieu de tout "discovered" (117 138 dans l'exemple mesure).
var _layer_positions: Dictionary = {}     # y -> chunk -> Array[Vector3i]
## Cache des plaques d'escalier, meme principe que _layer_sides_bottom mais
## PAS chunke (bucket 13 eclaire / 19 non eclaire, voir _is_underground) :
## construit dans _build_layer_cache() a partir de stair_grid, TOUJOURS
## restreint par Y seul (jamais par colonne) - un escalier est un evenement
## rare (cout mesure ~0ms meme non restreint), pas besoin de la complexite
## du chunking ici.
var _layer_stairs: Dictionary = {}        # int y -> Dictionary[bucket_idx -> ArrayMesh]
## Cache des cases "SOL SEUL" naturelles (CUBE vide, SOL herbe/eau synthetise
## juste au-dessus du vrai sommet de chaque colonne, voir VoxelWorld.get_sol
## regle 2) - meme principe que _layer_sides_bottom/_layer_natural_top
## (PARTITIONNE PAR (Y, CHUNK), meme raison) mais pour une case qui n'a
## JAMAIS d'entree dans "discovered" elle-meme (seul le bloc SOLIDE juste en
## dessous en a une), donc construit par un balayage PAR COLONNE (dans les
## bornes du chunk) plutot que "discovered.keys()" - voir _build_layer_cache.
## Necessaire depuis que generate_flat_terrain genere a nouveau la surface
## comme "CUBE vide + SOL" (Francois 2026-07-10 : "j'ai exige que TOUS les
## blocs aient la meme structure CUBE + SOL", y compris la surface jamais
## minee) : sans ce cache, la surface ne serait visible QUE quand view_level
## tombe pile dessus (deja couvert par _add_boundary_sol_only_faces, qui
## reste le seul chemin pour la couche-frontiere elle-meme) - jamais quand on
## regarde le relief depuis plus haut, ce qui avait fait "disparaitre le
## relief" lors d'une premiere tentative 2026-07-09 (le relief existait dans
## la grille mais son SOL naturel n'etait recompose nulle part en dessous de
## la coupe).
var _layer_sol_only: Dictionary = {}      # y -> chunk -> Dictionary[bucket_idx -> ArrayMesh]
## Vrai des qu'une reconstruction COMPLETE du cache a eu lieu au moins une
## fois (generation initiale) - conditionne si une invalidation LOCALE
## (dirty_y_min/max, voir invalidate_cache) est possible : sans premiere
## reconstruction complete, il n'existe rien a "patcher" localement.
var _cache_populated: bool = false
## Vrai si _build_layer_cache() doit tourner au prochain _rebuild_mesh_body()
## (positionne par invalidate_cache, quelle que soit la portee - complete ou
## locale). Remplace l'ancien garde "not _cache_populated", qui ne pouvait
## PAS detecter une invalidation locale (_cache_populated reste vrai dans ce
## cas - voir doc de invalidate_cache).
var _needs_cache_rebuild: bool = true
## Portee de la reconstruction en attente (voir invalidate_cache/
## _build_layer_cache) - -1/-1 = COMPLETE (toute la carte), sinon = seuls les
## niveaux Y dans [min,max] doivent etre recalcules, le reste du cache
## reste tel quel.
var _rebuild_dirty_min: int = -1
var _rebuild_dirty_max: int = -1
## Bornes colonne (X/Z) de la boucle de secours WIDTH*DEPTH dans
## _build_layer_cache (case sans entree sol_grid explicite, voir
## _emit_sol_only_box) - -1/-1 = pas de restriction (toute la carte, boucle
## complete). Independant de dirty_y_min/max : cette boucle appelle
## get_top_block_y.call(x,z) en direct (pas indexable par Y a l'avance), donc
## seule une restriction en X/Z (colonnes reellement touchees par la mutation,
## +1 case de marge) peut la borner - voir VoxelWorld.rebuild_mesh().
var _rebuild_dirty_x_min: int = -1
var _rebuild_dirty_x_max: int = -1
var _rebuild_dirty_z_min: int = -1
var _rebuild_dirty_z_max: int = -1

## Un MeshInstance3D PERSISTANT par (Y, CHUNK) (perf critique 250x250,
## Francois 2026-07-10 - 3e tentative : la 1ere, "mesh complet mis en cache
## par view_level", n'aidait qu'a REVENIR sur un niveau deja vu ; la 2e, "un
## seul MeshInstance3D par Y", a permis un gros gain initial mais empechait
## toute restriction par colonne SANS regression (voir memoire "terrain
## transparent" - le cache agrege par Y entier ne pouvait pas etre reconstruit
## partiellement sans perdre des colonnes). Desormais partitionne par (Y,
## CHUNK) comme le reste du cache - chaque noeud ne porte que la geometrie
## d'UN chunk a UN niveau Y, ce qui permet d'invalider/reconstruire un chunk
## a la fois sans jamais recomposer les autres. PERSISTE A TRAVERS LES
## MUTATIONS (memes raisons perf que la version precedente - Francois
## 2026-07-10 : "creuser (trou) est maintenant trop long et freeze un peu le
## jeu" - seul le CONTENU ".mesh" de chaque noeud change, voir
## _ensure_layer_instances/_layer_instances_stale).
## Cle = y (int) -> chunk (Vector2i) -> le noeud (enfant du meme parent que
## mesh_instance, donc detruit avec lui).
var _layer_mesh_instances: Dictionary = {}
## Vrai si _layer_mesh_instances doit etre reconstruit/mis a jour au prochain
## _rebuild_mesh_body() (positionne par invalidate_cache) - remplace l'ancien
## "is_empty()" comme garde, puisque le dictionnaire n'est plus vide entre 2
## mutations (les noeuds sont conserves, voir doc ci-dessus).
var _layer_instances_stale: bool = true

## Mesh de la couche-frontiere (voir _add_boundary_cube_faces/
## _add_boundary_sol_only_faces), en cache PAR VALEUR de view_level - deja peu
## couteux a construire (borne a la taille d'UNE seule couche, jamais a la
## profondeur), mais autant eviter de le refaire pour un simple aller-retour
## sur le meme niveau. Affiche sur l'ancien "mesh_instance" - le seul
## MeshInstance3D dont le contenu change reellement a chaque scroll.
var _boundary_mesh_cache: Dictionary = {}

## Plaques d'escalier (voir _layer_stairs) : contrairement au reste, TOUJOURS
## visibles quel que soit view_level (un escalier deja creuse est par
## definition deja connu) - un seul noeud PERSISTANT (meme raison que
## _layer_mesh_instances ci-dessus - reutilise, jamais detruit/recree a chaque
## minage), juste son ".mesh" est remplace quand stale.
var _stairs_mesh_instance: MeshInstance3D = null
var _stairs_stale: bool = true


## Cle de chunk (Vector2i) pour une colonne (x,z) - voir doc de CHUNK_SIZE.
## Division entiere sans souci de signe : x/z restent toujours >= 0 sur toute
## la duree du jeu (WIDTH/DEPTH bornent la carte a partir de 0).
func _chunk_key(x: int, z: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(x / CHUNK_SIZE, z / CHUNK_SIZE)


## Bornes colonne [x0,x1]x[z0,z1] (inclusives, deja bridees a
## [0,WIDTH-1]/[0,DEPTH-1]) couvertes par un chunk donne - voir doc de
## CHUNK_SIZE. Utilise pour reconstruire un chunk ENTIER (jamais une
## sous-boite) quand il est marque sale.
func _chunk_bounds(chunk: Vector2i) -> Array:
	var x0: int = chunk.x * CHUNK_SIZE
	var x1: int = mini(WIDTH - 1, x0 + CHUNK_SIZE - 1)
	var z0: int = chunk.y * CHUNK_SIZE
	var z1: int = mini(DEPTH - 1, z0 + CHUNK_SIZE - 1)
	return [x0, x1, z0, z1]


## Ensemble (sans doublon) des chunks qui recouvrent la boite de colonnes
## [x_min,x_max]x[z_min,z_max] (voir _rebuild_dirty_x/z_min/max) - typiquement
## 1 chunk, parfois jusqu'a 4 si la boite (marge 1 case autour de la mutation)
## chevauche une frontiere de chunk. Renvoie un tableau VIDE si x_min == -1
## (aucune restriction X/Z fournie) - voir appelants pour le filet de
## securite associe (traiter comme "portee non precisee", jamais une
## sous-boite partielle).
func _dirty_chunk_keys(x_min: int, x_max: int, z_min: int, z_max: int) -> Array:
	if x_min == -1:
		return []
	var result: Dictionary = {}
	for x in range(maxi(0, x_min), mini(WIDTH - 1, x_max) + 1):
		for z in range(maxi(0, z_min), mini(DEPTH - 1, z_max) + 1):
			result[_chunk_key(x, z)] = true
	return result.keys()


## Invalide le cache par couche (voir sa doc) - a appeler des qu'une mutation
## reelle rend la geometrie/les couleurs perimees. dirty_y_min/dirty_y_max
## (par defaut -1/-1) : Francois 2026-07-10, "perf creuser pas bonne" - miner
## UN SEUL bloc invalidait jusque-la TOUTE la carte (tous les niveaux Y),
## alors qu'une mutation ne touche jamais que quelques niveaux (voir doc de
## VoxelWorld.rebuild_mesh). Si une plage precise est donnee ET qu'une
## reconstruction complete a deja eu lieu au moins une fois (_cache_populated),
## SEULES les entrees de cette plage sont effacees - le reste du cache (et des
## noeuds _layer_mesh_instances/_boundary_mesh_cache correspondants) reste
## valable tel quel, jamais retouche. Sinon (portee -1/-1, ou tout premier
## appel avant la toute premiere construction), comportement historique :
## reconstruction COMPLETE au prochain _rebuild_mesh_body(). Les noeuds
## _layer_mesh_instances/_stairs_mesh_instance eux-memes ne sont JAMAIS
## detruits ici (Francois 2026-07-10 "trou... freeze") - seul leur CONTENU
## est marque perime, mis a jour EN PLACE par _ensure_layer_instances/
## _ensure_stairs_instance.
##
## PARTITIONNE PAR (Y, CHUNK) depuis le fix definitif du meme jour (voir
## CHUNK_SIZE/_dirty_chunk_keys) : quand une portee Y ET X/Z sont toutes deux
## fournies (cas normal - remove_block/build_block/dig_stairs), seuls les
## CHUNKS ENTIERS recouvrant la boite X/Z sont effaces pour chaque Y de la
## plage - jamais une sous-boite de colonnes (voir memoire "terrain
## transparent" : la 1ere tentative de restriction par colonne effacait un
## niveau Y ENTIER puis ne le reconstruisait que partiellement, laissant le
## reste du niveau sans geometrie). Si X/Z ne sont pas fournis (cas rare, ne
## devrait pas arriver avec les appelants actuels), filet de securite :
## efface le niveau Y ENTIER (tous chunks), comportement historique sans
## risque.
func invalidate_cache(dirty_y_min: int = -1, dirty_y_max: int = -1) -> void:
	var do_full: bool = dirty_y_min == -1 or not _cache_populated
	if do_full and OS.is_debug_build():
		# Mesure TEMPORAIRE (diagnostic freeze periodique, 2026-07-11 - a
		# retirer une fois la cause confirmee) : identifie l'appelant exact
		# d'un rebuild NON restreint (pleine carte), pour ne plus deviner.
		print("[Perf] invalidate_cache PLEINE CARTE - pile d'appel :")
		for frame in get_stack():
			print("    ", frame.get("source", "?"), ":", frame.get("line", "?"), " ", frame.get("function", "?"))
	if do_full:
		_layer_sides_bottom.clear()
		_layer_natural_top.clear()
		_layer_positions.clear()
		_layer_stairs.clear()
		_layer_sol_only.clear()
		_boundary_mesh_cache.clear()
		_rebuild_dirty_min = -1
		_rebuild_dirty_max = -1
	else:
		var chunks: Array = _dirty_chunk_keys(_rebuild_dirty_x_min, _rebuild_dirty_x_max, _rebuild_dirty_z_min, _rebuild_dirty_z_max)
		for y in range(dirty_y_min, dirty_y_max + 1):
			if chunks.is_empty():
				# Filet de securite (voir doc ci-dessus) - efface le niveau Y
				# ENTIER, jamais une sous-boite.
				_layer_sides_bottom.erase(y)
				_layer_natural_top.erase(y)
				_layer_positions.erase(y)
				_layer_sol_only.erase(y)
			else:
				if _layer_sides_bottom.has(y):
					for chunk in chunks:
						(_layer_sides_bottom[y] as Dictionary).erase(chunk)
				if _layer_natural_top.has(y):
					for chunk in chunks:
						(_layer_natural_top[y] as Dictionary).erase(chunk)
				if _layer_positions.has(y):
					for chunk in chunks:
						(_layer_positions[y] as Dictionary).erase(chunk)
				if _layer_sol_only.has(y):
					for chunk in chunks:
						(_layer_sol_only[y] as Dictionary).erase(chunk)
			_layer_stairs.erase(y)  # jamais chunke (voir sa doc) - efface en entier pour ce Y
			_boundary_mesh_cache.erase(y)
		_rebuild_dirty_min = dirty_y_min
		_rebuild_dirty_max = dirty_y_max
	_needs_cache_rebuild = true
	_layer_instances_stale = true
	_stairs_stale = true


## Point d'entree, appele par VoxelWorld.rebuild_mesh() (facade fine).
## Recopie l'etat necessaire puis reconstruit le mesh (voir _rebuild_mesh_body).
## p_grid_changed (true par defaut, comportement historique) : si vrai, le
## cache par couche est invalide avant reconstruction (voir sa doc) - a
## laisser a true partout SAUF depuis VoxelWorld.set_view_level(), le seul
## appelant qui ne fait QUE changer le niveau de vue sans toucher
## grid/discovered/climat/saison/neige.
func rebuild(p_grid: Dictionary, p_discovered: Dictionary, p_vein_system: VoxelVeinsScript,
		p_view_level: int, p_width: int, p_depth: int, p_is_frozen: bool,
		p_has_snow: bool, p_climate_id: String, p_season_id: String,
		p_terrain_noise: FastNoiseLite, p_stone_noise: FastNoiseLite,
		p_directions: Array, p_mesh_instance: MeshInstance3D,
		p_get_top_block_y: Callable, p_stair_grid: Dictionary, p_grid_changed: bool = true,
		p_get_sol: Callable = Callable(), p_sol_grid: Dictionary = {},
		p_dirty_y_min: int = -1, p_dirty_y_max: int = -1,
		p_discovered_by_xz: Dictionary = {}, p_sol_grid_by_xz: Dictionary = {},
		p_dirty_x_min: int = -1, p_dirty_x_max: int = -1,
		p_dirty_z_min: int = -1, p_dirty_z_max: int = -1) -> void:
	grid = p_grid
	discovered = p_discovered
	sol_grid = p_sol_grid
	discovered_by_xz = p_discovered_by_xz
	sol_grid_by_xz = p_sol_grid_by_xz
	vein_system = p_vein_system
	vein_grid = p_vein_system.vein_grid
	stair_grid = p_stair_grid
	view_level = p_view_level
	WIDTH = p_width
	DEPTH = p_depth
	is_frozen = p_is_frozen
	has_snow = p_has_snow
	climate_id = p_climate_id
	season_id = p_season_id
	terrain_noise = p_terrain_noise
	stone_noise = p_stone_noise
	DIRECTIONS = p_directions
	mesh_instance = p_mesh_instance
	get_top_block_y = p_get_top_block_y
	get_sol = p_get_sol
	_rebuild_dirty_x_min = p_dirty_x_min
	_rebuild_dirty_x_max = p_dirty_x_max
	_rebuild_dirty_z_min = p_dirty_z_min
	_rebuild_dirty_z_max = p_dirty_z_max
	if p_grid_changed:
		invalidate_cache(p_dirty_y_min, p_dirty_y_max)
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


## Assombrissement d'arete/coin ("AO", test perf demande par Francois
## 2026-07-10) SANS geometrie supplementaire - contrairement a la tentative
## precedente de tracer les aretes en vraies faces (desastre de perf), ceci
## reutilise juste la couleur par sommet DEJA calculee (herbe/pierre) : aucun
## cout de dessin en plus, juste quelques lectures/calculs par face.
## 2 sources combinees :
## 1) Relief : assombrit la ou le sommet de colonne differe reellement d'un
##    voisin (bord de trou, falaise, marche) - invisible sur du plat pur.
## 2) CORRIGE (2e essai encore invisible, Francois : "je suis a une layer de
##    terre, aucun indice visuel sur les limites de bloc") : le bruit
##    Perlin deja utilise pour l'herbe (_noise_modulated_color) varie trop
##    doucement d'une case a l'autre pour qu'on distingue une case de sa
##    voisine, meme sans aucune difference de relief. Un hash ENTIER de
##    (x,z) - pas un bruit continu - change radicalement d'une case a la
##    suivante : c'est ce qui cree un vrai "damier" visible de case en case,
##    y compris sur du terrain plat.
func _ao_darken(color: Color, pos: Vector3i) -> Color:
	return VoxelBlockAppearanceScript.ao_darken(color, pos, get_top_block_y)


## Couleur de l'herbe (dessus terre) a une position donnee. Exposee au ciel :
## couleur de base du climat/saison actuels moduleee par un bruit continu
## (+/- environ 12% de luminosite), variation douce case par case au lieu
## d'un damier clair/fonce. Sous-sol (voir _is_underground) : le climat/la
## saison n'ont pas de sens pour une case jamais exposee au ciel - couleur
## de terre fixe (DIRT_UNDERGROUND_BASE) assombrie en "penombre" a la place
## (feedback Francois 2026-07-08).
func _grass_color_for(pos: Vector3i) -> Color:
	return VoxelBlockAppearanceScript.grass_color_for(pos, terrain_noise, climate_id, season_id, has_snow,
			get_top_block_y, DIRT_UNDERGROUND_BASE, PENOMBRE_FACTOR, SNOW_COLOR)


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
	return VoxelBlockAppearanceScript.stone_color_for(pos, stone_noise, has_snow, get_top_block_y,
			STONE_BASE, SNOW_COLOR, PENOMBRE_FACTOR)


## Couleur UNIFORME du dessus d'un CUBE a la couche-frontiere (voir
## _add_boundary_cube_faces) - JAMAIS la teinte herbe/climat, contrairement a
## _grass_color_for/_stone_color_for qui basculent en couleur climat/saison
## quand "pos" EST le vrai sommet de sa colonne (cas normal pour elles,
## utilisees pour un dessus naturellement expose). Un CUBE reste un CUBE
## meme quand la coupe tombe pile sur une colonne jamais minee - Francois
## 2026-07-10 : "le CUBE doit etre une seule couleur uniforme sur toutes ses
## faces, dessus compris" (la teinte herbe est reservee au SOL, deja
## dessine a part par la boite SOL de cette meme fonction).
func _cube_top_color_for(pos: Vector3i, type: int) -> Color:
	return VoxelBlockAppearanceScript.cube_top_color_for(pos, type, BlockType.STONE, stone_noise, terrain_noise,
			STONE_BASE, DIRT_UNDERGROUND_BASE, PENOMBRE_FACTOR)


## Vrai si la case n'a plus de ciel ouvert au-dessus (encore un bloc plein
## entre elle et le sommet reel de la colonne) - definition de "sous-sol"
## utilisee pour la penombre (_apply_penombre), choisie par Francois
## 2026-07-08 : couvre aussi bien une poche fraichement minee que de la
## roche jamais decouverte en profondeur, sans notion de hauteur fixe.
func _is_underground(pos: Vector3i) -> bool:
	return VoxelBlockAppearanceScript.is_underground(pos, get_top_block_y)


## Assombrit une couleur de materiau DEJA calculee (PENOMBRE_FACTOR) sans en
## changer la teinte - ne remplace jamais par une couleur generique, pour
## rester correct avec de futurs materiaux de couleurs differentes.
func _apply_penombre(color: Color) -> Color:
	return VoxelBlockAppearanceScript.apply_penombre(color, PENOMBRE_FACTOR)


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
	return VoxelBlockAppearanceScript.vein_color_for(pos, vein_grid)


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
	# _sol_bucket_and_color_for). Ces 21 buckets sont repartis dans PLUSIEURS
	# MeshInstance3D depuis 2026-07-10 (voir _layer_mesh_instances/
	# _boundary_mesh_cache/_stairs_mesh_instance ci-dessus), plus le meme
	# gaspillage de bucket vide/reindexation possible dans chacun (voir
	# _get_bucket_materials).

	# Cache par couche Y (voir sa doc plus haut) : reconstruit UNE SEULE FOIS
	# par mutation reelle (grid_changed=true, voir rebuild()), jamais a cause
	# d'un simple changement de niveau de vue - le coeur du gain de perf
	# (2026-07-08). Depuis 2026-07-10, _rebuild_dirty_min/max restreint ce
	# recalcul aux SEULS niveaux Y reellement touches par la mutation
	# (minage/construction localise) au lieu de toute la carte a chaque fois -
	# voir doc de invalidate_cache.
	if _needs_cache_rebuild:
		# Mesure TEMPORAIRE (diagnostic freeze periodique, 2026-07-11 - a
		# retirer une fois la cause confirmee) - is_debug_build() seulement.
		var _dbg_t0: int = Time.get_ticks_msec() if OS.is_debug_build() else 0
		_build_layer_cache(_rebuild_dirty_min, _rebuild_dirty_max)
		if OS.is_debug_build():
			print("[Perf] _build_layer_cache : %d ms (y %d..%d)" % [Time.get_ticks_msec() - _dbg_t0, _rebuild_dirty_min, _rebuild_dirty_max])
		_needs_cache_rebuild = false

	# Noeuds persistants par couche/escaliers (voir leur doc plus haut) :
	# mis a jour une seule fois par mutation reelle, jamais recomposes au
	# scroll - 2e etape du gain de perf (2026-07-10). Ne fait rien si deja a
	# jour depuis la derniere invalidate_cache(). _ensure_layer_instances
	# recoit la meme portee que ci-dessus pour ne mettre a jour QUE les
	# noeuds des couches reellement recalculees.
	_ensure_layer_instances(_rebuild_dirty_min, _rebuild_dirty_max)
	_ensure_stairs_instance()

	# Le SEUL travail reellement refait a CHAQUE changement de niveau de vue :
	# un show/hide par couche (quasi gratuit, aucune geometrie recalculee) -
	# remplace l'ancienne recomposition totale (append_from sur TOUTES les
	# couches en dessous de view_level, a chaque scroll - cout qui grandissait
	# avec la profondeur, la vraie cause du "critique" 2026-07-10). Double
	# boucle depuis le partitionnement par (Y, CHUNK) - un noeud par chunk,
	# tous les chunks d'un meme Y partagent la meme visibilite.
	for y in _layer_mesh_instances.keys():
		var visible_now: bool = y < view_level
		for chunk in (_layer_mesh_instances[y] as Dictionary).keys():
			(_layer_mesh_instances[y][chunk] as MeshInstance3D).visible = visible_now

	# Couche-frontiere (y == view_level) : CUBE complet (parois + dessous +
	# le VRAI materiau du SOL sur la face du dessus, voir get_sol/modele
	# CUBE+SOL 2026-07-09) - plus les cases VIDES a EXACTEMENT view_level dont
	# le SOL est quand meme defini, et les blocs non decouverts (gris) - voir
	# _build_boundary_mesh. Deja bornee a la taille d'UNE seule couche (jamais
	# a la profondeur), donc peu couteuse - mise en cache par view_level quand
	# meme pour qu'un aller-retour sur le meme niveau soit gratuit.
	if not _boundary_mesh_cache.has(view_level):
		# Mesure TEMPORAIRE (diagnostic freeze periodique, 2026-07-11 - a
		# retirer une fois la cause confirmee) - is_debug_build() seulement.
		var _dbg_t1: int = Time.get_ticks_msec() if OS.is_debug_build() else 0
		_boundary_mesh_cache[view_level] = _build_boundary_mesh()
		if OS.is_debug_build():
			print("[Perf] _build_boundary_mesh : %d ms (niveau %d)" % [Time.get_ticks_msec() - _dbg_t1, view_level])
	mesh_instance.mesh = _boundary_mesh_cache[view_level]

	# Zone sale transmise telle quelle (voir doc de VoxelVeins.rebuild_pepites,
	# fix perf 2026-07-11) - memes valeurs que _build_layer_cache/
	# _ensure_layer_instances, deja disponibles comme membres de cette classe.
	# Mesure TEMPORAIRE (diagnostic perf rebuild complet, 2026-07-11 - a
	# retirer une fois la cause confirmee) - is_debug_build() seulement.
	var _dbg_t_pepites: int = Time.get_ticks_msec() if OS.is_debug_build() else 0
	vein_system.rebuild_pepites(view_level, discovered, Callable(self, "_is_face_exposed"), DIRECTIONS,
			_rebuild_dirty_min, _rebuild_dirty_max,
			_rebuild_dirty_x_min, _rebuild_dirty_x_max, _rebuild_dirty_z_min, _rebuild_dirty_z_max)
	if OS.is_debug_build():
		print("[Perf] rebuild_pepites : %d ms" % (Time.get_ticks_msec() - _dbg_t_pepites))


## Met a jour (si perime, voir _layer_instances_stale) le MeshInstance3D
## PERSISTANT par couche Y a partir des caches _layer_sides_bottom/
## _layer_natural_top/_layer_sol_only. REUTILISE les noeuds existants d'une
## mutation a l'autre (Francois 2026-07-10, "trou... freeze" - detruire puis
## recreer des dizaines de MeshInstance3D a chaque minage etait un cout de
## GESTION D'ARBRE DE SCENE ajoute en plus du recalcul geometrique deja
## necessaire ; un simple remplacement de ".mesh" est juste un echange de
## ressource, sans toucher l'arbre).
##
## dirty_y_min/dirty_y_max (memes valeurs que _build_layer_cache, voir sa
## doc) : Francois 2026-07-10 "perf creuser pas bonne" - cette fonction
## retraitait encore TOUTES les couches existantes a chaque mutation, meme
## quand _build_layer_cache() lui-meme n'en avait recalcule que 2-3 (le cache
## des AUTRES couches n'a pas change, donc leur ".mesh" actuel reste
## parfaitement valable, inutile de le regenerer). Si une plage precise est
## donnee, SEULS les (Y, CHUNK) touches par la mutation sont retraites ici ;
## sinon (portee complete, -1/-1), tous les (Y, CHUNK) presents dans les 3
## caches sont retraites, comme avant.
## PARTITIONNE PAR (Y, CHUNK) depuis le fix definitif 2026-07-10 (voir
## CHUNK_SIZE) : un noeud par chunk, jamais un seul noeud fusionnant toute la
## carte pour un Y (voir memoire "terrain transparent"). Cree un noeud
## UNIQUEMENT pour un (Y, CHUNK) vraiment nouveau, detruit un noeud
## UNIQUEMENT si son chunk est totalement vide desormais. Appele sans risque
## a chaque appel (ne fait rien si pas perime, voir _layer_instances_stale).
func _ensure_layer_instances(dirty_y_min: int = -1, dirty_y_max: int = -1) -> void:
	if not _layer_instances_stale:
		return
	_layer_instances_stale = false
	var restrict: bool = dirty_y_min != -1
	var dirty_chunks: Array = _dirty_chunk_keys(_rebuild_dirty_x_min, _rebuild_dirty_x_max, _rebuild_dirty_z_min, _rebuild_dirty_z_max)

	# Quels Y retraiter cette fois - voir doc ci-dessus.
	var ys: Dictionary = {}
	if restrict:
		for y in range(dirty_y_min, dirty_y_max + 1):
			ys[y] = true
	else:
		for y in _layer_sides_bottom.keys():
			ys[y] = true
		for y in _layer_natural_top.keys():
			ys[y] = true
		for y in _layer_sol_only.keys():
			ys[y] = true
		for y in _layer_mesh_instances.keys():
			ys[y] = true  # detecte aussi les noeuds dont la couche a disparu

	var bucket_materials: Dictionary = _get_bucket_materials()
	var parent: Node = mesh_instance.get_parent()
	var identity := Transform3D.IDENTITY
	for y in ys.keys():
		# Quels CHUNKS de ce Y retraiter - restreint (mutation localisee) ou
		# TOUS les chunks presents pour ce Y (portee complete, ou filet de
		# securite si X/Z non fournis - voir doc de invalidate_cache).
		var chunks_for_y: Array
		if restrict and not dirty_chunks.is_empty():
			chunks_for_y = dirty_chunks
		else:
			var chunk_set: Dictionary = {}
			for chunk in (_layer_sides_bottom.get(y, {}) as Dictionary).keys():
				chunk_set[chunk] = true
			for chunk in (_layer_natural_top.get(y, {}) as Dictionary).keys():
				chunk_set[chunk] = true
			for chunk in (_layer_sol_only.get(y, {}) as Dictionary).keys():
				chunk_set[chunk] = true
			for chunk in (_layer_mesh_instances.get(y, {}) as Dictionary).keys():
				chunk_set[chunk] = true  # detecte aussi les noeuds dont le chunk a disparu
			chunks_for_y = chunk_set.keys()

		for chunk in chunks_for_y:
			var sb: Dictionary = (_layer_sides_bottom.get(y, {}) as Dictionary).get(chunk, {})
			var nt: Dictionary = (_layer_natural_top.get(y, {}) as Dictionary).get(chunk, {})
			var so: Dictionary = (_layer_sol_only.get(y, {}) as Dictionary).get(chunk, {})
			var has_content: bool = not sb.is_empty() or not nt.is_empty() or not so.is_empty()
			var y_instances: Dictionary = _layer_mesh_instances.get(y, {})
			if not has_content:
				# Ce chunk n'a plus AUCUN contenu a ce Y (cas limite - un
				# mineur ne vide jamais un chunk entier d'un coup, mais
				# possible pour une reconstruction complete apres une
				# regeneration de carte).
				if y_instances.has(chunk):
					var mi_old: MeshInstance3D = y_instances[chunk]
					if is_instance_valid(mi_old):
						mi_old.queue_free()
					y_instances.erase(chunk)
					if y_instances.is_empty():
						_layer_mesh_instances.erase(y)
				continue
			var st_by_bucket: Dictionary = {}
			_collect_layer_meshes(st_by_bucket, sb, identity)
			_collect_layer_meshes(st_by_bucket, nt, identity)
			_collect_layer_meshes(st_by_bucket, so, identity)
			var mesh := ArrayMesh.new()
			for bucket_idx in st_by_bucket.keys():
				var surfaces_before := mesh.get_surface_count()
				(st_by_bucket[bucket_idx] as SurfaceTool).commit(mesh)
				if mesh.get_surface_count() > surfaces_before:
					var mat: Material = bucket_materials.get(bucket_idx)
					if mat == null:
						mat = StandardMaterial3D.new()
					mesh.surface_set_material(surfaces_before, mat)
			if not _layer_mesh_instances.has(y):
				_layer_mesh_instances[y] = {}
			if (_layer_mesh_instances[y] as Dictionary).has(chunk):
				(_layer_mesh_instances[y][chunk] as MeshInstance3D).mesh = mesh
			else:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.visible = y < view_level
				parent.add_child(mi)
				_layer_mesh_instances[y][chunk] = mi


## Fusionne les ArrayMesh deja figes d'un cache par couche (sides_bottom/
## natural_top/sol_only/stairs) dans un dictionnaire de SurfaceTool partage
## par bucket (SurfaceTool.append_from = copie native rapide, pas de
## recalcul) - factorise entre _ensure_layer_instances et
## _ensure_stairs_instance, seule la source change.
func _collect_layer_meshes(dest: Dictionary, src: Dictionary, identity: Transform3D) -> void:
	for bucket_idx in src.keys():
		if not dest.has(bucket_idx):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			dest[bucket_idx] = st
		(dest[bucket_idx] as SurfaceTool).append_from(src[bucket_idx], 0, identity)


## Plaques d'escalier (voir _layer_stairs) : un seul noeud PERSISTANT,
## TOUJOURS visible quel que soit view_level (un escalier deja creuse est par
## definition deja connu). REUTILISE le noeud existant (voir doc de
## _ensure_layer_instances, meme correctif "trou... freeze") - cree seulement
## au tout premier appel ou si le noeud a ete invalide entre-temps. Appele
## sans risque a chaque appel (voir _stairs_stale).
func _ensure_stairs_instance() -> void:
	if not _stairs_stale:
		return
	_stairs_stale = false
	if _layer_stairs.is_empty():
		if _stairs_mesh_instance != null and is_instance_valid(_stairs_mesh_instance):
			_stairs_mesh_instance.mesh = null
		return
	var st_by_bucket: Dictionary = {}
	var identity := Transform3D.IDENTITY
	for y in _layer_stairs.keys():
		_collect_layer_meshes(st_by_bucket, _layer_stairs[y], identity)
	if st_by_bucket.is_empty():
		return
	var bucket_materials: Dictionary = _get_bucket_materials()
	var mesh := ArrayMesh.new()
	for bucket_idx in st_by_bucket.keys():
		var surfaces_before := mesh.get_surface_count()
		(st_by_bucket[bucket_idx] as SurfaceTool).commit(mesh)
		if mesh.get_surface_count() > surfaces_before:
			var mat: Material = bucket_materials.get(bucket_idx)
			if mat == null:
				mat = StandardMaterial3D.new()
			mesh.surface_set_material(surfaces_before, mat)
	if _stairs_mesh_instance == null or not is_instance_valid(_stairs_mesh_instance):
		_stairs_mesh_instance = MeshInstance3D.new()
		mesh_instance.get_parent().add_child(_stairs_mesh_instance)
	_stairs_mesh_instance.mesh = mesh


## Construit le mesh de la couche-frontiere (y == view_level) : CUBE complet
## a la coupe (_add_boundary_cube_faces) + SOL seul des cases vides
## (_add_boundary_sol_only_faces) + blocs non decouverts (gris uniforme) -
## repris tel quel de l'ancienne composition inline, seule la destination
## change (son propre ArrayMesh independant, mis en cache par view_level dans
## _boundary_mesh_cache, plutot que les surface_tools partages de toute la
## carte de l'ancienne version). Deja borne a la taille d'UNE seule couche
## (_layer_positions/WIDTH*DEPTH), jamais a la profondeur.
func _build_boundary_mesh() -> ArrayMesh:
	# Active le cache temporaire de get_top_block_y pour la duree de cet appel
	# (voir doc de _scoped_top_cache) - restaure a la Callable reelle avant
	# le seul "return" de cette fonction, plus bas.
	_scoped_top_real_fn = get_top_block_y
	_scoped_top_cache.clear()
	get_top_block_y = Callable(self, "_cached_top_scoped")

	var surface_tools: Array = []
	for i in range(21):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface_tools.append(st)

	_add_boundary_cube_faces(surface_tools)
	_add_boundary_sol_only_faces(surface_tools)

	# Passe "non decouvert" - CUBE complet (6 faces, dessus inclus), gris
	# uniforme, pour representer ce qui n'a jamais ete explore au niveau de
	# coupe courant comme un vrai volume opaque (feedback Francois
	# 2026-07-08). Inconditionnel : un bloc de roche entoure d'autre roche
	# doit quand meme montrer ses parois pour se distinguer comme un cube.
	# Toujours borne a WIDTH*DEPTH*6 verifications (jamais la profondeur).
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
	# est vide. Chaque bucket est donc mappe a son materiau via un
	# dictionnaire, et surface_set_material n'est appele qu'apres coup, sur
	# le vrai indice de surface obtenu.
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
	# Restauration : plus rien apres _build_boundary_mesh() ne doit passer par
	# le cache temporaire (_build_layer_cache active/restaure le sien
	# separement - voir doc de _scoped_top_cache).
	get_top_block_y = _scoped_top_real_fn
	return mesh


## Callable de secours branchee temporairement sur get_top_block_y pendant
## _build_boundary_mesh() OU _build_layer_cache() (voir doc de
## _scoped_top_cache) - memoise par colonne, jamais persiste au-dela d'un
## seul appel.
func _cached_top_scoped(x: int, z: int) -> int:
	var col := Vector2i(x, z)
	if _scoped_top_cache.has(col):
		return _scoped_top_cache[col]
	var v: int = _scoped_top_real_fn.call(x, z)
	_scoped_top_cache[col] = v
	return v


## Ajoute la boite SOL SEUL (fine tranche du bas, assombrie) a "pos" dans le
## cache "active_sol_only" en construction (y -> chunk -> bucket_idx ->
## SurfaceTool, chunk = _chunk_key(pos.x, pos.z) - partitionnement 2026-07-10,
## voir doc de CHUNK_SIZE) - factorise entre les 2 sources possibles d'une
## case SOL SEUL (voir doc de la boucle appelante dans _build_layer_cache) :
## un objet SOL explicitement fige (sol_grid) ou le sol dynamique de fond de
## trou/couloir. N'ajoute rien si get_sol renvoie EMPTY pour cette case (ex:
## sol_grid perime, cas normalement impossible mais garde par securite).
func _emit_sol_only_box(active_sol_only: Dictionary, pos: Vector3i) -> void:
	var sol_type: int = get_sol.call(pos)
	if sol_type == BlockType.EMPTY:
		return
	var y: int = pos.y
	var chunk: Vector2i = _chunk_key(pos.x, pos.z)
	if not active_sol_only.has(y):
		active_sol_only[y] = {}
	if not (active_sol_only[y] as Dictionary).has(chunk):
		active_sol_only[y][chunk] = {}
	var chunk_dict: Dictionary = active_sol_only[y][chunk]
	var sol_info: Array = _sol_bucket_and_color_for(pos)
	var bucket_idx: int = sol_info[0]
	var c: Color = sol_info[1]
	var sol_color := Color(c.r * SOL_DARKEN_FACTOR, c.g * SOL_DARKEN_FACTOR, c.b * SOL_DARKEN_FACTOR, c.a)
	if not chunk_dict.has(bucket_idx):
		var new_st := SurfaceTool.new()
		new_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		chunk_dict[bucket_idx] = new_st
	var st: SurfaceTool = chunk_dict[bucket_idx]
	# Dessus/dessous : toujours dessines (le dessus est la vraie surface
	# marchable, jamais cachee par construction ; le dessous n'est visible que
	# dans de rares cas de surplomb - pas de culling ici, cout marginal, 2
	# faces sur 6).
	_add_face_y_range(st, pos, Vector3i(0, 1, 0), 0.0, SOL_THICKNESS, sol_color)
	_add_face_y_range(st, pos, Vector3i(0, -1, 0), 0.0, SOL_THICKNESS, sol_color)
	# Faces laterales : culling perf 2026-07-11 (voir doc de
	# HORIZONTAL_DIRECTIONS) - une case voisine (meme Y) cache entierement
	# cette face si elle contient un CUBE plein, OU si elle recevra elle-meme
	# une boite SOL (sol_grid, pas recouverte par un mur construit depuis) -
	# meme principe que le culling deja fait pour les CUBE (grid.get(neighbor)
	# != EMPTY dans la boucle "work_items" plus haut). Si le voisin est un
	# "SOL dynamique" (boucle de secours, pas d'entree sol_grid), la face reste
	# dessinee en trop (pas de regression, juste un peu moins optimal - cas
	# rare : fond de trou fraichement creuse, pas la surface naturelle).
	for dir in HORIZONTAL_DIRECTIONS:
		var npos: Vector3i = pos + dir
		var occluded: bool = grid.get(npos, BlockType.EMPTY) != BlockType.EMPTY \
				or (sol_grid.has(npos) and grid.get(npos, BlockType.EMPTY) == BlockType.EMPTY)
		if occluded:
			continue
		_add_face_y_range(st, pos, dir, 0.0, SOL_THICKNESS, sol_color)


## Reconstruit le cache par couche (Y, CHUNK) (voir sa doc et celle de
## CHUNK_SIZE) a partir de "discovered"/sol_grid. Appele uniquement quand une
## reconstruction est en attente (_needs_cache_rebuild, voir
## _rebuild_mesh_body) - JAMAIS a cause d'un simple changement de niveau de
## vue.
##
## dirty_y_min/dirty_y_max = -1/-1 (par defaut) : reconstruction COMPLETE,
## comme avant 2026-07-10. Sinon : SEULS les (Y, CHUNK) sales sont effaces
## puis recalcules (voir invalidate_cache, deja appele juste avant avec la
## meme plage) - TOUJOURS un CHUNK ENTIER a la fois, jamais une sous-boite de
## colonnes (voir memoire project_forgotten_caves_... regression
## "terrain transparent" 2026-07-10 : effacer par Y entier puis ne
## recalculer qu'un sous-ensemble de colonnes laissait le reste du niveau Y
## sans geometrie - desormais effacement ET recalcul se font TOUJOURS a la
## meme granularite, le chunk).
func _build_layer_cache(dirty_y_min: int = -1, dirty_y_max: int = -1) -> void:
	# Active le cache temporaire de get_top_block_y pour la duree de cet appel
	# (voir doc de _scoped_top_cache, perf 2026-07-11 v3 - I89) - restaure a la
	# Callable reelle avant la sortie de la fonction (voir tout en bas,
	# _cache_populated = true).
	_scoped_top_real_fn = get_top_block_y
	_scoped_top_cache.clear()
	get_top_block_y = Callable(self, "_cached_top_scoped")

	var restrict: bool = dirty_y_min != -1
	var restrict_xz: bool = restrict and _rebuild_dirty_x_min != -1
	var dirty_chunks: Array = _dirty_chunk_keys(_rebuild_dirty_x_min, _rebuild_dirty_x_max, _rebuild_dirty_z_min, _rebuild_dirty_z_max) if restrict_xz else []
	var dirty_chunks_set: Dictionary = {}
	for c in dirty_chunks:
		dirty_chunks_set[c] = true

	# SurfaceTool actifs pendant la construction, un par (y, chunk, bucket) et
	# par categorie (laterales+dessous / dessus naturel) - convertis en
	# ArrayMesh figes a la toute fin, une fois tous les blocs traites.
	var active_sb: Dictionary = {}  # y -> chunk -> Dictionary[bucket_idx -> SurfaceTool]
	var active_nt: Dictionary = {}  # y -> chunk -> Dictionary[bucket_idx -> SurfaceTool]

	# Regroupe les positions a traiter par (y, chunk) - TOUJOURS un chunk
	# ENTIER quand une restriction X/Z est disponible (via discovered_by_xz +
	# _chunk_bounds), jamais seulement les quelques colonnes mutees : c'est
	# cette regle qui garantit que l'effacement (invalidate_cache, par chunk
	# entier) et le recalcul (ici) portent toujours sur le meme perimetre.
	var work_items: Dictionary = {}  # y -> chunk -> Array[Vector3i]

	if restrict_xz:
		for chunk in dirty_chunks:
			var bounds: Array = _chunk_bounds(chunk)
			for x in range(bounds[0], bounds[1] + 1):
				for z in range(bounds[2], bounds[3] + 1):
					var col: Vector2i = Vector2i(x, z)
					if not discovered_by_xz.has(col):
						continue
					for pos in (discovered_by_xz[col] as Dictionary).keys():
						if pos.y < dirty_y_min or pos.y > dirty_y_max:
							continue
						if not work_items.has(pos.y):
							work_items[pos.y] = {}
						if not (work_items[pos.y] as Dictionary).has(chunk):
							work_items[pos.y][chunk] = []
						work_items[pos.y][chunk].append(pos)
	else:
		# Repli defensif (reconstruction complete, ou restriction Y sans X/Z
		# fournis - rare) : balayage complet de "discovered", reparti par
		# (y, chunk).
		for pos in discovered.keys():
			if restrict and (pos.y < dirty_y_min or pos.y > dirty_y_max):
				continue
			var chunk: Vector2i = _chunk_key(pos.x, pos.z)
			if not work_items.has(pos.y):
				work_items[pos.y] = {}
			if not (work_items[pos.y] as Dictionary).has(chunk):
				work_items[pos.y][chunk] = []
			work_items[pos.y][chunk].append(pos)

	# Mesure TEMPORAIRE (diagnostic perf rebuild complet, 2026-07-11 - a
	# retirer une fois la cause confirmee) - is_debug_build() seulement.
	var _dbg_t_faces: int = Time.get_ticks_msec() if OS.is_debug_build() else 0
	var _dbg_n_positions: int = 0
	for y in work_items.keys():
		for chunk in (work_items[y] as Dictionary).keys():
			for pos in (work_items[y][chunk] as Array):
				_dbg_n_positions += 1
				var type: int = grid.get(pos, BlockType.EMPTY)
				if type == BlockType.EMPTY:
					continue
				if not _layer_positions.has(y):
					_layer_positions[y] = {}
				if not (_layer_positions[y] as Dictionary).has(chunk):
					_layer_positions[y][chunk] = []
				_layer_positions[y][chunk].append(pos)
				if not active_sb.has(y):
					active_sb[y] = {}
					active_nt[y] = {}
				if not (active_sb[y] as Dictionary).has(chunk):
					active_sb[y][chunk] = {}
					active_nt[y][chunk] = {}
				for dir in DIRECTIONS:
					# Exposition "naturelle" (independante de view_level, voir doc du
					# cache) : le voisin est reellement vide, sans tenir compte d'un
					# quelconque niveau de coupe - valide car ce cache ne sert jamais
					# pour la couche-frontiere (traitee a part, voir
					# _add_boundary_cube_faces).
					var neighbor_pos: Vector3i = pos + dir
					if grid.get(neighbor_pos, BlockType.EMPTY) != BlockType.EMPTY:
						continue
					# Le dessus de ce CUBE est-il couvert par un objet SOL fige
					# (sol_grid, la vraie surface) juste au-dessus ? Si oui, cette face
					# est TOUJOURS entierement cachee sous la boite SOL (_layer_sol_only)
					# - inutile de la dessiner (perf, Francois 2026-07-10 : "le
					# changement de niveau de camera en 250x250 est critique"). Avant le
					# modele CUBE+SOL universel, ce cas n'existait pas (la surface
					# naturelle etait directement le sommet du CUBE, pas une case a
					# part) - depuis, CHAQUE colonne jamais minee ajoutait cette face en
					# double (dessus du CUBE + boite SOL par-dessus), pour rien.
					if dir == Vector3i(0, 1, 0) and sol_grid.has(neighbor_pos):
						continue
					var idx := _bucket_for(pos, type, dir)
					var face_color := Color.WHITE
					if idx == 0:
						face_color = _ao_darken(_grass_color_for(pos), pos)
					elif idx == 2:
						face_color = _ao_darken(_stone_color_for(pos), pos)
					elif idx == 10 or idx == 18:
						face_color = _vein_color_for(pos)
					# "dir" vient d'une boucle "for dir in DIRECTIONS" non typee (Array
					# generique, voir champ DIRECTIONS) : le comparer directement avec
					# ":=" empeche l'inference de type statique de Godot ("Cannot
					# infer the type..."), d'ou le type explicite "bool" ici (meme
					# comparaison que dans _bucket_for, ou "dir" est en revanche un
					# parametre type Vector3i - pas de probleme la-bas).
					var is_top: bool = dir == Vector3i(0, 1, 0)
					var bucket_dict: Dictionary = active_nt[y][chunk] if is_top else active_sb[y][chunk]
					if not bucket_dict.has(idx):
						var st := SurfaceTool.new()
						st.begin(Mesh.PRIMITIVE_TRIANGLES)
						bucket_dict[idx] = st
					_add_face(bucket_dict[idx], pos, dir, face_color)
	if OS.is_debug_build():
		print("[Perf] boucle faces (work_items) : %d ms (%d positions)" % [Time.get_ticks_msec() - _dbg_t_faces, _dbg_n_positions])

	# Mesure TEMPORAIRE (diagnostic perf rebuild complet, 2026-07-11 - a
	# retirer une fois la cause confirmee) - is_debug_build() seulement.
	var _dbg_t_commit: int = Time.get_ticks_msec() if OS.is_debug_build() else 0
	for y in active_sb.keys():
		if not _layer_sides_bottom.has(y):
			_layer_sides_bottom[y] = {}
		for chunk in (active_sb[y] as Dictionary).keys():
			var sb_meshes: Dictionary = {}
			for bucket_idx in (active_sb[y][chunk] as Dictionary).keys():
				var mesh := ArrayMesh.new()
				(active_sb[y][chunk][bucket_idx] as SurfaceTool).commit(mesh)
				sb_meshes[bucket_idx] = mesh
			_layer_sides_bottom[y][chunk] = sb_meshes
	for y in active_nt.keys():
		if not _layer_natural_top.has(y):
			_layer_natural_top[y] = {}
		for chunk in (active_nt[y] as Dictionary).keys():
			var nt_meshes: Dictionary = {}
			for bucket_idx in (active_nt[y][chunk] as Dictionary).keys():
				var mesh := ArrayMesh.new()
				(active_nt[y][chunk][bucket_idx] as SurfaceTool).commit(mesh)
				nt_meshes[bucket_idx] = mesh
			_layer_natural_top[y][chunk] = nt_meshes
	if OS.is_debug_build():
		print("[Perf] commit meshes sb/nt : %d ms" % (Time.get_ticks_msec() - _dbg_t_commit))

	# SOL SEUL (voir doc de _layer_sol_only) : DEUX sources, jamais la meme
	# case en double (voir sol_processed) -
	# 1) les objets SOL explicitement figes (sol_grid, la vraie surface
	#    naturelle - Francois 2026-07-10 : "c'est un objet reel") : valables
	#    quel que soit le sommet ACTUEL de la colonne, meme si un couloir a
	#    ete creuse plus bas depuis (voir generate_flat_terrain).
	# 2) le SOL "dynamique" de fond de trou/couloir fraichement creuse (juste
	#    au-dessus du sommet ACTUEL, pas de sol_grid pour cette case) - cette
	#    case n'a jamais sa PROPRE entree dans "discovered", seul le bloc
	#    solide juste en dessous en a une.
	var active_sol_only: Dictionary = {}  # y -> chunk -> Dictionary[bucket_idx -> SurfaceTool]
	var sol_processed: Dictionary = {}  # Vector3i -> true, evite un double ajout
	# Mesure TEMPORAIRE (diagnostic perf rebuild complet, 2026-07-11 - a
	# retirer une fois la cause confirmee) - is_debug_build() seulement.
	var _dbg_t_sol_reel: int = Time.get_ticks_msec() if OS.is_debug_build() else 0
	var _dbg_n_sol_reel: int = 0
	for sol_pos in sol_grid.keys():
		if grid.get(sol_pos, BlockType.EMPTY) != BlockType.EMPTY:
			continue  # un CUBE occupe desormais cette case (ex: mur construit)
		# Le dedoublonnage (sol_processed) reste global, meme restreint - sinon
		# le balayage ci-dessous pourrait retraiter cette case a tort. Seul le
		# calcul de geometrie (_emit_sol_only_box, couteux) est saute hors de
		# la plage sale (Y ET chunk desormais - voir doc de la fonction).
		sol_processed[sol_pos] = true
		if restrict and (sol_pos.y < dirty_y_min or sol_pos.y > dirty_y_max):
			continue
		if restrict_xz and not dirty_chunks_set.has(_chunk_key(sol_pos.x, sol_pos.z)):
			continue
		_dbg_n_sol_reel += 1
		_emit_sol_only_box(active_sol_only, sol_pos)
	if OS.is_debug_build():
		print("[Perf] boucle SOL reel (sol_grid) : %d ms (%d cases, %d total)" % [Time.get_ticks_msec() - _dbg_t_sol_reel, _dbg_n_sol_reel, sol_grid.size()])
	# Boucle de secours (SOL "dynamique" de fond de trou/couloir, voir doc
	# ci-dessus) : get_top_block_y.call(x,z) n'est PAS indexable a l'avance
	# (elle recalcule le sommet reel de la colonne), donc seule une
	# restriction en colonnes peut la borner - c'est elle, pas le balayage
	# sol_grid.keys() ci-dessus, qui dominait le cout mesure ("sol=1348.5ms",
	# Francois 2026-07-10). Colonnes couvertes = les CHUNKS entiers sales
	# (via _chunk_bounds), jamais seulement la boite de mutation etroite -
	# meme regle que pour work_items ci-dessus (perimetre identique a
	# invalidate_cache).
	var col_set: Dictionary = {}
	if restrict_xz:
		for chunk in dirty_chunks:
			var bounds: Array = _chunk_bounds(chunk)
			for x in range(bounds[0], bounds[1] + 1):
				for z in range(bounds[2], bounds[3] + 1):
					col_set[Vector2i(x, z)] = true
	else:
		for x in range(WIDTH):
			for z in range(DEPTH):
				col_set[Vector2i(x, z)] = true
	# Mesure TEMPORAIRE (diagnostic perf rebuild complet, 2026-07-11 - a
	# retirer une fois la cause confirmee) - is_debug_build() seulement.
	var _dbg_t_secours: int = Time.get_ticks_msec() if OS.is_debug_build() else 0
	for col in col_set.keys():
		var x: int = col.x
		var z: int = col.y
		var top_y: int = get_top_block_y.call(x, z)
		if top_y < 0:
			continue
		var sol_pos: Vector3i = Vector3i(x, top_y + 1, z)
		if sol_processed.has(sol_pos):
			continue
		if grid.get(sol_pos, BlockType.EMPTY) != BlockType.EMPTY:
			continue  # deja un CUBE plein ici (ex: mur construit en hauteur)
		if not discovered.has(Vector3i(x, top_y, z)):
			continue
		if restrict and (sol_pos.y < dirty_y_min or sol_pos.y > dirty_y_max):
			continue
		_emit_sol_only_box(active_sol_only, sol_pos)
	if OS.is_debug_build():
		print("[Perf] boucle de secours SOL : %d ms (%d colonnes)" % [Time.get_ticks_msec() - _dbg_t_secours, col_set.size()])
	# Mesure TEMPORAIRE (diagnostic perf rebuild complet, 2026-07-11 - a
	# retirer une fois la cause confirmee) - is_debug_build() seulement.
	var _dbg_t_commit_sol: int = Time.get_ticks_msec() if OS.is_debug_build() else 0
	for y in active_sol_only.keys():
		if not _layer_sol_only.has(y):
			_layer_sol_only[y] = {}
		for chunk in (active_sol_only[y] as Dictionary).keys():
			var sol_meshes: Dictionary = {}
			for bucket_idx in (active_sol_only[y][chunk] as Dictionary).keys():
				var mesh := ArrayMesh.new()
				(active_sol_only[y][chunk][bucket_idx] as SurfaceTool).commit(mesh)
				sol_meshes[bucket_idx] = mesh
			_layer_sol_only[y][chunk] = sol_meshes
	if OS.is_debug_build():
		print("[Perf] commit meshes sol_only : %d ms" % (Time.get_ticks_msec() - _dbg_t_commit_sol))

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
	# Mesure TEMPORAIRE (diagnostic perf rebuild complet, 2026-07-11 - a
	# retirer une fois la cause confirmee) - is_debug_build() seulement.
	var _dbg_t_stairs: int = Time.get_ticks_msec() if OS.is_debug_build() else 0
	for pos in stair_grid.keys():
		var y: int = pos.y
		if restrict and (y < dirty_y_min or y > dirty_y_max):
			continue
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
	if OS.is_debug_build():
		print("[Perf] escaliers : %d ms" % (Time.get_ticks_msec() - _dbg_t_stairs))

	# Restauration : plus rien apres _build_layer_cache() ne doit passer par
	# le cache temporaire (voir doc de _scoped_top_cache).
	get_top_block_y = _scoped_top_real_fn
	_cache_populated = true


## Ajoute VRAIMENT les 2 boites du modele CUBE+SOL (memoire
## project_forgotten_caves_cube_sol_model.md, section 2) pour les blocs
## decouverts EXACTEMENT au niveau de vue courant - utilise _layer_positions
## pour ne parcourir QUE cette couche (quelques milliers de blocs en moyenne)
## au lieu de tout "discovered". Inconditionnel (les faces sont ajoutees
## meme si le voisin correspondant est plein) : un bloc de terrain intact,
## entoure d'autres blocs pleins, doit quand meme se distinguer comme un
## cube. SOL = fine boite du bas [0, SOL_THICKNESS], assombrie ; CUBE = le
## reste au-dessus [SOL_THICKNESS, 1], vrai materiau/couleur - jusqu'au
## 2026-07-10 une seule face plate (couleur du SOL) etait dessinee ici, ce
## qui restait percu comme "juste un SOL" malgre les parois laterales
## deja ajoutees le 2026-07-08 (Francois : "je veux que le CUBE soit
## affiche, la il n'y a que le SOL").
func _add_boundary_cube_faces(surface_tools: Array) -> void:
	if not _layer_positions.has(view_level):
		return
	# _layer_positions est partitionne par (Y, CHUNK) depuis le fix 2026-07-10
	# (voir CHUNK_SIZE) - la couche-frontiere a toujours besoin de TOUS les
	# chunks de ce Y (jamais une restriction, deja bornee a une seule couche
	# et mise en cache par view_level - voir _boundary_mesh_cache), d'ou la
	# boucle imbriquee sur tous les chunks presents.
	var chunks: Dictionary = _layer_positions[view_level]
	for chunk in chunks.keys():
		for pos in (chunks[chunk] as Array):
			_add_boundary_cube_face_at(surface_tools, pos)


## Corps de la boucle de _add_boundary_cube_faces pour UNE position - extrait
## pour rester lisible malgre la boucle imbriquee (Y -> chunk -> positions)
## ajoutee par le partitionnement.
func _add_boundary_cube_face_at(surface_tools: Array, pos: Vector3i) -> void:
	var type: int = grid.get(pos, BlockType.EMPTY)
	if type == BlockType.EMPTY:
		return
	var sol_info: Array = _sol_bucket_and_color_for(pos)
	var c: Color = sol_info[1]
	var sol_color := Color(c.r * SOL_DARKEN_FACTOR, c.g * SOL_DARKEN_FACTOR, c.b * SOL_DARKEN_FACTOR, c.a)
	_add_box_faces(surface_tools[sol_info[0]], pos, 0.0, 1.0, 0.0, SOL_THICKNESS, 0.0, 1.0, sol_color)
	# Le CUBE est une matiere brute uniforme (terre/pierre/mur) : TOUTES ses
	# faces, dessus compris, prennent la meme couleur que ses parois - pas
	# la couleur "herbe" (variable climat/saison) reservee au SOL. Avant
	# 2026-07-10 ce dessus passait par _bucket_for (qui distingue dessus/
	# paroi, pense pour l'ancien cache "naturel" hors couche-frontiere) sans
	# jamais calculer sa couleur pour la terre/pierre (seuls les filons
	# l'etaient) - le dessus du CUBE restait donc blanc par defaut, percu
	# comme gris (Francois : "le dessus du bloc est gris, les murs sont
	# marron"). Les filons restent une exception (couleur reperable sur
	# toutes leurs faces, meme regle qu'avant).
	for dir in DIRECTIONS:
		var idx: int
		var face_color := Color.WHITE
		if type == BlockType.STONE and vein_grid.has(pos):
			idx = 18 if _is_underground(pos) else 10
			face_color = _vein_color_for(pos)
		elif dir == Vector3i(0, 1, 0) and (type == BlockType.DIRT or type == BlockType.STONE):
			# Dessus du CUBE (Francois 2026-07-10, test perf "distinguer les
			# blocs") : garde la couleur UNIFORME (jamais teintee herbe/
			# climat, voir _cube_top_color_for - la regle "CUBE = une seule
			# couleur uniforme" reste respectee), mais passe par un bucket a
			# couleur par sommet pour pouvoir y appliquer l'assombrissement
			# d'arete/case (_ao_darken) - invisible tant que le dessus
			# restait sur le bucket "paroi" a couleur fixe (Francois : "sur
			# un niveau de Terre vu de haut aucune separation visible").
			idx = 0 if type == BlockType.DIRT else 2
			face_color = _ao_darken(_cube_top_color_for(pos, type), pos)
		else:
			idx = _paroi_bucket_for(pos, type)
		_add_face_y_range(surface_tools[idx], pos, dir, SOL_THICKNESS, 1.0, face_color)


## Complement de _add_boundary_cube_faces : une case VIDE (grid EMPTY) a
## EXACTEMENT view_level n'y est jamais indexee (_layer_positions ne suit
## que les blocs PLEINS, comme "discovered" lui-meme) - sans cette passe,
## rien n'y est dessine du tout et l'ancien rendu du vrai bloc expose EN
## DESSOUS (cache "naturel", _build_layer_cache) restait visible a sa
## place : "Niveau 1 : le SOL au niveau d'en dessous" (Francois 2026-07-10).
## Balaie donc les colonnes (X,Z) - pas de raccourci par index possible ici,
## une case vide n'a pas d'entree dediee - et dessine SEULEMENT la boite SOL
## (pas de CUBE : rien n'occupe [SOL_THICKNESS,1] ici) pour les colonnes
## dont la surface naturelle (sommet reel + 1) tombe exactement sur
## view_level et dont le sommet reel est deja decouvert. Un balayage complet
## par changement de niveau de vue (pas par frame) reste raisonnable meme a
## grande echelle (250x250, voir [[project_forgotten_caves_view_level_perf]]).
func _add_boundary_sol_only_faces(surface_tools: Array) -> void:
	for x in range(WIDTH):
		for z in range(DEPTH):
			var pos := Vector3i(x, view_level, z)
			if grid.get(pos, BlockType.EMPTY) != BlockType.EMPTY:
				continue  # deja traite par _add_boundary_cube_faces
			# Un objet SOL explicitement fige (sol_grid, la vraie surface -
			# Francois 2026-07-10 : "c'est un objet reel") passe direct, quel
			# que soit le sommet ACTUEL de la colonne - sinon (sol dynamique de
			# fond de trou/couloir), meme regle qu'avant : uniquement juste
			# au-dessus du sommet ACTUEL, et son support decouvert.
			if not sol_grid.has(pos):
				var top_y: int = get_top_block_y.call(x, z)
				if top_y < 0 or view_level != top_y + 1:
					continue
				if not discovered.has(Vector3i(x, top_y, z)):
					continue
			var sol_type: int = get_sol.call(pos)
			if sol_type == BlockType.EMPTY:
				continue
			var sol_info: Array = _sol_bucket_and_color_for(pos)
			var c: Color = sol_info[1]
			var sol_color := Color(c.r * SOL_DARKEN_FACTOR, c.g * SOL_DARKEN_FACTOR, c.b * SOL_DARKEN_FACTOR, c.a)
			_add_box_faces(surface_tools[sol_info[0]], pos, 0.0, 1.0, 0.0, SOL_THICKNESS, 0.0, 1.0, sol_color)


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
			return [0, _ao_darken(_grass_color_for(pos), pos)]
		BlockType.STONE:
			return [2, _ao_darken(_stone_color_for(pos), pos)]
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
	return VoxelBlockAppearanceScript.darken(color)


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
	return VoxelBlockAppearanceScript.make_material(color)


## Variante NON ECLAIREE de _make_material - meme reglages, mais
## shading_mode=UNSHADED : la couleur reste fixe quelle que soit l'heure/la
## position du soleil (DayNightCycle.gd), pour un bloc veritablement sous un
## plafond qui ne devrait jamais recevoir de lumiere naturelle (Francois
## 2026-07-08, voir _is_underground).
func _make_unshaded_material(color: Color) -> StandardMaterial3D:
	return VoxelBlockAppearanceScript.make_unshaded_material(color)


## Materiau pour le bucket 0 (herbe), qui lit la couleur par sommet (definie
## via SurfaceTool.set_color dans _add_face) au lieu d'une seule couleur
## fixe - c'est ce qui permet la variation continue par case. Meme passage
## a l'eclairage reel que _make_material ci-dessus.
func _make_vertex_color_material() -> StandardMaterial3D:
	return VoxelBlockAppearanceScript.make_vertex_color_material()


## Variante NON ECLAIREE de _make_vertex_color_material (buckets 18/19 -
## filon/escalier sous plafond, voir _is_underground) - meme lecture de la
## couleur par sommet, mais insensible au soleil/cycle jour-nuit.
func _make_unshaded_vertex_color_material() -> StandardMaterial3D:
	return VoxelBlockAppearanceScript.make_unshaded_vertex_color_material()


## Ajoute un quad (2 triangles) sur la face "dir" du bloc a la position "pos".
## face_color : couleur de sommet, utilisee uniquement par le bucket
## "herbe"/"pierre"/"filon" dont le materiau lit vertex_color_use_as_albedo ;
## ignoree par les autres materiaux, donc sans effet pour eux.
func _add_face(st: SurfaceTool, pos: Vector3i, dir: Vector3i, face_color: Color = Color.WHITE) -> void:
	VoxelBlockAppearanceScript.add_face(st, pos, dir, face_color)


## Variante de _add_face pour une face bornee a [y0,y1] (0..1) au lieu de
## toute la case [0,1] - utilisee par _add_boundary_cube_faces pour dessiner
## uniquement la tranche CUBE (au-dessus de la tranche SOL, voir modele
## CUBE+SOL section 2). Meme construction/ordre de sommets que _add_face,
## generalisee sur l'axe Y : pour le dessus/dessous (dir.y != 0), seule la
## position Y de la face change (y1 ou y0) ; pour les faces laterales
## (dir.y == 0), la face est un rectangle vertical borne a [y0,y1] au lieu
## de [0,1].
func _add_face_y_range(st: SurfaceTool, pos: Vector3i, dir: Vector3i, y0: float, y1: float, face_color: Color = Color.WHITE) -> void:
	VoxelBlockAppearanceScript.add_face_y_range(st, pos, dir, y0, y1, face_color)


## Ajoute les 6 faces d'une "boite partielle" a l'interieur d'une case,
## bornee a [x0,x1] x [y0,y1] x [z0,z1] (chaque borne entre 0 et 1) -
## utilise pour les 4 sous-boites (bandes) de chaque case d'escalier (voir
## _build_layer_cache). Meme construction que _add_face mais
## parametree sur les 3 axes au lieu de 0..1 fixe, et dessine les 6
## directions d'un coup (pas de culling - une sous-boite isolee n'a
## normalement pas de voisin plein contre lequel se cacher).
func _add_box_faces(st: SurfaceTool, pos: Vector3i, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, color: Color) -> void:
	VoxelBlockAppearanceScript.add_box_faces(st, pos, x0, x1, y0, y1, z0, z1, color)
