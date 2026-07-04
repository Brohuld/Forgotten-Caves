extends Node
## Sprint 33 (2026-07-02) : systeme de saisons, plan approuve par Francois
## avant implementation. Minuteur independant (meme principe que
## WeatherSystem.gd) qui boucle a travers les 4 saisons de
## ClimateDefinitions.SEASONS (Ete -> Automne -> Hiver -> Printemps -> Ete...).
## A chaque changement de saison :
## - recolore le sol (VoxelWorld.season_id + rebuild_mesh())
## - reteint le feuillage des arbres deja plantes (Forest.apply_season_tint)
## - expose la saison courante (current_season_id()) pour que
##   WeatherSystem.gd puisse en tenir compte dans le tirage meteo
##
## season_duration_seconds : 2026-07-02, calendrier definitif fixe par
## Francois - 1 jour = 2 min (DayNightCycle.cycle_duration_seconds = 120s),
## 1 mois = 20 jours, 1 saison = 3 mois = 60 jours, donc 60 * 120 = 7200s.
## Ce minuteur reste independant de celui de DayNightCycle.gd (pas de lecture
## directe de day_count ici), mais comme les deux partent en meme temps au
## lancement du jeu et avancent du meme delta chaque frame, ils restent
## synchronises tant que season_duration_seconds est un multiple exact de
## cycle_duration_seconds (ici x60) - c'est ce qui permet a ActionController.gd
## de calculer jour-du-mois/mois-de-la-saison uniquement a partir de
## DayNightCycle.day_count, sans avoir besoin d'interroger ce script.

const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")
## Sprint 37 (backlog Phase 1 item 8) : pour lire le multiplicateur partage
## DayNightCycleScript.game_speed (pause/x1/x2/x4, voir ActionController.gd) -
## meme pattern que Dwarf.gd/CharacterSheetUI.gd (static var lue via le script,
## pas via une instance generique).
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")

## Nombre de jours par mois et de mois par saison (voir commentaire ci-dessus)
## - utilises par ActionController.gd pour l'affichage "Jour X (Mois Y)".
const DAYS_PER_MONTH := 20
const MONTHS_PER_SEASON := 3

@export var season_duration_seconds: float = 7200.0

var current_season_index: int = 0
var _time_left: float = 0.0

@onready var _voxel_world: Node3D = %VoxelWorld
@onready var _forest: Node3D = %Forest


func _ready() -> void:
	_time_left = season_duration_seconds
	_apply_season()


func _process(delta: float) -> void:
	_time_left -= delta * DayNightCycleScript.game_speed
	if _time_left <= 0.0:
		current_season_index = (current_season_index + 1) % ClimateDefs.SEASONS.size()
		_time_left = season_duration_seconds
		_apply_season()


## Utilise par WeatherSystem.gd (meteo liee a la saison) et par
## ActionController.gd (affichage de l'horloge/calendrier).
func current_season_id() -> String:
	return ClimateDefs.SEASONS[current_season_index]


## Sprint 37nonies (2026-07-04, backlog UI climat) : fraction (0-1) de
## progression a l'interieur de la saison courante - utilise par
## ActionController.gd pour positionner le marqueur sur le bandeau saison.
func season_progress() -> float:
	return 1.0 - clampf(_time_left / season_duration_seconds, 0.0, 1.0)


func _apply_season() -> void:
	var season_id := current_season_id()
	_voxel_world.season_id = season_id
	_voxel_world.rebuild_mesh()
	_forest.apply_season_tint(season_id)
