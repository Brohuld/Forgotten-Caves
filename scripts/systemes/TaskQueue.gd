extends Node
## Sprint 4 : file d'attente des taches designees par l'utilisateur
## (miner un bloc / couper un arbre). Les nains y piochent leur prochaine
## action au lieu d'errer au hasard.
## Sprint 6 : le nain pioche la tache la plus proche de lui, pas juste
## la premiere ajoutee (priorite par distance).
## Sprint 9bis : chaque tache de construction a un id unique, pour pouvoir
## retirer son mur "fantome" une fois la construction terminee (Sprint 26 :
## toutes les taches ont maintenant un id, voir plus bas).
## Sprint 24ter : ajoute la tache "cueillir" (recolte de fruits/baies sans
## abattre l'arbre/buisson, voir add_gather_task).
## Sprint 26 : toutes les taches (pas seulement "construire") ont maintenant
## un id unique, pour que ActionController puisse afficher une icone
## temporaire sur l'objet designe et la retirer une fois la tache terminee
## (voir Dwarf.gd/task_finished et ActionController.gd/_on_task_finished).

var tasks: Array = []
var next_task_id: int = 0


## Ajoute une tache de minage. walk_pos = ou le nain doit se placer,
## bx/by/bz = coordonnees du bloc a retirer dans VoxelWorld. Renvoie l'id
## unique de la tache (icone temporaire, voir ActionController.gd).
func add_mine_task(walk_pos: Vector3, bx: int, by: int, bz: int) -> int:
	var id := next_task_id
	next_task_id += 1
	tasks.append({
		"type": "miner",
		"id": id,
		"position": walk_pos,
		"bx": bx, "by": by, "bz": bz,
		"tree": null,
	})
	return id


## Ajoute une tache d'abattage sur un arbre (Node3D du groupe "trees").
## Renvoie l'id unique de la tache (icone temporaire, voir ActionController.gd).
func add_chop_task(tree: Node3D) -> int:
	var id := next_task_id
	next_task_id += 1
	tasks.append({
		"type": "couper",
		"id": id,
		"position": tree.global_position,
		"tree": tree,
	})
	return id


## Sprint 24ter : ajoute une tache de cueillette sur un arbre fruitier ou un
## buisson (Node3D du groupe "cueillette", voir Forest.gd/BerryBushes.gd) -
## ne detruit pas la cible, contrairement a "couper" (voir Dwarf.gd/_complete_task).
## Renvoie l'id unique de la tache (icone temporaire, voir ActionController.gd).
func add_gather_task(target: Node3D) -> int:
	var id := next_task_id
	next_task_id += 1
	tasks.append({
		"type": "cueillir",
		"id": id,
		"position": target.global_position,
		"tree": target,
	})
	return id


## Ajoute une tache de construction (mur bois/pierre/terre) a la colonne
## (bx,bz). Renvoie l'id unique de la tache (utilise pour gerer le mur
## fantome affiche pendant l'attente).
func add_build_task(walk_pos: Vector3, bx: int, bz: int, material: String) -> int:
	var id := next_task_id
	next_task_id += 1
	tasks.append({
		"type": "construire",
		"id": id,
		"position": walk_pos,
		"bx": bx, "bz": bz,
		"material": material,
	})
	return id


## Sprint 36 : ajoute une tache de puisage d'eau sur la colonne (bx,bz) - a la
## difference de "miner", le bloc n'est PAS retire (l'eau est une ressource
## renouvelable, voir VoxelWorld.is_water/Dwarf.gd/_complete_task "puiser").
## Renvoie l'id unique de la tache (icone temporaire, voir ActionController.gd).
func add_puiser_task(walk_pos: Vector3, bx: int, bz: int) -> int:
	var id := next_task_id
	next_task_id += 1
	tasks.append({
		"type": "puiser",
		"id": id,
		"position": walk_pos,
		"bx": bx, "bz": bz,
	})
	return id


func has_tasks() -> bool:
	return tasks.size() > 0


func task_count() -> int:
	return tasks.size()


## Retire et renvoie la tache la plus proche de "from_position" (priorite
## par distance, plutot que la simple ordre d'ajout)
func pop_nearest_task(from_position: Vector3) -> Dictionary:
	var best_index := 0
	var best_dist := INF
	for i in range(tasks.size()):
		var d: float = (tasks[i]["position"] - from_position).length()
		if d < best_dist:
			best_dist = d
			best_index = i
	return tasks.pop_at(best_index)


## Sprint 8 : remet une tache interrompue (faim/energie critique) dans la file
func requeue_task(task: Dictionary) -> void:
	tasks.push_front(task)
