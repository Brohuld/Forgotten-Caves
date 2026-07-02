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
		"tronc_color": Color(0.42, 0.28, 0.16),
		"branche_color": Color(0.36, 0.24, 0.14),
		"racine_color": Color(0.30, 0.20, 0.12),
		"feuillage_colors": [Color(0.22, 0.50, 0.18), Color(0.28, 0.56, 0.22)],
	},
	{
		"id": "sapin",
		"nom": "Sapin",
		"wood_resource": "bois_sapin",
		"forme": "conique",
		"hauteur": 1.85,  # Sprint 27 : remonte encore (etait 1.6, "arbres trop petits") -
		# le tronc visuel restant une fraction fixe de cette valeur (25%, voir
		# _build_trunk), l'augmentation se voit surtout dans le feuillage conique
		# (plus haut), pas dans un tronc qui redeviendrait long.
		"tronc_color": Color(0.35, 0.22, 0.13),
		"branche_color": Color(0.30, 0.19, 0.11),
		"racine_color": Color(0.26, 0.17, 0.10),
		"feuillage_colors": [Color(0.14, 0.35, 0.22), Color(0.17, 0.40, 0.26)],
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
		"feuillage_colors": [Color(0.55, 0.68, 0.30), Color(0.62, 0.74, 0.36)],
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
		"tronc_color": Color(0.40, 0.27, 0.15),
		"branche_color": Color(0.34, 0.23, 0.13),
		"racine_color": Color(0.28, 0.19, 0.11),
		"feuillage_colors": [Color(0.24, 0.52, 0.20), Color(0.30, 0.58, 0.24)],
		"fruit_resource": "pomme",
		"fruit_color": Color(0.75, 0.10, 0.12),
		"fruit_count": 5,
		"calories": 35.0,
	},
	{
		"id": "oranger",
		"nom": "Oranger",
		"wood_resource": "bois_oranger",
		"forme": "touffu",
		"hauteur": 0.95,
		"tronc_color": Color(0.38, 0.25, 0.14),
		"branche_color": Color(0.32, 0.21, 0.12),
		"racine_color": Color(0.27, 0.18, 0.10),
		"feuillage_colors": [Color(0.18, 0.46, 0.20), Color(0.22, 0.52, 0.24)],
		"fruit_resource": "orange",
		"fruit_color": Color(0.95, 0.55, 0.10),
		"fruit_count": 5,
		"calories": 30.0,
	},
	{
		"id": "cerisier",
		"nom": "Cerisier",
		"wood_resource": "bois_cerisier",
		"forme": "touffu",
		"hauteur": 0.85,
		"tronc_color": Color(0.36, 0.22, 0.14),
		"branche_color": Color(0.30, 0.19, 0.12),
		"racine_color": Color(0.25, 0.16, 0.10),
		"feuillage_colors": [Color(0.26, 0.54, 0.22), Color(0.32, 0.60, 0.26)],
		"fruit_resource": "cerise",
		"fruit_color": Color(0.55, 0.05, 0.12),
		"fruit_count": 6,
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
