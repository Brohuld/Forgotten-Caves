extends RefCounted
## Construction du portrait 3D d'un nain (mini SubViewport + camera cadree
## sur la tete). Fonction statique et autonome (aucun etat partage avec
## CharacterSheetUI.gd) : recoit le noeud "parent" auquel accrocher le
## SubViewport temporaire (add_child), puisque ce script n'est pas lui-meme
## un Node et ne peut pas le faire directement - meme pattern que
## ActionValidator.gd/IconRenderer.gd (aucune reference typee vers le script
## appelant, tout ce qui est necessaire est passe en parametre).

const DwarfModel3DScript := preload("res://scripts/prototypes/DwarfModel3D.gd")

const PORTRAIT_RENDER_SIZE := 128
const PORTRAIT_CAMERA_FOV := 30.0
## Liste explicite des champs d'APPARENCE a copier du vrai modele du nain
## vers le modele jetable du portrait - une copie totale de toutes les
## proprietes du noeud (position/rotation/scale...) n'a rien a voir avec
## l'apparence et provoquerait des erreurs.
const PORTRAIT_APPEARANCE_FIELDS := [
	"skin_color", "hair_color", "beard_color", "clothing_color", "pants_color",
	"armor_color", "boot_color", "coat_color", "wear_gloves", "wear_coat",
	"leg_height", "torso_height", "torso_shoulder_width", "torso_waist_width",
	"torso_depth", "head_radius", "head_height_factor", "arm_length",
	"hair_size", "hair_lift", "hair_back_offset",
	"hair_style", "beard_style", "beard_width", "corpulence", "outfit_style",
]


## Construit et renvoie la texture d'un portrait 3D pour "dwarf" - le
## SubViewport temporaire est ajoute comme enfant de "parent" (le CanvasLayer
## appelant, voir CharacterSheetUI.gd/_create_portrait_icon), jamais liberé
## explicitement ici (reste en vie tant que la texture est utilisee, meme
## duree de vie que l'icone qui l'affiche).
static func make_portrait_texture(dwarf: Node3D, parent: Node) -> Texture2D:
	var src_model: Node3D = dwarf.dwarf_model

	var viewport := SubViewport.new()
	viewport.size = Vector2i(PORTRAIT_RENDER_SIZE, PORTRAIT_RENDER_SIZE)
	viewport.transparent_bg = true
	# Monde 3D independant du jeu principal : sans ca, la camera du portrait
	# risquerait de partager (et donc afficher) le monde 3D de la scene
	# principale au lieu du seul modele copie ci-dessous.
	viewport.own_world_3d = true
	parent.add_child(viewport)

	# Apparence fixee AVANT d'ajouter le noeud a l'arbre (meme correction que
	# Dwarf.gd/_build_appearance, voir memoire perf) - add_child declenche
	# _ready()->_rebuild() qui construit alors directement le bon portrait,
	# sans passer par un premier essai jetable (valeurs par defaut) qu'il
	# faudrait ensuite nettoyer via un 2e appel explicite a _rebuild(). Ce
	# nettoyage inutile (jamais visible, ~0.01-0.02s la plupart du temps)
	# causait une pause de ~5s la toute premiere fois qu'il se produisait
	# dans une partie (peu importe si c'etait sur un nain ou sur un portrait).
	var portrait_model := Node3D.new()
	portrait_model.set_script(DwarfModel3DScript)
	for field in PORTRAIT_APPEARANCE_FIELDS:
		portrait_model.set(field, src_model.get(field))
	portrait_model.weapon_loadout = "Aucune"  # jamais d'arme dans le portrait, coherent avec le jeu principal
	viewport.add_child(portrait_model)

	# Cadrage "buste" : vise un peu sous le sommet de la tete (voir la formule
	# de head_y dans DwarfModel3D._build_model) pour laisser de la marge au-
	# dessus (cheveux) et voir un peu des epaules en bas de l'image. Distance
	# proportionnelle a head_radius pour rester correct si la tete change de
	# taille plus tard.
	var target_y: float = portrait_model.leg_height + portrait_model.torso_height + portrait_model.head_radius * 0.1
	var camera := Camera3D.new()
	camera.fov = PORTRAIT_CAMERA_FOV
	camera.position = Vector3(0, target_y, portrait_model.head_radius * 3.8)
	camera.current = true
	# look_at() a besoin de la transform globale du noeud, donc le noeud doit
	# deja etre DANS l'arbre de scene (add_child avant, pas apres) - meme
	# famille de bug que le "Parent node is busy" de l'anneau de selection,
	# mais ici c'est l'ordre des deux lignes qui compte.
	viewport.add_child(camera)
	camera.look_at(Vector3(0, target_y, 0), Vector3.UP)

	# Le contenu du portrait ne change plus jamais une fois construit (modele
	# jetable, jamais anime, jamais reconstruit) - sans ce reglage, le
	# SubViewport reste par defaut en UPDATE_ALWAYS et continue de re-rendre
	# une image identique CHAQUE frame, pour chaque nain, indefiniment (cout
	# GPU cumulatif inutile qui grandit avec le nombre de nains). UPDATE_ONCE
	# rend une derniere fois (le modele/camera venant d'etre ajoutes ci-dessus,
	# deja complets a ce stade) puis s'arrete.
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	return viewport.get_texture()
