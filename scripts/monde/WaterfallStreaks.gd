extends Node3D
## Sprint 49 (2026-07-04, demande explicite : "il faudrait aussi avoir des
## traits (?) en bleu clair et blanc pour montrer l'eau qui tombe").
## La cascade elle-meme (voir VoxelWorld._place_river/generate_flat_terrain)
## n'est qu'un bloc EAU plein et immobile - correct comme volume d'eau, mais
## ca ne "montre" pas visuellement une chute. Ce script ajoute, PAR-DESSUS ce
## volume, des particules decoratives (memes principes que les traits de
## pluie de WeatherSystem.gd/_build_particles : GPUParticles3D + BoxMesh fin,
## materiau non-eclaire/transparent) qui tombent en continu le long de la
## face de chaque colonne de cascade - contrairement a la pluie, une seule
## petite emission ETROITE par colonne (pas toute la carte), toujours active
## (une cascade coule qu'il pleuve ou non, contrairement a la pluie/neige qui
## dependent de la meteo).
##
## Genere une fois au demarrage a partir de VoxelWorld.get_waterfall_columns()
## (positions + hauteurs calculees par _place_river) - depend donc de l'ordre
## des noeuds dans Main.tscn (VoxelWorld doit avoir fini generate_flat_terrain
## dans son _ready() AVANT que ce script ne lise get_waterfall_columns(), meme
## principe deja utilise par Forest.gd/BerryBushes.gd pour _pick_dry_position).

const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")

@onready var voxel_world: Node3D = %VoxelWorld

## Nombre de "traits" (particules visibles simultanement) par colonne de
## cascade - volontairement modeste : le but est quelques traits nets et
## visibles, pas un rideau de pluie dense.
const STREAKS_PER_COLUMN := 10

## Couleur unique pale bleu/blanc (satisfait "bleu clair ET blanc" sans avoir
## besoin d'un degrade par particule - une teinte tres pale lit comme les deux
## a la fois, coherent avec WATER_COLOR de VoxelWorld.gd).
const STREAK_COLOR := Color(0.85, 0.95, 1.0, 0.6)

## Vitesse de chute (unites/s) - plus lente qu'une goutte de pluie en chute
## libre : ceci represente un filet d'eau qui glisse le long de la face de la
## cascade, pas une chute depuis le ciel.
const FALL_SPEED_MIN := 2.0
const FALL_SPEED_MAX := 3.2


func _ready() -> void:
	if voxel_world == null:
		return
	var columns: Array = voxel_world.get_waterfall_columns()
	for col in columns:
		add_child(_build_streak_particles(col))


## Construit un unique GPUParticles3D pour une colonne de cascade donnee -
## meme structure que WeatherSystem._build_particles (process_material +
## BoxMesh fin en draw_pass_1 + materiau non-eclaire/transparent), mais une
## boite d'emission tres etroite (une seule colonne de 1x1 bloc) et une chute
## bornee a la hauteur reelle de cette cascade (voir "top"/"bottom").
func _build_streak_particles(col: Dictionary) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "CascadeStreaks_%d_%d" % [int(col["x"]), int(col["z"])]

	var top_y: float = float(col["top"]) + 1.0
	var bottom_y: float = float(col["bottom"])
	var fall_height: float = maxf(top_y - bottom_y, 0.5)
	particles.position = Vector3(float(col["x"]) + 0.5, top_y, float(col["z"]) + 0.5)

	var process_mat := ParticleProcessMaterial.new()
	process_mat.direction = Vector3(0, -1, 0)
	process_mat.spread = 1.5
	process_mat.gravity = Vector3(0, 0, 0)  # vitesse constante : un filet d'eau, pas une chute libre acceleree
	process_mat.initial_velocity_min = FALL_SPEED_MIN
	process_mat.initial_velocity_max = FALL_SPEED_MAX
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_mat.emission_box_extents = Vector3(0.4, 0.02, 0.4)
	process_mat.color = STREAK_COLOR
	particles.process_material = process_mat

	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.4, 0.05)  # trait fin allonge vers le bas
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	box.material = mat
	particles.draw_pass_1 = box

	particles.amount = STREAKS_PER_COLUMN
	# Duree de vie = temps pour parcourir toute la hauteur de la cascade a la
	# vitesse moyenne - les traits disparaissent donc pile au niveau du bassin
	# bas, jamais en dessous.
	particles.lifetime = fall_height / ((FALL_SPEED_MIN + FALL_SPEED_MAX) * 0.5)
	particles.speed_scale = DayNightCycleScript.game_speed  # respecte pause/x1/x2/x4, comme Birds.gd/_sim_time
	particles.emitting = true
	# AABB genereux en espace local (particules crees par code, pas par
	# l'editeur - meme remarque que WeatherSystem._build_particles).
	particles.visibility_aabb = AABB(
		Vector3(-1.0, -fall_height - 1.0, -1.0),
		Vector3(2.0, fall_height + 2.0, 2.0)
	)

	return particles


## Sprint 49 : garde speed_scale synchronise avec le multiplicateur de temps
## du jeu (pause/x1/x2/x4) - sans ca les traits de cascade tourneraient a
## vitesse fixe meme en pause, contrairement a tout le reste (nains, cycle
## jour/nuit, nuages/oiseaux via _sim_time).
func _process(_delta: float) -> void:
	for child in get_children():
		if child is GPUParticles3D:
			child.speed_scale = DayNightCycleScript.game_speed
