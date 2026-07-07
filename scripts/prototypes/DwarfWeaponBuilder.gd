extends RefCounted
## Construction/pose des armes du modele 3D du nain (build_weapons et tout ce
## qu'elle appelle, directement ou indirectement).
##
## Fonctions STATIQUES prenant tout leur contexte en parametre, SANS
## reference typee vers DwarfModel3D (meme pattern que ActionValidator.gd/
## IconRenderer.gd/ClimateUI.gd) :
## - "model" est type Node3D (pas DwarfModel3DScript) et lu/ecrit uniquement
##   via get()/set() sur les noms de champs (weapon_type, weapon_material,
##   weapon_loadout, shield_type, ranged_type, weapon_pose, preview_animation,
##   weapon_color, weapon_handle_color, armor_color, torso_waist_width,
##   corpulence, leg_height, torso_depth, torso_height) - "duck typing"
##   choisi explicitement pour permettre a de futurs types de personnages
##   (autres races/visiteurs...) de reutiliser ce fichier sans heriter de
##   DwarfModel3D, du moment qu'ils exposent les memes champs @export.
## - hand_l/hand_r/arm_pivot_l/arm_pivot_r sont passes explicitement (ce sont
##   deja des noeuds construits par _build_arms, pas de simples donnees).
## - "parent" est le noeud auquel accrocher les armes/boucliers en position
##   "Repos" (ceinture/dos) via add_child - le script appelant passe "self".
##
## Voir Model3DUtils.gd pour flat_material()/edited_owner() (utilitaires
## partages).

const Model3DUtilsScript := preload("res://scripts/prototypes/Model3DUtils.gd")

## Palette de materiaux pour la tete/lame des armes - copie de
## DwarfModel3D.MATERIAL_COLORS (un const n'est pas accessible via get() sur
## "model", donc duplique ici comme les champs de Model3DUtils).
const MATERIAL_COLORS := {
	"Bois": Color(0.42, 0.28, 0.15),
	"Cuivre": Color(0.72, 0.45, 0.20),
	"Fer": Color(0.40, 0.40, 0.43),
	"Acier": Color(0.80, 0.82, 0.85),
}


## Choisit et place l'equipement selon "weapon_loadout" (voir @export_enum
## "Armes" dans DwarfModel3D.gd), puis les place selon
## effective_weapon_pose() : "Repos" -> attach_to_belt (armes a une main) ou
## attach_to_back (armes a 2 mains/boucliers/armes a distance) ; "Combat" ->
## attach_to_hand (main droite = arme principale, main gauche =
## bouclier/2e arme).
static func build_weapons(model: Node3D, parent: Node, hand_l: Node3D, hand_r: Node3D, arm_pivot_l: Node3D, arm_pivot_r: Node3D, head_y: float) -> void:
	model.set("weapon_color", weapon_material_color(model.get("weapon_material")))
	var pose: String = effective_weapon_pose(model)
	match model.get("weapon_loadout"):
		"Aucune":
			return
		"1 main":
			equip_one_handed(model, parent, hand_r, pose)
		"2 mains":
			equip_two_handed(model, parent, hand_r, arm_pivot_l, arm_pivot_r, pose, head_y)
		"1 main + bouclier":
			equip_one_handed_shield(model, parent, hand_l, hand_r, arm_pivot_l, pose, head_y)
		"Deux armes 1 main":
			equip_dual_wield(model, parent, hand_l, hand_r, pose)
		"Distance":
			equip_ranged(model, parent, hand_r, pose, head_y)


## Les 5 fonctions ci-dessous correspondent chacune a une branche du match de
## build_weapons() - meme pattern que le dispatch par type de tache dans
## Dwarf.gd/_complete_task.
static func equip_one_handed(model: Node3D, parent: Node, hand_r: Node3D, pose: String) -> void:
	var w := make_weapon_model(model, model.get("weapon_type"), false)
	if pose == "Combat":
		attach_to_hand(w, hand_r, false)
	else:
		attach_to_belt(model, parent, w, 1.0)


static func equip_two_handed(model: Node3D, parent: Node, hand_r: Node3D, arm_pivot_l: Node3D, arm_pivot_r: Node3D, pose: String, head_y: float) -> void:
	var w := make_weapon_model(model, model.get("weapon_type"), true)
	if pose == "Combat":
		attach_to_hand(w, hand_r, false)
		pose_two_handed_grip(arm_pivot_l, arm_pivot_r)
	else:
		attach_to_back(model, parent, w, head_y)


static func equip_one_handed_shield(model: Node3D, parent: Node, hand_l: Node3D, hand_r: Node3D, arm_pivot_l: Node3D, pose: String, head_y: float) -> void:
	var w := make_weapon_model(model, model.get("weapon_type"), false)
	var s := make_shield_model(model, model.get("shield_type"))
	if pose == "Combat":
		attach_to_hand(w, hand_r, false)
		attach_to_hand(s, hand_l, true)
		pose_shield_arm(arm_pivot_l)
	else:
		attach_to_belt(model, parent, w, 1.0)
		attach_to_back(model, parent, s, head_y)


static func equip_dual_wield(model: Node3D, parent: Node, hand_l: Node3D, hand_r: Node3D, pose: String) -> void:
	var w1 := make_weapon_model(model, model.get("weapon_type"), false)
	var w2 := make_weapon_model(model, model.get("weapon_type"), false)
	if pose == "Combat":
		attach_to_hand(w1, hand_r, false)
		attach_to_hand(w2, hand_l, false)
	else:
		attach_to_belt(model, parent, w1, 1.0)
		attach_to_belt(model, parent, w2, -1.0)


static func equip_ranged(model: Node3D, parent: Node, hand_r: Node3D, pose: String, head_y: float) -> void:
	var r := make_ranged_model(model, model.get("ranged_type"))
	if pose == "Combat":
		attach_to_hand(r, hand_r, false)
	else:
		attach_to_back(model, parent, r, head_y, true)


## Pose "effective" utilisee pour placer les armes : l'animation en cours a le
## dernier mot plutot que "weapon_pose" (choix manuel/randomise) seul, pour
## eviter des armes brandies en pleine main pendant des animations non
## martiales. "Combat" force les armes en main ; toute autre animation en
## mouvement (Marche/Travail/Manger/Dormir) force le rangement (ceinture/dos),
## meme si weapon_pose = "Combat" ; "Aucune" (apercu statique, utilise entre
## autres par la grille de demonstration figee) respecte le choix manuel de
## weapon_pose tel quel.
static func effective_weapon_pose(model: Node3D) -> String:
	match model.get("preview_animation"):
		"Combat":
			return "Combat"
		"Aucune":
			return model.get("weapon_pose")
		_:  # Marche, Travail, Manger, Dormir
			return "Repos"


## Convertit le materiau choisi (weapon_material) en couleur concrete (voir
## MATERIAL_COLORS) - appelee au debut de build_weapons pour recalculer
## weapon_color a chaque reconstruction (le champ n'est plus directement
## exportable/editable, voir sa declaration dans DwarfModel3D.gd).
static func weapon_material_color(material: String) -> Color:
	if MATERIAL_COLORS.has(material):
		return MATERIAL_COLORS[material]
	return MATERIAL_COLORS["Acier"]


## Construit le modele d'une arme (Epee/Masse/Hache), origine au niveau de la
## poignee (bas du manche), qui pointe vers +Y (le haut) au repos "neutre" du
## groupe - facilite le repositionnement/la rotation lors de l'attache
## (ceinture/dos/main, voir attach_to_*). "two_handed" agrandit l'ensemble
## (manche plus long, tete/lame plus grosse) pour la version a deux mains.
##
## Le "grip" (origine du groupe, point attache a la main en Combat - voir
## attach_to_hand) est au MILIEU de la poignee plutot que tout en bas : une
## fois attachee a la main (une simple sphere), une poignee dont l'origine
## est au bout semble "collee sur" la main plutot que tenue dedans. Centree,
## la moitie de la poignee se retrouve naturellement a l'interieur de la
## sphere de la main (cote pommeau) et l'autre moitie ressort vers la lame -
## plus lisible comme "tenue en main". Tous les decalages de tete/lame/garde
## ci-dessous sont donc exprimes par rapport a "handle_length * 0.5" (le haut
## de la poignee) plutot que "handle_length".
##
## Decoupee en une fonction par type d'arme (make_mace_head/make_axe_blade/
## make_sword_blade) + un helper commun (weapon_handle_length_base/
## make_weapon_handle).
static func make_weapon_model(model: Node3D, kind: String, two_handed: bool) -> Node3D:
	var group := Node3D.new()
	# Facteur d'echelle nettement marque (2.3x) pour une difference de taille
	# lisible entre une arme a une main et sa version a deux mains.
	var scale_factor: float = 2.3 if two_handed else 1.0
	var handle_length: float = weapon_handle_length_base(kind) * scale_factor

	# La masse et la hache sont tenues "au bout du manche" (comme un vrai
	# outil/arme d'impact, pour la portee/le levier du coup), pas au milieu
	# pres de la tete. L'origine du groupe (0,0,0) est le point attache a la
	# main (voir attach_to_hand) : pour Masse/Hache, elle correspond donc au
	# BOUT BAS du manche (handle_top = handle_length, la tete est tout en
	# haut). L'epee garde le grip au MILIEU du manche (handle_top =
	# handle_length * 0.5, plus proche d'une prise d'epee classique, entre
	# garde et pommeau).
	var grip_at_bottom: bool = (kind == "Masse" or kind == "Hache")
	var handle_top: float = handle_length if grip_at_bottom else handle_length * 0.5
	var handle_center_y: float = handle_length * 0.5 if grip_at_bottom else 0.0

	make_weapon_handle(model, group, handle_length, handle_center_y, scale_factor)

	match kind:
		"Masse":
			make_mace_head(model, group, handle_top, scale_factor)
		"Hache":
			make_axe_blade(model, group, handle_top, scale_factor)
		_:  # "Epee"
			make_sword_blade(model, group, handle_top, scale_factor)

	return group


## Longueur de manche par type d'arme (une masse et une epee n'ont pas la
## meme proportion manche/tete) - extrait de make_weapon_model().
static func weapon_handle_length_base(kind: String) -> float:
	match kind:
		"Masse":
			return 0.42
		"Hache":
			return 0.34
		_:  # "Epee"
			return 0.22


## Construit le manche (commun aux 3 types d'armes) - extrait de
## make_weapon_model(). N'assigne pas "owner" ici (ni dans les autres make_*/
## build_* de ce fichier) : "group" n'est pas encore accroche a son parent
## final a ce stade, et Godot refuse l'assignation d'un owner qui n'est pas
## un ancetre reel dans l'arbre ("Invalid owner..."). L'owner de TOUT le
## sous-arbre est assigne d'un coup par Model3DUtils.adopt_recursive(), une
## fois le groupe reellement attache (voir attach_to_belt/attach_to_back/
## attach_to_hand). Aucun effet visuel - "owner" ne sert qu'a la
## persistance/visibilite dans le panneau Scene de l'editeur.
static func make_weapon_handle(model: Node3D, group: Node3D, handle_length: float, handle_center_y: float, scale_factor: float) -> void:
	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.02 * scale_factor
	handle_mesh.bottom_radius = 0.02 * scale_factor
	handle_mesh.height = handle_length
	handle.mesh = handle_mesh
	handle.position = Vector3(0, handle_center_y, 0)  # centre du manche - au-dessus du grip pour Masse/Hache, sur le grip pour Epee
	handle.name = "Handle"
	handle.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("weapon_handle_color")))
	group.add_child(handle)


## Tete de la masse : une sphere centrale plus des "flanges" (fines boites
## autour de la tete) pour lire clairement comme une masse d'armes plutot
## qu'une simple boule - extrait de make_weapon_model().
static func make_mace_head(model: Node3D, group: Node3D, handle_top: float, scale_factor: float) -> void:
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.11 * scale_factor
	head_mesh.height = head_mesh.radius * 2.0
	head.mesh = head_mesh
	head.position = Vector3(0, handle_top, 0)
	head.name = "Head"
	head.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("weapon_color")))
	group.add_child(head)
	for i in range(4):
		var flange := MeshInstance3D.new()
		var flange_mesh := BoxMesh.new()
		flange_mesh.size = Vector3(0.022 * scale_factor, 0.15 * scale_factor, 0.08 * scale_factor)
		flange.mesh = flange_mesh
		flange.position = Vector3(0, handle_top, 0)
		flange.rotation.y = deg_to_rad(i * 90.0)
		flange.name = "Flange_%d" % i
		flange.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("weapon_color")))
		group.add_child(flange)


## Lame de la hache : une boite decalee lateralement par rapport au manche -
## extrait de make_weapon_model().
static func make_axe_blade(model: Node3D, group: Node3D, handle_top: float, scale_factor: float) -> void:
	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.20 * scale_factor, 0.25 * scale_factor, 0.03 * scale_factor)
	blade.mesh = blade_mesh
	blade.position = Vector3(0.09 * scale_factor, handle_top - 0.03, 0)
	blade.name = "Blade"
	blade.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("weapon_color")))
	group.add_child(blade)


## Lame + garde de l'epee - extrait de make_weapon_model().
static func make_sword_blade(model: Node3D, group: Node3D, handle_top: float, scale_factor: float) -> void:
	var blade_length: float = 0.64 * scale_factor
	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.05 * scale_factor, blade_length, 0.018 * scale_factor)
	blade.mesh = blade_mesh
	blade.position = Vector3(0, handle_top + blade_length * 0.5, 0)
	blade.name = "Blade"
	blade.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("weapon_color")))
	group.add_child(blade)

	var guard := MeshInstance3D.new()
	var guard_mesh := BoxMesh.new()
	guard_mesh.size = Vector3(0.13 * scale_factor, 0.025 * scale_factor, 0.03 * scale_factor)
	guard.mesh = guard_mesh
	guard.position = Vector3(0, handle_top, 0)
	guard.name = "Guard"
	guard.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("weapon_color")))
	group.add_child(guard)


## Construit un bouclier (Petit rond/Grand carre), origine au centre du
## bouclier, face avant tournee vers +Z par defaut (correspond a
## l'orientation "tenu devant soi" en position Combat).
static func make_shield_model(model: Node3D, kind: String) -> Node3D:
	var group := Node3D.new()
	match kind:
		"Grand carre":
			var panel := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.42, 0.57, 0.04)
			panel.mesh = mesh
			panel.name = "ShieldPanel"
			panel.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("armor_color"), true))
			group.add_child(panel)
		_:  # "Petit rond"
			var panel := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.26
			mesh.bottom_radius = 0.26
			mesh.height = 0.045
			panel.mesh = mesh
			panel.rotation.x = deg_to_rad(90.0)  # cylindre couche a plat -> disque face a +Z
			panel.name = "ShieldPanel"
			panel.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("armor_color"), true))
			group.add_child(panel)

			var boss := MeshInstance3D.new()
			var boss_mesh := SphereMesh.new()
			boss_mesh.radius = 0.065
			boss_mesh.height = boss_mesh.radius * 2.0
			boss.mesh = boss_mesh
			boss.position = Vector3(0, 0, 0.033)
			boss.name = "ShieldBoss"
			boss.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("weapon_color")))
			group.add_child(boss)

	return group


## Construit une arme a distance (Arc/Arbalete), origine au centre de l'arme.
## "Arc" reutilise le meme principe de courbe que la bouche/les sourcils
## (_build_curve_segments dans DwarfModel3D.gd), mais construit ici
## directement dans le groupe local (pas sur le modele) pour que la courbe
## reste attachee/bouge avec l'arme lors du positionnement.
static func make_ranged_model(model: Node3D, kind: String) -> Node3D:
	var group := Node3D.new()
	match kind:
		"Arbalete":
			build_crossbow_model(model, group)
		_:  # "Arc"
			build_bow_model(model, group)
	return group


## Modele de l'arbalete (crosse + arc rigide) - extrait de
## make_ranged_model().
static func build_crossbow_model(model: Node3D, group: Node3D) -> void:
	var stock := MeshInstance3D.new()
	var stock_mesh := BoxMesh.new()
	stock_mesh.size = Vector3(0.025, 0.03, 0.32)
	stock.mesh = stock_mesh
	stock.position = Vector3(0, 0, 0.16)
	stock.name = "Stock"
	stock.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("weapon_handle_color")))
	group.add_child(stock)

	var limb := MeshInstance3D.new()
	var limb_mesh := BoxMesh.new()
	limb_mesh.size = Vector3(0.34, 0.02, 0.02)
	limb.mesh = limb_mesh
	limb.position = Vector3(0, 0, 0.30)
	limb.name = "Limb"
	limb.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("weapon_color")))
	group.add_child(limb)


## Modele de l'arc : une courbe approximee par une chaine de segments
## (boites) dont l'orientation suit la tangente locale, construite a partir
## d'une parabole simple (arc = 1 - (2t-1)^2, t de 0 a 1) donnant la courbure
## caracteristique d'un arc bande - extrait de make_ranged_model().
static func build_bow_model(model: Node3D, group: Node3D) -> void:
	var pts: Array = []
	var points := 7
	var bow_height: float = 0.48
	var bow_curve: float = 0.09
	for i in range(points):
		var t: float = float(i) / float(points - 1)
		var y: float = lerp(-bow_height * 0.5, bow_height * 0.5, t)
		var arc: float = 1.0 - pow(2.0 * t - 1.0, 2.0)
		var x: float = arc * bow_curve
		pts.append(Vector3(x, y, 0))
	for i in range(pts.size() - 1):
		var p_a: Vector3 = pts[i]
		var p_b: Vector3 = pts[i + 1]
		var mid: Vector3 = (p_a + p_b) * 0.5
		var seg_length: float = p_a.distance_to(p_b) * 1.2
		var angle: float = atan2(p_b.y - p_a.y, p_b.x - p_a.x)
		var seg := MeshInstance3D.new()
		var seg_mesh := BoxMesh.new()
		seg_mesh.size = Vector3(0.022, seg_length, 0.022)
		seg.mesh = seg_mesh
		seg.position = mid
		seg.rotation.z = angle - deg_to_rad(90.0)
		seg.name = "BowSeg_%d" % i
		seg.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("weapon_handle_color")))
		group.add_child(seg)


## Attache une arme/bouclier a la ceinture (position "Repos" pour une arme a
## une main) - couche a l'horizontale contre la hanche, cote determine par
## "side" (-1.0 = gauche, 1.0 = droite).
static func attach_to_belt(model: Node3D, parent: Node, item: Node3D, side: float) -> void:
	var waist_w: float = model.get("torso_waist_width") * float(model.get("corpulence"))
	item.position = Vector3(side * (waist_w * 0.5 + 0.05), float(model.get("leg_height")) + 0.05, 0.02)
	item.rotation.z = deg_to_rad(side * 100.0)  # couche contre la hanche, poignee vers le haut/l'avant
	item.name = "Weapon_Belt_%s" % ("L" if side < 0.0 else "R")
	parent.add_child(item)
	Model3DUtilsScript.adopt_recursive(item, Model3DUtilsScript.edited_owner(model))


## Attache une arme a 2 mains/bouclier/arme a distance dans le dos (position
## "Repos") - a la verticale, centree derriere le torse, legerement inclinee
## pour coller au dos. La tete/lame pointe vers le BAS, donc l'attache est
## remontee pres de l'epaule pour que la tete/lame ne traverse pas le sol en
## pendant vers le bas du dos.
## Valeurs (height_factor/tilt_deg) estimees a l'oeil, sans reference
## geometrique precise (positionnement 3D sensible - voir memoire projet sur
## la geometrie a l'oeil) : a reajuster si le rendu en jeu ne convient pas.
static func attach_to_back(model: Node3D, parent: Node, item: Node3D, _head_y: float, is_ranged: bool = false) -> void:
	var depth: float = float(model.get("torso_depth")) * float(model.get("corpulence"))
	var height_factor: float = 0.92
	var tilt_deg: float = -168.0
	if is_ranged:
		# Parametre distinct pour permettre un reglage independant arc/arbalete
		# vs armes de melee/bouclier a l'avenir - pour l'instant, meme formule
		# que le melee.
		height_factor = 0.92
		tilt_deg = -168.0
	item.position = Vector3(0, float(model.get("leg_height")) + float(model.get("torso_height")) * height_factor, -depth * 0.6 - 0.03)
	item.rotation.x = deg_to_rad(tilt_deg)
	item.name = "Weapon_Back"
	parent.add_child(item)
	Model3DUtilsScript.adopt_recursive(item, Model3DUtilsScript.edited_owner(model))


## Attache une arme/bouclier dans une main (position "Combat") - enfant
## direct du noeud Main (Hand_L/Hand_R, deja positionne au bout du pivot de
## bras, voir _build_arms dans DwarfModel3D.gd), avec une legere orientation
## pour paraitre "empoignee" plutot que de pendre droit vers le bas. Un
## bouclier garde sa rotation neutre (deja face a +Z par construction, voir
## make_shield_model). Ne prend pas "model" en parametre : ne lit/n'ecrit
## aucun champ d'apparence, seulement la main deja fournie.
static func attach_to_hand(item: Node3D, hand: Node3D, is_shield: bool) -> void:
	if not hand:
		return
	if not is_shield:
		# Le personnage fait face a +Z (voir eye_z/nose/bouche dans
		# _build_face de DwarfModel3D.gd, tous positifs) : rotation.x = +70 deg
		# envoie la lame vers +Z (l'avant, cote visage) avec une legere
		# inclinaison vers le haut.
		item.rotation.x = deg_to_rad(70.0)
	else:
		# Leger decalage vers l'avant (+Z, cote visage) pour que le bouclier
		# se lise clairement comme "tenu devant soi" en Combat, plutot que
		# colle exactement au centre de la main (cote du corps).
		item.position = Vector3(0, 0, 0.08)
	item.name = "Weapon_Hand_%s" % hand.name
	hand.add_child(item)
	Model3DUtilsScript.adopt_recursive(item, Model3DUtilsScript.edited_owner(hand))


## Pose statique "tenue a deux mains" pour les armes 2 mains en Combat : la
## main droite tient deja le grip (voir attach_to_hand) ; on fait aussi
## pivoter le bras gauche pour l'amener pres du manche (desormais bien plus
## long, voir make_weapon_model), comme si les deux mains le portaient
## ensemble. Approximation a l'oeil (pas de cinematique inverse). Sans effet
## si preview_animation != "Aucune" : _process() recalcule alors les pivots
## de bras a chaque frame et prend le dessus (voir l'etat "Combat" de
## _process dans DwarfModel3D.gd).
static func pose_two_handed_grip(arm_pivot_l: Node3D, arm_pivot_r: Node3D) -> void:
	if not (arm_pivot_l and arm_pivot_r):
		return
	arm_pivot_r.rotation.x = deg_to_rad(-50.0)
	arm_pivot_r.rotation.z = deg_to_rad(-8.0)
	arm_pivot_l.rotation.x = deg_to_rad(-45.0)
	arm_pivot_l.rotation.z = deg_to_rad(55.0)  # ramene la main gauche vers le manche, cote droit du corps


## Pose statique "bras du bouclier" en Combat : sans elever le bras gauche,
## le bouclier (attache a Hand_L, voir attach_to_hand) se retrouve
## fondu/enfonce dans le torse au lieu de ressortir devant - on leve donc le
## bras gauche vers l'avant (meme principe que pose_two_handed_grip). Sans
## effet si preview_animation != "Aucune" (voir _process dans
## DwarfModel3D.gd, qui reprend la main sur les pivots de bras).
static func pose_shield_arm(arm_pivot_l: Node3D) -> void:
	if not arm_pivot_l:
		return
	arm_pivot_l.rotation.x = deg_to_rad(-72.0)
	arm_pivot_l.rotation.z = deg_to_rad(-12.0)  # legerement ecarte du corps
