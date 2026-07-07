extends RefCounted
## Table des types de baies (buissons/plantes). Meme pattern que
## TreeSpecies.gd/FRUIT_SPECIES : chaque type definit son id (utilise comme
## nom de ressource dans l'inventaire), son nom affiche et sa couleur.
##
## Les baies sont recoltees en inventaire via l'action "Cueillir" (comme les
## fruits d'arbres, voir BerryBush.gd) plutot que mangees directement au
## buisson - les nains mangent depuis l'inventaire quand ils ont faim (voir
## Dwarf.gd).
##
## Champs :
## - categorie : "buisson" (myrtille/groseille/cassis, poussent sur un vrai
##   buisson - boule + baies autour) ou "plante" (fraise/framboise, poussent
##   sur une plante basse - touffe de feuilles pres du sol) ; determine le
##   visuel construit par BerryBushes.gd.
## - calories  : valeur relative de faim restauree (voir Dwarf.gd) - une
##   baie est plus petite qu'un fruit d'arbre, donc des valeurs plus basses
##   que TreeSpecies.FRUIT_SPECIES.
const DataTableUtils := preload("res://scripts/data/materiaux/types/DataTableUtils.gd")

const TYPES := [
	{"id": "groseille", "nom": "Groseille", "couleur": Color(0.80, 0.15, 0.10), "categorie": "buisson", "calories": 18.0},
	{"id": "myrtille", "nom": "Myrtille", "couleur": Color(0.20, 0.16, 0.42), "categorie": "buisson", "calories": 20.0},
	{"id": "cassis", "nom": "Cassis", "couleur": Color(0.14, 0.05, 0.18), "categorie": "buisson", "calories": 22.0},
	{"id": "fraise", "nom": "Fraise", "couleur": Color(0.82, 0.08, 0.18), "categorie": "plante", "calories": 16.0},
	{"id": "framboise", "nom": "Framboise", "couleur": Color(0.70, 0.10, 0.28), "categorie": "plante", "calories": 18.0},
]


## Renvoie un type de baie au hasard (un par buisson genere, voir
## BerryBushes.gd), via un flux GameRandom dedie ("baies_types") pour rester
## deterministe a graine egale.
static func random_type() -> Dictionary:
	return TYPES[GameRandom.get_rng("baies_types").randi_range(0, TYPES.size() - 1)]


## Renvoie un type de baie par id, ou un dictionnaire vide si inconnu.
static func get_type(id: String) -> Dictionary:
	return DataTableUtils.find_by_id(TYPES, id)


## Calories d'une baie par id, -1.0 si inconnu (voir TreeSpecies.calories_for,
## meme convention).
static func calories_for(id: String) -> float:
	var t: Dictionary = get_type(id)
	if t.is_empty():
		return -1.0
	return t.get("calories", -1.0)


## Renvoie la liste de tous les id de baies (utilise par Dwarf.gd pour savoir
## quelles ressources d'inventaire comptent comme "nourriture").
static func all_ids() -> Array:
	var ids: Array = []
	for t in TYPES:
		ids.append(t["id"])
	return ids
