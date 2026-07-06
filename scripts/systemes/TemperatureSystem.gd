extends Node
## Sprint 37 (2026-07-04) : systeme de temperature/gel/neige - backlog Phase 1
## (items 1-6 : climat/temperature, voir memoire "Forgotten Caves Phase 1
## backlog"). Minuteur/etat independant, meme esprit que WeatherSystem.gd/
## SeasonSystem.gd.
## 2026-07-06 (revue de code Phase 3, C13) : correctif de commentaire - la
## phrase precedente ("place apres eux dans Main.tscn pour pouvoir les lire")
## laissait croire que la position de ce noeud dans Main.tscn importe pour la
## correction du script, ce qui n'est PAS le cas : SeasonSystem/WeatherSystem
## sont lus uniquement via les references %SeasonSystem/%WeatherSystem
## (resolues par nom unique, pas par ordre) et uniquement dans des fonctions
## appelees APRES le _ready() de tous les noeuds (_process/_maybe_start_episode/
## current_temperature) - aucune dependance a leur _ready() deja execute.
## L'ordre des noeuds dans Main.tscn n'a donc aucun impact fonctionnel connu
## pour ce script (contrairement au vrai couplage d'ordre corrige entre
## DayNightCycle.gd et WeatherSystem.gd, voir leurs commentaires).
##
## Simplifications assumees (pas de retour visuel possible pour moi, donc on
## reste sur des mecaniques simples et sures plutot que fines/par-case) :
## - Le gel/la neige sont des etats GLOBAUX (toute la carte), pas par case -
##   un vrai systeme par-case serait bien plus lourd (et couteux en perf, vu
##   la taille de la carte 100x100, voir memoire perf du Sprint 34/35).
## - "Neige au sol" = un voile blanc qui recouvre progressivement la couleur
##   du dessus terre/pierre (voir VoxelWorld.snow_coverage), pas un vrai bloc
##   de neige separe.
## - "Gel de l'eau" = un etat bool global (VoxelWorld.is_frozen) qui change la
##   couleur de l'eau (glace) et bloque le bouton Puiser (voir
##   ActionController._valid_puiser_rect_cells).

const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")
## Sprint 37 (backlog Phase 1 item 8) : voir SeasonSystem.gd/WeatherSystem.gd -
## meme pattern pour lire DayNightCycleScript.game_speed (pause/x1/x2/x4).
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")

## Temperature de base (degres C) par saison, avant oscillation jour/nuit et
## episodes - valeurs approximatives pour un climat "tempere".
const BASE_TEMP_PAR_SAISON := {
	"ete": 24.0,
	"automne": 12.0,
	"hiver": -2.0,
	"printemps": 14.0,
}

## Amplitude de l'oscillation jour/nuit (la nuit est plus froide que le jour)
const DAY_NIGHT_AMPLITUDE := 5.0

const EPISODE_COLD_WAVE := "vague_de_froid"
const EPISODE_HEAT_WAVE := "canicule"
const EPISODE_DELTA := {
	EPISODE_COLD_WAVE: -14.0,
	EPISODE_HEAT_WAVE: 10.0,
}
## Saisons ou chaque episode a un sens (pas de canicule en hiver, pas de vague
## de froid en plein ete)
const EPISODE_SEASONS := {
	EPISODE_COLD_WAVE: ["automne", "hiver", "printemps"],
	EPISODE_HEAT_WAVE: ["ete", "printemps"],
}
const EPISODE_CHANCE_PER_CHECK := 0.12  # tire a chaque fin de "cooldown" entre 2 episodes possibles

@export var episode_check_interval_min: float = 180.0
@export var episode_check_interval_max: float = 360.0
@export var episode_duration_min: float = 60.0
@export var episode_duration_max: float = 150.0

## Vitesse d'accumulation/fonte de la neige (par seconde, 0..1)
const SNOW_ACCUMULATION_RATE := 0.05
const SNOW_MELT_RATE := 0.04
## On ne redeclenche un rebuild_mesh (couteux) que quand la neige a change
## d'au moins ce pas, pas a chaque frame (voir _process/VoxelWorld.set_climate_state)
const SNOW_STEP := 0.1

var current_episode: String = ""  # "" = aucun episode en cours
var _episode_time_left: float = 0.0
var _episode_check_timer: float = 0.0
var snow_coverage: float = 0.0  # 0..1, lu par VoxelWorld pour le voile de neige

var _last_applied_frozen: bool = false
var _last_applied_snow_step: int = -1

## 2026-07-06 (revue de code, paquet C, M37) : evite de spammer la console a
## chaque frame si _voxel_world/_season_system restent null (noeud manquant/
## renomme) - un seul avertissement au premier _process() concerne.
## 2026-07-06 (revue de code, paquet F, I46) : la garde couvrait seulement
## _voxel_world/_season_system - etendue a _weather_system/_day_night ci-
## dessous, qui sont lus plus loin dans ce fichier (is_snowing/time_of_day)
## sans jamais etre verifies eux-memes.
var _warned_missing_refs: bool = false

@onready var _season_system: Node = %SeasonSystem
@onready var _day_night: Node = %DayNightCycle
@onready var _weather_system: Node = %WeatherSystem
@onready var _voxel_world: Node3D = %VoxelWorld


func _ready() -> void:
	_episode_check_timer = randf_range(episode_check_interval_min, episode_check_interval_max)


func _process(delta: float) -> void:
	if not _warned_missing_refs and (_voxel_world == null or _season_system == null or _weather_system == null or _day_night == null):
		push_warning("TemperatureSystem: reference(s) manquante(s) de facon persistante (VoxelWorld=%s, SeasonSystem=%s, WeatherSystem=%s, DayNightCycle=%s) - scene probablement mal configuree" % [_voxel_world != null, _season_system != null, _weather_system != null, _day_night != null])
		_warned_missing_refs = true
	var scaled_delta: float = delta * DayNightCycleScript.game_speed
	if current_episode != "":
		_episode_time_left -= scaled_delta
		if _episode_time_left <= 0.0:
			current_episode = ""
			_episode_check_timer = randf_range(episode_check_interval_min, episode_check_interval_max)
	else:
		_episode_check_timer -= scaled_delta
		if _episode_check_timer <= 0.0:
			_maybe_start_episode()

	var temp: float = current_temperature()
	var frozen: bool = temp <= 0.0
	var snowing: bool = frozen and _weather_system != null and _weather_system.is_snowing()
	if snowing:
		snow_coverage = minf(snow_coverage + SNOW_ACCUMULATION_RATE * scaled_delta, 1.0)
	elif not frozen:
		snow_coverage = maxf(snow_coverage - SNOW_MELT_RATE * scaled_delta, 0.0)
	# Sinon (gele mais pas de chute en cours) : la neige au sol reste telle
	# quelle, ni accumulation ni fonte.

	_apply_to_voxel_world(frozen)


## N'appelle VoxelWorld.set_climate_state (qui reconstruit le mesh) que quand
## l'etat gele change, ou que la neige a franchi un palier de SNOW_STEP - un
## rebuild_mesh a chaque frame serait beaucoup trop couteux sur la carte
## 100x100 (voir memoire perf Sprint 34/35).
func _apply_to_voxel_world(frozen: bool) -> void:
	if _voxel_world == null:
		return
	var snow_step: int = int(round(snow_coverage / SNOW_STEP))
	if frozen == _last_applied_frozen and snow_step == _last_applied_snow_step:
		return
	_last_applied_frozen = frozen
	_last_applied_snow_step = snow_step
	_voxel_world.set_climate_state(frozen, float(snow_step) * SNOW_STEP)


func _maybe_start_episode() -> void:
	_episode_check_timer = randf_range(episode_check_interval_min, episode_check_interval_max)
	if randf() > EPISODE_CHANCE_PER_CHECK:
		return
	# 2026-07-06 (revue de code, paquet B, I50) : repli factorise via
	# ClimateDefs.season_id_or_default (motif duplique aussi dans
	# DayNightCycle.gd/WeatherSystem.gd).
	var season_id: String = ClimateDefs.season_id_or_default(_season_system)
	var candidates: Array = []
	for episode_id in EPISODE_SEASONS:
		if season_id in EPISODE_SEASONS[episode_id]:
			candidates.append(episode_id)
	if candidates.is_empty():
		return
	current_episode = candidates[randi() % candidates.size()]
	_episode_time_left = randf_range(episode_duration_min, episode_duration_max)


## Temperature actuelle (degres C) : base de saison + oscillation jour/nuit
## (creux vers minuit, pic vers midi, voir DayNightCycle.time_of_day) +
## delta d'episode eventuel (vague de froid/canicule).
func current_temperature() -> float:
	var season_id: String = ClimateDefs.season_id_or_default(_season_system)
	var base: float = BASE_TEMP_PAR_SAISON.get(season_id, 15.0)
	if _day_night != null:
		# time_of_day : 0.0 Matin / 0.25 Jour(midi) / 0.5 Soir / 0.75 Nuit(minuit)
		var day_night_factor: float = cos((_day_night.time_of_day - 0.25) * TAU)
		base += day_night_factor * DAY_NIGHT_AMPLITUDE
	if current_episode != "":
		base += EPISODE_DELTA.get(current_episode, 0.0)
	return base


func is_frozen() -> bool:
	return current_temperature() <= 0.0


## Libelle affichable de l'episode en cours ("" si aucun) - utilise par
## ActionController.gd pour l'affichage du climat.
func episode_label() -> String:
	match current_episode:
		EPISODE_COLD_WAVE:
			return "Vague de froid"
		EPISODE_HEAT_WAVE:
			return "Canicule"
		_:
			return ""
