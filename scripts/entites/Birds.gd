extends Node3D
## Sprint 42 (2026-07-04, demande explicite : "des oiseaux simplifies
## purement decoratifs") : petits oiseaux stylises (corps aplati + 2 ailes
## plates qui battent) volant en boucle sur une trajectoire circulaire
## au-dessus de la carte. Purement decoratif - AUCUNE interaction avec le
## jeu (pas de groupe "trees"/"cueillette", pas cliquable, pas de metadonnee
## de tache), contrairement aux arbres/buissons.
##
## Peu d'oiseaux (bird_count petit, defaut 8), chacun un Node3D independant
## avec 3 MeshInstance3D enfants (corps + 2 ailes) - pas de MultiMesh ici
## (contrairement a CloudSystem.gd/Forest.gd) : chaque oiseau a sa propre
## trajectoire ET sa propre phase de battement d'ailes, ce qui demanderait
## de toute facon une transform par instance mise a jour chaque frame ; avec
## seulement quelques oiseaux, des noeuds simples (meme approche que Dwarf.gd,
## un nain = un Node3D) restent largement assez performants.

const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")

@export var bird_count: int = 8
@export var flap_speed: float = 6.0        # vitesse angulaire du battement (rad/s approx.)
@export var min_radius: float = 8.0
@export var max_radius: float = 22.0
@export var min_height: float = 14.0       # au-dessus de la surface (HEIGHT-1)
@export var max_height: float = 20.0
@export var min_angular_speed: float = 0.3 # rad/s le long du cercle de vol
@export var max_angular_speed: float = 0.7

const BODY_COLOR := Color(0.16, 0.16, 0.18)

var _birds: Array = []   # Array[Dictionary] : node, center, radius, height, angle, angular_speed, wing_left, wing_right, phase
var _sim_time: float = 0.0


func _ready() -> void:
	# 2026-07-05 (meme correctif que C2-C6/I9, decouvert incidemment lors de
	# cette revue - hors perimetre du diff d'origine mais meme cause) :
	# randomize() retire - reinitialisait le generateur aleatoire global de
	# facon non deterministe, APRES que VoxelWorld._ready() ait deja fixe sa
	# graine. Purement decoratif ici, mais casse la chaine de determinisme
	# pour tout script suivant dans Main.tscn - retire pour rester coherent.
	for i in range(bird_count):
		_spawn_bird(i)


func _spawn_bird(index: int) -> void:
	var margin := 15.0
	var cx: float = randf_range(margin, float(VoxelWorldScript.WIDTH) - margin)
	var cz: float = randf_range(margin, float(VoxelWorldScript.DEPTH) - margin)
	var center := Vector3(cx, 0.0, cz)
	var radius: float = randf_range(min_radius, max_radius)
	var height: float = float(VoxelWorldScript.HEIGHT - 1) + randf_range(min_height, max_height)
	var angle: float = randf_range(0.0, TAU)
	var angular_speed: float = randf_range(min_angular_speed, max_angular_speed) * (1.0 if randf() < 0.5 else -1.0)

	var bird := Node3D.new()
	bird.name = "Bird_%d" % index
	add_child(bird)

	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 1.0
	body_mesh.height = 2.0
	body.mesh = body_mesh
	body.scale = Vector3(0.12, 0.08, 0.24)
	_apply_unshaded(body, BODY_COLOR)
	bird.add_child(body)

	var wing_left := _make_wing(-1.0)
	var wing_right := _make_wing(1.0)
	bird.add_child(wing_left)
	bird.add_child(wing_right)

	_birds.append({
		"node": bird,
		"center": center,
		"radius": radius,
		"height": height,
		"angle": angle,
		"angular_speed": angular_speed,
		"wing_left": wing_left,
		"wing_right": wing_right,
		"phase": randf_range(0.0, TAU),
	})


## Une aile = un pivot (Node3D, a l'epaule) + le maillage plat decale vers
## l'exterieur - faire tourner le PIVOT en Z donne un battement d'aile
## credible sans avoir a animer un maillage articule.
func _make_wing(side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(side * 0.04, 0.0, 0.0)

	var mesh_inst := MeshInstance3D.new()
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(0.32, 0.015, 0.13)
	mesh_inst.mesh = wing_mesh
	mesh_inst.position = Vector3(side * 0.18, 0.0, 0.0)
	_apply_unshaded(mesh_inst, BODY_COLOR)
	pivot.add_child(mesh_inst)

	return pivot


func _apply_unshaded(mesh_instance: MeshInstance3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh_instance.material_override = mat


func _process(delta: float) -> void:
	var scaled_delta: float = delta * DayNightCycleScript.game_speed
	_sim_time += scaled_delta

	for bird in _birds:
		bird["angle"] += bird["angular_speed"] * scaled_delta
		var angle: float = bird["angle"]
		var center: Vector3 = bird["center"]
		var radius: float = bird["radius"]
		var pos := Vector3(
			center.x + cos(angle) * radius,
			bird["height"],
			center.z + sin(angle) * radius
		)
		var node: Node3D = bird["node"]
		node.position = pos

		# Orientation : tangente au cercle, dans le sens de rotation reel de
		# cet oiseau (certains tournent dans un sens, d'autres dans l'autre).
		var dir_sign: float = signf(bird["angular_speed"])
		var tangent := Vector3(-sin(angle), 0.0, cos(angle)) * dir_sign
		node.rotation.y = atan2(tangent.x, tangent.z)

		# Battement d'ailes : sinus dephase par oiseau (bird["phase"]), base
		# sur le temps de simulation (respecte pause/x1/x2/x4, voir game_speed
		# ci-dessus) plutot que l'horloge reelle.
		var flap: float = sin(_sim_time * flap_speed + bird["phase"]) * 0.9
		(bird["wing_left"] as Node3D).rotation.z = flap
		(bird["wing_right"] as Node3D).rotation.z = -flap
