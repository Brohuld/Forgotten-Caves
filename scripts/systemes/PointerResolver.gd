extends RefCounted
## Resout precisement CE QUI est reellement sous le curseur (ou sous un point
## ecran donne), quel que soit le type d'objet - terrain (raymarching voxel,
## voir VoxelWorld.raycast_visible_face) OU n'importe quel objet portant un
## collider Hoverable (tas, arbre, buisson, et tout futur objet - porte,
## meuble, arme, recolte... voir Hoverable.gd). Les deux candidats sont
## compares par distance REELLE le long du rayon - le plus proche de la
## camera gagne, exactement ce qui serait visuellement devant l'autre. Aucune
## connaissance du type d'objet ici : ajouter un futur objet survolable ne
## touche jamais ce fichier (feedback Francois 2026-07-10).
##
## Remplace l'ancienne recherche par proximite (rayon fixe 1.0-2.0 unites
## autour d'un point) qui debordait sur les cases voisines pres d'une berge/
## falaise - un objet "presque a cote" pouvait gagner a tort sur le terrain
## reellement vise. Ne sait PAS decrire ce qu'il trouve (separation des
## responsabilites) - voir EntityDescriptions.describe_by_kind pour les
## entites, ActionInspector.describe_block_at pour le terrain.

const HoverableScript := preload("res://scripts/systemes/Hoverable.gd")

const MAX_DIST := 300.0


## Renvoie null (rien de visible touche), ou un Dictionary :
## - {"kind": "entity", "node": Node3D, "hit": Vector3} - "node" est le
##   noeud PORTEUR du collider (owner passe a Hoverable.attach, celui qui
##   porte la metadonnee "hover_kind" - voir EntityDescriptions).
## - {"kind": "terrain", "cell": Vector3i, "hit": Vector3}
static func resolve(controller: CanvasLayer, ray_origin: Vector3, ray_dir: Vector3) -> Variant:
	var camera: Camera3D = controller.get("camera")
	var voxel_world: Node3D = controller.get("voxel_world")

	var entity_pos = null
	var entity_node: Node3D = null
	if camera != null:
		var space_state := camera.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * MAX_DIST)
		query.collision_mask = 1 << (HoverableScript.HOVERABLE_LAYER - 1)
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var result: Dictionary = space_state.intersect_ray(query)
		if not result.is_empty():
			entity_pos = result["position"]
			entity_node = (result["collider"] as Node3D).get_parent()

	var terrain_hit = voxel_world.raycast_visible_face(ray_origin, ray_dir) if voxel_world != null else null

	var entity_dist: float = ray_origin.distance_to(entity_pos) if entity_pos != null else INF
	var terrain_dist: float = ray_origin.distance_to(terrain_hit["hit"]) if terrain_hit != null else INF

	if entity_dist == INF and terrain_dist == INF:
		return null
	if entity_dist <= terrain_dist:
		return {"kind": "entity", "node": entity_node, "hit": entity_pos}
	return {"kind": "terrain", "cell": terrain_hit["cell"], "hit": terrain_hit["hit"]}
