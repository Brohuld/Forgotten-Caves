extends RefCounted
## 2026-07-06 (revue de code, paquet B, M17) : factorise le motif de
## recherche lineaire par "id" duplique a l'identique dans MetalTypes.gd/
## GemTypes.gd/BerryTypes.gd (fonction get_type) - meme structure de donnees
## (Array[Dictionary], chaque entree ayant une cle "id"), meme boucle, seul
## le nom de la table changeait d'un fichier a l'autre (seuil DRY de 3
## occurrences atteint, axe 14).


## Renvoie la premiere entree de "table" dont la cle "id" vaut "id_value",
## ou un dictionnaire vide si aucune ne correspond - comportement identique
## aux anciennes fonctions get_type() qu'elle remplace.
## 2026-07-06 (revue de code, paquet H, M14/M63) : .duplicate() sur l'entree
## trouvee - avant ce correctif, l'appelant recevait une reference DIRECTE
## vers l'entree de la table centrale (partagee par tout le jeu) ; un futur
## appelant qui modifierait le dictionnaire retourne aurait corrompu cette
## table pour tout le monde. Aucun appelant actuel ne mute ce retour (verifie
## par grep sur tout le repo avant ce changement), donc sans risque de
## regression aujourd'hui.
static func find_by_id(table: Array, id_value: String) -> Dictionary:
	for entry in table:
		if entry["id"] == id_value:
			return entry.duplicate()
	return {}
