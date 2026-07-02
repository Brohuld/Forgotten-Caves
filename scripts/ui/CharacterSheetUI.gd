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
## 2026-07-02 : chaque bouton affiche desormais un vrai portrait 3D du nain
## (mini SubViewport + camera cadree sur la tete, voir _make_portrait_texture)
## a la place du cercle colore generique, et son nom en permanence a cote
## (voir _create_entry) - avant, le nom n'etait visible qu'en ouvrant la
## fiche complete.
## 2026-07-02 (2e passe) : fiche de personnage agrandie (police bien plus
## grosse) et reorganisee en 3 onglets (TabContainer) - "Etat general" (nom,
## PV/Energie/Faim/Soif, tache en cours), "Caracteristiques", "Competences" -
## au lieu d'un long panneau vertical unique qui devenait difficile a lire.
## "Soif" est un placeholder pour l'instant (barre toujours pleine, jamais
## mise a jour) : aucune mecanique de soif n'existe encore cote gameplay
## (pas de baisse dans le temps, pas de source d'eau), meme traitement que
## "PV" (deja un placeholder depuis le Sprint 9).

const SkillDefs := preload("res://scripts/data/creatures/nains/caracteristiques/SkillDefinitions.gd")
const DwarfModel3DScript := preload("res://scripts/prototypes/DwarfModel3D.gd")

const ICON_SIZE := 72  # 2026-07-02 : agrandi (etait 48), jugee trop petite
const ICON_MARGIN := 16
const ICON_SPACING := 10
const NAME_LABEL_WIDTH := 260  # 2026-07-02 : elargi (etait 160), la boite ne contenait pas les noms les plus longs (prenom + nom de clan)
const NAME_LABEL_GAP := 8  # espace entre le texte du nom et l'icone

# Fiche de personnage (panel + onglets) : tailles et polices, nettement
# agrandies par rapport a l'ancien panneau unique (300x~370 px, police par
# defaut ~16). PANEL_WIDTH elargi une 2e fois (2026-07-02, 460->640) pour que
# les 3 onglets (Etat general/Caracteristiques/Competences) soient tous
# visibles d'un coup dans la barre d'onglets, sans fleches de defilement.
const PANEL_WIDTH := 640
const PANEL_HEIGHT := 460
const FONT_TITLE := 30       # nom du nain, en haut de la fiche
const FONT_SECTION := 20     # titres d'onglets + police des labels de contenu
const FONT_BODY := 20        # texte courant (stats, competences, tache en cours)
const BAR_HEIGHT := 26        # hauteur des barres PV/Faim/Energie/Soif

# Portrait 3D : taille de rendu du SubViewport (plus grand que l'icone
# affichee, ICON_SIZE, pour rester net une fois redimensionne) + reglages de
# cadrage de la mini-camera. Champs d'apparence copies depuis le vrai
# DwarfModel3D du nain (voir Dwarf.gd/_build_appearance) - liste explicite
# plutot qu'une copie generique par reflexion, pour ne jamais copier par
# erreur des proprietes de noeud (position/rotation/scale...) qui n'ont rien
# a voir avec l'apparence.
const PORTRAIT_RENDER_SIZE := 128
const PORTRAIT_CAMERA_FOV := 30.0
const PORTRAIT_APPEARANCE_FIELDS := [
	"skin_color", "hair_color", "beard_color", "clothing_color", "pants_color",
	"armor_color", "boot_color", "coat_color", "wear_gloves", "wear_coat",
	"leg_height", "torso_height", "torso_shoulder_width", "torso_waist_width",
	"torso_depth", "head_radius", "head_height_factor", "arm_length",
	"hair_size", "hair_lift", "hair_back_offset",
	"hair_style", "beard_style", "beard_width", "corpulence", "outfit_style",
]

# Anneau de selection (2026-07-02, devenu multiple le meme jour) : un rond
# bleu pose au sol autour des pieds de chaque nain SELECTIONNE, pour voir en
# un coup d'oeil qui est selectionne. Un anneau par nain (selection_rings,
# cree dans _create_entry), montre/cache selon l'appartenance a
# selected_dwarves (Dictionary utilise comme un ensemble) - plus un seul
# anneau partage comme au depart, puisque plusieurs nains peuvent maintenant
# etre selectionnes en meme temps (Ctrl/Maj+clic sur les portraits, ou
# glisser-clic sur la carte via ActionController.set_map_selection).
const SELECTION_RING_INNER_RADIUS := 0.32
const SELECTION_RING_OUTER_RADIUS := 0.5
const SELECTION_RING_COLOR := Color(0.25, 0.55, 1.0, 0.85)
# Teinte appliquee au portrait (modulate) d'un nain selectionne, pour le
# distinguer dans la liste sans avoir a ouvrir sa fiche.
const SELECTED_ICON_TINT := Color(0.55, 0.8, 1.3, 1.0)

var panels: Array = []  # un Panel par nain, meme ordre que le groupe "dwarves"
# 2026-07-02 : Dictionary utilise comme un ensemble (cle = noeud nain, valeur
# toujours true) plutot qu'un Array, pour un has()/erase() en O(1) - remplace
# l'ancien "selected_dwarf" unique (un seul nain a la fois).
var selected_dwarves: Dictionary = {}
var selection_rings: Dictionary = {}  # dwarf -> MeshInstance3D (un par nain)


func _ready() -> void:
	var dwarves: Array = get_tree().get_nodes_in_group("dwarves")
	dwarves.sort_custom(func(a, b): return a.name < b.name)
	for i in range(dwarves.size()):
		_create_entry(dwarves[i], i)


## Construit l'anneau de selection d'UN nain et l'ajoute au parent 3D (Main),
## pas a ce CanvasLayer - c'est un objet du monde 3D, pas un element
## d'interface. Cache par defaut (aucun nain selectionne au demarrage).
## 2026-07-02 : anneau plat construit a la main (ArrayMesh, voir
## _build_ring_mesh) au lieu d'un TorusMesh aplati par scale - l'anneau ne
## s'affichait pas du tout avec TorusMesh (tres probablement un souci de nom
## de propriete cote moteur), cette approche est la meme technique deja
## utilisee ailleurs dans le projet pour des formes generees par code (pas de
## dependance a l'API exacte d'un mesh primitif).
func _create_selection_ring_for(dwarf: Node3D) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = "SelectionRing_%s" % dwarf.name
	ring.mesh = _build_ring_mesh(SELECTION_RING_INNER_RADIUS, SELECTION_RING_OUTER_RADIUS)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SELECTION_RING_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # visible de dessus ET de dessous, peu importe le sens des triangles
	# 2026-07-02 : le nain se tient exactement AU NIVEAU du dessus du terrain
	# (voir VoxelWorld._add_face, face du haut a world_y = block_y + 1 = 30 =
	# ground_level) - un anneau colle a 0.03 au-dessus etait probablement
	# perdu dans un z-fighting avec la face du terrain (memes profondeurs, a
	# quelques cm pres). no_depth_test force l'anneau a toujours se dessiner
	# PAR-DESSUS le reste (meme technique que sleep_indicator dans Dwarf.gd),
	# donc plus aucune ambiguite de profondeur possible.
	mat.no_depth_test = true
	ring.set_surface_override_material(0, mat)
	ring.visible = false
	# 2026-07-02 : appele depuis _ready() (via _create_entry), le parent
	# (Main) est encore en train d'instancier ses propres enfants a ce moment
	# precis -> add_child() direct echoue silencieusement en erreur ("Parent
	# node is busy setting up children"), donc l'anneau n'etait jamais
	# reellement ajoute a la scene (d'ou "toujours rien" malgre plusieurs
	# corrections avant de trouver la vraie cause). call_deferred() repousse
	# l'ajout a apres la fin de l'initialisation en cours, ce qui resout le
	# probleme.
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


## Cree le nom, l'icone-portrait + la fiche (masquee au depart) pour un nain donne
func _create_entry(dwarf: Node3D, index: int) -> void:
	selection_rings[dwarf] = _create_selection_ring_for(dwarf)

	var top_offset: float = ICON_MARGIN + index * (ICON_SIZE + ICON_SPACING)

	# 2026-07-02 : fond sombre semi-transparent derriere le nom - le blanc seul
	# (meme avec un contour noir) restait peu lisible selon ce qu'il y a
	# derriere dans la scene 3D (ciel clair, terrain...). Un "chip" sombre
	# garantit le contraste quel que soit l'arriere-plan.
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
	name_label.add_theme_font_size_override("font_size", 18)
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

	var icon_button := Button.new()
	icon_button.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_button.icon = _make_portrait_texture(dwarf)
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
	panel.offset_left = -PANEL_WIDTH - ICON_MARGIN
	panel.offset_right = -ICON_MARGIN
	panel.offset_top = top_offset
	panel.offset_bottom = top_offset + PANEL_HEIGHT
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.visible = false
	# 2026-07-02 : fond fonce explicite + theme "texte blanc" pour toute la
	# fiche - le nom (et le reste du texte) restait illisible sur le fond
	# gris clair par defaut du theme Godot. Le Theme assigne ici au panel
	# s'applique en cascade a tous ses enfants (titre, onglets, labels...),
	# pas besoin de repeter la couleur sur chaque Label individuellement.
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15, 0.97)
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", panel_style)
	var sheet_theme := Theme.new()
	sheet_theme.set_color("font_color", "Label", Color(0.95, 0.95, 0.95))
	panel.theme = sheet_theme
	add_child(panel)

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

	# --- Onglet 1 : Etat general (nom deja affiche au-dessus des onglets,
	# donc ici juste PV/Energie/Faim/Soif + la tache en cours) ---
	var general_tab := VBoxContainer.new()
	general_tab.add_theme_constant_override("separation", 10)
	tabs.add_child(general_tab)
	tabs.set_tab_title(0, "Etat general")

	_make_stat_bar(general_tab, "PV", 100.0, 100.0)
	var hunger_bar := _make_stat_bar(general_tab, "Faim", dwarf.hunger_max, dwarf.hunger)
	var energy_bar := _make_stat_bar(general_tab, "Energie", dwarf.energy_max, dwarf.energy)
	# Soif : placeholder, aucune mecanique de soif n'existe encore (voir note
	# en tete de fichier) - barre toujours pleine, jamais rafraichie en _process.
	_make_stat_bar(general_tab, "Soif", 100.0, 100.0)

	var task_label := _make_label("Tache en cours : -", FONT_BODY)
	task_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	general_tab.add_child(task_label)

	# --- Onglet 2 : Caracteristiques (Sprint 12, fixees a la creation) ---
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

	# --- Onglet 3 : Competences (Sprint 18) - generees dynamiquement a
	# partir de la table SkillDefinitions.SKILLS, donc s'adapte
	# automatiquement si on en ajoute. Le niveau progresse avec le temps
	# (contrairement aux caracteristiques ci-dessus) : niveau + barre
	# rafraichis dans _process (voir _update_skill_row). 3 colonnes : nom de
	# la competence, niveau (juste le nombre, sans le mot "niveau"), barre de
	# progression vers le niveau suivant.
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

	# On garde les refs necessaires au _process directement sur le Panel,
	# pour ne pas avoir a maintenir plusieurs tableaux paralleles
	panel.set_meta("dwarf", dwarf)
	panel.set_meta("icon_button", icon_button)
	panel.set_meta("hunger_bar", hunger_bar)
	panel.set_meta("energy_bar", energy_bar)
	panel.set_meta("task_label", task_label)
	panel.set_meta("skill_rows", skill_rows)

	panels.append(panel)
	icon_button.pressed.connect(_on_icon_pressed.bind(index))


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
## Faim/Energie, jamais pour PV/Soif qui sont des placeholders).
func _make_stat_bar(container: VBoxContainer, label_text: String, max_value: float, value: float) -> ProgressBar:
	container.add_child(_make_label(label_text, FONT_SECTION))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(PANEL_WIDTH - 64.0, BAR_HEIGHT)
	bar.max_value = max_value
	bar.value = value
	container.add_child(bar)
	return bar


## Ajoute un label "Nom : valeur" dans une grille (caracteristiques du Sprint 12,
## fixees a la creation du nain, donc pas besoin de les rafraichir en _process)
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


## 2026-07-02 : Ctrl/Maj+clic sur un portrait ajoute/retire CE nain de la
## selection multiple courante SANS toucher a sa fiche (la multi-selection
## reste purement visuelle pour l'instant - anneaux au sol + surbrillance des
## portraits, voir _process). Un clic simple garde le comportement historique
## : ouvre/ferme la fiche de ce nain (une seule fiche a la fois, pour ne pas
## encombrer l'ecran) et remplace toute selection multiple en cours par ce
## seul nain.
func _on_icon_pressed(index: int) -> void:
	var target: Panel = panels[index]
	var dwarf = target.get_meta("dwarf")
	var additive: bool = Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)

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


## Appelee par ActionController lors d'une selection par rectangle sur la
## carte (glisser-clic quand aucun mode d'action n'est actif) - voir
## ActionController._finalize_box_selection. additive = Maj/Ctrl enfonce au
## relachement du clic = ajoute a la selection existante au lieu de la
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


## 2026-07-02 : ferme la fiche actuellement ouverte (s'il y en a une) et vide
## la selection en appuyant sur Echap - en plus du re-clic sur le portrait
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
		panel.get_meta("task_label").text = "Tache en cours : %s" % _task_description(dwarf)

		# Competences (Sprint 18) : niveau/xp progressent avec le temps,
		# contrairement aux caracteristiques du Sprint 12
		var skill_rows: Dictionary = panel.get_meta("skill_rows")
		for skill_id in skill_rows:
			_update_skill_row(dwarf, skill_id, skill_rows[skill_id])


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


## Portrait 3D (2026-07-02) : construit un mini SubViewport isole contenant
## une COPIE du modele DwarfModel3D du nain (meme apparence, voir
## PORTRAIT_APPEARANCE_FIELDS), filmee par une camera cadree sur la tete, et
## renvoie sa texture de rendu pour l'utiliser comme icone de bouton. Le
## SubViewport doit rester dans l'arbre de scene pour continuer a rendre (il
## est ajoute comme enfant de ce CanvasLayer, invisible a l'ecran comme tout
## SubViewport non affiche dans un SubViewportContainer).
func _make_portrait_texture(dwarf: Node3D) -> Texture2D:
	var src_model: Node3D = dwarf.dwarf_model

	var viewport := SubViewport.new()
	viewport.size = Vector2i(PORTRAIT_RENDER_SIZE, PORTRAIT_RENDER_SIZE)
	viewport.transparent_bg = true
	# Monde 3D independant du jeu principal : sans ca, la camera du portrait
	# risquerait de partager (et donc afficher) le monde 3D de la scene
	# principale au lieu du seul modele copie ci-dessous.
	viewport.own_world_3d = true
	add_child(viewport)

	var portrait_model := Node3D.new()
	portrait_model.set_script(DwarfModel3DScript)
	viewport.add_child(portrait_model)
	for field in PORTRAIT_APPEARANCE_FIELDS:
		portrait_model.set(field, src_model.get(field))
	portrait_model.weapon_loadout = "Aucune"  # jamais d'arme dans le portrait, coherent avec le jeu principal
	portrait_model._rebuild()

	# Cadrage "buste" : vise un peu sous le sommet de la tete (voir la formule
	# de head_y dans DwarfModel3D._build_model) pour laisser de la marge au-
	# dessus (cheveux) et voir un peu des epaules en bas de l'image. Distance
	# proportionnelle a head_radius pour rester correct si la tete change de
	# taille plus tard.
	var target_y: float = portrait_model.leg_height + portrait_model.torso_height + portrait_model.head_radius * 0.1
	var camera := Camera3D.new()
	camera.fov = PORTRAIT_CAMERA_FOV
	camera.position = Vector3(0, target_y, portrait_model.head_radius * 3.8)
	camera.current = true
	# 2026-07-02 : look_at() a besoin de la transform globale du noeud, donc
	# le noeud doit deja etre DANS l'arbre de scene (add_child avant, pas
	# apres) - meme famille de bug que le "Parent node is busy" de l'anneau
	# de selection, mais ici c'est l'ordre des deux lignes qui etait inverse.
	viewport.add_child(camera)
	camera.look_at(Vector3(0, target_y, 0), Vector3.UP)

	return viewport.get_texture()
