extends Node
## Systeme de saisons : minuteur independant (meme principe que
## WeatherSystem.gd) qui boucle a travers les 4 saisons de
## ClimateDefinitions.SEASONS (Ete -> Automne -> Hiver -> Printemps -> Ete...).
## A chaque changement de saison :
## - recolore le sol (VoxelWorld.season_id + rebuild_mesh())
## - reteint le feuillage des arbres deja plantes (Forest.apply_season_tint)
## - expose la saison courante (current_season_id()) pour que
##   WeatherSystem.gd puisse en tenir compte dans le tirage meteo
##
## season_duration_seconds : calendrier - 1 jour = 2 min
## (DayNightCycle.cycle_duration_seconds = 120s), 1 mois = 20 jours, 1 saison
## = 3 mois = 60 jours, donc 60 * 120 = 7200s. Ce minuteur reste independant
## de celui de DayNightCycle.gd (pas de lecture directe de day_count ici),
## mais comme les deux partent en meme temps au lancement du jeu et avancent
## du meme delta chaque frame, ils restent synchronises tant que
## season_duration_seconds est un multiple exact de cycle_duration_seconds
## (ici x60) - c'est ce qui permet a ActionController.gd de calculer
## jour-du-mois/mois-de-la-saison uniquement a partir de
## DayNightCycle.day_count, sans avoir besoin d'interroger ce script.

const ClimateDefs := preload("res://scripts/data/climats/ClimateDefinitions.gd")
## Pour lire le multiplicateur partage DayNightCycleScript.game_speed
## (pause/x1/x2/x4, voir ClimateUI.gd) - meme pattern que Dwarf.gd/
## CharacterSheetUI.gd (static var lue via le script, pas via une instance
## generique).
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")

## Nombre de jours par mois et de mois par saison (voir commentaire
## ci-dessus) - utilises par ActionController.gd pour l'affichage
## "Jour X (Mois Y)".
const DAYS_PER_MONTH := 20
const MONTHS_PER_SEASON := 3

@export var season_duration_seconds: float = 7200.0

## StartMenu.gd (ecran affiche avant Main.tscn) ecrit cette valeur AVANT le
## changement de scene - meme contrat que VoxelWorld.use_fixed_seed/
## requested_seed (voir sa doc) : SEUL StartMenu.gd a le droit d'ECRIRE, tout
## autre script ne fait que LIRE. Toujours un index valide dans
## ClimateDefs.SEASONS : StartMenu presente TOUJOURS un choix concret
## (preselectionne au hasard, ou force par un clic) - contrairement a la
## graine de carte, pas de notion de "vide = aleatoire" ici, donc pas besoin
## d'un bool "use_fixed_*" separe. Ce choix precede la creation du seed de
## partie et en est totalement independant : la meme graine peut desormais
## demarrer dans des saisons differentes d'une partie a l'autre (corrige
## I79/2026-07-11 : la saison de depart n'est plus tiree via le flux
## GameRandom("saisons"), remplace par ce choix explicite).
static var requested_season_index: int = 0

var current_season_index: int = 0
var _time_left: float = 0.0

@onready var _voxel_world: Node3D = %VoxelWorld
@onready var _forest: Node3D = %Forest
# SeasonSystem est declare APRES BerryBushes/GroundDecoration dans Main.tscn
# (voir ce fichier) - leur propre _ready() (construction des MultiMesh
# partages/de la decoration) s'execute donc AVANT celui de SeasonSystem,
# exactement comme Forest ci-dessus. Sans ce reordonnancement, le premier
# appel a _apply_season() (depuis _ready() plus bas) tomberait sur des
# dictionnaires _mmi/_pending_colors encore vides cote BerryBushes/
# GroundDecoration.
@onready var _berry_bushes: Node3D = %BerryBushes
@onready var _ground_decoration: Node3D = %GroundDecoration


func _ready() -> void:
	# Saison de depart choisie dans StartMenu.gd (preselectionnee au hasard,
	# ou forcee par un clic) - voir doc de requested_season_index. Bornee
	# defensivement (clampi) au cas ou ClimateDefs.SEASONS changerait de
	# taille sans mise a jour correspondante de StartMenu.gd.
	current_season_index = clampi(requested_season_index, 0, ClimateDefs.SEASONS.size() - 1)
	_time_left = season_duration_seconds
	# Forest/BerryBushes/GroundDecoration generent par paquets (voir leur
	# BATCH_SIZE, await process_frame) - cette generation peut donc encore
	# etre en cours quand ce _ready() s'execute (l'ancienne garantie "le
	# _ready() precedent dans Main.tscn est toujours fini avant celui-ci",
	# documentee juste au-dessus sur _berry_bushes/_ground_decoration, ne
	# tient plus des qu'un _ready() contient un await). On attend donc
	# explicitement la fin reelle de generation de chacun (generation_done/
	# generation_finished, voir leur doc) avant le tout premier appel a
	# _apply_season() - sans quoi apply_season_tint()/apply_season()
	# liraient des tableaux partiellement remplis alors que le MultiMesh
	# partage aurait encore un instance_count de 0 (crash).
	await _wait_for_world_generation()
	_apply_season()
	if OS.is_debug_build():
		print("[Perf] SeasonSystem : 1ere saison (%s) appliquee a %.1f s depuis le debut de la scene" % [current_season_id(), (Time.get_ticks_msec() - DayNightCycleScript.scene_start_ms) / 1000.0])


## Voir doc du await dans _ready() ci-dessus. N'attend que ce qui n'est pas
## deja termine (evite d'attendre indefiniment un signal deja emis - un
## signal Godot n'est jamais "rejoue" pour un ecouteur arrivant apres coup).
func _wait_for_world_generation() -> void:
	if _forest != null and not _forest.generation_done:
		await _forest.generation_finished
	if _berry_bushes != null and not _berry_bushes.generation_done:
		await _berry_bushes.generation_finished
	if _ground_decoration != null and not _ground_decoration.generation_done:
		await _ground_decoration.generation_finished


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


## Fraction (0-1) de progression a l'interieur de la saison courante -
## utilise par ClimateUI.gd pour positionner le marqueur sur le bandeau
## saison.
func season_progress() -> float:
	return 1.0 - clampf(_time_left / season_duration_seconds, 0.0, 1.0)


func _apply_season() -> void:
	# Garde de nullite sur les 4 noeuds lus ci-dessous (et par
	# _apply_winter_fruit_availability, appelee en fin de fonction) - meme
	# principe que CameraRig.gd (has_method/!= null) - un noeud manquant ou
	# un ordre de scene casse leve un avertissement explicite plutot qu'un
	# crash.
	if _voxel_world == null or _forest == null or _berry_bushes == null or _ground_decoration == null:
		push_warning("SeasonSystem: noeud(s) manquant(s) (VoxelWorld/Forest/BerryBushes/GroundDecoration), changement de saison ignore")
		return
	var season_id := current_season_id()
	_voxel_world.season_id = season_id
	_voxel_world.rebuild_mesh()
	_forest.apply_season_tint(season_id)
	# Cycle des saisons complet (printemps/ete/automne/hiver, voir les
	# commentaires de chaque fonction appelee ci-dessous pour le detail).
	_berry_bushes.apply_season_tint(season_id)
	_ground_decoration.apply_season(season_id)
	_apply_winter_fruit_availability(season_id == "hiver")


## Hiver : disparition totale des fruits sur les arbres, les plantes et les
## buissons - plus aucune recolte possible en hiver. Generique sur le groupe
## "cueillette" (arbres fruitiers ET buissons/plantes, voir Forest.gd/
## BerryBushes.gd - memes metadonnees fruit_resource/fruits_left et
## convention de nommage Fruit_%d ; voir aussi Dwarf.gd/_complete_task, qui
## exige fruits_left > 0 pour recolter - remettre cette meta a 0 suffit donc
## a bloquer la recolte sans toucher au code de Dwarf.gd). Stocke le vrai
## compte dans la meta "fruits_left_avant_hiver" et restaure les deux au
## degel - les fruits eux-memes ne sont jamais detruits ni regeneres,
## seulement caches (visible=false) puis reaffiches.
## update_view_level est rappele sur Forest.gd/BerryBushes.gd apres
## restauration pour reconcilier cette visibilite avec le niveau de vue
## courant (un arbre situe au-dessus du niveau affiche doit rester cache,
## meme si l'hiver vient de se terminer) - meme logique deja utilisee par
## ces deux scripts.
## Limite connue (acceptable, cas tres rare) : un arbre/buisson qui repousse
## PENDANT l'hiver (voir Forest.gd/_maybe_regrow_tree) n'est pas concerne par
## cette regle avant le prochain changement de saison - seul BerryBushes.gd a
## une repousse de fruit individuelle pendant la partie (voir
## set_winter_active ci-dessous), les arbres ne font repousser que des arbres
## entiers, jamais des fruits individuels sur un arbre existant.
func _apply_winter_fruit_availability(is_winter: bool) -> void:
	for target in get_tree().get_nodes_in_group("cueillette"):
		if is_winter:
			if target.has_meta("fruits_left_avant_hiver"):
				continue  # deja applique (evite d'ecraser la vraie valeur si _apply_season tournait 2x)
			var current: int = int(target.get_meta("fruits_left", 0))
			target.set_meta("fruits_left_avant_hiver", current)
			target.set_meta("fruits_left", 0)
			for child in target.get_children():
				if (child.name as String).begins_with("Fruit_"):
					child.visible = false
		else:
			if not target.has_meta("fruits_left_avant_hiver"):
				continue
			var restored: int = int(target.get_meta("fruits_left_avant_hiver"))
			target.set_meta("fruits_left", restored)
			target.remove_meta("fruits_left_avant_hiver")
			for child in target.get_children():
				if (child.name as String).begins_with("Fruit_"):
					child.visible = true
	_berry_bushes.set_winter_active(is_winter)
	_forest.set_winter_fruits_hidden(is_winter)  # sinon update_view_level() ci-dessous reafficherait les fruits caches juste au-dessus
	# L'ordre exact des 4 lignes ci-dessus (set_winter_* avant
	# update_view_level) n'est pas strictement critique : Forest.gd et
	# BerryBushes.gd consultent chacun leur PROPRE flag interne
	# (_winter_fruits_hidden / _winter_active) directement a l'interieur de
	# leur update_view_level(), donc meme un appel dans l'autre sens
	# donnerait le meme resultat final tant que les deux lignes de cette
	# fonction s'executent avant la fin de _apply_season().
	_forest.update_view_level(_voxel_world.view_level)
	_berry_bushes.update_view_level(_voxel_world.view_level)
