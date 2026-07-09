extends Node3D
## Construit le mur d'eau visible d'une cascade : un quart de cylindre pour
## le milieu du lit, un quart de sphere pour les coins - meme technique que
## le tronc des arbres (une forme toute faite, jamais de triangle dessine a
## la main).
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
## complet, mais seul un quart depasse de l'angle mur/bassin -> le "quart de
## cercle vu de profil".
## Colonnes de BORD du lit (is_corner=true) : une sphere, au lieu d'un
## cylindre - elle est ronde dans TOUTES les directions (largeur ET
## profondeur), donc son quart visible se prolonge aussi vers l'exterieur du
## lit plutot que de s'arreter net - c'est le "quart de sphere" pour les coins.

@onready var voxel_world: Node3D = %VoxelWorld

# "voxel_world.WATER_COLOR" (via la variable typee generique Node3D) n'est
# pas accessible : une const de script n'est pas resolvable en dispatch
# dynamique (contrairement a une fonction comme get_waterfall_columns(), qui
# elle fonctionne). Meme pattern que WeatherSystem.gd (VoxelWorldScript.WIDTH)
# : passer par le script preload pour lire une constante.
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")

## Rayon des formes = un demi-bloc, pour un raccord net avec la grille (le
## quart visible occupe alors exactement l'espace d'un bloc standard).
const SHAPE_RADIUS := 0.5
const SHAPE_SEGMENTS := 16  # lisse (le tronc d'arbre utilise aussi un cylindre a segments, meme niveau de detail)

## Couleur de l'eau de la riviere en haut de cascade, decalee vers le bleu
## clair en bas via un degrade (voir _color_for_height). Une seule teinte
## plate suffit pour toute la forme - l'effet d'ecume (fonce en haut, clair
## en bas) est gere separement par de petits nuages de particules mobiles
## (voir WaterfallFoamClouds.gd), pas par un degrade de couleur sur ce
## maillage.
const WATERFALL_COLOR := Color(0.45, 0.80, 0.98)  # identique a VoxelWorld.WATER_COLOR

## Degrade vertical : le bas garde exactement WATERFALL_COLOR (couleur
## inchangee) ; le haut est une version assombrie de cette meme teinte
## (memes proportions R/G/B, juste multipliees), pas une couleur totalement
## differente.
const WATERFALL_TOP_DARKEN := 0.65  # facteur multiplicatif (1.0 = pas de changement)


## Degrade vertical simple : meme couleur qu'avant en bas (y=0), assombrie en
## haut (y=radius). Signature conservee (y, radius) pour ne pas toucher les
## nombreux appels dans _build_quarter_cylinder_mesh.
func _color_for_height(y: float, radius: float) -> Color:
	var t: float = clamp(y / radius, 0.0, 1.0)
	var dark_color: Color = Color(
		WATERFALL_COLOR.r * WATERFALL_TOP_DARKEN,
		WATERFALL_COLOR.g * WATERFALL_TOP_DARKEN,
		WATERFALL_COLOR.b * WATERFALL_TOP_DARKEN,
		WATERFALL_COLOR.a
	)
	return WATERFALL_COLOR.lerp(dark_color, t)


## Geometrie sensible (gel leve le 2026-07-08, modifiable normalement -
## voir [[feedback_waterfall_shape_frozen]]) : verifier les 6 criteres de
## [[project_forgotten_caves_waterfall_shape_spec]] un par un apres toute
## modification de ce fichier, ne pas se contenter d'une relecture de code.
## Construit un vrai quart de cylindre PLEIN (pas juste la peau courbe) via
## SurfaceTool - arc 0-90° ("haut" vers "droite"), plus les 2 capuchons plats
## (les 2 bouts, en eventail depuis l'axe) et les 2 faces planes radiales (a
## angle 0 et a angle 90°) qui referment le volume ; sans elles on ne verrait
## que la coquille exterieure, creuse, au lieu d'un volume plein. Couleur par
## sommet (degrade), voir _color_for_height.
func _build_quarter_cylinder_mesh(radius: float, length: float, segments: int, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_len := length * 0.5
	var za := -half_len
	var zb := half_len

	# Surface courbe (coquille exterieure)
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

	# Les 2 capuchons (eventail de triangles depuis l'axe central)
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

	# Les 2 faces planes radiales qui referment le volume - a angle 0 (le
	# "haut", face normale vers -X) et a angle 90° (le "droite", face normale
	# vers -Y).
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
	# La couleur de la riviere varie avec le soleil/l'heure - DayNightCycle.gd
	# change en continu light_color/light_energy/l'ambiant. L'eau de la
	# riviere utilise un materiau ECLAIRE (VoxelWorld._make_material,
	# roughness=1.0/metallic=0.0), donc sa couleur affichee suit ces
	# variations - un materiau UNSHADED ignorerait tout ca (couleur figee).
	# Meme eclairage + memes roughness/metallic que _make_material pour que
	# la cascade reagisse identiquement a la lumiere du soleil, a tout moment
	# de la journee.
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.metallic = 0.0
	# Meme a roughness=1.0, Godot garde un reflet speculaire de base
	# (metallic_specular, 0.5 par defaut). La forme courbe (normales
	# variables) capte ce reflet a un endroit precis, contrairement a la
	# surface plate de l'eau au meme angle de vue - d'ou une bande blanche
	# qui ne "prend pas la couleur de l'eau". Desactive.
	mat.metallic_specular = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var columns: Array = voxel_world.get_waterfall_columns()
	for col in columns:
		add_child(_build_shape(col, mat))


## Un vrai quart de cylindre par colonne de cascade (voir
## _build_quarter_cylinder_mesh), a l'echelle REELLE de la chute (rayon =
## hauteur totale top-pool_surface_y), pas juste un petit biseau d'1 bloc.
## Position/orientation : l'origine du maillage (voir
## _build_quarter_cylinder_mesh, le centre du cercle) est placee exactement
## a la surface du bassin, a l'aplomb de la colonne - son point "haut"
## (local +Y, rayon au-dessus de l'origine) est donc bien EXACTEMENT au
## niveau du sommet reel de la cascade (col.top), et son point "droite"
## (local +X, rayon a cote de l'origine) rejoint la surface du bassin en
## s'eloignant dans le sens du courant. Une seule rotation autour de l'axe
## vertical (Y) suffit pour aligner cet axe "droite" sur la direction du
## courant (dx,dz).
## Geometrie sensible (gel leve le 2026-07-08, modifiable normalement -
## voir [[feedback_waterfall_shape_frozen]]) : verifier les 6 criteres de
## [[project_forgotten_caves_waterfall_shape_spec]] un par un apres toute
## modification de ce fichier, ne pas se contenter d'une relecture de code.
func _build_shape(col: Dictionary, mat: StandardMaterial3D) -> MeshInstance3D:
	var dx: int = int(col["dx"])
	var dz: int = int(col["dz"])
	var pool_surface_y: float = float(col["pool_surface_y"])
	var radius: float = 1.0

	# Hauteur = pool_surface_y+1.0, meme convention que get_top_block_y()+1
	# utilisee partout ailleurs (ex. Dwarf.gd).
	# Sur l'axe du SENS DU COURANT (celui porte par dx/dz), le mur de pierre
	# reel se trouve a la LIMITE entre la colonne de cascade et la colonne
	# amont precedente, c'est a dire a la coordonnee brute du bloc (col.x ou
	# col.z), PAS a son centre (+0.5) - centrer sur cet axe placerait
	# l'origine un demi-bloc trop loin en aval, creant un espace visible
	# entre le mur et la cascade. L'axe de LARGEUR (perpendiculaire au
	# courant), lui, reste centre (+0.5).
	var x_offset := 0.0 if dx != 0 else 0.5
	var z_offset := 0.0 if dz != 0 else 0.5

	var mi := MeshInstance3D.new()
	mi.mesh = _build_quarter_cylinder_mesh(radius, 1.0, SHAPE_SEGMENTS, mat)
	mi.position = Vector3(float(col["x"]) + x_offset, pool_surface_y + 1.0, float(col["z"]) + z_offset)
	mi.rotation.y = atan2(-float(dz), float(dx))

	# Cas particulier d'une cascade sur plusieurs niveaux : la chute reelle
	# (col.top - pool_surface_y) peut depasser 1 niveau ; le rayon de base
	# (SHAPE_RADIUS/radius) reste a 1 dans tous les cas -
	# on etire seulement l'instance en hauteur (echelle Y locale, PAS la
	# geometrie elle-meme) pour que le sommet de la forme rejoigne le vrai
	# sommet de la chute. La largeur (axe X, "profondeur" de la courbe hors
	# du mur) et la longueur (axe Z, largeur du lit) ne changent pas. Pour
	# une chute normale d'1 niveau, drop=1 -> echelle 1.0 -> comportement
	# strictement identique au cas simple.
	var drop: float = float(col["top"]) - pool_surface_y
	if drop > 1.0:
		mi.scale.y = drop
	# Memorise le niveau (indice de bloc) du sommet de CETTE cascade, pour
	# update_view_level - ne touche ni geometrie ni position/rotation/
	# echelle (inchangees par rapport a ce qui precede).
	mi.set_meta("waterfall_top", float(col["top"]))
	return mi


## Cache/reaffiche chaque forme de cascade selon que son sommet (col.top,
## memorise dans _build_shape) est au-dessus ou non du niveau de vue
## courant - meme convention que VoxelWorld ("y > view_level" = cache).
## Simple bascule de "visible" sur le noeud deja construit, geometrie
## non touchee.
func update_view_level(level: int) -> void:
	for child in get_children():
		if child is MeshInstance3D and child.has_meta("waterfall_top"):
			child.visible = float(child.get_meta("waterfall_top")) <= float(level)
