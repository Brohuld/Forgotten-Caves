extends RefCounted
## Sprint 19 : table des climats. Un seul climat est reellement implemente
## pour l'instant (tempere), mais la structure est prete a en accueillir
## d'autres plus tard (aride, enneige...) sans changer le reste du code :
## il suffit d'ajouter une entree dans CLIMATES, avec les memes champs.
##
## Champs de chaque climat :
## - nom              : nom affiche
## - herbe_base        : couleur de reference de l'herbe/vegetation pour ce climat
## - herbe_variations   : petites variations de teinte utilisees sur les touffes
##                       d'herbe pour casser la monotonie (au moins 1 couleur)
## - fleurs            : couleurs possibles pour les fleurs (une par "espece")
## - terrain_par_saison : Sprint 21 (couleur du sol/herbe du terrain lui-meme,
##                       voir VoxelWorld._grass_color_for) - une couleur de base
##                       par saison. Une seule saison ("ete") est vraiment geree
##                       pour l'instant, mais la structure est prete a en
##                       accueillir d'autres (automne, hiver...) sans toucher
##                       au reste du code : il suffit d'ajouter une entree.

const CLIMATES := {
	"tempere": {
		"nom": "Tempere",
		# Sprint 24 : herbe assombrie d'environ 20% (jugee trop claire) par
		# rapport aux couleurs d'origine du Sprint 19/21.
		"herbe_base": Color(0.36, 0.50, 0.22),
		"herbe_variations": [
			Color(0.32, 0.46, 0.19),
			Color(0.40, 0.53, 0.26),
			Color(0.35, 0.48, 0.24),
		],
		"fleurs": [
			Color(0.85, 0.15, 0.25),  # rouge
			Color(0.90, 0.80, 0.20),  # jaune
			Color(0.70, 0.35, 0.80),  # violet
		],
		"terrain_par_saison": {
			"ete": Color(0.34, 0.46, 0.19),
			# Exemple pour une future saison (non utilise pour l'instant) :
			# "automne": Color(0.55, 0.46, 0.20),
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

# Sprint 21 : liste des saisons geree par le jeu. Une seule pour l'instant ;
# on pourra en ajouter d'autres plus tard (voir terrain_par_saison ci-dessus).
const SEASONS := ["ete"]
const DEFAULT_SEASON := "ete"


## Renvoie la definition d'un climat par id, ou celle du climat par defaut
## si l'id est inconnu (evite un crash si le champ climate_id est mal saisi)
static func get_climate(id: String) -> Dictionary:
	return CLIMATES.get(id, CLIMATES[DEFAULT_CLIMATE])


## Renvoie la couleur de base du terrain/sol pour un climat et une saison
## donnes (Sprint 21). Retombe sur la saison par defaut si la saison demandee
## n'existe pas encore pour ce climat, puis sur herbe_base si le climat n'a
## meme pas de table terrain_par_saison (securite pour un climat mal defini).
static func get_terrain_color(climate_id: String, season_id: String) -> Color:
	var climate: Dictionary = get_climate(climate_id)
	var par_saison: Dictionary = climate.get("terrain_par_saison", {})
	if par_saison.has(season_id):
		return par_saison[season_id]
	if par_saison.has(DEFAULT_SEASON):
		return par_saison[DEFAULT_SEASON]
	return climate.get("herbe_base", Color(0.36, 0.50, 0.22))
