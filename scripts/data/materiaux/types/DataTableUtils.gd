extends RefCounted
## Recherche generique par "id" dans une table de donnees (Array[Dictionary]),
## utilisee par MetalTypes.gd/GemTypes.gd/BerryTypes.gd pour eviter de
## dupliquer la meme boucle de recherche dans chaque fichier.


## Renvoie une COPIE de la premiere entree de "table" dont la cle "id" vaut
## "id_value", ou un dictionnaire vide si aucune ne correspond. La copie
## (duplicate()) evite qu'un appelant modifie par erreur l'entree partagee
## de la table centrale.
static func find_by_id(table: Array, id_value: String) -> Dictionary:
	for entry in table:
		if entry["id"] == id_value:
			return entry.duplicate()
	return {}
