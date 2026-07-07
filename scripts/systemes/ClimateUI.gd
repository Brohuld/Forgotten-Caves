extends RefCounted
## UI climat/temps : bandeau heure (degrade jour/nuit + icone soleil/lune +
## marqueur), bandeau saison (degrade 4 couleurs + marqueur de progression),
## icone meteo, et les boutons Pause/x1/x2/x4 (+ logique de bascule
## pause/reprise). Suit le meme pattern que ActionValidator.gd/IconRenderer.gd :
## pas de reference typee vers ActionController.gd - setup() recoit le
## CanvasLayer parent (pour add_child) et l'instance IconRenderer partagee
## (pour reutiliser son cache de textures), update() recoit uniquement des
## valeurs deja calculees (season_id, is_daylight, etc.), jamais les noeuds
## SeasonSystem/DayNightCycle/WeatherSystem eux-memes.
const HOUR_BAND_SIZE := Vector2(800.0, 40.0)
const SEASON_BAND_SIZE := Vector2(800.0, 48.0)
const CLIMATE_ICON_SIZE := 72
const SUN_MOON_ICON_SIZE := 28.0

const TIME_ICON_SIZE := 24
const TIME_ICON_COLOR := Color(0.92, 0.92, 0.95)

## Pour lire/ecrire DayNightCycleScript.game_speed (pause/x1/x2/x4).
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")
## Type de la reference IconRenderer partagee (voir setup()) - pas de nouvelle
## instance ici, pour ne pas dupliquer inutilement son cache de textures.
const IconRendererScript := preload("res://scripts/systemes/IconRenderer.gd")
var _icon_renderer: IconRendererScript
# Garde contre un double appel accidentel de setup() - sans elle, les
# bandeaux/boutons seraient recrees et ajoutes une 2e fois en silence (aucune
# erreur visible).
var _is_setup: bool = false

var _hour_band: Control
var _hour_band_bg: TextureRect
var _hour_marker: ColorRect
var _sun_moon_icon: TextureRect
var _season_band: Control
var _season_band_bg: TextureRect
var _season_marker: ColorRect
var _weather_icon_wrap: Control
var _weather_icon_rect: TextureRect

# Caches pour eviter de reconstruire une texture a chaque frame (seulement
# quand la valeur affichee change reellement).
var _hour_band_season_cache: String = ""
var _sun_moon_is_day_cache: bool = false
var _sun_moon_icon_built: bool = false
var _weather_icon_cache: String = ""

# Boutons Pause/x1/x2/x4, construits dans setup() - pilotent
# DayNightCycleScript.game_speed (lu par Dwarf.gd/SeasonSystem.gd/
# WeatherSystem.gd/TemperatureSystem.gd), jamais par CameraRig.gd (la camera
# doit rester utilisable meme en pause).
var _btn_pause: Button
var _btn_speed1: Button
var _btn_speed2: Button
var _btn_speed4: Button

# Memorise la derniere vitesse active (1/2/4) juste avant une mise en pause
# par Espace, pour que Espace fasse basculer pause <-> reprise (au lieu de
# forcer 0.0 a chaque appui) - voir toggle_pause.
var _speed_before_pause: float = 1.0


## Texte "Printemps"/"Ete"/"Automne"/"Hiver" superpose au degrade du bandeau
## saison, un Label par segment (meme largeur fixe que chaque quart du
## degrade, voir _build_season_gradient_texture). Couleur de texte choisie au
## cas par cas pour rester lisible sur chaque fond (fonds clairs = texte
## fonce, fond automne plus sombre = texte clair).
const SEASON_TEXT_COLORS := {
	"printemps": Color(0.08, 0.28, 0.06),
	"ete": Color(0.35, 0.20, 0.0),
	"automne": Color(1.0, 0.95, 0.85),
	"hiver": Color(0.12, 0.14, 0.22),
}

## Degrade fixe (construit une seule fois) pour le bandeau saison - ordre
## d'affichage : vert clair printemps vers jaune ete vers orange fonce
## automne vers blanc hiver, boucle sur lui-meme.
const SEASON_DISPLAY_ORDER := ["printemps", "ete", "automne", "hiver"]
const SEASON_BAND_COLORS := {
	"printemps": Color(0.65, 0.9, 0.55),
	"ete": Color(0.95, 0.85, 0.25),
	"automne": Color(0.75, 0.4, 0.1),
	"hiver": Color(0.95, 0.95, 0.98),
}

## Lit directement les dictionnaires publics de DayNightCycle.gd
## (SUNRISE_HOUR/SUNSET_HOUR, par saison) via le script preload.
## Le bandeau heure est une progression a 3 teintes : noir (minuit) -> bleu
## fonce (lever/coucher) -> bleu clair (plein midi, exactement a mi-chemin
## entre lever et coucher) -> bleu fonce -> noir. NIGHT_BAND_COLOR est la
## couleur de minuit (noir), DAY_BAND_COLOR la couleur de plein midi (bleu
## clair), DAWN_DUSK_BAND_COLOR la teinte intermediaire au lever/coucher
## exact. HOUR_TRANSITION_FADE controle la largeur du fondu nuit -> bleu
## fonce : une valeur trop etroite (quelques texels sur une texture 128px)
## rend ce fondu invisible a l'oeil, donnant l'impression d'un saut direct
## bleu clair -> noir.
const NIGHT_BAND_COLOR := Color(0.03, 0.03, 0.08)
const DAWN_DUSK_BAND_COLOR := Color(0.16, 0.22, 0.48)
const DAY_BAND_COLOR := Color(0.55, 0.78, 0.95)
const HOUR_TRANSITION_FADE := 0.08  # ~2h, degrade nuit->bleu fonce bien visible


## Construit l'UI climat (bandeaux + icone meteo) et les controles de temps
## (boutons Pause/x1/x2/x4) - a appeler une seule fois depuis
## ActionController._ready(). `parent` est le CanvasLayer sur lequel accrocher
## les Control crees. `icon_renderer` est l'instance PARTAGEE d'IconRenderer
## d'ActionController (pas une nouvelle instance ici) pour ne pas dupliquer
## son cache de textures.
func setup(parent: CanvasLayer, icon_renderer: IconRendererScript) -> void:
	if _is_setup:
		push_warning("ClimateUI.setup() appele une 2e fois - ignore pour eviter de dupliquer les bandeaux/boutons.")
		return
	_is_setup = true
	_icon_renderer = icon_renderer
	_setup_bands(parent)
	_setup_time_controls(parent)


## Construit le bandeau "heure" + le bandeau "saison" (empiles verticalement)
## et une icone meteo a cote. Les degrades de fond (TextureRect +
## GradientTexture2D) et les icones (Image dessinee pixel par pixel, meme
## technique que les marqueurs de tache) sont construits/reconstruits au
## besoin dans update().
func _setup_bands(parent: CanvasLayer) -> void:
	var outer := HBoxContainer.new()
	outer.anchor_left = 0.5
	outer.anchor_right = 0.5
	outer.offset_left = -433.0
	outer.offset_right = 433.0
	outer.offset_top = 50.0
	outer.offset_bottom = 146.0
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_theme_constant_override("separation", 10)
	parent.add_child(outer)

	var bands_col := VBoxContainer.new()
	bands_col.add_theme_constant_override("separation", 3)
	bands_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outer.add_child(bands_col)

	_hour_band = _make_band_control(bands_col, HOUR_BAND_SIZE)
	_hour_band_bg = _make_band_background(_hour_band)
	_hour_marker = _make_band_marker(_hour_band, HOUR_BAND_SIZE.y)
	_sun_moon_icon = TextureRect.new()
	_sun_moon_icon.custom_minimum_size = Vector2(SUN_MOON_ICON_SIZE, SUN_MOON_ICON_SIZE)
	_sun_moon_icon.size = Vector2(SUN_MOON_ICON_SIZE, SUN_MOON_ICON_SIZE)
	_hour_band.add_child(_sun_moon_icon)

	_season_band = _make_band_control(bands_col, SEASON_BAND_SIZE)
	_season_band_bg = _make_band_background(_season_band)
	_season_band_bg.texture = _build_season_gradient_texture()
	_setup_season_labels(_season_band)
	_season_marker = _make_band_marker(_season_band, SEASON_BAND_SIZE.y)

	# Panneau arrondi semi-transparent derriere l'icone meteo, pour qu'elle
	# reste lisible quelle que soit la couleur du fond de l'interface (ex :
	# icone blanche "Neige").
	var wrap_size: float = CLIMATE_ICON_SIZE + 14.0
	_weather_icon_wrap = Control.new()
	_weather_icon_wrap.custom_minimum_size = Vector2(wrap_size, wrap_size)
	_weather_icon_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outer.add_child(_weather_icon_wrap)

	var bg_panel := Panel.new()
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.10, 0.16, 0.6)
	bg_style.set_corner_radius_all(8)
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	bg_panel.anchor_right = 1.0
	bg_panel.anchor_bottom = 1.0
	_weather_icon_wrap.add_child(bg_panel)

	_weather_icon_rect = TextureRect.new()
	_weather_icon_rect.custom_minimum_size = Vector2(CLIMATE_ICON_SIZE, CLIMATE_ICON_SIZE)
	var icon_padding: float = (wrap_size - CLIMATE_ICON_SIZE) * 0.5
	_weather_icon_rect.position = Vector2(icon_padding, icon_padding)
	_weather_icon_wrap.add_child(_weather_icon_rect)


func _setup_season_labels(parent: Control) -> void:
	var seg_width: float = SEASON_BAND_SIZE.x / float(SEASON_DISPLAY_ORDER.size())
	for i in range(SEASON_DISPLAY_ORDER.size()):
		var season_id: String = SEASON_DISPLAY_ORDER[i]
		var label := Label.new()
		label.text = season_id.capitalize()
		label.add_theme_color_override("font_color", SEASON_TEXT_COLORS.get(season_id, Color.BLACK))
		label.add_theme_font_size_override("font_size", 25)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.position = Vector2(seg_width * i, 0.0)
		label.size = Vector2(seg_width, SEASON_BAND_SIZE.y)
		parent.add_child(label)


## Petit Control de taille fixe servant de conteneur libre (fond degrade +
## marqueur/icone positionnes a la main, voir update()) - un simple
## TextureRect/ColorRect seul ne permettrait pas de superposer plusieurs
## enfants positionnes independamment.
func _make_band_control(parent: Control, size: Vector2) -> Control:
	var control := Control.new()
	control.custom_minimum_size = size
	parent.add_child(control)
	return control


func _make_band_background(parent: Control) -> TextureRect:
	var rect := TextureRect.new()
	rect.anchor_left = 0.0
	rect.anchor_top = 0.0
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	parent.add_child(rect)
	return rect


## Fine ligne verticale servant de marque pour l'heure/la progression
## actuelle - position.x mise a jour chaque frame.
func _make_band_marker(parent: Control, height: float) -> ColorRect:
	var marker := ColorRect.new()
	marker.color = Color(1, 1, 1, 0.95)
	marker.size = Vector2(3.0, height)
	parent.add_child(marker)
	return marker


## Les bornes minimales de clampf() ci-dessous (0.001 a 0.005) + la
## correction de stricte croissance (maxf(point[0], last_offset + 0.001) plus
## bas) garantissent un ordre de points toujours valide meme pour un jour
## tres court : verifie numeriquement que meme des jours artificiellement
## reduits jusqu'a 1h restent correctement ordonnes. Fonction fragile
## (deja source de 2 bugs geometriques distincts) - a ne pas retoucher sans
## revalider si un jour tres court (<4h) devait un jour etre introduit.
func _build_hour_gradient_texture(sunrise_frac: float, sunset_frac: float) -> GradientTexture2D:
	var gradient := Gradient.new()
	# Gradient.new() vient AVEC 2 points par defaut deja presents (offset 0.0
	# et 1.0, dont un blanc) - les appels add_point() ci-dessous doivent donc
	# REMPLACER ces points par defaut, pas s'y ajouter, sous peine de laisser
	# un point blanc residuel qui fausse le degrade pres d'une extremite.
	# Un Gradient Godot refuse toujours de descendre sous 1 point restant
	# (remove_point() echoue silencieusement en dessous) - on s'arrete donc a
	# 1 point restant (jamais 0), puis on ECRASE ce dernier point avec nos
	# propres valeurs au lieu d'essayer de le supprimer.
	while gradient.get_point_count() > 1:
		gradient.remove_point(1)
	var fade: float = HOUR_TRANSITION_FADE
	var noon_frac: float = (sunrise_frac + sunset_frac) * 0.5
	var points: Array = [
		[0.0, NIGHT_BAND_COLOR],
		[clampf(sunrise_frac - fade, 0.001, 0.998), NIGHT_BAND_COLOR],
		[clampf(sunrise_frac, 0.002, 0.999), DAWN_DUSK_BAND_COLOR],
		[clampf(noon_frac, 0.003, 0.999), DAY_BAND_COLOR],
		[clampf(sunset_frac, 0.004, 0.999), DAWN_DUSK_BAND_COLOR],
		[clampf(sunset_frac + fade, 0.005, 0.999), NIGHT_BAND_COLOR],
		[1.0, NIGHT_BAND_COLOR],
	]
	# Securite : garantit des offsets strictement croissants (Gradient l'exige) -
	# necessaire si deux saisons ont un lever/coucher tres proches d'une borne.
	# Le tout premier point ECRASE le point residuel qu'on a du garder
	# ci-dessus au lieu d'en ajouter un nouveau - sinon le gradient se
	# retrouverait avec 1 point par defaut EN PLUS de nos 7 points.
	var last_offset := -1.0
	var first := true
	for point in points:
		var point_offset: float = maxf(point[0], last_offset + 0.001)
		if first:
			gradient.set_offset(0, point_offset)
			gradient.set_color(0, point[1])
			first = false
		else:
			gradient.add_point(point_offset, point[1])
		last_offset = point_offset

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 8
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func _build_season_gradient_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	# Meme correctif que _build_hour_gradient_texture (voir son commentaire) :
	# vide les points par defaut avant d'ajouter les notres, en s'arretant a
	# 1 point restant (jamais 0, sinon boucle infinie), puis ecrase ce point
	# restant avec notre premiere valeur au lieu d'en ajouter un de plus.
	while gradient.get_point_count() > 1:
		gradient.remove_point(1)
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, SEASON_BAND_COLORS["printemps"])
	gradient.add_point(0.25, SEASON_BAND_COLORS["ete"])
	gradient.add_point(0.5, SEASON_BAND_COLORS["automne"])
	gradient.add_point(0.75, SEASON_BAND_COLORS["hiver"])
	gradient.add_point(1.0, SEASON_BAND_COLORS["printemps"])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 8
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


## Boutons Pause/x1/x2/x4, pilotent DayNightCycleScript.game_speed (lu par
## Dwarf.gd/SeasonSystem.gd/WeatherSystem.gd/TemperatureSystem.gd - jamais
## par CameraRig.gd, qui doit rester utilisable meme en pause).
func _setup_time_controls(parent: CanvasLayer) -> void:
	var box := HBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -100.0
	box.offset_right = 100.0
	box.offset_top = 152.0
	box.offset_bottom = 180.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)

	_btn_pause = _make_time_button(box, "pause", "Pause / Reprise (Espace)")
	_btn_speed1 = _make_time_button(box, "vitesse1", "Vitesse normale (F1)")
	_btn_speed2 = _make_time_button(box, "vitesse2", "Accéléré (F2)")
	_btn_speed4 = _make_time_button(box, "vitesse4", "Rapide (F3)")

	_btn_pause.pressed.connect(on_time_speed_pressed.bind(0.0))
	_btn_speed1.pressed.connect(on_time_speed_pressed.bind(1.0))
	_btn_speed2.pressed.connect(on_time_speed_pressed.bind(2.0))
	_btn_speed4.pressed.connect(on_time_speed_pressed.bind(4.0))
	_update_time_buttons()


## Bouton a icone dessinee (pas de texte "Pause"/"x1"/etc). tooltip_text
## rappelle le raccourci clavier associe (voir ActionController._unhandled_input).
func _make_time_button(parent: HBoxContainer, icon_kind: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.icon = _icon_renderer.get_time_icon_texture(icon_kind, TIME_ICON_SIZE, TIME_ICON_COLOR)
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(44, 40)
	btn.tooltip_text = tooltip
	btn.expand_icon = true
	# Sans ceci, le bouton Pause peut garder le focus clavier apres un clic -
	# Espace est mappe par defaut sur l'action "ui_accept", qui reactiverait
	# alors CE bouton en plus de notre propre gestion KEY_SPACE (toggle_pause),
	# pour un aller-retour pause/reprise quasi instantane (1 seule frame).
	btn.focus_mode = Control.FOCUS_NONE
	parent.add_child(btn)
	return btn


func on_time_speed_pressed(speed: float) -> void:
	DayNightCycleScript.game_speed = speed
	_update_time_buttons()


## Bascule pause/reprise au lieu de toujours forcer 0.0 - si le jeu tourne,
## memorise la vitesse courante puis met en pause ; si le jeu est deja en
## pause, reprend a la derniere vitesse memorisee (1.0 par defaut si Espace
## est le tout premier appui, avant toute selection explicite de vitesse).
func toggle_pause() -> void:
	if is_equal_approx(DayNightCycleScript.game_speed, 0.0):
		on_time_speed_pressed(_speed_before_pause)
	else:
		_speed_before_pause = DayNightCycleScript.game_speed
		on_time_speed_pressed(0.0)


func _update_time_buttons() -> void:
	var speed: float = DayNightCycleScript.game_speed
	_btn_pause.button_pressed = is_equal_approx(speed, 0.0)
	_btn_speed1.button_pressed = is_equal_approx(speed, 1.0)
	_btn_speed2.button_pressed = is_equal_approx(speed, 2.0)
	_btn_speed4.button_pressed = is_equal_approx(speed, 4.0)


## Mise a jour a chaque frame (appele depuis ActionController._process) :
## degrade heure + position du marqueur/icone soleil-lune, position du
## marqueur de saison, icone meteo. Ne recoit QUE des valeurs deja calculees
## par ActionController (jamais les noeuds SeasonSystem/DayNightCycle/
## WeatherSystem eux-memes) pour rester decouple, meme principe que
## ActionValidator.gd/IconRenderer.gd.
## - season_progress_raw : SeasonSystem.season_progress() (0.0-1.0 DANS la
##   saison courante, avant combinaison avec SEASON_DISPLAY_ORDER).
## - weather_label : "" si aucun WeatherSystem present.
## - time_label_text : texte deja forme par ActionController (jour/heure/
##   saison/temperature) - reutilise tel quel comme tooltip du marqueur heure.
func update(season_id: String, is_daylight: bool, time_of_day: float, season_progress_raw: float, weather_label: String, time_label_text: String) -> void:
	if _hour_band_bg:
		# Le degrade depend du lever/coucher de la saison courante -
		# reconstruit uniquement quand la saison change (pas chaque frame).
		if season_id != _hour_band_season_cache:
			_hour_band_season_cache = season_id
			# Reutilise directement DayNightCycle.gd (meme lookup exact, pas
			# de duplication ici).
			var sunrise_frac: float = DayNightCycleScript.sunrise_fraction_for(season_id)
			var sunset_frac: float = DayNightCycleScript.sunset_fraction_for(season_id)
			_hour_band_bg.texture = _build_hour_gradient_texture(sunrise_frac, sunset_frac)

		var hour_x: float = time_of_day * HOUR_BAND_SIZE.x
		_hour_marker.position = Vector2(hour_x - _hour_marker.size.x * 0.5, 0.0)
		_hour_marker.tooltip_text = time_label_text

		if not _sun_moon_icon_built or is_daylight != _sun_moon_is_day_cache:
			_sun_moon_is_day_cache = is_daylight
			_sun_moon_icon_built = true
			_sun_moon_icon.texture = _icon_renderer.make_sun_moon_icon(is_daylight, SUN_MOON_ICON_SIZE)
		_sun_moon_icon.position = Vector2(
			hour_x - _sun_moon_icon.custom_minimum_size.x * 0.5,
			(HOUR_BAND_SIZE.y - _sun_moon_icon.custom_minimum_size.y) * 0.5
		)
		_sun_moon_icon.tooltip_text = "Jour" if is_daylight else "Nuit"

	if _season_marker:
		# Ordre d'affichage voulu (printemps/ete/automne/hiver) different de
		# l'ordre interne de ClimateDefinitions.SEASONS (ete/automne/hiver/
		# printemps) - voir SEASON_DISPLAY_ORDER.
		var display_index: int = SEASON_DISPLAY_ORDER.find(season_id)
		if display_index < 0:
			display_index = 0
		var season_progress: float = (float(display_index) + season_progress_raw) / float(SEASON_DISPLAY_ORDER.size())
		var season_x: float = season_progress * SEASON_BAND_SIZE.x
		_season_marker.position = Vector2(season_x - _season_marker.size.x * 0.5, 0.0)
		_season_marker.tooltip_text = season_id.capitalize()

	if _weather_icon_rect and weather_label != "":
		if weather_label != _weather_icon_cache:
			_weather_icon_cache = weather_label
			_weather_icon_rect.texture = _icon_renderer.make_weather_icon(weather_label, CLIMATE_ICON_SIZE)
		_weather_icon_rect.tooltip_text = weather_label
