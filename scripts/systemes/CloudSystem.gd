extends Node3D
## Sprint 42 (2026-07-04, demande explicite : "mettre des nuages (legers) qui
## se deplacent ? plus ou moins fonce en fonction du climat") : nuages
## purement decoratifs (aucun effet gameplay), generes proceduralement -
## aucune texture, meme technique que les cimes d'arbres (Forest.gd,
## PartType.BLOB) : des spheres aplaties regroupees en petits amas. Chaque
## nuage derive lentement dans une direction de "vent" fixe (tiree au hasard
## au demarrage) et boucle (wrap) une fois sorti de la carte, sans jamais
## s'arreter.
##
## Sprint 44 (2026-07-04, "plus compliques (pas juste des simples ovales),
## plus clairs/transparents, et sombres avec la nuit") :
## - Forme : un nuage n'est plus un tas de blobs purement aleatoires (ovale
##   simple) mais une "rangee" de bosses principales (grosse au centre, plus
##   petites aux bords, comme un cumulus) PLUS quelques petites bosses posees
##   par-dessus/entre elles - voir _generate_cloud_blobs.
## - Couleur de base : plus claire (proche du blanc) et plus transparente
##   qu'avant (alpha ~0.45-0.6 au lieu de 0.8).
## - Assombrissement nocturne : en plus de la teinte meteo (voir
##   WeatherSystem.cloud_tint_color/cloud_tint_strength), un second fondu
##   assombrit les nuages la nuit, base sur `light_energy` de la lumiere du
##   soleil (%DirectionalLight3D, pilotee par DayNightCycle.gd) - pas de
##   nouvel accesseur necessaire cote DayNightCycle, on lit directement la
##   valeur qu'il vient d'assigner ce meme frame (meme ordre de traitement
##   que pour la teinte meteo).
##
## Perf : nombre d'instances toujours petit (cloud_count * ~7 blobs en
## moyenne, par defaut ~14*7=98) - tres loin des milliers de noeuds qui
## avaient motive le passage en MultiMesh pour arbres/buissons/decor
## (Sprint 34) ; mettre a jour TOUTES les transforms/couleurs chaque frame
## reste donc largement negligeable en cout.

const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")

@export var cloud_count: int = 14
@export var wind_speed: float = 1.4          # unites/seconde
@export var cloud_height_min: float = 18.0   # au-dessus de la surface (HEIGHT-1)
@export var cloud_height_max: float = 26.0
@export var cloud_scale_min: float = 3.0
@export var cloud_scale_max: float = 6.0

# Sprint 44 : couleur/opacite de nuit - un nuage garde une teinte tres sombre
# mais jamais totalement noire (encore visible au clair de lune).
const NIGHT_CLOUD_COLOR := Color(0.10, 0.11, 0.16)
const NIGHT_DARKEN_STRENGTH := 0.8

@onready var _weather_system: Node = %WeatherSystem
@onready var _light: DirectionalLight3D = %DirectionalLight3D

var _mmi: MultiMeshInstance3D
# Un nuage = une position de base (le "vent" ne deplace que celle-ci) ; ses
# blobs (voir _generate_cloud_blobs) gardent un decalage LOCAL fixe autour de
# cette position, recalcule chaque frame (cloud_pos + decalage local).
var _cloud_positions: Array = []          # Array[Vector3], un par nuage
var _instance_cloud_index: Array = []     # Array[int], un par instance (quel nuage)
var _instance_local_offset: Array = []    # Array[Vector3], un par instance
var _instance_local_scale: Array = []     # Array[Vector3], un par instance
var _instance_base_color: Array = []      # Array[Color], un par instance (jitter blanc/gris clair + alpha)

var _wind_dir: Vector2 = Vector2.RIGHT
var _map_width: float
var _map_depth: float


func _ready() -> void:
	randomize()
	_map_width = float(VoxelWorldScript.WIDTH)
	_map_depth = float(VoxelWorldScript.DEPTH)
	var wind_angle: float = randf_range(0.0, TAU)
	_wind_dir = Vector2(cos(wind_angle), sin(wind_angle))
	_build_shared_mesh()
	_spawn_clouds()
	_update_all_transforms()
	_update_all_colors(Color.WHITE, 0.0, 0.0)


## Un seul maillage "unite" (sphere aplatie) partage par tous les blobs de
## tous les nuages, comme les cimes d'arbres (Forest.gd/_make_sphere_mesh +
## MultiMeshInstance3D). transparency legere pour un aspect "leger", demande
## explicitement par Francois ("nuages legers").
func _build_shared_mesh() -> void:
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = MultiMesh.new()
	_mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_mmi.multimesh.use_colors = true
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	_mmi.multimesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mmi.material_override = mat
	add_child(_mmi)


func _spawn_clouds() -> void:
	var total_blobs := 0
	for i in range(cloud_count):
		var cx: float = randf_range(0.0, _map_width)
		var cz: float = randf_range(0.0, _map_depth)
		var cy: float = float(VoxelWorldScript.HEIGHT - 1) + randf_range(cloud_height_min, cloud_height_max)
		_cloud_positions.append(Vector3(cx, cy, cz))

		# Sprint 44 : plus clair (proche du blanc) et plus transparent qu'avant.
		var base_gray: float = randf_range(0.94, 1.0)
		var base_alpha: float = randf_range(0.42, 0.6)
		total_blobs += _generate_cloud_blobs(i, base_gray, base_alpha)

	_mmi.multimesh.instance_count = total_blobs


## Sprint 44 (2026-07-04, "plus compliques, pas juste des simples ovales") :
## un nuage = une rangee de bosses PRINCIPALES le long de l'axe X local
## (profil "bombe" - grosses au centre, plus petites aux extremites, comme un
## cumulus) PLUS quelques petites bosses posees par-dessus/entre elles pour
## casser la silhouette ovale. Renvoie le nombre de blobs generes (pour
## totaliser l'instance_count du MultiMesh dans _spawn_clouds).
func _generate_cloud_blobs(cloud_index: int, base_gray: float, base_alpha: float) -> int:
	var count := 0
	var main_count: int = randi_range(3, 5)
	var span: float = randf_range(3.0, 5.0)
	var main_x_positions: Array = []

	for m in range(main_count):
		var frac: float = (float(m) / float(main_count - 1)) if main_count > 1 else 0.5
		# Profil "bombe" : 1.0 au centre (frac=0.5), plus petit vers les bords.
		var hump: float = clampf(1.0 - absf(frac - 0.5) * 1.6, 0.45, 1.0)
		var local_x: float = (frac - 0.5) * span * 2.0 + randf_range(-0.3, 0.3)
		var local_z: float = randf_range(-0.8, 0.8)
		main_x_positions.append(local_x)

		var scale_xz: float = randf_range(cloud_scale_min, cloud_scale_max) * hump
		var local_scale := Vector3(scale_xz, scale_xz * 0.42, scale_xz * 0.8)
		var local_offset := Vector3(local_x, randf_range(-0.2, 0.2), local_z)
		_add_blob(cloud_index, local_offset, local_scale, base_gray, base_alpha)
		count += 1

	var top_count: int = randi_range(2, 4)
	for t in range(top_count):
		var pick_x: float = main_x_positions[randi_range(0, main_x_positions.size() - 1)]
		var local_x: float = pick_x + randf_range(-0.8, 0.8)
		var local_z: float = randf_range(-0.6, 0.6)
		var local_y: float = randf_range(0.5, 1.3)  # posee au-dessus de la rangee principale
		var scale_xz: float = randf_range(cloud_scale_min, cloud_scale_max) * randf_range(0.35, 0.6)
		var local_scale := Vector3(scale_xz, scale_xz * 0.5, scale_xz * 0.7)
		var local_offset := Vector3(local_x, local_y, local_z)
		_add_blob(cloud_index, local_offset, local_scale, base_gray, base_alpha * 0.9)
		count += 1

	return count


## Ajoute un blob a la liste d'instances, avec un petit jitter individuel de
## teinte/opacite pour une texture moins uniforme d'un blob a l'autre.
func _add_blob(cloud_index: int, local_offset: Vector3, local_scale: Vector3, gray: float, alpha: float) -> void:
	_instance_cloud_index.append(cloud_index)
	_instance_local_offset.append(local_offset)
	_instance_local_scale.append(local_scale)
	var g: float = clampf(gray + randf_range(-0.02, 0.02), 0.85, 1.0)
	var a: float = clampf(alpha + randf_range(-0.05, 0.05), 0.25, 0.75)
	_instance_base_color.append(Color(g, g, g, a))


func _process(delta: float) -> void:
	var scaled_delta: float = delta * DayNightCycleScript.game_speed
	# Marge de wrap : les nuages sortent un peu de la carte avant de
	# reapparaitre de l'autre cote, pour eviter un "pop" visible au bord.
	var margin := 12.0
	for i in range(_cloud_positions.size()):
		var pos: Vector3 = _cloud_positions[i]
		pos.x = wrapf(pos.x + _wind_dir.x * wind_speed * scaled_delta + margin, -margin, _map_width + margin) - margin
		pos.z = wrapf(pos.z + _wind_dir.y * wind_speed * scaled_delta + margin, -margin, _map_depth + margin) - margin
		_cloud_positions[i] = pos
	_update_all_transforms()

	# Sprint 44 : assombrissement nocturne, base sur light_energy de la
	# lumiere directionnelle (deja mise a jour ce meme frame par
	# DayNightCycle, qui tourne avant ce script - meme ordre que la teinte
	# meteo). Normalise par rapport a l'energie de plein jour (LIGHT_ENERGY[1]
	# de DayNightCycle.gd) plutot qu'une valeur codee en dur, pour rester
	# correct si ces constantes sont retouchees plus tard (ce qui est deja
	# arrive plusieurs fois - voir memoire du cycle jour/nuit).
	var day_energy: float = DayNightCycleScript.LIGHT_ENERGY[1]
	var night_factor: float = 1.0 - clampf(_light.light_energy / maxf(day_energy, 0.001), 0.0, 1.0)

	if _weather_system:
		_update_all_colors(_weather_system.cloud_tint_color(), _weather_system.cloud_tint_strength(), night_factor)
	else:
		_update_all_colors(Color.WHITE, 0.0, night_factor)


func _update_all_transforms() -> void:
	for idx in range(_instance_cloud_index.size()):
		var cloud_pos: Vector3 = _cloud_positions[_instance_cloud_index[idx]]
		var offset: Vector3 = _instance_local_offset[idx]
		var inst_scale: Vector3 = _instance_local_scale[idx]
		var xform := Transform3D(Basis().scaled(inst_scale), cloud_pos + offset)
		_mmi.multimesh.set_instance_transform(idx, xform)


func _update_all_colors(tint: Color, strength: float, night_factor: float) -> void:
	for idx in range(_instance_base_color.size()):
		var base: Color = _instance_base_color[idx]
		var weathered: Color = base.lerp(Color(tint.r, tint.g, tint.b, base.a), strength)
		var final_color: Color = weathered.lerp(
			Color(NIGHT_CLOUD_COLOR.r, NIGHT_CLOUD_COLOR.g, NIGHT_CLOUD_COLOR.b, weathered.a),
			night_factor * NIGHT_DARKEN_STRENGTH
		)
		_mmi.multimesh.set_instance_color(idx, final_color)
