extends Node
## Systeme de temperature/gel/neige. Minuteur/etat independant, meme esprit
## que WeatherSystem.gd/SeasonSystem.gd. L'ordre des noeuds dans Main.tscn
## n'a pas d'impact fonctionnel pour ce script : SeasonSystem/WeatherSystem
## sont lus uniquement via les references %SeasonSystem/%WeatherSystem
## (resolues par nom unique, pas par ordre) et uniquement dans des fonctions
## appelees APRES le _ready() de tous les noeuds (_process/
## _maybe_start_episode/current_temperature).
##
## Simplifications assumees (pas de retour visuel possible pour moi pendant
## le developpement, donc mecaniques simples et sures plutot que fines/
## par-case) :
## - Le gel/la neige sont des etats GLOBAUX (toute la carte), pas par case -
##   un vrai systeme par-case serait bien plus lourd (et couteux en perf, vu
##   la taille de la carte).
## - "Neige au sol" = 2 couleurs discretes herbe/pierre (voir
##   VoxelBlockAppearance.grass_color_for/stone_color_for), pas un vrai bloc
##   de neige separe.
## - "Gel de l'eau" = un etat bool global (VoxelWorld.is_frozen) qui change la
##   couleur de l'eau (glace) et bloque le bouton Puiser (voir
##   ActionValidator.valid_puiser_rect_cells).
##
## Etat gel/neige DETERMINISTE depuis 2026-07-11 (voir _is_ground_frozen) -
## remplace l'ancien seuil continu "temperature <= 0", qui faisait geler/
## degeler le sol 2 fois par jour (cycle jour/nuit traversant 0 en hiver) et
## causait un rebuild_mesh complet a chaque franchissement - un freeze
## periodique tres frequent (voir memoire project_forgotten_caves_
## periodic_freeze_snow_fix). Francois 2026-07-11 : "en climat tempere, le
## sol gele en hiver, directement" - le gel/la neige suivent maintenant
## uniquement la saison et les episodes (vague de froid), jamais la
## temperature fine calculee frame par frame. current_temperature() reste
## inchangee (encore utilisee pour l'affichage et le confort des nains, voir
## Dwarf.temperature_status/ActionController).

const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")
## Voir SeasonSystem.gd/WeatherSystem.gd - meme pattern pour lire
## DayNightCycleScript.game_speed (pause/x1/x2/x4).
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

var current_episode: String = ""  # "" = aucun episode en cours
var _episode_time_left: float = 0.0
var _episode_check_timer: float = 0.0

var _last_applied_frozen: int = -1  # -1 = aucun appel encore fait (voir _apply_to_voxel_world)

## Evite de spammer la console a chaque frame si _voxel_world/_season_system/
## _weather_system/_day_night restent null (noeud manquant/renomme) - un seul
## avertissement au premier _process() concerne.
var _warned_missing_refs: bool = false

@onready var _season_system: Node = %SeasonSystem
@onready var _day_night: Node = %DayNightCycle
@onready var _weather_system: Node = %WeatherSystem
@onready var _voxel_world: Node3D = %VoxelWorld


func _ready() -> void:
	# Flux GameRandom dedie ("temperature") plutot que le RNG global -
	# reproductibilite par graine isolee des autres systemes (corrige I80
	# 2026-07-11, voir doc GameRandom.gd).
	_episode_check_timer = GameRandom.get_rng("temperature").randf_range(episode_check_interval_min, episode_check_interval_max)


func _process(delta: float) -> void:
	if not _warned_missing_refs and (_voxel_world == null or _season_system == null or _weather_system == null or _day_night == null):
		push_warning("TemperatureSystem: reference(s) manquante(s) de facon persistante (VoxelWorld=%s, SeasonSystem=%s, WeatherSystem=%s, DayNightCycle=%s) - scene probablement mal configuree" % [_voxel_world != null, _season_system != null, _weather_system != null, _day_night != null])
		_warned_missing_refs = true
	var scaled_delta: float = delta * DayNightCycleScript.game_speed
	if current_episode != "":
		_episode_time_left -= scaled_delta
		if _episode_time_left <= 0.0:
			current_episode = ""
			_episode_check_timer = GameRandom.get_rng("temperature").randf_range(episode_check_interval_min, episode_check_interval_max)
	else:
		_episode_check_timer -= scaled_delta
		if _episode_check_timer <= 0.0:
			_maybe_start_episode()

	_apply_to_voxel_world(_is_ground_frozen())


## Vrai si le sol/l'eau doivent etre geles (et donc l'herbe/pierre "gelees",
## voir VoxelBlockAppearance) - deterministe, ne depend plus de
## current_temperature() frame par frame (voir doc de tete du fichier).
## Gele en hiver, ou pendant une vague de froid (n'importe quelle saison
## eligible, voir EPISODE_SEASONS) - jamais entre les deux.
func _is_ground_frozen() -> bool:
	var season_id: String = ClimateDefs.season_id_or_default(_season_system)
	return season_id == "hiver" or current_episode == EPISODE_COLD_WAVE


## N'appelle VoxelWorld.set_climate_state (qui reconstruit le mesh) que quand
## l'etat gele change reellement - has_snow suit exactement la meme valeur
## que frozen (Francois 2026-07-11 : "des le debut de l'hiver" plutot qu'une
## accumulation progressive, voir memoire freeze periodique).
func _apply_to_voxel_world(frozen: bool) -> void:
	if _voxel_world == null:
		return
	if int(frozen) == _last_applied_frozen:
		return
	_last_applied_frozen = int(frozen)
	if OS.is_debug_build():
		print("[Perf] set_climate_state declenche : frozen=%s" % frozen)
	_voxel_world.set_climate_state(frozen, frozen)


func _maybe_start_episode() -> void:
	# Flux GameRandom dedie ("temperature") pour tous les tirages de cette
	# fonction - voir doc de _ready().
	var rng: RandomNumberGenerator = GameRandom.get_rng("temperature")
	_episode_check_timer = rng.randf_range(episode_check_interval_min, episode_check_interval_max)
	if rng.randf() > EPISODE_CHANCE_PER_CHECK:
		return
	# Repli factorise via ClimateDefs.season_id_or_default (motif duplique
	# aussi dans DayNightCycle.gd/WeatherSystem.gd).
	var season_id: String = ClimateDefs.season_id_or_default(_season_system)
	var candidates: Array = []
	for episode_id in EPISODE_SEASONS:
		if season_id in EPISODE_SEASONS[episode_id]:
			candidates.append(episode_id)
	if candidates.is_empty():
		return
	current_episode = candidates[rng.randi() % candidates.size()]
	_episode_time_left = rng.randf_range(episode_duration_min, episode_duration_max)
	# Vague de froid : force la meteo visible a "Neige" pour toute la duree de
	# l'episode (Francois 2026-07-11 : "temps=neige, sol gele=VRAI") - voir
	# WeatherSystem.force_snow, un nom explicite pour ne pas avoir a resoudre
	# l'enum Weather depuis ce fichier (meme raison que is_snowing()).
	if current_episode == EPISODE_COLD_WAVE and _weather_system != null:
		_weather_system.force_snow(_episode_time_left)


## Temperature actuelle (degres C) : base de saison + oscillation jour/nuit
## (creux vers minuit, pic vers midi, voir DayNightCycle.time_of_day) +
## delta d'episode eventuel (vague de froid/canicule). Purement informatif
## depuis 2026-07-11 (affichage ClimateUI, confort Dwarf.temperature_status)
## - ne pilote plus le gel/la neige (voir _is_ground_frozen).
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
	return _is_ground_frozen()


## Libelle affichable de l'episode en cours ("" si aucun) - utilise par
## ClimateUI.gd pour l'affichage du climat.
func episode_label() -> String:
	match current_episode:
		EPISODE_COLD_WAVE:
			return "Vague de froid"
		EPISODE_HEAT_WAVE:
			return "Canicule"
		_:
			return ""
