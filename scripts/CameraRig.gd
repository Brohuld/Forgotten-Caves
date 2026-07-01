extends Node3D
## Sprint 2 : camera controlable.
## - Deplacement (pan) : ZQSD (touches physiques Z/Q/S/D sur clavier francais)
## - Rotation : touches A et E (Q est deja pris par le deplacement, donc pas de Q/E)
## - Zoom : touches + et -
## - Changement de niveau de profondeur : molette de la souris

@export var move_speed: float = 12.0
@export var rotate_step_deg: float = 45.0
@export var zoom_speed: float = 3.0
@export var min_distance: float = 8.0
@export var max_distance: float = 60.0

# Doivent correspondre aux constantes de VoxelWorld.gd
@export var grid_height: int = 10

var current_level: int = 9
var camera_distance: float = 30.0
var pitch_deg: float = 35.0

@onready var camera: Camera3D = $Camera3D
var level_label: Label


func _ready() -> void:
	global_position.y = float(current_level)
	_update_camera_offset()
	_create_ui()
	_update_label()


func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	level_label = Label.new()
	level_label.position = Vector2(16, 16)
	level_label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(level_label)


func _process(delta: float) -> void:
	var input_dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_D):
		input_dir.x += 1
	if Input.is_physical_key_pressed(KEY_A):  # touche Q sur clavier francais
		input_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_W):  # touche Z sur clavier francais
		input_dir.z -= 1
	if Input.is_physical_key_pressed(KEY_S):
		input_dir.z += 1

	if input_dir != Vector3.ZERO:
		input_dir = input_dir.normalized()
		var move: Vector3 = transform.basis * input_dir
		move.y = 0
		global_position += move * move_speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Rotation : touches A et E (physiques). Q etant deja pris par le
		# deplacement (ZQSD), on utilise A (a cote) pour eviter le conflit.
		if event.physical_keycode == KEY_Q:
			rotate_y(deg_to_rad(rotate_step_deg))
		elif event.physical_keycode == KEY_E:
			rotate_y(deg_to_rad(-rotate_step_deg))
		elif event.physical_keycode == KEY_EQUAL or event.physical_keycode == KEY_KP_ADD:
			camera_distance = clamp(camera_distance - zoom_speed, min_distance, max_distance)
			_update_camera_offset()
		elif event.physical_keycode == KEY_MINUS or event.physical_keycode == KEY_KP_SUBTRACT:
			camera_distance = clamp(camera_distance + zoom_speed, min_distance, max_distance)
			_update_camera_offset()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_level = clampi(current_level + 1, 0, grid_height - 1)
			global_position.y = float(current_level)
			_update_label()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_level = clampi(current_level - 1, 0, grid_height - 1)
			global_position.y = float(current_level)
			_update_label()


func _update_camera_offset() -> void:
	var pitch := deg_to_rad(pitch_deg)
	var horizontal := camera_distance * cos(pitch)
	camera.position = Vector3(0, camera_distance * sin(pitch), horizontal)
	camera.look_at(global_position, Vector3.UP)


func _update_label() -> void:
	if level_label:
		level_label.text = "Niveau : %d / %d" % [current_level, grid_height - 1]
