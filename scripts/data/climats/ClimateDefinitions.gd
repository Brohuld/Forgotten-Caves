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
		# Sprint 37duodecies (2026-07-04, signale par Francois : "l'herbe est
		# vert tres fonce/marron, il faut un vert normal") : eclaircie/plus
		# saturee par rapport a la version Sprint 24 (qui l'avait assombrie de
		# 20%, jugee alors trop claire) - avec le passage a un materiau REELEMENT
		# eclaire (Sprint 29/day-night, plus SHADING_MODE_UNSHADED), la base
		# couleur parait plus sombre qu'avant a luminosite egale, d'ou ce
		# rattrapage.
		# Sprint 37quaterdecies (2026-07-04, meme plainte persistante : "l'herbe
		# et l'eau ont toujours des couleurs trop sombres") : eclaircissement
		# nettement plus marque cette fois (le rattrapage precedent etait trop
		# timide), combine a la remontee de LIGHT_ENERGY/AMBIENT_ENERGY dans
		# DayNightCycle.gd (voir la aussi pour la cause : perte d'energie du
		# calcul de diffusion reel par rapport a un rendu "unshaded").
		# Sprint 37septdecies (2026-07-04, signale par Francois : "le vert de
		# l'herbe devrait etre tres proche de celui des buissons (un peu plus
		# fonce) et pas kaki") : le vrai bug etait le RATIO rouge/vert, pas la
		# luminosite - (0.52,0.74,0.34) a un ratio R:G ~0.70, ce qui tire
		# n'importe quel vert vers le kaki/olive des que la lumiere l'eclaircit,
		# independamment de sa luminosite absolue. La couleur des buissons
		# (BerryBushes.gd, Color(0.20,0.42,0.16)/Color(0.25,0.45,0.15)) a un
		# ratio R:G ~0.47-0.55, un vrai vert. Herbe alignee sur cette teinte,
		# legerement plus foncee comme demande.
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
			# 2026-07-05 (cycle des saisons, demande explicite de Francois :
			# "herbe un peu plus jaune" en ete) : R/G legerement remontes, B
			# baisse - decale le ratio vers le jaune sans changer la luminosite
			# globale (etait Color(0.17, 0.36, 0.13)).
			"ete": Color(0.23, 0.39, 0.09),
			# 2026-07-02 (Sprint 33) : les 3 saisons manquantes sont remplies -
			# SeasonSystem.gd fait desormais vraiment tourner les 4 saisons.
			# Sprint 37duodecies : eclaircies dans la meme proportion que "ete"
			# ci-dessus (l'automne reste volontairement brun/orange - couleur
			# d'automne realiste - mais moins sombre/terne qu'avant).
			# Sprint 37septdecies : "ete"/"printemps" alignes sur le ratio
			# rouge/vert des buissons (voir commentaire herbe_base ci-dessus) -
			# l'automne reste volontairement brun/orange (couleur d'automne
			# realiste, differente par nature), l'hiver reste blanchi (neige).
			"automne": Color(0.62, 0.48, 0.24),
			"hiver": Color(0.90, 0.92, 0.94),
			# 2026-07-05 (cycle des saisons, "herbe plus claire" au printemps) :
			# tous les canaux remontes d'environ 50% (etait Color(0.20, 0.42, 0.16)).
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

# Sprint 21 : liste des saisons geree par le jeu.
# Sprint 33 : les 4 saisons tournent vraiment desormais (SeasonSystem.gd),
# dans cet ordre (ete -> automne -> hiver -> printemps -> ete...).
const SEASONS := ["ete", "automne", "hiver", "printemps"]
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
