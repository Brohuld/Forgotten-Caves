extends RefCounted
## Table des pierres precieuses trouvables en filons dans la pierre (voir
## VoxelWorld.gd/_setup_vein_noises et VeinMaterials.gd pour la generation).
## Meme pattern que MetalTypes.gd/TreeSpecies.gd : const TABLE + static func,
## facile a etendre.
##
## Champs : voir MetalTypes.gd (memes champs id/nom/rarete/couleur).
## Rarete par defaut "rare" pour cette categorie, sauf exceptions ("tres_rare").
const DataTableUtils := preload("res://scripts/data/materiaux/types/DataTableUtils.gd")

const TABLE := [
	{"id": "emeraude", "nom": "Emeraude", "rarete": "rare", "couleur": Color(0.10, 0.55, 0.30)},
	{"id": "rubis", "nom": "Rubis", "rarete": "rare", "couleur": Color(0.75, 0.08, 0.15)},
	{"id": "saphir", "nom": "Saphir", "rarete": "rare", "couleur": Color(0.12, 0.28, 0.68)},
	{"id": "lapis_lazuli", "nom": "Lapis-lazuli", "rarete": "rare", "couleur": Color(0.20, 0.24, 0.52)},
	{"id": "jade", "nom": "Jade", "rarete": "rare", "couleur": Color(0.40, 0.65, 0.48)},
	{"id": "diamant_blanc", "nom": "Diamant blanc", "rarete": "rare", "couleur": Color(0.90, 0.94, 0.97)},
	{"id": "diamant_rose", "nom": "Diamant rose", "rarete": "tres_rare", "couleur": Color(0.93, 0.75, 0.80)},
	{"id": "diamant_noir", "nom": "Diamant noir", "rarete": "tres_rare", "couleur": Color(0.14, 0.13, 0.15)},
	# Exemple pour ajouter une future pierre precieuse (non utilise pour l'instant) :
	# {"id": "opale", "nom": "Opale", "rarete": "rare", "couleur": Color(0.85, 0.88, 0.9)},
]


## Renvoie la definition d'une pierre precieuse par id, ou un dictionnaire vide si inconnu
static func get_type(id: String) -> Dictionary:
	return DataTableUtils.find_by_id(TABLE, id)
