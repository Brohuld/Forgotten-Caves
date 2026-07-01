extends Node3D
## Sprint 8 : place quelques buissons a baies au hasard sur la carte,
## pour que le nain puisse se nourrir quand il a faim.

@export var grid_width: int = 20
@export var grid_depth: int = 20
@export var ground_level: float = 10.0
@export var bush_count: int = 5

const BUSH_SCRIPT := preload("res://scripts/BerryBush.gd")


func _ready() -> void:
	randomize()
	for i in range(bush_count):
		_spawn_bush()


func _spawn_bush() -> void:
	var x := randf_range(2.0, float(grid_width - 2))
	var z := randf_range(2.0, float(grid_depth - 2))

	var bush := Node3D.new()
	bush.name = "Bush_%d" % get_child_count()
	bush.position = Vector3(x, ground_level, z)
	bush.add_to_group("berries")
	bush.set_script(BUSH_SCRIPT)
	add_child(bush)
	bush.berries_left = 3

	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.4
	body_mesh.height = 0.8
	body.mesh = body_mesh
	body.position.y = 0.4
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.25, 0.45, 0.15)
	body.set_surface_override_material(0, body_mat)
	bush.add_child(body)

	for i in range(3):
		var berry := MeshInstance3D.new()
		var berry_mesh := SphereMesh.new()
		berry_mesh.radius = 0.08
		berry_mesh.height = 0.16
		berry.mesh = berry_mesh
		var angle := i * TAU / 3.0
		berry.position = Vector3(cos(angle) * 0.35, 0.55, sin(angle) * 0.35)
		var berry_mat := StandardMaterial3D.new()
		berry_mat.albedo_color = Color(0.7, 0.05, 0.05)
		berry.set_surface_override_material(0, berry_mat)
		berry.name = "Berry_%d" % i
		bush.add_child(berry)
