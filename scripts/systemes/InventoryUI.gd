extends RefCounted
## Panneau d'inventaire complet (toutes les ressources connues d'Inventory.gd,
## groupees par categorie), ancre en haut a droite de l'ecran. Utilise le
## controle "Tree" natif de Godot - le pli/depli de chaque categorie est deja
## gere par Godot lui-meme (fleche cliquable), aucune logique de pli/depli a
## ecrire ici.
##
## Meme pattern que ClimateUI.gd : instancie UNE FOIS (voir
## ActionController.gd/inventory_ui), setup() construit l'arbre et garde une
## reference vers chaque TreeItem, update() ne fait QUE modifier le texte des
## items deja crees - PAS de clear()+reconstruction a chaque frame, ce qui
## reinitialiserait l'etat plie/deplie choisi par le joueur a chaque frame et
## viderait tout l'interet d'un arbre repliable.
##
## Categories : Bois (par essence, y compris les arbres fruitiers qui donnent
## aussi du bois a la coupe - Chene/Sapin/Bouleau/Pommier/Oranger/Cerisier),
## Fruits (Pomme/Orange/Cerise), Baies (Groseille/Myrtille/Cassis/Fraise/
## Framboise), Metaux (Fer/Cuivre/Etain/Charbon/Argent/Or/Platine), Pierres
## precieuses (8 types). Pierre/Terre/Eau restent des lignes seules (pas de
## sous-categorie, une seule ressource generique chacune).
## Le total affiche sur la ligne "Bois" reutilise le compteur GENERIQUE
## "bois" (deja alimente en parallele de chaque compteur par essence, voir
## DwarfTaskResolver.complete_couper_task/DwarfResourcePile.
## spawn_starting_wood_stock) plutot qu'une somme recalculee - c'est deja la
## meme valeur, et c'est le compteur reellement lu par la construction. Les
## autres categories (Fruits/Baies/Metaux/Pierres precieuses) n'ont pas de
## compteur generique equivalent dans Inventory.gd : leur total affiche est
## donc la somme des enfants, recalculee a chaque update().

const TreeSpeciesScript := preload("res://scripts/data/materiaux/types/bois/TreeSpecies.gd")
const BerryTypesScript := preload("res://scripts/data/materiaux/types/baies/BerryTypes.gd")
const MetalTypesScript := preload("res://scripts/data/materiaux/types/metaux/MetalTypes.gd")
const GemTypesScript := preload("res://scripts/data/materiaux/types/pierres_precieuses/GemTypes.gd")

const PANEL_WIDTH := 560.0
const PANEL_HEIGHT := 1200.0
const TREE_FONT_SIZE := 24
const TITLE_FONT_SIZE := 28

# Meme garde que ClimateUI._is_setup : evite une reconstruction/double-ajout
# silencieux en cas d'appel multiple de setup().
var _is_setup: bool = false

var _tree: Tree
# resource_id (String) -> TreeItem, pour les lignes "feuille" (une ressource
# precise, pas de sous-categorie).
var _leaf_items: Dictionary = {}
var _leaf_labels: Dictionary = {}
# category_id (String, ex: "bois") -> TreeItem de la ligne categorie.
var _category_items: Dictionary = {}
var _category_labels: Dictionary = {}
# category_id -> Array[String] des resource_id enfants (pour la somme
# affichee sur la ligne categorie, sauf "bois" qui a son propre compteur
# generique - voir update()).
var _category_children: Dictionary = {}


func setup(parent: CanvasLayer) -> void:
	if _is_setup:
		return
	_is_setup = true

	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -(PANEL_WIDTH + 16.0)
	panel.offset_top = 16.0
	panel.offset_right = -16.0
	panel.offset_bottom = 16.0 + PANEL_HEIGHT
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Inventaire"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	vbox.add_child(title)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_tree.add_theme_font_size_override("font_size", TREE_FONT_SIZE)
	vbox.add_child(_tree)

	var root: TreeItem = _tree.create_item()

	_add_category(root, "bois", "Bois", _wood_entries())
	_add_category(root, "fruits", "Fruits", _fruit_entries())
	_add_category(root, "baies", "Baies", _berry_entries())
	_add_category(root, "metaux", "Metaux", _metal_entries())
	_add_category(root, "pierres_precieuses", "Pierres precieuses", _gem_entries())

	_add_leaf(root, "pierre", "Pierre")
	_add_leaf(root, "terre", "Terre")
	_add_leaf(root, "eau", "Eau")


## Met a jour le texte de chaque ligne (feuille + categorie) a partir des
## compteurs actuels d'Inventory - AUCUNE creation/suppression de TreeItem
## ici, donc l'etat plie/deplie choisi par le joueur est preserve.
func update(inventory: Node) -> void:
	if not _is_setup:
		return
	for resource_id in _leaf_items:
		var item: TreeItem = _leaf_items[resource_id]
		item.set_text(0, "%s : %d" % [_leaf_labels[resource_id], inventory.get_count(resource_id)])
	for category_id in _category_items:
		var total: int
		if category_id == "bois":
			total = inventory.get_count("bois")
		else:
			total = 0
			for resource_id in _category_children[category_id]:
				total += inventory.get_count(resource_id)
		_category_items[category_id].set_text(0, "%s : %d" % [_category_labels[category_id], total])


## entries : Array de {"id": resource_id, "nom": libelle affiche}.
func _add_category(root: TreeItem, category_id: String, label: String, entries: Array) -> void:
	var item: TreeItem = _tree.create_item(root)
	_category_items[category_id] = item
	_category_labels[category_id] = label
	var child_ids: Array = []
	for entry in entries:
		_add_leaf(item, entry["id"], entry["nom"])
		child_ids.append(entry["id"])
	_category_children[category_id] = child_ids


func _add_leaf(parent_item: TreeItem, resource_id: String, label: String) -> void:
	var item: TreeItem = _tree.create_item(parent_item)
	_leaf_items[resource_id] = item
	_leaf_labels[resource_id] = label


## Une entree par essence, foret ET fruitiere confondues (les arbres
## fruitiers donnent aussi du bois a la coupe, voir DwarfTaskResolver.
## complete_couper_task).
func _wood_entries() -> Array:
	var entries: Array = []
	for species in TreeSpeciesScript.SPECIES:
		entries.append({"id": species["wood_resource"], "nom": species["nom"]})
	for species in TreeSpeciesScript.FRUIT_SPECIES:
		entries.append({"id": species["wood_resource"], "nom": species["nom"]})
	return entries


## Pas de champ "nom" dedie au fruit dans FRUIT_SPECIES (seulement au nom de
## l'arbre, ex: "Pommier") - capitalize() sur l'id de la ressource
## ("pomme" -> "Pomme") suffit, ce sont des mots simples sans accent/tiret.
func _fruit_entries() -> Array:
	var entries: Array = []
	for species in TreeSpeciesScript.FRUIT_SPECIES:
		var fruit_id: String = species["fruit_resource"]
		entries.append({"id": fruit_id, "nom": fruit_id.capitalize()})
	return entries


func _berry_entries() -> Array:
	var entries: Array = []
	for entry in BerryTypesScript.TYPES:
		entries.append({"id": entry["id"], "nom": entry["nom"]})
	return entries


func _metal_entries() -> Array:
	var entries: Array = []
	for entry in MetalTypesScript.TABLE:
		entries.append({"id": entry["id"], "nom": entry["nom"]})
	return entries


func _gem_entries() -> Array:
	var entries: Array = []
	for entry in GemTypesScript.TABLE:
		entries.append({"id": entry["id"], "nom": entry["nom"]})
	return entries
