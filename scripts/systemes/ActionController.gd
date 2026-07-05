extends CanvasLayer
## Sprint 4 : menu d'actions (Miner / Couper) + designation a la souris.
## Sprint 7 : ajoute Mur Bois / Mur Pierre (construction).
## Sprint 9 : icones de couleur sur les boutons.
## Sprint 9bis : refonte du menu (Construire > materiau), selection de
## plusieurs cases de mur par cliquer-glisser, et mur "fantome" semi-
## transparent tant que la construction n'est pas terminee.
## Sprint 11 : plusieurs nains simultanes (groupe "dwarves" au lieu d'un
## %Dwarf unique) ; chaque nain signale la fin de ses propres constructions.
## Sprint 24ter : ajoute le mode CUEILLIR (recolte de fruits/baies sans
## abattre l'arbre/buisson, cible = groupe "cueillette", voir Forest.gd/
## BerryBushes.gd/TaskQueue.gd/Dwarf.gd).
## Sprint 25 : ajoute "Inspecter" - quand aucun mode d'action n'est actif, un
## clic gauche affiche une petite fenetre d'info sur l'objet clique (arbre,
## buisson/plante, terre, pierre, filon, mur), sans creer de tache. Pas un
## mode a part entiere (pas de bouton dedie) : c'est le comportement par
## defaut du clic quand Mode.NONE.
## Sprint 26 : une icone temporaire apparait sur l'objet/la case designe(e)
## pour Miner/Couper/Cueillir, et disparait une fois la tache terminee - meme
## principe que le mur "fantome" de Construire, generalise a toutes les
## taches via le nouveau signal Dwarf.task_finished (voir _spawn_task_marker/
## _on_task_finished).
## Sprint 26bis : l'icone n'est plus un simple carre colore mais une forme
## d'outil reconnaissable (pioche/hache/panier selon le mode), dessinee
## pixel par pixel a l'execution (voir _get_icon_texture et les fonctions
## _draw_*_icon), toujours dans la couleur du bouton du mode correspondant.
## Sprint 29 : selection multiple de nains par rectangle (glisser-clic),
## uniquement quand aucun mode d'action n'est actif (comme Inspecter). Un
## clic simple (sans glisser reel) continue de declencher Inspecter, comme
## avant ; un glisser au-dela de SELECT_DRAG_THRESHOLD pixels dessine un
## rectangle de selection a l'ecran et, au relachement, transmet a
## CharacterSheetUI.set_map_selection() tous les nains dont la position
## projetee a l'ecran tombe dans le rectangle. Ctrl/Maj enfonce au
## relachement = ajoute a la selection existante au lieu de la remplacer
## (meme convention que Ctrl/Maj+clic sur un portrait de la fiche).
## Sprint 35ter (2026-07-03, demande explicite) : deux changements de
## comportement pour Miner/Couper/Cueillir/Construire -
## (1) Miner peut desormais designer plusieurs cases d'un coup par
## cliquer-glisser (meme mecanique de rectangle "monde" que Construire, voir
## _valid_mine_rect_cells/_update_mine_drag_preview/_finalize_mine_selection) ;
## Couper/Cueillir peuvent desormais designer plusieurs arbres/buissons d'un
## coup par cliquer-glisser (meme mecanique de rectangle "ecran" que la
## selection de nains ci-dessus, voir _targets_in_screen_rect/
## _finalize_chop_selection/_finalize_gather_selection) - un clic simple (sans
## glisser reel) continue de cibler un seul objet, comme avant.
## (2) Les 4 modes (Miner/Couper/Cueillir/Construire) reviennent desormais
## automatiquement a Mode.NONE apres CHAQUE designation/selection (clic simple
## OU glisser) - avant, le mode restait actif jusqu'a un reclic manuel sur le
## bouton, ce qui pretait a confusion ("le bouton reste enfonce indefiniment").
## Sprint 36 (2026-07-03) : ajoute le mode PUISER (recolte d'eau, voir
## VoxelWorld.is_water/TaskQueue.add_puiser_task/Dwarf.gd "puiser") - reutilise
## exactement la meme mecanique de rectangle "monde" que Miner (voir
## _valid_puiser_rect_cells/_update_puiser_drag_preview/_finalize_puiser_selection),
## la seule vraie difference etant le filtre (case d'eau au lieu de case
## minable) et le fait qu'aucun bloc n'est retire a la fin. Miner exclut
## desormais l'eau de sa propre selection (l'eau se puise, ne se mine pas).

const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
## Sprint 33 (calendrier) : pour lire DAYS_PER_MONTH/MONTHS_PER_SEASON sans
## dupliquer ces valeurs en dur ici (season_system est type "Node" generique
## via %SeasonSystem, donc ses constantes ne sont pas visibles directement).
const SeasonSystemScript := preload("res://scripts/systemes/SeasonSystem.gd")
## Sprint 37 (backlog Phase 1 item 8) : pour lire/ecrire DayNightCycleScript.game_speed
## (pause/x1/x2/x4).
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")
## 2026-07-05 (revue de code, item F010) : uniquement pour le garde-fou de
## _ready() ci-dessous (GRID_WIDTH/GRID_DEPTH dupliques en dur ci-dessous).
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")
## 2026-07-05 (revue de code, dette d'architecture A1 : separation
## presentation/regles) : validation des cases cibles (Construire/Miner/
## Puiser) extraite dans ActionValidator.gd - voir _valid_rect_cells/
## _valid_mine_rect_cells/_valid_puiser_rect_cells ci-dessous, desormais de
## simples delegations (aucun changement de comportement/API interne).
const ActionValidatorScript := preload("res://scripts/systemes/ActionValidator.gd")
var action_validator: ActionValidatorScript = ActionValidatorScript.new()

## 2026-07-05 (revue de code, dette d'architecture A1, etape suivante) : tout
## le dessin pixel par pixel des icones (marqueurs de tache, climat,
## pause/vitesse, boutons d'action) extrait dans IconRenderer.gd - voir
## _get_icon_texture/_get_time_icon_texture/_make_sun_moon_icon/
## _make_weather_icon/_make_square_icon ci-dessous, desormais de simples
## delegations (aucun changement de comportement/API interne).
const IconRendererScript := preload("res://scripts/systemes/IconRenderer.gd")
var icon_renderer: IconRendererScript = IconRendererScript.new()

enum Mode { NONE, MINER, COUPER, CONSTRUIRE, CUEILLIR, PUISER }
var current_mode: int = Mode.NONE
var selected_material: String = ""  # "bois" / "pierre" / "terre" en mode CONSTRUIRE

const GRID_WIDTH := 100  # 2026-07-03 : map resize (etait 20)
const GRID_DEPTH := 100  # 2026-07-03 : map resize (etait 20)
# Sprint 24quinquies : corrige - etait reste a 10.0 (hauteur de carte d'avant
# le Sprint 23, qui l'a portee a 30). Comme la camera regarde le sol en angle,
# une mauvaise hauteur de plan decale aussi x/z du point clique, pas seulement
# y - ca ratait systematiquement les cibles rares ("Cueillir"), et decalait
# probablement aussi (de facon moins visible) miner/couper/construire.
const GROUND_LEVEL := 50.0  # 2026-07-03 : map resize (etait 30.0)

# Sprint 26bis : taille (en pixels) des icones d'outil dessinees a l'execution
# pour les marqueurs de tache (voir _get_icon_texture)
# 2026-07-05 (demande explicite Francois, icones jugees "moches et pas
# lisibles") : agrandie (20 -> 40) et le glyphe (pioche/hache/panier) est
# maintenant dessine plus petit qu'avant (voir ICON_GLYPH_SIZE) puis incruste
# au centre d'un badge rond jaune, pour un meilleur contraste sur n'importe
# quel decor et une forme reconnaissable de loin.
const ICON_SIZE := 40
const ICON_GLYPH_SIZE := 24

## Sprint 37quindecies (2026-07-04, demande explicite : "remplacer les boutons
## pause x1 x2 x4 par des icones") : taille/couleur des icones de controle du
## temps (voir _get_time_icon_texture/_draw_pause_icon/_draw_speed_icon), et
## raccourcis clavier associes (Espace=pause, F1=x1, F2=x2, F3=x4), valables
## quel que soit le mode d'action courant (voir _unhandled_input).
const TIME_ICON_SIZE := 24
const TIME_ICON_COLOR := Color(0.92, 0.92, 0.95)

# Sprint 37 (backlog Phase 1 item 9) : rayon (en pixels ecran) de detection
# d'un nain au clic/survol direct sur son modele - voir _dwarf_at_screen_pos.
const DWARF_CLICK_RADIUS_PX := 28.0

@onready var btn_miner: Button = $HBox/MinerButton
@onready var btn_couper: Button = $HBox/CouperButton
@onready var btn_construire: Button = $HBox/ConstruireButton
@onready var btn_cueillir: Button = $HBox/CueillirButton
@onready var btn_puiser: Button = $HBox/PuiserButton
@onready var material_box: HBoxContainer = $MaterialBox
@onready var btn_bois: Button = $MaterialBox/BoisButton
@onready var btn_pierre: Button = $MaterialBox/PierreButton
@onready var btn_terre: Button = $MaterialBox/TerreButton
@onready var stats_label: Label = $StatsLabel
@onready var time_label: Label = $TimeLabel
@onready var info_panel: PanelContainer = $InfoPanel
@onready var info_label: Label = $InfoPanel/VBox/InfoLabel
@onready var info_close_button: Button = $InfoPanel/VBox/CloseButton

@onready var voxel_world: Node3D = %VoxelWorld
@onready var task_queue: Node = %TaskQueue
@onready var camera: Camera3D = %Camera3D
@onready var inventory: Node = %Inventory
@onready var character_sheet_ui: CanvasLayer = %CharacterSheetUI
@onready var day_night_cycle: Node = %DayNightCycle
@onready var season_system: Node = %SeasonSystem
@onready var weather_system: Node = %WeatherSystem
@onready var temperature_system: Node = %TemperatureSystem

# Sprint 37nonies (2026-07-04, remplace les 3 pastilles de couleur - signale
# par Francois : "je ne comprends pas la signification des carres de
# couleurs") : un bandeau "heure" (0h-24h, degrade jour/nuit selon la saison,
# icone soleil/lune qui se deplace + marqueur de l'heure actuelle), un
# bandeau "saison" (degrade 4 couleurs avec marqueur de progression), et une
# icone meteo dessinee (voir _make_weather_icon). Construits dans
# _setup_climate_icons, mis a jour chaque frame dans _process - complement
# graphique au texte de time_label (pas un remplacement total : le texte
# reste plus precis/lisible).
# Sprint 37decies (2026-07-04, demande explicite : "les differentes barres
# doivent etre beaucoup plus grosses (x2 en hauteur, x4 en largeur) ainsi que
# l'icone de climat") : tailles x2/x4 par rapport a la version initiale
# (200x20 / 200x12 / icone 28).
const HOUR_BAND_SIZE := Vector2(800.0, 40.0)
# Sprint 37undecies (2026-07-04, demande explicite : "elargir en hauteur la
# barre des saisons et mettre un texte") : hauteur x2 (24 -> 48) pour laisser
# la place au texte Printemps/Ete/Automne/Hiver (voir _setup_season_labels).
const SEASON_BAND_SIZE := Vector2(800.0, 48.0)
# Sprint 37undecies : agrandi pour s'aligner avec la nouvelle hauteur du
# bandeau saison (etait 56, base sur l'ancienne hauteur x2 generique).
# Sprint 47 (2026-07-04, demande explicite : "agrandir l'icone de climat") :
# encore agrandie (etait 48).
const CLIMATE_ICON_SIZE := 72
const SUN_MOON_ICON_SIZE := 28.0

var _hour_band: Control
var _hour_band_bg: TextureRect
var _hour_marker: ColorRect
var _sun_moon_icon: TextureRect
var _season_band: Control
var _season_band_bg: TextureRect
var _season_marker: ColorRect
var _weather_icon_wrap: Control
var _weather_icon_rect: TextureRect

# Caches pour eviter de reconstruire une texture a chaque frame (seulement
# quand la valeur affichee change reellement).
var _hour_band_season_cache: String = ""
var _sun_moon_is_day_cache: bool = false
var _sun_moon_icon_built: bool = false
var _weather_icon_cache: String = ""

# Sprint 37 (backlog Phase 1 item 8) : boutons Pause/x1/x2/x4, construits dans
# _setup_time_controls - pilotent DayNightCycleScript.game_speed (lu par
# Dwarf.gd/SeasonSystem.gd/WeatherSystem.gd/TemperatureSystem.gd), jamais par
# CameraRig.gd (la camera doit rester utilisable meme en pause).
var _btn_pause: Button
var _btn_speed1: Button
var _btn_speed2: Button
var _btn_speed4: Button

# 2026-07-05 (demande explicite Francois : "la barre d'espace met en pause,
# il faudrait qu'elle puisse aussi faire repartir a la vitesse qui etait
# selectionnee avant la pause") : memorise la derniere vitesse active (1/2/4)
# juste avant une mise en pause par Espace, pour que Espace fasse desormais
# basculer pause <-> reprise (au lieu de forcer 0.0 a chaque appui) - voir
# _toggle_pause.
var _speed_before_pause: float = 1.0

# Sprint 29 : selection multiple de nains par rectangle (Mode.NONE
# uniquement). Distinct du systeme de glisser du mode CONSTRUIRE ci-dessus
# (is_dragging/drag_start/drag_end, qui travaille en cases de grille, pas en
# coordonnees ecran).
const SELECT_DRAG_THRESHOLD := 6.0  # pixels avant de considerer que c'est un glisser, pas un simple clic
var _select_button_down: bool = false   # vrai entre l'appui et le relachement du clic gauche (Mode.NONE)
var _select_dragging_active: bool = false  # vrai seulement une fois le seuil de glisser depasse
var _select_press_pos: Vector2 = Vector2.ZERO
var _select_box: Panel

# Selection multi-cases par cliquer-glisser (mode CONSTRUIRE uniquement)
var is_dragging: bool = false
var drag_start: Vector2i = Vector2i.ZERO
var drag_end: Vector2i = Vector2i.ZERO
var drag_preview_ghosts: Array = []

# Murs "fantome" (semi-transparents) affiches tant que la construction
# n'est pas terminee (que ce soit un succes ou un echec faute de ressource)
var queued_ghosts: Dictionary = {}     # task_id -> MeshInstance3D
var pending_columns: Dictionary = {}   # Vector2i(x,z) -> true

# Sprint 26 : icones temporaires sur les objets/cases designes pour Miner/
# Couper/Cueillir, retirees des que Dwarf.task_finished signale la fin de
# la tache correspondante (voir _spawn_task_marker/_on_task_finished)
var queued_markers: Dictionary = {}    # task_id -> MeshInstance3D
# 2026-07-05 (dette A1) : cache des textures d'icones deplace dans
# IconRenderer.gd (_icon_texture_cache/_time_icon_cache).


func _ready() -> void:
	# 2026-07-05 (revue de code, item F010) : GRID_WIDTH/GRID_DEPTH dupliques
	# en dur (aucune garde-fou automatique auparavant) - avertissement si
	# desynchronise de VoxelWorld.gd, sans changer le comportement.
	if GRID_WIDTH != VoxelWorldScript.WIDTH or GRID_DEPTH != VoxelWorldScript.DEPTH:
		push_warning("ActionController.GRID_WIDTH/GRID_DEPTH (%d/%d) desynchronise de VoxelWorld.WIDTH/DEPTH (%d/%d)" % [GRID_WIDTH, GRID_DEPTH, VoxelWorldScript.WIDTH, VoxelWorldScript.DEPTH])
	btn_miner.pressed.connect(_on_miner_pressed)
	btn_couper.pressed.connect(_on_couper_pressed)
	btn_construire.pressed.connect(_on_construire_pressed)
	btn_cueillir.pressed.connect(_on_cueillir_pressed)
	btn_puiser.pressed.connect(_on_puiser_pressed)
	btn_bois.pressed.connect(_on_material_pressed.bind("bois"))
	btn_pierre.pressed.connect(_on_material_pressed.bind("pierre"))
	btn_terre.pressed.connect(_on_material_pressed.bind("terre"))
	# 2026-07-05 (meme correctif que _make_time_button) : evite que ces
	# boutons gardent le focus clavier et soient reactives par megarde par
	# Espace/Entree ("ui_accept").
	for b in [btn_miner, btn_couper, btn_construire, btn_cueillir, btn_puiser, btn_bois, btn_pierre, btn_terre]:
		b.focus_mode = Control.FOCUS_NONE
	for d in get_tree().get_nodes_in_group("dwarves"):
		d.build_task_finished.connect(_on_build_task_finished)
		d.task_finished.connect(_on_task_finished)
	_setup_icons()
	_update_buttons()
	_update_material_buttons()
	material_box.visible = false
	_setup_select_box()
	_setup_climate_icons()
	_setup_time_controls()
	# Sprint 37 (backlog Phase 1 item 12) : "transformation du clic+panneau...
	# par un panneau standard en bas a droite qui affiche les proprietes en
	# mouse over" - le panneau d'inspection (Sprint 25) devient permanent,
	# repositionne en bas a droite (voir Main.tscn), mis a jour en continu par
	# survol dans _process au lieu d'apparaitre/disparaitre au clic. Le bouton
	# "Fermer" n'a plus lieu d'etre (le panneau ne se ferme plus), mais le
	# noeud reste dans la scene (repli le plus simple/sur, pas de retouche de
	# structure de Main.tscn au-dela du repositionnement).
	info_close_button.visible = false
	info_panel.visible = true
	info_label.text = "Survolez un element de la carte..."


## Sprint 29 : rectangle de selection affiche pendant un glisser-clic en
## Mode.NONE (voir _update_select_drag). Simple Panel + StyleBoxFlat (fond
## bleu tres transparent + bordure), cree une seule fois et repositionne/
## redimensionne a chaque frame de glisser plutot que recree.
func _setup_select_box() -> void:
	_select_box = Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.6, 1.0, 0.15)
	style.border_color = Color(0.45, 0.75, 1.0, 0.9)
	style.set_border_width_all(1)
	_select_box.add_theme_stylebox_override("panel", style)
	_select_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_select_box.visible = false
	add_child(_select_box)


## Sprint 37nonies (2026-07-04) : remplace les 3 pastilles de couleur par un
## bandeau "heure" + un bandeau "saison" (empiles verticalement) et une icone
## meteo a cote - voir le bloc de commentaire au niveau des `var` ci-dessus
## pour le detail de ce que represente chaque element. Les degrades de fond
## (TextureRect + GradientTexture2D) et les icones (Image dessinee pixel par
## pixel, meme technique deja utilisee pour les marqueurs de tache - voir
## _get_icon_texture - donc sans risque de reproduire le bug de blocs blancs
## d'une texture d'atlas) sont construits/reconstruits au besoin dans _process.
func _setup_climate_icons() -> void:
	var outer := HBoxContainer.new()
	outer.anchor_left = 0.5
	outer.anchor_right = 0.5
	outer.offset_left = -433.0
	outer.offset_right = 433.0
	outer.offset_top = 50.0
	outer.offset_bottom = 146.0
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)

	var bands_col := VBoxContainer.new()
	bands_col.add_theme_constant_override("separation", 3)
	bands_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outer.add_child(bands_col)

	_hour_band = _make_band_control(bands_col, HOUR_BAND_SIZE)
	_hour_band_bg = _make_band_background(_hour_band)
	_hour_marker = _make_band_marker(_hour_band, HOUR_BAND_SIZE.y)
	_sun_moon_icon = TextureRect.new()
	_sun_moon_icon.custom_minimum_size = Vector2(SUN_MOON_ICON_SIZE, SUN_MOON_ICON_SIZE)
	_sun_moon_icon.size = Vector2(SUN_MOON_ICON_SIZE, SUN_MOON_ICON_SIZE)
	_hour_band.add_child(_sun_moon_icon)

	_season_band = _make_band_control(bands_col, SEASON_BAND_SIZE)
	_season_band_bg = _make_band_background(_season_band)
	_season_band_bg.texture = _build_season_gradient_texture()
	_setup_season_labels(_season_band)
	_season_marker = _make_band_marker(_season_band, SEASON_BAND_SIZE.y)

	# Sprint 37undecies (2026-07-04, demande explicite : "mettre un fond a
	# l'icone de climat et l'agrandir") : panneau arrondi semi-transparent
	# derriere l'icone meteo, pour qu'elle reste lisible quelle que soit la
	# couleur du fond de l'interface (ex : icone blanche "Neige").
	var wrap_size: float = CLIMATE_ICON_SIZE + 14.0
	_weather_icon_wrap = Control.new()
	_weather_icon_wrap.custom_minimum_size = Vector2(wrap_size, wrap_size)
	_weather_icon_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outer.add_child(_weather_icon_wrap)

	var bg_panel := Panel.new()
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.10, 0.16, 0.6)
	bg_style.set_corner_radius_all(8)
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	bg_panel.anchor_right = 1.0
	bg_panel.anchor_bottom = 1.0
	_weather_icon_wrap.add_child(bg_panel)

	_weather_icon_rect = TextureRect.new()
	_weather_icon_rect.custom_minimum_size = Vector2(CLIMATE_ICON_SIZE, CLIMATE_ICON_SIZE)
	var icon_padding: float = (wrap_size - CLIMATE_ICON_SIZE) * 0.5
	_weather_icon_rect.position = Vector2(icon_padding, icon_padding)
	_weather_icon_wrap.add_child(_weather_icon_rect)


## Sprint 37undecies : texte "Printemps"/"Ete"/"Automne"/"Hiver" superpose au
## degrade du bandeau saison, un Label par segment (meme largeur fixe que
## chaque quart du degrade, voir _build_season_gradient_texture). Couleur de
## texte choisie au cas par cas pour rester lisible sur chaque fond (fonds
## clairs = texte fonce, fond automne plus sombre = texte clair).
const SEASON_TEXT_COLORS := {
	"printemps": Color(0.08, 0.28, 0.06),
	"ete": Color(0.35, 0.20, 0.0),
	"automne": Color(1.0, 0.95, 0.85),
	"hiver": Color(0.12, 0.14, 0.22),
}

func _setup_season_labels(parent: Control) -> void:
	var seg_width: float = SEASON_BAND_SIZE.x / float(SEASON_DISPLAY_ORDER.size())
	for i in range(SEASON_DISPLAY_ORDER.size()):
		var season_id: String = SEASON_DISPLAY_ORDER[i]
		var label := Label.new()
		label.text = season_id.capitalize()
		label.add_theme_color_override("font_color", SEASON_TEXT_COLORS.get(season_id, Color.BLACK))
		label.add_theme_font_size_override("font_size", 25)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.position = Vector2(seg_width * i, 0.0)
		label.size = Vector2(seg_width, SEASON_BAND_SIZE.y)
		parent.add_child(label)


## Petit Control de taille fixe servant de conteneur libre (fond degrade +
## marqueur/icone positionnes a la main, voir _process) - un simple
## TextureRect/ColorRect seul ne permettrait pas de superposer plusieurs
## enfants positionnes independamment.
func _make_band_control(parent: Control, size: Vector2) -> Control:
	var control := Control.new()
	control.custom_minimum_size = size
	parent.add_child(control)
	return control


func _make_band_background(parent: Control) -> TextureRect:
	var rect := TextureRect.new()
	rect.anchor_left = 0.0
	rect.anchor_top = 0.0
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	parent.add_child(rect)
	return rect


## Fine ligne verticale servant de "marque pour l'heure/la progression
## actuelle" (demande explicite) - position.x mise a jour chaque frame.
func _make_band_marker(parent: Control, height: float) -> ColorRect:
	var marker := ColorRect.new()
	marker.color = Color(1, 1, 1, 0.95)
	marker.size = Vector2(3.0, height)
	parent.add_child(marker)
	return marker


## Sprint 37nonies : lit directement les dictionnaires publics de
## DayNightCycle.gd (SUNRISE_HOUR/SUNSET_HOUR, par saison) via le script
## preload - meme pattern que DayNightCycleScript.game_speed ailleurs dans
## ce fichier, pas besoin de dupliquer ces heures ici.
func _sunrise_fraction_for(season_id: String) -> float:
	var hour: float = DayNightCycleScript.SUNRISE_HOUR.get(season_id, DayNightCycleScript.SUNRISE_HOUR["ete"])
	return hour / 24.0


func _sunset_fraction_for(season_id: String) -> float:
	var hour: float = DayNightCycleScript.SUNSET_HOUR.get(season_id, DayNightCycleScript.SUNSET_HOUR["ete"])
	return hour / 24.0


## Sprint 37nonies : degrade "nuit -> jour -> nuit" pour le bandeau heure,
## avec le lever/coucher exact de la saison courante (voir DayNightCycle.
## SUNRISE_HOUR/SUNSET_HOUR) - reconstruit uniquement quand la saison change
## (voir _process/_hour_band_season_cache), jamais chaque frame.
## Sprint 37quindecies (2026-07-04, demande explicite de Francois) : la bande
## ne doit plus etre un simple binaire nuit/jour avec un bref fondu, mais une
## vraie progression a 3 teintes : noir (minuit) -> bleu fonce (lever/coucher)
## -> bleu clair (plein midi, exactement a mi-chemin entre lever et coucher)
## -> bleu fonce -> noir. NIGHT_BAND_COLOR devient la couleur de minuit (noir),
## DAY_BAND_COLOR la couleur de plein midi (bleu clair) ; DAWN_DUSK_BAND_COLOR
## (nouveau) est la teinte intermediaire au lever/coucher exact.
## Sprint 37sexdecies (2026-07-04, signale par Francois : "il faut un degrade
## noir vers bleu fonce et est bugue a droite (ca se termine par du blanc")) :
## le fondu NUIT -> BLEU FONCE (juste avant/apres le lever/coucher exact)
## etait beaucoup trop etroit (0.02, ~2-3 texels sur une texture 128px) pour
## etre visible - a l'oeil, la bande passait donc directement du bleu clair
## (jour) au noir sans jamais montrer de bleu fonce, ce qui donnait
## l'impression d'un blanc/bleu clair colle au noir ("bugue"). Elargi a 0.08
## (~2h) pour un vrai degrade visible noir -> bleu fonce -> bleu clair.
const NIGHT_BAND_COLOR := Color(0.03, 0.03, 0.08)
const DAWN_DUSK_BAND_COLOR := Color(0.16, 0.22, 0.48)
const DAY_BAND_COLOR := Color(0.55, 0.78, 0.95)
const HOUR_TRANSITION_FADE := 0.08  # ~2h, degrade nuit->bleu fonce bien visible

func _build_hour_gradient_texture(sunrise_frac: float, sunset_frac: float) -> GradientTexture2D:
	var gradient := Gradient.new()
	# Sprint 47 (2026-07-04, ROOT CAUSE de "toujours blanche a droite", signale
	# a plusieurs reprises malgre les correctifs de largeur de fondu 37quindecies/
	# sexdecies) : Gradient.new() vient AVEC 2 points par defaut deja presents
	# (offset 0.0 et 1.0, dont un blanc) - les appels add_point() ci-dessous
	# AJOUTAIENT nos 7 points a cote de ces 2 points par defaut au lieu de les
	# remplacer, laissant un point blanc residuel qui faussait le degrade pres
	# d'une extremite.
	# Sprint 50 (2026-07-04, CRASH signale par Francois au lancement : "Condition
	# 'points.size() <= 1' is true" dans remove_point()) : un Gradient Godot
	# refuse TOUJOURS de descendre sous 1 point restant - "while
	# get_point_count() > 0: remove_point(0)" tournait donc indefiniment des
	# qu'il ne restait plus qu'1 point (remove_point echoue silencieusement, le
	# compteur ne descend jamais a 0, boucle infinie -> plantage/gel). Fix : on
	# s'arrete a 1 point restant (jamais 0), puis on ECRASE ce dernier point
	# avec nos propres valeurs au lieu d'essayer de le supprimer.
	while gradient.get_point_count() > 1:
		gradient.remove_point(1)
	var fade: float = HOUR_TRANSITION_FADE
	var noon_frac: float = (sunrise_frac + sunset_frac) * 0.5
	var points: Array = [
		[0.0, NIGHT_BAND_COLOR],
		[clampf(sunrise_frac - fade, 0.001, 0.998), NIGHT_BAND_COLOR],
		[clampf(sunrise_frac, 0.002, 0.999), DAWN_DUSK_BAND_COLOR],
		[clampf(noon_frac, 0.003, 0.999), DAY_BAND_COLOR],
		[clampf(sunset_frac, 0.004, 0.999), DAWN_DUSK_BAND_COLOR],
		[clampf(sunset_frac + fade, 0.005, 0.999), NIGHT_BAND_COLOR],
		[1.0, NIGHT_BAND_COLOR],
	]
	# Securite : garantit des offsets strictement croissants (Gradient l'exige) -
	# necessaire si deux saisons ont un lever/coucher tres proches d'une borne.
	# Sprint 50 : le tout premier point ECRASE le point residuel qu'on a du
	# garder ci-dessus (voir commentaire Sprint 50) au lieu d'en ajouter un
	# nouveau - sinon le gradient se retrouverait avec 1 point par defaut EN
	# PLUS de nos 7 points, reproduisant exactement le bug d'origine (Sprint 47).
	var last_offset := -1.0
	var first := true
	for point in points:
		var point_offset: float = maxf(point[0], last_offset + 0.001)
		if first:
			gradient.set_offset(0, point_offset)
			gradient.set_color(0, point[1])
			first = false
		else:
			gradient.add_point(point_offset, point[1])
		last_offset = point_offset

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 8
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


## Sprint 37nonies : degrade fixe (construit une seule fois) pour le bandeau
## saison - ordre d'affichage voulu par Francois : "vert clair printemps vers
## jaune ete vers orange fonce automne vers blanc hiver", boucle sur lui-meme.
const SEASON_DISPLAY_ORDER := ["printemps", "ete", "automne", "hiver"]
const SEASON_BAND_COLORS := {
	"printemps": Color(0.65, 0.9, 0.55),
	"ete": Color(0.95, 0.85, 0.25),
	"automne": Color(0.75, 0.4, 0.1),
	"hiver": Color(0.95, 0.95, 0.98),
}

func _build_season_gradient_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	# Sprint 47 : meme correctif que _build_hour_gradient_texture (voir son
	# commentaire) - vide les points par defaut avant d'ajouter les notres.
	# Sprint 50 (2026-07-04, CRASH signale par Francois : "Condition
	# 'points.size() <= 1' is true" dans remove_point(), meme cause que
	# _build_hour_gradient_texture - voir son commentaire Sprint 50) : on
	# s'arrete a 1 point restant (jamais 0, sinon boucle infinie), et on
	# ECRASE ce point restant avec notre premiere valeur au lieu d'en ajouter
	# un de plus.
	while gradient.get_point_count() > 1:
		gradient.remove_point(1)
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, SEASON_BAND_COLORS["printemps"])
	gradient.add_point(0.25, SEASON_BAND_COLORS["ete"])
	gradient.add_point(0.5, SEASON_BAND_COLORS["automne"])
	gradient.add_point(0.75, SEASON_BAND_COLORS["hiver"])
	gradient.add_point(1.0, SEASON_BAND_COLORS["printemps"])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 8
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


## 2026-07-05 (dette A1) : _fill_circle/_make_sun_moon_icon/_make_weather_icon
## deplaces dans IconRenderer.gd (make_sun_moon_icon/make_weather_icon,
## appeles depuis _process ci-dessous).


## Sprint 37 (backlog Phase 1 item 8) : boutons Pause/x1/x2/x4, pilotent
## DayNightCycleScript.game_speed (lu par Dwarf.gd/SeasonSystem.gd/
## WeatherSystem.gd/TemperatureSystem.gd - jamais par CameraRig.gd, qui doit
## rester utilisable meme en pause).
func _setup_time_controls() -> void:
	var box := HBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -100.0
	box.offset_right = 100.0
	# Sprint 37undecies : decale vers le bas (etait 126/154) - le bandeau saison
	# est maintenant plus haut (texte Printemps/Ete/Automne/Hiver, voir
	# SEASON_BAND_SIZE), la ligne climat s'arrete desormais a y=146.
	box.offset_top = 152.0
	box.offset_bottom = 180.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	_btn_pause = _make_time_button(box, "pause", "Pause / Reprise (Espace)")
	_btn_speed1 = _make_time_button(box, "vitesse1", "Vitesse normale (F1)")
	_btn_speed2 = _make_time_button(box, "vitesse2", "Accéléré (F2)")
	_btn_speed4 = _make_time_button(box, "vitesse4", "Rapide (F3)")

	_btn_pause.pressed.connect(_on_time_speed_pressed.bind(0.0))
	_btn_speed1.pressed.connect(_on_time_speed_pressed.bind(1.0))
	_btn_speed2.pressed.connect(_on_time_speed_pressed.bind(2.0))
	_btn_speed4.pressed.connect(_on_time_speed_pressed.bind(4.0))
	_update_time_buttons()


## Sprint 37quindecies : bouton a icone dessinee (plus de texte "Pause"/"x1"/
## etc) - voir _get_time_icon_texture. tooltip_text rappelle le raccourci
## clavier associe (voir _unhandled_input).
func _make_time_button(parent: HBoxContainer, icon_kind: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.icon = icon_renderer.get_time_icon_texture(icon_kind, TIME_ICON_SIZE, TIME_ICON_COLOR)
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(44, 40)
	btn.tooltip_text = tooltip
	btn.expand_icon = true
	# 2026-07-05 (correctif bug "Espace remet en pause tout de suite") : sans
	# ceci, le bouton Pause peut garder le focus clavier apres un clic - Espace
	# est mappe par defaut sur l'action "ui_accept", qui reactiverait alors CE
	# bouton en plus de notre propre gestion KEY_SPACE (_toggle_pause), pour
	# un aller-retour pause/reprise quasi instantane (1 seule frame ecoulee).
	btn.focus_mode = Control.FOCUS_NONE
	parent.add_child(btn)
	return btn


func _on_time_speed_pressed(speed: float) -> void:
	DayNightCycleScript.game_speed = speed
	_update_time_buttons()


## 2026-07-05 (demande explicite, voir _speed_before_pause) : bascule pause/
## reprise au lieu de toujours forcer 0.0 - si le jeu tourne, memorise la
## vitesse courante puis met en pause ; si le jeu est deja en pause, reprend
## a la derniere vitesse memorisee (1.0 par defaut si Espace est le tout
## premier appui, avant toute selection explicite de vitesse).
func _toggle_pause() -> void:
	if is_equal_approx(DayNightCycleScript.game_speed, 0.0):
		_on_time_speed_pressed(_speed_before_pause)
	else:
		_speed_before_pause = DayNightCycleScript.game_speed
		_on_time_speed_pressed(0.0)


func _update_time_buttons() -> void:
	var speed: float = DayNightCycleScript.game_speed
	_btn_pause.button_pressed = is_equal_approx(speed, 0.0)
	_btn_speed1.button_pressed = is_equal_approx(speed, 1.0)
	_btn_speed2.button_pressed = is_equal_approx(speed, 2.0)
	_btn_speed4.button_pressed = is_equal_approx(speed, 4.0)


## Sprint 9 : petites icones de couleur (formes simples) sur chaque bouton,
## en attendant de vraies illustrations (style BD du brief)
func _setup_icons() -> void:
	btn_miner.icon = icon_renderer.make_square_icon(Color(0.5, 0.5, 0.5), 18)
	btn_couper.icon = icon_renderer.make_square_icon(Color(0.25, 0.55, 0.15), 18)
	btn_construire.icon = icon_renderer.make_square_icon(Color(0.85, 0.65, 0.13), 18)
	btn_cueillir.icon = icon_renderer.make_square_icon(Color(0.85, 0.25, 0.25), 18)
	btn_puiser.icon = icon_renderer.make_square_icon(_material_color("eau"), 18)
	btn_bois.icon = icon_renderer.make_square_icon(_material_color("bois"), 18)
	btn_pierre.icon = icon_renderer.make_square_icon(_material_color("pierre"), 18)
	btn_terre.icon = icon_renderer.make_square_icon(_material_color("terre"), 18)


## 2026-07-05 (dette A1) : deplace dans IconRenderer.gd (make_square_icon).


func _material_color(material: String) -> Color:
	match material:
		"bois":
			return Color(0.55, 0.38, 0.20)
		"pierre":
			return Color(0.60, 0.62, 0.66)
		"terre":
			return Color(0.35, 0.25, 0.15)
		"gris_minage":  # Sprint 35ter : fantome de previsualisation pour Miner (voir _update_mine_drag_preview)
			return Color(0.5, 0.5, 0.5)
		"eau":  # Sprint 36 : bouton Puiser + fantome de previsualisation
			return Color(0.25, 0.55, 0.85)
		_:
			return Color(1, 1, 1)


func _process(_delta: float) -> void:
	# Sprint 20 : "Bois" reste le total utilisable pour construire, avec le
	# detail par espece entre parentheses (chene/sapin/bouleau) a titre
	# informatif
	var wood_detail := "Chene %d, Sapin %d, Bouleau %d" % [
		inventory.get_count("bois_chene"),
		inventory.get_count("bois_sapin"),
		inventory.get_count("bois_bouleau"),
	]
	# 2026-07-05 (demande explicite Francois) : "Taches en attente" doit
	# compter toute tache designee tant qu'elle n'est pas VRAIMENT terminee,
	# pas seulement celles encore non-affectees dans TaskQueue - un nain qui a
	# deja pris une tache (current_task) mais ne l'a pas encore finie compte
	# donc aussi. task_queue.task_count() seul retombe a 0 des qu'un nain
	# libre recupere la tache, meme avant d'etre arrive dessus.
	var active_task_count: int = task_queue.task_count()
	for d in get_tree().get_nodes_in_group("dwarves"):
		if not d.current_task.is_empty():
			active_task_count += 1
	stats_label.text = "Bois : %d (%s)    Pierre : %d    Terre : %d    Taches en attente : %d" % [
		inventory.get_count("bois"),
		wood_detail,
		inventory.get_count("pierre"),
		inventory.get_count("terre"),
		active_task_count,
	]

	# Sprint 33 : horloge/calendrier - jour courant (DayNightCycle.day_count),
	# heure deduite de time_of_day (0.0-1.0 -> 24h), et saison courante
	# (SeasonSystem.current_season_id(), mise en forme avec capitalize() pour
	# l'affichage - pas besoin d'une table de noms separee).
	# 2026-07-02 : jour-du-mois et mois-de-la-saison sont deduits directement
	# de day_night_cycle.day_count (pas besoin d'interroger season_system pour
	# ca) - valable tant que SeasonSystem.season_duration_seconds reste un
	# multiple exact de DayNightCycle.cycle_duration_seconds (voir commentaire
	# dans SeasonSystem.gd).
	var total_minutes: float = day_night_cycle.time_of_day * 24.0 * 60.0
	var hours: int = int(total_minutes / 60.0)
	var minutes: int = int(fmod(total_minutes, 60.0))
	var days_per_season: int = SeasonSystemScript.DAYS_PER_MONTH * SeasonSystemScript.MONTHS_PER_SEASON
	var day_in_season: int = (day_night_cycle.day_count - 1) % days_per_season
	# Division entiere volontaire (indice de mois = division entiere + 1, pas
	# un calcul decimal) - avertissement Godot desactive explicitement ici.
	@warning_ignore("integer_division")
	var month_in_season: int = (day_in_season / SeasonSystemScript.DAYS_PER_MONTH) + 1
	var day_in_month: int = (day_in_season % SeasonSystemScript.DAYS_PER_MONTH) + 1
	# Sprint 37 (backlog Phase 1 item 1/5) : temperature + episode climatique
	# (vague de froid/canicule) ajoutes a l'affichage existant.
	var episode: String = temperature_system.episode_label() if temperature_system else ""
	var episode_suffix: String = " (%s)" % episode if episode != "" else ""
	time_label.text = "Jour %d (Mois %d) - %02dh%02d - %s - %d°C%s" % [
		day_in_month,
		month_in_season,
		hours,
		minutes,
		season_system.current_season_id().capitalize(),
		int(round(temperature_system.current_temperature())) if temperature_system else 0,
		episode_suffix,
	]

	# Sprint 37nonies : bandeau heure (degrade jour/nuit + icone soleil/lune +
	# marqueur), bandeau saison (degrade 4 couleurs + marqueur de progression)
	# et icone meteo - remplace les 3 anciennes pastilles de couleur unie.
	var season_id: String = season_system.current_season_id()
	var is_daylight: bool = day_night_cycle.is_daytime()

	if _hour_band_bg:
		# Le degrade depend du lever/coucher de la saison courante -
		# reconstruit uniquement quand la saison change (pas chaque frame).
		if season_id != _hour_band_season_cache:
			_hour_band_season_cache = season_id
			var sunrise_frac: float = _sunrise_fraction_for(season_id)
			var sunset_frac: float = _sunset_fraction_for(season_id)
			_hour_band_bg.texture = _build_hour_gradient_texture(sunrise_frac, sunset_frac)

		var hour_x: float = day_night_cycle.time_of_day * HOUR_BAND_SIZE.x
		_hour_marker.position = Vector2(hour_x - _hour_marker.size.x * 0.5, 0.0)
		_hour_marker.tooltip_text = time_label.text

		if not _sun_moon_icon_built or is_daylight != _sun_moon_is_day_cache:
			_sun_moon_is_day_cache = is_daylight
			_sun_moon_icon_built = true
			_sun_moon_icon.texture = icon_renderer.make_sun_moon_icon(is_daylight, SUN_MOON_ICON_SIZE)
		_sun_moon_icon.position = Vector2(
			hour_x - _sun_moon_icon.custom_minimum_size.x * 0.5,
			(HOUR_BAND_SIZE.y - _sun_moon_icon.custom_minimum_size.y) * 0.5
		)
		_sun_moon_icon.tooltip_text = "Jour" if is_daylight else "Nuit"

	if _season_marker:
		# Ordre d'affichage voulu (printemps/ete/automne/hiver) different de
		# l'ordre interne de ClimateDefinitions.SEASONS (ete/automne/hiver/
		# printemps) - voir SEASON_DISPLAY_ORDER.
		var display_index: int = SEASON_DISPLAY_ORDER.find(season_id)
		if display_index < 0:
			display_index = 0
		var season_progress: float = (float(display_index) + season_system.season_progress()) / float(SEASON_DISPLAY_ORDER.size())
		var season_x: float = season_progress * SEASON_BAND_SIZE.x
		_season_marker.position = Vector2(season_x - _season_marker.size.x * 0.5, 0.0)
		_season_marker.tooltip_text = season_id.capitalize()

	if _weather_icon_rect and weather_system:
		var weather_label: String = weather_system.current_weather_label()
		if weather_label != _weather_icon_cache:
			_weather_icon_cache = weather_label
			_weather_icon_rect.texture = icon_renderer.make_weather_icon(weather_label, CLIMATE_ICON_SIZE)
		_weather_icon_rect.tooltip_text = weather_label

	# Sprint 37 (backlog Phase 1 item 12) : panneau d'inspection permanent, mis
	# a jour par survol de la souris (remplace l'ancien systeme au clic, voir
	# _ready()).
	_update_hover_info_panel()


func _on_miner_pressed() -> void:
	current_mode = Mode.NONE if current_mode == Mode.MINER else Mode.MINER
	_update_buttons()


func _on_couper_pressed() -> void:
	current_mode = Mode.NONE if current_mode == Mode.COUPER else Mode.COUPER
	_update_buttons()


func _on_construire_pressed() -> void:
	current_mode = Mode.NONE if current_mode == Mode.CONSTRUIRE else Mode.CONSTRUIRE
	_update_buttons()


func _on_cueillir_pressed() -> void:
	current_mode = Mode.NONE if current_mode == Mode.CUEILLIR else Mode.CUEILLIR
	_update_buttons()


func _on_puiser_pressed() -> void:
	current_mode = Mode.NONE if current_mode == Mode.PUISER else Mode.PUISER
	_update_buttons()


func _on_material_pressed(material: String) -> void:
	selected_material = "" if selected_material == material else material
	_update_material_buttons()


func _update_buttons() -> void:
	btn_miner.button_pressed = (current_mode == Mode.MINER)
	btn_couper.button_pressed = (current_mode == Mode.COUPER)
	btn_construire.button_pressed = (current_mode == Mode.CONSTRUIRE)
	btn_cueillir.button_pressed = (current_mode == Mode.CUEILLIR)
	btn_puiser.button_pressed = (current_mode == Mode.PUISER)
	material_box.visible = (current_mode == Mode.CONSTRUIRE)
	# Sprint 35ter : Miner utilise maintenant le meme rectangle "monde" que
	# Construire (voir _on_left_press/_update_drag/_on_left_release), donc ne
	# pas annuler son glisser en cours non plus. Sprint 36 : Puiser fait de meme.
	if current_mode != Mode.CONSTRUIRE and current_mode != Mode.MINER and current_mode != Mode.PUISER:
		_cancel_drag()
	# Sprint 37 (backlog Phase 1 item 12) : le panneau d'inspection est
	# maintenant permanent (mis a jour par survol, voir _update_hover_info_panel) -
	# plus besoin de le cacher en changeant de mode.


func _update_material_buttons() -> void:
	btn_bois.button_pressed = (selected_material == "bois")
	btn_pierre.button_pressed = (selected_material == "pierre")
	btn_terre.button_pressed = (selected_material == "terre")


func _unhandled_input(event: InputEvent) -> void:
	# Sprint 37quindecies (2026-07-04, demande explicite) : raccourcis clavier
	# pour le controle du temps - Espace=pause, F1=vitesse normale, F2=accelere,
	# F3=rapide. Verifies AVANT la logique par mode ci-dessous pour rester
	# actifs quel que soit le mode d'action en cours (Miner/Construire/etc).
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_toggle_pause()
				get_viewport().set_input_as_handled()
				return
			KEY_F1:
				_on_time_speed_pressed(1.0)
				get_viewport().set_input_as_handled()
				return
			KEY_F2:
				_on_time_speed_pressed(2.0)
				get_viewport().set_input_as_handled()
				return
			KEY_F3:
				_on_time_speed_pressed(4.0)
				get_viewport().set_input_as_handled()
				return

	# Sprint 35ter : Mode.NONE (inspecter/selectionner des nains), Mode.COUPER
	# et Mode.CUEILLIR partagent maintenant la meme mecanique clic-ou-glisser
	# (voir _on_select_press/_update_select_drag/_on_select_release) - un clic
	# simple cible un seul objet (comme avant), un glisser au-dela de
	# SELECT_DRAG_THRESHOLD selectionne tous les arbres/buissons du rectangle.
	if current_mode == Mode.NONE or current_mode == Mode.COUPER or current_mode == Mode.CUEILLIR:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_select_button_down = true
				_on_select_press(event.position)
			else:
				_select_button_down = false
				_on_select_release(event.position)
		elif event is InputEventMouseMotion and _select_button_down:
			_update_select_drag(event.position)
		return

	# Reste : Mode.MINER et Mode.CONSTRUIRE, tous deux bases sur un rectangle
	# "monde" de cases de grille (voir is_dragging/drag_start/drag_end).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_press(event.position)
		else:
			_on_left_release()
	elif event is InputEventMouseMotion and is_dragging:
		_update_drag(event.position)


## Sprint 35ter : Miner utilise desormais le meme rectangle "monde" que
## Construire (un simple clic = rectangle de 1 case, un glisser = plusieurs) -
## voir _valid_mine_rect_cells/_update_mine_drag_preview/_finalize_mine_selection.
func _on_left_press(screen_pos: Vector2) -> void:
	var hit = _raycast_ground(screen_pos)
	if hit == null:
		return

	if current_mode == Mode.MINER:
		var cell := _cell_from_hit(hit)
		drag_start = cell
		drag_end = cell
		is_dragging = true
		_update_mine_drag_preview()
	elif current_mode == Mode.PUISER:
		var cell := _cell_from_hit(hit)
		drag_start = cell
		drag_end = cell
		is_dragging = true
		_update_puiser_drag_preview()
	elif current_mode == Mode.CONSTRUIRE:
		if selected_material == "":
			return
		var cell := _cell_from_hit(hit)
		drag_start = cell
		drag_end = cell
		is_dragging = true
		_update_drag_preview()


## Sprint 35ter : Miner et Construire se desactivent tous les deux
## automatiquement (retour a Mode.NONE) une fois la selection finalisee -
## demande explicite, uniformise avec Couper/Cueillir (voir _on_select_release).
func _on_left_release() -> void:
	if not is_dragging:
		return
	is_dragging = false
	match current_mode:
		Mode.MINER:
			_finalize_mine_selection()
		Mode.PUISER:
			_finalize_puiser_selection()
		_:
			_finalize_drag_selection()
	_clear_drag_preview()
	current_mode = Mode.NONE
	_update_buttons()


func _update_drag(screen_pos: Vector2) -> void:
	var hit = _raycast_ground(screen_pos)
	if hit == null:
		return
	drag_end = _cell_from_hit(hit)
	match current_mode:
		Mode.MINER:
			_update_mine_drag_preview()
		Mode.PUISER:
			_update_puiser_drag_preview()
		_:
			_update_drag_preview()


func _cancel_drag() -> void:
	is_dragging = false
	_clear_drag_preview()


## Sprint 29 : appui du clic gauche en Mode.NONE - on ne sait pas encore si
## ce sera un simple clic (Inspecter) ou un glisser (selection de nains), la
## decision est prise au relachement (_on_select_release) ou des que le
## glisser depasse SELECT_DRAG_THRESHOLD (_update_select_drag).
func _on_select_press(screen_pos: Vector2) -> void:
	_select_press_pos = screen_pos
	_select_dragging_active = false


## Appelee a chaque mouvement de souris tant que le bouton gauche est enfonce
## en Mode.NONE. Bascule en mode "glisser" des que la distance au point de
## depart depasse le seuil, et affiche/redimensionne le rectangle a l'ecran.
func _update_select_drag(screen_pos: Vector2) -> void:
	if not _select_dragging_active:
		if _select_press_pos.distance_to(screen_pos) < SELECT_DRAG_THRESHOLD:
			return
		_select_dragging_active = true
		_select_box.visible = true
	var top_left := Vector2(minf(_select_press_pos.x, screen_pos.x), minf(_select_press_pos.y, screen_pos.y))
	var size := (_select_press_pos - screen_pos).abs()
	_select_box.position = top_left
	_select_box.size = size


## Relachement du clic gauche en Mode.NONE : soit on termine un vrai glisser
## (selection de nains dans le rectangle), soit c'etait un simple clic
## (Inspecter, comportement inchange depuis le Sprint 25).
## Sprint 35ter : branche maintenant sur current_mode - Mode.NONE garde le
## comportement historique (Inspecter/selection de nains) ; Mode.COUPER et
## Mode.CUEILLIR font de meme mais ciblent des arbres/buissons pour les
## designer (glisser = plusieurs, clic simple = un seul, comme avant), puis se
## desactivent automatiquement (retour a Mode.NONE, demande explicite).
func _on_select_release(screen_pos: Vector2) -> void:
	if _select_dragging_active:
		match current_mode:
			Mode.COUPER:
				_finalize_chop_selection(_select_press_pos, screen_pos)
			Mode.CUEILLIR:
				_finalize_gather_selection(_select_press_pos, screen_pos)
			_:
				_finalize_box_selection(_select_press_pos, screen_pos)
		_select_dragging_active = false
		_select_box.visible = false
	elif current_mode == Mode.COUPER:
		var hit = _raycast_ground(_select_press_pos)
		if hit != null:
			_handle_chop_click(hit)
	elif current_mode == Mode.CUEILLIR:
		var hit = _raycast_ground(_select_press_pos)
		if hit != null:
			_handle_gather_click(hit)
	else:
		_handle_inspect_click(_select_press_pos)

	if current_mode == Mode.COUPER or current_mode == Mode.CUEILLIR:
		current_mode = Mode.NONE
		_update_buttons()


## Trouve tous les nains dont la position ecran (projetee via la camera
## active) tombe dans le rectangle glisse, et transmet la selection a
## CharacterSheetUI (qui gere l'affichage - anneaux au sol + surbrillance des
## portraits, purement visuel pour l'instant). Ctrl/Maj enfonce au
## relachement = ajoute a la selection existante au lieu de la remplacer,
## meme convention que Ctrl/Maj+clic sur un portrait de la fiche.
func _finalize_box_selection(a: Vector2, b: Vector2) -> void:
	var top_left := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var bottom_right := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var found: Array = []
	for dwarf in get_tree().get_nodes_in_group("dwarves"):
		var screen_pos: Vector2 = camera.unproject_position(dwarf.global_position)
		if screen_pos.x >= top_left.x and screen_pos.x <= bottom_right.x \
				and screen_pos.y >= top_left.y and screen_pos.y <= bottom_right.y:
			found.append(dwarf)
	var additive: bool = Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)
	character_sheet_ui.set_map_selection(found, additive)


## Sprint 35ter : tous les membres de "group" (ex: "trees"/"cueillette") dont
## la position ecran (projetee via la camera active) tombe dans le rectangle
## glisse - meme principe que _finalize_box_selection (nains), generalise a
## un groupe quelconque. Utilise par _finalize_chop_selection/
## _finalize_gather_selection ci-dessous.
func _targets_in_screen_rect(a: Vector2, b: Vector2, group: String) -> Array:
	var top_left := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var bottom_right := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var found: Array = []
	for target in get_tree().get_nodes_in_group(group):
		var screen_pos: Vector2 = camera.unproject_position(target.global_position)
		if screen_pos.x >= top_left.x and screen_pos.x <= bottom_right.x \
				and screen_pos.y >= top_left.y and screen_pos.y <= bottom_right.y:
			found.append(target)
	return found


## Sprint 35ter : version "plusieurs a la fois" de _handle_chop_click - meme
## logique de tache/marqueur (voir cette fonction), appliquee a chaque arbre
## trouve dans le rectangle glisse au lieu du seul arbre le plus proche du clic.
func _finalize_chop_selection(a: Vector2, b: Vector2) -> void:
	for target in _targets_in_screen_rect(a, b, "trees"):
		var task_id: int = task_queue.add_chop_task(target)
		var marker_pos: Vector3 = target.global_position + Vector3(0, _marker_height_for(target), 0)
		queued_markers[task_id] = _spawn_task_marker(marker_pos, "hache", Color(0.25, 0.55, 0.15))


## Sprint 35ter : version "plusieurs a la fois" de _handle_gather_click - meme
## logique de tache/marqueur (voir cette fonction), appliquee a chaque arbre
## fruitier/buisson trouve dans le rectangle glisse au lieu du seul le plus
## proche du clic.
func _finalize_gather_selection(a: Vector2, b: Vector2) -> void:
	for target in _targets_in_screen_rect(a, b, "cueillette"):
		var marker_pos: Vector3 = target.global_position + Vector3(0, _marker_height_for(target), 0)
		var task_id: int = task_queue.add_gather_task(target)
		queued_markers[task_id] = _spawn_task_marker(marker_pos, "panier", Color(0.85, 0.25, 0.25))


## Intersection du rayon camera->souris avec le sol. Sprint 38 (reliefs) : le
## sol n'est plus a une hauteur fixe partout (collines) - un seul plan a
## GROUND_LEVEL decalerait x/z du point vise des qu'on clique sur une colline
## (meme bug que Sprint 24quinquies, en pire : la camera regarde en angle, donc
## une hauteur de plan fausse decale aussi x/z, pas seulement y). On affine
## donc en plusieurs passes : apres une premiere intersection, on regarde la
## vraie hauteur de la colonne visee (get_top_block_y+1) et on refait
## l'intersection avec cette hauteur, jusqu'a convergence (releif doux, 2-3
## passes suffisent largement).
func _raycast_ground(screen_pos: Vector2):
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	if absf(ray_dir.y) < 0.0001:
		return null
	var plane_y: float = GROUND_LEVEL
	var hit: Vector3 = Vector3.ZERO
	for i in range(4):
		var t := (plane_y - ray_origin.y) / ray_dir.y
		if t < 0.0:
			return null
		hit = ray_origin + ray_dir * t
		var top_y: int = voxel_world.get_top_block_y(int(floor(hit.x)), int(floor(hit.z)))
		if top_y < 0:
			break
		var real_y: float = float(top_y) + 1.0
		if absf(real_y - plane_y) < 0.01:
			break
		plane_y = real_y
	return hit


func _cell_from_hit(hit: Vector3) -> Vector2i:
	return Vector2i(int(floor(hit.x)), int(floor(hit.z)))


## Toutes les cases valides (dans la carte, constructibles, pas deja en
## attente de construction) du rectangle defini par deux coins.
## 2026-07-05 (dette d'architecture A1) : delegue a ActionValidator.gd.
func _valid_rect_cells(a: Vector2i, b: Vector2i) -> Array:
	return action_validator.valid_rect_cells(a, b, GRID_WIDTH, GRID_DEPTH, voxel_world, pending_columns)


func _update_drag_preview() -> void:
	_clear_drag_preview()
	for cell in _valid_rect_cells(drag_start, drag_end):
		var y: int = voxel_world.get_top_block_y(cell.x, cell.y) + 1
		var ghost := _spawn_ghost(cell.x, y, cell.y, selected_material, 0.35)
		drag_preview_ghosts.append(ghost)


## Sprint 35ter : toutes les cases valides (dans la carte, avec quelque chose
## a miner) du rectangle defini par deux coins - meme principe que
## _valid_rect_cells (Construire) mais sans le filtre "constructible" ; pas de
## suivi de cases "en attente" non plus, pour rester fidele au comportement
## du clic simple d'origine (qui ne verifiait deja pas les doublons).
## 2026-07-05 (dette d'architecture A1) : delegue a ActionValidator.gd.
func _valid_mine_rect_cells(a: Vector2i, b: Vector2i) -> Array:
	return action_validator.valid_mine_rect_cells(a, b, GRID_WIDTH, GRID_DEPTH, voxel_world)


## Sprint 35ter : fantomes gris (voir _material_color("gris_minage")) sur
## chaque case a miner du rectangle courant, meme principe que
## _update_drag_preview (Construire).
func _update_mine_drag_preview() -> void:
	_clear_drag_preview()
	for cell in _valid_mine_rect_cells(drag_start, drag_end):
		var y: int = voxel_world.get_top_block_y(cell.x, cell.y)
		var ghost := _spawn_ghost(cell.x, y, cell.y, "gris_minage", 0.35)
		drag_preview_ghosts.append(ghost)


## Sprint 35ter : version "plusieurs a la fois" de l'ancien _handle_mine_click -
## une tache de minage par case valide du rectangle, chacune avec son propre
## marqueur pioche (meme logique que _finalize_drag_selection pour Construire).
func _finalize_mine_selection() -> void:
	for cell in _valid_mine_rect_cells(drag_start, drag_end):
		var top_y: int = voxel_world.get_top_block_y(cell.x, cell.y)
		var walk_pos := Vector3(cell.x + 0.5, GROUND_LEVEL, cell.y + 0.5)
		var task_id: int = task_queue.add_mine_task(walk_pos, cell.x, top_y, cell.y)
		var marker_pos := Vector3(cell.x + 0.5, top_y + 1.4, cell.y + 0.5)
		queued_markers[task_id] = _spawn_task_marker(marker_pos, "pioche", Color(0.5, 0.5, 0.5))


## Sprint 36 : toutes les cases valides (dans la carte, avec de l'eau en
## surface) du rectangle defini par deux coins - meme principe que
## _valid_mine_rect_cells, mais ne garde que les colonnes d'eau (voir
## VoxelWorld.is_water). Pas de suivi de cases "en attente" : l'eau est une
## ressource renouvelable, on peut la puiser autant de fois qu'on veut.
## 2026-07-05 (dette d'architecture A1) : delegue a ActionValidator.gd.
func _valid_puiser_rect_cells(a: Vector2i, b: Vector2i) -> Array:
	return action_validator.valid_puiser_rect_cells(a, b, GRID_WIDTH, GRID_DEPTH, voxel_world)


## Sprint 36 : fantomes bleus (voir _material_color("eau")) sur chaque case
## d'eau du rectangle courant, meme principe que _update_mine_drag_preview.
func _update_puiser_drag_preview() -> void:
	_clear_drag_preview()
	for cell in _valid_puiser_rect_cells(drag_start, drag_end):
		var y: int = voxel_world.get_top_block_y(cell.x, cell.y)
		var ghost := _spawn_ghost(cell.x, y, cell.y, "eau", 0.5)
		drag_preview_ghosts.append(ghost)


## Sprint 36 : une tache de puisage par case d'eau valide du rectangle, chacune
## avec son propre marqueur (reutilise l'icone "panier", teintee en bleu, pas
## besoin d'un nouveau dessin pixel par pixel pour un seau/une gourde).
func _finalize_puiser_selection() -> void:
	for cell in _valid_puiser_rect_cells(drag_start, drag_end):
		var top_y: int = voxel_world.get_top_block_y(cell.x, cell.y)
		var walk_pos := Vector3(cell.x + 0.5, GROUND_LEVEL, cell.y + 0.5)
		var task_id: int = task_queue.add_puiser_task(walk_pos, cell.x, cell.y)
		var marker_pos := Vector3(cell.x + 0.5, top_y + 1.2, cell.y + 0.5)
		queued_markers[task_id] = _spawn_task_marker(marker_pos, "panier", Color(0.25, 0.55, 0.85))


func _clear_drag_preview() -> void:
	for ghost in drag_preview_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	drag_preview_ghosts.clear()


## Cliquer-glisser termine : on file une tache de construction par case
## valide, chacune avec son propre mur fantome persistant jusqu'a ce que
## le nain ait fini de construire (succes ou echec faute de ressource)
func _finalize_drag_selection() -> void:
	for cell in _valid_rect_cells(drag_start, drag_end):
		var walk_pos := Vector3(cell.x + 0.5, GROUND_LEVEL, cell.y + 0.5)
		var task_id: int = task_queue.add_build_task(walk_pos, cell.x, cell.y, selected_material)
		pending_columns[cell] = true
		var y: int = voxel_world.get_top_block_y(cell.x, cell.y) + 1
		queued_ghosts[task_id] = _spawn_ghost(cell.x, y, cell.y, selected_material, 0.5)


## Retire le mur fantome correspondant une fois la tache de construction
## terminee (que le mur ait vraiment ete pose ou non)
func _on_build_task_finished(task_id: int, bx: int, bz: int) -> void:
	pending_columns.erase(Vector2i(bx, bz))
	if queued_ghosts.has(task_id):
		var ghost = queued_ghosts[task_id]
		if is_instance_valid(ghost):
			ghost.queue_free()
		queued_ghosts.erase(task_id)


## Sprint 26 : retire l'icone temporaire d'une tache Miner/Couper/Cueillir
## (ou Construire, mais celle-ci n'en cree pas - voir _finalize_drag_selection
## qui n'ajoute rien a queued_markers) une fois qu'elle est terminee. Signal
## generique emis pour TOUTES les taches (voir Dwarf.gd/task_finished), donc
## on verifie juste si un marqueur existe pour cet id avant de le retirer.
func _on_task_finished(task_id: int) -> void:
	if queued_markers.has(task_id):
		var marker = queued_markers[task_id]
		if is_instance_valid(marker):
			marker.queue_free()
		queued_markers.erase(task_id)


func _spawn_ghost(gx: int, gy: int, gz: int, material: String, alpha: float) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.94, 0.94, 0.94)  # legerement plus petit que le bloc reel pour bien le distinguer
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	var color := _material_color(material)
	color.a = alpha
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.position = Vector3(gx + 0.5, gy + 0.5, gz + 0.5)

	get_parent().add_child(mesh_inst)
	return mesh_inst


## Sprint 26bis : petit marqueur en forme d'outil (pioche/hache/panier selon
## "kind"), toujours face a la camera, affiche au-dessus d'un objet/case
## designe pour Miner/Couper/Cueillir tant que la tache n'est pas terminee.
## L'icone est dessinee pixel par pixel a l'execution (voir _get_icon_texture/
## _draw_pickaxe_icon/_draw_axe_icon/_draw_basket_icon), pas une image chargee
## depuis le disque - meme approche que _make_square_icon (icones de boutons),
## pour eviter le bug de blocs blancs deja rencontre avec les textures de
## filons chargees en fichier (voir memoire).
func _spawn_task_marker(pos: Vector3, kind: String, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	mesh_inst.mesh = quad

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = icon_renderer.get_icon_texture(kind, color, ICON_SIZE, ICON_GLYPH_SIZE)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED  # toujours face a la camera
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # rendu net, pas flou
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.position = pos

	get_parent().add_child(mesh_inst)
	return mesh_inst


## 2026-07-05 (dette A1) : _get_icon_texture/_draw_pickaxe_icon/_draw_axe_icon/
## _draw_basket_icon/_get_time_icon_texture/_draw_pause_icon/_draw_speed_icon
## + tous les helpers de dessin pixel par pixel (_fill_quad/_stroke_segment/
## _fill_rect_px/_draw_thick_line/_plot_blob/_fill_triangle/
## _point_in_triangle/_triangle_sign/_set_pixel_safe) deplaces dans
## IconRenderer.gd (get_icon_texture/get_time_icon_texture, appeles depuis
## _spawn_task_marker/_make_time_button ci-dessus).


## 2026-07-05 (dette d'architecture A1, etape 2) : recherche de la cible la
## plus proche deleguee a ActionValidator.gd (logique pure, voir sa doc) -
## seuls le marqueur visuel et l'ajout a la queue de taches restent ici.
func _handle_chop_click(hit: Vector3) -> void:
	var closest_tree: Node3D = action_validator.closest_in_group(hit, "trees", get_tree(), 2.0)

	if closest_tree:
		var task_id: int = task_queue.add_chop_task(closest_tree)
		var marker_pos: Vector3 = closest_tree.global_position + Vector3(0, _marker_height_for(closest_tree), 0)
		queued_markers[task_id] = _spawn_task_marker(marker_pos, "hache", Color(0.25, 0.55, 0.15))


## 2026-07-05 (correctif bug icone invisible Couper/Cueillir) : les arbres
## (Forest.gd) et buissons (BerryBushes.gd) sont mis a l'echelle aleatoirement
## a la creation (jusqu'a environ x1.5 pour les arbres selon espece/jitter,
## voir Forest.gd/scale_jitter) - un decalage de hauteur FIXE (comme avant)
## placait le marqueur a l'interieur du feuillage des arbres plus grands que
## la moyenne, le rendant invisible (cache par la couronne). La hauteur suit
## donc maintenant l'echelle reelle de la cible.
## 2026-07-05 (2e correctif, meme jour, "icone hache cachee dans l'arbre") :
## le coefficient 2.3 avait ete choisi sans calculer la hauteur reelle de la
## couronne - verifie via TreeSpecies.gd/Forest.gd : le chene (le plus haut
## des arbres "normaux" cibles par Couper, forme "touffu", hauteur=1.3) a une
## couronne qui monte jusqu'a 0.22+1.3+0.65+0.55=2.72 (top_y + y_max des blobs
## + leur rayon max, voir _build_foliage_touffu). Comme le marqueur ET la
## couronne sont mis a l'echelle par le meme facteur (tree.scale), 2.3 etait
## insuffisant quelle que soit l'echelle - remonte a 2.9 (2.72 + marge) pour
## rester nettement au-dessus de la couronne la plus haute.
func _marker_height_for(target: Node3D) -> float:
	if target.is_in_group("trees"):
		return 2.9 * target.scale.y
	return 1.0


## Sprint 24ter : detection au clic pour "Cueillir" - cible le groupe
## "cueillette" (arbres fruitiers + buissons a baies, voir Forest.gd/
## BerryBushes.gd), independant du groupe "trees" utilise par "Couper"
func _handle_gather_click(hit: Vector3) -> void:
	var closest_target: Node3D = action_validator.closest_in_group(hit, "cueillette", get_tree(), 2.0)

	if closest_target:
		var task_id: int = task_queue.add_gather_task(closest_target)
		var marker_pos: Vector3 = closest_target.global_position + Vector3(0, _marker_height_for(closest_target), 0)
		queued_markers[task_id] = _spawn_task_marker(marker_pos, "panier", Color(0.85, 0.25, 0.25))


## Sprint 25 : point d'entree de l'inspection (clic gauche quand aucun mode
## d'action n'est actif). Sprint 37 (backlog Phase 1 item 9) : ne gere plus
## que la selection/ouverture de fiche d'un nain clique directement (le texte
## d'inspection lui-meme est maintenant gere en continu par survol, voir
## _update_hover_info_panel/_ready) - un clic sur un nain selectionne/ouvre sa
## fiche (comme un clic sur son portrait), un clic ailleurs ne fait plus rien
## de special ici.
func _handle_inspect_click(screen_pos: Vector2) -> void:
	var clicked_dwarf: Node = _dwarf_at_screen_pos(screen_pos)
	if clicked_dwarf == null:
		return
	var additive: bool = Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)
	character_sheet_ui.select_and_open_dwarf(clicked_dwarf, additive)


## Sprint 37 (backlog Phase 1 item 9) : nain le plus proche d'une position
## ECRAN (pas monde), dans un rayon de DWARF_CLICK_RADIUS_PX pixels - meme
## technique de projection que _finalize_box_selection/_targets_in_screen_rect,
## utilisee ici pour un clic/survol direct sur le modele plutot qu'un
## rectangle. Renvoie null si aucun nain n'est assez proche.
func _dwarf_at_screen_pos(screen_pos: Vector2) -> Node:
	var closest: Node = null
	var closest_dist := DWARF_CLICK_RADIUS_PX
	for dwarf in get_tree().get_nodes_in_group("dwarves"):
		var projected: Vector2 = camera.unproject_position(dwarf.global_position)
		var d: float = projected.distance_to(screen_pos)
		if d < closest_dist:
			closest_dist = d
			closest = dwarf
	return closest


## Sprint 37 (backlog Phase 1 item 11, "piles d'objets") : les tas de
## ressources au sol (groupe "resource_piles", voir Dwarf._add_to_resource_pile)
## sont detectes en priorite, avant les arbres/buissons.
func _closest_resource_pile(hit: Vector3) -> Node3D:
	var closest: Node3D = null
	var closest_dist := 1.0
	for pile in get_tree().get_nodes_in_group("resource_piles"):
		var d: float = Vector2(pile.global_position.x - hit.x, pile.global_position.z - hit.z).length()
		if d < closest_dist:
			closest_dist = d
			closest = pile
	return closest


func _describe_resource_pile(pile: Node3D) -> String:
	var resource_name: String = String(pile.get_meta("resource_name"))
	var count: int = int(pile.get_meta("count"))
	return "Pile de %d %s" % [count, resource_name.capitalize()]


func _inspect_label_for(hit: Vector3) -> String:
	var pile := _closest_resource_pile(hit)
	if pile != null:
		return _describe_resource_pile(pile)

	var closest_target: Node3D = null
	var closest_dist := 2.0  # meme rayon de detection que Couper/Cueillir

	for target in get_tree().get_nodes_in_group("cueillette"):
		var d: float = Vector2(target.global_position.x - hit.x, target.global_position.z - hit.z).length()
		if d < closest_dist:
			closest_dist = d
			closest_target = target
	if closest_target == null:
		for target in get_tree().get_nodes_in_group("trees"):
			var d: float = Vector2(target.global_position.x - hit.x, target.global_position.z - hit.z).length()
			if d < closest_dist:
				closest_dist = d
				closest_target = target

	if closest_target:
		return _describe_gatherable(closest_target)

	var gx := int(floor(hit.x))
	var gz := int(floor(hit.z))
	if gx < 0 or gx >= GRID_WIDTH or gz < 0 or gz >= GRID_DEPTH:
		return ""
	return _describe_block(gx, gz)


## Nom + etat de recolte d'un arbre/buisson/plante, via les metadonnees
## deja posees par Forest.gd/BerryBushes.gd ("species_name", "fruits_left")
func _describe_gatherable(node: Node) -> String:
	var species_name: String = node.get_meta("species_name", "?")
	if not node.is_in_group("cueillette"):
		return species_name
	var fruits_left: int = node.get_meta("fruits_left", -1)
	if fruits_left < 0:
		return species_name
	if fruits_left == 0:
		return "%s (vide)" % species_name
	return "%s - %d fruit(s) restant(s)" % [species_name, fruits_left]


## Nom d'un bloc de sol (terre/pierre/mur), via VoxelWorld.get_block_info().
## Si le bloc de pierre contient un filon, affiche son nom (VeinMaterials).
func _describe_block(gx: int, gz: int) -> String:
	var info: Dictionary = voxel_world.get_block_info(gx, gz)
	match info["type"]:
		"terre":
			return "Terre"
		"pierre":
			var materiau: String = info["materiau"]
			if materiau != "":
				var mat: Dictionary = VeinMaterials.get_type(materiau)
				return "Filon de %s" % mat.get("nom", materiau)
			return "Pierre"
		"mur_bois":
			return "Mur en bois"
		"mur_pierre":
			return "Mur en pierre"
		"eau":
			return "Eau"
		_:
			return ""


## Sprint 37 (backlog Phase 1 item 12) : mis a jour chaque frame (voir
## _process) plutot qu'au clic - decrit ce qui se trouve sous la souris
## (nain, arbre/buisson, bloc de sol), quel que soit le mode courant. Le
## panneau reste toujours visible en bas a droite (voir Main.tscn/_ready),
## affiche un texte de repli quand rien de pertinent n'est survole.
func _update_hover_info_panel() -> void:
	var screen_pos: Vector2 = get_viewport().get_mouse_position()

	var hovered_dwarf: Node = _dwarf_at_screen_pos(screen_pos)
	if hovered_dwarf != null and is_instance_valid(hovered_dwarf):
		info_label.text = "%s\nTache : %s" % [hovered_dwarf.dwarf_name, _hover_task_description(hovered_dwarf)]
		return

	var hit = _raycast_ground(screen_pos)
	if hit == null:
		info_label.text = "Survolez un element de la carte..."
		return

	var label := _inspect_label_for(hit)
	info_label.text = label if label != "" else "Survolez un element de la carte..."


## Description courte de la tache en cours d'un nain survole - version
## simplifiee de CharacterSheetUI._task_description (pas d'acces direct a ce
## script prive depuis ActionController, et pas besoin du detail complet ici).
func _hover_task_description(dwarf: Node) -> String:
	if dwarf.is_working:
		return String(dwarf.current_task.get("type", "?")).capitalize()
	if dwarf.is_resting:
		return "Repos"
	if dwarf.is_eating:
		return "Manger"
	if dwarf.is_drinking:
		return "Boire"
	if not dwarf.current_task.is_empty():
		return String(dwarf.current_task.get("type", "?")).capitalize()
	return "Errance"
