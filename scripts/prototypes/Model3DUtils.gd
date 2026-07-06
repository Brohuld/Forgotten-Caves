extends RefCounted
## 2026-07-06 (revue de code, paquet E, M58 - etape 1/3) : utilitaires
## partages entre DwarfModel3D.gd et ses futurs fichiers "builder" extraits
## (DwarfWeaponBuilder.gd, puis DwarfOutfitBuilder.gd/DwarfHairBuilder.gd aux
## etapes suivantes). Copie exacte de DwarfModel3D._flat_material/
## _edited_owner (aucun changement de comportement) - DwarfModel3D.gd garde
## ses propres copies privees pour les fonctions qui n'ont pas encore ete
## extraites, afin de ne pas toucher a du code non concerne par cette etape.
##
## Fonctions statiques et independantes de tout etat (RefCounted, pas de
## reference typee vers DwarfModel3D) - pensees pour etre reutilisables par
## de futurs types de personnages (autres races/visiteurs...) qui n'heriteront
## pas forcement de DwarfModel3D.


## Materiau plat non eclaire, coherent avec le style du reste du jeu
## (terrain, arbres, decorations, outils - voir Forest.gd/_flat_material).
## "double_sided" desactive le retrait des faces arriere - utilise pour des
## meshes dont le sens des triangles n'est pas garanti face par face.
static func flat_material(color: Color, double_sided: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if double_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## En mode editeur (@tool), il faut assigner "owner" a chaque noeud genere
## pour qu'il soit visible/sauvegardable dans la scene ouverte - sans ca,
## les formes s'affichent mais n'apparaissent pas dans l'arborescence et
## disparaissent a la fermeture de Godot. Sans effet en jeu (owner inutile
## a l'execution normale). "node" doit deja etre dans l'arbre de scene pour
## que get_tree() fonctionne (meme contrainte que la version d'origine).
static func edited_owner(node: Node) -> Node:
	if Engine.is_editor_hint():
		return node.get_tree().edited_scene_root
	return null


## 2026-07-06 (bug) : assigne "owner" a "node" ET a tous ses descendants,
## d'un coup, APRES que "node" a ete accroche a son parent final dans
## l'arbre reel. Corrige "Invalid owner. Owner must be an ancestor in the
## tree." (DwarfWeaponBuilder.gd) : avant, chaque sous-piece d'une arme
## recevait son owner juste apres avoir ete ajoutee a un groupe encore
## orphelin (pas encore attache nulle part) - a cet instant, la racine de
## scene editee ne peut pas etre un ancetre de la piece, donc Godot refuse
## l'assignation (verifiee immediatement, pas differee a l'entree dans
## l'arbre). Sans consequence visuelle (owner ne sert qu'a la persistance/
## visibilite dans le panneau Scene de l'editeur), mais empechait ces pieces
## d'etre sauvegardees avec la scene et polluait la console. En appelant
## cette fonction une seule fois sur le groupe complet, DEJA accroche a son
## parent final, l'ancetre est valide pour tout le monde d'un coup.
static func adopt_recursive(node: Node, owner: Node) -> void:
	if not owner:
		return
	node.owner = owner
	for child in node.get_children():
		adopt_recursive(child, owner)


## 2026-07-06 (revue de code, paquet E, M58 - etape 2/3) : copie de
## DwarfModel3D._make_trapezoid_mesh (aucun changement de comportement) -
## utilisee par DwarfOutfitBuilder.gd (manteau/plastron). DwarfModel3D.gd
## garde sa propre copie privee, encore utilisee par _build_torso (pas
## extrait a cette etape).
## Sprint 28quinquies : construit un tronc de piramide (base rectangulaire en
## haut, base rectangulaire differente en bas) - aucun mesh primitif de Godot
## ne fait ca directement (CylinderMesh permet bien un rayon different en
## haut/bas, mais uniquement pour une base ronde).
static func make_trapezoid_mesh(size_top: Vector2, size_bottom: Vector2, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hy: float = height * 0.5
	var tw: float = size_top.x * 0.5
	var td: float = size_top.y * 0.5
	var bw: float = size_bottom.x * 0.5
	var bd: float = size_bottom.y * 0.5

	var top_fl := Vector3(-tw, hy, td)
	var top_fr := Vector3(tw, hy, td)
	var top_bl := Vector3(-tw, hy, -td)
	var top_br := Vector3(tw, hy, -td)
	var bot_fl := Vector3(-bw, -hy, bd)
	var bot_fr := Vector3(bw, -hy, bd)
	var bot_bl := Vector3(-bw, -hy, -bd)
	var bot_br := Vector3(bw, -hy, -bd)

	add_quad(st, bot_fl, bot_fr, top_fr, top_fl)  # face avant (+Z)
	add_quad(st, bot_br, bot_bl, top_bl, top_br)  # face arriere (-Z)
	add_quad(st, bot_bl, bot_fl, top_fl, top_bl)  # face gauche (-X)
	add_quad(st, bot_fr, bot_br, top_br, top_fr)  # face droite (+X)
	add_quad(st, top_fl, top_fr, top_br, top_bl)  # dessus (+Y)
	add_quad(st, bot_fr, bot_fl, bot_bl, bot_br)  # dessous (-Y)

	st.generate_normals()
	return st.commit()


## Copie de DwarfModel3D._add_quad (aucun changement de comportement).
static func add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


## 2026-07-06 (revue de code, paquet E, M58 - etape 3/3) : copie de
## DwarfModel3D._color_variant (aucun changement de comportement) - utilisee
## par DwarfHairBuilder.hair_color_variant(). DwarfModel3D.gd garde sa propre
## copie privee, encore utilisee par _randomize_variation() pour les themes
## d'habits (pas concernee par cette etape).
## Sprint 28quinseptuagesies : jitter generique (facteur ajustable) de
## couleur (+/-jitter par canal, clampe 0-1).
static func color_variant(base: Color, jitter: float) -> Color:
	var rng: RandomNumberGenerator = GameRandom.get_rng("nains_apparence")
	return Color(
		clampf(base.r * rng.randf_range(1.0 - jitter, 1.0 + jitter), 0.0, 1.0),
		clampf(base.g * rng.randf_range(1.0 - jitter, 1.0 + jitter), 0.0, 1.0),
		clampf(base.b * rng.randf_range(1.0 - jitter, 1.0 + jitter), 0.0, 1.0)
	)


## 2026-07-06 (revue de code, paquet E, M58 - etape 3/3) : copie de
## DwarfModel3D._head_surface_radius (aucun changement de comportement) -
## utilisee par DwarfHairBuilder.gd (barbe moustache/fourchue). DwarfModel3D.gd
## garde sa propre copie privee (encore utilisee par _build_face, pas extrait
## a cette etape). Prend head_radius/head_height_factor en parametres au lieu
## de lire des champs d'instance.
## Sprint 28octies : rayon (dans le plan XZ) de la surface ovale de la tete a
## un decalage vertical "dy" donne (relatif au centre de la tete) - geometrie
## d'ellipsoide : a une hauteur donnee, le rayon horizontal restant est
## head_radius*sin(phi), ou phi est l'angle polaire correspondant.
static func head_surface_radius(head_radius: float, head_height_factor: float, dy: float) -> float:
	var half_height: float = head_radius * head_height_factor
	var cos_phi: float = clampf(dy / half_height, -1.0, 1.0)
	var sin_phi: float = sqrt(max(1.0 - cos_phi * cos_phi, 0.0))
	return head_radius * sin_phi
