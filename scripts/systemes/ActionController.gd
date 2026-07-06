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
## 2026-07-06 (dette d'architecture A1, I58 - revue de code) : ce fichier
## melangeait presentation (ghosts/marqueurs) et orchestration des regles
## (creation de taches) dans les memes fonctions "finalize_*", plus le groupe
## inspection/survol. Extrait mecaniquement en 2 nouveaux fichiers -
## ActionDragController.gd (glisser/selection/creation de taches, coeur
## stateful) et ActionInspector.gd (inspection/survol, lecture seule) - voir
## leurs docs. Aucun changement de comportement/API interne ; les fonctions
## ci-dessous qui delegent sont marquees "simple delegation".

const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
## Sprint 33 (calendrier) : pour lire DAYS_PER_MONTH/MONTHS_PER_SEASON sans
## dupliquer ces valeurs en dur ici (season_system est type "Node" generique
## via %SeasonSystem, donc ses constantes ne sont pas visibles directement).
const SeasonSystemScript := preload("res://scripts/systemes/SeasonSystem.gd")
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

## 2026-07-06 (dette A1, etape suivante apres ActionValidator.gd/DwarfSkills.gd/
## IconRenderer.gd) : toute la construction/mise a jour de l'UI climat (bandeau
## heure, bandeau saison, icone meteo) et des controles de temps (boutons
## Pause/x1/x2/x4 + raccourcis clavier associes) extraite dans ClimateUI.gd -
## voir climate_ui.setup()/update()/toggle_pause()/on_time_speed_pressed()
## ci-dessous, desormais de simples appels (aucun changement de comportement/
## API interne).
const ClimateUIScript := preload("res://scripts/systemes/ClimateUI.gd")
var climate_ui: ClimateUIScript = ClimateUIScript.new()

## 2026-07-06 (dette A1, I58) : glisser/selection/creation de taches
## (Miner/Construire/Puiser/Couper/Cueillir/selection de nains) extrait dans
## ActionDragController.gd - voir _on_left_press/_on_left_release/etc.
## ci-dessous, desormais de simples delegations.
const ActionDragControllerScript := preload("res://scripts/systemes/ActionDragController.gd")
## 2026-07-06 (dette A1, I58) : inspection/survol (lecture seule) extrait
## dans ActionInspector.gd - voir _handle_inspect_click/_update_hover_info_panel
## ci-dessous, desormais de simples delegations.
const ActionInspectorScript := preload("res://scripts/systemes/ActionInspector.gd")

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
# 2026-07-06 (dette A1, I58) : GROUND_LEVEL (deplacee/dupliquee dans
# ActionDragController.gd) retiree d'ici, plus utilisee dans ce fichier.

# Sprint 26bis : taille (en pixels) des icones d'outil dessinees a l'execution
# pour les marqueurs de tache (voir IconRenderer.gd)
# 2026-07-05 (demande explicite Francois, icones jugees "moches et pas
# lisibles") : agrandie (20 -> 40) et le glyphe (pioche/hache/panier) est
# maintenant dessine plus petit qu'avant puis incruste au centre d'un badge
# rond jaune, pour un meilleur contraste sur n'importe quel decor et une
# forme reconnaissable de loin.
# 2026-07-06 (dette A1, I58) : ICON_SIZE/ICON_GLYPH_SIZE (deplacees/dupliquees
# dans ActionDragController.gd) retirees d'ici, plus utilisees dans ce fichier.

## Sprint 37quindecies (2026-07-04, demande explicite : "remplacer les boutons
## pause x1 x2 x4 par des icones") : raccourcis clavier associes (Espace=pause,
## F1=x1, F2=x2, F3=x4), valables quel que soit le mode d'action courant (voir
## _unhandled_input). Taille/couleur des icones + logique pause/vitesse
## deplacees dans ClimateUI.gd (2026-07-06, dette A1, voir climate_ui).

# Sprint 37 (backlog Phase 1 item 9) : rayon (en pixels ecran) de detection
# d'un nain au clic/survol direct sur son modele - voir ActionInspector.gd.
# 2026-07-06 (dette A1, I58) : DWARF_CLICK_RADIUS_PX (deplacee/dupliquee dans
# ActionInspector.gd) retiree d'ici, plus utilisee dans ce fichier.

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

## 2026-07-06 (dette A1) : bandeaux heure/saison, icone meteo, boutons
## Pause/x1/x2/x4 et tout leur etat (caches, _speed_before_pause...) deplaces
## dans ClimateUI.gd - voir sa doc pour l'historique complet (Sprint 37nonies
## a 47) de ces elements d'UI.

# Sprint 29 : selection multiple de nains par rectangle (Mode.NONE
# uniquement). Distinct du systeme de glisser du mode CONSTRUIRE ci-dessus
# (is_dragging/drag_start/drag_end, qui travaille en cases de grille, pas en
# coordonnees ecran).
# 2026-07-06 (dette A1, I58) : SELECT_DRAG_THRESHOLD (deplacee/dupliquee dans
# ActionDragController.gd) retiree d'ici, plus utilisee dans ce fichier.
var _select_button_down: bool = false   # vrai entre l'appui et le relachement du clic gauche (Mode.NONE)
## 2026-07-06 (correctif UNUSED_PRIVATE_CLASS_VARIABLE) : ces 2 proprietes ne
## sont plus lues/ecrites QUE dynamiquement (get()/set()) depuis
## ActionDragController.gd depuis l'extraction I58 - l'analyseur GDScript ne
## detecte pas cet usage indirect, d'ou l'avertissement sans consequence
## (les valeurs restent bien lues/ecrites normalement a l'execution).
@warning_ignore("unused_private_class_variable")
var _select_dragging_active: bool = false  # vrai seulement une fois le seuil de glisser depasse
@warning_ignore("unused_private_class_variable")
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
	climate_ui.setup(self, icon_renderer)
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


## 2026-07-05 (dette A1) : _fill_circle/_make_sun_moon_icon/_make_weather_icon
## deplaces dans IconRenderer.gd (make_sun_moon_icon/make_weather_icon,
## appeles depuis _process ci-dessous).


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


## 2026-07-06 (revue de code Phase 3, C14) : decoupee en sous-fonctions
## thematiques (_update_stats_label/_update_time_label/_update_climate_ui) -
## depassait le seuil de 50 lignes de l'axe 1. Aucun changement de
## comportement, meme ordre d'appel qu'avant.
func _process(_delta: float) -> void:
	_update_stats_label()
	_update_time_label()
	_update_climate_ui()
	_update_hover_info_panel()


## Sprint 20 : "Bois" reste le total utilisable pour construire, avec le
## detail par espece entre parentheses (chene/sapin/bouleau) a titre
## informatif.
## 2026-07-05 (demande explicite Francois) : "Taches en attente" doit compter
## toute tache designee tant qu'elle n'est pas VRAIMENT terminee, pas
## seulement celles encore non-affectees dans TaskQueue - un nain qui a deja
## pris une tache (current_task) mais ne l'a pas encore finie compte donc
## aussi. task_queue.task_count() seul retombe a 0 des qu'un nain libre
## recupere la tache, meme avant d'etre arrive dessus.
func _update_stats_label() -> void:
	var wood_detail := "Chene %d, Sapin %d, Bouleau %d" % [
		inventory.get_count("bois_chene"),
		inventory.get_count("bois_sapin"),
		inventory.get_count("bois_bouleau"),
	]
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


## Sprint 33 : horloge/calendrier - jour courant (DayNightCycle.day_count),
## heure deduite de time_of_day (0.0-1.0 -> 24h), et saison courante
## (SeasonSystem.current_season_id(), mise en forme avec capitalize() pour
## l'affichage - pas besoin d'une table de noms separee).
## 2026-07-02 : jour-du-mois et mois-de-la-saison sont deduits directement de
## day_night_cycle.day_count (pas besoin d'interroger season_system pour ca) -
## valable tant que SeasonSystem.season_duration_seconds reste un multiple
## exact de DayNightCycle.cycle_duration_seconds (voir commentaire dans
## SeasonSystem.gd).
## Sprint 37 (backlog Phase 1 item 1/5) : temperature + episode climatique
## (vague de froid/canicule) ajoutes a l'affichage existant.
func _update_time_label() -> void:
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


## Sprint 37nonies : bandeau heure (degrade jour/nuit + icone soleil/lune +
## marqueur), bandeau saison (degrade 4 couleurs + marqueur de progression) et
## icone meteo - remplace les 3 anciennes pastilles de couleur unie.
## Appelee APRES _update_time_label (utilise time_label.text deja a jour comme
## tooltip, voir ClimateUI.update).
func _update_climate_ui() -> void:
	var season_id: String = season_system.current_season_id()
	var is_daylight: bool = day_night_cycle.is_daytime()
	var weather_label: String = weather_system.current_weather_label() if weather_system else ""
	climate_ui.update(season_id, is_daylight, day_night_cycle.time_of_day, season_system.season_progress(), weather_label, time_label.text)


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


## 2026-07-06 (revue de code Phase 3, C15) : le bloc raccourcis clavier a ete
## extrait dans _handle_time_shortcuts() - depassait le seuil de 50 lignes de
## l'axe 1. Aucun changement de comportement.
func _unhandled_input(event: InputEvent) -> void:
	if _handle_time_shortcuts(event):
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


## Sprint 37quindecies (2026-07-04, demande explicite) : raccourcis clavier
## pour le controle du temps - Espace=pause, F1=vitesse normale, F2=accelere,
## F3=rapide. Verifies AVANT la logique par mode de _unhandled_input pour
## rester actifs quel que soit le mode d'action en cours (Miner/Construire/etc).
## Renvoie true si l'evenement a ete consomme (l'appelant doit alors return).
## 2026-07-06 (revue de code Phase 3, C15) : extrait de _unhandled_input.
func _handle_time_shortcuts(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				climate_ui.toggle_pause()
				get_viewport().set_input_as_handled()
				return true
			KEY_F1:
				climate_ui.on_time_speed_pressed(1.0)
				get_viewport().set_input_as_handled()
				return true
			KEY_F2:
				climate_ui.on_time_speed_pressed(2.0)
				get_viewport().set_input_as_handled()
				return true
			KEY_F3:
				climate_ui.on_time_speed_pressed(4.0)
				get_viewport().set_input_as_handled()
				return true
	return false


## 2026-07-06 (dette A1, I58) : glisser/selection/creation de taches -
## simples delegations vers ActionDragController.gd (voir sa doc). Aucun
## changement de comportement/API interne.
func _on_left_press(screen_pos: Vector2) -> void:
	ActionDragControllerScript.on_left_press(self, screen_pos)


func _on_left_release() -> void:
	ActionDragControllerScript.on_left_release(self)


func _update_drag(screen_pos: Vector2) -> void:
	ActionDragControllerScript.update_drag(self, screen_pos)


func _cancel_drag() -> void:
	ActionDragControllerScript.cancel_drag(self)


func _on_select_press(screen_pos: Vector2) -> void:
	ActionDragControllerScript.on_select_press(self, screen_pos)


func _update_select_drag(screen_pos: Vector2) -> void:
	ActionDragControllerScript.update_select_drag(self, screen_pos)


func _on_select_release(screen_pos: Vector2) -> void:
	ActionDragControllerScript.on_select_release(self, screen_pos)


## Retire le mur fantome correspondant une fois la tache de construction
## terminee - simple delegation, connectee au signal Dwarf.build_task_finished
## dans _ready() ci-dessus.
func _on_build_task_finished(task_id: int, bx: int, bz: int) -> void:
	ActionDragControllerScript.on_build_task_finished(self, task_id, bx, bz)


## Retire l'icone temporaire d'une tache terminee - simple delegation,
## connectee au signal Dwarf.task_finished dans _ready() ci-dessus.
func _on_task_finished(task_id: int) -> void:
	ActionDragControllerScript.on_task_finished(self, task_id)


## 2026-07-06 (dette A1, I58) : inspection/survol - simples delegations vers
## ActionInspector.gd (voir sa doc). Aucun changement de comportement/API
## interne.
func _handle_inspect_click(screen_pos: Vector2) -> void:
	ActionInspectorScript.handle_inspect_click(self, screen_pos)


func _update_hover_info_panel() -> void:
	ActionInspectorScript.update_hover_info_panel(self)
