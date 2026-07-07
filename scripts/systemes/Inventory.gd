extends Node
## Inventaire global simple (compteur par ressource) - sera remplace plus
## tard par de vraies zones de stockage physiques.
##
## Compteurs presents : un par espece de bois (chene/sapin/bouleau, etc.), en
## plus du compteur generique "bois" (le seul consomme par la construction,
## voir Dwarf.gd/_complete_task et ActionController.gd) ; un par metal/pierre
## precieuse recolte en filon (voir VoxelWorld.gd/MetalTypes.gd/GemTypes.gd,
## purement suivi en interne pour l'instant, pas encore affiche dans un
## panneau d'inventaire dedie) ; "eau" (voir bouton Puiser/
## ActionController.gd), remplie par la tache "puiser" et consommee par les
## nains lorsque la soif est critique (voir Dwarf.gd/_try_start_drinking).
##
## resource_counts est DERIVE des tables centrales (MetalTypes.TABLE/
## GemTypes.TABLE/BerryTypes.TYPES/TreeSpecies.SPECIES/FRUIT_SPECIES) dans
## _ready() plutot que liste a la main - un futur ajout dans une de ces
## tables apparait donc automatiquement ici, sans modification a faire dans
## ce fichier.
const MetalTypesScript := preload("res://scripts/data/materiaux/types/metaux/MetalTypes.gd")
const GemTypesScript := preload("res://scripts/data/materiaux/types/pierres_precieuses/GemTypes.gd")
const BerryTypesScript := preload("res://scripts/data/materiaux/types/baies/BerryTypes.gd")
const TreeSpeciesScript := preload("res://scripts/data/materiaux/types/bois/TreeSpecies.gd")

var resource_counts: Dictionary = {
	"bois": 0,
	"pierre": 0,
	"terre": 0,
	"eau": 0,
}


func _ready() -> void:
	for species in TreeSpeciesScript.SPECIES:
		resource_counts[species["wood_resource"]] = 0
	for species in TreeSpeciesScript.FRUIT_SPECIES:
		resource_counts[species["wood_resource"]] = 0
		resource_counts[species["fruit_resource"]] = 0
	for entry in MetalTypesScript.TABLE:
		resource_counts[entry["id"]] = 0
	for entry in GemTypesScript.TABLE:
		resource_counts[entry["id"]] = 0
	for id in BerryTypesScript.all_ids():
		resource_counts[id] = 0


func add_resource(resource_name: String, amount: int = 1) -> void:
	resource_counts[resource_name] = resource_counts.get(resource_name, 0) + amount


func get_count(resource_name: String) -> int:
	return resource_counts.get(resource_name, 0)


func has_resource(resource_name: String, amount: int = 1) -> bool:
	return get_count(resource_name) >= amount


## Depense une ressource (construction). Renvoie false si pas assez.
func remove_resource(resource_name: String, amount: int = 1) -> bool:
	if not has_resource(resource_name, amount):
		return false
	resource_counts[resource_name] = get_count(resource_name) - amount
	return true
