extends RefCounted
## Generation des lacs/riviere/cascades - la partie la plus retravaillee du
## terrain (voir memoires "regles riviere/cascade", "spec forme cascade").
##
## Comme VoxelVeins.gd/VoxelMeshBuilder.gd, ne prend jamais de reference
## typee vers VoxelWorld.gd lui-meme (une reference typee generique ne
## resout pas les constantes de script, voir leurs notes de tete).
## WIDTH/DEPTH/HEIGHT/LAKE_*/RIVER_* sont dupliques ici en constantes (meme
## convention que WIDTH/DEPTH ailleurs dans ce projet - plusieurs scripts
## dupliquent ces valeurs et doivent etre mis a jour ensemble). Seuls
## water_noise (instance seedee a chaque partie) et _hill_height_at (depend
## de l'export hill_amplitude) sont vraiment dynamiques - recus en
## parametres a chaque appel de compute_water_columns(), jamais dupliques.

const WIDTH := 100
const DEPTH := 100
const HEIGHT := 50

const LAKE_COUNT := 2
const LAKE_RADIUS_MIN := 5.0
const LAKE_RADIUS_MAX := 9.0
const RIVER_HALF_WIDTH := 3

const LAKE_DEPTH_MIN := 2
const LAKE_DEPTH_MAX := 3
const RIVER_DEPTH := 2

var water_noise: FastNoiseLite
var hill_height_at: Callable


## Point d'entree, appele par VoxelWorld._compute_water_columns() (facade
## fine conservee sur VoxelWorld.gd - generate_flat_terrain() n'a pas eu
## besoin de changer). Calcule l'ensemble des colonnes (x,z) couvertes par
## un lac ou la riviere. Renvoie un Dictionary a 4 cles - "cols" (profondeur
## d'eau, cle = Vector2i), "hill_overrides" (decalage de relief FORCE pour
## ces colonnes - lacs aplatis a 0, riviere en paliers hauts/bas),
## "waterfalls" (colonnes de cascade, cle = Vector2i, valeur = {"top": y,
## "bottom": y, ...}), "bank_faces" (colonnes de berge a reveler comme une
## falaise, meme forme que "waterfalls").
func compute_water_columns(p_water_noise: FastNoiseLite, p_hill_height_at: Callable) -> Dictionary:
	water_noise = p_water_noise
	hill_height_at = p_hill_height_at

	var cols: Dictionary = {}
	var hill_overrides: Dictionary = {}
	var waterfalls: Dictionary = {}
	# Dict separe pour les colonnes de BERGE a reveler (pas de l'eau, juste
	# du terrain solide) le long d'une cascade - voir _place_river plus bas.
	var bank_faces: Dictionary = {}
	_place_lakes(cols, hill_overrides)
	_place_river(cols, hill_overrides, waterfalls, bank_faces)
	return {"cols": cols, "hill_overrides": hill_overrides, "waterfalls": waterfalls, "bank_faces": bank_faces}


## Place LAKE_COUNT lacs a des centres aleatoires (marge de 12 blocs par
## rapport aux bords, pour eviter un lac coupe net par le bord de la carte),
## contour legerement irregulier via water_noise (sinon un cercle parfait,
## trop artificiel). Chaque lac tire une profondeur
## (LAKE_DEPTH_MIN..LAKE_DEPTH_MAX) une seule fois, appliquee a toutes ses
## cases - voir generate_flat_terrain pour comment la profondeur devient des
## niveaux d'eau reels. Le relief est aplati (hill_overrides=0) sur tout le
## rectangle englobant du lac (pas seulement le cercle d'eau) - un lac a une
## surface plate par nature, meme entoure de collines ; simplification
## assumee (pas de vraie berge en pente). Flux GameRandom dedie
## "hydrologie" (idem dans _place_river) pour rester deterministe a graine
## egale - voir GameRandom.gd.
func _place_lakes(cols: Dictionary, hill_overrides: Dictionary) -> void:
	var rng: RandomNumberGenerator = GameRandom.get_rng("hydrologie")
	for i in range(LAKE_COUNT):
		var cx := rng.randi_range(12, WIDTH - 12)
		var cz := rng.randi_range(12, DEPTH - 12)
		var radius := rng.randf_range(LAKE_RADIUS_MIN, LAKE_RADIUS_MAX)
		var depth := rng.randi_range(LAKE_DEPTH_MIN, LAKE_DEPTH_MAX)
		var margin := int(radius) + 3
		var min_x := maxi(0, cx - margin)
		var max_x := mini(WIDTH - 1, cx + margin)
		var min_z := maxi(0, cz - margin)
		var max_z := mini(DEPTH - 1, cz + margin)
		for x in range(min_x, max_x + 1):
			for z in range(min_z, max_z + 1):
				hill_overrides[Vector2i(x, z)] = 0
				var d: float = Vector2(x - cx, z - cz).length()
				var n: float = water_noise.get_noise_2d(float(x), float(z))  # -1..1
				if d + n * 3.0 < radius:
					var pos := Vector2i(x, z)
					# Si un lac precedent ou la riviere couvre deja cette case,
					# on garde la profondeur la plus grande (pas d'ecrasement).
					cols[pos] = maxi(int(cols.get(pos, 0)), depth)


## Riviere traversant la carte d'un bord a l'autre (X ou Z au hasard), legere
## ondulation sinusoidale, RIVER_HALF_WIDTH blocs de large, profondeur fixe
## RIVER_DEPTH.
##
## Algorithme en 3 etapes :
## 1. tracer le centre du lit, rangee par rangee, sans cascade (ondulation
##    sinusoidale, cross_size = largeur perpendiculaire au trajet).
## 2. reperer les ruptures de niveau le long du trajet (relief le plus bas
##    sonde sur la largeur du lit + berges) - un seul palier par rangee,
##    valable pour toute la largeur (jamais d'escalier entre rangees d'une
##    meme cascade), calcule en un seul sens depuis l'extremite au relief le
##    plus haut vers l'extremite la plus basse (jamais un point milieu).
## 3. a chaque rangee ou le palier vient de baisser par rapport a la rangee
##    juste en amont : poser une cascade en reprenant EXACTEMENT les colonnes
##    reellement posees a la rangee du dessus (used_columns), jamais un
##    nouveau centre recalcule pour cette rangee - condition necessaire pour
##    garantir les regles C2/C3/C5 ci-dessous.
##
## GEOMETRIE GELEE : regles physiques completes R1-R3 (riviere)/C1-C5
## (cascade), validees par simulation sur plusieurs milliers de cartes
## generees hors-jeu. Ne pas modifier sans autorisation explicite - voir
## [[project_forgotten_caves_river_rules]] (memoire dediee, regles et
## historique des cas limites deja rencontres, ne pas dupliquer ce contenu
## ici).
func _place_river(cols: Dictionary, hill_overrides: Dictionary, waterfalls: Dictionary, bank_faces: Dictionary) -> void:
	# Flux GameRandom dedie "hydrologie" (meme flux que _place_lakes),
	# UNIQUEMENT sur ces 3 tirages initiaux - le reste de la fonction
	# (geometrie riviere/cascade R1-R3/C1-C5, GELEE) est deterministe une
	# fois ces 3 valeurs fixees.
	var rng: RandomNumberGenerator = GameRandom.get_rng("hydrologie")
	var horizontal: bool = rng.randf() < 0.5
	var length: int = WIDTH if horizontal else DEPTH
	var cross_size: int = DEPTH if horizontal else WIDTH
	var start: float = rng.randf_range(cross_size * 0.25, cross_size * 0.75)
	var end: float = rng.randf_range(cross_size * 0.25, cross_size * 0.75)
	const BANK_MARGIN: int = RIVER_HALF_WIDTH

	# Etape 1 : centre du lit, rangee par rangee (sinusoide, purement
	# visuelle, R3) - et pour CHAQUE rangee, la liste REELLE des colonnes
	# cross qu'elle couvre (row_columns[i]) : c'est cette liste, pas le
	# centre, qui servira de reference a l'Etape 3 pour une rangee de
	# cascade (voir commentaire principal ci-dessus). Le sondage de relief
	# (natural_ground) regarde en plus BANK_MARGIN cases de chaque cote de
	# la largeur (la future berge, R1), pour qu'un palier commun ne depasse
	# jamais le terrain de la berge.
	var natural_ground: Array = []
	var row_columns: Array = []  # Array[Array[int]] : colonnes cross reelles de chaque rangee
	for i in range(length):
		# max(length - 1, 1) protege contre une division par zero si length
		# valait 1 (non atteignable avec WIDTH/DEPTH=100 actuels), sans
		# changer le resultat pour les tailles de carte reelles.
		var t: float = float(i) / float(max(length - 1, 1))
		var center: float = lerp(start, end, t) + sin(t * PI * 3.0) * (cross_size * 0.08)

		var columns: Array = []
		for offset in range(-RIVER_HALF_WIDTH, RIVER_HALF_WIDTH + 1):
			var cross: int = int(round(center)) + offset
			if cross < 0 or cross >= cross_size:
				continue
			columns.append(cross)
		row_columns.append(columns)

		var lowest_here: int = 999
		for offset in range(-RIVER_HALF_WIDTH - BANK_MARGIN, RIVER_HALF_WIDTH + BANK_MARGIN + 1):
			var cross2: int = int(round(center)) + offset
			if cross2 < 0 or cross2 >= cross_size:
				continue
			var hx: int = i if horizontal else cross2
			var hz: int = cross2 if horizontal else i
			# Priorite a hill_overrides (deja pose par _place_lakes) sur le
			# relief brut, sinon une zone de lac deja aplatie fausserait le
			# relief "naturel" sonde ici.
			var ground_here: int = int(hill_overrides.get(Vector2i(hx, hz), hill_height_at.call(hx, hz)))
			lowest_here = mini(lowest_here, ground_here)
		natural_ground.append(lowest_here)

	# Etape 2 : le "haut" du trajet = l'extremite (bord de carte) dont le
	# relief naturel est le plus haut - jamais un point milieu (R2). On
	# descend en escalier en UN SEUL SENS depuis ce bout vers l'autre,
	# rangee par rangee, chaque palier = min(palier de la rangee precedente,
	# relief naturel de cette rangee) - jamais au-dessus du relief, et
	# toujours connecte a la rangee juste avant.
	var starts_at_zero: bool = natural_ground[0] >= natural_ground[length - 1]
	var shelf: Array = []
	shelf.resize(length)
	if starts_at_zero:
		shelf[0] = natural_ground[0]
		for i in range(1, length):
			shelf[i] = mini(shelf[i - 1], natural_ground[i])
	else:
		shelf[length - 1] = natural_ground[length - 1]
		for i in range(length - 2, -1, -1):
			shelf[i] = mini(shelf[i + 1], natural_ground[i])

	# Direction de l'ecoulement : constante sur tout le trajet (R2 - on
	# descend toujours du bout "haut" vers le bout "bas").
	var downstream_dx: int = 0
	var downstream_dz: int = 0
	if starts_at_zero:
		if horizontal: downstream_dx = 1
		else: downstream_dz = 1
	else:
		if horizontal: downstream_dx = -1
		else: downstream_dz = -1

	# Etape 3 : pour chaque rangee, EN SUIVANT L'ECOULEMENT une par une
	# depuis le haut, si le palier vient de baisser par rapport a la rangee
	# juste en amont (immediatement precedente dans ce sens), c'est une
	# cascade.
	#
	# Quand DEUX rangees de cascade se suivent immediatement (le relief
	# descend de plusieurs petits paliers d'affilee), une cascade doit
	# reprendre les colonnes REELLEMENT posees a la rangee du dessus - pas
	# la liste THEORIQUE "row_columns[upstream_i]" calculee a l'Etape 1, qui
	# peut differer d'une case si cette rangee amont est elle-meme une
	# rangee de cascade (elle a elle-meme emprunte sa propre rangee amont).
	# "used_columns[i]" retient donc les colonnes REELLEMENT posees a
	# chaque rangee, rangee par rangee, DANS L'ORDRE REEL DU COURANT (voir
	# "order" ci-dessous - necessaire car, quand le courant va du bout haut
	# vers l'indice 0, la rangee amont a un indice PLUS GRAND, qui doit donc
	# etre traitee AVANT). Une rangee de cascade reprend
	# "used_columns[upstream_i]" (ce qui a reellement ete pose), jamais
	# "row_columns[upstream_i]" (la liste theorique jamais mise a jour).
	var order: Array = range(length) if starts_at_zero else range(length - 1, -1, -1)
	var used_columns: Array = []
	used_columns.resize(length)

	for i in order:
		var upstream_i: int = i - 1 if starts_at_zero else i + 1

		var is_falls_row: bool = false
		var upper_shelf: int = shelf[i]
		if upstream_i >= 0 and upstream_i < length and shelf[i] < shelf[upstream_i]:
			is_falls_row = true
			upper_shelf = shelf[upstream_i]

		var upper_surface_y: int = HEIGHT - 1 + upper_shelf
		var lower_surface_y: int = HEIGHT - 1 + shelf[i]

		var columns: Array = used_columns[upstream_i] if is_falls_row else row_columns[i]

		for cross in columns:
			var pos: Vector2i = Vector2i(i, cross) if horizontal else Vector2i(cross, i)
			cols[pos] = maxi(int(cols.get(pos, 0)), RIVER_DEPTH)
			hill_overrides[pos] = shelf[i]
			if is_falls_row:
				waterfalls[pos] = {
					"top": upper_surface_y,
					"bottom": lower_surface_y - RIVER_DEPTH + 1,
					"dx": downstream_dx,
					"dz": downstream_dz,
					"pool_surface_y": lower_surface_y,
				}

		# Les colonnes de berge juste a cote du lit REELLEMENT utilise a
		# cette rangee (min/max de "columns" ci-dessus, PAS un centre) sont
		# reperees pour etre revelees sur la meme hauteur que la chute
		# d'eau - la berge redevient une falaise visible plutot qu'un mur
		# gris cache sous le brouillard de guerre.
		if is_falls_row and not columns.is_empty():
			var min_cross: int = columns[0]
			var max_cross: int = columns[columns.size() - 1]
			for m in range(1, BANK_MARGIN + 1):
				for bcross in [min_cross - m, max_cross + m]:
					if bcross < 0 or bcross >= cross_size:
						continue
					var bpos: Vector2i = Vector2i(i, bcross) if horizontal else Vector2i(bcross, i)
					bank_faces[bpos] = {
						"top": upper_surface_y,
						"bottom": lower_surface_y - RIVER_DEPTH + 1,
					}

		# Retient ce qui a ete REELLEMENT pose a cette rangee, pour que la
		# PROCHAINE rangee en aval (si elle est elle-meme une rangee de
		# cascade) emprunte cette liste reelle - jamais la liste theorique
		# "row_columns[i]" (voir commentaire principal ci-dessus).
		used_columns[i] = columns
