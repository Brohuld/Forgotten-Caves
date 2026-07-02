extends Node
## Sprint 29 (2026-07-02) : cycle jour/nuit purement visuel (plan approuve
## par Francois avant implementation, voir memoire "day/night cycle plan").
## Pilote le ciel (WorldEnvironment/ProceduralSkyMaterial), la lumiere
## directionnelle (couleur/intensite/rotation) et une lune fixe visible la
## nuit. Aucun lien avec le gameplay (sommeil des nains, etc.) pour
## l'instant - strictement visuel, comme demande.
##
## cycle_duration_seconds est volontairement tres court (30s) pour tester
## rapidement les transitions ; sera augmente pour la version definitive
## (simple changement de valeur dans l'inspecteur, aucun code a modifier).

@export var cycle_duration_seconds: float = 30.0

## Inclinaison fixe (lacet) de l'axe de rotation du soleil, pour donner un
## balayage "en diagonale" plutot que purement nord-sud (coherent avec le
## ressenti "gauche a droite" demande). Le TANGAGE (x), lui, tourne en
## continu sur 360 degres au fil du cycle : a x=0 la lumiere est quasi
## horizontale (lever), a x=-90 elle pointe droit vers le bas (zenith, midi),
## a x=-180 de nouveau horizontale mais de l'autre cote (coucher), a x=-270
## elle pointe vers le HAUT (sous l'horizon, minuit - plus aucun eclairage au
## sol). Une seule formule continue (voir _process) evite tout probleme de
## "sens de rotation" qu'aurait une interpolation par quaternions entre des
## keyframes disjointes.
const SUN_YAW_DEGREES := -45.0

## 4 phases reparties a intervalles egaux sur le cycle : Matin(0.0) / Jour
## (0.25) / Soir(0.5) / Nuit(0.75), puis retour a Matin (1.0 == 0.0). Tous
## les tableaux ci-dessous sont interpoles en continu entre phases
## adjacentes (voir _process) - aucune bascule brutale.
const PHASE_COUNT := 4

const SKY_TOP := [
	Color(0.95, 0.65, 0.75),  # Matin (rose)
	Color(0.32, 0.52, 0.85),  # Jour (bleu, palette d'origine de Main.tscn)
	Color(0.35, 0.12, 0.12),  # Soir (rouge sombre)
	Color(0.03, 0.03, 0.05),  # Nuit (gris tres sombre)
]
const SKY_HORIZON := [
	Color(1.0, 0.75, 0.65),
	Color(0.75, 0.82, 0.9),
	Color(0.65, 0.25, 0.15),
	Color(0.08, 0.08, 0.12),
]
const GROUND_BOTTOM := [
	Color(0.35, 0.25, 0.25),
	Color(0.28, 0.22, 0.18),
	Color(0.25, 0.12, 0.1),
	Color(0.02, 0.02, 0.03),
]
const GROUND_HORIZON := [
	Color(0.7, 0.55, 0.5),
	Color(0.55, 0.48, 0.4),
	Color(0.45, 0.22, 0.15),
	Color(0.05, 0.05, 0.07),
]
const LIGHT_COLOR := [
	Color(1.0, 0.75, 0.7),
	Color(1.0, 1.0, 1.0),
	Color(0.9, 0.35, 0.25),
	Color(0.3, 0.35, 0.5),
]
## Nuit = 0.0 pile (pas juste "tres faible") : Francois veut qu'il n'y ait
## plus DU TOUT de lumiere sur la carte la nuit.
const LIGHT_ENERGY := [0.8, 1.0, 0.6, 0.0]
## 2026-07-02 : la lumiere ambiante (WorldEnvironment.environment.
## ambient_light_energy, source = ciel) n'etait jusqu'ici jamais touchee par
## ce script - meme avec light_energy quasi nul la nuit, l'ambiant restait a
## sa valeur par defaut (1.0) et continuait a eclairer legerement toute la
## carte. On la fait maintenant varier avec les memes phases, pour une nuit
## vraiment sombre (voir aussi VoxelWorld._make_material / Forest.
## _flat_material qui, jusqu'a ce sprint, ignoraient totalement l'eclairage -
## SHADING_MODE_UNSHADED - ce qui empechait aussi bien l'ombre que
## l'assombrissement nocturne de fonctionner).
const AMBIENT_ENERGY := [0.8, 1.0, 0.6, 0.0]
const FOG_COLOR := [
	Color(0.9, 0.7, 0.7),
	Color(0.65, 0.68, 0.72),  # Jour : identique au fog_light_color d'origine de Main.tscn
	Color(0.5, 0.25, 0.2),
	Color(0.08, 0.08, 0.12),
]
## Opacite de la lune : invisible le jour, pleine opacite la nuit, fondu
## enchaine automatique pendant les phases adjacentes (Soir->Nuit et
## Nuit->Matin) grace a la meme interpolation que les autres champs.
const MOON_ALPHA := [0.0, 0.0, 0.0, 1.0]

var time_of_day: float = 0.0

@onready var _light: DirectionalLight3D = %DirectionalLight3D
@onready var _world_environment: WorldEnvironment = %WorldEnvironment
@onready var _moon: MeshInstance3D = %Moon
@onready var _sky_material: ProceduralSkyMaterial = _world_environment.environment.sky.sky_material as ProceduralSkyMaterial
@onready var _moon_material: StandardMaterial3D = _moon.material_override as StandardMaterial3D


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / cycle_duration_seconds, 1.0)

	var phase_pos: float = time_of_day * PHASE_COUNT
	var idx0: int = int(floor(phase_pos)) % PHASE_COUNT
	var idx1: int = (idx0 + 1) % PHASE_COUNT
	var t: float = phase_pos - floor(phase_pos)

	_sky_material.sky_top_color = SKY_TOP[idx0].lerp(SKY_TOP[idx1], t)
	_sky_material.sky_horizon_color = SKY_HORIZON[idx0].lerp(SKY_HORIZON[idx1], t)
	_sky_material.ground_bottom_color = GROUND_BOTTOM[idx0].lerp(GROUND_BOTTOM[idx1], t)
	_sky_material.ground_horizon_color = GROUND_HORIZON[idx0].lerp(GROUND_HORIZON[idx1], t)

	_light.light_color = LIGHT_COLOR[idx0].lerp(LIGHT_COLOR[idx1], t)
	_light.light_energy = lerp(LIGHT_ENERGY[idx0], LIGHT_ENERGY[idx1], t)
	# Rotation continue (voir commentaire de SUN_YAW_DEGREES) : independante
	# du systeme de keyframes ci-dessus, calculee directement a partir de
	# time_of_day pour eviter toute discontinuite de sens de rotation.
	_light.rotation_degrees = Vector3(-360.0 * time_of_day, SUN_YAW_DEGREES, 0.0)

	_world_environment.environment.ambient_light_energy = lerp(AMBIENT_ENERGY[idx0], AMBIENT_ENERGY[idx1], t)
	_world_environment.environment.fog_light_color = FOG_COLOR[idx0].lerp(FOG_COLOR[idx1], t)

	var moon_alpha: float = lerp(MOON_ALPHA[idx0], MOON_ALPHA[idx1], t)
	_moon.visible = moon_alpha > 0.01
	if _moon_material:
		_moon_material.albedo_color.a = moon_alpha
