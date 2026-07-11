extends CanvasLayer
## Menu d'actions (boutons de mode + sous-menu materiau/construction),
## designation a la souris (clic simple ou rectangle glisse selon le mode),
## et panneau d'inspection au survol.
##
## Ce fichier reste le point d'entree/l'etat partage (current_mode,
## selected_material, boutons, references aux systemes du jeu), mais delegue
## le detail de plusieurs responsabilites a des fichiers dedies :
## - ActionValidator.gd : validation des cases cibles (Construire/Miner/
##   Puiser/Detruire).
## - IconRenderer.gd : dessin pixel par pixel de toutes les icones (marqueurs
##   de tache, climat, pause/vitesse, boutons d'action).
## - ClimateUI.gd : bandeau heure, bandeau saison, icone meteo, controles de
##   temps (Pause/x1/x2/x4).
## - InventoryUI.gd : panneau d'inventaire collapsible.
## - ActionDragController.gd : glisser/selection/creation de taches (coeur
##   stateful de Miner/Construire/Puiser/Couper/Cueillir/Detruire/Interdire/
##   selection de nains).
## - ActionInspector.gd : inspection/survol en lecture seule.
## - ActionMenuBar.gd : construction par code des boutons de mode + sous-menu
##   Construire, a partir d'une table de donnees plutot que de noeuds nommes
##   en dur dans Main.tscn.
## Cette separation evite de melanger presentation (ghosts/marqueurs) et
## orchestration des regles (creation de taches) dans les memes fonctions ;
## les fonctions de ce fichier qui delegent sont marquees "simple delegation".

const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
## Pour lire DAYS_PER_MONTH/MONTHS_PER_SEASON sans dupliquer ces valeurs en
## dur ici (season_system est type "Node" generique via %SeasonSystem, donc
## ses constantes ne sont pas visibles directement).
const SeasonSystemScript := preload("res://scripts/systemes/SeasonSystem.gd")
## Pour le garde-fou de _ready() ci-dessous et pour GRID_WIDTH/GRID_DEPTH.
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")
## Table centrale menu/icone/couleur/effort par type de tache - voir sa doc.
const TaskDefinitionsScript := preload("res://scripts/data/taches/TaskDefinitions.gd")
const ActionValidatorScript := preload("res://scripts/systemes/ActionValidator.gd")
var action_validator: ActionValidatorScript = ActionValidatorScript.new()

const IconRendererScript := preload("res://scripts/systemes/IconRenderer.gd")
var icon_renderer: IconRendererScript = IconRendererScript.new()

const ClimateUIScript := preload("res://scripts/systemes/ClimateUI.gd")
var climate_ui: ClimateUIScript = ClimateUIScript.new()

## Meme pattern que climate_ui ci-dessus : instance unique, setup() construit
## le panneau une fois (_ready()), update() rafraichit juste les compteurs
## (_process()). Voir InventoryUI.gd pour le detail des categories.
const InventoryUIScript := preload("res://scripts/systemes/InventoryUI.gd")
var inventory_ui: InventoryUIScript = InventoryUIScript.new()

const ActionDragControllerScript := preload("res://scripts/systemes/ActionDragController.gd")
const ActionInspectorScript := preload("res://scripts/systemes/ActionInspector.gd")
## Raccourcis clavier (mode/sous-type/sortie/temps) - voir _handle_*_shortcuts
## et _handle_mode_exit plus bas, simples relais (revue de code C26,
## 2026-07-11).
const ActionShortcutsScript := preload("res://scripts/systemes/ActionShortcuts.gd")

## Rangee de boutons d'action + sous-menu Construire construits PAR CODE a
## partir d'une table de donnees (ActionMenuBar.MODE_ENTRIES/
## CONSTRUIRE_SUBMENU_ENTRIES) au lieu de boutons nommes en dur dans
## Main.tscn - voir sa doc. Chaque mode a un raccourci clavier (B/C/U/M/P,
## voir _handle_mode_shortcuts).
const ActionMenuBarScript := preload("res://scripts/systemes/ActionMenuBar.gd")

## Modes disponibles. ANNULER annule une tache deja designee (encore en file
## OU deja prise par un nain) mais pas encore terminee, voir
## _on_annuler_click/ActionDragController.on_annuler_click. DETRUIRE demolit
## un mur construit (mur_bois/mur_pierre), meme mecanique de rectangle
## "monde" que Miner, voir ActionValidator.valid_destroy_rect_cells/
## ActionDragController.finalize_destroy_selection. INTERDIRE bloque le
## ramassage/utilisation d'une case de terrain (rectangle, meme univers que
## Miner) ou d'un arbre/element de cueillette (clic individuel), reversible
## (re-cliquer/re-tracer re-autorise) - voir VoxelWorld.forbidden_cells,
## ActionDragController.finalize_interdire_selection/toggle_interdit_entity.
enum Mode { NONE, MINER, COUPER, CONSTRUIRE, CUEILLIR, PUISER, ANNULER, DETRUIRE, INTERDIRE }
## Correspondance entre l'id de mode (String, utilise par ActionMenuBar.gd
## pour ne pas dependre directement de l'enum Mode) et sa valeur reelle.
const MODE_BY_ID := {
	"MINER": Mode.MINER,
	"COUPER": Mode.COUPER,
	"CONSTRUIRE": Mode.CONSTRUIRE,
	"CUEILLIR": Mode.CUEILLIR,
	"PUISER": Mode.PUISER,
	"ANNULER": Mode.ANNULER,
	"DETRUIRE": Mode.DETRUIRE,
	"INTERDIRE": Mode.INTERDIRE,
}
var current_mode: int = Mode.NONE
var selected_material: String = ""  # "bois" / "pierre" / "terre" en mode CONSTRUIRE

## Sous-type actif en Mode.MINER ("bloc" = minage rectangle classique,
## "escalier" = creusage de colonne, voir MinerSubMenu/miner_submenu_box plus
## bas) - meme principe que selected_material pour CONSTRUIRE, mais ici le
## sous-type change completement le GESTE de designation (rectangle vs
## clic+molette+clic), pas juste un materiau.
var miner_subtype: String = "bloc"

## Etat du geste "escalier" (clic sur la colonne, molette pour regler la
## profondeur, 2e clic pour confirmer) - voir ActionDragController.
## on_stair_click/extend_stair_gesture/finalize_stair_selection.
## stair_active est lu par CameraRig.gd (via %ActionUI, acces dynamique) pour
## suspendre temporairement le changement de niveau de vue a la molette
## pendant le geste (sinon la molette ferait les deux choses a la fois).
var stair_active: bool = false
var stair_column: Vector2i = Vector2i.ZERO
var stair_top_y: int = 0
var stair_bottom_y: int = 0
var stair_preview_ghosts: Array = []

## Reference directe a VoxelWorld.WIDTH/DEPTH (source unique) plutot qu'un
## nombre duplique en dur : desynchronisation structurellement impossible
## plutot que juste detectee a l'execution. Plus des const : WIDTH/DEPTH
## sont reglables depuis StartMenu.gd (taille de carte), mais restent figes
## une fois lus ici (jamais modifies en cours de partie).
var GRID_WIDTH: int = VoxelWorldScript.WIDTH
var GRID_DEPTH: int = VoxelWorldScript.DEPTH
# Note : comme la camera regarde le sol en angle, une mauvaise hauteur de
# plan de projection decale aussi x/z du point clique, pas seulement y - une
# hauteur erronee peut donc rater systematiquement les cibles rares
# ("Cueillir") et decaler aussi (de facon moins visible) miner/couper/
# construire. GROUND_LEVEL vit desormais dans ActionDragController.gd.

# Taille (en pixels) des icones d'outil dessinees a l'execution pour les
# marqueurs de tache (voir IconRenderer.gd) : le glyphe (pioche/hache/panier)
# est dessine plus petit que l'icone puis incruste au centre d'un badge rond
# jaune, pour un meilleur contraste sur n'importe quel decor et une forme
# reconnaissable de loin. ICON_SIZE/ICON_GLYPH_SIZE vivent dans
# ActionDragController.gd.

## Raccourcis clavier de controle du temps (Espace=pause, F1=x1, F2=x2,
## F3=x4), valables quel que soit le mode d'action courant (voir
## _unhandled_input). Taille/couleur des icones + logique pause/vitesse
## vivent dans ClimateUI.gd (voir climate_ui).

# Rayon (en pixels ecran) de detection d'un nain au clic/survol direct sur
# son modele - vit dans ActionInspector.gd (DWARF_CLICK_RADIUS_PX).

## Les boutons de mode sont construits par code dans _ready() via
## ActionMenuBarScript.build() - voir mode_buttons/construire_type_buttons
## ci-dessous. "mode_box" reste un conteneur vide dans Main.tscn, rempli au
## demarrage.
@onready var mode_box: HBoxContainer = $HBox
@onready var construire_submenu_box: VBoxContainer = $ConstruireSubMenu
## Sous-menu Creuser (Miner/Escalier) - meme principe que construire_submenu_box
## ci-dessus, voir MINER_SUBMENU_ENTRIES dans ActionMenuBar.gd.
@onready var miner_submenu_box: VBoxContainer = $MinerSubMenu
var mode_buttons: Dictionary = {}          # id (String, cle de MODE_BY_ID) -> Button
## Reference vers le ButtonGroup partage par les boutons de mode (cree dans
## ActionMenuBarScript.build()) : Godot maintient lui-meme "un seul enfonce a
## la fois", on se contente de LIRE son etat (get_pressed_button()) au lieu
## de forcer chaque bouton un par un - voir _on_mode_button_toggled/
## _reset_mode_selection.
var mode_button_group: ButtonGroup
## Id de mode (String) -> ImageTexture, generees par ActionMenuBarScript.
## build() (voir cursor_textures dans ce fichier), pour que le curseur change
## de forme selon le mode actif. Cle "" absente : Mode.NONE restaure le
## curseur systeme (voir _update_cursor()).
var cursor_textures: Dictionary = {}
var construire_type_buttons: Dictionary = {}  # "mur"/"porte"/... -> Button
var miner_submenu_buttons: Dictionary = {}    # "bloc"/"escalier" -> Button
var miner_subtype_group: ButtonGroup
@onready var material_box: VBoxContainer = $MaterialBox
@onready var btn_bois: Button = $MaterialBox/BoisButton
@onready var btn_pierre: Button = $MaterialBox/PierreButton
@onready var btn_terre: Button = $MaterialBox/TerreButton
## Meme principe que mode_button_group ci-dessus, pour le trio Bois/Pierre/
## Terre (ces 3 boutons restent nommes en dur dans Main.tscn, donc ce groupe
## est cree ici plutot que dans ActionMenuBarScript.build()).
var material_button_group := ButtonGroup.new()
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

# Bandeaux heure/saison, icone meteo, boutons Pause/x1/x2/x4 et tout leur
# etat (caches, _speed_before_pause...) vivent dans ClimateUI.gd.

# Selection multiple de nains par rectangle (Mode.NONE uniquement). Distinct
# du systeme de glisser du mode CONSTRUIRE ci-dessous (is_dragging/
# drag_start/drag_end, qui travaille en cases de grille, pas en coordonnees
# ecran). SELECT_DRAG_THRESHOLD vit dans ActionDragController.gd.
var _select_button_down: bool = false   # vrai entre l'appui et le relachement du clic gauche (Mode.NONE)
## Ces 2 proprietes ne sont plus lues/ecrites QUE dynamiquement (get()/set())
## depuis ActionDragController.gd - l'analyseur GDScript ne detecte pas cet
## usage indirect, d'ou l'avertissement sans consequence (les valeurs
## restent bien lues/ecrites normalement a l'execution).
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

# Icones temporaires sur les objets/cases designes pour Miner/Couper/
# Cueillir, retirees des que Dwarf.task_finished signale la fin de la tache
# correspondante (voir _spawn_task_marker/_on_task_finished)
var queued_markers: Dictionary = {}    # task_id -> MeshInstance3D
# Cache des textures d'icones : voir IconRenderer.gd
# (_icon_texture_cache/_time_icon_cache).


func _ready() -> void:
	# Boutons de mode + sous-menu Construire construits par code (voir
	# ActionMenuBarScript.build()).
	var menu: Dictionary = ActionMenuBarScript.build(mode_box, construire_submenu_box, miner_submenu_box, icon_renderer, _material_color("eau"))
	mode_buttons = menu["mode_buttons"]
	construire_type_buttons = menu["submenu_buttons"]
	miner_submenu_buttons = menu["miner_submenu_buttons"]
	miner_subtype_group = menu["miner_subtype_group"]
	mode_button_group = menu["mode_group"]
	cursor_textures = menu["cursor_textures"]
	# UN SEUL signal ecoute (n'importe lequel des boutons du groupe suffit,
	# ils partagent le meme mode_button_group) au lieu d'un .pressed par
	# bouton avec logique de bascule manuelle - voir
	# _on_mode_button_toggled, qui relit l'etat du groupe plutot que de le
	# recalculer lui-meme.
	for mode_id in mode_buttons:
		mode_buttons[mode_id].toggled.connect(_on_mode_button_toggled)
	for subtype_id in miner_submenu_buttons:
		miner_submenu_buttons[subtype_id].toggled.connect(_on_miner_subtype_toggled)
	# Pre-selectionne "bloc" (comportement historique de Creuser) SANS emettre
	# le signal toggled (set_pressed_no_signal) - miner_subtype vaut deja
	# "bloc" par defaut (voir sa declaration), pas besoin de re-declencher le
	# handler pour un etat qui ne change pas.
	if miner_submenu_buttons.has("bloc"):
		miner_submenu_buttons["bloc"].set_pressed_no_signal(true)
	material_button_group.allow_unpress = true
	btn_bois.button_group = material_button_group
	btn_bois.set_meta("material_id", "bois")
	btn_pierre.button_group = material_button_group
	btn_pierre.set_meta("material_id", "pierre")
	btn_terre.button_group = material_button_group
	btn_terre.set_meta("material_id", "terre")
	for b in [btn_bois, btn_pierre, btn_terre]:
		b.toggled.connect(_on_material_button_toggled)
	# Evite que ces boutons gardent le focus clavier et soient reactives par
	# megarde par Espace/Entree ("ui_accept"). Les boutons de mode/sous-menu
	# recoivent deja FOCUS_NONE dans ActionMenuBarScript.build() ci-dessus.
	for b in [btn_bois, btn_pierre, btn_terre]:
		b.focus_mode = Control.FOCUS_NONE
	for d in get_tree().get_nodes_in_group("dwarves"):
		d.build_task_finished.connect(_on_build_task_finished)
		d.task_finished.connect(_on_task_finished)
	_setup_icons()
	_update_buttons()
	_update_material_buttons()
	# Ces 4 conteneurs (VBoxContainer/HBoxContainer) ont un rect plus grand
	# que leurs boutons (ancres/offsets fixes dans Main.tscn, separation
	# entre boutons) - en filtre souris par defaut (MOUSE_FILTER_STOP), tout
	# clic dans cet espace "vide" mais toujours a l'interieur du rect est
	# absorbe par le conteneur et n'atteint jamais _unhandled_input, alors
	# que la carte 3D est visible et cliquable juste en-dessous/a cote.
	# Symptome rapporte par Francois 2026-07-08 : apres avoir choisi un mode,
	# le premier clic sur la carte semblait juste "sortir du menu" sans
	# rien designer - en realite ce clic etait silencieusement avale ici, le
	# clic suivant (hors de ce rect) fonctionnait. IGNORE sur le CONTENEUR
	# n'empeche pas ses boutons enfants de rester cliquables (chacun garde
	# son propre filtre STOP par defaut) - meme pattern deja utilise pour
	# _select_box ci-dessous.
	for box in [mode_box, construire_submenu_box, miner_submenu_box, material_box]:
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material_box.visible = false
	construire_submenu_box.visible = false
	miner_submenu_box.visible = false
	_setup_select_box()
	climate_ui.setup(self, icon_renderer)
	inventory_ui.setup(self)
	# Le panneau d'inspection est permanent, positionne en bas a droite (voir
	# Main.tscn), mis a jour en continu par survol dans _process au lieu
	# d'apparaitre/disparaitre au clic. Le bouton "Fermer" n'a plus lieu
	# d'etre (le panneau ne se ferme plus), mais le noeud reste dans la
	# scene.
	info_close_button.visible = false
	info_panel.visible = true
	info_label.text = "Survolez un element de la carte..."


## Rectangle de selection affiche pendant un glisser-clic en Mode.NONE (voir
## _update_select_drag). Simple Panel + StyleBoxFlat (fond bleu tres
## transparent + bordure), cree une seule fois et repositionne/redimensionne
## a chaque frame de glisser plutot que recree.
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


## Petites icones de couleur (formes simples) sur chaque bouton, en attendant
## de vraies illustrations. Les icones des boutons de mode sont posees
## directement dans ActionMenuBarScript.build() (elles n'existent qu'une
## fois les boutons crees par code) - ne reste ici que le sous-menu materiau
## (bois/pierre/terre), toujours des boutons nommes en dur dans Main.tscn.
func _setup_icons() -> void:
	btn_bois.icon = icon_renderer.make_square_icon(_material_color("bois"), 18)
	btn_pierre.icon = icon_renderer.make_square_icon(_material_color("pierre"), 18)
	btn_terre.icon = icon_renderer.make_square_icon(_material_color("terre"), 18)
	# Reutilise ActionMenuBarScript.SUBMENU_FONT_SIZE (deja la taille des
	# boutons de type Mur/Porte/etc.) comme SOURCE UNIQUE plutot que de
	# dupliquer un nombre : garantit que les deux listes restent identiques
	# par construction, pas par coincidence.
	for b in [btn_bois, btn_pierre, btn_terre]:
		b.add_theme_font_size_override("font_size", ActionMenuBarScript.SUBMENU_FONT_SIZE)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_setup_material_button_frame()


## Le materiau selectionne est encadre : bordure vive uniquement sur l'etat
## "pressed" (bouton selectionne), "draw_center = false" pour ne PAS
## remplacer le fond du bouton (evite de devoir deviner la couleur de fond
## exacte du theme Godot par defaut - voir
## [[feedback_bad_at_icon_geometry]] - juste un contour ajoute par-dessus).
## Les 3 boutons partagent la meme StyleBox (ressource partagee, pas d'etat
## par instance necessaire).
func _setup_material_button_frame() -> void:
	var frame_style := StyleBoxFlat.new()
	frame_style.draw_center = false
	frame_style.border_color = Color(1.0, 0.85, 0.2, 1.0)
	frame_style.set_border_width_all(4)
	frame_style.set_corner_radius_all(3)
	for b in [btn_bois, btn_pierre, btn_terre]:
		b.add_theme_stylebox_override("pressed", frame_style)


## "gris_minage"/"eau"/"detruire"/"escalier" delegue a TaskDefinitions (voir
## sa doc) pour ne jamais desynchroniser la couleur du fantome de
## previsualisation (ici) de celle du marqueur de tache une fois designee
## (ActionDragController.gd) - une seule source pour ces 4 couleurs. "bois"/
## "pierre"/"terre"/"interdire" restent ici : ce sont de VRAIS materiaux (ou
## un mode sans tache associee pour "interdire"), pas des couleurs de tache.
func _material_color(material: String) -> Color:
	match material:
		"bois":
			return Color(0.55, 0.38, 0.20)
		"pierre":
			return Color(0.60, 0.62, 0.66)
		"terre":
			return Color(0.35, 0.25, 0.15)
		"gris_minage":  # fantome de previsualisation pour Miner (voir _update_mine_drag_preview)
			return TaskDefinitionsScript.get_color("miner")
		"eau":  # bouton Puiser + fantome de previsualisation
			return TaskDefinitionsScript.get_color("puiser")
		"detruire":  # bouton/fantome/marqueur du mode Detruire
			return TaskDefinitionsScript.get_color("detruire")
		"interdire":  # bouton/fantome du mode Interdire
			return Color(0.15, 0.15, 0.15)
		"escalier":  # fantome/marqueur du geste de creusage d'escalier
			return TaskDefinitionsScript.get_color("escalier")
		_:
			return Color(1, 1, 1)


## Decoupee en sous-fonctions thematiques (_update_stats_label/
## _update_time_label/_update_climate_ui), meme ordre d'appel que si tout
## etait inline.
func _process(_delta: float) -> void:
	_update_stats_label()
	_update_time_label()
	_update_climate_ui()
	_update_hover_info_panel()
	inventory_ui.update(inventory)


## "Bois" reste le total utilisable pour construire, avec le detail par
## espece entre parentheses (chene/sapin/bouleau) a titre informatif.
## "Taches en attente" compte toute tache designee tant qu'elle n'est pas
## VRAIMENT terminee, pas seulement celles encore non-affectees dans
## TaskQueue - un nain qui a deja pris une tache (current_task) mais ne l'a
## pas encore finie compte donc aussi. task_queue.task_count() seul retombe
## a 0 des qu'un nain libre recupere la tache, meme avant d'etre arrive
## dessus.
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


## Horloge/calendrier - jour courant (DayNightCycle.day_count), heure
## deduite de time_of_day (0.0-1.0 -> 24h), et saison courante
## (SeasonSystem.current_season_id(), mise en forme avec capitalize() pour
## l'affichage - pas besoin d'une table de noms separee). Jour-du-mois et
## mois-de-la-saison sont deduits directement de day_night_cycle.day_count
## (pas besoin d'interroger season_system pour ca) - valable tant que
## SeasonSystem.season_duration_seconds reste un multiple exact de
## DayNightCycle.cycle_duration_seconds (voir commentaire dans
## SeasonSystem.gd). Temperature + episode climatique (vague de froid/
## canicule) completent l'affichage.
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


## Bandeau heure (degrade jour/nuit + icone soleil/lune + marqueur), bandeau
## saison (degrade 4 couleurs + marqueur de progression) et icone meteo -
## remplacent 3 anciennes pastilles de couleur unie. Appelee APRES
## _update_time_label (utilise time_label.text deja a jour comme tooltip,
## voir ClimateUI.update).
func _update_climate_ui() -> void:
	var season_id: String = season_system.current_season_id()
	var is_daylight: bool = day_night_cycle.is_daytime()
	var weather_label: String = weather_system.current_weather_label() if weather_system else ""
	climate_ui.update(season_id, is_daylight, day_night_cycle.time_of_day, season_system.season_progress(), weather_label, time_label.text)


## Remplace l'ancien schema "_select_mode/_on_mode_button_pressed" : quel que
## soit le bouton dont l'etat vient de changer (clic direct, ou consequence
## de l'exclusivite du groupe quand un AUTRE bouton devient enfonce), on
## relit simplement l'etat REEL du groupe via get_pressed_button() plutot que
## de recalculer une bascule a la main. Fonctionne aussi pour le "recliquer
## sur le mode actif le desactive" (allow_unpress = true, voir
## ActionMenuBarScript.build()) : dans ce cas get_pressed_button() renvoie
## null, donc Mode.NONE.
func _on_mode_button_toggled(_toggled_on: bool) -> void:
	var pressed_btn: BaseButton = mode_button_group.get_pressed_button()
	current_mode = MODE_BY_ID[pressed_btn.get_meta("mode_id")] if pressed_btn != null else Mode.NONE
	# Reinitialise toujours sur "Miner" en entrant dans le mode Creuser -
	# sans ca, "Escalier" restait selectionne d'une session a l'autre (le
	# ButtonGroup du sous-menu ne se remet pas a zero tout seul), source de
	# confusion (feedback Francois 2026-07-08). set_pressed_no_signal comme
	# au _ready() : pas besoin de re-declencher _on_miner_subtype_toggled
	# pour un etat qu'on met a jour nous-memes juste apres.
	if current_mode == Mode.MINER and miner_submenu_buttons.has("bloc"):
		miner_submenu_buttons["bloc"].set_pressed_no_signal(true)
		miner_subtype = "bloc"
	_update_buttons()


## Meme principe que _on_mode_button_toggled, pour le trio Bois/Pierre/Terre.
func _on_material_button_toggled(_toggled_on: bool) -> void:
	var pressed_btn: BaseButton = material_button_group.get_pressed_button()
	selected_material = pressed_btn.get_meta("material_id") if pressed_btn != null else ""
	_update_material_buttons()


## Meme principe que _on_mode_button_toggled, pour le sous-menu Creuser
## (Miner/Escalier). Un changement de sous-type EN COURS de geste escalier
## (raccourci clavier 1/2 presse au milieu d'un clic+molette+clic) annule le
## geste en cours plutot que de le laisser dans un etat incoherent.
func _on_miner_subtype_toggled(_toggled_on: bool) -> void:
	var pressed_btn: BaseButton = miner_subtype_group.get_pressed_button()
	var new_subtype: String = pressed_btn.get_meta("subtype_id") if pressed_btn != null else "bloc"
	if new_subtype != miner_subtype and stair_active:
		ActionDragControllerScript.cancel_stair(self)
	miner_subtype = new_subtype


## Depresse le bouton de mode actuellement enfonce (s'il y en a un) plutot
## que de forcer current_mode a Mode.NONE directement - necessaire depuis
## l'adoption de ButtonGroup : _update_buttons() ne reforce plus l'etat
## visuel de TOUS les boutons a chaque appel (Godot s'en charge lui-meme), un
## simple "current_mode = Mode.NONE" ailleurs (fin de glisser Miner/
## Construire/Puiser/Detruire, clic Annuler...) ne suffit donc plus a
## depresser visuellement le bouton - il faut explicitement toucher le
## bouton pour que Godot (et _on_mode_button_toggled, qui remettra
## current_mode a jour par ricochet) soit au courant. Utilisee par
## ActionDragController.gd (fin de selection) et la branche ANNULER
## ci-dessous.
func _reset_mode_selection() -> void:
	var pressed_btn: BaseButton = mode_button_group.get_pressed_button()
	if pressed_btn != null:
		pressed_btn.button_pressed = false
	else:
		current_mode = Mode.NONE
		_update_buttons()


func _update_buttons() -> void:
	material_box.visible = (current_mode == Mode.CONSTRUIRE)
	construire_submenu_box.visible = (current_mode == Mode.CONSTRUIRE)
	miner_submenu_box.visible = (current_mode == Mode.MINER)
	if current_mode == Mode.MINER:
		_position_miner_submenu()
	# L'etat du bouton "Mur" depend de selected_material, voir
	# _update_material_buttons() (seule fonction qui le met a jour desormais,
	# appelee a la fois ici et apres chaque clic materiau pour rester a jour
	# dans les deux sens) : impossible de selectionner le type Mur tant
	# qu'un materiau n'est pas choisi.
	_update_material_buttons()
	# Miner/Puiser/Detruire/Interdire utilisent tous le meme rectangle
	# "monde" que Construire (voir _on_left_press/_update_drag/
	# _on_left_release) - ne pas annuler leur glisser en cours en changeant
	# de bouton visuel.
	if current_mode != Mode.CONSTRUIRE and current_mode != Mode.MINER and current_mode != Mode.PUISER and current_mode != Mode.DETRUIRE and current_mode != Mode.INTERDIRE:
		_cancel_drag()
	# Quitter Mode.MINER (quel qu'en soit le sous-type) annule un geste
	# escalier en cours - sinon stair_active resterait vrai alors que le
	# sous-menu correspondant a disparu.
	if current_mode != Mode.MINER and stair_active:
		ActionDragControllerScript.cancel_stair(self)
	# Le panneau d'inspection est permanent (mis a jour par survol, voir
	# _update_hover_info_panel) - plus besoin de le cacher en changeant de
	# mode.
	_update_cursor()


## Aligne le bord gauche du sous-menu Creuser sur celui du VRAI bouton
## "Creuser" (mode_buttons["MINER"]) - contrairement au sous-menu Construire
## (position fixe dans Main.tscn : Construire est le 1er bouton de la
## rangee, avec MaterialBox juste a cote), Creuser est le 4e bouton : sa
## position ecran depend de la largeur cumulee des 3 boutons precedents,
## pas calculable a la main de facon fiable (voir
## [[feedback_bad_at_icon_geometry]], meme prudence pour un pixel devine que
## pour une forme dessinee a la main) - on la lit directement sur le bouton
## une fois qu'il est reellement en place, plutot que de deviner un offset
## fixe dans la scene. global_position (coordonnees ecran) plutot que
## position (relative a un parent different pour le bouton - mode_box - et
## pour le sous-menu - ActionUI) : les deux ont un parent CanvasLayer sans
## transformation propre, donc position ecran = position locale pour les
## deux, mais rester en coordonnees ecran evite toute ambiguite.
func _position_miner_submenu() -> void:
	if mode_buttons.has("MINER"):
		miner_submenu_box.global_position.x = mode_buttons["MINER"].global_position.x


## Applique la texture de curseur correspondant a current_mode (ou restaure
## le curseur systeme en Mode.NONE), pour que le curseur change de forme
## selon le mode. MODE_BY_ID mappe id (String) -> Mode (int) ; on en a besoin
## dans l'autre sens ici, d'ou la petite boucle (pas de dictionnaire inverse
## tenu a jour ailleurs, la table ne bouge pas a l'execution donc le cout est
## negligeable).
func _update_cursor() -> void:
	if current_mode == Mode.NONE:
		Input.set_custom_mouse_cursor(null)
		return
	for mode_id in MODE_BY_ID:
		if MODE_BY_ID[mode_id] == current_mode:
			var tex: ImageTexture = cursor_textures.get(mode_id)
			if tex != null:
				Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, Vector2(1, 1))
			return


## "mur" (seul type de construction reellement code, voir
## ActionMenuBarScript) suit l'etat de selected_material - grise/desactive/
## depresse tant qu'aucun materiau n'est choisi, actif+coche des qu'un
## materiau l'est. selected_material n'est JAMAIS reinitialise ailleurs dans
## ce fichier (persiste tel quel d'un passage en mode Construire a l'autre) -
## "le dernier materiau selectionne est selectionne par defaut" est donc deja
## garanti par cette absence de reset, ce bouton se contente de refleter
## fidelement cet etat existant. Ne pilote plus btn_bois/pierre/terre
## eux-memes (Godot le fait via material_button_group, voir
## _on_material_button_toggled) - reste uniquement la logique "Mur", qui n'a
## pas d'equivalent natif Godot (elle depend d'un etat EXTERNE au groupe).
func _update_material_buttons() -> void:
	if construire_type_buttons.has("mur"):
		var mur_btn: Button = construire_type_buttons["mur"]
		var has_material: bool = selected_material != ""
		mur_btn.button_pressed = has_material
		mur_btn.disabled = not has_material
		mur_btn.tooltip_text = "" if has_material else "Choisissez d'abord un materiau"
		mur_btn.modulate = Color(1, 1, 1, 1) if has_material else Color(1, 1, 1, 0.45)


## Le bloc raccourcis clavier est extrait dans _handle_time_shortcuts().
func _unhandled_input(event: InputEvent) -> void:
	if _handle_time_shortcuts(event):
		return
	if _handle_mode_shortcuts(event):
		return
	if _handle_miner_subtype_shortcuts(event):
		return
	if _handle_mode_exit(event):
		return

	# Mode ANNULER : simple clic gauche, pas de glisser (contrairement a
	# Miner/Construire/Puiser) - annule la tache la plus proche du clic
	# (marqueur ou fantome de construction) puis revient a Mode.NONE, meme
	# convention que Couper/Cueillir apres un clic simple.
	if current_mode == Mode.ANNULER:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_annuler_click(event.position)
			# Depresse le bouton "Annuler" plutot que de forcer current_mode
			# a la main - voir _reset_mode_selection.
			_reset_mode_selection()
		return

	# Mode.NONE (inspecter/selectionner des nains), Mode.COUPER et
	# Mode.CUEILLIR partagent la meme mecanique clic-ou-glisser (voir
	# _on_select_press/_update_select_drag/_on_select_release) - un clic
	# simple cible un seul objet (comme avant), un glisser au-dela de
	# SELECT_DRAG_THRESHOLD selectionne tous les arbres/buissons du
	# rectangle.
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

	# Mode.MINER + sous-type "escalier" : geste clic+molette+clic dedie
	# (colonne unique, PAS un rectangle) - voir doc de stair_active plus haut
	# et ActionDragController.on_stair_click/extend_stair_gesture. Verifie
	# AVANT le "reste" ci-dessous, qui traite Mode.MINER en rectangle
	# (sous-type "bloc", comportement historique).
	if current_mode == Mode.MINER and miner_subtype == "escalier":
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			ActionDragControllerScript.on_stair_click(self, event.position)
		elif stair_active and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			ActionDragControllerScript.extend_stair_gesture(self, 1)
			get_viewport().set_input_as_handled()
		elif stair_active and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			ActionDragControllerScript.extend_stair_gesture(self, -1)
			get_viewport().set_input_as_handled()
		return

	# Reste : Mode.MINER (sous-type "bloc") et Mode.CONSTRUIRE, tous deux
	# bases sur un rectangle "monde" de cases de grille (voir is_dragging/
	# drag_start/drag_end).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_press(event.position)
		else:
			_on_left_release()
	elif event is InputEventMouseMotion and is_dragging:
		_update_drag(event.position)


## Raccourcis clavier pour choisir un mode d'action - B=Construire,
## C=Couper, U=Cueillir, M=Creuser(Miner), P=Puiser (voir
## ActionMenuBarScript.MODE_ENTRIES, source unique de cette correspondance).
## Meme structure que _handle_time_shortcuts ci-dessous (verifie juste apres
## lui, avant la logique par mode) - physical_keycode plutot que keycode pour
## rester sur les memes touches physiques quelle que soit la disposition
## clavier (meme choix que CameraRig.gd pour WASD/QE). Bascule directement le
## bouton correspondant (button_pressed = not button_pressed) au lieu de
## piloter current_mode directement - assigner button_pressed emet "toggled"
## comme un vrai clic (comportement standard Godot, sauf avec
## set_pressed_no_signal()), donc _on_mode_button_toggled se declenche et
## remet current_mode a jour par le meme chemin qu'un clic souris. ButtonGroup
## gere alors lui-meme l'exclusivite si on VIENT d'enfoncer ce bouton (les
## autres se depressent automatiquement) - inverser manuellement ici
## reproduit aussi le "reappuyer sur le raccourci du mode actif le
## desactive" (equivalent clavier de allow_unpress, qui ne couvre que le
## clic souris/tactile).
func _handle_mode_shortcuts(event: InputEvent) -> bool:
	return ActionShortcutsScript.handle_mode_shortcuts(self, event)


## Raccourcis 1/2 pour choisir le sous-type de Creuser (Miner/Escalier) -
## uniquement actifs quand Mode.MINER est deja le mode courant (contrairement
## a _handle_mode_shortcuts ci-dessus, qui marche depuis n'importe quel
## mode). Contrairement au groupe de mode principal, ce sous-menu n'a pas
## d'allow_unpress (un sous-type reste toujours selectionne) - un simple
## button_pressed = true suffit donc, pas de bascule.
func _handle_miner_subtype_shortcuts(event: InputEvent) -> bool:
	return ActionShortcutsScript.handle_miner_subtype_shortcuts(self, event)


## Sortir du mode par Esc ou clic droit : quel que soit le mode d'action
## actif (hors Mode.NONE, ou il n'y a rien a annuler), Echap ou un clic
## droit annule un eventuel glisser en cours (_cancel_drag pour Miner/
## Construire/Puiser/Detruire/Interdire, le rectangle ecran de Couper/
## Cueillir gere a part juste en-dessous - deux mecaniques de glisser
## distinctes, voir doc d'ActionDragController.gd) puis depresse le bouton de
## mode actif (_reset_mode_selection, meme chemin que la fin normale d'une
## selection). Verifiee ICI, avant toute logique specifique a un mode, pour
## rester valable quel que soit le mode courant - meme position que
## _handle_mode_shortcuts ci-dessus. set_input_as_handled() evite qu'un clic
## droit "fuite" vers autre chose (ex: la camera) le meme frame.
func _handle_mode_exit(event: InputEvent) -> bool:
	return ActionShortcutsScript.handle_mode_exit(self, event)


## Raccourcis clavier pour le controle du temps - Espace=pause, F1=vitesse
## normale, F2=accelere, F3=rapide. Verifies AVANT la logique par mode de
## _unhandled_input pour rester actifs quel que soit le mode d'action en
## cours (Miner/Construire/etc). Renvoie true si l'evenement a ete consomme
## (l'appelant doit alors return).
func _handle_time_shortcuts(event: InputEvent) -> bool:
	return ActionShortcutsScript.handle_time_shortcuts(self, event)


## Glisser/selection/creation de taches - simples delegations vers
## ActionDragController.gd (voir sa doc).
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


## Simple delegation, voir ActionDragControllerScript.on_annuler_click.
func _on_annuler_click(screen_pos: Vector2) -> void:
	ActionDragControllerScript.on_annuler_click(self, screen_pos)


## Retire le mur fantome correspondant une fois la tache de construction
## terminee - simple delegation, connectee au signal Dwarf.build_task_finished
## dans _ready() ci-dessus.
func _on_build_task_finished(task_id: int, bx: int, bz: int) -> void:
	ActionDragControllerScript.on_build_task_finished(self, task_id, bx, bz)


## Retire l'icone temporaire d'une tache terminee - simple delegation,
## connectee au signal Dwarf.task_finished dans _ready() ci-dessus.
func _on_task_finished(task_id: int) -> void:
	ActionDragControllerScript.on_task_finished(self, task_id)


## Inspection/survol - simples delegations vers ActionInspector.gd (voir sa
## doc).
func _handle_inspect_click(screen_pos: Vector2) -> void:
	ActionInspectorScript.handle_inspect_click(self, screen_pos)


func _update_hover_info_panel() -> void:
	ActionInspectorScript.update_hover_info_panel(self)
