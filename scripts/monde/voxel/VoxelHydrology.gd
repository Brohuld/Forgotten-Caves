extends RefCounted
## Generation des lacs/riviere/cascades - la partie la plus retravaillee du
## terrain (voir memoires "regles riviere/cascade", "spec forme cascade").
##
## Comme VoxelVeins.gd/VoxelMeshBuilder.gd, ne prend jamais de reference
## typee vers VoxelWorld.gd lui-meme (une reference typee generique ne
## resout pas les constantes de script, voir leurs notes de tete).
## WIDTH/DEPTH sont recus en parametres a chaque appel de
## compute_water_columns() (comme water_noise/hill_height_at), PAS dupliques
## en constantes - une duplication ici avait cause le bug C19 (carte passee
## de 100x100 a 250x250 sans mettre a jour ce fichier). HEIGHT reste une
## const ; les LAKE_*/RIVER_* de base aussi, MAIS le nombre de lacs/le rayon
## max sont desormais calcules par taille de carte (_lake_count()/
## _lake_radius_max(), a partir de WIDTH/DEPTH) - voir leur doc plus bas.

var WIDTH: int
var DEPTH: int
const HEIGHT := 50

## Nombre de lacs et rayon max, mis a l'echelle par taille de carte
## (2026-07-10, demande explicite Francois). Nombre de lacs PROPORTIONNEL A
## LA SURFACE (reference : LAKE_COUNT_REFERENCE lacs a une carte
## LAKE_COUNT_REFERENCE_SIZE x LAKE_COUNT_REFERENCE_SIZE) -> voir
## _lake_count() : 2 a 50x50, 8 a 100x100, 50 a 250x250. Rayon max donne
## explicitement par Francois par taille de carte (PAS une formule) -> voir
## _lake_radius_max() : LAKE_RADIUS_MAX_BY_SIZE. LAKE_RADIUS_MIN reste
## identique pour les 3 tailles (4.0, avant 5.0).
const LAKE_COUNT_REFERENCE := 2
const LAKE_COUNT_REFERENCE_SIZE := 50
const LAKE_RADIUS_MIN := 4.0
const LAKE_RADIUS_MAX_BY_SIZE := {50: 7.0, 100: 8.0, 250: 19.0}
## Essai 2026-07-08 (carte 250x250) : plusieurs rivieres independantes au
## lieu d'une seule fixe - voir _place_rivers()/_place_one_river() plus bas.
## Reversible (voir sauvegarde outputs/staging/backups/
## VoxelHydrology.gd.single-river-2026-07-08) si le rendu ne convient pas.
const RIVER_COUNT_MIN := 1
const RIVER_COUNT_MAX := 3
## Largeur aleatoire par riviere (2026-07-10, demande explicite Francois -
## "largeur de chaque riviere aleatoire, entre 1 et 3, rattachee a la seed"),
## tiree dans _place_one_river() via le meme flux "hydrologie" que
## start/end - voir la var locale river_half_width plus bas.
const RIVER_HALF_WIDTH_MIN := 1
const RIVER_HALF_WIDTH_MAX := 3

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
func compute_water_columns(p_water_noise: FastNoiseLite, p_hill_height_at: Callable, p_width: int, p_depth: int) -> Dictionary:
	water_noise = p_water_noise
	hill_height_at = p_hill_height_at
	WIDTH = p_width
	DEPTH = p_depth

	var cols: Dictionary = {}
	var hill_overrides: Dictionary = {}
	var waterfalls: Dictionary = {}
	# Dict separe pour les colonnes de BERGE a reveler (pas de l'eau, juste
	# du terrain solide) le long d'une cascade - voir _place_one_river plus bas.
	var bank_faces: Dictionary = {}
	# Dict separe (2026-07-10, fix "lac creuse par la riviere") : marque
	# UNIQUEMENT les cases posees par _place_lakes, distinct de hill_overrides/
	# cols qui melangent lacs+rivieres - voir _place_one_river plus bas pour
	# pourquoi cette distinction est necessaire (lac et riviere doivent
	# partager le meme niveau d'eau la ou ils se rejoignent).
	var lake_cols: Dictionary = {}
	_place_lakes(cols, hill_overrides, lake_cols)
	_place_rivers(cols, hill_overrides, waterfalls, bank_faces, lake_cols)
	return {"cols": cols, "hill_overrides": hill_overrides, "waterfalls": waterfalls, "bank_faces": bank_faces}


## Nombre de lacs proportionnel a la SURFACE de la carte (voir
## LAKE_COUNT_REFERENCE/LAKE_COUNT_REFERENCE_SIZE) - au moins 1.
func _lake_count() -> int:
	var surface_ratio: float = float(WIDTH * DEPTH) / float(LAKE_COUNT_REFERENCE_SIZE * LAKE_COUNT_REFERENCE_SIZE)
	return maxi(1, int(round(LAKE_COUNT_REFERENCE * surface_ratio)))


## Rayon max donne explicitement par taille de carte (LAKE_RADIUS_MAX_BY_SIZE)
## - repli sur la valeur 250 si WIDTH ne correspond a aucune taille connue
## (garde-fou, StartMenu.gd ne propose que 50/100/250).
func _lake_radius_max() -> float:
	return float(LAKE_RADIUS_MAX_BY_SIZE.get(WIDTH, LAKE_RADIUS_MAX_BY_SIZE[250]))


## Place _lake_count() lacs a des centres aleatoires (marge de 12 blocs par
## rapport aux bords, pour eviter un lac coupe net par le bord de la carte),
## contour legerement irregulier via water_noise (sinon un cercle parfait,
## trop artificiel). Chaque lac tire une profondeur
## (LAKE_DEPTH_MIN..LAKE_DEPTH_MAX) une seule fois, appliquee a toutes ses
## cases - voir generate_flat_terrain pour comment la profondeur devient des
## niveaux d'eau reels. Flux GameRandom dedie "hydrologie" (idem dans
## _place_river) pour rester deterministe a graine egale - voir GameRandom.gd.
##
## Fix bug de bordure (2026-07-10, meme famille que le fix R1 riviere - voir
## [[project_forgotten_caves_river_rules]]) : hill_overrides n'est plus ecrit
## que pour les cases REELLEMENT dans le cercle d'eau (test d+n*3.0<radius) -
## avant, il etait ecrit pour TOUT le rectangle englobant (rive comprise),
## forcant la rive au meme niveau que l'eau et supprimant tout mur possible.
func _place_lakes(cols: Dictionary, hill_overrides: Dictionary, lake_cols: Dictionary) -> void:
	var rng: RandomNumberGenerator = GameRandom.get_rng("hydrologie")
	var lake_count: int = _lake_count()
	var radius_max: float = _lake_radius_max()
	for i in range(lake_count):
		var cx := rng.randi_range(12, WIDTH - 12)
		var cz := rng.randi_range(12, DEPTH - 12)
		var radius := rng.randf_range(LAKE_RADIUS_MIN, radius_max)
		var depth := rng.randi_range(LAKE_DEPTH_MIN, LAKE_DEPTH_MAX)
		var margin := int(radius) + 3
		var min_x := maxi(0, cx - margin)
		var max_x := mini(WIDTH - 1, cx + margin)
		var min_z := maxi(0, cz - margin)
		var max_z := mini(DEPTH - 1, cz + margin)
		for x in range(min_x, max_x + 1):
			for z in range(min_z, max_z + 1):
				var d: float = Vector2(x - cx, z - cz).length()
				var n: float = water_noise.get_noise_2d(float(x), float(z))  # -1..1
				if d + n * 3.0 < radius:
					var pos := Vector2i(x, z)
					hill_overrides[pos] = 0
					lake_cols[pos] = true
					# Si un lac precedent ou la riviere couvre deja cette case,
					# on garde la profondeur la plus grande (pas d'ecrasement).
					cols[pos] = maxi(int(cols.get(pos, 0)), depth)


## Point d'entree pour 1 a RIVER_COUNT_MAX rivieres independantes (essai
## 2026-07-08, carte 250x250 - voir commentaire pres de RIVER_COUNT_MIN/MAX).
## Chaque riviere est placee par un appel separe a _place_one_river()
## (algorithme inchange - voir sa doc), qui ecrit dans les MEMES
## dictionnaires partages "cols"/"hill_overrides"/"waterfalls"/"bank_faces".
## Limite connue et ACCEPTEE pour cet essai : si deux rivieres se croisent,
## la seconde ecrase silencieusement le palier ("hill_overrides") de la
## premiere sur les colonnes communes (pas de fusion intelligente comme pour
## les lacs, qui gardent la plus grande profondeur) - peut donner une petite
## marche visuelle au croisement. A revoir si le rendu en jeu pose probleme.
func _place_rivers(cols: Dictionary, hill_overrides: Dictionary, waterfalls: Dictionary, bank_faces: Dictionary, lake_cols: Dictionary) -> void:
	var rng: RandomNumberGenerator = GameRandom.get_rng("hydrologie")
	var river_count: int = rng.randi_range(RIVER_COUNT_MIN, RIVER_COUNT_MAX)
	for i in range(river_count):
		_place_one_river(cols, hill_overrides, waterfalls, bank_faces, lake_cols)


## Riviere traversant la carte d'un bord a l'autre (X ou Z au hasard), legere
## ondulation sinusoidale, largeur ALEATOIRE par riviere (RIVER_HALF_WIDTH_MIN
## .. RIVER_HALF_WIDTH_MAX blocs de demi-largeur, voir river_half_width plus
## bas), profondeur fixe RIVER_DEPTH. Appelee 1 a RIVER_COUNT_MAX fois par
## _place_rivers() ci-dessus
## (une fois par riviere), chaque appel etant independant (nouveaux tirages
## horizontal/start/end a chaque fois).
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
## Geometrie sensible (gel leve le 2026-07-08, modifiable normalement -
## voir [[feedback_waterfall_shape_frozen]]) : regles physiques completes
## R1-R3 (riviere)/C1-C5 (cascade), validees par simulation sur plusieurs
## milliers de cartes generees hors-jeu - voir [[project_forgotten_caves_river_rules]]
## (memoire dediee, regles et historique des cas limites deja rencontres, ne
## pas dupliquer ce contenu ici) et bien verifier ces regles apres toute
## modification. Renommee _place_river -> _place_one_river le 2026-07-08
## (essai multi-rivieres) SANS toucher au corps de la fonction ci-dessous.
func _place_one_river(cols: Dictionary, hill_overrides: Dictionary, waterfalls: Dictionary, bank_faces: Dictionary, lake_cols: Dictionary) -> void:
	# Flux GameRandom dedie "hydrologie" (meme flux que _place_lakes),
	# UNIQUEMENT sur ces 4 tirages initiaux - le reste de la fonction
	# (geometrie riviere/cascade R1-R3/C1-C5) est deterministe une
	# fois ces 4 valeurs fixees.
	var rng: RandomNumberGenerator = GameRandom.get_rng("hydrologie")
	var horizontal: bool = rng.randf() < 0.5
	var length: int = WIDTH if horizontal else DEPTH
	var cross_size: int = DEPTH if horizontal else WIDTH
	var start: float = rng.randf_range(cross_size * 0.25, cross_size * 0.75)
	var end: float = rng.randf_range(cross_size * 0.25, cross_size * 0.75)
	# Largeur ALEATOIRE de CETTE riviere (voir RIVER_HALF_WIDTH_MIN/MAX) - une
	# valeur differente par riviere, deterministe a seed egale. bank_margin
	# suit la meme largeur tiree (ne peut plus etre const, contrairement a
	# avant, puisqu'elle depend desormais d'un tirage).
	var river_half_width: int = rng.randi_range(RIVER_HALF_WIDTH_MIN, RIVER_HALF_WIDTH_MAX)
	var bank_margin: int = river_half_width
	const R1_WALL_MARGIN: int = 1

	# Etape 1 : centre du lit, rangee par rangee (sinusoide, purement
	# visuelle, R3) - et pour CHAQUE rangee, la liste REELLE des colonnes
	# cross qu'elle couvre (row_columns[i]) : c'est cette liste, pas le
	# centre, qui servira de reference a l'Etape 3 pour une rangee de
	# cascade (voir commentaire principal ci-dessus). Le sondage de relief
	# (natural_ground) regarde en plus bank_margin cases de chaque cote de
	# la largeur (la future berge, R1), pour qu'un palier commun ne depasse
	# jamais le terrain de la berge.
	#
	# R1_WALL_MARGIN (2026-07-10, fix REGRESSION R1) : le palier ne doit
	# jamais seulement etre INFERIEUR OU EGAL au relief le plus bas sonde -
	# une egalite donne un mur de hauteur 0, donc invisible. Avec un relief
	# tres plat/quantifie en entiers (V2, HILL_MIN..HILL_MAX=1..5), cette
	# egalite se produit tres tot et se propage a toute la riviere (le
	# palier est un minimum courant qui reste ensuite sur ce plateau) - c'est
	# la cause du bug "aucun mur, partout, des le depart" signale par
	# Francois. Fix GARANTI PAR CONSTRUCTION (pas probabiliste) : on
	# soustrait R1_WALL_MARGIN au minimum sonde AVANT de calculer le palier,
	# donc le palier est TOUJOURS strictement sous le point le plus bas de
	# la berge+lit, jamais egal. Voir [[project_forgotten_caves_river_rules]].
	#
	# 2026-07-10 (fix "lac creuse par la riviere") : R1_WALL_MARGIN ne doit
	# JAMAIS s'appliquer contre une case DEJA COUVERTE D'EAU (lac ou une
	# riviere precedente de cette meme passe, voir "cols") - ce n'est pas une
	# berge a sonder pour garantir un mur, c'est de l'eau que la riviere doit
	# REJOINDRE AU MEME NIVEAU. Avant ce fix, une case de lac (hauteur 0)
	# sondee comme point le plus bas etait traitee comme du terrain sec et
	# abaissee de R1_WALL_MARGIN, creusant un creux d'exactement 1 bloc a la
	# jonction riviere/lac. Desormais la marge est appliquee PAR ECHANTILLON
	# (uniquement sur les points secs), pas sur le minimum final.
	var natural_ground: Array = []
	var row_columns: Array = []  # Array[Array[int]] : colonnes cross reelles de chaque rangee
	for i in range(length):
		# max(length - 1, 1) protege contre une division par zero si length
		# valait 1 (non atteignable avec WIDTH/DEPTH=250 actuels), sans
		# changer le resultat pour les tailles de carte reelles.
		var t: float = float(i) / float(max(length - 1, 1))
		var center: float = lerp(start, end, t) + sin(t * PI * 3.0) * (cross_size * 0.08)

		var columns: Array = []
		for offset in range(-river_half_width, river_half_width + 1):
			var cross: int = int(round(center)) + offset
			if cross < 0 or cross >= cross_size:
				continue
			columns.append(cross)
		row_columns.append(columns)

		var lowest_here: int = 999
		for offset in range(-river_half_width - bank_margin, river_half_width + bank_margin + 1):
			var cross2: int = int(round(center)) + offset
			if cross2 < 0 or cross2 >= cross_size:
				continue
			var hx: int = i if horizontal else cross2
			var hz: int = cross2 if horizontal else i
			var sample_pos := Vector2i(hx, hz)
			# Priorite a hill_overrides (deja pose par _place_lakes) sur le
			# relief brut, sinon une zone de lac deja aplatie fausserait le
			# relief "naturel" sonde ici.
			var ground_here: int = int(hill_overrides.get(sample_pos, hill_height_at.call(hx, hz)))
			if not cols.has(sample_pos):
				ground_here -= R1_WALL_MARGIN
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
			# Ne JAMAIS ecraser le niveau d'une case de LAC (voir le commentaire
			# pres de R1_WALL_MARGIN plus haut) - le lac reste la reference,
			# la riviere doit deja avoir calcule le meme palier a cet endroit
			# (grace au fix de sondage ci-dessus) ; on evite ici toute
			# reecriture, meme redondante, et surtout aucune cascade fictive a
			# l'interieur d'un lac.
			if lake_cols.has(pos):
				continue
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
			for m in range(1, bank_margin + 1):
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
