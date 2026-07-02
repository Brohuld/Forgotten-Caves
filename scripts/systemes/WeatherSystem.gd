extends Node
## Sprint 30 (2026-07-02) : systeme meteo purement visuel, independant du
## gameplay (comme DayNightCycle.gd). Alterne aleatoirement dans le temps
## entre Normal / Brouillard / Pluie / Neige. Place APRES DayNightCycle.gd
## dans Main.tscn afin que son _process() tourne juste apres (l'ordre de
## traitement de Godot suit l'ordre des enfants dans l'arbre) - ca permet
## d'ajouter les effets meteo PAR-DESSUS ce que DayNightCycle vient de
## calculer ce meme frame (densite de fog, energie de la lumiere), sans que
## les deux scripts se marchent dessus : DayNightCycle reste proprietaire
## des couleurs de ciel/sol et de la rotation/couleur de base de la lumiere ;
## WeatherSystem n'ajoute qu'un delta de densite de fog et un multiplicateur
## d'energie lumineuse, tous deux lisses/interpoles pour eviter un
## changement brutal quand la meteo change.

## Reference au script (pas juste une scene) pour lire ses constantes de
## dimensions de carte (WIDTH/DEPTH/BUILD_CEILING) sans les dupliquer en dur
## ici - voir la memoire du bug GROUND_LEVEL (2026-07-02) : une constante de
## hauteur dupliquee et jamais mise a jour ailleurs avait cause un bug
## silencieux, on evite de reproduire ce probleme.
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")

enum Weather { NORMAL, BROUILLARD, PLUIE, NEIGE }

@export var min_weather_duration: float = 15.0
@export var max_weather_duration: float = 35.0
## Vitesse de fondu (plus haut = plus rapide) entre l'ancien et le nouvel
## etat meteo, pour eviter un changement instantane de densite de
## brouillard / d'energie lumineuse quand la meteo change.
@export var transition_speed: float = 0.6

## Densite de fog "ciel degage" de Main.tscn (Environment_1.fog_density
## d'origine) - gardee ici en dur car WeatherSystem doit RE-DEFINIR
## fog_density chaque frame (base + extra meteo), jamais l'incrementer,
## sous peine d'accumulation infinie frame apres frame.
const BASE_FOG_DENSITY := 0.008

const FOG_DENSITY_EXTRA := {
	Weather.NORMAL: 0.0,
	Weather.BROUILLARD: 0.05,
	Weather.PLUIE: 0.015,
	Weather.NEIGE: 0.02,
}
const LIGHT_ENERGY_MULT := {
	Weather.NORMAL: 1.0,
	Weather.BROUILLARD: 0.85,
	Weather.PLUIE: 0.6,
	Weather.NEIGE: 0.8,
}

var current_weather: int = Weather.NORMAL
var _time_left: float = 0.0
var _fog_extra: float = 0.0
var _light_mult: float = 1.0

@onready var _world_environment: WorldEnvironment = %WorldEnvironment
@onready var _light: DirectionalLight3D = %DirectionalLight3D
var _rain_particles: GPUParticles3D
var _snow_particles: GPUParticles3D


func _ready() -> void:
	_time_left = randf_range(min_weather_duration, max_weather_duration)
	_rain_particles = _build_particles(false)
	_snow_particles = _build_particles(true)
	add_child(_rain_particles)
	add_child(_snow_particles)
	_apply_particles()


func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		_pick_new_weather()

	_fog_extra = lerp(_fog_extra, FOG_DENSITY_EXTRA[current_weather], delta * transition_speed)
	_light_mult = lerp(_light_mult, LIGHT_ENERGY_MULT[current_weather], delta * transition_speed)

	_world_environment.environment.fog_density = BASE_FOG_DENSITY + _fog_extra
	_light.light_energy *= _light_mult


func _pick_new_weather() -> void:
	# "Normal" deux fois plus probable que chaque autre etat, pour que le
	# ciel degage reste l'etat "par defaut" le plus frequent.
	var choices := [Weather.NORMAL, Weather.NORMAL, Weather.BROUILLARD, Weather.PLUIE, Weather.NEIGE]
	current_weather = choices[randi() % choices.size()]
	_time_left = randf_range(min_weather_duration, max_weather_duration)
	_apply_particles()


func _apply_particles() -> void:
	_rain_particles.emitting = current_weather == Weather.PLUIE
	_snow_particles.emitting = current_weather == Weather.NEIGE


## Construit un emetteur de particules (pluie si is_snow=false, neige si
## true) couvrant toute la carte, positionne au-dessus du plafond de
## construction (VoxelWorldScript.BUILD_CEILING) et tombant a travers toute
## la hauteur jouable. visibility_aabb est defini a la main (large, en
## espace LOCAL au noeud) car ces particules sont creees par code, sans
## passer par le bouton "Generate Visibility AABB" de l'editeur Godot -
## sans ca, Godot risque de considerer les particules hors-champ et de ne
## jamais les afficher.
func _build_particles(is_snow: bool) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "SnowParticles" if is_snow else "RainParticles"

	var half_w: float = VoxelWorldScript.WIDTH * 0.5
	var half_d: float = VoxelWorldScript.DEPTH * 0.5
	var emit_height: float = VoxelWorldScript.BUILD_CEILING + 4.0
	particles.position = Vector3(half_w, emit_height, half_d)

	var process_mat := ParticleProcessMaterial.new()
	process_mat.direction = Vector3(0, -1, 0)
	process_mat.spread = 8.0 if is_snow else 3.0
	process_mat.gravity = Vector3(0, -4.0 if is_snow else -14.0, 0)
	process_mat.initial_velocity_min = 1.0 if is_snow else 12.0
	process_mat.initial_velocity_max = 2.5 if is_snow else 16.0
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_mat.emission_box_extents = Vector3(half_w + 3.0, 0.2, half_d + 3.0)
	particles.process_material = process_mat

	var mesh: PrimitiveMesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if is_snow:
		var sphere := SphereMesh.new()
		sphere.radius = 0.05
		sphere.height = 0.1
		mesh = sphere
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.02, 0.35, 0.02)  # streak allongee vers le bas
		mesh = box
		mat.albedo_color = Color(0.7, 0.8, 0.95, 0.5)
	mesh.material = mat
	particles.draw_pass_1 = mesh

	particles.amount = 150 if is_snow else 400
	particles.lifetime = 6.0 if is_snow else 2.5
	particles.emitting = false
	# AABB genereux en espace local (centre sur le noeud) : couvre toute la
	# chute, de l'emission jusque bien sous le niveau du sol.
	particles.visibility_aabb = AABB(
		Vector3(-half_w - 5.0, -emit_height - 5.0, -half_d - 5.0),
		Vector3((half_w + 5.0) * 2.0, emit_height + 10.0, (half_d + 5.0) * 2.0)
	)

	return particles
