extends RefCounted
## Table des especes d'arbres. Chaque espece definit ses couleurs (tronc,
## branches, racines, feuillage), sa forme generale ("touffu" = chene/
## fruitiers, "conique" = sapin, "fin" = bouleau) et le type de bois recolte
## a la coupe (voir Forest.gd pour la construction du modele, et Dwarf.gd
## pour la recolte du bon type de bois).
##
## Champs optionnels d'une espece de foret (SPECIES) :
## - echelle_base      : multiplicateur global de taille par-dessus le
##   size_multiplier commun a tous les arbres (voir Forest.gd) - grandit
##   tronc/feuilles/branches/racines proportionnellement pour cette espece.
## - feuillage_echelle : multiplicateur applique uniquement aux blobs de
##   feuillage (voir Forest.gd/_build_foliage_touffu), independant de
##   echelle_base.
##
## FRUIT_SPECIES (arbres fruitiers, places a part de la foret "normale" -
## voir Forest.gd) partage les memes champs que SPECIES, plus :
## - fruit_resource : id de la ressource recoltee via l'action "Cueillir"
## - fruit_color    : couleur des fruits
## - fruit_count    : nombre de fruits generes sur l'arbre. Chaque fruit a
##   une orientation aleatoire independante autour de son blob de feuillage,
##   donc seule une partie environ est visible cote camera a un instant
##   donne (l'autre moitie est masquee par le feuillage du cote oppose) -
##   les valeurs sont donc plus hautes que le nombre "visible" souhaite.
## - fruit_radius   : rayon d'un fruit
## - calories       : valeur relative de faim restauree par fruit mange
##   (voir Dwarf.gd), valeurs choisies a la main sans source reelle.
##
## Pour ajouter une espece : ajouter une entree ici avec les memes champs
## (reutiliser une "forme" existante, ou en gerer une nouvelle dans
## Forest._build_foliage si besoin d'une silhouette vraiment differente).

const SPECIES := [
	{
		"id": "chene",
		"nom": "Chene",
		"wood_resource": "bois_chene",
		"forme": "touffu",
		"hauteur": 1.3,
		"echelle_base": 1.2,
		"feuillage_echelle": 1.3,
		"tronc_color": Color(0.28, 0.18, 0.10),
		"branche_color": Color(0.36, 0.24, 0.14),
		"racine_color": Color(0.30, 0.20, 0.12),
		"feuillage_colors": [Color(0.04, 0.16, 0.06), Color(0.05, 0.19, 0.08)],
	},
	{
		"id": "sapin",
		"nom": "Sapin",
		"wood_resource": "bois_sapin",
		"forme": "conique",
		# Le rayon des cones (voir Forest._build_foliage_conique,
		# lerp(0.48, 0.10, t)) ne depend pas de "hauteur" - seul le span
		# vertical du feuillage suit cette valeur, le diametre max reste 0.48
		# quelle que soit la hauteur totale de l'arbre.
		"hauteur": 2.405,
		"tronc_color": Color(0.22, 0.14, 0.08),
		"branche_color": Color(0.30, 0.19, 0.11),
		"racine_color": Color(0.26, 0.17, 0.10),
		"feuillage_colors": [Color(0.02, 0.09, 0.03), Color(0.03, 0.11, 0.04)],
	},
	{
		"id": "bouleau",
		"nom": "Bouleau",
		"wood_resource": "bois_bouleau",
		"forme": "fin",
		"hauteur": 1.05,
		"tronc_color": Color(0.82, 0.80, 0.74),
		"branche_color": Color(0.70, 0.68, 0.62),
		"racine_color": Color(0.55, 0.50, 0.42),
		"feuillage_colors": [Color(0.30, 0.44, 0.16), Color(0.36, 0.50, 0.20)],
	},
]

const FRUIT_SPECIES := [
	{
		"id": "pommier",
		"nom": "Pommier",
		"wood_resource": "bois_pommier",
		"forme": "touffu",
		"hauteur": 0.9,
		"tronc_color": Color(0.44, 0.29, 0.15),
		"branche_color": Color(0.34, 0.23, 0.13),
		"racine_color": Color(0.28, 0.19, 0.11),
		"feuillage_colors": [Color(0.18, 0.42, 0.14), Color(0.22, 0.46, 0.16)],
		"fruit_resource": "pomme",
		"fruit_color": Color(0.75, 0.10, 0.12),
		"fruit_count": 22,
		"fruit_radius": 0.10,
		"calories": 35.0,
	},
	{
		"id": "oranger",
		"nom": "Oranger",
		"wood_resource": "bois_oranger",
		"forme": "touffu",
		"hauteur": 0.72,
		"tronc_color": Color(0.58, 0.50, 0.35),
		"branche_color": Color(0.48, 0.41, 0.28),
		"racine_color": Color(0.40, 0.34, 0.23),
		"feuillage_colors": [Color(0.13, 0.32, 0.13), Color(0.16, 0.35, 0.15)],
		"fruit_resource": "orange",
		"fruit_color": Color(0.95, 0.55, 0.10),
		"fruit_count": 22,
		"fruit_radius": 0.10,
		"calories": 30.0,
	},
	{
		"id": "cerisier",
		"nom": "Cerisier",
		"wood_resource": "bois_cerisier",
		"forme": "touffu",
		"hauteur": 0.85,
		"tronc_color": Color(0.30, 0.15, 0.13),
		"branche_color": Color(0.26, 0.13, 0.11),
		"racine_color": Color(0.22, 0.12, 0.10),
		"feuillage_colors": [Color(0.18, 0.37, 0.13), Color(0.21, 0.40, 0.15)],
		"fruit_resource": "cerise",
		"fruit_color": Color(0.55, 0.05, 0.12),
		"fruit_count": 26,
		"fruit_radius": 0.06,
		"calories": 22.0,  # petit fruit, moins nourrissant qu'une pomme/orange
	},
]


## Renvoie une espece au hasard parmi les arbres de foret (chene/sapin/
## bouleau - voir Forest.gd), via un flux GameRandom dedie ("arbres_especes")
## pour rester deterministe a graine egale.
static func random_species() -> Dictionary:
	return SPECIES[GameRandom.get_rng("arbres_especes").randi_range(0, SPECIES.size() - 1)]


## Renvoie une espece fruitiere au hasard (voir Forest.gd, boucle separee des
## arbres fruitiers), meme flux GameRandom que random_species().
static func random_fruit_species() -> Dictionary:
	return FRUIT_SPECIES[GameRandom.get_rng("arbres_especes").randi_range(0, FRUIT_SPECIES.size() - 1)]


## Renvoie une espece (foret ou fruitiere) par id, ou la premiere de SPECIES
## si l'id est inconnu.
static func get_species(id: String) -> Dictionary:
	for s in SPECIES:
		if s["id"] == id:
			return s
	for s in FRUIT_SPECIES:
		if s["id"] == id:
			return s
	return SPECIES[0]


## Renvoie l'espece fruitiere dont "fruit_resource" vaut "resource_id", ou un
## dictionnaire vide si aucune ne correspond.
static func _fruit_species_for(resource_id: String) -> Dictionary:
	for s in FRUIT_SPECIES:
		if s.get("fruit_resource", "") == resource_id:
			return s
	return {}


## Indique si "resource_id" est le fruit d'une espece fruitiere (utilise par
## Dwarf.gd pour colorer l'item recolte).
static func is_fruit(resource_id: String) -> bool:
	return not _fruit_species_for(resource_id).is_empty()


## Couleur d'un fruit par id de ressource, blanc si inconnu.
static func fruit_color_for(resource_id: String) -> Color:
	return _fruit_species_for(resource_id).get("fruit_color", Color.WHITE)


## Calories d'un fruit par id de ressource (voir Dwarf.gd), -1.0 si inconnu
## (permet a l'appelant de distinguer "pas un fruit" d'une vraie valeur).
static func calories_for(resource_id: String) -> float:
	return _fruit_species_for(resource_id).get("calories", -1.0)
