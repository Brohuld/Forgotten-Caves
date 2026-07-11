extends RefCounted
## Raccourcis clavier (choix de mode, sous-type Creuser, sortie de mode,
## controle du temps) - extrait de ActionController.gd (revue de code C26,
## 2026-07-11 : fichier a 833 lignes, aucune violation SOLID nette
## identifiee par la revue, mais Francois a demande un decoupage partiel
## quand meme).
##
## Fonctions statiques : "controller" recoit le ActionController via
## parametre (meme motif que ActionDragController.gd/Model3DUtils.gd) au
## lieu d'un "self" implicite ; champs lus/ecrits via controller.get()/
## controller.set() (type generique CanvasLayer, evite un preload
## circulaire avec ActionController.gd). Enum Mode duplique ci-dessous
## (meme raison/meme risque documente que dans ActionDragController.gd - a
## garder synchronise si l'original change).

const ActionMenuBarScript := preload("res://scripts/systemes/ActionMenuBar.gd")
const ActionDragControllerScript := preload("res://scripts/systemes/ActionDragController.gd")

enum Mode { NONE, MINER, COUPER, CONSTRUIRE, CUEILLIR, PUISER, ANNULER, DETRUIRE, INTERDIRE }


## Raccourcis clavier pour choisir un mode d'action - voir
## ActionController._handle_mode_shortcuts pour le detail complet (B/C/U/M/P,
## touche physique, bascule via button_pressed pour declencher "toggled"
## comme un vrai clic).
static func handle_mode_shortcuts(controller: CanvasLayer, event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		var mode_id: String = ActionMenuBarScript.mode_for_shortcut(event.physical_keycode)
		if mode_id != "":
			var mode_buttons: Dictionary = controller.get("mode_buttons")
			var btn: Button = mode_buttons[mode_id]
			btn.button_pressed = not btn.button_pressed
			return true
	return false


## Raccourcis 1/2 pour le sous-type de Creuser (Miner/Escalier), uniquement
## actifs en Mode.MINER - voir
## ActionController._handle_miner_subtype_shortcuts pour le detail complet.
static func handle_miner_subtype_shortcuts(controller: CanvasLayer, event: InputEvent) -> bool:
	if controller.get("current_mode") != Mode.MINER:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		var subtype_id: String = ActionMenuBarScript.miner_subtype_for_shortcut(event.physical_keycode)
		if subtype_id != "":
			var miner_submenu_buttons: Dictionary = controller.get("miner_submenu_buttons")
			miner_submenu_buttons[subtype_id].button_pressed = true
			return true
	return false


## Sortir du mode par Esc ou clic droit - voir
## ActionController._handle_mode_exit pour le detail complet (annule glisser
## + escalier + selection en cours, depresse le bouton de mode actif).
static func handle_mode_exit(controller: CanvasLayer, event: InputEvent) -> bool:
	if controller.get("current_mode") == Mode.NONE:
		return false
	var is_escape: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	var is_right_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	if is_escape or is_right_click:
		ActionDragControllerScript.cancel_drag(controller)
		if controller.get("stair_active"):
			ActionDragControllerScript.cancel_stair(controller)
		if controller.get("_select_dragging_active"):
			controller.set("_select_dragging_active", false)
			controller.set("_select_button_down", false)
			var select_box: Panel = controller.get("_select_box")
			select_box.visible = false
		controller.call("_reset_mode_selection")
		controller.get_viewport().set_input_as_handled()
		return true
	return false


## Raccourcis clavier pour le controle du temps - voir
## ActionController._handle_time_shortcuts pour le detail complet
## (Espace=pause, F1=x1, F2=x2, F3=x4).
static func handle_time_shortcuts(controller: CanvasLayer, event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		var climate_ui = controller.get("climate_ui")
		match event.keycode:
			KEY_SPACE:
				climate_ui.toggle_pause()
				controller.get_viewport().set_input_as_handled()
				return true
			KEY_F1:
				climate_ui.on_time_speed_pressed(1.0)
				controller.get_viewport().set_input_as_handled()
				return true
			KEY_F2:
				climate_ui.on_time_speed_pressed(2.0)
				controller.get_viewport().set_input_as_handled()
				return true
			KEY_F3:
				climate_ui.on_time_speed_pressed(4.0)
				controller.get_viewport().set_input_as_handled()
				return true
	return false
