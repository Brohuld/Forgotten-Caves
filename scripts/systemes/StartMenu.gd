extends Control
## Ecran affiche avant Main.tscn (voir project.godot, run/main_scene) : un
## champ pour taper une graine (seed) precise, ou le laisser vide pour une
## carte aleatoire comme avant. Une graine FIXE est donnee a la main, pas
## juste "reprendre la derniere carte automatiquement" - la meme graine
## tapee deux fois doit toujours produire exactement la meme carte (relief/
## lacs/riviere/cascades identiques), utile pour reproduire un bug precis a
## volonte pendant les tests.
##
## Construit entierement par code (aucun noeud dans StartMenu.tscn), meme
## convention que les autres UI de ce projet (ActionController.gd,
## CharacterSheetUI.gd) - evite tout risque d'erreur de syntaxe .tscn pour
## une interface simple.
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")

## La derniere graine utilisee est sauvegardee dans ce petit fichier (dossier
## de sauvegarde du jeu, "user://" - persiste entre les lancements,
## contrairement a une variable en memoire) et relue au prochain demarrage
## pour pre-remplir le champ - un nouveau nombre aleatoire n'est genere QUE
## la toute premiere fois (aucune sauvegarde encore presente).
const LAST_SEED_PATH := "user://last_seed.txt"

## Plage de la graine aleatoire par defaut.
const DEFAULT_SEED_RANGE := 1000000

var seed_input: LineEdit


func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0

	_build_background()
	var box: VBoxContainer = _build_panel()
	_build_title(box)
	_build_seed_field(box)
	_build_launch_button(box)
	_build_note(box)


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.12, 0.16)
	bg.anchor_left = 0.0
	bg.anchor_top = 0.0
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)


## Cree le panneau central + son conteneur vertical, et retourne ce dernier
## pour que les autres _build_*() y ajoutent leurs elements.
func _build_panel() -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = -110
	panel.offset_bottom = 110
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.18, 0.20, 0.26)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	return box


func _build_title(box: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Forgotten Caves"
	title.add_theme_font_size_override("font_size", 35)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)


func _build_seed_field(box: VBoxContainer) -> void:
	var hint := Label.new()
	hint.text = "Graine de la carte (laisser vide = carte aleatoire) :"
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	seed_input = LineEdit.new()
	seed_input.placeholder_text = "ex: 12345"
	seed_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_input.custom_minimum_size = Vector2(200, 0)
	seed_input.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Le champ n'est pas vide au demarrage, il propose deja un nombre
	# aleatoire, modifiable ou effacable. Cette valeur par defaut est la
	# DERNIERE graine utilisee (voir LAST_SEED_PATH), pas un nouveau nombre a
	# chaque fois - un nombre aleatoire n'est genere que s'il n'existe encore
	# aucune sauvegarde (tout premier lancement).
	randomize()
	var last_seed: String = _load_last_seed()
	seed_input.text = last_seed if not last_seed.is_empty() else str(randi() % DEFAULT_SEED_RANGE)
	# N'accepte que des chiffres (une graine est toujours un nombre entier).
	seed_input.text_changed.connect(_on_seed_text_changed)
	box.add_child(seed_input)


func _build_launch_button(box: VBoxContainer) -> void:
	var launch_button := Button.new()
	launch_button.text = "Lancer la partie"
	launch_button.custom_minimum_size = Vector2(200, 40)
	launch_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	launch_button.pressed.connect(_on_launch_pressed)
	box.add_child(launch_button)


func _build_note(box: VBoxContainer) -> void:
	var note := Label.new()
	note.text = "La graine utilisee sera affichee dans la console Godot."
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(note)


## Filtre la saisie pour ne garder que des chiffres (evite un texte invalide
## au moment de lancer la partie).
func _on_seed_text_changed(new_text: String) -> void:
	var filtered := ""
	for c in new_text:
		if c >= "0" and c <= "9":
			filtered += c
	if filtered != new_text:
		seed_input.text = filtered
		seed_input.caret_column = filtered.length()


func _on_launch_pressed() -> void:
	var text: String = seed_input.text.strip_edges()
	if text.is_empty():
		VoxelWorldScript.use_fixed_seed = false
	else:
		VoxelWorldScript.use_fixed_seed = true
		VoxelWorldScript.requested_seed = int(text)
		# Sauvegarde cette graine pour qu'elle soit reproposee par defaut au
		# prochain lancement (voir LAST_SEED_PATH/_load_last_seed).
		_save_last_seed(text)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


## Lit la derniere graine sauvegardee (fichier absent ou vide au tout premier
## lancement -> chaine vide, gere par l'appelant).
func _load_last_seed() -> String:
	if not FileAccess.file_exists(LAST_SEED_PATH):
		return ""
	var f := FileAccess.open(LAST_SEED_PATH, FileAccess.READ)
	if f == null:
		return ""
	var raw := f.get_as_text().strip_edges()
	# Filtre aux chiffres, meme regle que _on_seed_text_changed() - un
	# fichier last_seed.txt modifie a la main (texte non numerique)
	# afficherait sinon ce texte tel quel dans le champ avant la prochaine
	# frappe utilisateur, contrairement a la saisie live.
	var filtered := ""
	for c in raw:
		if c >= "0" and c <= "9":
			filtered += c
	return filtered


## Sauvegarde la graine utilisee ce lancement, pour la retrouver par defaut
## au prochain demarrage.
func _save_last_seed(text: String) -> void:
	var f := FileAccess.open(LAST_SEED_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
	else:
		# Echouait silencieusement (disque plein/permissions) - la graine ne
		# sera simplement pas reproposee au prochain lancement (defaut :
		# nouveau nombre aleatoire), rien de bloquant, mais desormais visible
		# dans la console.
		push_warning("StartMenu: impossible d'ecrire %s (graine non sauvegardee)" % LAST_SEED_PATH)
