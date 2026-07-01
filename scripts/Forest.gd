extends Node3D
## Sprint 4 : quelques arbres de test places au hasard sur la carte,
## pour valider l'action "couper". Sera remplace par une vraie generation
## de vegetation liee au climat plus tard.

@export var grid_width: int = 20
@export var grid_depth: int = 20
@export var ground_level: float = 10.0
@export var tree_count: int = 6


func _ready() -> void:
	randomize()
	for i in range(tree_count):
		_spawn_tree()


func _spawn_tree() -> void:
	var x := randf_range(2.0, float(grid_width - 2))
	var z := randf_range(2.0, float(grid_depth - 2))

	var tree := Node3D.new()
	tree.name = "Tree_%d" % get_child_count()
	tree.position = Vector3(x, ground_level, z)
	tree.add_to_group("trees")
	add_child(tree)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.15
	trunk_mesh.bottom_radius = 0.2
	trunk_mesh.height = 1.2
	trunk.mesh = trunk_mesh
	trunk.position.y = 0.6
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.25, 0.1)
	trunk.set_surface_override_material(0, trunk_mat)
	tree.add_child(trunk)

	var foliage := MeshInstance3D.new()
	var foliage_mesh := SphereMesh.new()
	foliage_mesh.radius = 0.6
	foliage_mesh.height = 1.2
	foliage.mesh = foliage_mesh
	foliage.position.y = 1.5
	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.albedo_color = Color(0.2, 0.55, 0.2)
	foliage.set_surface_override_material(0, foliage_mat)
	tree.add_child(foliage)
