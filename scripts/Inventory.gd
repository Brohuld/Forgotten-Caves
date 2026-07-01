extends Node
## Sprint 5 : inventaire global simple (compteur par ressource).
## Sera remplace plus tard par de vraies zones de stockage physiques.

var resource_counts: Dictionary = {
	"bois": 0,
	"pierre": 0,
	"terre": 0,
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
