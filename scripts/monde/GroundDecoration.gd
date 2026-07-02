extends Node3D
## Sprint 19 : decoration legere du sol (touffes d'herbe, fleurs, petits
## cailloux) pour casser la monotonie visuelle du damier de terre. Purement
## decoratif (aucune interaction, contrairement aux buissons a baies) :
## generee une seule fois au demarrage, a partir de l'etat initial du terrain
## (une decoration ne disparait pas si le bloc en-dessous est mine ensuite -
## limitation connue, acceptable pour l'instant vu la faible densite).
##
## La couleur de base de l'herbe/des fleurs depend du climat de la carte
## (ClimateDefinitions.gd). Un seul climat existe reellement pour l'instant
## (tempere), mais la structure est prete a en accueillir d'autres plus tard
## (climate_id est deja un champ expose, pret a devenir un vrai choix de
## carte quand un systeme de climats/saisons existera).

const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")

@export var grid_width: int = 20
@export var grid_depth: int = 20
@export var climate_id: String = "tempere"
@export var decoration_chance: float = 0.24  # Sprint 24 : densite doublee (etait 0.12, jugee trop faible)

@onready var voxel_world: Node3D = %VoxelWorld


func _ready() -> void:
	randomize()
	var climate: Dictionary = ClimateDefs.get_climate(climate_id)
	for x in range(grid_width):
		for z in range(grid_depth):
			if randf() > decoration_chance:
				continue
			if not voxel_world.is_dirt_top(x, z):
				continue
			var top_y: int = voxel_world.get_top_block_y(x, z)
			_spawn_decoration(x, top_y + 1, z, climate)


## Choisit un type de decoration au hasard (davantage d'herbe que de fleurs,
## et un peu de cailloux) et le fait apparaitre a la position donnee
func _spawn_decoration(x: int, y: int, z: int, climate: Dictionary) -> void:
	var roll := randf()
	if roll < 0.45:
		_spawn_grass_tuft(x, y, z, climate)
	elif roll < 0.85:
		_spawn_flower(x, y, z, climate)
	else:
		_spawn_pebble(x, y, z)


## Petite touffe de 3 a 5 brins d'herbe fins, teintee avec une variation
## aleatoire de la couleur de base du climat
func _spawn_grass_tuft(x: int, y: int, z: int, climate: Dictionary) -> void:
	var tuft := Node3D.new()
	tuft.position = Vector3(x + randf_range(0.2, 0.8), y, z + randf_range(0.2, 0.8))
	tuft.rotation.y = randf_range(0.0, TAU)
	add_child(tuft)

	var variations: Array = climate.get("herbe_variations", [climate.get("herbe_base", Color.GREEN)])
	var blade_count: int = randi_range(3, 5)
	for i in range(blade_count):
		var blade := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.01
		mesh.bottom_radius = 0.03
		mesh.height = randf_range(0.12, 0.22)
		blade.mesh = mesh
		blade.position = Vector3(randf_range(-0.08, 0.08), mesh.height * 0.5, randf_range(-0.08, 0.08))
		blade.rotation.z = randf_range(-0.3, 0.3)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = variations[randi_range(0, variations.size() - 1)]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		blade.set_surface_override_material(0, mat)
		tuft.add_child(blade)


## Petite fleur (tige + bouton), couleur choisie au hasard parmi les
## "especes" du climat (une couleur = une espece, approche volontairement
## simple pour l'instant)
func _spawn_flower(x: int, y: int, z: int, climate: Dictionary) -> void:
	var flower := Node3D.new()
	flower.position = Vector3(x + randf_range(0.25, 0.75), y, z + randf_range(0.25, 0.75))
	add_child(flower)

	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.012
	stem_mesh.bottom_radius = 0.016
	stem_mesh.height = 0.18
	stem.mesh = stem_mesh
	stem.position.y = 0.09
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.3, 0.5, 0.2)
	stem_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stem.set_surface_override_material(0, stem_mat)
	flower.add_child(stem)

	var bloom := MeshInstance3D.new()
	var bloom_mesh := SphereMesh.new()
	bloom_mesh.radius = 0.05
	bloom_mesh.height = 0.1
	bloom.mesh = bloom_mesh
	bloom.position.y = 0.2
	var fleurs: Array = climate.get("fleurs", [Color.WHITE])
	var bloom_mat := StandardMaterial3D.new()
	bloom_mat.albedo_color = fleurs[randi_range(0, fleurs.size() - 1)]
	bloom_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bloom.set_surface_override_material(0, bloom_mat)
	flower.add_child(bloom)


## Petit caillou gris, taille/teinte/rotation legerement aleatoires
func _spawn_pebble(x: int, y: int, z: int) -> void:
	var pebble := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var size: float = randf_range(0.06, 0.14)
	mesh.size = Vector3(size, size * 0.6, size * randf_range(0.8, 1.2))
	pebble.mesh = mesh
	pebble.position = Vector3(x + randf_range(0.2, 0.8), y + size * 0.3, z + randf_range(0.2, 0.8))
	pebble.rotation.y = randf_range(0.0, TAU)
	var shade: float = randf_range(0.45, 0.62)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(shade, shade, shade * 1.02)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pebble.set_surface_override_material(0, mat)
	add_child(pebble)
