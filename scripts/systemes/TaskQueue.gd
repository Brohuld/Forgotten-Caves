extends Node
## File d'attente des taches designees par l'utilisateur (miner un bloc /
## couper un arbre / cueillir / construire / puiser / detruire). Les nains y
## piochent leur prochaine action au lieu d'errer au hasard, en priorisant la
## tache la plus proche d'eux (pas juste la premiere ajoutee).
##
## Toutes les taches ont un id unique, pour que ActionController puisse
## afficher une icone temporaire sur l'objet designe et la retirer une fois
## la tache terminee (voir Dwarf.gd/task_finished et ActionController.gd/
## _on_task_finished).

var tasks: Array = []
var next_task_id: int = 0


## Factorise les 5 fonctions add_*_task ci-dessous, qui dupliqueraient sinon
## a l'identique la generation d'id (next_task_id) et l'ajout au tableau
## "tasks" - seul le contenu propre a chaque type de tache change. "fields"
## doit deja contenir toutes les cles de la tache SAUF "id" (ajoutee ici).
func _add_task(fields: Dictionary) -> int:
	var id := next_task_id
	next_task_id += 1
	fields["id"] = id
	tasks.append(fields)
	return id


## Ajoute une tache de minage. walk_pos = ou le nain doit se placer,
## bx/by/bz = coordonnees du bloc a retirer dans VoxelWorld. clear_sol_above
## (Francois 2026-07-10) : uniquement pour un "trou" classique (creusage
## vertical depuis la vraie surface) - la vraie surface (SOL) juste au-dessus
## du bloc doit disparaitre avec lui (ouverture au ciel). JAMAIS pour un
## "couloir" (tunnel horizontal), qui doit laisser intact tout SOL fige plus
## haut dans la colonne (voir DwarfTaskResolver.complete_miner_task/
## VoxelWorld.clear_sol). Renvoie l'id unique de la tache (icone temporaire,
## voir ActionController.gd).
func add_mine_task(walk_pos: Vector3, bx: int, by: int, bz: int, clear_sol_above: bool = false) -> int:
	return _add_task({
		"type": "miner",
		"position": walk_pos,
		"bx": bx, "by": by, "bz": bz,
		"tree": null,
		"clear_sol_above": clear_sol_above,
	})


## Ajoute une tache de creusage d'escalier sur la colonne (bx,bz), du niveau
## top_y (sommet actuel, cote surface) au niveau bottom_y (le plus profond
## atteint via le geste clic+molette+clic, voir
## ActionDragController.finalize_stair_selection). Un seul nain traite TOUTE
## la plage en une seule tache (voir VoxelWorld.dig_stairs) - pas une tache
## par niveau. Renvoie l'id unique de la tache (icone temporaire, voir
## ActionController.gd).
func add_stair_task(walk_pos: Vector3, bx: int, bz: int, top_y: int, bottom_y: int) -> int:
	return _add_task({
		"type": "escalier",
		"position": walk_pos,
		"bx": bx, "bz": bz,
		"top_y": top_y, "bottom_y": bottom_y,
	})


## Ajoute une tache d'abattage sur un arbre (Node3D du groupe "trees").
## Renvoie l'id unique de la tache (icone temporaire, voir ActionController.gd).
func add_chop_task(tree: Node3D) -> int:
	return _add_task({
		"type": "couper",
		"position": tree.global_position,
		"tree": tree,
	})


## Ajoute une tache de cueillette sur un arbre fruitier ou un buisson
## (Node3D du groupe "cueillette", voir Forest.gd/BerryBushes.gd) - ne
## detruit pas la cible, contrairement a "couper" (voir Dwarf.gd/
## _complete_task). Renvoie l'id unique de la tache (icone temporaire, voir
## ActionController.gd).
func add_gather_task(target: Node3D) -> int:
	return _add_task({
		"type": "cueillir",
		"position": target.global_position,
		"tree": target,
	})


## Ajoute une tache de construction (mur bois/pierre/terre) a la colonne
## (bx,bz). Renvoie l'id unique de la tache (utilise pour gerer le mur
## fantome affiche pendant l'attente).
func add_build_task(walk_pos: Vector3, bx: int, bz: int, material: String) -> int:
	return _add_task({
		"type": "construire",
		"position": walk_pos,
		"bx": bx, "bz": bz,
		"material": material,
	})


## Ajoute une tache de puisage d'eau sur la colonne (bx,bz) - a la difference
## de "miner", le bloc n'est PAS retire (l'eau est une ressource renouvelable,
## voir VoxelWorld.is_water/Dwarf.gd/_complete_task "puiser"). Renvoie l'id
## unique de la tache (icone temporaire, voir ActionController.gd).
func add_puiser_task(walk_pos: Vector3, bx: int, bz: int) -> int:
	return _add_task({
		"type": "puiser",
		"position": walk_pos,
		"bx": bx, "bz": bz,
	})


## Ajoute une tache de demolition d'un mur construit (mur_bois/mur_pierre) a
## la colonne (bx,bz). "by" capture le sommet AU MOMENT DE LA DESIGNATION
## (meme convention que add_mine_task), utilise par VoxelWorld.remove_block a
## la fin de la tache. Renvoie l'id unique de la tache (icone temporaire,
## voir ActionController.gd).
func add_destroy_task(walk_pos: Vector3, bx: int, by: int, bz: int) -> int:
	return _add_task({
		"type": "detruire",
		"position": walk_pos,
		"bx": bx, "by": by, "bz": bz,
	})


func has_tasks() -> bool:
	return tasks.size() > 0


func task_count() -> int:
	return tasks.size()


## Retire et renvoie la tache la plus proche de "from_position" (priorite par
## distance, plutot que le simple ordre d'ajout) PARMI CELLES EXECUTABLES
## MAINTENANT. Une tache "miner" ciblant un bloc pas encore accessible (voir
## VoxelWorld.can_reach_block - regle Francois 2026-07-08 : un "trou" se
## creuse toujours depuis la surface, mais un "couloir" ne se creuse que
## depuis un point deja relie) est ignoree SANS etre retiree de la file -
## elle redeviendra candidate des qu'un chemin la reliera. Meme traitement
## pour une tache "miner" dont la cible est a plus d'1 niveau du nain SANS
## escalier connectant (regles de pathing, Francois 2026-07-08, voir
## VoxelWorld.can_walk_to_level) - le nain ne peut PAS y marcher pour
## l'instant, meme si le minage lui-meme serait autorise. Renvoie {} si
## aucune tache n'est executable actuellement, meme si la file n'est pas
## vide - l'appelant (Dwarf.gd) doit alors traiter ce nain comme s'il n'y
## avait pas de tache du tout pour cette frame (pas de crash sur "position"
## absente d'un dictionnaire vide).
func pop_nearest_task(from_position: Vector3, voxel_world: Node) -> Dictionary:
	var best_index := -1
	var best_dist := INF
	for i in range(tasks.size()):
		var task: Dictionary = tasks[i]
		if task["type"] == "miner" and not voxel_world.can_reach_block(task["bx"], task["by"], task["bz"]):
			continue
		if task["type"] == "miner" and not voxel_world.can_walk_to_level(int(round(from_position.y)), task["bx"], task["bz"], task["by"]):
			continue
		var d: float = (task["position"] - from_position).length()
		if d < best_dist:
			best_dist = d
			best_index = i
	if best_index == -1:
		return {}
	return tasks.pop_at(best_index)


## Remet une tache interrompue (faim/energie critique) dans la file
func requeue_task(task: Dictionary) -> void:
	tasks.push_front(task)


## Retire une tache encore dans la file (pas encore prise par un nain) par
## son id unique. Renvoie le dictionnaire retire, ou {} si aucune tache de
## cet id n'est dans la file (auquel cas elle est probablement deja affectee
## a un nain - voir ActionDragController.cancel_task, qui cherche ensuite
## cote Dwarf.current_task).
func remove_task(task_id: int) -> Dictionary:
	for i in range(tasks.size()):
		if tasks[i]["id"] == task_id:
			return tasks.pop_at(i)
	return {}
