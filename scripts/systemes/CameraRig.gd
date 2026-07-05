extends Node3D
## Sprint 2 : camera controlable.
## - Deplacement (pan) : ZQSD (touches physiques Z/Q/S/D sur clavier francais)
## - Rotation : touches A et E (Q est deja pris par le deplacement, donc pas de Q/E)
## - Zoom : touches + et -, ou Ctrl+molette (Sprint 35bis, demande explicite)
## - Changement de niveau de profondeur : molette de la souris (sans Ctrl)
## - Angle de vue (pitch + rotation) : maintenir le clic molette (bouton du
##   milieu) et glisser la souris (horizontal = rotation, vertical = pitch)
## Sprint 23bis : le changement de niveau ne faisait jusqu'ici que deplacer la
## camera en Y, sans rien cacher du terrain - inutile pour "voir" un niveau
## souterrain puisque tout est plein autour. Chaque changement de niveau
## demande maintenant a VoxelWorld de reveler une coupe horizontale complete
## du niveau vise (voir VoxelWorld.set_view_level).

## 2026-07-05 (revue de code, item F010) : uniquement pour le garde-fou de
## _ready() ci-dessous (grid_height doit rester synchronise avec
## VoxelWorldScript.HEIGHT, duplique ici en dur pour l'@export ci-dessous).
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

# Doivent correspondre aux constantes de VoxelWorld.gd
@export var grid_height: int = 50  # 2026-07-03 : 30 -> 50 (map resize)
# Sprint 37octies (2026-07-04, demande explicite : "les niveaux geres par la
# molette doivent permettre de monter au dessus de 0, on aura des reliefs dans
# le futur") - doit correspondre a VoxelWorld.VIEW_LEVEL_MARGIN_ABOVE.
@export var view_level_margin_above: int = 15
# Sprint 38 (2026-07-04, reliefs) : doit correspondre a VoxelWorld.hill_amplitude
# pour que la camera demarre assez haut pour voir le sommet des collines.
@export var hill_amplitude: float = 3.0

var current_level: int = 49  # sommet de la carte (grid_height - 1), ajuste en _ready()
var camera_distance: float = 16.0
var pitch_deg: float = 35.0
var is_middle_dragging: bool = false

@onready var camera: Camera3D = $Camera3D
@onready var voxel_world: Node3D = %VoxelWorld
# Sprint 85 (2026-07-04, demande explicite : "les arbres/buissons/cascades
# doivent disparaitre avec leur niveau, comme les rivieres elles memes") -
# memes noeuds que VoxelWorld ci-dessus, notifies a chaque changement de
# niveau de vue (voir _update_view_level plus bas).
@onready var forest: Node3D = %Forest
@onready var berry_bushes: Node3D = %BerryBushes
@onready var waterfall_shapes: Node3D = %WaterfallShapes
@onready var waterfall_streaks: Node3D = %WaterfallStreaks
@onready var waterfall_foam_clouds: Node3D = %WaterfallFoamClouds
# Sprint 87 (2026-07-04, demande explicite : "les decorations (fleurs etc)
# doivent disparaitre aussi" en descendant de niveau).
@onready var ground_decoration: Node3D = %GroundDecoration
var level_label: Label


func _ready() -> void:
	# 2026-07-05 (revue de code, item F010) : grid_height est duplique en dur
	# (aucune garde-fou automatique auparavant si VoxelWorld.HEIGHT changeait
	# sans repercuter partout) - avertissement si desynchronise, sans changer
	# le comportement (grid_height reste la valeur utilisee ci-dessous).
	if grid_height != VoxelWorldScript.HEIGHT:
		push_warning("CameraRig.grid_height (%d) desynchronise de VoxelWorld.HEIGHT (%d)" % [grid_height, VoxelWorldScript.HEIGHT])
	# Sprint 38 (reliefs) : demarre au-dessus du sommet des collines les plus
	# hautes, sinon la vue par defaut cache leur sommet (meme logique que
	# VoxelWorld._ready, qui calcule son view_level de la meme facon).
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
		# Sprint 35bis (2026-07-03) : Ctrl+molette zoome (meme logique que
		# +/-) au lieu de changer de niveau - demande explicite. Verifie
		# ctrl_pressed AVANT de traiter la molette comme un changement de
		# niveau, pour que les deux usages restent bien separes (molette
		# seule = niveau, Ctrl+molette = zoom).
		if event.pressed and event.ctrl_pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = clamp(camera_distance - zoom_speed, min_distance, max_distance)
			_update_camera_offset()
		elif event.pressed and event.ctrl_pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = clamp(camera_distance + zoom_speed, min_distance, max_distance)
			_update_camera_offset()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Sprint 36bis (2026-07-03) : instrumentation de diagnostic (voir
			# memoire) a confirme que sur trackpad Mac (defilement "naturel",
			# reglage par defaut du systeme), scroller vers le BAS envoie
			# l'evenement WHEEL_UP a Godot, pas WHEEL_DOWN - le code d'origine
			# (WHEEL_UP = monter) faisait donc l'inverse de ce que l'utilisateur
			# attendait, et restait bloque a la surface. Les deux branches sont
			# desormais inversees pour correspondre au ressenti reel du trackpad.
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


## Sprint 60 (2026-07-04, signale par Francois : "la rotation A/E est trop
## brusque") : rotate_y() applique un saut de 45° INSTANTANE (aucune
## interpolation), ressenti comme brutal. Anime desormais la rotation sur une
## courte duree via un Tween plutot qu'un saut immediat.
func _rotate_step(delta_deg: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation:y", rotation.y + deg_to_rad(delta_deg), 0.25)


func _update_camera_offset() -> void:
	var pitch := deg_to_rad(pitch_deg)
	var horizontal := camera_distance * cos(pitch)
	camera.position = Vector3(0, camera_distance * sin(pitch), horizontal)
	camera.look_at(global_position, Vector3.UP)


## Sprint 23bis : repercute le niveau courant sur VoxelWorld pour que le
## terrain au-dessus soit reellement cache (voir VoxelWorld.set_view_level).
## Sans filet particulier si voxel_world est introuvable (%VoxelWorld) : ca ne
## devrait pas arriver dans la scene actuelle, mais on evite un crash au cas ou.
func _update_view_level() -> void:
	if voxel_world != null and voxel_world.has_method("set_view_level"):
		voxel_world.set_view_level(current_level)
	# Sprint 85 : meme notification pour les arbres/buissons/cascades (voir
	# Forest.gd/BerryBushes.gd/WaterfallShapes.gd/WaterfallStreaks.gd/
	# WaterfallFoamClouds.gd/update_view_level).
	# 2026-07-05 (revue de code, item F028) : les 6 blocs "if X != null and
	# X.has_method(...): X.update_view_level(...)" quasi identiques sont
	# remplaces par une boucle sur ce tableau - meme comportement exact, mais
	# un seul endroit a modifier si un 7e noeud decoratif doit s'y ajouter.
	var view_level_nodes: Array = [
		forest, berry_bushes, waterfall_shapes, waterfall_streaks,
		waterfall_foam_clouds, ground_decoration,
	]
	for node in view_level_nodes:
		if node != null and node.has_method("update_view_level"):
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
			# Sprint 37octies : niveaux au-dessus de la surface actuelle, prets
			# pour un futur relief (rien n'y est encore genere).
			suffix = " (relief)"
		level_label.text = "Niveau : %d%s" % [displayed_level, suffix]
