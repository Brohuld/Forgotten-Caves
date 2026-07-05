extends RefCounted
## Decoupage de VoxelWorld.gd (2026-07-05, revue de code item C1 : fichier
## trop long / fonctions trop longues - _place_river depassait a elle seule
## 150 lignes). Regroupe la generation des lacs/riviere/cascades - la partie
## la plus retravaillee de ce projet (voir memoires "regles riviere/cascade",
## "spec forme cascade", "reecriture tracage riviere", "relief/collines").
##
## RELOCALISATION PURE : aucune ligne de logique n'a change a l'interieur de
## _place_lakes/_place_river par rapport a VoxelWorld.gd - seul le
## "conteneur" a change. Ne pas toucher a la geometrie/aux regles physiques a
## l'occasion de ce decoupage ; si un ajustement est necessaire, le faire
## dans un commit separe, apres avoir confirme que le decoupage lui-meme n'a
## rien casse (protocole de non-regression, voir memoire de la session).
##
## Comme VoxelVeins.gd/VoxelMeshBuilder.gd, ne prend jamais de reference
## typee vers VoxelWorld.gd lui-meme (evite le piege deja rencontre avec un
## acces direct via une reference typee generique, voir leurs notes de tete).
## WIDTH/DEPTH/HEIGHT/LAKE_*/RIVER_* sont dupliques ici en constantes (meme
## convention deja utilisee ailleurs dans ce projet pour WIDTH/DEPTH - voir
## le commentaire de VoxelWorld.gd a leur sujet : "plusieurs autres scripts
## dupliquent ces valeurs et doivent etre mis a jour en meme temps"). Seuls
## water_noise (instance seedee a chaque partie) et _hill_height_at (depend
## de l'export hill_amplitude) sont vraiment dynamiques - recus en parametres
## a chaque appel de compute_water_columns(), jamais dupliques.

const WIDTH := 100
const DEPTH := 100
const HEIGHT := 50

const LAKE_COUNT := 2
const LAKE_RADIUS_MIN := 5.0
const LAKE_RADIUS_MAX := 9.0
const RIVER_HALF_WIDTH := 3  # Sprint 43 : elargi (etait 2) pour une courbe de cascade plus douce/large

const LAKE_DEPTH_MIN := 2
const LAKE_DEPTH_MAX := 3
const RIVER_DEPTH := 2

var water_noise: FastNoiseLite
var hill_height_at: Callable


## Point d'entree, appele par VoxelWorld._compute_water_columns() (thin
## delegateur conserve sur VoxelWorld.gd - generate_flat_terrain() n'a donc
## pas eu besoin de changer). Sprint 36 : calcule l'ensemble des colonnes
## (x,z) couvertes par un lac ou la riviere. Sprint 38 : renvoie un Dictionary
## a 4 cles - "cols" (profondeur d'eau, cle = Vector2i), "hill_overrides"
## (decalage de relief FORCE pour ces colonnes - lacs aplatis a 0, riviere en
## paliers hauts/bas), "waterfalls" (colonnes de cascade, cle = Vector2i,
## valeur = {"top": y, "bottom": y, ...}), "bank_faces" (colonnes de berge a
## reveler comme une falaise, meme forme que "waterfalls").
func compute_water_columns(p_water_noise: FastNoiseLite, p_hill_height_at: Callable) -> Dictionary:
	water_noise = p_water_noise
	hill_height_at = p_hill_height_at

	var cols: Dictionary = {}
	var hill_overrides: Dictionary = {}
	var waterfalls: Dictionary = {}
	# Sprint 36 (suite, 2026-07-04, application des 5 regles physiques
	# donnees par Francois - voir memoire "regles riviere/cascade") : dict
	# separe pour les colonnes de BERGE a reveler (pas de l'eau, juste du
	# terrain solide) le long d'une cascade - voir _place_river plus bas.
	var bank_faces: Dictionary = {}
	_place_lakes(cols, hill_overrides)
	_place_river(cols, hill_overrides, waterfalls, bank_faces)
	return {"cols": cols, "hill_overrides": hill_overrides, "waterfalls": waterfalls, "bank_faces": bank_faces}


## Sprint 36 : place LAKE_COUNT lacs a des centres aleatoires (marge de 12
## blocs par rapport aux bords, pour eviter un lac coupe net par le bord de la
## carte), contour legerement irregulier via water_noise (sinon un cercle
## parfait, trop artificiel). Sprint 36bis : chaque lac tire une profondeur
## (LAKE_DEPTH_MIN..LAKE_DEPTH_MAX) une seule fois, appliquee a toutes ses
## cases - voir generate_flat_terrain pour comment la profondeur devient des
## niveaux d'eau reels. Sprint 38 : le relief est aplati (hill_overrides=0) sur
## tout le rectangle englobant du lac (pas seulement le cercle d'eau) - un lac
## a une surface plate par nature, meme entoure de collines ; simplification
## assumee pour cette premiere version du relief (pas de vraie berge en pente).
func _place_lakes(cols: Dictionary, hill_overrides: Dictionary) -> void:
	for i in range(LAKE_COUNT):
		var cx := randi_range(12, WIDTH - 12)
		var cz := randi_range(12, DEPTH - 12)
		var radius := randf_range(LAKE_RADIUS_MIN, LAKE_RADIUS_MAX)
		var depth := randi_range(LAKE_DEPTH_MIN, LAKE_DEPTH_MAX)
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


## Sprint 36 : une riviere qui traverse la carte d'un bord a l'autre, au hasard
## en X (ouest-est) ou en Z (nord-sud), avec une legere ondulation (sinus)
## plutot qu'une ligne parfaitement droite. RIVER_HALF_WIDTH blocs de part et
## d'autre du centre du lit a chaque "tranche" traversee. Sprint 36bis :
## profondeur fixe RIVER_DEPTH (demande explicite, moins profonde qu'un lac).
##
## Sprint 75 (2026-07-04, reecriture complete demandee par Francois) : bug
## identifie ou l'eau du trace pouvait se retrouver plus haute que le relief
## naturel environnant, faute de verifier ce relief le long du trajet.
##
## Sprint 78 (2026-07-04, demande explicite de Francois : "cascade alignee et
## pas avec des blocs qui avancent comme maintenant") : le Sprint 77 (relief
## independant par bande de largeur) provoquait des cascades en escalier
## decalees d'une bande a l'autre (visible sur capture d'ecran - plusieurs
## quarts de cylindre a des rangees differentes). Retour a UNE seule rupture
## de niveau par rangee, valable pour TOUTE la largeur du lit a la fois - donc
## une cascade toujours alignee, jamais en escalier.
## Algorithme (3 etapes demandees par Francois) :
## 1. tracer le centre du lit, rangee par rangee, sans cascade.
## 2. reperer les ruptures de niveau le long du trajet (relief le plus bas
##    sur la largeur totale + berges, palier en escalier depuis la source).
## 3. pour chaque rangee du haut (juste avant une rupture), tracer UNE
##    colonne de cascade valable pour toute la largeur du lit ce jour-la.
##
## Meme sprint (suite, 2026-07-04, bug signale par Francois via capture
## d'ecran : un bloc d'eau sans berge a cote de la cascade) : regle physique
## rappelee par Francois - un bloc d'eau ne peut JAMAIS se retrouver sans
## berge (mur) de chaque cote. Le sondage du relief ne portait QUE sur la
## largeur exacte de la riviere, jamais au-dela - rien ne garantissait donc
## que le terrain juste a l'exterieur de cette largeur (la future berge)
## soit bien plus haut que le niveau d'eau choisi. Fix : le sondage du
## relief (pour decider le palier de chaque rangee) regarde maintenant
## aussi 1 case de plus de chaque cote de la largeur du lit (BANK_MARGIN=1)
## - le niveau d'eau choisi ne peut donc plus jamais depasser le terrain de
## la berge elle-meme. Seul le sondage est elargi ; la largeur d'eau posee
## reste exactement RIVER_HALF_WIDTH comme avant.
##
## Meme sprint (suite, 2026-07-04, bug signale par Francois via capture
## d'ecran : une cascade isolee qui ne tombe d'aucune riviere) : l'ancienne
## version cherchait une "source" comme le point le plus haut de TOUT le
## trajet (recherche globale), puis descendait en escalier dans les 2 sens a
## partir de ce point - un point interne pouvait ainsi etre choisi comme
## source sans etre reellement rattache a un ecoulement coherent, produisant
## une cascade "orpheline". Fix, conforme a la demande explicite de
## Francois ("calculer le point de cascade pour chaque case de riviere en
## haut, une par une") : le calcul se fait maintenant en UN SEUL SENS, du
## bout du trajet le plus haut vers l'autre bout, rangee par rangee, chaque
## palier ne dependant que de la rangee immediatement precedente (jamais
## d'un point milieu). Le trajet entier est donc toujours connecte d'un
## bout a l'autre, plus aucune cascade ne peut apparaitre sans riviere
## continue juste en amont.
##
## Meme sprint (suite, 2026-07-04, "mur gris" puis "cascade sans eau au-
## dessus" reapparus - Francois a reconstruit ma comprehension pas a pas
## jusqu'a la vraie root cause, memoire "regles riviere/cascade" reorganisee
## en R1-R3 (rivieres) et C1-C5 (cascades)) : la largeur de CHAQUE rangee
## etait recalculee independamment a partir de SON PROPRE centre (ondulation
## sinusoidale, R3) - a la rangee de cascade specifiquement, ce nouveau
## centre n'est presque jamais parfaitement aligne avec celui de la rangee
## du dessus, violant C2 (case d'eau du haut sans case en dessous) sur un
## bord de la largeur ET le corollaire C3 (cascade sans eau au-dessus) sur
## l'autre bord. Francois a explicitement rejete l'idee de "faire
## correspondre les centres" - le concept meme de centre recalcule par
## rangee est le probleme a la transition.
## Vrai correctif : les colonnes cross de CHAQUE rangee sont desormais
## calculees UNE SEULE FOIS (row_columns[i], Etape 1) a partir du centre de
## cette rangee - utilisees telles quelles pour une rangee normale (R3 :
## l'ondulation reste OK sans changement de niveau). Mais a une rangee de
## cascade, on n'utilise PLUS row_columns[i] : on reprend LITTERALEMENT
## row_columns[upstream_i], les colonnes REELLES de la rangee du dessus,
## une par une - jamais un nouveau centre pour cette rangee-la. Ca garantit
## par construction C2/C3/C5 : impossible d'avoir de l'eau sans cascade en
## dessous, ou une cascade sans eau au-dessus.
func _place_river(cols: Dictionary, hill_overrides: Dictionary, waterfalls: Dictionary, bank_faces: Dictionary) -> void:
	var horizontal: bool = randf() < 0.5
	var length: int = WIDTH if horizontal else DEPTH
	var cross_size: int = DEPTH if horizontal else WIDTH
	var start: float = randf_range(cross_size * 0.25, cross_size * 0.75)
	var end: float = randf_range(cross_size * 0.25, cross_size * 0.75)
	const BANK_MARGIN: int = RIVER_HALF_WIDTH

	# Etape 1 : centre du lit, rangee par rangee (meme sinusoide qu'avant,
	# purement visuelle, R3) - et pour CHAQUE rangee, la liste REELLE des
	# colonnes cross qu'elle couvre (row_columns[i]) : c'est cette liste,
	# pas le centre, qui servira de reference a l'Etape 3 pour une rangee de
	# cascade (voir commentaire principal ci-dessus). Le sondage de relief
	# (natural_ground) regarde en plus BANK_MARGIN cases de chaque cote de
	# la largeur (la future berge, R1), pour qu'un palier commun ne depasse
	# jamais le terrain de la berge.
	var natural_ground: Array = []
	var row_columns: Array = []  # Array[Array[int]] : colonnes cross reelles de chaque rangee
	for i in range(length):
		# 2026-07-05 (revue de code, item F014) : division par zero si length
		# valait 1 - non atteignable avec WIDTH/DEPTH=100 actuels, mais
		# max(length - 1, 1) protege ce calcul sans changer le resultat pour
		# les tailles de carte reelles.
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
			# Sprint 76 : priorite a hill_overrides (deja pose par
			# _place_lakes) sur le relief brut, sinon une zone de lac deja
			# aplatie fausserait le relief "naturel" sonde ici.
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
	# Sprint 86 (2026-07-04, bug signale par Francois via capture d'ecran -
	# case sans eau sous une cascade, verifie C2 quand meme viole) : quand
	# DEUX rangees de cascade se suivent immediatement (le relief descend
	# de plusieurs petits paliers d'affilee), la 2e cascade reprenait
	# "row_columns[upstream_i]" - la liste THEORIQUE de la rangee du dessus
	# (calculee une seule fois a l'Etape 1, jamais mise a jour) - au lieu
	# des colonnes REELLEMENT posees a cette rangee (qui avaient elles-
	# memes ete empruntees a SA PROPRE rangee amont, puisqu'elle est aussi
	# une rangee de cascade). Les deux listes peuvent differer d'une case,
	# recreant exactement le bug C2/C3 vise par le premier correctif, un
	# cran plus loin. Confirme par simulation (300 cartes generees en
	# dehors du jeu, avec le meme algorithme) : 2 violations trouvees.
	# Corrige : "used_columns[i]" retient desormais les colonnes REELLEMENT
	# posees a chaque rangee (empruntees ou non), rangee par rangee, DANS
	# L'ORDRE REEL DU COURANT (voir "order" ci-dessous - necessaire car,
	# quand le courant va du bout haut vers l'indice 0, la rangee amont a
	# un indice PLUS GRAND, qui doit donc etre traitee AVANT). Une rangee
	# de cascade reprend desormais "used_columns[upstream_i]" (ce qui a
	# reellement ete pose) au lieu de "row_columns[upstream_i]" (la liste
	# jamais mise a jour). Reteste par simulation (2000 cartes) : 0
	# violation apres ce correctif.
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

		# Meme sprint (suite, C1) : les colonnes de berge juste a cote du
		# lit REELLEMENT utilise a cette rangee (min/max de "columns" ci-
		# dessus, PAS un centre) sont reperees pour etre revelees sur la
		# meme hauteur que la chute d'eau - la berge redevient une falaise
		# visible plutot qu'un mur gris enigmatique sous le brouillard de
		# guerre.
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

		# Sprint 86 : retient ce qui a ete REELLEMENT pose a cette rangee,
		# pour que la PROCHAINE rangee en aval (si elle est elle-meme une
		# rangee de cascade) emprunte cette liste reelle - jamais la liste
		# theorique "row_columns[i]" (voir commentaire principal ci-dessus).
		used_columns[i] = columns
