extends RefCounted
## Sprint 20 : table des especes d'arbres. Chaque espece definit ses
## couleurs (tronc, branches, racines, feuillage), sa forme generale
## ("touffu" = chene, "conique" = sapin, "fin" = bouleau) et le type de
## bois recolte a la coupe (voir Forest.gd pour la construction du modele,
## et Dwarf.gd/_complete_task pour la recolte du bon type de bois).
##
## Pour ajouter une espece, ajouter une entree ici avec les memes champs
## (reutiliser une "forme" existante, ou en gerer une nouvelle dans
## Forest._build_foliage si besoin d'une silhouette vraiment differente).
##
## Sprint 24bis : hauteurs de sapin/bouleau reduites (jugees trop hautes).
## Sprint 24ter : ajoute FRUIT_SPECIES (pommier/oranger/cerisier), separee de
## SPECIES pour que random_species() (utilisee par Forest.gd pour la foret
## "normale") ne pioche pas dedans - les arbres fruitiers sont places a part
## (voir Forest._spawn_fruit_tree). Champs supplementaires d'une espece
## fruitiere : fruit_resource (id de la ressource recoltee), fruit_color,
## fruit_count (nombre de fruits sur l'arbre a la generation).

const SPECIES := [
	{
		"id": "chene",
		"nom": "Chene",
		"wood_resource": "bois_chene",
		"forme": "touffu",
		"hauteur": 1.3,
		# 2026-07-05 (Francois : "augmenter de 20% les chenes en hauteur et
		# largeur") : multiplie tree.scale (voir Forest.gd/_spawn_tree) - grandit
		# tronc/feuilles/branches/racines proportionnellement, meme mecanisme
		# que le size_multiplier global existant (voir son commentaire).
		"echelle_base": 1.2,
		# 2026-07-05 (Francois : "augmente la taille du feuillage" du chene,
		# demande decomposee separement de l'echelle globale ci-dessus) :
		# facteur applique UNIQUEMENT aux blobs de feuillage (voir Forest.gd/
		# _build_foliage_touffu) - n'affecte pas les arbres fruitiers, qui
		# utilisent la meme forme "touffu" mais n'ont pas ce champ (defaut 1.0).
		"feuillage_echelle": 1.3,
		# 2026-07-05 (Francois : "assombrir les troncs des chenes") : etait
		# (0.42, 0.28, 0.16).
		"tronc_color": Color(0.28, 0.18, 0.10),
		"branche_color": Color(0.36, 0.24, 0.14),
		"racine_color": Color(0.30, 0.20, 0.12),
		# 2026-07-05 (2e ajustement du gradient, meme jour - Francois : "les
		# chenes doivent etre de la couleur des sapins actuels") : reprend
		# exactement l'ancienne couleur du sapin (avant qu'il soit encore
		# assombri ci-dessous), pour que chene > sapin dans le gradient.
		"feuillage_colors": [Color(0.04, 0.16, 0.06), Color(0.05, 0.19, 0.08)],
	},
	{
		"id": "sapin",
		"nom": "Sapin",
		"wood_resource": "bois_sapin",
		"forme": "conique",
		# 2026-07-05 (Francois : "augmenter de 30% la hauteur des sapins, mais
		# pas le diametre total des feuilles") : etait 1.85. Le rayon des cones
		# (voir _build_foliage_conique, lerp(0.48, 0.10, t)) ne depend pas de
		# cette valeur - seul le span vertical grandit, le diametre max des
		# feuilles reste 0.48 quelle que soit la hauteur.
		"hauteur": 2.405,  # Sprint 27 : remonte encore (etait 1.6, "arbres trop petits") -
		# le tronc visuel restant une fraction fixe de cette valeur (voir
		# _build_trunk), l'augmentation se voit surtout dans le feuillage conique
		# (plus haut), pas dans un tronc qui redeviendrait long.
		# 2026-07-05 (Francois : "assombrir les troncs des sapins") : etait
		# (0.35, 0.22, 0.13).
		"tronc_color": Color(0.22, 0.14, 0.08),
		"branche_color": Color(0.30, 0.19, 0.11),
		"racine_color": Color(0.26, 0.17, 0.10),
		# Sprint 37octodecies (2026-07-04, "pas assez fonce pour les sapins",
		# 3e signalement) : au-dela du ratio (deja corrige Sprint 37septdecies),
		# les cimes (spheres/cones) restent bien eclairees quel que soit
		# l'angle du soleil (normales dans toutes les directions, voir
		# DayNightCycle.LIGHT_ENERGY/AMBIENT_ENERGY) - contrairement au sol/
		# a l'eau (faces plates), donc leur albedo doit rester sombre en
		# valeur absolue pour paraitre "vert fonce" a l'ecran. Assombri.
		# 2026-07-05 (2e ajustement, meme jour - "les sapins peuvent etre tres
		# fonces") : le chene reprenant maintenant l'ancienne couleur du
		# sapin (voir ci-dessus), le sapin est encore assombri pour rester
		# nettement le plus sombre des 6 especes.
		"feuillage_colors": [Color(0.02, 0.09, 0.03), Color(0.03, 0.11, 0.04)],
	},
	{
		"id": "bouleau",
		"nom": "Bouleau",
		"wood_resource": "bois_bouleau",
		"forme": "fin",
		"hauteur": 1.05,  # Sprint 24bis : etait 1.4, juge trop haut
		"tronc_color": Color(0.82, 0.80, 0.74),
		"branche_color": Color(0.70, 0.68, 0.62),
		"racine_color": Color(0.55, 0.50, 0.42),
		"feuillage_colors": [Color(0.30, 0.44, 0.16), Color(0.36, 0.50, 0.20)],  # Sprint 37unvicies : assombri (bouleau trop clair/jaune)
	},
]

## Sprint 24ter : arbres fruitiers - meme forme "touffu" (silhouette arrondie,
## coherente avec de vrais arbres fruitiers, plus bas que les arbres de foret).
## Sprint 24septies : ajoute "calories" (valeur relative de faim restauree par
## fruit mange, voir Dwarf.gd/_process_eating) - valeurs choisies a la main,
## pas de source reelle, ajustables si un fruit parait trop/pas assez nourrissant.
## Sprint 27 : hauteur du sapin remontee (voir SPECIES) ; "hauteur" de chene/
## bouleau/arbres fruitiers volontairement INCHANGEE (le tronc en depend
## directement pour ces formes, voir Forest.gd/_build_trunk) - l'augmentation
## de taille demandee passe par des branches/feuillages plus grands cote
## Forest.gd, pas par ce champ.
const FRUIT_SPECIES := [
	{
		"id": "pommier",
		"nom": "Pommier",
		"wood_resource": "bois_pommier",
		"forme": "touffu",
		"hauteur": 0.9,
		# 2026-07-05 (signale par Francois, "couleurs de troncs differentes pour
		# les 3 fruitiers" - les 3 bruns etaient trop proches) : brun chaud,
		# le plus "classique", pour le pommier.
		"tronc_color": Color(0.44, 0.29, 0.15),
		"branche_color": Color(0.34, 0.23, 0.13),
		"racine_color": Color(0.28, 0.19, 0.11),
		# 2026-07-05 (gradient clair->fonce demande : bouleau > pommier >
		# cerisier > oranger > chene > sapin) : juste sous le bouleau.
		"feuillage_colors": [Color(0.18, 0.42, 0.14), Color(0.22, 0.46, 0.16)],
		"fruit_resource": "pomme",
		"fruit_color": Color(0.75, 0.10, 0.12),
		# 2026-07-05 (2e passe, meme jour - "les fruits ne sont visibles que
		# d'un cote") : chaque fruit a une direction aleatoire independante
		# sur son blob, donc statistiquement seule la moitie des fruits fait
		# face a la camera a un instant donne (l'autre moitie est cachee par
		# le feuillage du cote oppose) - ce n'est pas un bug de repartition,
		# juste un effet d'occlusion normal. Augmente encore le nombre total
		# pour qu'il en reste suffisamment de visibles cote camera (9 -> 14 -> 22).
		"fruit_count": 22,
		"fruit_radius": 0.10,
		"calories": 35.0,
	},
	{
		"id": "oranger",
		"nom": "Oranger",
		"wood_resource": "bois_oranger",
		"forme": "touffu",
		# 2026-07-05 (signale par Francois, "les orangers doivent etre plus
		# petits que les autres fruitiers") : etait la plus haute des 3 (0.95),
		# desormais nettement la plus basse.
		"hauteur": 0.72,
		# Ecorce plus claire/grisee (agrumes), pour se distinguer du pommier/
		# cerisier.
		"tronc_color": Color(0.58, 0.50, 0.35),
		"branche_color": Color(0.48, 0.41, 0.28),
		"racine_color": Color(0.40, 0.34, 0.23),
		# 2026-07-05 (gradient clair->fonce demande) : plus fonce que le
		# cerisier, plus clair que le chene.
		"feuillage_colors": [Color(0.13, 0.32, 0.13), Color(0.16, 0.35, 0.15)],
		"fruit_resource": "orange",
		"fruit_color": Color(0.95, 0.55, 0.10),
		"fruit_count": 22,  # 2026-07-05 (2e passe) : voir commentaire pommier ci-dessus
		"fruit_radius": 0.10,
		"calories": 30.0,
	},
	{
		"id": "cerisier",
		"nom": "Cerisier",
		"wood_resource": "bois_cerisier",
		"forme": "touffu",
		"hauteur": 0.85,
		# Ecorce plus sombre/rougeatre (cerisier), pour se distinguer du
		# pommier/oranger.
		"tronc_color": Color(0.30, 0.15, 0.13),
		"branche_color": Color(0.26, 0.13, 0.11),
		"racine_color": Color(0.22, 0.12, 0.10),
		# 2026-07-05 (gradient clair->fonce demande) : plus fonce que le
		# pommier, plus clair que l'oranger.
		"feuillage_colors": [Color(0.18, 0.37, 0.13), Color(0.21, 0.40, 0.15)],
		"fruit_resource": "cerise",
		"fruit_color": Color(0.55, 0.05, 0.12),
		# 2026-07-05 (signale par Francois, "cerises beaucoup trop grosses" +
		# "il faut plus de cerises") : rayon reduit (une cerise reste petite,
		# contrairement a la pomme/l'orange) et compte augmente nettement -
		# un cerisier porte en vrai beaucoup de petits fruits.
		# 2026-07-05 (2e passe, meme jour) : voir commentaire pommier plus
		# haut (occlusion normale, environ moitie des fruits visibles a la
		# fois cote camera) - encore augmente (16 -> 26).
		"fruit_count": 26,
		"fruit_radius": 0.06,
		"calories": 22.0,  # petit fruit, moins nourrissant malgre un arbre plus "genereux" en fruits
	},
]


## Renvoie une espece au hasard parmi les arbres de foret (chene/sapin/bouleau
## - voir Forest.gd, boucle des tree_count arbres "normaux")
static func random_species() -> Dictionary:
	return SPECIES[randi_range(0, SPECIES.size() - 1)]


## Sprint 24ter : renvoie une espece fruitiere au hasard (voir Forest.gd,
## boucle separee des arbres fruitiers)
static func random_fruit_species() -> Dictionary:
	return FRUIT_SPECIES[randi_range(0, FRUIT_SPECIES.size() - 1)]


## Renvoie une espece (foret ou fruitiere) par id, ou la premiere de SPECIES
## si l'id est inconnu
static func get_species(id: String) -> Dictionary:
	for s in SPECIES:
		if s["id"] == id:
			return s
	for s in FRUIT_SPECIES:
		if s["id"] == id:
			return s
	return SPECIES[0]


## Sprint 24ter : indique si "resource_id" est le fruit d'une espece fruitiere
## (utilise par Dwarf.gd/_resource_color pour colorer l'item recolte)
static func is_fruit(resource_id: String) -> bool:
	for s in FRUIT_SPECIES:
		if s.get("fruit_resource", "") == resource_id:
			return true
	return false


## Sprint 24ter : couleur d'un fruit par id de ressource, blanc si inconnu
static func fruit_color_for(resource_id: String) -> Color:
	for s in FRUIT_SPECIES:
		if s.get("fruit_resource", "") == resource_id:
			return s.get("fruit_color", Color.WHITE)
	return Color.WHITE


## Sprint 24septies : calories d'un fruit par id de ressource (voir
## Dwarf.gd/_process_eating), -1.0 si inconnu (permet a l'appelant de
## distinguer "pas un fruit" d'une vraie valeur)
static func calories_for(resource_id: String) -> float:
	for s in FRUIT_SPECIES:
		if s.get("fruit_resource", "") == resource_id:
			return s.get("calories", -1.0)
	return -1.0
