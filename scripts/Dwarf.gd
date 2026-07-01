extends Node3D
## Sprint 3 : nain provisoire (capsule) qui se deplace et s'anime.
## Sprint 4 : pioche ses destinations dans la TaskQueue (miner/couper/construire)
## en priorite, et erre au hasard seulement s'il n'y a rien a faire.
## Sprint 8 : jauges faim/energie. Si un besoin devient critique, le nain
## interrompt ce qu'il fait pour manger (buisson a baies) ou se reposer.
## Sprint 9bis : signale la fin d'une tache de construction (succes ou
## echec) pour que l'UI puisse retirer le mur "fantome" correspondant.

signal build_task_finished(task_id: int, bx: int, bz: int)

# Doivent correspondre a VoxelWorld.gd
@export var grid_width: int = 20
@export var grid_depth: int = 20
@export var ground_level: float = 10.0  # sommet de la carte (HEIGHT)

@export var move_speed: float = 3.0        # unites / seconde
@export var rotation_speed: float = 8.0    # vitesse de rotation vers la direction
@export var bob_height: float = 0.08       # amplitude du petit rebond de marche
@export var bob_speed: float = 6.0
@export var work_duration: float = 1.5     # secondes pour miner/couper une fois arrive

# Besoins (Sprint 8) - vitesses volontairement rapides pour tester sans attendre
@export var hunger_max: float = 100.0
@export var energy_max: float = 100.0
@export var hunger_depletion_rate: float = 8.0   # points / seconde
@export var energy_depletion_rate: float = 5.0   # points / seconde
@export var hunger_critical: float = 20.0
@export var energy_critical: float = 15.0
@export var energy_rest_target: float = 70.0     # niveau vise avant de reprendre l'activite
@export var energy_regen_rate: float = 20.0      # points / seconde au repos
@export var hunger_restore_per_berry: float = 40.0
@export var eat_duration: float = 1.2            # secondes, animation de manger

var hunger: float = 100.0
var energy: float = 100.0

var target_position: Vector3
var bob_time: float = 0.0
var resting_y: float = 0.85  # doit correspondre a la moitie de la hauteur de la capsule

var current_task: Dictionary = {}
var is_working: bool = false
var work_timer: float = 0.0

var is_resting: bool = false
var is_seeking_food: bool = false
var is_eating: bool = false
var eat_timer: float = 0.0
var target_food: Node3D = null

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var task_queue: Node = %TaskQueue
@onready var voxel_world: Node3D = %VoxelWorld
@onready var inventory: Node = %Inventory

var hunger_bar: ProgressBar
var energy_bar: ProgressBar


func _ready() -> void:
	global_position = Vector3(grid_width / 2.0, ground_level, grid_depth / 2.0)
	mesh_instance.position.y = resting_y
	_pick_new_target()
	_create_needs_ui()


func _create_needs_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var container := VBoxContainer.new()
	container.position = Vector2(16, 56)
	canvas.add_child(container)

	var hunger_label := Label.new()
	hunger_label.text = "Faim"
	container.add_child(hunger_label)
	hunger_bar = ProgressBar.new()
	hunger_bar.custom_minimum_size = Vector2(200, 18)
	hunger_bar.max_value = hunger_max
	hunger_bar.value = hunger
	container.add_child(hunger_bar)

	var energy_label := Label.new()
	energy_label.text = "Energie"
	container.add_child(energy_label)
	energy_bar = ProgressBar.new()
	energy_bar.custom_minimum_size = Vector2(200, 18)
	energy_bar.max_value = energy_max
	energy_bar.value = energy
	container.add_child(energy_bar)


func _process(delta: float) -> void:
	_update_needs(delta)
	hunger_bar.value = hunger
	energy_bar.value = energy

	if is_working:
		_process_work(delta)
		return

	if is_resting:
		_process_resting(delta)
		return

	if is_eating:
		_process_eating(delta)
		return

	if is_seeking_food:
		_process_seek_food(delta)
		return

	# Les besoins critiques passent avant les taches et l'errance
	if energy <= energy_critical:
		_start_resting()
		return
	if hunger <= hunger_critical:
		if _start_seeking_food():
			return
		# sinon (aucun buisson disponible) : on continue normalement

	# Priorite aux taches designees par l'utilisateur, la plus proche d'abord
	if current_task.is_empty() and task_queue.has_tasks():
		current_task = task_queue.pop_nearest_task(global_position)
		target_position = current_task["position"]

	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	if distance < 0.15:
		if not current_task.is_empty():
			is_working = true
			work_timer = 0.0
			mesh_instance.rotation.z = 0.0
			return
		_pick_new_target()
		bob_time = 0.0
		mesh_instance.position.y = resting_y
		return

	_move_toward(to_target, distance, delta)


## Diminue faim et energie au fil du temps
func _update_needs(delta: float) -> void:
	hunger = max(hunger - hunger_depletion_rate * delta, 0.0)
	energy = max(energy - energy_depletion_rate * delta, 0.0)


## Deplacement generique reutilise par la marche normale et la recherche de nourriture
func _move_toward(to_target: Vector3, distance: float, delta: float) -> void:
	var direction := to_target.normalized()
	var step: float = min(move_speed * delta, distance)
	global_position += direction * step

	var target_yaw: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, rotation_speed * delta)

	bob_time += delta * bob_speed
	mesh_instance.position.y = resting_y + absf(sin(bob_time)) * bob_height


## --- Repos (energie critique) : le nain "s'allonge" et dort sur place ---

func _start_resting() -> void:
	is_resting = true
	mesh_instance.rotation.z = deg_to_rad(90)
	mesh_instance.position.y = 0.35
	if not current_task.is_empty():
		task_queue.requeue_task(current_task)
		current_task = {}


func _process_resting(delta: float) -> void:
	energy = min(energy + energy_regen_rate * delta, energy_max)
	# petite respiration pendant le sommeil
	mesh_instance.position.y = 0.35 + sin(Time.get_ticks_msec() / 400.0) * 0.03
	if energy >= energy_rest_target:
		is_resting = false
		mesh_instance.rotation.z = 0.0
		mesh_instance.position.y = resting_y


## --- Recherche de nourriture (faim critique) ---

func _start_seeking_food() -> bool:
	var bush := _find_nearest_bush()
	if bush == null:
		return false
	is_seeking_food = true
	target_food = bush
	if not current_task.is_empty():
		task_queue.requeue_task(current_task)
		current_task = {}
	return true


func _find_nearest_bush() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for bush in get_tree().get_nodes_in_group("berries"):
		var d: float = global_position.distance_to(bush.global_position)
		if d < best_dist:
			best_dist = d
			best = bush
	return best


func _process_seek_food(delta: float) -> void:
	if not is_instance_valid(target_food):
		is_seeking_food = false
		target_food = null
		return

	var to_target: Vector3 = target_food.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	if distance < 0.4:
		is_seeking_food = false
		is_eating = true
		eat_timer = 0.0
		return

	_move_toward(to_target, distance, delta)


## Anime le nain qui "hoche la tete" pour manger, puis consomme la baie
func _process_eating(delta: float) -> void:
	eat_timer += delta
	mesh_instance.rotation.x = sin(eat_timer * 14.0) * 0.3

	if eat_timer >= eat_duration:
		mesh_instance.rotation.x = 0.0
		if is_instance_valid(target_food) and target_food.has_method("eat") and target_food.eat():
			hunger = min(hunger + hunger_restore_per_berry, hunger_max)
			print("Le nain mange une baie (faim: %d)" % int(hunger))
		target_food = null
		is_eating = false
		bob_time = 0.0
		mesh_instance.position.y = resting_y


## --- Taches (miner / couper / construire) ---

func _process_work(delta: float) -> void:
	work_timer += delta
	mesh_instance.rotation.z = sin(work_timer * 12.0) * 0.15

	if work_timer >= work_duration:
		mesh_instance.rotation.z = 0.0
		_complete_task()


func _complete_task() -> void:
	if current_task.get("type") == "miner":
		var resource_name: String = voxel_world.remove_block(
			current_task["bx"], current_task["by"], current_task["bz"]
		)
		if resource_name != "":
			_collect_resource(resource_name)
	elif current_task.get("type") == "couper":
		var tree = current_task.get("tree")
		if is_instance_valid(tree):
			tree.queue_free()
		_collect_resource("bois")
	elif current_task.get("type") == "construire":
		var material: String = current_task["material"]
		var bx: int = current_task["bx"]
		var bz: int = current_task["bz"]
		if inventory.remove_resource(material, 1):
			voxel_world.build_block(bx, bz, material)
			print("Mur en %s construit a (%d, %d)" % [material, bx, bz])
		else:
			print("Pas assez de %s pour construire (tache annulee)" % material)
		build_task_finished.emit(current_task.get("id", -1), bx, bz)

	current_task = {}
	is_working = false
	_pick_new_target()


## Ajoute la ressource a l'inventaire et fait apparaitre un petit item
## qui "saute" puis disparait, pour visualiser la recolte (Sprint 5)
func _collect_resource(resource_name: String) -> void:
	inventory.add_resource(resource_name, 1)
	_spawn_loot_item(resource_name, global_position)
	print("Recolte : +1 %s (total %d)" % [resource_name, inventory.get_count(resource_name)])


func _spawn_loot_item(resource_name: String, pos: Vector3) -> void:
	var item := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	item.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _resource_color(resource_name)
	item.set_surface_override_material(0, mat)
	item.position = pos + Vector3(0, 0.3, 0)
	get_parent().add_child(item)

	var tween := get_tree().create_tween()
	tween.tween_property(item, "position:y", item.position.y + 0.6, 0.4)
	tween.parallel().tween_property(item, "scale", Vector3.ZERO, 0.4)
	tween.tween_callback(item.queue_free)


func _resource_color(resource_name: String) -> Color:
	match resource_name:
		"bois":
			return Color(0.4, 0.25, 0.1)
		"pierre":
			return Color(0.55, 0.55, 0.55)
		"terre":
			return Color(0.35, 0.25, 0.15)
		_:
			return Color(1, 1, 1)


## Choisit une nouvelle case cible aleatoire sur la carte (marge de 1 bloc au bord)
func _pick_new_target() -> void:
	var x := randf_range(1.0, float(grid_width - 1))
	var z := randf_range(1.0, float(grid_depth - 1))
	target_position = Vector3(x, ground_level, z)
