extends Node3D
## La cascade elle-meme (voir VoxelWorld._place_river/generate_flat_terrain)
## n'est qu'un bloc EAU plein et immobile - correct comme volume d'eau, mais
## ca ne "montre" pas visuellement une chute. Ce script ajoute, PAR-DESSUS ce
## volume, des petits traits decoratifs qui glissent en continu le long de la
## face de chaque colonne de cascade, en suivant la courbe exterieure du
## quart de cylindre de la cascade (voir WaterfallShapes.gd).
##
## Chaque trait est une MeshInstance3D dont la position est recalculee chaque
## frame par trigonometrie, exactement sur le meme cercle que la forme bleue
## (WaterfallShapes._build_shape, meme origine/rotation, meme rayon) - une
## animation codee a la main plutot qu'un systeme de particules Godot, pour
## un controle total sur le point de depart exact (le sommet de la courbe).
##
## Genere une fois au demarrage a partir de VoxelWorld.get_waterfall_columns()
## (positions + hauteurs calculees par _place_river) - depend donc de l'ordre
## des noeuds dans Main.tscn (VoxelWorld doit avoir fini generate_flat_terrain
## dans son _ready() AVANT que ce script ne lise get_waterfall_columns(), meme
## principe deja utilise par Forest.gd/BerryBushes.gd pour _pick_dry_position).

const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")

@onready var voxel_world: Node3D = %VoxelWorld

## Nombre de "traits" (visibles simultanement) par colonne de cascade -
## volontairement modeste : le but est quelques traits nets et visibles, pas
## un rideau de pluie dense.
const STREAKS_PER_COLUMN := 6

## Chaque trait tire au hasard une de ces 3 couleurs a sa creation (voir
## _build_streak_group), au lieu d'une teinte unique partagee par tous.
const STREAK_COLORS := [
	Color(0.97, 0.98, 1.0, 0.6),   # blanc
	Color(0.75, 0.90, 1.0, 0.6),   # bleu clair
	Color(0.30, 0.55, 0.85, 0.6),  # bleu fonce
]

## Vitesse angulaire (radians/s) le long du quart de cercle - un trait met
## entre PI/2 divise par ANGULAR_SPEED_MAX et ANGULAR_SPEED_MIN secondes pour
## parcourir toute la courbe (du haut jusqu'au bassin).
const ANGULAR_SPEED_MIN := 2.2
const ANGULAR_SPEED_MAX := 3.4

## Rayon reel de la forme (WaterfallShapes._build_shape, geometrie GELEE) -
## meme valeur ici pour que les traits suivent exactement la meme courbe que
## la forme bleue, pas touchee par ce script.
const CASCADE_RADIUS := 1.0

## Un materiau par couleur (voir STREAK_COLORS), construit une seule fois et
## partage entre tous les traits de cette couleur - evite de creer un
## nouveau materiau par trait individuel.
var _streak_materials: Array = []


func _ready() -> void:
	if voxel_world == null:
		return
	# Le generateur aleatoire global est deja correctement initialise a ce
	# point (VoxelWorld._ready() a deja fixe sa graine) - pas de randomize()
	# ici, purement decoratif mais garde la chaine de determinisme pour tout
	# script suivant dans Main.tscn.
	_build_streak_materials()
	var columns: Array = voxel_world.get_waterfall_columns()
	for col in columns:
		add_child(_build_streak_group(col))


## Construit les 3 materiaux (un par couleur de STREAK_COLORS), reutilises
## ensuite pour tous les traits de toutes les colonnes de cascade.
func _build_streak_materials() -> void:
	_streak_materials.clear()
	for c in STREAK_COLORS:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = c
		_streak_materials.append(mat)


## Un Node3D "support" par colonne de cascade, positionne/tourne exactement
## comme l'origine de WaterfallShapes._build_shape (meme centre de cercle,
## meme rotation autour de l'axe Y) - les traits, enfants de ce support,
## n'ont ensuite qu'a se positionner en coordonnees LOCALES sur le cercle
## (voir _process/_position_streak), la rotation du support s'occupant
## d'orienter tout ca dans le sens du courant.
func _build_streak_group(col: Dictionary) -> Node3D:
	var group := Node3D.new()
	group.name = "CascadeStreaks_%d_%d" % [int(col["x"]), int(col["z"])]

	var dx: int = int(col["dx"])
	var dz: int = int(col["dz"])
	var pool_surface_y: float = float(col.get("pool_surface_y", col["bottom"]))
	var x_offset: float = 0.0 if dx != 0 else 0.5
	var z_offset: float = 0.0 if dz != 0 else 0.5
	group.position = Vector3(float(col["x"]) + x_offset, pool_surface_y + 1.0, float(col["z"]) + z_offset)
	group.rotation.y = atan2(-float(dz), float(dx))
	# Voir WaterfallShapes.gd/update_view_level pour le detail - meme
	# principe, applique ici au groupe de traits de CETTE cascade.
	group.set_meta("waterfall_top", float(col["top"]))

	var box := BoxMesh.new()
	# Le trait reste TOUJOURS vertical (allonge sur Y), quel que soit sa
	# position sur la courbe - pas de rotation tangentielle a la courbe
	# (un trait tangentiel apparaitrait couche/horizontal a certains angles).
	box.size = Vector3(0.05, 0.3, 0.05)
	# Pas de materiau unique ici : chaque trait recoit le sien (voir boucle
	# ci-dessous, _streak_materials construits une fois dans _ready).

	# Flux GameRandom dedie ("cascade_traits") plutot que le RNG global -
	# reproductibilite par graine (revue de code M92).
	var rng: RandomNumberGenerator = GameRandom.get_rng("cascade_traits")
	for i in range(STREAKS_PER_COLUMN):
		var streak := MeshInstance3D.new()
		streak.mesh = box
		streak.material_override = _streak_materials[rng.randi() % _streak_materials.size()]
		# Depart etale sur toute la courbe (pas tous au sommet en meme temps),
		# sinon les traits arriveraient groupes/synchronises.
		var start_angle: float = rng.randf_range(0.0, PI * 0.5)
		var speed: float = rng.randf_range(ANGULAR_SPEED_MIN, ANGULAR_SPEED_MAX)
		# Decalage aleatoire fixe sur l'axe Z local (largeur du bloc,
		# perpendiculaire a la courbe) - sans ca, tous les traits d'une meme
		# colonne resteraient dans le meme plan, empiles au centre du bloc
		# plutot qu'etales dans sa largeur.
		var z_jitter: float = rng.randf_range(-0.35, 0.35)
		streak.set_meta("angle", start_angle)
		streak.set_meta("speed", speed)
		streak.set_meta("z_jitter", z_jitter)
		_position_streak(streak, start_angle, z_jitter)
		group.add_child(streak)

	return group


## Place un trait en coordonnees LOCALES sur le quart de cercle - angle=0 ->
## sommet de la courbe (Vector3(0, radius, 0), meme point que le sommet du
## quart de cylindre), angle=PI/2 -> niveau du bassin (Vector3(radius, 0, 0))
## - exactement la meme parametrisation que
## WaterfallShapes._build_quarter_cylinder_mesh (n = Vector3(sin(a), cos(a), 0)).
## z_jitter : decalage fixe sur la largeur du bloc (voir _build_streak_group).
## Le trait reste toujours vertical (pas de rotation tangentielle, voir
## box.size ci-dessus).
func _position_streak(streak: MeshInstance3D, angle: float, z_jitter: float) -> void:
	streak.position = Vector3(sin(angle), cos(angle), 0.0) * CASCADE_RADIUS + Vector3(0, 0, z_jitter)


## Fait avancer chaque trait le long de la courbe (angle croissant de 0 a
## PI/2), et le fait reboucler au sommet des qu'il atteint le bassin - un
## ecoulement continu, jamais interrompu. speed_scale du jeu (pause/x1/x2/
## x4) applique ici, comme le reste des elements animes de la carte.
func _process(delta: float) -> void:
	var scaled_delta: float = delta * DayNightCycleScript.game_speed
	for group in get_children():
		if not (group is Node3D):
			continue
		for streak in group.get_children():
			if not (streak is MeshInstance3D):
				continue
			var angle: float = float(streak.get_meta("angle", 0.0))
			var speed: float = float(streak.get_meta("speed", ANGULAR_SPEED_MIN))
			var z_jitter: float = float(streak.get_meta("z_jitter", 0.0))
			angle += speed * scaled_delta
			if angle > PI * 0.5:
				angle = fmod(angle, PI * 0.5)
			streak.set_meta("angle", angle)
			_position_streak(streak, angle, z_jitter)


## Cache/reaffiche chaque groupe de traits selon le niveau de vue courant -
## meme principe que WaterfallShapes.gd/update_view_level.
func update_view_level(level: int) -> void:
	for group in get_children():
		if group is Node3D and group.has_meta("waterfall_top"):
			group.visible = float(group.get_meta("waterfall_top")) <= float(level)
