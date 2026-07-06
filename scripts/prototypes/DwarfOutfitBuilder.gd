extends RefCounted
## 2026-07-06 (revue de code, paquet E, M58 - etape 2/3) : extrait de
## DwarfModel3D.gd (9 fonctions liees a la tenue/l'armure - _build_outfit et
## tout ce qu'elle appelle, plus le manteau et les gants qui sont des
## accessoires independants de outfit_style). Meme demarche que l'etape 1
## (armes, voir DwarfWeaponBuilder.gd) : fichier source toujours trop
## volumineux, decoupe en 3 etapes testees separement. Aucun changement de
## comportement.
##
## Fonctions STATIQUES, meme pattern que DwarfWeaponBuilder.gd :
## - "model" est type Node3D (pas DwarfModel3DScript), lu via get() sur les
##   noms de champs (outfit_style, wear_coat, wear_gloves, torso_waist_width,
##   corpulence, torso_depth, torso_height, leg_height, torso_shoulder_width,
##   coat_color, armor_color, boot_color, head_radius) - duck typing, meme
##   raison qu'en etape 1 (futures races/visiteurs).
## - "parent" est le noeud auquel accrocher les pieces de tenue (le script
##   appelant passera "self") - contrairement aux armes, aucune piece ici
##   n'est construite dans un groupe orphelin avant attache : chaque mesh est
##   ajoute directement a "parent" (ou a une main pour les gants), donc pas
##   besoin de Model3DUtils.adopt_recursive() ici.
## - hand_l/hand_r passes explicitement pour build_gloves (comme
##   hand_l/hand_r dans DwarfWeaponBuilder.gd).
##
## Voir Model3DUtils.gd pour flat_material()/edited_owner()/
## make_trapezoid_mesh() (utilitaires partages).

const Model3DUtilsScript := preload("res://scripts/prototypes/Model3DUtils.gd")


## Sprint 28unvicies : aiguille vers la construction de la tenue/armure selon
## "outfit_style" (voir @export_enum dans DwarfModel3D.gd) - "Tunique simple"
## (defaut) ne construit rien de plus que le torse de base.
static func build_outfit(model: Node3D, parent: Node, head_y: float) -> void:
	match model.get("outfit_style"):
		"Tunique + cape":
			build_cape(model, parent)
		"Armure legere":
			build_chestplate(model, parent)
		"Armure lourde":
			build_chestplate(model, parent)
			build_shoulder_pads(model, parent)
			build_helmet(model, parent, head_y)
		_:  # "Tunique simple" (defaut)
			pass


## Sprint 28sixseptuagesies : manteau - accessoire independant de
## outfit_style (voir wear_coat, groupe "Accessoires"), peut se porter
## par-dessus n'importe quelle tenue. Reutilise make_trapezoid_mesh (comme le
## torse/la cape/le plastron) mais legerement plus large que le torse (pour
## bien le recouvrir) et surtout plus LONG, descendant sous la taille jusqu'
## aux cuisses.
static func build_coat(model: Node3D, parent: Node) -> void:
	if not model.get("wear_coat"):
		return
	var waist_w: float = model.get("torso_waist_width") * float(model.get("corpulence"))
	var depth: float = float(model.get("torso_depth")) * float(model.get("corpulence"))
	var coat_height: float = float(model.get("torso_height")) + 0.22
	var torso_top_y: float = float(model.get("leg_height")) + float(model.get("torso_height"))
	var top_size := Vector2(float(model.get("torso_shoulder_width")) * 1.08, depth * 1.2)
	var bottom_size := Vector2(waist_w * 1.35, depth * 1.2)
	var coat_center_y: float = torso_top_y - coat_height * 0.5

	var coat := MeshInstance3D.new()
	coat.mesh = Model3DUtilsScript.make_trapezoid_mesh(top_size, bottom_size, coat_height)
	coat.position = Vector3(0, coat_center_y, 0)
	coat.name = "Coat"
	coat.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("coat_color"), true))
	parent.add_child(coat)
	coat.owner = Model3DUtilsScript.edited_owner(model)

	# Sprint 28octoseptuagesies : "juste une grosse boite" signale par
	# l'utilisateur - une petite sphere a chaque coin superieur (epaule) pour
	# arrondir l'angle vif entre le haut plat du manteau et le bras.
	for side in [-1.0, 1.0]:
		build_coat_shoulder_cap(model, parent, side, depth, top_size, torso_top_y)

	build_coat_buttons(model, parent, torso_top_y, coat_center_y, coat_height, top_size)


## 2026-07-06 (revue de code, paquet E, I63) : extrait de _build_coat() - une
## seule epaulette, aucun changement de comportement.
static func build_coat_shoulder_cap(model: Node3D, parent: Node, side: float, depth: float, top_size: Vector2, torso_top_y: float) -> void:
	var side_name: String = "L" if side < 0.0 else "R"
	var cap := MeshInstance3D.new()
	var cap_mesh := SphereMesh.new()
	# Sprint 28neufseptuagesies : etait depth * 0.55, positionnee tout au
	# bord (x0.5) - depassait trop, signale par l'utilisateur. Reduite et
	# rentree legerement vers l'interieur.
	cap_mesh.radius = depth * 0.32
	cap_mesh.height = cap_mesh.radius * 2.0
	cap.mesh = cap_mesh
	cap.position = Vector3(side * top_size.x * 0.42, torso_top_y - 0.02, 0)
	cap.name = "CoatShoulder_%s" % side_name
	cap.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("coat_color")))
	parent.add_child(cap)
	cap.owner = Model3DUtilsScript.edited_owner(model)


## 2026-07-06 (revue de code, paquet E, I63) : extrait de _build_coat() -
## rangee de boutons devant, aucun changement de comportement.
static func build_coat_buttons(model: Node3D, parent: Node, torso_top_y: float, coat_center_y: float, coat_height: float, top_size: Vector2) -> void:
	var button_count := 4
	var button_top_y: float = torso_top_y - 0.06
	var button_bottom_y: float = coat_center_y - coat_height * 0.42
	var button_z: float = top_size.y * 0.5 + 0.01
	for i in range(button_count):
		var t: float = float(i) / float(button_count - 1)
		var button := MeshInstance3D.new()
		var button_mesh := SphereMesh.new()
		button_mesh.radius = 0.018
		button_mesh.height = button_mesh.radius * 2.0
		button.mesh = button_mesh
		button.position = Vector3(0, lerp(button_top_y, button_bottom_y, t), button_z)
		button.name = "CoatButton_%d" % i
		button.set_surface_override_material(0, Model3DUtilsScript.flat_material(Color(0.14, 0.12, 0.10)))
		parent.add_child(button)
		button.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28sixseptuagesies : gants - accessoire independant de outfit_style
## (voir wear_gloves, groupe "Accessoires"). Une petite sphere legerement
## plus grosse que la main (voir _build_arms dans DwarfModel3D.gd), attachee
## directement en enfant du noeud Main (hand_l/hand_r) pour suivre
## automatiquement bras/pivot - meme reference que attach_to_hand pour les
## armes (DwarfWeaponBuilder.gd). Couleur cuir (boot_color, meme logique que
## les bottes) plutot qu'une nouvelle couleur dediee.
static func build_gloves(model: Node3D, hand_l: Node3D, hand_r: Node3D) -> void:
	if not model.get("wear_gloves"):
		return
	for hand in [hand_l, hand_r]:
		if not hand:
			continue
		var glove := MeshInstance3D.new()
		var glove_mesh := SphereMesh.new()
		glove_mesh.radius = 0.075
		glove_mesh.height = glove_mesh.radius * 2.0
		glove.mesh = glove_mesh
		glove.name = "Glove_%s" % hand.name
		glove.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("boot_color")))
		hand.add_child(glove)
		glove.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28unvicies : cape plate accrochee aux epaules, tombant le long du
## dos (armor_color, comme la ceinture - voir _build_belt dans DwarfModel3D.gd
## - pour rester coherent avec les 4 couleurs personnalisables existantes).
static func build_cape(model: Node3D, parent: Node) -> void:
	var shoulder_y: float = float(model.get("leg_height")) + float(model.get("torso_height")) - 0.04
	var depth: float = float(model.get("torso_depth")) * float(model.get("corpulence"))
	var cape_height: float = float(model.get("torso_height")) * 0.9
	var cape := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(float(model.get("torso_shoulder_width")) * 0.85, cape_height, 0.03)
	cape.mesh = mesh
	cape.position = Vector3(0, shoulder_y - cape_height * 0.5, -depth * 0.5 - 0.02)
	cape.name = "Cape"
	cape.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("armor_color"), true))
	parent.add_child(cape)
	cape.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28unvicies : plastron - reutilise make_trapezoid_mesh (meme forme
## que le torse, voir _build_torso dans DwarfModel3D.gd) en plus petit/plus
## plat, plaque devant le torse existant (armor_color) plutot que de
## remplacer le torse.
static func build_chestplate(model: Node3D, parent: Node) -> void:
	var depth: float = float(model.get("torso_depth")) * float(model.get("corpulence"))
	var plate := MeshInstance3D.new()
	plate.mesh = Model3DUtilsScript.make_trapezoid_mesh(
		Vector2(float(model.get("torso_shoulder_width")) * 1.04, depth * 0.5),
		Vector2(model.get("torso_waist_width") * float(model.get("corpulence")) * 1.02, depth * 0.5),
		float(model.get("torso_height")) * 0.65
	)
	plate.position = Vector3(0, float(model.get("leg_height")) + float(model.get("torso_height")) * 0.72, depth * 0.28)
	plate.name = "Chestplate"
	plate.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("armor_color"), true))
	parent.add_child(plate)
	plate.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28unvicies : petites epaulieres (une boite par epaule, armor_color),
## a la meme position X que le pivot du bras (voir _build_arms dans
## DwarfModel3D.gd) pour rester bien alignees quelle que soit la largeur
## d'epaules.
static func build_shoulder_pads(model: Node3D, parent: Node) -> void:
	var shoulder_y: float = float(model.get("leg_height")) + float(model.get("torso_height")) - 0.04
	var arm_x_offset: float = float(model.get("torso_shoulder_width")) * 0.5 + 0.04
	for side in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"
		var pad := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.16, 0.08, 0.18)
		pad.mesh = mesh
		pad.position = Vector3(side * arm_x_offset, shoulder_y + 0.04, 0)
		pad.name = "ShoulderPad_%s" % side_name
		pad.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("armor_color")))
		parent.add_child(pad)
		pad.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28unvicies : casque - sphere aplatie (armor_color) couvrant la tete,
## posee par-dessus les cheveux/la coiffe choisie (peut legerement chevaucher
## la coiffe, acceptable pour un prototype - a affiner si ca choque une fois
## vu dans Godot, par exemple en masquant les cheveux quand un casque est
## porte).
static func build_helmet(model: Node3D, parent: Node, head_y: float) -> void:
	# Dome principal : couvre le dessus/l'avant du crane. Reprend les memes
	# proportions "surete" que les cheveux courts (_build_hair_short : rayon
	# ~1.08-1.15x head_radius, recul ~0.20-0.22x) plutot que le centre remonte
	# + sphere aplatie d'avant, qui laissait le bas-arriere du crane decouvert
	# (une sphere aplatie et decentree vers le haut retrecit tres vite en Y
	# des qu'on s'eloigne de son pole, donc son bord a l'arriere ne
	# descendait pas assez bas pour couvrir jusqu'a la nuque).
	var head_radius: float = model.get("head_radius")
	var dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	var dome_radius: float = head_radius * 1.15
	dome_mesh.radius = dome_radius
	dome_mesh.height = dome_radius * 2.0
	dome.mesh = dome_mesh
	dome.position = Vector3(0, head_y + head_radius * 0.15, -head_radius * 0.20)
	dome.name = "Helmet"
	dome.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("armor_color")))
	parent.add_child(dome)
	dome.owner = Model3DUtilsScript.edited_owner(model)

	# Garde-nuque : deuxieme sphere dediee, decalee vers l'arriere ET vers le
	# bas, pour prolonger explicitement la couverture jusqu'a l'arriere du
	# crane/la nuque - signale manquant par l'utilisateur avec la 1ere version
	# (dome seul).
	var guard := MeshInstance3D.new()
	var guard_mesh := SphereMesh.new()
	var guard_radius: float = head_radius * 0.85
	guard_mesh.radius = guard_radius
	guard_mesh.height = guard_radius * 2.0
	guard.mesh = guard_mesh
	guard.position = Vector3(0, head_y - head_radius * 0.10, -head_radius * 0.68)
	guard.name = "HelmetGuard"
	guard.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("armor_color")))
	parent.add_child(guard)
	guard.owner = Model3DUtilsScript.edited_owner(model)
