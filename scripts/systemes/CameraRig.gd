extends Node3D
## Camera controlable :
## - Deplacement (pan) : ZQSD (touches physiques Z/Q/S/D sur clavier francais)
## - Rotation : touches A et E (Q est deja pris par le deplacement, donc pas de Q/E)
## - Zoom : touches + et -, ou Ctrl+molette
## - Changement de niveau de profondeur : molette de la souris (sans Ctrl)
## - Angle de vue (pitch + rotation) : maintenir le clic molette (bouton du
##   milieu) et glisser la souris (horizontal = rotation, vertical = pitch)
##
## Chaque changement de niveau demande a VoxelWorld de reveler une coupe
## horizontale complete du niveau vise (voir VoxelWorld.set_view_level) -
## sans ca, changer de niveau ne ferait que deplacer la camera en Y, sans
## rien cacher du terrain (inutile pour "voir" un niveau souterrain, puisque
## tout est plein autour).

const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")

@export var move_speed: float = 12.0
@export var rotate_step_deg: float = 45.0
@export var zoom_speed: float = 3.0
@export var min_distance: float = 8.0
@export var max_distance: float = 60.0
@export var pitch_sensitivity: float = 0.2   # degres par pixel de glissement (vertical)
@export var yaw_sensitivity: float = 0.3     # degres par pixel de glissement (horizontal)
@export var min_pitch_deg: float = 10.0
@export var max_pitch_deg: float = 85.0

## Lit directement VoxelWorld.HEIGHT (source unique) au lieu d'un nombre
## duplique en dur derriere un @export.
const grid_height := VoxelWorldScript.HEIGHT
## Doit correspondre a VoxelWorld.VIEW_LEVEL_MARGIN_ABOVE - permet de monter
## au-dessus du niveau 0 (relief).
@export var view_level_margin_above: int = 15
## Doit correspondre a VoxelWorld.hill_amplitude pour que la camera demarre
## assez haut pour voir le sommet des collines.
@export var hill_amplitude: float = 3.0

var current_level: int = 49  # sommet de la carte (grid_height - 1), ajuste en _ready()
var camera_distance: float = 16.0
var pitch_deg: float = 35.0
var is_middle_dragging: bool = false

@onready var camera: Camera3D = $Camera3D
@onready var voxel_world: Node3D = %VoxelWorld
## Memes noeuds que VoxelWorld ci-dessus, notifies a chaque changement de
## niveau de vue (voir _update_view_level plus bas) - les arbres/buissons/
## cascades doivent disparaitre avec leur niveau, comme les rivieres
## elles-memes.
@onready var forest: Node3D = %Forest
@onready var berry_bushes: Node3D = %BerryBushes
@onready var waterfall_shapes: Node3D = %WaterfallShapes
@onready var waterfall_streaks: Node3D = %WaterfallStreaks
@onready var waterfall_foam_clouds: Node3D = %WaterfallFoamClouds
## Les decorations (fleurs etc.) doivent aussi disparaitre en descendant de
## niveau.
@onready var ground_decoration: Node3D = %GroundDecoration
var level_label: Label
## Reference au Tween de rotation en cours, pour pouvoir l'arreter avant
## d'en lancer un nouveau si l'utilisateur presse A/E rapidement plusieurs
## fois - voir _rotate_step().
var _rotate_tween: Tween


func _ready() -> void:
	# Demarre au-dessus du sommet des collines les plus hautes, sinon la vue
	# par defaut cache leur sommet (meme logique que VoxelWorld._ready, qui
	# calcule son view_level de la meme facon).
	current_level = grid_height - 1 + int(ceil(hill_amplitude))
	global_position.y = float(current_level)
	_update_camera_offset()
	_create_ui()
	_update_label()
	_update_view_level()


func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	level_label = Label.new()
	level_label.position = Vector2(16, 16)
	level_label.add_theme_font_size_override("font_size", 28)
	canvas.add_child(level_label)


func _process(delta: float) -> void:
	var input_dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_D):
		input_dir.x += 1
	if Input.is_physical_key_pressed(KEY_A):  # touche Q sur clavier francais
		input_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_W):  # touche Z sur clavier francais
		input_dir.z -= 1
	if Input.is_physical_key_pressed(KEY_S):
		input_dir.z += 1

	if input_dir != Vector3.ZERO:
		input_dir = input_dir.normalized()
		var move: Vector3 = transform.basis * input_dir
		move.y = 0
		global_position += move * move_speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Rotation : touches A et E (physiques). Q etant deja pris par le
		# deplacement (ZQSD), on utilise A (a cote) pour eviter le conflit.
		if event.physical_keycode == KEY_Q:
			_rotate_step(rotate_step_deg)
		elif event.physical_keycode == KEY_E:
			_rotate_step(-rotate_step_deg)
		elif event.physical_keycode == KEY_EQUAL or event.physical_keycode == KEY_KP_ADD:
			camera_distance = clamp(camera_distance - zoom_speed, min_distance, max_distance)
			_update_camera_offset()
		elif event.physical_keycode == KEY_MINUS or event.physical_keycode == KEY_KP_SUBTRACT:
			camera_distance = clamp(camera_distance + zoom_speed, min_distance, max_distance)
			_update_camera_offset()

	if event is InputEventMouseButton:
		# Ctrl+molette zoome (meme logique que +/-) au lieu de changer de
		# niveau. Verifie ctrl_pressed AVANT de traiter la molette comme un
		# changement de niveau, pour que les deux usages restent bien
		# separes (molette seule = niveau, Ctrl+molette = zoom).
		if event.pressed and event.ctrl_pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = clamp(camera_distance - zoom_speed, min_distance, max_distance)
			_update_camera_offset()
		elif event.pressed and event.ctrl_pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = clamp(camera_distance + zoom_speed, min_distance, max_distance)
			_update_camera_offset()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Sur trackpad Mac (defilement "naturel", reglage par defaut du
			# systeme), scroller vers le BAS envoie l'evenement WHEEL_UP a
			# Godot, pas WHEEL_DOWN - les deux branches sont donc inversees
			# par rapport a une simple lecture "UP = monter" pour
			# correspondre au ressenti reel du trackpad.
			current_level = clampi(current_level - 1, 0, grid_height - 1 + view_level_margin_above)
			global_position.y = float(current_level)
			_update_label()
			_update_view_level()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_level = clampi(current_level + 1, 0, grid_height - 1 + view_level_margin_above)
			global_position.y = float(current_level)
			_update_label()
			_update_view_level()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_middle_dragging = event.pressed

	if event is InputEventMouseMotion and is_middle_dragging:
		pitch_deg = clamp(pitch_deg + event.relative.y * pitch_sensitivity, min_pitch_deg, max_pitch_deg)
		rotate_y(deg_to_rad(-event.relative.x * yaw_sensitivity))
		_update_camera_offset()


## rotate_y() applique un saut de 45° INSTANTANE (aucune interpolation),
## ressenti comme brutal - anime donc la rotation sur une courte duree via un
## Tween plutot qu'un saut immediat.
func _rotate_step(delta_deg: float) -> void:
	# Arrete le Tween de rotation precedent s'il tourne encore (pressions
	# rapides de A/E) avant d'en lancer un nouveau - evite deux Tweens
	# concurrents sur "rotation:y".
	if _rotate_tween != null and _rotate_tween.is_valid():
		_rotate_tween.kill()
	_rotate_tween = create_tween()
	_rotate_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_rotate_tween.tween_property(self, "rotation:y", rotation.y + deg_to_rad(delta_deg), 0.25)


func _update_camera_offset() -> void:
	var pitch := deg_to_rad(pitch_deg)
	var horizontal := camera_distance * cos(pitch)
	camera.position = Vector3(0, camera_distance * sin(pitch), horizontal)
	camera.look_at(global_position, Vector3.UP)


## Repercute le niveau courant sur VoxelWorld pour que le terrain au-dessus
## soit reellement cache (voir VoxelWorld.set_view_level). Sans filet
## particulier si voxel_world est introuvable (%VoxelWorld) : ca ne devrait
## pas arriver dans la scene actuelle, mais on evite un crash au cas ou.
func _update_view_level() -> void:
	if voxel_world != null and voxel_world.has_method("set_view_level"):
		voxel_world.set_view_level(current_level)
	# Meme notification pour les arbres/buissons/cascades (voir Forest.gd/
	# BerryBushes.gd/WaterfallShapes.gd/WaterfallStreaks.gd/
	# WaterfallFoamClouds.gd/update_view_level) - une boucle sur ce tableau
	# remplace 6 blocs "if X != null and X.has_method(...):
	# X.update_view_level(...)" quasi identiques, pour n'avoir qu'un seul
	# endroit a modifier si un 7e noeud decoratif doit s'y ajouter.
	var view_level_nodes: Array = [
		forest, berry_bushes, waterfall_shapes, waterfall_streaks,
		waterfall_foam_clouds, ground_decoration,
	]
	for node in view_level_nodes:
		if node != null and node.has_method("update_view_level"):
			# is_node_ready() evite d'appeler update_view_level() sur un
			# noeud dont le _ready() n'est pas encore termine (ordre
			# d'execution entre noeuds freres non garanti) - avertit plutot
			# que d'echouer silencieusement sur un etat interne pas encore
			# initialise.
			if not node.is_node_ready():
				push_warning("CameraRig._update_view_level : %s n'est pas encore pret (_ready() non termine), appel ignore cette fois." % node.name)
				continue
			# is_node_ready() devient VRAI des qu'un noeud entre dans
			# l'arbre de scene, MEME SI son _ready() est encore en pause sur
			# un "await" (Forest/BerryBushes/GroundDecoration generent par
			# paquets, voir leur BATCH_SIZE) - ne suffit donc pas a garantir
			# que la generation est reellement terminee
			# (mmi.multimesh.instance_count reste a 0 jusqu'a la toute fin
			# de leur generation). Verifie donc aussi generation_done si le
			# noeud l'expose - get() renvoie null (donc jamais egal a
			# "false") pour les noeuds qui n'ont pas cette propriete
			# (cascades), jamais bloquant pour eux.
			if node.get("generation_done") == false:
				push_warning("CameraRig._update_view_level : %s encore en cours de generation, appel ignore cette fois." % node.name)
				continue
			node.update_view_level(current_level)


## current_level est stocke en interne comme la coordonnee Y reelle de la
## grille (0 = fond de pierre, grid_height-1 = surface). Pour l'affichage,
## on le convertit pour que 0 = surface et les niveaux en dessous (sous-sol,
## a miner) s'affichent en negatif, ce qui correspond a l'intuition du joueur.
func _update_label() -> void:
	if level_label:
		var displayed_level := current_level - (grid_height - 1)
		var suffix := ""
		if displayed_level == 0:
			suffix = " (surface)"
		elif displayed_level < 0:
			suffix = " (sous-sol)"
		else:
			# Niveaux au-dessus de la surface actuelle, prets pour un futur
			# relief (rien n'y est encore genere).
			suffix = " (relief)"
		level_label.text = "Niveau : %d%s" % [displayed_level, suffix]
