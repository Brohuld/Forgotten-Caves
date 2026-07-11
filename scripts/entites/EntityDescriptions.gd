extends RefCounted
## Texte de survol pour les entites du monde (tas de ressources, arbres,
## buissons/plantes) - deplace depuis ActionInspector.gd le 2026-07-10 :
## le systeme d'inspection generique (ActionInspector/PointerResolver) ne
## connait plus aucun type d'entite particulier, seulement des colliders
## Hoverable (voir Hoverable.gd). Colocalise ici (dans scripts/entites/)
## plutot que dans scripts/systemes/ pour eviter toute dependance
## circulaire : DwarfResourcePile.gd/Forest.gd/BerryBushes.gd (entites)
## peuvent preloader ce fichier (autre entite) sans jamais dependre de
## scripts/systemes/.
##
## describe_by_kind() est le SEUL point a completer pour ajouter un futur
## type d'objet survolable (porte, meuble, arme, recolte...) - chaque entite
## pose sa propre metadonnee "hover_kind" a sa creation (voir
## DwarfResourcePile._attach_hover_collider/Forest._spawn_tree/
## BerryBushes._spawn_bush pour des exemples), ce fichier fait juste le lien
## entre ce nom et la fonction de description correspondante. Rien d'autre
## dans le systeme de survol/ciblage (Hoverable.gd, PointerResolver.gd)
## n'a besoin d'etre modifie.
static func describe_by_kind(node: Node3D) -> String:
	match String(node.get_meta("hover_kind", "")):
		"pile":
			return describe_resource_pile(node)
		"gatherable":
			return describe_gatherable(node)
		_:
			return ""

## "Pile de N <ressource>" - lu depuis les metadonnees posees a la creation
## du tas (voir DwarfResourcePile.add_to_resource_pile).
static func describe_resource_pile(pile: Node3D) -> String:
	var resource_name: String = String(pile.get_meta("resource_name"))
	var count: int = int(pile.get_meta("count"))
	return "Pile de %d %s" % [count, resource_name.capitalize()]


## Nom + etat de recolte d'un arbre/buisson/plante, via les metadonnees deja
## posees par Forest.gd/BerryBushes.gd ("species_name", "fruits_left").
## Suffixe "[Interdit]" si toggle_interdit_entity (ActionDragController.gd) a
## marque ce noeud - sans ca, rien ne permet au joueur de savoir qu'un arbre
## est interdit (Couper/Cueillir echouent silencieusement dessus, voir
## handle_chop_click/handle_gather_click).
static func describe_gatherable(node: Node) -> String:
	var species_name: String = node.get_meta("species_name", "?")
	var suffix: String = "  [Interdit]" if node.get_meta("interdit", false) else ""
	if not node.is_in_group("cueillette"):
		return species_name + suffix
	var fruits_left: int = node.get_meta("fruits_left", -1)
	if fruits_left < 0:
		return species_name + suffix
	if fruits_left == 0:
		return "%s (vide)%s" % [species_name, suffix]
	return "%s - %d fruit(s) restant(s)%s" % [species_name, fruits_left, suffix]
