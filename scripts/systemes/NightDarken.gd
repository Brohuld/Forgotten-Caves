extends RefCounted
## 2026-07-06 (revue de code, paquet H, A2/I65) : utilitaire partage pour
## assombrir un materiau SHADING_MODE_UNSHADED la nuit - jusqu'ici chaque
## systeme decoratif unshaded (CloudSystem.gd, WaterfallFoamClouds.gd)
## reimplementait sa propre copie de ce calcul (M30 : duplication constatee
## entre ces 2 fichiers), et un 3e cas (tas de ressources, DwarfResourcePile.gd)
## avait ete oublie entierement (I65 : "les tas restent identiques jour et
## nuit"). Objet de cet utilitaire : UNE seule formule partagee, reutilisable
## par tout futur objet unshaded, plutot que de re-decouvrir/re-implementer ce
## calcul a chaque nouvelle feature.
##
## Limite connue et acceptee (voir decision Francois du 2026-07-06) : ceci
## reste une fonction utilitaire simple (calcul + application ponctuelle), PAS
## un systeme d'assombrissement "vivant" automatique. Un objet dont le
## materiau est cree UNE FOIS et jamais revisite (comme un tas de ressources,
## contrairement aux nuages qui ont leur propre _process() a chaque frame) aura
## la bonne teinte AU MOMENT DE SA CREATION, mais ne continuera pas a
## s'assombrir/eclaircir tout seul ensuite si la partie continue longtemps sur
## le meme tas. Un vrai systeme "vivant" (groupe Godot dedie + reapplication
## par frame) serait un chantier separe si ce besoin devient genant en jeu.

const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")


## Facteur d'assombrissement nocturne actuel (0 = plein jour, 1 = pleine nuit),
## a partir du champ base_light_energy de DayNightCycle (voir CloudSystem.gd/
## I43 - source de verite independante de l'ordre d'execution). "day_night"
## peut etre null (noeud non trouve) - repli sur 0.0 (jour) plutot que de
## planter.
static func night_factor(day_night: Node) -> float:
	if day_night == null:
		return 0.0
	var day_energy: float = DayNightCycleScript.LIGHT_ENERGY[1]
	return 1.0 - clampf(day_night.base_light_energy / maxf(day_energy, 0.001), 0.0, 1.0)


## Applique l'assombrissement nocturne a "base_color" - meme formule que
## CloudSystem._update_all_colors/WaterfallFoamClouds._update_all_colors
## (interpolation vers "night_tint", jamais totalement noir). "strength"
## borne l'intensite maximale de l'assombrissement (ex: 0.8).
static func apply(base_color: Color, factor: float, night_tint: Color, strength: float) -> Color:
	return base_color.lerp(Color(night_tint.r, night_tint.g, night_tint.b, base_color.a), factor * strength)
