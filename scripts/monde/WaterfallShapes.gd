extends Node3D
## Sprint 52 (2026-07-04, demande explicite de Francois : "quart de cylindre"
## pour le mur de cascade, "quart de sphere" pour les coins - meme technique
## que le tronc des arbres, une forme toute faite, jamais de triangle dessine
## a la main).
##
## Astuce : un CylinderMesh/SphereMesh est un cercle/une sphere COMPLET(E).
## Pour n'en montrer qu'un quart, on ne "coupe" rien nous-meme - on place la
## forme complete a cheval sur le coin solide (mur vertical de pierre au-
## dessus, bassin plat en dessous) : la roche/l'eau plate, deja opaques,
## recouvrent/masquent les 3/4 de la forme qui tombent dedans, et seul le
## quart qui depasse a l'air libre reste visible. C'est le meme principe
## qu'un arrondi de bord de table en 3D (bevel) : une forme ronde complete,
## a moitie enfoncee dans l'angle, dont on ne voit que la partie qui depasse.
##
## Colonnes du MILIEU du lit (is_corner=false) : un cylindre couche, axe
## horizontal le long de la largeur du lit (donc perpendiculaire au sens du
## courant) - vu de profil (dans le sens du courant), on voit son cercle
## complet, mais seul un quart depasse de l'angle mur/bassin -> le fameux
## "quart de cercle vu de profil" demande.
## Colonnes de BORD du lit (is_corner=true) : une sphere, au lieu d'un
## cylindre - elle est ronde dans TOUTES les directions (largeur ET
## profondeur), donc son quart visible se prolonge aussi vers l'exterieur du
## lit plutot que de s'arreter net - c'est le "quart de sphere" pour les coins.

@onready var voxel_world: Node3D = %VoxelWorld

# Sprint 53 (2026-07-04, bug signale par Francois : "pas de cylindre ni de
# sphere" - rien n'apparaissait du tout) : "voxel_world.WATER_COLOR" plantait
# _ready() avant meme le premier add_child - une const de script n'est PAS
# accessible via une variable typee generique Node3D (contrairement a une
# fonction comme get_waterfall_columns(), qui elle fonctionne bien en dispatch
# dynamique). Meme pattern que WeatherSystem.gd (VoxelWorldScript.WIDTH) :
# passer par le script preload pour lire une constante.
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")

## Rayon des formes = un demi-bloc, pour un raccord net avec la grille (le
## quart visible occupe alors exactement l'espace d'un bloc standard, comme
## demande : "un quart de cylindre de la taille d'un bloc standard").
const SHAPE_RADIUS := 0.5
const SHAPE_SEGMENTS := 16  # lisse (le tronc d'arbre utilise aussi un cylindre a segments, meme niveau de detail)

## Sprint 72 (2026-07-04, demande explicite : "on enleve l'eclairage, on prend
## la couleur de l'eau de la riviere en haut de cascade, et on decale vers le
## bleu clair en bas"). TOP_COLOR = couleur de l'eau de la riviere.
const TOP_COLOR := Color(0.45, 0.80, 0.98)  # identique a VoxelWorld.WATER_COLOR
const BOTTOM_COLOR := Color(0.65, 0.88, 1.0)  # bleu clair


## Couleur interpolee selon la hauteur locale y (0 = bas, radius = haut).
func _color_for_height(y: float, radius: float) -> Color:
	var t: float = clamp(y / radius, 0.0, 1.0)
	return BOTTOM_COLOR.lerp(TOP_COLOR, t)


## Construit un vrai quart de cylindre PLEIN (pas juste la peau courbe) via
## SurfaceTool - arc 0-90° ("haut" vers "droite"), plus les 2 capuchons plats
## (les 2 bouts, en eventail depuis l'axe) et les 2 faces planes radiales
## (a angle 0 et a angle 90°) qui referment le volume - sinon on ne voyait
## que la coquille exterieure (Sprint 61, signale par Francois : "tu peux
## remplir le quart de cylindre bleu ? pas seulement la surface").
## Sprint 72 : couleur par sommet (degrade), geometrie inchangee.
func _build_quarter_cylinder_mesh(radius: float, length: float, segments: int, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_len := length * 0.5
	var za := -half_len
	var zb := half_len

	# Surface courbe (coquille exterieure, deja presente avant Sprint 61)
	for i in range(segments):
		var a0 := deg_to_rad(90.0 * float(i) / float(segments))
		var a1 := deg_to_rad(90.0 * float(i + 1) / float(segments))
		var n0 := Vector3(sin(a0), cos(a0), 0.0)
		var n1 := Vector3(sin(a1), cos(a1), 0.0)
		var c0 := _color_for_height(n0.y * radius, radius)
		var c1 := _color_for_height(n1.y * radius, radius)
		var p0_a := n0 * radius + Vector3(0, 0, za)
		var p1_a := n1 * radius + Vector3(0, 0, za)
		var p0_b := n0 * radius + Vector3(0, 0, zb)
		var p1_b := n1 * radius + Vector3(0, 0, zb)
		st.set_normal(n0); st.set_color(c0); st.add_vertex(p0_a)
		st.set_normal(n1); st.set_color(c1); st.add_vertex(p1_a)
		st.set_normal(n1); st.set_color(c1); st.add_vertex(p1_b)
		st.set_normal(n0); st.set_color(c0); st.add_vertex(p0_a)
		st.set_normal(n1); st.set_color(c1); st.add_vertex(p1_b)
		st.set_normal(n0); st.set_color(c0); st.add_vertex(p0_b)

	# Sprint 61 : les 2 capuchons (eventail de triangles depuis l'axe central)
	var center_color := _color_for_height(0.0, radius)
	for i in range(segments):
		var a0 := deg_to_rad(90.0 * float(i) / float(segments))
		var a1 := deg_to_rad(90.0 * float(i + 1) / float(segments))
		var q0 := Vector3(sin(a0), cos(a0), 0.0) * radius
		var q1 := Vector3(sin(a1), cos(a1), 0.0) * radius
		var cq0 := _color_for_height(q0.y, radius)
		var cq1 := _color_for_height(q1.y, radius)
		# Capuchon arriere (za), normale vers -Z
		st.set_normal(Vector3(0, 0, -1)); st.set_color(center_color); st.add_vertex(Vector3(0, 0, za))
		st.set_normal(Vector3(0, 0, -1)); st.set_color(cq1); st.add_vertex(q1 + Vector3(0, 0, za))
		st.set_normal(Vector3(0, 0, -1)); st.set_color(cq0); st.add_vertex(q0 + Vector3(0, 0, za))
		# Capuchon avant (zb), normale vers +Z
		st.set_normal(Vector3(0, 0, 1)); st.set_color(center_color); st.add_vertex(Vector3(0, 0, zb))
		st.set_normal(Vector3(0, 0, 1)); st.set_color(cq0); st.add_vertex(q0 + Vector3(0, 0, zb))
		st.set_normal(Vector3(0, 0, 1)); st.set_color(cq1); st.add_vertex(q1 + Vector3(0, 0, zb))

	# Sprint 61 : les 2 faces planes radiales qui referment le volume - a
	# angle 0 (le "haut", face normale vers -X) et a angle 90° (le "droite",
	# face normale vers -Y).
	var top_pt := Vector3(0, radius, 0)
	var right_pt := Vector3(radius, 0, 0)
	var top_color := _color_for_height(radius, radius)
	st.set_normal(Vector3(-1, 0, 0)); st.set_color(center_color); st.add_vertex(Vector3(0, 0, za))
	st.set_normal(Vector3(-1, 0, 0)); st.set_color(top_color); st.add_vertex(top_pt + Vector3(0, 0, za))
	st.set_normal(Vector3(-1, 0, 0)); st.set_color(top_color); st.add_vertex(top_pt + Vector3(0, 0, zb))
	st.set_normal(Vector3(-1, 0, 0)); st.set_color(center_color); st.add_vertex(Vector3(0, 0, za))
	st.set_normal(Vector3(-1, 0, 0)); st.set_color(top_color); st.add_vertex(top_pt + Vector3(0, 0, zb))
	st.set_normal(Vector3(-1, 0, 0)); st.set_color(center_color); st.add_vertex(Vector3(0, 0, zb))

	st.set_normal(Vector3(0, -1, 0)); st.set_color(center_color); st.add_vertex(Vector3(0, 0, za))
	st.set_normal(Vector3(0, -1, 0)); st.set_color(center_color); st.add_vertex(Vector3(0, 0, zb))
	st.set_normal(Vector3(0, -1, 0)); st.set_color(center_color); st.add_vertex(right_pt + Vector3(0, 0, zb))
	st.set_normal(Vector3(0, -1, 0)); st.set_color(center_color); st.add_vertex(Vector3(0, 0, za))
	st.set_normal(Vector3(0, -1, 0)); st.set_color(center_color); st.add_vertex(right_pt + Vector3(0, 0, zb))
	st.set_normal(Vector3(0, -1, 0)); st.set_color(center_color); st.add_vertex(right_pt + Vector3(0, 0, za))

	var mesh := ArrayMesh.new()
	st.commit(mesh)
	mesh.surface_set_material(0, mat)
	return mesh


func _ready() -> void:
	if voxel_world == null:
		return
	var mat := StandardMaterial3D.new()
	# Sprint 73 (2026-07-04) : signale par Francois - la couleur de la riviere
	# varie avec le soleil/l'heure - DayNightCycle.gd change en continu
	# light_color/light_energy/l'ambiant. L'eau de la riviere utilise un
	# materiau ECLAIRE (VoxelWorld._make_material, roughness=1.0/metallic=0.0),
	# donc sa couleur affichee suit ces variations. UNSHADED ignorait tout ca
	# (couleur figee) ; retour a l'eclairage normal + memes roughness/metallic
	# que _make_material pour que la cascade reagisse identiquement a la
	# lumiere du soleil, a tout moment de la journee.
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.metallic = 0.0
	# Sprint 74 (2026-07-04, signale par Francois : reflet blanc en diagonale
	# sur la capture) : meme a roughness=1.0, Godot garde un reflet speculaire
	# de base (metallic_specular, 0.5 par defaut). La forme courbe (normales
	# variables) capte ce reflet a un endroit precis, contrairement a la
	# surface plate de l'eau au meme angle de vue - d'ou la bande blanche qui
	# ne "prend pas la couleur de l'eau". Desactive.
	mat.metallic_specular = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var columns: Array = voxel_world.get_waterfall_columns()
	for col in columns:
		add_child(_build_shape(col, mat))


## Sprint 56 (2026-07-04, demande explicite : "remplace tout ce code [le
## remplissage en blocs de VoxelWorld._place_river] par la forme qu'on vient
## de creer, en faisant attention que le haut du cylindre soit le point haut
## de la cascade") : un vrai quart de cylindre par colonne de cascade (voir
## _build_quarter_cylinder_mesh), a l'echelle REELLE de la chute (rayon =
## hauteur totale top-pool_surface_y), pas juste un petit biseau d'1 bloc.
## Position/orientation : l'origine du maillage (voir _build_quarter_cylinder_mesh,
## le centre du cercle) est placee exactement a la surface du bassin, a
## l'aplomb de la colonne - son point "haut" (local +Y, rayon au-dessus de
## l'origine) est donc bien EXACTEMENT au niveau du sommet reel de la cascade
## (col.top), et son point "droite" (local +X, rayon a cote de l'origine)
## rejoint la surface du bassin en s'eloignant dans le sens du courant. Une
## seule rotation autour de l'axe vertical (Y) suffit pour aligner cet axe
## "droite" sur la direction du courant (dx,dz) - contrairement au cylindre
## complet couche (Sprint 52-54), qui necessitait un axe couche errone.
func _build_shape(col: Dictionary, mat: StandardMaterial3D) -> MeshInstance3D:
	var dx: int = int(col["dx"])
	var dz: int = int(col["dz"])
	var pool_surface_y: float = float(col["pool_surface_y"])
	var radius: float = 1.0

	# Sprint 62 : hauteur confirmee bonne (pool_surface_y+1.0, meme convention
	# que get_top_block_y()+1 utilisee partout ailleurs, ex. Dwarf.gd).
	# Sprint 64 (2026-07-04, signale par Francois : "l'espace entre le mur et
	# la cascade", hauteur/rayon confirmes bons) : sur l'axe du SENS DU COURANT
	# (celui porte par dx/dz), le mur de pierre reel se trouve a la LIMITE
	# entre la colonne de cascade et la colonne amont precedente, c'est a dire
	# a la coordonnee brute du bloc (col.x ou col.z), PAS a son centre
	# (+0.5) - centrer sur cet axe plaçait l'origine un demi-bloc trop loin en
	# aval, creant l'espace visible. L'axe de LARGEUR (perpendiculaire au
	# courant), lui, reste centre (+0.5) : c'est le bon reglage confirme au
	# Sprint 63.
	var x_offset := 0.0 if dx != 0 else 0.5
	var z_offset := 0.0 if dz != 0 else 0.5

	var mi := MeshInstance3D.new()
	mi.mesh = _build_quarter_cylinder_mesh(radius, 1.0, SHAPE_SEGMENTS, mat)
	mi.position = Vector3(float(col["x"]) + x_offset, pool_surface_y + 1.0, float(col["z"]) + z_offset)
	mi.rotation.y = atan2(-float(dz), float(dx))
	return mi
