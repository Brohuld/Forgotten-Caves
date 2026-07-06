extends RefCounted
## 2026-07-06 (dette d'architecture A1, I60 - revue de code) : besoins
## critiques (repos/repas/boisson) extraits mecaniquement de Dwarf.gd -
## fonctions inchangees, seule la signature change ("dwarf" recoit le Dwarf
## via parametre au lieu d'un "self" implicite, meme motif que
## DwarfVisuals.gd/DwarfMovement.gd).
## Proprietes lues/ecrites via dwarf.get()/dwarf.set() (acces dynamique
## Godot, necessaire car "dwarf" est type generiquement Node3D, pas Dwarf).
## Delegue a DwarfVisuals.gd (reset_pose) et DwarfResourcePile.gd
## (resource_color) - preloades ci-dessous.
## HEAD_HEIGHT_APPROX duplique ci-dessous (deja duplique dans
## DwarfVisuals.gd) - a garder synchronise si la valeur d'origine change.

const HEAD_HEIGHT_APPROX := 0.95
const BerryTypes := preload("res://scripts/data/materiaux/types/baies/BerryTypes.gd")
const TreeSpecies := preload("res://scripts/data/materiaux/types/bois/TreeSpecies.gd")
const DwarfVisualsScript := preload("res://scripts/entites/DwarfVisuals.gd")
const DwarfResourcePileScript := preload("res://scripts/entites/DwarfResourcePile.gd")


## --- Repos (energie critique) : le nain s'allonge et dort sur place ---
static func start_resting(dwarf: Node3D) -> void:
	dwarf.set("is_resting", true)
	var dwarf_model: Node3D = dwarf.get("dwarf_model")
	dwarf_model.preview_animation = "Dormir"
	var sleep_indicator: Label3D = dwarf.get("sleep_indicator")
	sleep_indicator.visible = true
	var current_task: Dictionary = dwarf.get("current_task")
	if not current_task.is_empty():
		var task_queue: Node = dwarf.get("task_queue")
		task_queue.requeue_task(current_task)
		dwarf.set("current_task", {})


static func process_resting(dwarf: Node3D, delta: float) -> void:
	var energy_regen_rate: float = dwarf.get("energy_regen_rate")
	var energy_max: float = dwarf.get("energy_max")
	var energy: float = dwarf.get("energy")
	energy = min(energy + energy_regen_rate * delta, energy_max)
	dwarf.set("energy", energy)
	# le "Z z z" flotte doucement au-dessus de la tete
	var sleep_indicator: Label3D = dwarf.get("sleep_indicator")
	var model_scale: float = dwarf.get("model_scale")
	sleep_indicator.position.y = (HEAD_HEIGHT_APPROX + 0.35) * model_scale + sin(Time.get_ticks_msec() / 600.0) * 0.08
	var energy_rest_target: float = dwarf.get("energy_rest_target")
	if energy >= energy_rest_target:
		dwarf.set("is_resting", false)
		sleep_indicator.visible = false
		DwarfVisualsScript.reset_pose(dwarf)


## --- Repas depuis l'inventaire (faim critique, Sprint 24quater) ---
## Toutes les ressources considerees comme nourriture (baies + fruits d'arbres)
static func food_resource_ids() -> Array:
	var ids: Array = BerryTypes.all_ids()
	for s in TreeSpecies.FRUIT_SPECIES:
		ids.append(s["fruit_resource"])
	return ids


## 2026-07-06 (revue de code, paquet B, I62) : extrait de _try_start_eating/
## _try_start_drinking, qui dupliquaient a l'identique la teinte de
## l'indicateur, le passage en animation "Manger" et l'interruption de la
## tache en cours.
static func begin_meal_animation(dwarf: Node3D, resource_id_for_color: String) -> void:
	var food_indicator: MeshInstance3D = dwarf.get("food_indicator")
	var indicator_mat: StandardMaterial3D = food_indicator.get_surface_override_material(0)
	if indicator_mat:
		indicator_mat.albedo_color = DwarfResourcePileScript.resource_color(resource_id_for_color)
	var dwarf_model: Node3D = dwarf.get("dwarf_model")
	dwarf_model.preview_animation = "Manger"  # meme geste mains->bouche, reutilise aussi pour boire
	var current_task: Dictionary = dwarf.get("current_task")
	if not current_task.is_empty():
		var task_queue: Node = dwarf.get("task_queue")
		task_queue.requeue_task(current_task)
		dwarf.set("current_task", {})


## 2026-07-06 (revue de code, paquet B, I62) : extrait de _process_eating/
## _process_drinking, qui dupliquaient a l'identique l'avance du timer et le
## balancement de l'indicateur. Renvoie le timer mis a jour (GDScript ne
## passe pas les float par reference).
static func advance_meal_timer(dwarf: Node3D, timer: float, delta: float) -> float:
	var new_timer: float = timer + delta
	var food_indicator: MeshInstance3D = dwarf.get("food_indicator")
	var model_scale: float = dwarf.get("model_scale")
	food_indicator.visible = true
	food_indicator.position.z = (0.18 - absf(sin(new_timer * 14.0)) * 0.10) * model_scale
	return new_timer


## Cherche une ressource de nourriture disponible en inventaire ; si trouvee,
## interrompt la tache en cours (comme avant) et lance l'animation du repas
## sur place (pas de deplacement). Renvoie false si aucune nourriture stockee.
static func try_start_eating(dwarf: Node3D) -> bool:
	var inventory: Node = dwarf.get("inventory")
	var food_id: String = ""
	for id in food_resource_ids():
		if inventory.has_resource(id, 1):
			food_id = id
			break
	if food_id == "":
		return false

	dwarf.set("eating_food_id", food_id)
	begin_meal_animation(dwarf, food_id)
	dwarf.set("is_eating", true)
	dwarf.set("eat_timer", 0.0)
	return true


## Les deux bras du modele 3D convergent vers la bouche pendant "Manger" ;
## on fait juste suivre le fruit/la baie au meme rythme, puis on consomme la
## ressource depuis l'inventaire.
static func process_eating(dwarf: Node3D, delta: float) -> void:
	var eat_timer: float = advance_meal_timer(dwarf, dwarf.get("eat_timer"), delta)
	dwarf.set("eat_timer", eat_timer)

	var eat_duration: float = dwarf.get("eat_duration")
	if eat_timer >= eat_duration:
		var inventory: Node = dwarf.get("inventory")
		var eating_food_id: String = dwarf.get("eating_food_id")
		if eating_food_id != "" and inventory.remove_resource(eating_food_id, 1):
			var hunger_max: float = dwarf.get("hunger_max")
			var hunger: float = dwarf.get("hunger")
			hunger = min(hunger + food_calories(dwarf, eating_food_id), hunger_max)
			dwarf.set("hunger", hunger)
			# 2026-07-06 (revue de code, paquet D, I61) : instrumentation
			# conditionnee a OS.is_debug_build().
			if OS.is_debug_build():
				print("Le nain mange : %s (faim: %d)" % [eating_food_id, int(hunger)])
		dwarf.set("eating_food_id", "")
		dwarf.set("is_eating", false)
		var food_indicator: MeshInstance3D = dwarf.get("food_indicator")
		food_indicator.visible = false
		DwarfVisualsScript.reset_pose(dwarf)


## --- Boisson depuis l'inventaire (soif critique, Sprint 36) ---
## Tente de commencer a boire ; interrompt la tache en cours (comme la faim)
## et lance l'animation depuis l'inventaire. Renvoie false si pas d'eau stockee.
static func try_start_drinking(dwarf: Node3D) -> bool:
	var inventory: Node = dwarf.get("inventory")
	if not inventory.has_resource("eau", 1):
		return false

	begin_meal_animation(dwarf, "eau")
	dwarf.set("is_drinking", true)
	dwarf.set("drink_timer", 0.0)
	return true


static func process_drinking(dwarf: Node3D, delta: float) -> void:
	var drink_timer: float = advance_meal_timer(dwarf, dwarf.get("drink_timer"), delta)
	dwarf.set("drink_timer", drink_timer)

	var drink_duration: float = dwarf.get("drink_duration")
	if drink_timer >= drink_duration:
		var inventory: Node = dwarf.get("inventory")
		if inventory.remove_resource("eau", 1):
			var thirst_max: float = dwarf.get("thirst_max")
			var thirst: float = dwarf.get("thirst")
			var thirst_restore_per_gorgee: float = dwarf.get("thirst_restore_per_gorgee")
			thirst = min(thirst + thirst_restore_per_gorgee, thirst_max)
			dwarf.set("thirst", thirst)
			if OS.is_debug_build():
				print("Le nain boit de l'eau (soif: %d)" % int(thirst))
		dwarf.set("is_drinking", false)
		var food_indicator: MeshInstance3D = dwarf.get("food_indicator")
		food_indicator.visible = false
		DwarfVisualsScript.reset_pose(dwarf)


## Sprint 24septies : valeur de faim restauree par la nourriture "food_id"
## (calories propres a chaque fruit/baie) - retombe sur hunger_restore_per_berry
## (valeur exportee du Dwarf, modifiable dans l'inspecteur) si aucune valeur
## n'est trouvee (securite, ne devrait pas arriver en pratique).
static func food_calories(dwarf: Node3D, food_id: String) -> float:
	var berry_cal: float = BerryTypes.calories_for(food_id)
	if berry_cal >= 0.0:
		return berry_cal
	var fruit_cal: float = TreeSpecies.calories_for(food_id)
	if fruit_cal >= 0.0:
		return fruit_cal
	return dwarf.get("hunger_restore_per_berry")
