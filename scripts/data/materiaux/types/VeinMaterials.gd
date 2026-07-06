extends RefCounted
## Sprint 23 : regroupe MetalTypes.gd et GemTypes.gd en une seule liste,
## triee du plus rare au plus commun (utilise par VoxelWorld.gd pour la
## generation des filons : verifier les materiaux rares en premier evite
## qu'un materiau commun "prenne" un bloc avant qu'un materiau rare ait pu
## y pretendre, voir _setup_vein_noises/generate_flat_terrain).
##
## Egalement utilise par Dwarf.gd (_resource_color) pour retrouver la couleur
## d'un minerai/pierre precieuse recolte, sans dupliquer les couleurs.
##
## 2026-07-06 (revue de code, paquet H, I17) : atlas_order()/atlas_index()
## (Sprint 23quater, approche "atlas de textures" via tools/gen_vein_atlas.py)
## supprimees - ce fichier Python n'existe plus dans le depot et ces 2
## fonctions n'etaient appelees nulle part ailleurs (approche abandonnee).

const MetalTypes := preload("res://scripts/data/materiaux/types/metaux/MetalTypes.gd")
const GemTypes := preload("res://scripts/data/materiaux/types/pierres_precieuses/GemTypes.gd")

const RARITY_ORDER := ["tres_rare", "rare", "commun"]


## Liste combinee metaux + pierres precieuses, triee du plus rare au plus commun
static func all() -> Array:
	var combined: Array = []
	combined.append_array(MetalTypes.TABLE)
	combined.append_array(GemTypes.TABLE)
	# 2026-07-06 (revue de code, paquet H, M13) : une "rarete" absente de
	# RARITY_ORDER (faute de frappe) donnait RARITY_ORDER.find() = -1, ce qui
	# la placait silencieusement EN TETE (plus rare que "tres_rare") sans
	# aucun avertissement - averti ici une seule fois par materiau concerne.
	for entry in combined:
		if not RARITY_ORDER.has(entry["rarete"]):
			push_warning("VeinMaterials.all() : materiau \"%s\" a une rarete inconnue (\"%s\"), absente de RARITY_ORDER - trie en tete par defaut." % [entry.get("id", "?"), entry["rarete"]])
	combined.sort_custom(func(a, b): return RARITY_ORDER.find(a["rarete"]) < RARITY_ORDER.find(b["rarete"]))
	return combined


## Renvoie la definition d'un materiau (metal ou pierre precieuse) par id,
## ou un dictionnaire vide si inconnu
static func get_type(id: String) -> Dictionary:
	var found: Dictionary = MetalTypes.get_type(id)
	if not found.is_empty():
		return found
	return GemTypes.get_type(id)


## Sprint 23sexies : indique si un materiau est un metal (true) ou une pierre
## precieuse (false) - utilise par VoxelWorld.gd pour choisir la forme des
## "pepites" 3D (rondes pour les metaux, a facettes pour les pierres precieuses)
## et les reglages de materiau (metallic/roughness vs emission), sans avoir a
## dupliquer un champ "categorie" dans MetalTypes.gd/GemTypes.gd.
static func is_metal(id: String) -> bool:
	return not MetalTypes.get_type(id).is_empty()
