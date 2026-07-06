extends RefCounted
## 2026-07-06 (revue de code, paquet B, M17) : get_type() delegue desormais a
## DataTableUtils.find_by_id() (motif duplique aussi dans GemTypes.gd/
## BerryTypes.gd) - comportement inchange.
const DataTableUtils := preload("res://scripts/data/materiaux/types/DataTableUtils.gd")
## Sprint 23 : table des metaux trouvables en filons dans la pierre (voir
## VoxelWorld.gd/_setup_vein_noises et VeinMaterials.gd pour la generation).
## Meme pattern que TreeSpecies.gd/ClimateDefinitions.gd : const TABLE +
## static func, facile a etendre (il suffit d'ajouter une entree).
##
## Champs de chaque metal :
## - id      : identifiant utilise comme nom de ressource dans l'inventaire
## - nom     : nom affiche
## - rarete  : "commun", "rare" ou "tres_rare" (determine la frequence du filon,
##             voir VoxelWorld.RARITY_THRESHOLDS)
## - couleur : couleur du bloc de filon dans la roche + de l'item recolte au sol

const TABLE := [
	{"id": "fer", "nom": "Fer", "rarete": "commun", "couleur": Color(0.55, 0.30, 0.22)},
	{"id": "cuivre", "nom": "Cuivre", "rarete": "commun", "couleur": Color(0.72, 0.38, 0.16)},
	{"id": "etain", "nom": "Etain", "rarete": "commun", "couleur": Color(0.70, 0.72, 0.74)},
	{"id": "charbon", "nom": "Charbon", "rarete": "commun", "couleur": Color(0.10, 0.10, 0.11)},
	{"id": "argent", "nom": "Argent", "rarete": "rare", "couleur": Color(0.85, 0.86, 0.88)},
	{"id": "or", "nom": "Or", "rarete": "tres_rare", "couleur": Color(0.95, 0.78, 0.15)},
	{"id": "platine", "nom": "Platine", "rarete": "tres_rare", "couleur": Color(0.80, 0.83, 0.90)},
	# Exemple pour ajouter un futur metal (non utilise pour l'instant) :
	# {"id": "mithril", "nom": "Mithril", "rarete": "tres_rare", "couleur": Color(0.6, 0.8, 0.85)},
]


## Renvoie la definition d'un metal par id, ou un dictionnaire vide si inconnu
static func get_type(id: String) -> Dictionary:
	return DataTableUtils.find_by_id(TABLE, id)
