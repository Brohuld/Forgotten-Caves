extends CanvasLayer
## Sprint 9 : icone du nain en haut de l'ecran, cliquable, qui ouvre une
## fiche de personnage basique (PV factice, Faim, Energie, tache en cours).
## Sprint 11 : generalise a plusieurs nains. Une icone par nain, empilees en
## haut a droite ; cliquer sur une icone ouvre/ferme la fiche du nain
## correspondant (une seule fiche visible a la fois pour ne pas encombrer
## l'ecran). Tout est cree dynamiquement au demarrage, donc ca s'adapte
## automatiquement si on change le nombre de nains plus tard.
## Sprint 12 : affiche aussi les caracteristiques de base du nain (Force,
## Agilite, Constitution, Intelligence, Beaute, Bonheur) sous son nom.
## Sprint 18 : affiche aussi les competences (liste dans SkillDefinitions.gd)
## et leur niveau, qui evolue avec le temps (contrairement aux caracteristiques
## du Sprint 12) : rafraichi a chaque frame comme faim/energie.

const SkillDefs := preload("res://scripts/data/creatures/nains/caracteristiques/SkillDefinitions.gd")

const ICON_SIZE := 40
const ICON_MARGIN := 16
const ICON_SPACING := 8
const SKILL_ROW_HEIGHT := 22
# Hauteur de base (260, comme avant le Sprint 18) + une ligne par competence
# de la table + une ligne pour le titre "Competences" ; si la table grandit
# beaucoup plus tard, ajuster ce calcul ou reduire ICON_MARGIN/PANEL_HEIGHT.
var PANEL_HEIGHT: int = 260 + SKILL_ROW_HEIGHT * (SkillDefs.SKILLS.size() + 1)

var panels: Array = []  # un Panel par nain, meme ordre que le groupe "dwarves"


func _ready() -> void:
	var dwarves: Array = get_tree().get_nodes_in_group("dwarves")
	dwarves.sort_custom(func(a, b): return a.name < b.name)
	for i in range(dwarves.size()):
		_create_entry(dwarves[i], i)


## Cree l'icone + la fiche (masquee au depart) pour un nain donne
func _create_entry(dwarf: Node3D, index: int) -> void:
	var top_offset: float = ICON_MARGIN + index * (ICON_SIZE + ICON_SPACING)

	var icon_button := Button.new()
	icon_button.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_button.icon = _make_circle_icon(Color(0.8, 0.6, 0.4), ICON_SIZE)
	icon_button.expand_icon = true
	icon_button.anchor_left = 1.0
	icon_button.anchor_right = 1.0
	icon_button.offset_left = -ICON_MARGIN - ICON_SIZE
	icon_button.offset_right = -ICON_MARGIN
	icon_button.offset_top = top_offset
	icon_button.offset_bottom = top_offset + ICON_SIZE
	icon_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(icon_button)

	var panel := Panel.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -300.0
	panel.offset_right = -16.0
	panel.offset_top = top_offset
	panel.offset_bottom = top_offset + PANEL_HEIGHT
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.visible = false
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.offset_left = 12.0
	vbox.offset_top = 12.0
	vbox.offset_right = 270.0
	vbox.offset_bottom = PANEL_HEIGHT - 15.0
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 18)
	title.text = dwarf.dwarf_name
	vbox.add_child(title)

	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 16)
	vbox.add_child(stats_grid)
	_add_stat_label(stats_grid, "Force", dwarf.force)
	_add_stat_label(stats_grid, "Agilite", dwarf.agilite)
	_add_stat_label(stats_grid, "Constitution", dwarf.constitution)
	_add_stat_label(stats_grid, "Intelligence", dwarf.intelligence)
	_add_stat_label(stats_grid, "Beaute", dwarf.beaute)
	_add_stat_label(stats_grid, "Bonheur", "%d%%" % dwarf.bonheur)

	# Competences (Sprint 18) : generees dynamiquement a partir de la table
	# SkillDefinitions.SKILLS, donc s'adapte automatiquement si on en ajoute.
	# Le niveau progresse avec le temps (contrairement aux caracteristiques
	# ci-dessus) : les labels sont donc rafraichis dans _process.
	var skills_title := Label.new()
	skills_title.add_theme_font_size_override("font_size", 14)
	skills_title.text = "Competences"
	vbox.add_child(skills_title)

	var skill_labels: Dictionary = {}
	for skill in SkillDefs.SKILLS:
		var skill_id: String = skill["id"]
		var lbl := Label.new()
		lbl.text = _skill_line(dwarf, skill_id)
		vbox.add_child(lbl)
		skill_labels[skill_id] = lbl

	var pv_label := Label.new()
	pv_label.text = "PV"
	vbox.add_child(pv_label)
	var pv_bar := ProgressBar.new()
	pv_bar.custom_minimum_size = Vector2(240, 16)
	pv_bar.max_value = 100
	pv_bar.value = 100
	vbox.add_child(pv_bar)

	var hunger_label := Label.new()
	hunger_label.text = "Faim"
	vbox.add_child(hunger_label)
	var hunger_bar := ProgressBar.new()
	hunger_bar.custom_minimum_size = Vector2(240, 16)
	hunger_bar.max_value = dwarf.hunger_max
	vbox.add_child(hunger_bar)

	var energy_label := Label.new()
	energy_label.text = "Energie"
	vbox.add_child(energy_label)
	var energy_bar := ProgressBar.new()
	energy_bar.custom_minimum_size = Vector2(240, 16)
	energy_bar.max_value = dwarf.energy_max
	vbox.add_child(energy_bar)

	var task_label := Label.new()
	task_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	task_label.text = "Tache en cours : -"
	vbox.add_child(task_label)

	# On garde les refs necessaires au _process directement sur le Panel,
	# pour ne pas avoir a maintenir plusieurs tableaux paralleles
	panel.set_meta("dwarf", dwarf)
	panel.set_meta("hunger_bar", hunger_bar)
	panel.set_meta("energy_bar", energy_bar)
	panel.set_meta("task_label", task_label)
	panel.set_meta("skill_labels", skill_labels)

	panels.append(panel)
	icon_button.pressed.connect(_on_icon_pressed.bind(index))


## Ajoute un label "Nom : valeur" dans une grille (caracteristiques du Sprint 12,
## fixees a la creation du nain, donc pas besoin de les rafraichir en _process)
func _add_stat_label(grid: GridContainer, label_text: String, value) -> void:
	var lbl := Label.new()
	lbl.text = "%s : %s" % [label_text, str(value)]
	grid.add_child(lbl)


## Texte d'une ligne de competence : "Nom : niveau (xp/xp_suivant)"
func _skill_line(dwarf, skill_id: String) -> String:
	var level: int = dwarf.skill_levels.get(skill_id, 0)
	var xp: float = dwarf.skill_xp.get(skill_id, 0.0)
	var xp_needed: float = dwarf._xp_needed_for_level(level)
	return "%s : niveau %d (%d/%d xp)" % [SkillDefs.display_name(skill_id), level, int(xp), int(xp_needed)]


func _on_icon_pressed(index: int) -> void:
	var target: Panel = panels[index]
	var was_visible := target.visible
	for p in panels:
		p.visible = false
	target.visible = not was_visible


func _process(_delta: float) -> void:
	for panel in panels:
		if not panel.visible:
			continue
		var dwarf = panel.get_meta("dwarf")
		if not is_instance_valid(dwarf):
			continue
		panel.get_meta("hunger_bar").value = dwarf.hunger
		panel.get_meta("energy_bar").value = dwarf.energy
		panel.get_meta("task_label").text = "Tache en cours : %s" % _task_description(dwarf)

		# Competences (Sprint 18) : niveau/xp progressent avec le temps,
		# contrairement aux caracteristiques du Sprint 12
		var skill_labels: Dictionary = panel.get_meta("skill_labels")
		for skill_id in skill_labels:
			skill_labels[skill_id].text = _skill_line(dwarf, skill_id)


func _task_description(dwarf) -> String:
	if dwarf.is_working:
		return String(dwarf.current_task.get("type", "?")).capitalize()
	elif dwarf.is_resting:
		return "Repos"
	elif dwarf.is_eating:
		# Sprint 24quater : le nain mange directement depuis l'inventaire (plus
		# de trajet jusqu'a un buisson, voir Dwarf.gd/_try_start_eating) - un
		# seul etat "Manger" suffit desormais (l'ancien "Va manger" n'a plus
		# de sens sans deplacement).
		return "Manger"
	elif not dwarf.current_task.is_empty():
		return String(dwarf.current_task.get("type", "?")).capitalize()
	return "Errance"


## Genere une icone circulaire coloree sans avoir besoin d'un fichier image
func _make_circle_icon(color: Color, size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := size / 2.0
	var radius := size / 2.0 - 2.0
	for y in range(size):
		for x in range(size):
			var dx := x - center
			var dy := y - center
			if dx * dx + dy * dy <= radius * radius:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)
