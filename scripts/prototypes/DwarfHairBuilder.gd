extends RefCounted
## 2026-07-06 (revue de code, paquet E, M58 - etape 3/3, DERNIERE etape) :
## extrait de DwarfModel3D.gd (15 fonctions liees aux cheveux/a la barbe -
## _build_hair et _build_beard, et tout ce qu'elles appellent). Meme demarche
## que les etapes 1 (armes, DwarfWeaponBuilder.gd) et 2 (tenue/armure,
## DwarfOutfitBuilder.gd) : fichier source toujours trop volumineux, decoupe
## en 3 etapes testees separement. Aucun changement de comportement.
##
## Fonctions STATIQUES, meme pattern que les 2 fichiers precedents :
## - "model" est type Node3D (pas DwarfModel3DScript), lu via get() sur les
##   noms de champs (outfit_style, hair_style, head_radius, hair_size,
##   hair_lift, hair_back_offset, hair_color, leg_height, torso_height,
##   head_height_factor, beard_style, beard_width, beard_color) - duck
##   typing, meme raison qu'aux etapes precedentes (futures races/visiteurs).
## - "parent" est le noeud auquel accrocher les meches/la barbe (le script
##   appelant passera "self") - comme la tenue (etape 2), aucune piece ici
##   n'est construite dans un groupe orphelin avant attache, donc pas besoin
##   de Model3DUtils.adopt_recursive().
##
## Voir Model3DUtils.gd pour flat_material()/edited_owner()/color_variant()/
## head_surface_radius() (utilitaires partages).

const Model3DUtilsScript := preload("res://scripts/prototypes/Model3DUtils.gd")


## Sprint 28quindecies/28octodecies : aiguille vers l'une des formes de
## cheveux selon "hair_style" (voir @export_enum dans DwarfModel3D.gd).
## "Chauve" ne construit rien.
static func build_hair(model: Node3D, parent: Node, head_y: float) -> void:
	# Sprint 28sexvicies : "bug de couleur de cheveux" signale par l'utilisateur
	# (frange grise visible alors que les cheveux sont noirs/blonds) - en fait
	# pas un bug de couleur : le casque (Armure lourde, gris par defaut, voir
	# DwarfOutfitBuilder.build_helmet) et des cheveux plus grands que lui
	# (ex. "Touffu", qui depasse largement le rayon du casque) se chevauchent,
	# laissant le casque visible en avant du crane pendant que les cheveux
	# colores debordent autour/derriere - lu a tort comme "une frange grise".
	# Corrige logiquement : un casque complet cache les cheveux dessous, donc
	# on ne les construit pas.
	if model.get("outfit_style") == "Armure lourde":
		return
	match model.get("hair_style"):
		"Chauve":
			return
		"Attache":
			build_hair_short(model, parent, head_y)
			build_hair_ponytail(model, parent, head_y)
		"Iroquois":
			build_hair_mohawk(model, parent, head_y)
		"Touffu":
			build_hair_bushy(model, parent, head_y)
		"Frange basse":
			build_hair_low_fringe(model, parent, head_y)
		"Longs":
			build_hair_short(model, parent, head_y)
			build_hair_long(model, parent, head_y)
		"Tresse":
			build_hair_short(model, parent, head_y)
			build_hair_braid(model, parent, head_y)
		_:  # "Court" (defaut)
			build_hair_short(model, parent, head_y)


## Cheveux courts, proches du crane. Sprint 28quater : au lieu d'une boule
## de cheveux posee au-dessus de la tete (look "poof" peu realiste, et bug
## corrige au Sprint 28ter ou elle etait presque entierement avalee dans la
## tete), on utilise maintenant une sphere a peine plus grande que la tete
## (hair_size ~1.08x), centree presque au meme endroit mais legerement
## remontee (hair_lift) et decalee vers l'arriere (hair_back_offset) - ca
## forme une fine "enveloppe" qui suit le crane de pres sur le dessus/
## l'arriere/les cotes, tout en degageant le visage a l'avant et la nuque/
## machoire en bas (elle ne redescend pas assez pour les atteindre). Les 3
## parametres sont exposes pour ajuster la coupe a l'oeil sans coder.
static func build_hair_short(model: Node3D, parent: Node, head_y: float) -> void:
	var head_radius: float = model.get("head_radius")
	var hair := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	var hair_radius: float = head_radius * float(model.get("hair_size"))
	hair_mesh.radius = hair_radius
	hair_mesh.height = hair_radius * 2.0  # sphere pleine, pas aplatie
	hair.mesh = hair_mesh
	var base_pos := Vector3(
		0,
		head_y + head_radius * float(model.get("hair_lift")),
		-head_radius * float(model.get("hair_back_offset"))
	)
	hair.position = base_pos
	hair.name = "Hair"
	hair.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("hair_color")))
	parent.add_child(hair)
	hair.owner = Model3DUtilsScript.edited_owner(model)

	# Sprint 28unseptuagesies : silhouette jugee "trop circulaire", demande
	# de texture/variation - une vraie texture d'image serait incoherente
	# avec le style plat/non-eclaire du jeu (voir Model3DUtils.flat_material),
	# donc option la plus simple retenue : quelques petites "meches" (spheres)
	# superposees sur la sphere principale, legerement decalees et teintees
	# (voir hair_color_variant) - casse la silhouette parfaitement ronde et
	# evite un aplat de couleur uniforme, sans texture ni UV.
	# Sprint 28troisseptuagesies : la 1ere version placait les meches TROP
	# PRES du centre (offset x0.55 du rayon) - avec un rayon de meche
	# (~0.35x) plus petit que le rayon principal (1.0x), la meche restait
	# entierement CONTENUE dans la sphere principale (invisible, cachee a
	# l'interieur) - aucune difference visible, signale par l'utilisateur.
	# Corrige en placant chaque meche sur la SURFACE de la sphere principale
	# (direction normalisee x hair_radius), pour qu'elle depasse clairement
	# vers l'exterieur.
	# Sprint 28quatreseptuagesies : "plus de meches, beaucoup plus petites"
	# demande par l'utilisateur - chacune des 5 directions "sures" ci-dessus
	# (deja verifiees pour ne pas deborder sur le visage) est declinee en 3
	# petites variantes (leger bruit aleatoire avant normalisation), pour un
	# total de 15 petites meches au lieu de 5 grandes - reste dans les memes
	# zones surface deja validees, juste plus fin/granuleux.
	var base_dirs := [
		Vector3(0.6, 0.5, 0.3),
		Vector3(-0.6, 0.4, 0.25),
		Vector3(0.0, 0.75, -0.2),
		Vector3(0.4, -0.15, -0.65),
		Vector3(-0.4, -0.05, -0.65),
	]
	var tuft_index := 0
	for base_dir in base_dirs:
		for v in range(3):
			build_hair_tuft(model, parent, base_pos, hair_radius, base_dir, tuft_index)
			tuft_index += 1


## 2026-07-06 (revue de code, paquet E, I63) : extrait de _build_hair_short()
## - construit UNE meche (corps de la double boucle base_dirs x variantes),
## aucun changement de comportement.
static func build_hair_tuft(model: Node3D, parent: Node, base_pos: Vector3, hair_radius: float, base_dir: Vector3, tuft_index: int) -> void:
	var jitter := Vector3(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15), randf_range(-0.15, 0.15))
	var dir: Vector3 = (base_dir + jitter).normalized()
	var tuft := MeshInstance3D.new()
	var tuft_mesh := SphereMesh.new()
	var tuft_radius: float = hair_radius * randf_range(0.10, 0.16)
	tuft_mesh.radius = tuft_radius
	tuft_mesh.height = tuft_radius * 2.0
	tuft.mesh = tuft_mesh
	tuft.position = base_pos + dir * hair_radius * 0.95
	tuft.name = "HairTuft_%d" % tuft_index
	tuft.set_surface_override_material(0, Model3DUtilsScript.flat_material(hair_color_variant(model.get("hair_color"))))
	parent.add_child(tuft)
	tuft.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28unseptuagesies : leger jitter aleatoire de couleur (+/-8% par
## canal, clampe 0-1) - utilise pour les "meches" de cheveux (voir
## build_hair_short) afin d'eviter un aplat de couleur parfaitement uniforme,
## sans avoir besoin d'une vraie texture d'image (incompatible avec le style
## plat/non-eclaire du jeu, voir Model3DUtils.flat_material).
static func hair_color_variant(base: Color) -> Color:
	return Model3DUtilsScript.color_variant(base, 0.08)


## Sprint 28septdecies : "Touffu" recouvrait tout le visage - le recul precedent
## (hair_back_offset * 0.6, donc REDUIT par rapport aux cheveux courts) etait
## pense pour une sphere a peine plus grande, pas pour une sphere 1.35x plus
## grosse : son avant (centre + rayon) depassait tres largement devant les
## yeux/le nez (jusqu'a ~1.33x head_radius, alors que le nez est a ~0.95x).
## Corrige en calculant le recul a partir d'une limite avant explicite
## (front_target, nettement derriere les yeux a 0.90x head_radius) plutot que
## de partir d'un facteur de recul pense pour une sphere plus petite.
static func build_hair_bushy(model: Node3D, parent: Node, head_y: float) -> void:
	var head_radius: float = model.get("head_radius")
	var hair := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	# Sprint 28septuagesies : "boule" de cheveux "Touffu" jugee trop grosse
	# (1.35x le rayon de la tete, tres proeminente) - reduite a 1.15x. Le
	# calcul de front_target ci-dessous reste inchange et continue de garantir
	# que la sphere (quelle que soit sa taille) ne deborde jamais sur le
	# visage (voir Sprint 28septdecies).
	var hair_radius: float = head_radius * float(model.get("hair_size")) * 1.15
	hair_mesh.radius = hair_radius
	hair_mesh.height = hair_radius * 2.0
	hair.mesh = hair_mesh
	var front_target: float = head_radius * 0.62  # limite avant voulue, nettement derriere les yeux (0.90x) et le nez (0.95x)
	var offset_z: float = front_target - hair_radius  # recul necessaire pour que centre+rayon = front_target
	hair.position = Vector3(
		0,
		head_y + head_radius * (float(model.get("hair_lift")) + 0.05),
		offset_z
	)
	hair.name = "Hair"
	hair.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("hair_color")))
	parent.add_child(hair)
	hair.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28vicies : correction complete de "Frange basse" - la 1ere version
## (Sprint 28octodecies) ajoutait un 2e morceau de cheveux (une sphere aplatie
## separee, collee au-dessus des sourcils) EN PLUS du casque court existant,
## ce qui laissait un anneau de peau visible entre les deux (bug signale par
## l'utilisateur sur le modele "7" de la grille) - et ce n'etait de toute
## facon pas ce qui etait demande : il fallait avancer/abaisser la ligne de
## cheveux EXISTANTE, pas en ajouter une nouvelle. Corrige en repensant la
## coupe courte comme UNE SEULE sphere (comme build_hair_short), mais avec
## son centre remonte (dy=0.46 au lieu de hair_lift=0.15, donc le "ventre" le
## plus large de la sphere se retrouve au niveau du front/des sourcils au lieu
## du niveau des yeux) et moins reculee vers l'arriere (0.16 au lieu de 0.22) -
## la sphere avance donc plus loin PRECISEMENT devant le front, tout en
## restant en retrait au niveau des yeux/du nez (plus bas, donc plus loin de
## l'equateur de la sphere, qui recule naturellement a mesure qu'on s'eloigne
## du centre).
static func build_hair_low_fringe(model: Node3D, parent: Node, head_y: float) -> void:
	var head_radius: float = model.get("head_radius")
	var hair := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	var hair_radius: float = head_radius * float(model.get("hair_size")) * 1.02  # a peine plus grande que "Court"
	hair_mesh.radius = hair_radius
	hair_mesh.height = hair_radius * 2.0
	hair.mesh = hair_mesh
	var dy: float = head_radius * 0.46
	var z_offset: float = -head_radius * 0.16
	hair.position = Vector3(0, head_y + dy, z_offset)
	hair.name = "Hair"
	hair.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("hair_color")))
	parent.add_child(hair)
	hair.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28novodecies : cheveux "Longs" - en plus de la base courte, une masse
## de cheveux (cylindre effile) qui descend le long de l'arriere du crane
## jusqu'a la nuque/le haut des epaules (contrairement a "Attache", pas de
## veritable queue fine qui se detache : c'est une masse continue, large,
## posee contre l'arriere de la tete).
static func build_hair_long(model: Node3D, parent: Node, head_y: float) -> void:
	var head_radius: float = model.get("head_radius")
	var shoulder_y: float = float(model.get("leg_height")) + float(model.get("torso_height")) - 0.06
	var top_y: float = head_y + head_radius * 0.3
	var bottom_y: float = shoulder_y + 0.05
	var mane := MeshInstance3D.new()
	var mane_mesh := CylinderMesh.new()
	mane_mesh.top_radius = head_radius * 0.55
	mane_mesh.bottom_radius = head_radius * 0.35
	mane_mesh.height = top_y - bottom_y
	mane.mesh = mane_mesh
	mane.position = Vector3(0, (top_y + bottom_y) * 0.5, -head_radius * (float(model.get("hair_back_offset")) + 0.55))
	mane.name = "HairLong"
	mane.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("hair_color")))
	parent.add_child(mane)
	mane.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28novodecies : cheveux "Tresse" - en plus de la base courte, une
## petite "attache" (sphere) a la base du crane puis une longue tresse fine
## (cylindre effile) qui descend loin dans le dos, terminee par une petite
## perle (meme principe que la barbe "Tressee", voir build_beard_braid_tip).
static func build_hair_braid(model: Node3D, parent: Node, head_y: float) -> void:
	var head_radius: float = model.get("head_radius")
	var hair_color: Color = model.get("hair_color")
	var attach_y: float = head_y - head_radius * 0.15
	var braid_length: float = head_radius * 2.6
	var z_offset: float = -head_radius * (float(model.get("hair_back_offset")) + 0.5)

	var tie := MeshInstance3D.new()
	var tie_mesh := SphereMesh.new()
	tie_mesh.radius = head_radius * 0.11
	tie_mesh.height = tie_mesh.radius * 2.0
	tie.mesh = tie_mesh
	tie.position = Vector3(0, attach_y, z_offset)
	tie.name = "HairBraidTie"
	tie.set_surface_override_material(0, Model3DUtilsScript.flat_material(hair_color))
	parent.add_child(tie)
	tie.owner = Model3DUtilsScript.edited_owner(model)

	var braid := MeshInstance3D.new()
	var braid_mesh := CylinderMesh.new()
	braid_mesh.top_radius = head_radius * 0.13
	braid_mesh.bottom_radius = head_radius * 0.07
	braid_mesh.height = braid_length
	braid.mesh = braid_mesh
	braid.position = Vector3(0, attach_y - braid_length * 0.5, z_offset)
	braid.name = "HairBraid"
	braid.set_surface_override_material(0, Model3DUtilsScript.flat_material(hair_color))
	parent.add_child(braid)
	braid.owner = Model3DUtilsScript.edited_owner(model)

	var end_bead := MeshInstance3D.new()
	var end_mesh := SphereMesh.new()
	end_mesh.radius = head_radius * 0.09
	end_mesh.height = end_mesh.radius * 2.0
	end_bead.mesh = end_mesh
	end_bead.position = Vector3(0, attach_y - braid_length, z_offset)
	end_bead.name = "HairBraidEnd"
	end_bead.set_surface_override_material(0, Model3DUtilsScript.flat_material(hair_color * 0.85))
	parent.add_child(end_bead)
	end_bead.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28quindecies : cheveux "Attache" - la base courte (build_hair_short)
## plus une "queue" attachee : cylindre effile partant de l'arriere du crane
## et retombant en biais vers le bas/l'arriere.
static func build_hair_ponytail(model: Node3D, parent: Node, head_y: float) -> void:
	var head_radius: float = model.get("head_radius")
	var tail := MeshInstance3D.new()
	var tail_mesh := CylinderMesh.new()
	tail_mesh.top_radius = head_radius * 0.12
	tail_mesh.bottom_radius = head_radius * 0.05
	tail_mesh.height = head_radius * 1.1
	tail.mesh = tail_mesh
	tail.position = Vector3(0, head_y - head_radius * 0.25, -head_radius * (float(model.get("hair_back_offset")) + 0.55))
	tail.rotation.x = deg_to_rad(75)  # incline vers l'arriere-bas
	tail.name = "HairTail"
	tail.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("hair_color")))
	parent.add_child(tail)
	tail.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28quindecies : cheveux "Iroquois" - simple crete fine (boite) posee
## sur le sommet de la tete, centree sur l'axe avant-arriere.
static func build_hair_mohawk(model: Node3D, parent: Node, head_y: float) -> void:
	var head_radius: float = model.get("head_radius")
	var mohawk := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(head_radius * 0.18, head_radius * 0.55, head_radius * 1.3)
	mohawk.mesh = mesh
	var head_top: float = head_y + head_radius * float(model.get("head_height_factor"))
	mohawk.position = Vector3(0, head_top + head_radius * 0.12, 0)
	mohawk.name = "Hair"
	mohawk.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("hair_color")))
	parent.add_child(mohawk)
	mohawk.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28quindecies/28unvicies : aiguille vers l'une des formes de barbe
## selon "beard_style" (voir @export_enum dans DwarfModel3D.gd). "Sans barbe"
## ne construit rien. Plupart reutilisent build_beard_shape (meme cone que
## l'original, juste parametrise en largeur/longueur/position) ; "Tressee"
## ajoute une petite "perle" au bout ; "Moustache"/"Fourchue" ont leur propre
## forme (pas un simple cone).
static func build_beard(model: Node3D, parent: Node, head_y: float) -> void:
	var head_radius: float = model.get("head_radius")
	match model.get("beard_style"):
		"Sans barbe":
			return
		"Longue":
			build_beard_shape(model, parent, head_y, head_radius * 0.38, 0.60, -head_radius * 0.62)
		"Tressee":
			build_beard_shape(model, parent, head_y, head_radius * 0.32, 0.62, -head_radius * 0.65)
			build_beard_braid_tip(model, parent, head_y)
		"Fournie":
			# Sprint 28duoseptuagesies : etait 0.72 - base deja tres large
			# avant meme beard_width, principale cause du "gros triangle"
			# encore visible malgre le premier plafonnement (n°19, toujours
			# signale). Reduite a 0.48 et hauteur augmentee (0.32->0.42) pour
			# un cone plus effile, moins large/plat.
			build_beard_shape(model, parent, head_y, head_radius * 0.48, 0.42, -head_radius * 0.55)
		"Bouc":
			build_beard_shape(model, parent, head_y, head_radius * 0.24, 0.20, -head_radius * 0.60)
		"Moustache":
			build_beard_moustache(model, parent, head_y)
		"Fourchue":
			build_beard_forked(model, parent, head_y)
		_:  # "Courte" (defaut)
			# Sprint 28duoseptuagesies : etait 0.55 - trop large pour une
			# barbe "courte", contribuait aussi au bug signale. Reduite a
			# 0.40.
			build_beard_shape(model, parent, head_y, head_radius * 0.40, 0.30, -head_radius * 0.55)


## Forme conique sous le menton : trait caracteristique du nain. Parametree
## (top_radius/height/dy) pour etre reutilisee par les differents styles de
## barbe (voir build_beard) - avec les valeurs d'origine, "Courte" reproduit
## exactement la forme du Sprint 28bis.
static func build_beard_shape(model: Node3D, parent: Node, head_y: float, top_radius: float, height: float, dy: float) -> void:
	var head_radius: float = model.get("head_radius")
	var beard_width: float = model.get("beard_width")
	var beard := MeshInstance3D.new()
	var beard_mesh := CylinderMesh.new()
	# Sprint 28neufsexagesies/28duoseptuagesies : "beard_width" (tire au
	# hasard, voir _randomize_variation dans DwarfModel3D.gd) multipliait un
	# top_radius deja large pour certains styles sans limite suffisante - un
	# 1er plafond a 0.85x head_radius restait encore trop genereux (bug
	# encore visible, n°19, signale a nouveau). Resserre a 0.58x, combine a
	# des top_radius de base reduits (voir build_beard) et une plage
	# beard_width plus etroite (voir _randomize_variation).
	beard_mesh.top_radius = min(top_radius * beard_width, head_radius * 0.58)
	beard_mesh.bottom_radius = 0.02
	beard_mesh.height = height
	beard.mesh = beard_mesh
	beard.position = Vector3(0, head_y + dy, head_radius * 0.55)
	beard.rotation.x = deg_to_rad(-20)
	beard.name = "Beard"
	beard.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("beard_color")))
	parent.add_child(beard)
	beard.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28quindecies : petite "perle" au bout de la barbe "Tressee" -
## position approximative (pas suivie point par point le long du cone
## incline), a ajuster a l'oeil si besoin une fois vu dans Godot.
static func build_beard_braid_tip(model: Node3D, parent: Node, head_y: float) -> void:
	var head_radius: float = model.get("head_radius")
	var tip := MeshInstance3D.new()
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = head_radius * 0.10
	tip_mesh.height = tip_mesh.radius * 2.0
	tip.mesh = tip_mesh
	tip.position = Vector3(0, head_y - head_radius * 1.05, head_radius * 0.75)
	tip.name = "BeardTip"
	tip.set_surface_override_material(0, Model3DUtilsScript.flat_material(model.get("beard_color") * 0.8))
	parent.add_child(tip)
	tip.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28unvicies : "Moustache" - pas de barbe au menton, juste une fine
## moustache sous le nez (au-dessus de la bouche, qui est placee a dy=-0.31 -
## voir _build_mouth dans DwarfModel3D.gd).
static func build_beard_moustache(model: Node3D, parent: Node, head_y: float) -> void:
	var head_radius: float = model.get("head_radius")
	var head_height_factor: float = model.get("head_height_factor")
	var beard_width: float = model.get("beard_width")
	var beard_color: Color = model.get("beard_color")
	# Sprint 28septseptuagesies : refonte en "fer a cheval" (horseshoe) -
	# l'utilisateur n'aimait pas la simple barre horizontale d'origine.
	# Desormais : la meme barre au-dessus de la levre, PLUS deux meches qui
	# tombent de chaque cote de la bouche jusque vers le bas du menton (meme
	# technique de cone effile que build_beard_forked).
	var dy: float = -head_radius * 0.22
	var z: float = Model3DUtilsScript.head_surface_radius(head_radius, head_height_factor, dy) * 1.05
	# Sprint 28octoseptuagesies : etait 0.21 - a peine plus etroit que la
	# bouche elle-meme (half_width = 0.22, voir _build_mouth), donc les
	# meches tombantes traversaient la bouche au lieu de l'encadrer, signale
	# par l'utilisateur. Elargi a 0.32 pour rester nettement a l'exterieur.
	var half_width: float = head_radius * 0.32 * beard_width

	var stache := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(half_width * 2.0, head_radius * 0.09, head_radius * 0.09)
	stache.mesh = mesh
	stache.position = Vector3(0, head_y + dy, z)
	stache.name = "Beard"
	stache.set_surface_override_material(0, Model3DUtilsScript.flat_material(beard_color))
	parent.add_child(stache)
	stache.owner = Model3DUtilsScript.edited_owner(model)

	for side in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"
		var strand_dy: float = dy - head_radius * 0.19
		var strand_z: float = Model3DUtilsScript.head_surface_radius(head_radius, head_height_factor, strand_dy) * 1.05
		var strand := MeshInstance3D.new()
		var strand_mesh := CylinderMesh.new()
		strand_mesh.top_radius = head_radius * 0.05 * beard_width
		strand_mesh.bottom_radius = head_radius * 0.02 * beard_width
		strand_mesh.height = head_radius * 0.38
		strand.mesh = strand_mesh
		strand.position = Vector3(side * half_width * 0.95, head_y + strand_dy, strand_z)
		strand.rotation.x = deg_to_rad(-8)
		strand.rotation.z = deg_to_rad(side * -6.0)  # leger evasement vers l'exterieur
		strand.name = "BeardStrand_%s" % side_name
		strand.set_surface_override_material(0, Model3DUtilsScript.flat_material(beard_color))
		parent.add_child(strand)
		strand.owner = Model3DUtilsScript.edited_owner(model)


## Sprint 28unvicies : "Fourchue" - deux meches distinctes qui divergent
## depuis le menton (au lieu d'un cone unique centre), chacune terminee par
## une petite perle (meme principe que build_beard_braid_tip).
static func build_beard_forked(model: Node3D, parent: Node, head_y: float) -> void:
	var head_radius: float = model.get("head_radius")
	var beard_width: float = model.get("beard_width")
	var beard_color: Color = model.get("beard_color")
	for side in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"

		var strand := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = head_radius * 0.16 * beard_width
		mesh.bottom_radius = head_radius * 0.03 * beard_width
		mesh.height = 0.42
		strand.mesh = mesh
		strand.position = Vector3(side * head_radius * 0.14 * beard_width, head_y - head_radius * 0.58, head_radius * 0.55)
		strand.rotation.x = deg_to_rad(-20)
		strand.rotation.z = deg_to_rad(side * -12.0)  # ecarte les deux meches l'une de l'autre
		strand.name = "Beard_%s" % side_name
		strand.set_surface_override_material(0, Model3DUtilsScript.flat_material(beard_color))
		parent.add_child(strand)
		strand.owner = Model3DUtilsScript.edited_owner(model)

		var tip := MeshInstance3D.new()
		var tip_mesh := SphereMesh.new()
		tip_mesh.radius = head_radius * 0.07
		tip_mesh.height = tip_mesh.radius * 2.0
		tip.mesh = tip_mesh
		tip.position = Vector3(side * head_radius * 0.28 * beard_width, head_y - head_radius * 1.0, head_radius * 0.62)
		tip.name = "BeardTip_%s" % side_name
		tip.set_surface_override_material(0, Model3DUtilsScript.flat_material(beard_color * 0.85))
		parent.add_child(tip)
		tip.owner = Model3DUtilsScript.edited_owner(model)
