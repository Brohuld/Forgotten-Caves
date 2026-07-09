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

## Tailles de carte proposees (voir _build_map_size_field) - "size" ecrit
## directement VoxelWorldScript.WIDTH/DEPTH juste avant de lancer la partie
## (voir _on_launch_pressed), meme mecanisme que use_fixed_seed/
## requested_seed plus bas (ecrit sur la classe AVANT change_scene_to_file).
const MAP_SIZES := [
	{"label": "50 x 50", "size": 50},
	{"label": "100 x 100", "size": 100},
	{"label": "250 x 250", "size": 250},
]
const DEFAULT_MAP_SIZE := 250

var seed_input: LineEdit
var selected_map_size: int = DEFAULT_MAP_SIZE


func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0

	_build_background()
	var box: VBoxContainer = _build_panel()
	_build_title(box)
	_build_seed_field(box)
	_build_map_size_field(box)
	_build_biome_field(box)
	_build_terrain_field(box)
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
	# Agrandi pour loger les nouvelles sections (taille de carte/biome/
	# terrain) en plus de la graine, et les polices plus grandes (voir
	# HINT_FONT_SIZE/BUTTON_FONT_SIZE) - hauteur fixe comme avant (plus
	# simple que de faire dependre le centrage vertical d'un contenu
	# dynamique).
	panel.offset_left = -320
	panel.offset_right = 320
	panel.offset_top = -310
	panel.offset_bottom = 310
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.18, 0.20, 0.26)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	return box


func _build_title(box: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Forgotten Caves"
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)


## Taille de police commune aux labels d'indication (taille de carte/biome/
## terrain/graine) et aux boutons - toutes les polices de cet ecran etaient
## trop petites (2026-07-08), augmentees nettement au-dela de la valeur par
## defaut du theme (~16).
const HINT_FONT_SIZE := 26
const BUTTON_FONT_SIZE := 26


func _build_seed_field(box: VBoxContainer) -> void:
	var hint := Label.new()
	hint.text = "Graine de la carte (laisser vide = carte aleatoire) :"
	hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	seed_input = LineEdit.new()
	seed_input.placeholder_text = "ex: 12345"
	seed_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_input.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	seed_input.custom_minimum_size = Vector2(280, 0)
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


## Rangee de boutons a selection exclusive (ButtonGroup) pour choisir la
## taille de la carte (voir MAP_SIZES) - "250 x 250" pre-selectionne par
## defaut. Le bouton presse ecrit selected_map_size, lu par
## _on_launch_pressed juste avant de lancer la partie.
func _build_map_size_field(box: VBoxContainer) -> void:
	var hint := Label.new()
	hint.text = "Taille de la carte :"
	hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var group := ButtonGroup.new()
	for entry in MAP_SIZES:
		var btn := Button.new()
		btn.text = entry["label"]
		btn.toggle_mode = true
		btn.button_group = group
		btn.button_pressed = entry["size"] == DEFAULT_MAP_SIZE
		btn.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
		btn.custom_minimum_size = Vector2(150, 48)
		# "toggled" (pas "pressed") : ButtonGroup emet ce signal aussi bien
		# pour le bouton qui devient presse que pour celui qui se depresse -
		# ne reagir qu'a "true" evite de repasser deux fois sur la meme
		# selection.
		btn.toggled.connect(_on_map_size_toggled.bind(entry["size"]))
		row.add_child(btn)


## Rangee de boutons DESACTIVES (menu futur, voir doc en tete de fichier) -
## un seul biome existe reellement pour l'instant (ClimateDefinitions.gd),
## affiche ici a titre d'apercu de la structure finale, sans aucun effet sur
## la generation.
func _build_biome_field(box: VBoxContainer) -> void:
	var hint := Label.new()
	hint.text = "Biome (a venir) :"
	hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)

	var btn := Button.new()
	btn.text = "Tempere"
	btn.toggle_mode = true
	btn.button_pressed = true
	btn.disabled = true
	btn.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	btn.custom_minimum_size = Vector2(180, 48)
	row.add_child(btn)


## Rangee de boutons DESACTIVES (menu futur, voir _build_biome_field) - le
## terrain "Collines" est deja celui reellement genere aujourd'hui
## (hill_amplitude, voir VoxelWorld.gd), affiche ici en pre-selectionne a
## titre d'apercu, sans effet.
func _build_terrain_field(box: VBoxContainer) -> void:
	var hint := Label.new()
	hint.text = "Terrain (a venir) :"
	hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	for label in ["Plat", "Collines", "Montagnes"]:
		var btn := Button.new()
		btn.text = label
		btn.toggle_mode = true
		btn.button_pressed = label == "Collines"
		btn.disabled = true
		btn.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
		btn.custom_minimum_size = Vector2(150, 48)
		row.add_child(btn)


func _build_launch_button(box: VBoxContainer) -> void:
	var launch_button := Button.new()
	launch_button.text = "Lancer la partie"
	launch_button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	launch_button.custom_minimum_size = Vector2(280, 56)
	launch_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	launch_button.pressed.connect(_on_launch_pressed)
	box.add_child(launch_button)


func _build_note(box: VBoxContainer) -> void:
	var note := Label.new()
	note.text = "La graine utilisee sera affichee dans la console Godot."
	note.add_theme_font_size_override("font_size", 20)
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


## Ne reagit qu'au bouton qui devient presse (voir sa connexion dans
## _build_map_size_field) - ButtonGroup garantit qu'un seul bouton est presse
## a la fois, donc selected_map_size reste toujours coherent avec l'affichage.
func _on_map_size_toggled(is_pressed: bool, map_size: int) -> void:
	if is_pressed:
		selected_map_size = map_size


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
	# Ecrit la taille choisie AVANT le changement de scene (WIDTH/DEPTH ne
	# sont plus des const cote VoxelWorld.gd, voir sa doc) - meme mecanisme
	# que use_fixed_seed/requested_seed juste au-dessus.
	VoxelWorldScript.WIDTH = selected_map_size
	VoxelWorldScript.DEPTH = selected_map_size
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
