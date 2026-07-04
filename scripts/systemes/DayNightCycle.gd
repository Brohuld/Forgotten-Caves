extends Node
## Sprint 29 (2026-07-02) : cycle jour/nuit purement visuel (plan approuve
## par Francois avant implementation, voir memoire "day/night cycle plan").
## Pilote le ciel (WorldEnvironment/ProceduralSkyMaterial), la lumiere
## directionnelle (couleur/intensite/rotation) et une lune fixe visible la
## nuit. Aucun lien avec le gameplay (sommeil des nains, etc.) pour
## l'instant - strictement visuel, comme demande.
##
## cycle_duration_seconds : duree reelle d'une journee de jeu.
## 2026-07-02 : Francois a fixe le calendrier definitif -
## 1 jour = 2 minutes, 1 mois = 20 jours, 1 saison = 3 mois (voir aussi
## SeasonSystem.gd, dont season_duration_seconds doit rester un multiple
## exact de cette valeur pour que jour/mois/saison restent synchronises).

@export var cycle_duration_seconds: float = 120.0

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
# Sprint 48 (2026-07-04, "le ciel est bleu, mais il y a un mur marron a la
# base" - visible seulement maintenant que le fog ne recouvre plus le ciel,
# voir Sprint 46/fog_sky_affect) : ProceduralSkyMaterial a un dégradé "sol"
# separe du degrade "ciel", visible sous la ligne d'horizon des que la camera
# regarde meme legerement vers le bas (le cas la plupart du temps avec une
# carte plate vue en plongee) - les anciennes couleurs (brun/terre) creaient
# un "mur" net et disgracieux la ou il rencontre le sol du ciel. Fix : le
# degrade sol REPREND desormais la couleur d'horizon du ciel (GROUND_HORIZON
# = SKY_HORIZON) pour une jonction invisible, et GROUND_BOTTOM n'est plus
# qu'une version assombrie de cette meme teinte (plus de brun distinct).
const GROUND_BOTTOM := [
	Color(0.6, 0.45, 0.4),
	Color(0.45, 0.5, 0.55),
	Color(0.35, 0.15, 0.1),
	Color(0.03, 0.03, 0.05),
]
const GROUND_HORIZON := [
	Color(1.0, 0.75, 0.65),
	Color(0.75, 0.82, 0.9),
	Color(0.65, 0.25, 0.15),
	Color(0.08, 0.08, 0.12),
]
const LIGHT_COLOR := [
	Color(1.0, 0.75, 0.7),
	Color(1.0, 1.0, 1.0),
	Color(0.9, 0.35, 0.25),
	Color(0.3, 0.35, 0.5),
]
## Nuit = 0.0 pile (pas juste "tres faible") : Francois veut qu'il n'y ait
## plus DU TOUT de lumiere sur la carte la nuit.
## Sprint 37 (backlog Phase 1 item 15, 2026-07-04) : Matin/Jour/Soir remontes
## (jugee "un peu sombre dans la journee") - Nuit INCHANGE (reste 0.0, demande
## explicite ci-dessus, ne pas y toucher).
## Sprint 37quaterdecies (2026-07-04, meme plainte persistante : "l'herbe et
## l'eau ont toujours des couleurs trop sombres") : le passage a un materiau
## REELEMENT eclaire (roughness=1.0, voir VoxelWorld._make_material) attenue
## la couleur de base par rapport a un rendu "unshaded" (perte d'energie du
## calcul de diffusion, meme a light_energy=1.0 la couleur affichee est plus
## sombre que l'albedo brut) - remonte encore Matin/Jour/Soir (Nuit INCHANGE,
## voir ci-dessus) pour compenser, en plus de l'eclaircissement direct des
## couleurs (voir ClimateDefinitions.gd / VoxelWorld.WATER_COLOR).
## Sprint 37octodecies (2026-07-04, apres 3 corrections de couleur infructueuses
## - "ça fait 3 fois que je demande") : nouveau diagnostic, cette fois sur la
## GEOMETRIE de l'eclairage, pas juste la couleur. L'herbe et l'eau sont des
## faces PLATES horizontales (normale = tout droit vers le haut) : leur
## eclairage direct depend entierement de l'angle du soleil (DirectionalLight3D,
## voir _solar_phase) - des que le soleil n'est pas pile au zenith (donc la
## plupart de la journee), le produit scalaire normale/lumiere chute et ces
## faces s'assombrissent fortement, MEME avec un albedo clair. Les cimes
## d'arbres (spheres/cones) ont des normales dans toutes les directions : une
## bonne partie de leur surface reste bien orientee vers le soleil quel que
## soit son angle, donc elles restent toujours bien eclairees - d'ou l'ecart
## observe (sol/eau trop sombres, arbres trop clairs) qu'aucun reglage de
## couleur ne pouvait corriger. Fix : LIGHT_ENERGY (direct, depend de l'angle)
## LEGEREMENT reduit, AMBIENT_ENERGY (uniforme, independant de l'angle des
## faces) fortement augmente - le sol/l'eau dependent desormais surtout de
## l'ambiant (toujours present, quel que soit le moment de la journee) plutot
## que du soleil direct. Nuit INCHANGE (reste 0.0, regle explicite ci-dessus).
## Sprint 37vicies (2026-07-04, "ça a marché mais il y a trop de lumiere
## generale") : maintenant que l'ambiant fonctionne reellement (voir
## AMBIENT_COLOR/ambient_light_source plus bas), Matin/Jour/Soir redescendus
## un peu (Nuit INCHANGE, comme toujours).
## Sprint 37duovicies (2026-07-04, meme retour : "encore trop lumineux") :
## nouvelle baisse.
## Sprint 39 (2026-07-04, "c'est très bien, il y a encore trop de luminosité") :
## 3e baisse (meme facteur ~0.85 que les 2 precedentes). Nuit INCHANGE.
const LIGHT_ENERGY := [0.68, 0.89, 0.58, 0.0]
## 2026-07-02 : la lumiere ambiante (WorldEnvironment.environment.
## ambient_light_energy, source = ciel) n'etait jusqu'ici jamais touchee par
## ce script - meme avec light_energy quasi nul la nuit, l'ambiant restait a
## sa valeur par defaut (1.0) et continuait a eclairer legerement toute la
## carte. On la fait maintenant varier avec les memes phases, pour une nuit
## vraiment sombre (voir aussi VoxelWorld._make_material / Forest.
## _flat_material qui, jusqu'a ce sprint, ignoraient totalement l'eclairage -
## SHADING_MODE_UNSHADED - ce qui empechait aussi bien l'ombre que
## l'assombrissement nocturne de fonctionner).
## Sprint 37octodecies : voir commentaire LIGHT_ENERGY ci-dessus - l'ambiant
## devient la source dominante de luminosite en journee (superieure a
## LIGHT_ENERGY), justement parce qu'il n'est PAS affecte par l'angle des
## faces (contrairement au direct) : c'est ce qui doit stabiliser la
## luminosite du sol/de l'eau quelle que soit l'heure de la journee.
const AMBIENT_ENERGY := [0.77, 1.06, 0.64, 0.0]  # Sprint 39 : 3e baisse (voir commentaire LIGHT_ENERGY), meme facteur ~0.85
## Sprint 37novodecies (2026-07-04, "revois une fois pour toutes le code" -
## apres plusieurs correctifs de couleur infructueux meme "a midi") : cause
## racine enfin identifiee - Main.tscn avait `ambient_light_source = 3`
## (AMBIENT_SOURCE_SKY). Avec ce mode, la lumiere ambiante ne vient PAS
## directement des couleurs qu'on assigne a sky_top_color/sky_horizon_color
## chaque frame : Godot calcule l'ambiant a partir d'une sonde de
## rayonnement (irradiance probe) DERIVEE du ciel, qui n'est pas garantie de
## se rafraichir instantanement/completement a chaque frame (surtout avec un
## cycle jour/nuit de 2 MINUTES qui change le ciel tres vite) - l'ambiant
## utilise pouvait donc rester "en retard"/errone sur ce que le ciel affiche
## reellement a l'instant t, quelle que soit l'heure. Cote sol/eau (qui,
## depuis le correctif precedent, dependent surtout de l'ambiant - voir
## LIGHT_ENERGY/AMBIENT_ENERGY ci-dessus), ca expliquait un assombrissement
## qui ne repondait a AUCUN reglage de couleur ni d'heure. Fix : Main.tscn
## passe a `ambient_light_source = 2` (AMBIENT_SOURCE_COLOR) - l'ambiant vient
## desormais d'une simple Color assignee directement par ce script chaque
## frame (AMBIENT_COLOR ci-dessous), sans intermediaire/sonde/latence
## possible. Root cause plus probable que les hypotheses precedentes
## (ratio de couleur, angle du soleil) car elle explique un assombrissement
## qui ne bougeait PAS avec l'heure (le probleme signale explicitement).
const AMBIENT_COLOR := [
	Color(0.85, 0.75, 0.75),
	Color(0.65, 0.78, 0.95),  # Jour : ciel bleu clair
	Color(0.55, 0.35, 0.35),
	Color(0.15, 0.17, 0.25),
]
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

## Sprint 37terdecies (2026-07-04, valeurs demandees explicitement par
## Francois) : heure de lever/coucher au SOLSTICE d'ete (6h-22h) et au
## SOLSTICE d'hiver (8h-20h) ; printemps/automne (equinoxes) a mi-chemin
## (7h-21h). Utilisees par is_daytime()/_day_color_blend() (couleurs/energie)
## ET par _solar_phase() (rotation du soleil, purement visuelle).
const SUNRISE_HOUR := {
	"ete": 6.0,
	"printemps": 7.0,
	"automne": 7.0,
	"hiver": 8.0,
}
const SUNSET_HOUR := {
	"ete": 22.0,
	"printemps": 21.0,
	"automne": 21.0,
	"hiver": 20.0,
}

## Sprint 37terdecies (2026-07-04, bug signale par Francois : "il fait jour a
## 3h du matin") : largeur (fraction du cycle 0-1) de la transition aube/
## crepuscule - environ 36 minutes de part et d'autre du lever/coucher exact.
## Cause du bug : l'ancien systeme etalait la transition Nuit->Matin/Soir->Nuit
## sur un QUART ENTIER de la nuit (proportionnel a sa duree, via _solar_phase),
## donc le ciel commençait a s'eclaircir des heures avant le vrai lever. Le
## nouveau systeme (_day_color_blend) utilise une fenetre de largeur FIXE
## ancree exactement sur SUNRISE_HOUR/SUNSET_HOUR, avec un plateau JOUR/NUIT
## constant en dehors de cette fenetre - la luminosite correspond donc
## precisement aux heures demandees, quelle que soit la duree de la nuit.
const DAWN_DUSK_TRANSITION := 0.025

## Sprint 37novodecies (2026-07-04, demande explicite : "le lancement du jeu
## doit commencer a 7h du matin, pas a minuit") : time_of_day=0.0 correspond
## a l'heure affichee 00h00 (minuit, voir hour = time_of_day*24 dans
## ActionController._process) - la partie demarrait donc en pleine nuit
## (LIGHT_ENERGY/AMBIENT_ENERGY a 0.0). Demarre maintenant a 7.0/24.0 = 7h00.
var time_of_day: float = 7.0 / 24.0
# Sprint 33 : compteur de jours pour l'horloge/calendrier affiche
# (ActionController.gd) - commence a 1 ("Jour 1"), incremente a chaque
# boucle complete du cycle jour/nuit (detectee via le fmod qui revient en
# arriere, voir _process).
var day_count: int = 1

@onready var _light: DirectionalLight3D = %DirectionalLight3D
@onready var _world_environment: WorldEnvironment = %WorldEnvironment
@onready var _moon: MeshInstance3D = %Moon
@onready var _sky_material: ProceduralSkyMaterial = _world_environment.environment.sky.sky_material as ProceduralSkyMaterial
@onready var _moon_material: StandardMaterial3D = _moon.material_override as StandardMaterial3D
# Sprint 37quinquies (2026-07-04, bug signale par Francois : "le cycle diurne
# devrait correspondre a l'heure (lever/coucher du soleil, variance selon les
# saisons)") - avant ce correctif, time_of_day=0.0 etait A LA FOIS affiche
# "00h00" (minuit, voir ActionController._process) ET traite comme l'instant
# du lever du soleil par la formule de rotation ci-dessous (x=0 = horizontale
# montante) - un decalage de 6h entre l'horloge affichee et le soleil reellement
# visible. Voir _season_system/SUNRISE_HOUR/SUNSET_HOUR/_solar_phase plus bas.
@onready var _season_system: Node = %SeasonSystem

## Sprint 34ter (2026-07-03) : mesure de duree de chargement - ce script est
## le premier avec code a s'executer dans Main.tscn (voir l'ordre des noeuds),
## donc le meilleur point de depart pour mesurer tout le temps passe DANS la
## scene (n'inclut PAS le temps de demarrage de Godot lui-meme avant que la
## scene ne commence a s'instancier, qui n'est pas mesurable en GDScript).
## Lu par GroundDecoration.gd (fin de la generation du monde) et
## CharacterSheetUI.gd (dernier script a finir, fin du chargement complet).
static var scene_start_ms: int = 0

## Sprint 37 (backlog Phase 1 item 8) : multiplicateur de vitesse du temps de
## jeu, pilote par les boutons Pause/x1/x2/x4 de ActionController.gd. "static"
## (comme scene_start_ms ci-dessus) pour etre lu/ecrit depuis n'importe quel
## script sans reference d'instance - voir SeasonSystem.gd/WeatherSystem.gd/
## TemperatureSystem.gd (multiplient leurs propres minuteurs) et Dwarf.gd
## (multiplie directement son delta en tete de _process, ce qui met en pause/
## accelere d'un coup deplacement, besoins et travail). Sciemment PAS applique
## a CameraRig.gd : la camera doit rester utilisable meme en pause.
static var game_speed: float = 1.0


func _ready() -> void:
	scene_start_ms = Time.get_ticks_msec()


func _process(delta: float) -> void:
	var previous_time_of_day := time_of_day
	time_of_day = fmod(time_of_day + (delta * game_speed) / cycle_duration_seconds, 1.0)
	if time_of_day < previous_time_of_day:
		day_count += 1

	var sunrise: float = _sunrise_fraction()
	var sunset: float = _sunset_fraction()

	# Sprint 37terdecies : couleurs/energie pilotees par une fenetre de
	# transition de largeur FIXE ancree sur le lever/coucher exact (voir
	# _day_color_blend) - remplace l'ancien systeme proportionnel a la duree
	# de la nuit qui faisait "entrer le jour" bien trop tot.
	var blend: Array = _day_color_blend(time_of_day, sunrise, sunset)
	var idx0: int = blend[0]
	var idx1: int = blend[1]
	var t: float = blend[2]

	# La rotation du soleil (purement visuelle - direction des ombres, pas de
	# disque solaire visible) continue d'utiliser _solar_phase() : un balayage
	# continu sur tout le cycle, decouple du plateau jour/nuit ci-dessus.
	var w: float = _solar_phase(time_of_day, sunrise, sunset)

	_sky_material.sky_top_color = SKY_TOP[idx0].lerp(SKY_TOP[idx1], t)
	_sky_material.sky_horizon_color = SKY_HORIZON[idx0].lerp(SKY_HORIZON[idx1], t)
	_sky_material.ground_bottom_color = GROUND_BOTTOM[idx0].lerp(GROUND_BOTTOM[idx1], t)
	_sky_material.ground_horizon_color = GROUND_HORIZON[idx0].lerp(GROUND_HORIZON[idx1], t)

	_light.light_color = LIGHT_COLOR[idx0].lerp(LIGHT_COLOR[idx1], t)
	_light.light_energy = lerp(LIGHT_ENERGY[idx0], LIGHT_ENERGY[idx1], t)
	# Rotation continue (voir commentaire de SUN_YAW_DEGREES) : basee sur "w"
	# (et non plus time_of_day directement) pour que le soleil soit reellement
	# horizontal (lever/coucher) aux heures de lever/coucher de la saison
	# courante, pas toujours a 00h00/12h00.
	_light.rotation_degrees = Vector3(-360.0 * w, SUN_YAW_DEGREES, 0.0)

	_world_environment.environment.ambient_light_energy = lerp(AMBIENT_ENERGY[idx0], AMBIENT_ENERGY[idx1], t)
	# Sprint 37novodecies : ambient_light_color pilote desormais reellement
	# l'ambiant (ambient_light_source = 2 = AMBIENT_SOURCE_COLOR dans
	# Main.tscn) - voir le commentaire de AMBIENT_COLOR plus haut pour la
	# raison (l'ancien mode SKY ne se rafraichissait pas de facon fiable).
	_world_environment.environment.ambient_light_color = AMBIENT_COLOR[idx0].lerp(AMBIENT_COLOR[idx1], t)
	_world_environment.environment.fog_light_color = FOG_COLOR[idx0].lerp(FOG_COLOR[idx1], t)

	var moon_alpha: float = lerp(MOON_ALPHA[idx0], MOON_ALPHA[idx1], t)
	_moon.visible = moon_alpha > 0.01
	if _moon_material:
		_moon_material.albedo_color.a = moon_alpha


## Sprint 37quinquies : heure de lever/coucher (0-24) pour la saison courante -
## repli sur "ete" si la saison est introuvable (ne devrait pas arriver).
func _sunrise_fraction() -> float:
	var season_id: String = _season_system.current_season_id() if _season_system else "ete"
	var hour: float = SUNRISE_HOUR.get(season_id, SUNRISE_HOUR["ete"])
	return hour / 24.0


func _sunset_fraction() -> float:
	var season_id: String = _season_system.current_season_id() if _season_system else "ete"
	var hour: float = SUNSET_HOUR.get(season_id, SUNSET_HOUR["ete"])
	return hour / 24.0


## Sprint 37quinquies : deforme time_of_day (horloge lineaire 0-1) en une
## "phase solaire" 0-1, ou 0/0.5 tombent EXACTEMENT au lever/coucher de la
## saison courante. La portion "du lever au coucher" (le jour) est etiree ou
## compressee sur la premiere moitie (0-0.5), la portion "du coucher au lever
## suivant" (la nuit) sur la seconde moitie (0.5-1.0) - c'est ce qui fait qu'un
## jour plus long (ete) "dilate" la premiere moitie de la rotation du soleil
## (il se deplace plus lentement dans le ciel, visible plus longtemps) sans
## jamais casser la continuite de la rotation (pas de saut d'un cycle a
## l'autre). Sprint 37terdecies : ne pilote plus QUE la rotation (purement
## visuelle) - les couleurs/l'energie lumineuse utilisent desormais
## _day_color_blend() ci-dessous (fenetre de transition a largeur fixe,
## corrige le bug "jour a 3h du matin").
func _solar_phase(t: float, sunrise: float, sunset: float) -> float:
	var day_len: float = clampf(sunset - sunrise, 0.1, 0.9)
	var night_len: float = 1.0 - day_len
	var rel: float = fmod(t - sunrise + 1.0, 1.0)
	if rel < day_len:
		return (rel / day_len) * 0.5
	return 0.5 + ((rel - day_len) / night_len) * 0.5


## Sprint 37terdecies : determine les 2 keyframes a interpoler (indices dans
## SKY_TOP/LIGHT_COLOR/etc, 0=Matin/1=Jour/2=Soir/3=Nuit) et le facteur de
## melange, a partir d'une fenetre de transition de largeur FIXE
## (DAWN_DUSK_TRANSITION) ancree exactement sur le lever/coucher de la saison
## courante - PAS proportionnelle a la duree de la nuit (voir le bug corrige
## en tete de fichier). En dehors des fenetres aube/crepuscule, un plateau
## Jour ou Nuit constant est maintenu.
func _day_color_blend(t: float, sunrise: float, sunset: float) -> Array:
	var dawn_start: float = sunrise - DAWN_DUSK_TRANSITION
	var dawn_end: float = sunrise + DAWN_DUSK_TRANSITION
	var dusk_start: float = sunset - DAWN_DUSK_TRANSITION
	var dusk_end: float = sunset + DAWN_DUSK_TRANSITION

	if t < dawn_start or t >= dusk_end:
		return [3, 3, 0.0]  # Nuit, plateau constant
	if t < sunrise:
		return [3, 0, (t - dawn_start) / (sunrise - dawn_start)]  # Nuit -> Matin
	if t < dawn_end:
		return [0, 1, (t - sunrise) / (dawn_end - sunrise)]  # Matin -> Jour
	if t < dusk_start:
		return [1, 1, 0.0]  # Jour, plateau constant
	if t < sunset:
		return [1, 2, (t - dusk_start) / (sunset - dusk_start)]  # Jour -> Soir
	return [2, 3, (t - sunset) / (dusk_end - sunset)]  # Soir -> Nuit


## Sprint 37quinquies : utilise par ActionController.gd pour la pastille
## jour/nuit (remplace l'ancienne verification "time_of_day < 0.5" qui
## supposait toujours un jour de 12h pile).
func is_daytime() -> bool:
	var sunrise: float = _sunrise_fraction()
	var sunset: float = _sunset_fraction()
	var rel: float = fmod(time_of_day - sunrise + 1.0, 1.0)
	return rel < (sunset - sunrise)
