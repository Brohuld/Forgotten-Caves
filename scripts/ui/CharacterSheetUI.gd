extends CanvasLayer
## Icone du nain en haut de l'ecran, cliquable, qui ouvre une fiche de
## personnage (PV factice, Faim/Energie/Soif, caracteristiques, competences,
## equipement, tache en cours). Une icone par nain, empilees en haut a
## droite ; cliquer sur une icone ouvre/ferme la fiche du nain correspondant
## (une seule fiche visible a la fois pour ne pas encombrer l'ecran). Tout
## est cree dynamiquement au demarrage, donc ca s'adapte automatiquement si
## on change le nombre de nains plus tard.
##
## Chaque bouton affiche un vrai portrait 3D du nain (mini SubViewport +
## camera cadree sur la tete, voir PortraitRenderer.gd), et son nom en
## permanence a cote (voir _create_entry). La fiche complete est organisee en
## onglets (TabContainer) : "Etat general" (nom, PV/Energie/Faim/Soif, tache
## en cours), "Caracteristiques", "Competences", "Equipement" - plus lisible
## qu'un long panneau vertical unique.
##
## "PV" reste un placeholder (pas encore de systeme de degats/combat).
## "Soif" est branchee sur dwarf.thirst/thirst_max (meme mecanique que
## Faim/Energie, voir Dwarf.gd), rafraichie a chaque frame.

const SkillDefs := preload("res://scripts/data/creatures/nains/caracteristiques/SkillDefinitions.gd")
## Construction du portrait 3D extraite dans son propre script - voir
## PortraitRenderer.gd.
const PortraitRendererScript := preload("res://scripts/ui/PortraitRenderer.gd")
## Uniquement pour lire DayNightCycleScript.scene_start_ms - ce script est le
## DERNIER a finir son _ready() dans l'ordre de Main.tscn (les portraits 3D,
## construits ici pour chaque nain, sont probablement la partie la plus
## couteuse du chargement) donc le bon endroit pour afficher le temps total
## ecoule depuis le tout debut de la scene.
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")
## _task_description delegue a hover_task_description (meme logique, voir
## revue de code M77) - evite la duplication du if/elif entre les deux scripts.
const ActionInspectorScript := preload("res://scripts/systemes/ActionInspector.gd")

const ICON_SIZE := 72
const ICON_MARGIN := 16
const ICON_SPACING := 10
const NAME_LABEL_WIDTH := 260  # assez large pour prenom + nom de clan
const NAME_LABEL_GAP := 8  # espace entre le texte du nom et l'icone

# Fiche de personnage (panel + onglets) : tailles et polices nettement
# agrandies par rapport a un panneau unique classique. PANEL_WIDTH est assez
# large pour que les 4 onglets (Etat general/Caracteristiques/Competences/
# Equipement) soient tous visibles d'un coup dans la barre d'onglets, sans
# fleches de defilement.
const PANEL_WIDTH := 640
const PANEL_HEIGHT := 460
const FONT_TITLE := 38       # nom du nain, en haut de la fiche
const FONT_SECTION := 25     # titres d'onglets + police des labels de contenu
const FONT_BODY := 25        # texte courant (stats, competences, tache en cours)
const BAR_HEIGHT := 26        # hauteur des barres PV/Faim/Energie/Soif

# Anneau de selection : un rond bleu pose au sol autour des pieds de chaque
# nain SELECTIONNE, pour voir en un coup d'oeil qui est selectionne. Un
# anneau par nain (selection_rings, cree dans _create_entry), montre/cache
# selon l'appartenance a selected_dwarves (Dictionary utilise comme un
# ensemble) - plusieurs nains peuvent etre selectionnes en meme temps
# (Ctrl/Maj+clic sur les portraits, ou glisser-clic sur la carte via
# ActionController.set_map_selection).
const SELECTION_RING_INNER_RADIUS := 0.32
const SELECTION_RING_OUTER_RADIUS := 0.5
const SELECTION_RING_COLOR := Color(0.25, 0.55, 1.0, 0.85)
# Teinte appliquee au portrait (modulate) d'un nain selectionne, pour le
# distinguer dans la liste sans avoir a ouvrir sa fiche.
const SELECTED_ICON_TINT := Color(0.55, 0.8, 1.3, 1.0)

var panels: Array = []  # un Panel par nain, meme ordre que le groupe "dwarves"
# Dictionary utilise comme un ensemble (cle = noeud nain, valeur toujours
# true) plutot qu'un Array, pour un has()/erase() en O(1).
var selected_dwarves: Dictionary = {}
var selection_rings: Dictionary = {}  # dwarf -> MeshInstance3D (un par nain)


func _ready() -> void:
	# Mesure a l'ENTREE de ce script (donc APRES la generation du monde ET
	# apres la creation des nains eux-memes, qui ont deja du construire leur
	# propre modele 3D pour exister dans le groupe "dwarves" - voir Dwarf.gd)
	var dwarves: Array = get_tree().get_nodes_in_group("dwarves")
	# Tri par dwarf_name (nom affiche au joueur) plutot que le nom de noeud
	# Godot (souvent juste "Dwarf2"), voir revue de code M78.
	dwarves.sort_custom(func(a, b): return a.dwarf_name < b.dwarf_name)
	for i in range(dwarves.size()):
		_create_entry(dwarves[i], i)


## Construit l'anneau de selection d'UN nain et l'ajoute au parent 3D (Main),
## pas a ce CanvasLayer - c'est un objet du monde 3D, pas un element
## d'interface. Cache par defaut (aucun nain selectionne au demarrage).
## Anneau plat construit a la main (ArrayMesh, voir _build_ring_mesh) plutot
## qu'un TorusMesh aplati par scale, pour un rendu garanti sans dependre des
## noms de proprietes exacts d'un mesh primitif - meme technique deja
## utilisee ailleurs dans le projet pour des formes generees par code.
func _create_selection_ring_for(dwarf: Node3D) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = "SelectionRing_%s" % dwarf.name
	ring.mesh = _build_ring_mesh(SELECTION_RING_INNER_RADIUS, SELECTION_RING_OUTER_RADIUS)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SELECTION_RING_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # visible de dessus ET de dessous, peu importe le sens des triangles
	# Le nain se tient exactement AU NIVEAU du dessus du terrain (voir
	# VoxelWorld._add_face, face du haut a world_y = block_y + 1 =
	# ground_level) - un anneau colle a une hauteur trop proche du sol
	# risquerait un z-fighting avec la face du terrain (memes profondeurs, a
	# quelques cm pres). no_depth_test force l'anneau a toujours se dessiner
	# PAR-DESSUS le reste (meme technique que sleep_indicator dans Dwarf.gd),
	# donc plus aucune ambiguite de profondeur possible.
	mat.no_depth_test = true
	ring.set_surface_override_material(0, mat)
	ring.visible = false
	# Appele depuis _ready() (via _create_entry), le parent (Main) est encore
	# en train d'instancier ses propres enfants a ce moment precis ->
	# add_child() direct echouerait silencieusement en erreur ("Parent node
	# is busy setting up children"), donc l'anneau ne serait jamais reellement
	# ajoute a la scene. call_deferred() repousse l'ajout a apres la fin de
	# l'initialisation en cours, ce qui resout le probleme.
	get_parent().add_child.call_deferred(ring)
	return ring


## Construit un anneau plat (dans le plan XZ, donc pose "a plat" au sol sans
## rotation a appliquer) : deux cercles de rayons "inner"/"outer" relies par
## des triangles. Technique manuelle (ArrayMesh) plutot qu'un mesh primitif
## du moteur, pour un rendu garanti sans dependre des noms de proprietes
## exacts d'une classe comme TorusMesh.
func _build_ring_mesh(inner: float, outer: float, segments: int = 48) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in range(segments + 1):
		var angle: float = i * TAU / float(segments)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		verts.append(dir * outer)
		verts.append(dir * inner)
	for i in range(segments):
		var a: int = i * 2
		var b: int = a + 1
		var c: int = a + 2
		var d: int = a + 3
		indices.append(a)
		indices.append(c)
		indices.append(b)
		indices.append(b)
		indices.append(c)
		indices.append(d)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return array_mesh


## Cree le nom, l'icone-portrait + la fiche (masquee au depart) pour un nain
## donne. Decoupee en sous-fonctions par bloc d'UI (_create_name_chip/
## _create_portrait_icon/_create_sheet_panel/_build_*_tab), meme pattern que
## StartMenu.gd/ClimateUI.gd.
func _create_entry(dwarf: Node3D, index: int) -> void:
	selection_rings[dwarf] = _create_selection_ring_for(dwarf)

	var top_offset: float = ICON_MARGIN + index * (ICON_SIZE + ICON_SPACING)

	_create_name_chip(dwarf, top_offset)
	var icon_button: Button = _create_portrait_icon(dwarf, top_offset)
	var panel: Panel = _create_sheet_panel(top_offset)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.offset_left = 16.0
	outer_vbox.offset_top = 12.0
	outer_vbox.offset_right = PANEL_WIDTH - 16.0
	outer_vbox.offset_bottom = PANEL_HEIGHT - 12.0
	outer_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(outer_vbox)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.text = dwarf.dwarf_name
	outer_vbox.add_child(title)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(PANEL_WIDTH - 32.0, PANEL_HEIGHT - 90.0)
	tabs.add_theme_font_size_override("font_size", FONT_SECTION)
	outer_vbox.add_child(tabs)

	var general_info: Dictionary = _build_general_tab(tabs, dwarf)
	_build_stats_tab(tabs, dwarf)
	var skill_rows: Dictionary = _build_skills_tab(tabs, dwarf)
	var equip_labels: Dictionary = _build_equipment_tab(tabs, dwarf)

	# On garde les refs necessaires au _process directement sur le Panel,
	# pour ne pas avoir a maintenir plusieurs tableaux paralleles
	panel.set_meta("dwarf", dwarf)
	panel.set_meta("icon_button", icon_button)
	panel.set_meta("hunger_bar", general_info["hunger_bar"])
	panel.set_meta("energy_bar", general_info["energy_bar"])
	panel.set_meta("thirst_bar", general_info["thirst_bar"])
	panel.set_meta("comfort_label", general_info["comfort_label"])
	panel.set_meta("task_label", general_info["task_label"])
	panel.set_meta("skill_rows", skill_rows)
	panel.set_meta("equip_labels", equip_labels)

	panels.append(panel)
	icon_button.pressed.connect(_on_icon_pressed.bind(index))


## Fond sombre semi-transparent derriere le nom - le blanc seul (meme avec un
## contour noir) reste peu lisible selon ce qu'il y a derriere dans la scene
## 3D (ciel clair, terrain...). Un "chip" sombre garantit le contraste quel
## que soit l'arriere-plan.
func _create_name_chip(dwarf: Node3D, top_offset: float) -> void:
	var name_bg := ColorRect.new()
	name_bg.color = Color(0.05, 0.05, 0.07, 0.6)
	name_bg.anchor_left = 1.0
	name_bg.anchor_right = 1.0
	name_bg.offset_right = -ICON_MARGIN - ICON_SIZE - NAME_LABEL_GAP * 0.5
	name_bg.offset_left = name_bg.offset_right - NAME_LABEL_WIDTH - NAME_LABEL_GAP * 0.5
	name_bg.offset_top = top_offset
	name_bg.offset_bottom = top_offset + ICON_SIZE
	name_bg.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_bg)

	var name_label := Label.new()
	name_label.text = dwarf.dwarf_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # filet de securite si un nom depasse quand meme NAME_LABEL_WIDTH
	name_label.anchor_left = 1.0
	name_label.anchor_right = 1.0
	name_label.offset_right = -ICON_MARGIN - ICON_SIZE - NAME_LABEL_GAP
	name_label.offset_left = name_label.offset_right - NAME_LABEL_WIDTH
	name_label.offset_top = top_offset
	name_label.offset_bottom = top_offset + ICON_SIZE
	name_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(name_label)


func _create_portrait_icon(dwarf: Node3D, top_offset: float) -> Button:
	var icon_button := Button.new()
	icon_button.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_button.icon = PortraitRendererScript.make_portrait_texture(dwarf, self)
	icon_button.expand_icon = true
	icon_button.anchor_left = 1.0
	icon_button.anchor_right = 1.0
	icon_button.offset_left = -ICON_MARGIN - ICON_SIZE
	icon_button.offset_right = -ICON_MARGIN
	icon_button.offset_top = top_offset
	icon_button.offset_bottom = top_offset + ICON_SIZE
	icon_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(icon_button)
	return icon_button


## Fond fonce explicite + theme "texte blanc" pour toute la fiche - le texte
## reste illisible sur le fond gris clair par defaut du theme Godot. Le
## Theme assigne ici au panel s'applique en cascade a tous ses enfants
## (titre, onglets, labels...), pas besoin de repeter la couleur sur chaque
## Label individuellement.
func _create_sheet_panel(top_offset: float) -> Panel:
	var panel := Panel.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -PANEL_WIDTH - ICON_MARGIN
	panel.offset_right = -ICON_MARGIN
	panel.offset_top = top_offset
	panel.offset_bottom = top_offset + PANEL_HEIGHT
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.visible = false
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15, 0.97)
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", panel_style)
	var sheet_theme := Theme.new()
	sheet_theme.set_color("font_color", "Label", Color(0.95, 0.95, 0.95))
	panel.theme = sheet_theme
	add_child(panel)
	return panel


## Onglet 1 : Etat general (nom deja affiche au-dessus des onglets, donc ici
## juste PV/Energie/Faim/Soif + la tache en cours). Renvoie les refs dont
## _process a besoin (barres/labels), pour que _create_entry les pose sur le
## Panel via set_meta.
func _build_general_tab(tabs: TabContainer, dwarf: Node3D) -> Dictionary:
	var general_tab := VBoxContainer.new()
	general_tab.add_theme_constant_override("separation", 10)
	tabs.add_child(general_tab)
	tabs.set_tab_title(0, "Etat general")

	_make_stat_bar(general_tab, "PV", 100.0, 100.0)
	var hunger_bar := _make_stat_bar(general_tab, "Faim", dwarf.hunger_max, dwarf.hunger)
	var energy_bar := _make_stat_bar(general_tab, "Energie", dwarf.energy_max, dwarf.energy)
	var thirst_bar := _make_stat_bar(general_tab, "Soif", dwarf.thirst_max, dwarf.thirst)

	# Confort thermique - purement informatif pour l'instant (voir
	# Dwarf.temperature_status), aucun effet sur le gameplay tant qu'il n'y a
	# pas de systeme d'habits.
	var comfort_label := _make_label("Confort : Normal", FONT_BODY)
	general_tab.add_child(comfort_label)

	var task_label := _make_label("Tache en cours : -", FONT_BODY)
	task_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	general_tab.add_child(task_label)

	return {
		"hunger_bar": hunger_bar,
		"energy_bar": energy_bar,
		"thirst_bar": thirst_bar,
		"comfort_label": comfort_label,
		"task_label": task_label,
	}


## Onglet 2 : Caracteristiques (fixees a la creation du nain).
func _build_stats_tab(tabs: TabContainer, dwarf: Node3D) -> void:
	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 24)
	stats_grid.add_theme_constant_override("v_separation", 10)
	tabs.add_child(stats_grid)
	tabs.set_tab_title(1, "Caracteristiques")
	_add_stat_label(stats_grid, "Force", dwarf.force)
	_add_stat_label(stats_grid, "Agilite", dwarf.agilite)
	_add_stat_label(stats_grid, "Constitution", dwarf.constitution)
	_add_stat_label(stats_grid, "Intelligence", dwarf.intelligence)
	_add_stat_label(stats_grid, "Beaute", dwarf.beaute)
	_add_stat_label(stats_grid, "Bonheur", "%d%%" % dwarf.bonheur)


## Onglet 3 : Competences, generees dynamiquement a partir de la table
## SkillDefinitions.SKILLS, donc s'adapte automatiquement si on en ajoute. Le
## niveau progresse avec le temps (contrairement aux caracteristiques
## ci-dessus) : niveau + barre rafraichis dans _process (voir
## _update_skill_row). 3 colonnes : nom de la competence, niveau (juste le
## nombre, sans le mot "niveau"), barre de progression vers le niveau suivant.
func _build_skills_tab(tabs: TabContainer, dwarf: Node3D) -> Dictionary:
	var skills_grid := GridContainer.new()
	skills_grid.columns = 3
	skills_grid.add_theme_constant_override("h_separation", 16)
	skills_grid.add_theme_constant_override("v_separation", 10)
	tabs.add_child(skills_grid)
	tabs.set_tab_title(2, "Competences")

	var skill_rows: Dictionary = {}
	for skill in SkillDefs.SKILLS:
		var skill_id: String = skill["id"]
		skills_grid.add_child(_make_label(SkillDefs.display_name(skill_id), FONT_BODY))
		var level_label := _make_label("0", FONT_BODY)
		skills_grid.add_child(level_label)
		var xp_bar := ProgressBar.new()
		xp_bar.custom_minimum_size = Vector2(220.0, BAR_HEIGHT)
		skills_grid.add_child(xp_bar)
		var row: Dictionary = {"level_label": level_label, "bar": xp_bar}
		skill_rows[skill_id] = row
		_update_skill_row(dwarf, skill_id, row)
	return skill_rows


## Onglet 4 : Equipement - stub minimal en lecture seule sur
## dwarf.personal_inventory ; pas de systeme d'equipement/artisanat reel pour
## l'instant (Phase 2, voir note en tete de dwarf.personal_inventory).
func _build_equipment_tab(tabs: TabContainer, dwarf: Node3D) -> Dictionary:
	var equip_grid := GridContainer.new()
	equip_grid.columns = 2
	equip_grid.add_theme_constant_override("h_separation", 24)
	equip_grid.add_theme_constant_override("v_separation", 10)
	tabs.add_child(equip_grid)
	tabs.set_tab_title(3, "Equipement")
	var equip_labels: Dictionary = {}
	var slot_display_names: Dictionary = {
		"gourde": "Gourde",
		"sac_a_dos": "Sac a dos",
		"habit": "Habit",
		"arme": "Arme",
	}
	for slot in dwarf.personal_inventory.keys():
		equip_grid.add_child(_make_label(slot_display_names.get(slot, slot.capitalize()), FONT_BODY))
		var value_label := _make_label("-", FONT_BODY)
		equip_grid.add_child(value_label)
		equip_labels[slot] = value_label
	return equip_labels


## Petit Label prerempli avec la police "fiche de personnage" (FONT_BODY par
## defaut), pour eviter de repeter add_theme_font_size_override partout.
func _make_label(text: String, font_size: int = FONT_BODY) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	return lbl


## Ajoute une ligne "Titre" + barre de progression dans un conteneur vertical
## (utilise par PV/Faim/Energie/Soif dans l'onglet "Etat general") et renvoie
## la barre pour que l'appelant puisse la garder (rafraichie en _process pour
## Faim/Energie/Soif, jamais pour PV qui reste un placeholder).
func _make_stat_bar(container: VBoxContainer, label_text: String, max_value: float, value: float) -> ProgressBar:
	container.add_child(_make_label(label_text, FONT_SECTION))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(PANEL_WIDTH - 64.0, BAR_HEIGHT)
	bar.max_value = max_value
	bar.value = value
	container.add_child(bar)
	return bar


## Ajoute un label "Nom : valeur" dans une grille (caracteristiques fixees a
## la creation du nain, donc pas besoin de les rafraichir en _process)
func _add_stat_label(grid: GridContainer, label_text: String, value) -> void:
	grid.add_child(_make_label("%s : %s" % [label_text, str(value)], FONT_BODY))


## Met a jour une ligne de l'onglet Competences : niveau (juste le nombre) +
## barre de progression vers le niveau suivant (row = {"level_label": Label,
## "bar": ProgressBar}, voir _create_entry).
func _update_skill_row(dwarf, skill_id: String, row: Dictionary) -> void:
	var level: int = dwarf.skill_levels.get(skill_id, 0)
	var xp: float = dwarf.skill_xp.get(skill_id, 0.0)
	var xp_needed: float = dwarf._xp_needed_for_level(level)
	row["level_label"].text = str(level)
	row["bar"].max_value = xp_needed
	row["bar"].value = xp


## Ctrl/Maj+clic sur un portrait ajoute/retire CE nain de la selection
## multiple courante SANS toucher a sa fiche (la multi-selection reste
## purement visuelle pour l'instant - anneaux au sol + surbrillance des
## portraits, voir _process). Un clic simple garde le comportement
## historique : ouvre/ferme la fiche de ce nain (une seule fiche a la fois,
## pour ne pas encombrer l'ecran) et remplace toute selection multiple en
## cours par ce seul nain.
func _on_icon_pressed(index: int) -> void:
	var target: Panel = panels[index]
	var dwarf = target.get_meta("dwarf")
	var additive: bool = Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)
	_toggle_panel_selection(target, dwarf, additive)


## Appelee par ActionController lors d'une selection par rectangle sur la
## carte (glisser-clic quand aucun mode d'action n'est actif) - voir
## ActionDragController.finalize_box_selection. additive = Maj/Ctrl enfonce
## au relachement du clic = ajoute a la selection existante au lieu de la
## remplacer (meme convention que Ctrl/Maj+clic sur un portrait ci-dessus).
## Purement visuel pour l'instant (anneaux + surbrillance des portraits),
## n'ouvre aucune fiche automatiquement.
func set_map_selection(dwarves: Array, additive: bool) -> void:
	if not additive:
		selected_dwarves.clear()
		for p in panels:
			p.visible = false
	for dwarf in dwarves:
		selected_dwarves[dwarf] = true


## Appelee par ActionController quand un clic simple (pas de glisser) tombe
## directement sur un nain dans le monde (voir ActionInspector.
## handle_inspect_click/dwarf_at_screen_pos) - meme comportement qu'un clic
## sur son portrait (_on_icon_pressed ci-dessus), juste retrouve via le
## noeud nain plutot qu'un index de panneau.
func select_and_open_dwarf(dwarf, additive: bool) -> void:
	var target: Panel = null
	for p in panels:
		if p.get_meta("dwarf") == dwarf:
			target = p
			break
	if target == null:
		return
	_toggle_panel_selection(target, dwarf, additive)


## Factorise la logique de bascule de selection/visibilite, partagee par
## _on_icon_pressed (clic sur portrait) et select_and_open_dwarf (clic sur le
## nain dans le monde) - meme comportement exact, seule la facon de trouver
## "target" differe entre les deux appelants.
func _toggle_panel_selection(target: Panel, dwarf, additive: bool) -> void:
	if additive:
		if selected_dwarves.has(dwarf):
			selected_dwarves.erase(dwarf)
		else:
			selected_dwarves[dwarf] = true
		return

	var was_visible := target.visible
	for p in panels:
		p.visible = false
	target.visible = not was_visible
	selected_dwarves.clear()
	if target.visible:
		selected_dwarves[dwarf] = true


## Ferme la fiche actuellement ouverte (s'il y en a une) et vide la
## selection en appuyant sur Echap - en plus du re-clic sur le portrait
## (deja pris en charge par _on_icon_pressed ci-dessus, qui referme si on
## reclique sur l'icone deja ouverte). "ui_cancel" est l'action Echap par
## defaut de Godot.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		for p in panels:
			p.visible = false
		selected_dwarves.clear()


func _process(_delta: float) -> void:
	# Anneaux de selection : un par nain (selection_rings), visible seulement
	# si ce nain fait partie de la selection courante.
	for dwarf in selection_rings:
		var ring: MeshInstance3D = selection_rings[dwarf]
		if selected_dwarves.has(dwarf) and is_instance_valid(dwarf):
			ring.visible = true
			ring.global_position = Vector3(
				dwarf.global_position.x,
				dwarf.global_position.y + 0.03,
				dwarf.global_position.z
			)
		else:
			ring.visible = false

	for panel in panels:
		var dwarf = panel.get_meta("dwarf")
		var icon_button: Button = panel.get_meta("icon_button")
		icon_button.modulate = SELECTED_ICON_TINT if selected_dwarves.has(dwarf) else Color.WHITE

		if not panel.visible:
			continue
		if not is_instance_valid(dwarf):
			continue
		panel.get_meta("hunger_bar").value = dwarf.hunger
		panel.get_meta("energy_bar").value = dwarf.energy
		panel.get_meta("thirst_bar").value = dwarf.thirst
		panel.get_meta("comfort_label").text = "Confort : %s" % dwarf.temperature_status()
		panel.get_meta("task_label").text = "Tache en cours : %s" % _task_description(dwarf)

		# Competences : niveau/xp progressent avec le temps, contrairement
		# aux caracteristiques.
		var skill_rows: Dictionary = panel.get_meta("skill_rows")
		for skill_id in skill_rows:
			_update_skill_row(dwarf, skill_id, skill_rows[skill_id])

		# Equipement : stub en lecture seule sur dwarf.personal_inventory,
		# "-" tant qu'un emplacement est vide.
		var equip_labels: Dictionary = panel.get_meta("equip_labels")
		for slot in equip_labels:
			var value: String = String(dwarf.personal_inventory.get(slot, ""))
			equip_labels[slot].text = value if value != "" else "-"


func _task_description(dwarf) -> String:
	# Logique identique a ActionInspector.hover_task_description - deleguee
	# pour ne pas dupliquer le if/elif (voir revue de code M77).
	return ActionInspectorScript.hover_task_description(dwarf)
