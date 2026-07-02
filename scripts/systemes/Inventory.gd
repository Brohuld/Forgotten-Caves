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

var resource_counts: Dictionary = {
	"bois": 0,
	"bois_chene": 0,
	"bois_sapin": 0,
	"bois_bouleau": 0,
	"pierre": 0,
	"terre": 0,
	# Metaux (Sprint 23)
	"fer": 0,
	"cuivre": 0,
	"etain": 0,
	"charbon": 0,
	"argent": 0,
	"or": 0,
	"platine": 0,
	# Pierres precieuses (Sprint 23)
	"emeraude": 0,
	"rubis": 0,
	"saphir": 0,
	"lapis_lazuli": 0,
	"jade": 0,
	"diamant_blanc": 0,
	"diamant_rose": 0,
	"diamant_noir": 0,
}


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
