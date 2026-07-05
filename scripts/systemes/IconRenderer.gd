extends RefCounted
## Extrait de ActionController.gd le 2026-07-05 (revue de code, dette
## d'architecture A1 : separation presentation/regles, etape suivante apres
## ActionValidator.gd/DwarfSkills.gd). Regroupe TOUT le dessin pixel par
## pixel des icones (marqueurs de tache pioche/hache/panier, icones
## climat/soleil-lune, icones pause/vitesse, icones de boutons d'action) -
## purement visuel, aucune regle de jeu. Suit le meme pattern que
## ActionValidator.gd/DwarfSkills.gd : pas de reference typee vers
## ActionController.gd, les tailles/couleurs necessaires sont passees en
## parametres plutot que lues depuis des constantes de ActionController.gd.

# Caches (deplaces depuis ActionController.gd) : "kind|couleur" -> ImageTexture
# pour les icones de marqueur de tache, "kind" -> ImageTexture pour les icones
# pause/vitesse (taille/couleur fixes, pas besoin de cle composite).
var _icon_texture_cache: Dictionary = {}
var _time_icon_cache: Dictionary = {}


## Icone carree unie (boutons d'action Miner/Couper/Construire/etc.)
func make_square_icon(color: Color, size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## Icone "passage du soleil" (jour) ou lune (nuit) affichee dans le bandeau
## heure - voir doc d'origine dans ActionController.gd (Sprint 37nonies/decies).
func make_sun_moon_icon(is_day: bool, icon_size: float) -> ImageTexture:
	var size := int(icon_size)
	var center := icon_size * 0.5
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if is_day:
		_fill_circle(img, center, center, 11.0, Color(1.0, 0.85, 0.3))
	else:
		_fill_circle(img, center, center, 11.0, Color(0.85, 0.87, 0.95))
		_fill_circle(img, center + 4.0, center - 4.0, 9.0, Color(0, 0, 0, 0))  # decoupe un croissant
	return ImageTexture.create_from_image(img)


## Icone meteo (soleil/brouillard/pluie/neige) - voir doc d'origine dans
## ActionController.gd (Sprint 37nonies/decies, Sprint 47).
func make_weather_icon(weather_label: String, icon_size: int) -> ImageTexture:
	var size := icon_size
	var s: float = float(size) / 44.0
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match weather_label:
		"Pluie":
			_fill_circle(img, 22 * s, 18 * s, 13.0 * s, Color(0.75, 0.78, 0.82))
			for i in range(3):
				var x: int = int((12 + i * 10) * s)
				for y in range(int(30 * s), int(38 * s)):
					img.set_pixel(x, y, Color(0.35, 0.5, 0.85))
					img.set_pixel(x + 1, y, Color(0.35, 0.5, 0.85))
		"Neige":
			_fill_circle(img, 22 * s, 18 * s, 13.0 * s, Color(0.85, 0.87, 0.9))
			for i in range(3):
				var x: int = int((12 + i * 10) * s)
				var step: int = int(2 * s)
				for dy in range(2):
					var y: int = int(32 * s) + dy * step
					img.set_pixel(x, y, Color(1, 1, 1))
					img.set_pixel(x - step, y, Color(1, 1, 1))
					img.set_pixel(x + step, y, Color(1, 1, 1))
					img.set_pixel(x, y - step, Color(1, 1, 1))
					img.set_pixel(x, y + step, Color(1, 1, 1))
		"Brouillard":
			for i in range(3):
				var y: int = int((14 + i * 8) * s)
				for x in range(int(6 * s), int(38 * s)):
					img.set_pixel(x, y, Color(0.75, 0.78, 0.8, 0.9))
					img.set_pixel(x, y + 1, Color(0.75, 0.78, 0.8, 0.9))
		_:  # "Ciel degage"
			_fill_circle(img, 22 * s, 22 * s, 11.0 * s, Color(1.0, 0.85, 0.3))
			for ray in range(8):
				var angle: float = ray * TAU / 8.0
				var dir := Vector2(cos(angle), sin(angle))
				var p1 := Vector2(22 * s, 22 * s) + dir * (15.0 * s)
				var p2 := Vector2(22 * s, 22 * s) + dir * (19.0 * s)
				_fill_circle(img, p1.x, p1.y, 1.2 * s, Color(1.0, 0.85, 0.3))
				_fill_circle(img, p2.x, p2.y, 1.2 * s, Color(1.0, 0.85, 0.3))
	return ImageTexture.create_from_image(img)


## Icone de marqueur de tache (pioche/hache/panier) : badge rond jaune +
## glyphe incruste au centre. "icon_size"/"glyph_size" remplacent les
## constantes ICON_SIZE/ICON_GLYPH_SIZE de ActionController.gd.
func get_icon_texture(kind: String, color: Color, icon_size: int, glyph_size: int) -> ImageTexture:
	var key := "%s|%s" % [kind, color]
	if _icon_texture_cache.has(key):
		return _icon_texture_cache[key]
	var img := Image.create(icon_size, icon_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # fond transparent

	# Badge rond jaune (demande explicite Francois) - une fine bordure plus
	# sombre dessinee d'abord, puis le disque jaune par-dessus (legerement
	# plus petit), pour un contour net qui se detache bien du decor 3D.
	var center := float(icon_size) / 2.0
	_fill_circle(img, center, center, center - 1.0, Color(0.55, 0.4, 0.05))
	_fill_circle(img, center, center, center - 3.0, Color(0.95, 0.78, 0.15))

	# Le glyphe (pioche/hache/panier) est dessine separement, plus petit
	# (glyph_size) que le badge, puis incruste au centre - _draw_*_icon se
	# basent sur la largeur reelle de l'image recue, donc fonctionnent tels
	# quels sur ce canevas plus petit.
	var glyph := Image.create(glyph_size, glyph_size, false, Image.FORMAT_RGBA8)
	glyph.fill(Color(0, 0, 0, 0))
	match kind:
		"pioche":
			_draw_pickaxe_icon(glyph, color)
		"hache":
			_draw_axe_icon(glyph, color)
		"panier":
			_draw_basket_icon(glyph, color)
	var inset := int(round((icon_size - glyph_size) / 2.0))
	img.blend_rect(glyph, Rect2i(Vector2i.ZERO, Vector2i(glyph_size, glyph_size)), Vector2i(inset, inset))

	var tex := ImageTexture.create_from_image(img)
	_icon_texture_cache[key] = tex
	return tex


## Icones pause/vitesse pour les boutons de controle du temps. "icon_size"/
## "icon_color" remplacent TIME_ICON_SIZE/TIME_ICON_COLOR de
## ActionController.gd.
func get_time_icon_texture(kind: String, icon_size: int, icon_color: Color) -> ImageTexture:
	if _time_icon_cache.has(kind):
		return _time_icon_cache[kind]
	var img := Image.create(icon_size, icon_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # fond transparent
	match kind:
		"pause":
			_draw_pause_icon(img, icon_color, icon_size)
		"vitesse1":
			_draw_speed_icon(img, icon_color, 1, icon_size)
		"vitesse2":
			_draw_speed_icon(img, icon_color, 2, icon_size)
		"vitesse4":
			_draw_speed_icon(img, icon_color, 4, icon_size)
	var tex := ImageTexture.create_from_image(img)
	_time_icon_cache[kind] = tex
	return tex


## Pause : deux barres verticales pleines, cote a cote (symbole standard).
func _draw_pause_icon(img: Image, color: Color, icon_size: int) -> void:
	var s := float(icon_size)
	var bar_w := s * 0.16
	var top := s * 0.18
	var bottom := s * 0.82
	_fill_rect_px(img, s * 0.28 - bar_w * 0.5, top, bar_w, bottom - top, color)
	_fill_rect_px(img, s * 0.72 - bar_w * 0.5, top, bar_w, bottom - top, color)


## Vitesse : "count" triangles pleins pointant vers la droite, cote a cote
## (1 = normal, 2/4 = avance rapide - meme convention que les lecteurs video
## "»" repetes).
func _draw_speed_icon(img: Image, color: Color, count: int, icon_size: int) -> void:
	var s := float(icon_size)
	var tri_w := s * 0.22
	var tri_h := s * 0.5
	var spacing := s * 0.10
	var total_w: float = count * tri_w + float(count - 1) * spacing
	var start_x: float = (s - total_w) * 0.5
	var top := (s - tri_h) * 0.5
	for i in range(count):
		var x0: float = start_x + float(i) * (tri_w + spacing)
		var a := Vector2(x0, top)
		var b := Vector2(x0, top + tri_h)
		var c := Vector2(x0 + tri_w, top + tri_h * 0.5)
		_fill_triangle(img, a, b, c, color)


## Pioche : manche diagonal + tete en arc de cercle (120 degres), pointes aux
## deux extremites - voir historique des refontes dans ActionController.gd
## avant extraction (2026-07-05).
func _draw_pickaxe_icon(img: Image, _color: Color) -> void:
	var s := float(img.get_width())
	var handle_color := Color(0.549, 0.353, 0.118)
	var head_color := Color(0.533, 0.549, 0.576)
	var arc_hw := s * 0.03571429
	_stroke_segment(img, Vector2(s * 0.125, s * 0.875), Vector2(s * 0.65, s * 0.35), arc_hw, handle_color)
	# Tete en arc de cercle (120 degres), pointes aux deux extremites
	var center := Vector2(s * 0.371585, s * 0.62843)
	var radius := s * 0.3375
	var theta1 := deg_to_rad(255.0)
	var theta2 := deg_to_rad(375.0)
	var segments := 12
	var prev := center + Vector2(cos(theta1), sin(theta1)) * radius
	for i in range(1, segments + 1):
		var t: float = theta1 + (theta2 - theta1) * float(i) / float(segments)
		var cur := center + Vector2(cos(t), sin(t)) * radius
		_stroke_segment(img, prev, cur, arc_hw, head_color)
		prev = cur
	_fill_triangle(img, Vector2(s * 0.1973, s * 0.3257), Vector2(s * 0.293938, s * 0.338653), Vector2(s * 0.274528, s * 0.266203), head_color)
	_fill_triangle(img, Vector2(s * 0.674278, s * 0.8027), Vector2(s * 0.733798, s * 0.725473), Vector2(s * 0.661348, s * 0.706063), head_color)


## Hache : manche diagonal + tete en trapeze (talon + lame), dessinee avec
## _stroke_segment (rectangles nets) - voir historique des refontes dans
## ActionController.gd avant extraction (2026-07-05).
func _draw_axe_icon(img: Image, _color: Color) -> void:
	var s := float(img.get_width())
	var handle_color := Color(0.549, 0.353, 0.118)
	var head_color := Color(0.533, 0.549, 0.576)
	var head_border := Color(0.227, 0.239, 0.259)
	var handle_hw := s * 0.03571429
	var border_hw := s * 0.01116071
	_stroke_segment(img, Vector2(s * 0.125, s * 0.875), Vector2(s * 0.65, s * 0.35), handle_hw, handle_color)
	var p1 := Vector2(s * 0.49166, s * 0.272015)
	var p2 := Vector2(s * 0.41291, s * 0.350765)
	var p3 := Vector2(s * 0.60986, s * 0.626465)
	var p4 := Vector2(s * 0.76736, s * 0.468965)
	_fill_triangle(img, p1, p2, p3, head_color)
	_fill_triangle(img, p1, p3, p4, head_color)
	_stroke_segment(img, p1, p2, border_hw, head_border)
	_stroke_segment(img, p2, p3, border_hw, head_border)
	_stroke_segment(img, p3, p4, border_hw, head_border)
	_stroke_segment(img, p4, p1, border_hw, head_border)


## Panier : corps trapezoidal (plus large en haut) + anse courbe au-dessus
func _draw_basket_icon(img: Image, color: Color) -> void:
	var s := float(img.get_width())
	var body_top := s * 0.45
	var body_bottom := s * 0.85
	var top_half_width := s * 0.32
	var bottom_half_width := s * 0.18
	var center_x := s * 0.5

	var y := int(body_top)
	while y <= int(body_bottom):
		var t: float = (float(y) - body_top) / (body_bottom - body_top)
		var half_width: float = lerp(top_half_width, bottom_half_width, t)
		var x_start := int(round(center_x - half_width))
		var x_end := int(round(center_x + half_width))
		for x in range(x_start, x_end + 1):
			_set_pixel_safe(img, x, y, color)
		y += 1

	var handle_top := s * 0.12
	var handle_span := s * 0.22
	var steps := 24
	for i in range(steps + 1):
		var t2 := float(i) / float(steps)
		var x2: float = center_x - handle_span + t2 * (handle_span * 2.0)
		var arc: float = sin(t2 * PI)  # 0 aux extremites, 1 au sommet de l'anse
		var y2: float = body_top - (body_top - handle_top) * arc
		_plot_blob(img, Vector2(x2, y2), 1, color)


func _fill_circle(img: Image, cx: float, cy: float, r: float, color: Color) -> void:
	var ir := int(ceil(r))
	for dx in range(-ir, ir + 1):
		for dy in range(-ir, ir + 1):
			if dx * dx + dy * dy <= r * r:
				var x: int = int(cx) + dx
				var y: int = int(cy) + dy
				if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
					img.set_pixel(x, y, color)


## Remplit un quadrilatere convexe (a,b,c,d dans l'ordre) via 2 triangles.
func _fill_quad(img: Image, a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	_fill_triangle(img, a, b, c, color)
	_fill_triangle(img, a, c, d, color)


## Trace un segment epais comme un rectangle plein (contour net), plutot que
## des tampons ronds empiles (_draw_thick_line) qui, sur un petit canevas,
## debordent et recouvrent les formes voisines (bug constate le 2026-07-05
## sur la hache/pioche : la tete grise disparaissait completement).
func _stroke_segment(img: Image, from: Vector2, to: Vector2, half_width: float, color: Color) -> void:
	var dir := (to - from).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var c1 := from + perp * half_width
	var c2 := from - perp * half_width
	var c3 := to - perp * half_width
	var c4 := to + perp * half_width
	_fill_quad(img, c1, c2, c3, c4, color)


## Remplit un rectangle plein (coordonnees flottantes, utilise pour l'icone
## pause) - meme principe que _fill_triangle mais pour un rectangle simple.
func _fill_rect_px(img: Image, x: float, y: float, w: float, h: float, color: Color) -> void:
	var x0 := int(round(x))
	var y0 := int(round(y))
	var x1 := int(round(x + w))
	var y1 := int(round(y + h))
	for py in range(y0, y1):
		for px in range(x0, x1):
			_set_pixel_safe(img, px, py, color)


## Trace un trait epais entre deux points (utilise pour les manches d'outils).
## thickness (rayon du trait, en pixels) : parametre optionnel, garde 1 par
## defaut pour les appels existants (paniers/icones de temps).
func _draw_thick_line(img: Image, from: Vector2, to: Vector2, color: Color, thickness: int = 1) -> void:
	var dist := from.distance_to(to)
	var steps := int(dist) * 2 + 1
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := from.lerp(to, t)
		_plot_blob(img, p, thickness, color)


## Peint un petit disque de pixels autour de "center" (rayon en pixels)
func _plot_blob(img: Image, center: Vector2, radius: int, color: Color) -> void:
	var cx := int(round(center.x))
	var cy := int(round(center.y))
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				_set_pixel_safe(img, cx + dx, cy + dy, color)


## Remplit un triangle plein (utilise pour la lame de la hache)
func _fill_triangle(img: Image, a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	var min_x := int(floor(min(a.x, min(b.x, c.x))))
	var max_x := int(ceil(max(a.x, max(b.x, c.x))))
	var min_y := int(floor(min(a.y, min(b.y, c.y))))
	var max_y := int(ceil(max(a.y, max(b.y, c.y))))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			if _point_in_triangle(p, a, b, c):
				_set_pixel_safe(img, x, y, color)


func _point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := _triangle_sign(p, a, b)
	var d2 := _triangle_sign(p, b, c)
	var d3 := _triangle_sign(p, c, a)
	var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)


func _triangle_sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


## set_pixel securise (ignore silencieusement les coordonnees hors image)
func _set_pixel_safe(img: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or x >= img.get_width() or y < 0 or y >= img.get_height():
		return
	img.set_pixel(x, y, color)
