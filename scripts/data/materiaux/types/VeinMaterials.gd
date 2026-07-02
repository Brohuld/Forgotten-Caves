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
## Sprint 23quater : atlas_order()/atlas_index() donnent un ordre FIXE (pas
## trie par rarete, contrairement a all()) utilise pour placer chaque materiau
## dans l'atlas de textures des filons (voir VoxelWorld.gd/_atlas_uv_min et
## assets/vein_atlas.png, genere par tools/gen_vein_atlas.py). Important :
## cet ordre doit rester identique a la liste MATERIALS de gen_vein_atlas.py -
## si on ajoute un materiau, l'ajouter A LA FIN des deux listes, jamais au milieu.

const MetalTypes := preload("res://scripts/data/materiaux/types/metaux/MetalTypes.gd")
const GemTypes := preload("res://scripts/data/materiaux/types/pierres_precieuses/GemTypes.gd")

const RARITY_ORDER := ["tres_rare", "rare", "commun"]


## Liste combinee metaux + pierres precieuses, triee du plus rare au plus commun
static func all() -> Array:
	var combined: Array = []
	combined.append_array(MetalTypes.TABLE)
	combined.append_array(GemTypes.TABLE)
	combined.sort_custom(func(a, b): return RARITY_ORDER.find(a["rarete"]) < RARITY_ORDER.find(b["rarete"]))
	return combined


## Renvoie la definition d'un materiau (metal ou pierre precieuse) par id,
## ou un dictionnaire vide si inconnu
static func get_type(id: String) -> Dictionary:
	var found: Dictionary = MetalTypes.get_type(id)
	if not found.is_empty():
		return found
	return GemTypes.get_type(id)


## Ordre fixe (metaux puis pierres precieuses, dans l'ordre des tables) utilise
## pour l'atlas de textures - contrairement a all(), jamais retrie par rarete
## (l'atlas a une case fixe par materiau, elle ne doit pas bouger d'un appel a l'autre)
static func atlas_order() -> Array:
	var combined: Array = []
	combined.append_array(MetalTypes.TABLE)
	combined.append_array(GemTypes.TABLE)
	return combined


## Renvoie l'index (case) d'un materiau dans l'atlas, -1 si inconnu
static func atlas_index(id: String) -> int:
	var ordered: Array = atlas_order()
	for i in range(ordered.size()):
		if ordered[i]["id"] == id:
			return i
	return -1


## Sprint 23sexies : indique si un materiau est un metal (true) ou une pierre
## precieuse (false) - utilise par VoxelWorld.gd pour choisir la forme des
## "pepites" 3D (rondes pour les metaux, a facettes pour les pierres precieuses)
## et les reglages de materiau (metallic/roughness vs emission), sans avoir a
## dupliquer un champ "categorie" dans MetalTypes.gd/GemTypes.gd.
static func is_metal(id: String) -> bool:
	return not MetalTypes.get_type(id).is_empty()
