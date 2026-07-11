extends RefCounted
## Attache un collider de detection "souris" GENERIQUE a n'importe quel objet
## du monde (tas de ressources, arbre, buisson, et tout futur objet placable
## - porte, meuble, arme, recolte...). Convention volontairement minimale :
## un objet devient "survolable/ciblable" des qu'il possede UNE Area3D sur
## HOVERABLE_LAYER. Ce fichier ne connait QUE la geometrie (forme/position du
## collider) - decrire l'objet trouve est une responsabilite separee (voir
## EntityDescriptions.describe_by_kind, qui lit une metadonnee "hover_kind"
## posee par l'entite elle-meme). PointerResolver.gd (le resolveur qui
## utilise ce collider) n'a besoin d'AUCUNE connaissance du type d'objet, et
## ce fichier non plus - donc ajouter un futur type d'objet ne touche jamais
## ni le resolveur ni ce fichier (feedback Francois 2026-07-10 : "on ne va
## pas dans le futur avoir un probleme avec de nouveaux objets").
##
## Remplace l'ancienne detection par proximite (ActionInspector.
## closest_resource_pile / ActionValidator.closest_in_group, distance a un
## point avec un rayon fixe 1.0-2.0) : un vrai volume de collision donne une
## reponse geometrique exacte (le rayon doit reellement entrer dans le
## volume), plus de "fuite" possible vers une case voisine.
##
## Area3D plutot que StaticBody3D : aucune collision physique reelle requise
## (les nains ne doivent pas heurter un tas de bois), seulement la
## detection par raycast (voir PointerResolver.resolve, collide_with_areas).
## monitoring/monitorable desactives (pas besoin des signaux d'entree/sortie
## de zone) - un raycast avec collide_with_areas=true detecte le collider
## independamment de ces deux flags.

## Bit de calque dedie (voir project.godot, layer_names/3d_physics/layer_3) -
## separe de tout futur calque de gameplay (mouvement des nains, projectiles)
## pour que ce raycast de detection n'interagisse jamais avec eux.
const HOVERABLE_LAYER := 3


## Cree et attache le collider. "shape" est en unites LOCALES a "owner" - pas
## besoin de la mettre a l'echelle manuellement, l'Area3D est un enfant direct
## de "owner" et herite donc automatiquement de sa position/rotation/echelle
## (ex: DwarfResourcePile.pile.scale qui grossit avec le compte du tas).
## "shape_offset" decale le centre du volume (ex: remonter un cylindre pour
## qu'il englobe le tronc+feuillage d'un arbre plutot que d'etre centre au
## sol). Ne pose AUCUNE metadonnee de description - c'est a l'appelant de
## poser "hover_kind" sur "owner" (pas sur le collider), voir
## EntityDescriptions.describe_by_kind.
static func attach(owner: Node3D, shape: Shape3D, shape_offset: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = "HoverCollider"
	area.collision_layer = 1 << (HOVERABLE_LAYER - 1)
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = shape_offset
	area.add_child(col)
	owner.add_child(area)
	return area


## Active/desactive le collider d'un objet DEJA attache via attach() - a
## appeler chaque fois que l'objet devient visible/invisible (ex: masque par
## le niveau de vue/molette, meme regle que Node3D.visible ailleurs dans le
## code). IMPORTANT : Node3D.visible=false ne desactive PAS la collision par
## defaut - sans cet appel, un objet cache par la coupe resterait quand meme
## detectable par le survol/ciblage (PointerResolver), ce qui contredirait
## "le pointeur pointe toujours sur ce qui est reellement affiche" (feedback
## Francois 2026-07-10). Ne fait rien si "owner" n'a pas de collider attache.
static func set_enabled(owner: Node3D, enabled: bool) -> void:
	var area := owner.get_node_or_null("HoverCollider")
	if area != null:
		area.collision_layer = (1 << (HOVERABLE_LAYER - 1)) if enabled else 0
