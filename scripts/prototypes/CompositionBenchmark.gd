extends Node3D
## Benchmark ISOLE (2026-07-10, Francois : "on va tester. Genere un vecteur
## 250 x 250 x 100 ... Chronometre") - mesure le cout de generation d'un
## vecteur dense de materiau a la taille MAX prevue (250x250, profondeur 100 -
## PAS SUBSOIL_DEPTH=30 utilise actuellement dans le prototype).
##
## Correction 2026-07-10 (Francois : "il faut que ce soit la vraie generation
## du vecteur, avec pierre metaux etc") - 1ere version ISOLAIT le remplissage
## terre/pierre SANS filons, ecart signale comme faux : les filons
## (VoxelVeins.gd/VeinMaterials.gd, REUTILISES TELS QUELS - meme appel exact
## que CubeSolTestV2._generate_composition) sont la partie couteuse identifiee
## dans la memoire du projet ("jusqu'a 17 evaluations de bruit par bloc de
## pierre") - les exclure du benchmark aurait mesure un cout non representatif.
## Toujours aucun rendu/hydrologie/relief (hors sujet de ce test precis).
##
## Correction 2026-07-10 (Parser Error) : "extends Node" -> "extends Node3D" -
## vein_system.setup_pepites_nodes(parent: Node3D) exige un Node3D, jamais
## verifie avant deploiement. Scene .tscn mise a jour en consequence (racine
## Node3D, pas Node).

const VoxelVeinsScript := preload("res://scripts/monde/voxel/VoxelVeins.gd")
const VeinMaterialsScript := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")

enum BlockType { EMPTY, DIRT, STONE, WOOD_WALL, STONE_WALL, WATER }

const WIDTH := 250
const DEPTH := 250
const LAYER_COUNT := 100  # profondeur MAX a tester
const DIRT_HEIGHT_MIN := 1
const DIRT_HEIGHT_MAX := 3
const PROTOTYPE_SEED := 123456

var composition: PackedByteArray = PackedByteArray()
var vein_system := VoxelVeinsScript.new()


func _ready() -> void:
	GameRandom.setup(PROTOTYPE_SEED)
	vein_system.setup_vein_noises()
	vein_system.setup_pepites_nodes(self)
	var start_msec: int = Time.get_ticks_msec()
	var start_usec: int = Time.get_ticks_usec()
	_generate_composition()
	var end_msec: int = Time.get_ticks_msec()
	var end_usec: int = Time.get_ticks_usec()
	print("=== Benchmark composition %dx%dx%d (%d cases, AVEC filons) ===" % [WIDTH, DEPTH, LAYER_COUNT, WIDTH * DEPTH * LAYER_COUNT])
	print("Debut : %d ms (%d us)" % [start_msec, start_usec])
	print("Fin   : %d ms (%d us)" % [end_msec, end_usec])
	print("Duree : %d ms (%d us)" % [end_msec - start_msec, end_usec - start_usec])


func _composition_index(x: int, layer: int, z: int) -> int:
	return x + z * WIDTH + layer * WIDTH * DEPTH


## Meme regle que CubeSolTestV2._generate_composition (hauteur de terre
## aleatoire par colonne, pierre au-dela, filon tire sur CHAQUE bloc de pierre
## via vein_system.maybe_place_vein - meme appel exact, meme cout reel).
## Pas de relief : colonne "a plat" (layer_to_y = -layer), le relief ne change
## rien au cout de calcul d'un filon (meme nombre d'appels quelle que soit la
## position Y).
func _generate_composition() -> void:
	composition.resize(WIDTH * DEPTH * LAYER_COUNT)
	var rng := GameRandom.get_rng("sous_sol")
	var veins: Array = VeinMaterialsScript.all()
	for x in range(WIDTH):
		for z in range(DEPTH):
			var dirt_height := rng.randi_range(DIRT_HEIGHT_MIN, DIRT_HEIGHT_MAX)
			for layer in range(LAYER_COUNT):
				var block_type: int = BlockType.DIRT if layer < dirt_height else BlockType.STONE
				composition[_composition_index(x, layer, z)] = block_type
				if block_type == BlockType.STONE:
					vein_system.maybe_place_vein(Vector3i(x, -layer, z), veins)
