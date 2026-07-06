extends Node
## Sprint 30 (2026-07-02) : systeme meteo purement visuel, independant du
## gameplay (comme DayNightCycle.gd). Alterne aleatoirement dans le temps
## entre Normal / Brouillard / Pluie / Neige. Ajoute les effets meteo
## PAR-DESSUS ce que DayNightCycle calcule (densite de fog, energie
## lumineuse, teinte du ciel) : DayNightCycle reste proprietaire des
## couleurs de ciel/sol et de la rotation/couleur de base de la lumiere ;
## WeatherSystem n'ajoute qu'un delta de densite de fog, un multiplicateur
## d'energie lumineuse et une teinte de ciel, tous lisses/interpoles pour
## eviter un changement brutal quand la meteo change.
## 2026-07-06 (revue de code Phase 2, C8/C10/I49/I56) : jusqu'ici cette
## composition ne fonctionnait QUE parce que WeatherSystem est place APRES
## DayNightCycle dans Main.tscn (donc son _process() tourne juste apres) -
## un reordonnancement accidentel des noeuds aurait casse silencieusement le
## resultat visuel (aucune erreur levee). Desormais WeatherSystem lit les
## champs publics base_light_energy/base_sky_*_color/base_ground_*_color de
## DayNightCycle (voir _day_night_cycle ci-dessous) au lieu de relire
## _light.light_energy/_sky_material.*_color (potentiellement deja modifies
## par ce meme script) - la composition ne depend plus de l'ordre des noeuds.

## Reference au script (pas juste une scene) pour lire ses constantes de
## dimensions de carte (WIDTH/DEPTH/BUILD_CEILING) sans les dupliquer en dur
## ici - voir la memoire du bug GROUND_LEVEL (2026-07-02) : une constante de
## hauteur dupliquee et jamais mise a jour ailleurs avait cause un bug
## silencieux, on evite de reproduire ce probleme.
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")
## Sprint 37 (backlog Phase 1 item 8) : voir SeasonSystem.gd - meme pattern
## pour lire DayNightCycleScript.game_speed (pause/x1/x2/x4).
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")
## 2026-07-06 (revue de code, paquet B, I50) : pour season_id_or_default().
const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")

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

## Sprint 41 (2026-07-04, demande explicite : "on peut changer la couleur
## d'arriere plan, bleu s'il fait beau, gris pour brouillard et pluies etc")
## - couleur de ciel "teinte" par meteo, appliquee PAR-DESSUS la couleur de
## DayNightCycle (meme principe de composition que fog_density/light_energy
## ci-dessus : DayNightCycle reste proprietaire de la couleur "de base" par
## heure, WeatherSystem la teinte ensuite ce meme frame - voir _process, qui
## tourne juste APRES DayNightCycle grace a l'ordre des noeuds dans
## Main.tscn). NORMAL garde une force de 0.0 (aucune teinte, le ciel reste
## celui de l'heure du jour tel quel) ; les 3 autres tirent progressivement
## vers un gris (plus ou moins fonce/bleute) a la force indiquee.
const SKY_TINT_COLOR := {
	Weather.NORMAL: Color(0.32, 0.52, 0.85),      # ignore (force 0.0 ci-dessous)
	Weather.BROUILLARD: Color(0.78, 0.79, 0.80),  # gris clair uniforme
	Weather.PLUIE: Color(0.42, 0.46, 0.52),       # gris plus sombre, legerement bleute
	Weather.NEIGE: Color(0.88, 0.90, 0.93),       # gris tres clair/blanchatre
}
## Sprint 43 (2026-07-04, "le ciel n'a pas change de couleur" - force
## augmentee nettement pour un changement indiscutable, meme si la meteo
## n'a montre qu'une legere teinte auparavant).
const SKY_TINT_STRENGTH := {
	Weather.NORMAL: 0.0,
	Weather.BROUILLARD: 0.85,
	Weather.PLUIE: 0.8,
	Weather.NEIGE: 0.7,
}

var current_weather: int = Weather.NORMAL
var _time_left: float = 0.0
var _fog_extra: float = 0.0
var _light_mult: float = 1.0
var _sky_tint_strength: float = 0.0

@onready var _world_environment: WorldEnvironment = %WorldEnvironment
@onready var _light: DirectionalLight3D = %DirectionalLight3D
@onready var _season_system: Node = %SeasonSystem
@onready var _sky_material: ProceduralSkyMaterial = _world_environment.environment.sky.sky_material as ProceduralSkyMaterial
## 2026-07-06 (revue de code Phase 2, C8/C10/I49/I56) : reference au noeud
## (pas juste au script comme DayNightCycleScript ci-dessus) pour lire ses
## champs d'instance base_light_energy/base_sky_*_color/base_ground_*_color
## - voir le commentaire d'en-tete de ce fichier.
@onready var _day_night_cycle: Node = %DayNightCycle
var _rain_particles: GPUParticles3D
var _snow_particles: GPUParticles3D

# Sprint 33 : la meteo n'est plus tiree dans une seule liste fixe - chaque
# saison a sa propre "urne" de probabilites (repetition = plus de chances),
# pour que l'hiver ait plus de neige, le printemps/l'automne plus de pluie,
# et l'ete quasiment jamais de neige.
const SEASON_WEATHER_POOLS := {
	"ete": [Weather.NORMAL, Weather.NORMAL, Weather.NORMAL, Weather.BROUILLARD, Weather.PLUIE],
	"automne": [Weather.NORMAL, Weather.NORMAL, Weather.BROUILLARD, Weather.BROUILLARD, Weather.PLUIE, Weather.PLUIE],
	"hiver": [Weather.NORMAL, Weather.NORMAL, Weather.BROUILLARD, Weather.NEIGE, Weather.NEIGE, Weather.NEIGE],
	"printemps": [Weather.NORMAL, Weather.NORMAL, Weather.PLUIE, Weather.PLUIE, Weather.PLUIE, Weather.BROUILLARD],
}


func _ready() -> void:
	_time_left = randf_range(min_weather_duration, max_weather_duration)
	_rain_particles = _build_particles(false)
	_snow_particles = _build_particles(true)
	add_child(_rain_particles)
	add_child(_snow_particles)
	_apply_particles()


func _process(delta: float) -> void:
	var scaled_delta: float = delta * DayNightCycleScript.game_speed
	_time_left -= scaled_delta
	if _time_left <= 0.0:
		_pick_new_weather()

	_fog_extra = lerp(_fog_extra, FOG_DENSITY_EXTRA[current_weather], scaled_delta * transition_speed)
	_light_mult = lerp(_light_mult, LIGHT_ENERGY_MULT[current_weather], scaled_delta * transition_speed)
	_sky_tint_strength = lerp(_sky_tint_strength, SKY_TINT_STRENGTH[current_weather], scaled_delta * transition_speed)

	_world_environment.environment.fog_density = BASE_FOG_DENSITY + _fog_extra
	_light.light_energy = _day_night_cycle.base_light_energy * _light_mult

	# 2026-07-06 (revue de code, C9) : print de diagnostic temporaire du
	# 2026-07-05 ("chene/bouleau deviennent vert sombre tout a coup") retire -
	# il tournait en continu toutes les 2 secondes sans jamais avoir ete
	# retire, marque "temporaire" dans son propre commentaire d'origine. Si le
	# symptome revient, rediagnostiquer plutot que supposer la cause deja
	# trouvee (aucune confirmation en jeu ne l'atteste).

	# Sprint 41 : teinte le ciel (deja colore par DayNightCycle ce meme frame,
	# voir commentaire de SKY_TINT_COLOR) vers un gris selon la meteo courante.
	# Les couleurs "sol" (ground_bottom/ground_horizon) recoivent la meme
	# teinte assombrie de 25%, pour rester coherentes avec le rapport
	# sky/ground deja utilise par DayNightCycle.
	var tint: Color = SKY_TINT_COLOR[current_weather]
	var ground_tint: Color = tint * 0.75
	_sky_material.sky_top_color = _day_night_cycle.base_sky_top_color.lerp(tint, _sky_tint_strength)
	_sky_material.sky_horizon_color = _day_night_cycle.base_sky_horizon_color.lerp(tint, _sky_tint_strength)
	_sky_material.ground_bottom_color = _day_night_cycle.base_ground_bottom_color.lerp(ground_tint, _sky_tint_strength)
	_sky_material.ground_horizon_color = _day_night_cycle.base_ground_horizon_color.lerp(ground_tint, _sky_tint_strength)


func _pick_new_weather() -> void:
	# Sprint 33 : l'urne de probabilites depend de la saison courante
	# (SeasonSystem.gd) - repli sur la saison par defaut si jamais SeasonSystem
	# n'est pas trouve (ne devrait pas arriver, garde-fou uniquement).
	# 2026-07-06 (paquet B, I50) : repli factorise via ClimateDefs.season_id_or_default.
	var season_id: String = ClimateDefs.season_id_or_default(_season_system)
	var choices: Array = SEASON_WEATHER_POOLS.get(season_id, SEASON_WEATHER_POOLS["ete"])
	current_weather = choices[randi() % choices.size()]
	_time_left = randf_range(min_weather_duration, max_weather_duration)
	_apply_particles()


func _apply_particles() -> void:
	_rain_particles.emitting = current_weather == Weather.PLUIE
	_snow_particles.emitting = current_weather == Weather.NEIGE


## Sprint 37 : petits accesseurs typés (bool/String/Color), pour que d'autres
## scripts (TemperatureSystem.gd, ActionController.gd) n'aient pas besoin de
## resoudre l'enum "Weather" via une reference generique %WeatherSystem (le
## typage generique ne resout pas les enums definis dans ce script, meme
## probleme deja rencontre avec VoxelWorld.BlockType - voir ses commentaires).
func is_snowing() -> bool:
	return current_weather == Weather.NEIGE


func current_weather_label() -> String:
	match current_weather:
		Weather.BROUILLARD:
			return "Brouillard"
		Weather.PLUIE:
			return "Pluie"
		Weather.NEIGE:
			return "Neige"
		_:
			return "Ciel degage"


## Sprint 42 : accesseurs utilises par CloudSystem.gd pour teinter les nuages
## EN PHASE avec la teinte du ciel (meme couleur/force que SKY_TINT_COLOR/
## _sky_tint_strength ci-dessus, voir _process) - un nuage plus fonce en
## meme temps que le ciel grisaille, pas un systeme independant.
func cloud_tint_color() -> Color:
	return SKY_TINT_COLOR[current_weather]


func cloud_tint_strength() -> float:
	return _sky_tint_strength


## Couleur utilisee pour la petite icone meteo (voir ActionController._setup_climate_icons)
func current_weather_color() -> Color:
	match current_weather:
		Weather.BROUILLARD:
			return Color(0.75, 0.78, 0.8)
		Weather.PLUIE:
			return Color(0.35, 0.5, 0.85)
		Weather.NEIGE:
			return Color(0.9, 0.95, 1.0)
		_:
			return Color(1.0, 0.85, 0.3)


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
