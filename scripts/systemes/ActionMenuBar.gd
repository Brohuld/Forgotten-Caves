extends RefCounted
## Rangee de boutons d'action (Construire/Couper/Cueillir/Creuser/Puiser/...)
## + sous-menu Construire (mur/porte/plancher/toit/escalier) construits PAR
## CODE a partir de MODE_ENTRIES/CONSTRUIRE_SUBMENU_ENTRIES ci-dessous,
## plutot que des boutons nommes en dur dans Main.tscn - pour ajouter un
## futur item (nouveau mode ou nouveau sous-type), il suffit d'ajouter une
## entree dans la table correspondante, sans toucher a la scene.
##
## Meme pattern de delegation que ActionValidator.gd/IconRenderer.gd : pas de
## reference typee vers ActionController.gd. build() recoit les conteneurs
## HBoxContainer (deja presents, vides, dans Main.tscn) et l'instance
## IconRenderer partagee (pour reutiliser son cache de textures), et renvoie
## les boutons crees - c'est l'appelant (ActionController.gd) qui connecte les
## signaux et garde la logique de mode/selection, ce fichier ne fait QUE
## construire l'UI.
##
## PORTABILITE (note ouverte, revue de code M100, 2026-07-11) : chaque entree
## a un raccourci clavier physique ("shortcut"), sans equivalent tactile
## dedie - les boutons eux-memes restent tactiles (vrais Button Godot,
## tapables normalement), seuls les raccourcis lettre necessitent un clavier.
## Volontairement documente ici sans action pour l'instant (decision
## Francois 2026-07-11) - a traiter dans un futur chantier iPad/iPhone si/
## quand il devient prioritaire (voir aussi CameraRig.gd).

const IconRendererScript := preload("res://scripts/systemes/IconRenderer.gd")

## Chaque entree : id (String, doit correspondre a une cle de
## ActionController.MODE_BY_ID), label affiche, touche physique (shortcut) +
## son libelle affiche entre parentheses sur le bouton, couleur du badge
## carre (meme style que les boutons existants) - "color" a null pour Puiser
## (couleur reelle du materiau "eau", passee a build() par l'appelant plutot
## que dupliquee ici). "icon_kind", quand non vide, reutilise TEL QUEL un
## glyphe deja dessine/valide pour les marqueurs de tache
## (IconRenderer.get_icon_texture : "pioche"/"hache"/"panier"/"construire"/
## "puiser"/"annuler"/"detruire"/"interdire") - tous les modes ont un glyphe
## dedie plutot qu'un simple badge carre de couleur.
const MODE_ENTRIES := [
	{"id": "CONSTRUIRE", "label": "Construire", "shortcut": KEY_B, "shortcut_label": "B", "color": Color(0.85, 0.65, 0.13), "icon_kind": "construire"},
	{"id": "COUPER", "label": "Couper", "shortcut": KEY_C, "shortcut_label": "C", "color": Color(0.25, 0.55, 0.15), "icon_kind": "hache"},
	{"id": "CUEILLIR", "label": "Cueillir", "shortcut": KEY_U, "shortcut_label": "U", "color": Color(0.85, 0.25, 0.25), "icon_kind": "panier"},
	# KEY_SEMICOLON (pas KEY_M) : "physical_keycode" designe la position
	# PHYSIQUE de la touche nommee d'apres un clavier QWERTY americain, pas le
	# caractere imprime sur un clavier AZERTY francais. Sur AZERTY, la touche
	# imprimee "M" est physiquement a l'emplacement du point-virgule QWERTY
	# (B/C/U/P/K/X/I sont tous a la MEME position sur les deux dispositions,
	# donc sans ce probleme - seul M differe, voir feedback de François
	# 2026-07-08 : "le raccourci M ne marche pas"). Meme logique que le
	# choix de KEY_W/KEY_A pour ZQSD dans CameraRig.gd.
	{"id": "MINER", "label": "Creuser", "shortcut": KEY_SEMICOLON, "shortcut_label": "M", "color": Color(0.5, 0.5, 0.5), "icon_kind": "pioche"},
	{"id": "PUISER", "label": "Puiser", "shortcut": KEY_P, "shortcut_label": "P", "color": null, "icon_kind": "puiser"},
	{"id": "ANNULER", "label": "Annuler", "shortcut": KEY_K, "shortcut_label": "K", "color": Color(0.55, 0.1, 0.1), "icon_kind": "annuler"},
	# DETRUIRE (demolit un mur construit) - couleur dupliquee de
	# ActionController._material_color("detruire") (fantomes/marqueurs).
	{"id": "DETRUIRE", "label": "Détruire", "shortcut": KEY_X, "shortcut_label": "X", "color": Color(0.75, 0.25, 0.05), "icon_kind": "detruire"},
	# INTERDIRE (bloque le ramassage/utilisation d'une case ou d'un arbre/
	# element de cueillette, reversible).
	{"id": "INTERDIRE", "label": "Interdire", "shortcut": KEY_I, "shortcut_label": "I", "color": Color(0.75, 0.15, 0.1), "icon_kind": "interdire"},
]

## Taille des icones de bouton (badge carre OU glyphe outil reutilise) - plus
## petite que les marqueurs de tache dans le monde 3D (voir ICON_SIZE=40 dans
## ActionDragController.gd), les boutons ont moins de place.
const BUTTON_ICON_SIZE := 56
const BUTTON_ICON_GLYPH_SIZE := 32
const BADGE_ICON_SIZE := 36

## Le curseur de mode reutilise directement l'icone du bouton (voir plus bas,
## icon_renderer.make_cursor_texture(btn.icon)) plutot qu'une taille dediee
## redessinee plus petite - garantit une resolution native, identique a
## l'icone du bouton, sans perte de qualite au redessin.

const MODE_FONT_SIZE := 40
const SUBMENU_FONT_SIZE := 38

## Sous-menu affiche uniquement quand Construire est actif. Seul "mur"
## correspond a une vraie mecanique de jeu aujourd'hui (murs bois/pierre/terre
## existants, voir MaterialBox dans ActionController.gd) - les 4 autres sont
## prevus pour une phase ulterieure (voir memoire "Plan Phase 2"), affiches
## des maintenant mais grises ("a venir") tant qu'ils ne sont pas codes.
const CONSTRUIRE_SUBMENU_ENTRIES := [
	{"id": "mur", "label": "Mur", "enabled": true},
	{"id": "porte", "label": "Porte", "enabled": false},
	{"id": "plancher", "label": "Plancher", "enabled": false},
	{"id": "toit", "label": "Toit", "enabled": false},
	{"id": "escalier", "label": "Escalier", "enabled": false},
]

## Sous-menu affiche uniquement quand Creuser (Mode.MINER) est actif -
## contrairement a CONSTRUIRE_SUBMENU_ENTRIES ci-dessus, les 2 entrees sont
## deja pleinement fonctionnelles (pas de placeholder grise) : "bloc" =
## minage classique (rectangle, comportement historique du mode Creuser),
## "escalier" = creusage d'une colonne d'escalier (geste clic+molette+clic,
## voir ActionDragController.on_stair_click). Raccourcis 1/2 (chiffres,
## distincts des touches de mode B/C/U/M/P/K/X/I) - "shortcut_kp" est
## l'equivalent PAVE NUMERIQUE (KEY_KP_1/KEY_KP_2, code physique DIFFERENT de
## KEY_1/KEY_2) - voir miner_subtype_for_shortcut, qui teste les deux.
const MINER_SUBMENU_ENTRIES := [
	{"id": "bloc", "label": "Miner", "shortcut": KEY_1, "shortcut_kp": KEY_KP_1, "shortcut_label": "1"},
	{"id": "escalier", "label": "Escalier", "shortcut": KEY_2, "shortcut_kp": KEY_KP_2, "shortcut_label": "2"},
]


## Construit les boutons de mode dans "mode_box", les boutons de sous-type
## Construire dans "construire_submenu_box" et les boutons de sous-type
## Creuser dans "miner_submenu_box" (tous deja presents dans la scene, vides
## au depart - voir Main.tscn). Renvoie {"mode_buttons": Dictionary[String,Button],
## "submenu_buttons": Dictionary[String,Button] (Construire),
## "miner_submenu_buttons": Dictionary[String,Button] (Creuser),
## "miner_subtype_group": ButtonGroup}. Les submenu_box sont des
## VBoxContainer (empilement vertical) tandis que "mode_box" (rangee de mode
## en haut) reste un HBoxContainer.
static func build(mode_box: HBoxContainer, submenu_box: VBoxContainer, miner_submenu_box: VBoxContainer, icon_renderer: IconRendererScript, eau_color: Color) -> Dictionary:
	# Les boutons de mode partagent tous ce ButtonGroup (assigne ci-dessous a
	# chacun). Godot garantit alors lui-meme "un seul enfonce a la fois",
	# plus besoin de boucler sur tous les boutons pour forcer leur etat (voir
	# ActionController._update_buttons(), qui ne touche plus les boutons de
	# mode). allow_unpress = true reproduit nativement "recliquer sur le mode
	# actif le desactive".
	var mode_group := ButtonGroup.new()
	mode_group.allow_unpress = true
	var mode_buttons: Dictionary = {}
	# Une texture de curseur par mode, generee ici a partir de btn.icon (meme
	# icone que le bouton, voir plus bas), pour que le curseur change de
	# forme selon le mode. Cle "" -> pas d'entree (Mode.NONE restaure le
	# curseur systeme, voir ActionController._update_cursor()).
	var cursor_textures: Dictionary = {}
	for i in range(MODE_ENTRIES.size()):
		var entry: Dictionary = MODE_ENTRIES[i]
		var btn := Button.new()
		btn.button_group = mode_group
		# Id de mode pose en metadonnee sur le bouton lui-meme - evite une
		# table de correspondance Button -> mode_id separee cote
		# ActionController.gd (voir _on_mode_button_toggled).
		btn.set_meta("mode_id", entry["id"])
		# Largeur fixe IDENTIQUE a tous les boutons (Godot agrandirait sinon
		# individuellement un bouton dont le contenu depasse ce minimum,
		# cassant l'alignement), texte aligne a gauche (Godot centre le
		# texte par defaut).
		btn.custom_minimum_size = Vector2(400, 110)
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = "%s (%s)" % [entry["label"], entry["shortcut_label"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", MODE_FONT_SIZE)
		var color: Color = entry["color"] if entry["color"] != null else eau_color
		var icon_kind: String = entry["icon_kind"]
		if icon_kind != "":
			btn.icon = icon_renderer.get_icon_texture(icon_kind, color, BUTTON_ICON_SIZE, BUTTON_ICON_GLYPH_SIZE)
		else:
			btn.icon = icon_renderer.make_square_icon(color, BADGE_ICON_SIZE)
		mode_box.add_child(btn)
		mode_buttons[entry["id"]] = btn
		# Reutilise TEL QUEL btn.icon (assigne juste au-dessus, resolution
		# native BUTTON_ICON_SIZE/BUTTON_ICON_GLYPH_SIZE) au lieu de
		# regenerer une version plus petite - garantit un badge de curseur
		# strictement identique (meme pixels) a l'icone du bouton.
		cursor_textures[entry["id"]] = icon_renderer.make_cursor_texture(btn.icon)
		# VSeparator natif Godot plutot qu'une bordure dessinee a la main sur
		# chaque bouton, pour accoler les rectangles avec juste une ligne de
		# separation (le HBoxContainer garde une separation quasi nulle,
		# voir Main.tscn).
		if i < MODE_ENTRIES.size() - 1:
			mode_box.add_child(VSeparator.new())

	var submenu_buttons: Dictionary = {}
	for i in range(CONSTRUIRE_SUBMENU_ENTRIES.size()):
		var entry: Dictionary = CONSTRUIRE_SUBMENU_ENTRIES[i]
		var btn := Button.new()
		# Meme raisonnement que ci-dessus pour la largeur/l'alignement.
		btn.custom_minimum_size = Vector2(200, 88)
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = entry["label"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", SUBMENU_FONT_SIZE)
		btn.disabled = not entry["enabled"]
		if not entry["enabled"]:
			btn.tooltip_text = "À venir (Phase 2, Sprint 1)"
			btn.modulate = Color(1, 1, 1, 0.45)
		submenu_box.add_child(btn)
		submenu_buttons[entry["id"]] = btn
		# HSeparator (ligne HORIZONTALE) plutot que VSeparator : submenu_box
		# empile les boutons verticalement, la ligne de separation doit donc
		# etre elle aussi horizontale (un VSeparator, pense pour une rangee,
		# ne s'afficherait pas correctement dans un VBoxContainer).
		if i < CONSTRUIRE_SUBMENU_ENTRIES.size() - 1:
			submenu_box.add_child(HSeparator.new())

	# Sous-menu Creuser (Miner/Escalier) - meme construction visuelle que le
	# sous-menu Construire ci-dessus, mais toujours "enabled" (pas de
	# placeholder) et avec son propre ButtonGroup EXCLUSIF (allow_unpress
	# volontairement absent : contrairement au mode principal, un sous-type
	# doit toujours rester selectionne - pas d'etat "aucun sous-type").
	var miner_subtype_group := ButtonGroup.new()
	var miner_submenu_buttons: Dictionary = {}
	for i in range(MINER_SUBMENU_ENTRIES.size()):
		var entry: Dictionary = MINER_SUBMENU_ENTRIES[i]
		var btn := Button.new()
		btn.button_group = miner_subtype_group
		btn.set_meta("subtype_id", entry["id"])
		btn.custom_minimum_size = Vector2(200, 88)
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = "%s (%s)" % [entry["label"], entry["shortcut_label"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", SUBMENU_FONT_SIZE)
		miner_submenu_box.add_child(btn)
		miner_submenu_buttons[entry["id"]] = btn
		if i < MINER_SUBMENU_ENTRIES.size() - 1:
			miner_submenu_box.add_child(HSeparator.new())

	return {
		"mode_buttons": mode_buttons, "submenu_buttons": submenu_buttons,
		"miner_submenu_buttons": miner_submenu_buttons, "miner_subtype_group": miner_subtype_group,
		"mode_group": mode_group, "cursor_textures": cursor_textures,
	}


## Renvoie l'id de mode (String, cle de MODE_ENTRIES/ActionController.MODE_BY_ID)
## associe a une touche physique, ou "" si aucune correspondance - utilise par
## ActionController._handle_mode_shortcuts().
static func mode_for_shortcut(physical_keycode: int) -> String:
	for entry in MODE_ENTRIES:
		if entry["shortcut"] == physical_keycode:
			return entry["id"]
	return ""


## Meme principe que mode_for_shortcut ci-dessus, pour les 2 sous-types de
## Creuser (touches 1/2 OU pave numerique 1/2, voir doc de
## MINER_SUBMENU_ENTRIES) - utilise par
## ActionController._handle_miner_subtype_shortcuts().
static func miner_subtype_for_shortcut(physical_keycode: int) -> String:
	for entry in MINER_SUBMENU_ENTRIES:
		if entry["shortcut"] == physical_keycode or entry["shortcut_kp"] == physical_keycode:
			return entry["id"]
	return ""
