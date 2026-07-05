extends Node3D
## Sprint 81 (2026-07-04, demande explicite de Francois : le degrade de
## couleur sur la forme de cascade (WaterfallShapes.gd) s'est avere "trop
## difficile" a regler visuellement - remplace par de petits nuages d'ecume,
## plus foncEs en haut de la cascade et plus clairs en bas, legerement
## mobiles ("tout petits nuages eventuellement mobiles"). Meme technique de
## "blobs" (spheres aplaties regroupees) que CloudSystem.gd (nuages du ciel),
## mais des amas minuscules ancres a chaque colonne de cascade (meme source
## de donnees que WaterfallShapes.gd/WaterfallStreaks.gd :
## VoxelWorld.get_waterfall_columns()) plutot que derivant sur toute la
## carte au gre du vent.
##
## Mouvement : chaque petit amas oscille doucement autour d'un point fixe
## (le haut ou le bas de SA cascade) via un sinus/cosinus dephase par
## instance - un mouvement de "flottement" credible sans faire deriver le
## nuage loin de sa cascade (contrairement aux nuages du ciel qui, eux,
## parcourent toute la carte).

const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")

@onready var voxel_world: Node3D = %VoxelWorld
## Sprint 81 (suite, 2026-07-04, demande explicite de Francois : "l'ecume doit
## etre obscurcie par la meteo et l'heure, comme les nuages") - memes sources
## que CloudSystem.gd : la meteo (teinte/force) et la lumiere directionnelle
## (nuit) pour assombrir l'ecume exactement comme les nuages du ciel.
@onready var _weather_system: Node = %WeatherSystem
@onready var _light: DirectionalLight3D = %DirectionalLight3D

## "Tout petits nuages" - un amas minuscule de quelques bosses par cascade,
## bien plus petit que les nuages du ciel (CloudSystem.gd).
const PUFFS_PER_CLOUD := 3
const PUFF_SCALE_MIN := 0.09
const PUFF_SCALE_MAX := 0.15

## Amplitude/vitesse du leger flottement autour du point d'ancrage.
const DRIFT_RADIUS := 0.12
const DRIFT_SPEED_MIN := 0.5
const DRIFT_SPEED_MAX := 1.0

## Sprint 81 (suite) : avancee du nuage du bas dans le sens du courant, pour
## sortir de sous le quart de cylindre PLEIN (rayon 1.0) qui le masquait sinon.
const FOAM_FORWARD_OFFSET := 0.9

## Sprint 81 : couleurs demandees - plus fonce (gris-bleu) en haut de la
## cascade, plus clair (quasi blanc) en bas - remplace le degrade continu
## qui etait fait directement sur le maillage de la cascade.
const TOP_FOAM_COLOR := Color(0.55, 0.75, 0.88, 0.55)
const BOTTOM_FOAM_COLOR := Color(0.95, 0.98, 1.0, 0.65)

## Sprint 81 (suite) : assombrissement nocturne - memes constantes de principe
## que CloudSystem.gd (jamais totalement noir, encore visible au clair de
## lune), mais un poil moins sombre qu'un nuage du ciel (l'ecume reste tout
## pres de l'eau/de la cascade, jamais dans l'ombre totale).
const NIGHT_FOAM_COLOR := Color(0.16, 0.18, 0.24)
const NIGHT_DARKEN_STRENGTH := 0.7

var _mmi: MultiMeshInstance3D
var _anchor: Array = []          # Vector3 par instance - point fixe (haut/bas de la cascade)
var _phase: Array = []           # float par instance - dephasage du flottement
var _drift_speed: Array = []     # float par instance
var _local_scale: Array = []     # Vector3 par instance
var _instance_base_color: Array = []  # Color par instance - couleur de base (avant meteo/nuit)
var _time: float = 0.0

## Sprint 85 (2026-07-04, demande explicite : "les cascades doivent
## disparaitre avec leur niveau de riviere, comme les rivieres elles memes")
## - "top" de la cascade (indice de bloc) memorise par instance (pas de noeud
## par instance ici, tout est dans UN SEUL MultiMesh partage - contrairement a
## WaterfallShapes/Streaks qui ont un noeud par cascade a cacher/montrer).
var _col_top: Array = []        # float par instance
var _view_level: int = 999999   # tres haut par defaut = rien de cache tant que CameraRig n'a pas encore appele update_view_level


# 2026-07-05 (revue de code, item F016) : _ready() (~58 lignes) decoupe en
# sous-fonctions - meme contenu qu'avant, rien de fonctionnel ne change.
func _ready() -> void:
	if voxel_world == null:
		return
	# 2026-07-05 (correctif revue de code C6, meme cause que C2-C5/I9) :
	# randomize() retire - reinitialisait le generateur aleatoire global de
	# facon non deterministe, APRES que VoxelWorld._ready() ait deja fixe sa
	# graine. Purement decoratif ici (l'ecume n'a pas besoin d'etre
	# reproductible), mais casse la chaine de determinisme pour tout script
	# suivant dans Main.tscn - retire pour rester coherent avec le reste.
	_build_shared_mesh()
	_spawn_foam_clouds()
	_finalize_instances()


## Cree les 2 petits nuages d'ecume (haut/bas) de chaque colonne de cascade.
func _spawn_foam_clouds() -> void:
	# Sprint 81 (suite, 2026-07-04, bug signale par Francois : "aucune ecume
	# ne s'affiche") : "top"/"pool_surface_y" sont des INDICES de bloc, pas
	# des positions monde directement utilisables - un bloc d'indice Y occupe
	# l'espace de Y a Y+1, sa surface visible/marchable est donc a Y+1 (meme
	# convention que WaterfallShapes._build_shape, qui place son origine a
	# "pool_surface_y + 1.0", jamais juste "pool_surface_y"). Les nuages
	# etaient places ~1 bloc trop bas, a l'interieur du sol/de l'eau pleine -
	# donc invisibles, caches par cette geometrie opaque. Correction : +1.0
	# avant le petit decalage decoratif.
	# Sprint 81 (suite, 2026-07-04, bug signale par Francois via capture
	# d'ecran : "l'ecume a decale les cascades") : le decalage horizontal
	# (x/z) etait fixe a +0.5 sur les 2 axes, alors que WaterfallShapes.
	# _build_shape (position REELLE de la cascade, deja calee/confirmee au
	# Sprint 64) utilise +0.0 sur l'axe du SENS DU COURANT et +0.5 seulement
	# sur l'axe de la LARGEUR - sinon l'ancrage se retrouve decale d'un demi-
	# bloc dans le sens du courant, sur la colonne de berge voisine au lieu
	# de la colonne de cascade elle-meme (exactement le "mur gris avec de
	# l'ecume dessus" visible sur la capture). Meme formule reprise ici pour
	# que les nuages restent alignes avec la vraie position de la cascade.
	var columns: Array = voxel_world.get_waterfall_columns()
	for col in columns:
		var dx: int = int(col["dx"])
		var dz: int = int(col["dz"])
		var x_offset: float = 0.0 if dx != 0 else 0.5
		var z_offset: float = 0.0 if dz != 0 else 0.5
		var top_y: float = float(col["top"]) + 1.0
		var pool_y: float = float(col.get("pool_surface_y", col["bottom"])) + 1.0
		var x: float = float(col["x"]) + x_offset
		var z: float = float(col["z"]) + z_offset
		# Sprint 81 (suite, 2026-07-04, demande explicite de Francois : "abaisse
		# les nuages d'ecume du haut de la cascade de 10 pixels") : le monde 3D
		# n'a pas de "pixels" (c'est une position en unites de bloc, pas un
		# ecran) - approxime par une petite baisse de 0.12 unite (~10px a un
		# zoom de camera courant). A ajuster encore si ce n'est pas assez/trop.
		_add_cloud(Vector3(x, top_y + 0.23, z), TOP_FOAM_COLOR, float(col["top"]))
		# Sprint 81 (suite, 2026-07-04, bug signale par Francois : "aucune ecume
		# en bas" - hypothese de Francois confirmee) : a l'origine de la forme
		# (x/z sans avancee), le nuage se retrouve juste contre le mur, dans
		# l'epaisseur du quart de cylindre PLEIN (Sprint 61) qui le masque -
		# avance donc le nuage du bas vers le bord exterieur de la cascade,
		# dans le sens du courant (dx,dz), jusqu'a FOAM_FORWARD_OFFSET (proche
		# du rayon de la forme, 1.0) pour sortir de sous la cascade, dans le
		# bassin a l'air libre. Baisse aussi de 0.12 unite supplementaire,
		# comme demande.
		var bx: float = x + float(dx) * FOAM_FORWARD_OFFSET
		var bz: float = z + float(dz) * FOAM_FORWARD_OFFSET
		# Petit nuage clair juste au-dessus du bassin (l'ecume de l'impact).
		_add_cloud(Vector3(bx, pool_y + 0.13, bz), BOTTOM_FOAM_COLOR, float(col["top"]))


## Active les instances du MultiMesh une fois tous les blobs ajoutes.
func _finalize_instances() -> void:
	_mmi.multimesh.instance_count = _anchor.size()
	_update_all_colors(Color.WHITE, 0.0, 0.0)
	_update_all_transforms()


## Un seul maillage "unite" (sphere aplatie) partage par tous les blobs de
## tous les petits nuages - meme principe que CloudSystem._build_shared_mesh
## et que les cimes d'arbres (Forest.gd).
func _build_shared_mesh() -> void:
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = MultiMesh.new()
	_mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_mmi.multimesh.use_colors = true
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	_mmi.multimesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mmi.material_override = mat
	add_child(_mmi)


## Ajoute les quelques bosses (PUFFS_PER_CLOUD) d'un petit nuage d'ecume,
## chacune avec son propre point d'ancrage (autour du centre donne), son
## dephasage de flottement et sa couleur (avec un leger jitter individuel).
func _add_cloud(center: Vector3, color: Color, col_top: float) -> void:
	for i in range(PUFFS_PER_CLOUD):
		var jitter := Vector3(randf_range(-0.10, 0.10), randf_range(-0.04, 0.04), randf_range(-0.10, 0.10))
		_anchor.append(center + jitter)
		_phase.append(randf_range(0.0, TAU))
		_drift_speed.append(randf_range(DRIFT_SPEED_MIN, DRIFT_SPEED_MAX))
		var s: float = randf_range(PUFF_SCALE_MIN, PUFF_SCALE_MAX)
		_local_scale.append(Vector3(s, s * 0.7, s))
		var a: float = clampf(color.a + randf_range(-0.08, 0.08), 0.2, 0.8)
		_instance_base_color.append(Color(color.r, color.g, color.b, a))
		_col_top.append(col_top)  # Sprint 85 : pour update_view_level


## Sprint 81 (suite) : meme ordre que CloudSystem._process - la lumiere
## directionnelle (DayNightCycle) et la meteo (WeatherSystem) ont deja
## tourne ce meme frame avant ce script (meme ordre des noeuds dans
## Main.tscn), donc lire leurs valeurs ici est a jour.
func _process(delta: float) -> void:
	_time += delta * DayNightCycleScript.game_speed
	_update_all_transforms()

	var day_energy: float = DayNightCycleScript.LIGHT_ENERGY[1]
	var night_factor: float = 1.0 - clampf(_light.light_energy / maxf(day_energy, 0.001), 0.0, 1.0)

	if _weather_system:
		_update_all_colors(_weather_system.cloud_tint_color(), _weather_system.cloud_tint_strength(), night_factor)
	else:
		_update_all_colors(Color.WHITE, 0.0, night_factor)


func _update_all_transforms() -> void:
	for idx in range(_anchor.size()):
		# Sprint 85 : puff cache (echelle zero) si sa cascade est au-dessus du
		# niveau de vue courant - meme convention que VoxelWorld ("y >
		# view_level" = cache).
		if _col_top[idx] > float(_view_level):
			_mmi.multimesh.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		var anchor: Vector3 = _anchor[idx]
		var phase: float = _phase[idx]
		var speed: float = _drift_speed[idx]
		var drift := Vector3(
			sin(_time * speed + phase) * DRIFT_RADIUS,
			cos(_time * speed * 0.7 + phase) * DRIFT_RADIUS * 0.5,
			cos(_time * speed + phase * 1.3) * DRIFT_RADIUS
		)
		var xform := Transform3D(Basis().scaled(_local_scale[idx]), anchor + drift)
		_mmi.multimesh.set_instance_transform(idx, xform)


## Sprint 85 : appele par CameraRig a chaque changement de niveau de vue -
## stocke la valeur et rafraichit immediatement (sans attendre le prochain
## _process) pour eviter un frame de decalage visible.
func update_view_level(level: int) -> void:
	_view_level = level
	_update_all_transforms()


## Sprint 81 (suite) : meme calcul que CloudSystem._update_all_colors -
## teinte meteo d'abord (interpolee selon sa force), puis assombrissement
## nocturne par-dessus (jamais totalement noir).
func _update_all_colors(tint: Color, strength: float, night_factor: float) -> void:
	for idx in range(_instance_base_color.size()):
		var base: Color = _instance_base_color[idx]
		var weathered: Color = base.lerp(Color(tint.r, tint.g, tint.b, base.a), strength)
		var final_color: Color = weathered.lerp(
			Color(NIGHT_FOAM_COLOR.r, NIGHT_FOAM_COLOR.g, NIGHT_FOAM_COLOR.b, weathered.a),
			night_factor * NIGHT_DARKEN_STRENGTH
		)
		_mmi.multimesh.set_instance_color(idx, final_color)
