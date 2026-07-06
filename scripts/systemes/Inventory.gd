extends Node
## Sprint 5 : inventaire global simple (compteur par ressource).
## Sera remplace plus tard par de vraies zones de stockage physiques.
## Sprint 20 : ajoute un compteur par espece de bois (chene/sapin/bouleau),
## en plus du compteur generique "bois" (qui reste le seul consomme par la
## construction, voir Dwarf.gd/_complete_task et ActionController.gd)
## Sprint 23 : ajoute un compteur par metal/pierre precieuse recolte en filon
## (voir VoxelWorld.gd/MetalTypes.gd/GemTypes.gd). Purement suivi en interne
## pour l'instant, pas encore affiche dans la barre de stats (deja chargee) -
## un vrai panneau d'inventaire viendra plus tard.
## Sprint 36 : ajoute "eau" (voir bouton Puiser/ActionController.gd), remplie
## par la tache "puiser" et consommee par les nains lorsque la soif est
## critique (voir Dwarf.gd/_try_start_drinking).
##
## 2026-07-06 (revue de code, paquet B, I23) : la liste des ids etait
## dupliquee ici a la main, desynchronisee des tables centrales (bois/fruits
## des especes fruitieres - bois_pommier/bois_oranger/bois_cerisier/pomme/
## orange/cerise - et les 5 baies n'y figuraient pas du tout, alors que
## add_resource() les gere deja correctement via son repli ".get(id, 0)").
## resource_counts est maintenant DERIVE des tables (MetalTypes.TABLE/
## GemTypes.TABLE/BerryTypes.TYPES/TreeSpecies.SPECIES/FRUIT_SPECIES) dans
## _ready() - un futur ajout dans une de ces tables apparait donc
## automatiquement ici, sans modification a faire dans ce fichier.
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


## Sprint 7 : depense une ressource (construction). Renvoie false si pas assez.
func remove_resource(resource_name: String, amount: int = 1) -> bool:
	if not has_resource(resource_name, amount):
		return false
	resource_counts[resource_name] = get_count(resource_name) - amount
	return true
