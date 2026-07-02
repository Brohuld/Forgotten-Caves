extends Node3D
## Sprint 8 : place quelques buissons a baies au hasard sur la carte,
## pour que le nain puisse se nourrir quand il a faim.
##
## Sprint 24quater : 4 types de baies (BerryTypes.gd : groseille, myrtille,
## fraise, framboise) au lieu d'un seul type generique. Les buissons sont
## maintenant recoltes en inventaire via l'action "Cueillir" au lieu d'etre
## manges directement (voir Dwarf.gd/_complete_task pour la recolte,
## generique avec les arbres fruitiers - memes metadonnees fruit_resource/
## fruits_left et meme convention de nommage Fruit_%d, voir Forest.gd). Le
## buisson reste en place une fois vide (pas de disparition), comme un arbre
## fruitier entierement cueilli.
##
## Sprint 24sexies : deux visuels distincts selon BerryTypes.categorie -
## "buisson" (myrtille/groseille/cassis) garde la forme boule + baies autour ;
## "plante" (fraise/framboise) est une touffe de feuilles basse au ras du sol,
## avec les baies nichees dedans. Signale par l'utilisateur : les buissons et
## les plantes basses ne devraient pas avoir le meme sprite.

const BerryTypes := preload("res://scripts/data/materiaux/types/baies/BerryTypes.gd")

@export var grid_width: int = 20
@export var grid_depth: int = 20
@export var ground_level: float = 30.0  # sommet de la carte (HEIGHT, Sprint 23 : 10 -> 30)
@export var bush_count: int = 8  # Sprint 24quater : un peu plus (etait 5), pour varier les types
const BERRIES_PER_BUSH := 4


func _ready() -> void:
	randomize()
	for i in range(bush_count):
		_spawn_bush()


func _spawn_bush() -> void:
	var x := randf_range(2.0, float(grid_width - 2))
	var z := randf_range(2.0, float(grid_depth - 2))
	var berry_type: Dictionary = BerryTypes.random_type()

	var bush := Node3D.new()
	bush.name = "Bush_%d" % get_child_count()
	bush.position = Vector3(x, ground_level, z)
	bush.add_to_group("cueillette")
	bush.set_meta("fruit_resource", berry_type["id"])
	bush.set_meta("fruits_left", BERRIES_PER_BUSH)
	bush.set_meta("species_name", berry_type["nom"])
	add_child(bush)

	if berry_type.get("categorie", "buisson") == "plante":
		_build_plant_visual(bush, berry_type)
	else:
		_build_bush_visual(bush, berry_type)


## Visuel "buisson" (myrtille/groseille/cassis) : boule de feuillage + baies
## disposees autour, a hauteur de genou - inchange depuis les sprints precedents.
func _build_bush_visual(bush: Node3D, berry_type: Dictionary) -> void:
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

	var berry_mat := StandardMaterial3D.new()
	berry_mat.albedo_color = berry_type["couleur"]
	for i in range(BERRIES_PER_BUSH):
		var berry := MeshInstance3D.new()
		var berry_mesh := SphereMesh.new()
		berry_mesh.radius = 0.08
		berry_mesh.height = 0.16
		berry.mesh = berry_mesh
		var angle := i * TAU / float(BERRIES_PER_BUSH)
		berry.position = Vector3(cos(angle) * 0.35, 0.55, sin(angle) * 0.35)
		berry.set_surface_override_material(0, berry_mat)
		berry.name = "Fruit_%d" % i
		bush.add_child(berry)


## Sprint 24sexies : visuel "plante" (fraise/framboise) - touffe basse de
## feuilles pres du sol (pas de grosse boule), avec les baies nichees dedans,
## beaucoup plus proche du sol qu'un buisson.
func _build_plant_visual(bush: Node3D, berry_type: Dictionary) -> void:
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.20, 0.42, 0.16)
	leaf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var leaf_count := randi_range(6, 9)
	for i in range(leaf_count):
		var leaf := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(randf_range(0.12, 0.18), 0.015, randf_range(0.07, 0.11))
		leaf.mesh = mesh
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(0.05, 0.22)
		leaf.position = Vector3(cos(angle) * dist, 0.06 + randf_range(0.0, 0.05), sin(angle) * dist)
		leaf.rotation.y = angle + randf_range(-0.4, 0.4)
		leaf.rotation.x = randf_range(-0.15, 0.15)
		leaf.set_surface_override_material(0, leaf_mat)
		bush.add_child(leaf)

	var berry_mat := StandardMaterial3D.new()
	berry_mat.albedo_color = berry_type["couleur"]
	for i in range(BERRIES_PER_BUSH):
		var berry := MeshInstance3D.new()
		var berry_mesh := SphereMesh.new()
		berry_mesh.radius = 0.05
		berry_mesh.height = 0.10
		berry.mesh = berry_mesh
		var angle := i * TAU / float(BERRIES_PER_BUSH) + randf_range(-0.3, 0.3)
		var dist := randf_range(0.08, 0.18)
		berry.position = Vector3(cos(angle) * dist, 0.10, sin(angle) * dist)
		berry.set_surface_override_material(0, berry_mat)
		berry.name = "Fruit_%d" % i
		bush.add_child(berry)
