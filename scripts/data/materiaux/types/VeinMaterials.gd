extends RefCounted
## Regroupe MetalTypes.gd et GemTypes.gd en une seule liste, triee du plus
## rare au plus commun (utilise par VoxelWorld.gd pour la generation des
## filons : verifier les materiaux rares en premier evite qu'un materiau
## commun "prenne" un bloc avant qu'un materiau rare ait pu y pretendre).
##
## Egalement utilise par Dwarf.gd pour retrouver la couleur d'un minerai/
## pierre precieuse recolte, sans dupliquer les couleurs.

const MetalTypes := preload("res://scripts/data/materiaux/types/metaux/MetalTypes.gd")
const GemTypes := preload("res://scripts/data/materiaux/types/pierres_precieuses/GemTypes.gd")

const RARITY_ORDER := ["tres_rare", "rare", "commun"]


## Liste combinee metaux + pierres precieuses, triee du plus rare au plus
## commun. Avertit (sans planter) si un materiau a une "rarete" absente de
## RARITY_ORDER : sort_custom() le placerait sinon silencieusement en tete
## (find() renvoie -1 dans ce cas, le plus petit index possible).
static func all() -> Array:
	var combined: Array = []
	combined.append_array(MetalTypes.TABLE)
	combined.append_array(GemTypes.TABLE)
	for entry in combined:
		if not RARITY_ORDER.has(entry["rarete"]):
			push_warning("VeinMaterials.all() : materiau \"%s\" a une rarete inconnue (\"%s\"), absente de RARITY_ORDER - trie en tete par defaut." % [entry.get("id", "?"), entry["rarete"]])
	combined.sort_custom(func(a, b): return RARITY_ORDER.find(a["rarete"]) < RARITY_ORDER.find(b["rarete"]))
	return combined


## Renvoie la definition d'un materiau (metal ou pierre precieuse) par id,
## ou un dictionnaire vide si inconnu.
static func get_type(id: String) -> Dictionary:
	var found: Dictionary = MetalTypes.get_type(id)
	if not found.is_empty():
		return found
	return GemTypes.get_type(id)


## Indique si un materiau est un metal (true) ou une pierre precieuse
## (false) - utilise par VoxelWorld.gd pour choisir la forme des "pepites"
## 3D (rondes pour les metaux, a facettes pour les pierres precieuses) et
## les reglages de materiau (metallic/roughness vs emission), sans avoir a
## dupliquer un champ "categorie" dans MetalTypes.gd/GemTypes.gd.
static func is_metal(id: String) -> bool:
	return not MetalTypes.get_type(id).is_empty()
