extends RefCounted
## Table des climats du jeu. Un seul climat est actuellement defini (tempere),
## mais la structure supporte d'en ajouter d'autres (aride, enneige...) en
## ajoutant simplement une entree a CLIMATES avec les memes champs.
##
## Champs de chaque climat :
## - nom              : nom affiche
## - herbe_base        : couleur de reference de l'herbe/vegetation
## - herbe_variations   : variations de teinte pour les touffes d'herbe (au
##                       moins 1 couleur), pour casser la monotonie visuelle
## - fleurs            : couleurs possibles des fleurs (une par "espece")
## - terrain_par_saison : couleur de base du sol/herbe du terrain par saison
##                       (voir VoxelWorld._grass_color_for) - une entree par
##                       saison (voir SEASONS plus bas)

const CLIMATES := {
	"tempere": {
		"nom": "Tempere",
		"herbe_base": Color(0.17, 0.36, 0.13),
		"herbe_variations": [
			Color(0.15, 0.32, 0.11),
			Color(0.19, 0.40, 0.15),
			Color(0.17, 0.37, 0.14),
		],
		"fleurs": [
			Color(0.85, 0.15, 0.25),  # rouge
			Color(0.90, 0.80, 0.20),  # jaune
			Color(0.70, 0.35, 0.80),  # violet
		],
		"terrain_par_saison": {
			"ete": Color(0.23, 0.39, 0.09),
			"automne": Color(0.62, 0.48, 0.24),
			"hiver": Color(0.90, 0.92, 0.94),
			"printemps": Color(0.30, 0.54, 0.24),
		},
	},
	# Exemple pour ajouter un futur climat (non utilise pour l'instant) :
	# "aride": {
	#     "nom": "Aride",
	#     "herbe_base": Color(0.68, 0.58, 0.30),
	#     "herbe_variations": [Color(0.62, 0.52, 0.26), Color(0.72, 0.62, 0.34)],
	#     "fleurs": [Color(0.9, 0.55, 0.15)],
	#     "terrain_par_saison": {"ete": Color(0.62, 0.54, 0.26)},
	# },
}

const DEFAULT_CLIMATE := "tempere"

## Saisons gerees par le jeu, dans l'ordre de rotation (voir SeasonSystem.gd).
const SEASONS := ["ete", "automne", "hiver", "printemps"]
const DEFAULT_SEASON := "ete"


## Renvoie l'id de la saison courante d'un SeasonSystem (ou tout noeud
## exposant current_season_id()), ou DEFAULT_SEASON si "season_system" est null.
static func season_id_or_default(season_system) -> String:
	return season_system.current_season_id() if season_system else DEFAULT_SEASON


## Renvoie la definition d'un climat par id, ou celle du climat par defaut
## si l'id est inconnu (evite un crash si le champ climate_id est mal saisi).
static func get_climate(id: String) -> Dictionary:
	return CLIMATES.get(id, CLIMATES[DEFAULT_CLIMATE])


## Renvoie la couleur de base du terrain/sol pour un climat et une saison
## donnes. Retombe sur la saison par defaut si la saison demandee n'existe
## pas encore pour ce climat, puis sur herbe_base si le climat n'a meme pas
## de table terrain_par_saison (securite pour un climat mal defini).
static func get_terrain_color(climate_id: String, season_id: String) -> Color:
	var climate: Dictionary = get_climate(climate_id)
	var par_saison: Dictionary = climate.get("terrain_par_saison", {})
	if par_saison.has(season_id):
		return par_saison[season_id]
	if par_saison.has(DEFAULT_SEASON):
		return par_saison[DEFAULT_SEASON]
	return climate.get("herbe_base", Color(0.36, 0.50, 0.22))
