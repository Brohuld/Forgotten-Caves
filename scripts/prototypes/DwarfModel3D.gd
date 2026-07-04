@tool
extends Node3D
## Sprint 28 : PROTOTYPE separe pour experimenter avec un "vrai" nain 3D
## (formes generees par code, meme principe que les arbres/objets du monde -
## voir Forest.gd) en remplacement eventuel du sprite 2D illustre actuel
## (voir Dwarf.gd/_build_appearance).
##
## Ce script ne touche a AUCUN fichier du jeu principal (Dwarf.gd, Main.tscn
## restent inchanges) - il vit dans sa propre scene
## (scenes/prototypes/DwarfModel3DPrototype.tscn) qu'on peut ouvrir et
## executer seule dans Godot (bouton "Executer la scene actuelle", ou F6)
## sans lancer tout le jeu.
##
## @tool : ce script s'execute aussi DANS L'EDITEUR (pas seulement en jeu),
## donc le modele apparait des l'ouverture de la scene, avant meme d'appuyer
## sur Jouer. Toutes les valeurs ci-dessous (couleurs + proportions) sont
## reglables dans l'Inspecteur sans toucher au code ; coche "Rebuild In
## Editor" (en bas) apres un changement pour regenerer le modele et voir le
## resultat immediatement.
##
## Si le style convient, cette logique sera portee dans Dwarf.gd (nouvelle
## fonction _build_appearance_3d_model(), utilisee a la place du sprite) -
## rien n'est encore decide, ce fichier sert juste a essayer/ajuster.

@export_group("Couleurs")
@export var skin_color: Color = Color(0.85, 0.68, 0.52)
@export var hair_color: Color = Color(0.59, 0.45, 0.33)
@export var beard_color: Color = Color(0.80, 0.71, 0.53)
@export var clothing_color: Color = Color(0.68, 0.51, 0.41)  # chemise/torse/bras
## Sprint 28quinseptuagesies : couleur du pantalon (jambes), separee de
## clothing_color (chemise/torse/bras) - avant, les jambes reutilisaient
## simplement clothing_color * 0.85 (variation fixe, jamais independante).
## Desormais tiree du meme "theme" que la chemise mais avec sa propre petite
## variation aleatoire (voir _randomize_variation/CLOTHING_THEMES).
@export var pants_color: Color = Color(0.58, 0.43, 0.35)
@export var armor_color: Color = Color(0.55, 0.55, 0.58)
@export var boot_color: Color = Color(0.25, 0.18, 0.12)
@export var coat_color: Color = Color(0.38, 0.30, 0.24)  # manteau (voir _build_coat) - theme derive, comme clothing_color/pants_color

## Sprint 28sixseptuagesies : gants et manteau, demande par l'utilisateur -
## des accessoires INDEPENDANTS de outfit_style (voir plus bas), pas des
## options exclusives : un manteau ou des gants peuvent se porter par-dessus
## n'importe quelle tenue (tunique ou armure). Les gants reutilisent
## boot_color (cuir, meme logique que les bottes) plutot qu'une nouvelle
## couleur dediee, pour ne pas surcharger l'Inspecteur pour un petit
## accessoire.
@export_group("Accessoires")
@export var wear_gloves: bool = false
@export var wear_coat: bool = false

@export_group("Proportions")
@export var leg_height: float = 0.26  # raccourci (etait 0.34) - silhouette plus trapue
@export var torso_height: float = 0.46
# Sprint 28quinquies : le torse etait une simple boite (largeur constante).
# Remplace par un tronc de piramide (voir _make_trapezoid_mesh) : plus large
# aux epaules qu'a la taille, pour un vrai effet "trapeze" (silhouette en V).
@export var torso_shoulder_width: float = 0.58  # largeur aux epaules (haut) - encore elargi (etait 0.50)
@export var torso_waist_width: float = 0.36     # largeur a la taille (bas)
@export var torso_depth: float = 0.22
@export var head_radius: float = 0.22
@export var head_height_factor: float = 1.22  # >1 = tete plus haute que large (ovale), 1.0 = sphere parfaite
@export var arm_length: float = 0.36
@export var hair_size: float = 1.08        # rayon des cheveux / rayon de la tete (>1 = legere enveloppe autour du crane)
## Sprint 28octosexagesies : hair_lift 0.15->0.25 et hair_back_offset
## 0.22->0.17 - la ligne de cheveux de la coiffure "Court" (par defaut)
## remontait trop haut sur le front (grand front degarni visible, meme
## principe de correction que "Frange basse", voir _build_hair_low_fringe),
## signale par l'utilisateur. Ces 2 valeurs sont partagees par plusieurs
## coiffures (Court/Attache/Longs/Tresse, toutes basees sur
## _build_hair_short), donc toutes en beneficient.
@export var hair_lift: float = 0.25        # decalage vertical du centre des cheveux, fraction de head_radius (remonte vers le sommet du crane)
@export var hair_back_offset: float = 0.17 # decalage vers l'arriere, fraction de head_radius (degage le visage a l'avant)

# Couleurs fixes du visage (pas exposees comme les couleurs principales, pour
# ne pas surcharger l'Inspecteur - facile a exposer plus tard si besoin)
const EYE_COLOR := Color(0.12, 0.10, 0.09)
const EYE_WHITE_COLOR := Color(0.95, 0.95, 0.93)  # "fond" blanc de l'oeil, derriere la pupille

## Sprint 28duovicies : palette de couleurs naturelles piochee par
## _randomize_variation() pour hair_color/beard_color (les sourcils suivent
## automatiquement, voir _build_eyebrows qui derive brow_color de hair_color).
const NATURAL_HAIR_COLORS := [
	Color(0.15, 0.14, 0.13),  # noir
	Color(0.60, 0.55, 0.47),  # gris - etait (0.55, 0.55, 0.57), un gris neutre trop proche des materiaux d'armes (voir MATERIAL_COLORS, Fer/Acier), signale par l'utilisateur. Undertone chaud/brun ajoute pour se distinguer clairement du metal.
	Color(0.68, 0.55, 0.28),  # blond - etait (0.85, 0.72, 0.45), quasi la meme luminosite que skin_color (0.85, 0.68, 0.52) : invisible/peu lisible sur le visage (barbe/moustache), signale par l'utilisateur. Assombri nettement pour contraster.
	Color(0.72, 0.35, 0.18),  # roux
	Color(0.40, 0.27, 0.15),  # chatain
]

## Sprint 28quinseptuagesies : "themes" d'habits - un theme est tire au hasard
## par _randomize_variation(), puis chemise (clothing_color) et pantalon
## (pants_color) sont derives de ce meme theme avec une petite variation
## chacun (voir _clothing_color_variant), pour rester coordonnes sans etre
## identiques. Toutes les teintes sont volontairement DESATUREES/mates (pas
## de couleurs vives), demande explicite de l'utilisateur.
const CLOTHING_THEMES := [
	Color(0.45, 0.45, 0.47),  # gris
	Color(0.20, 0.19, 0.18),  # noir (charbon, pas un noir pur)
	Color(0.33, 0.40, 0.29),  # vert (olive/foret, mat)
	Color(0.45, 0.24, 0.22),  # rouge (brique delavee)
	Color(0.28, 0.33, 0.42),  # bleu (ardoise)
	Color(0.42, 0.31, 0.21),  # marron
]

## Sprint 28duotrigesies : palette de materiaux pour la tete/lame des armes -
## meme principe que NATURAL_HAIR_COLORS, un ton par materiau, choisi via le
## menu deroulant "Weapon Material" (voir _weapon_material_color).
const MATERIAL_COLORS := {
	"Bois": Color(0.42, 0.28, 0.15),
	"Cuivre": Color(0.72, 0.45, 0.20),
	"Fer": Color(0.40, 0.40, 0.43),
	"Acier": Color(0.80, 0.82, 0.85),
}

## Sprint 28quindecies : variations - formes de cheveux/barbe + corpulence.
## Exposees en @export_enum (menu deroulant dans l'Inspecteur, reglable a la
## main), ET pilotables via le bouton "Randomiser" (groupe Debug plus bas) qui
## tire une combinaison au hasard, y compris torso_shoulder_width (deja
## exportee dans "Proportions" ci-dessus).
@export_group("Variations")
@export_enum("Chauve", "Court", "Attache", "Iroquois", "Touffu", "Frange basse", "Longs", "Tresse") var hair_style: String = "Court"
## Sprint 28unvicies : 3 nouveaux styles (Bouc/Moustache/Fourchue) en plus des
## 5 existants, pour varier largeur/longueur/forme de la barbe.
@export_enum("Sans barbe", "Courte", "Longue", "Tressee", "Fournie", "Bouc", "Moustache", "Fourchue") var beard_style: String = "Courte"
@export_range(0.6, 1.6, 0.02) var beard_width: float = 1.0  # multiplicateur de largeur, combinable avec tous les styles ci-dessus (voir _build_beard_shape/_moustache/_forked)
@export_range(0.7, 1.4, 0.01) var corpulence: float = 1.0  # multiplicateur de largeur/epaisseur (mince <-> costaud), n'affecte pas la largeur d'epaules (torso_shoulder_width, deja separement reglable/randomisable)

## Sprint 28unvicies : tenue/armure portee par-dessus le corps existant (le
## torse reste la "tunique de base" dans tous les cas - voir _build_torso).
@export_enum("Tunique simple", "Tunique + cape", "Armure legere", "Armure lourde") var outfit_style: String = "Tunique simple"

## Sprint 28quinvicies : equipement d'armes - 5 configurations possibles
## (voir _build_weapons) : une arme a une main (main libre), une arme a deux
## mains, une arme a une main + bouclier, deux armes a une main (une par
## main), ou une arme a distance (arc/arbalete). "Aucune" ne construit rien.
@export_group("Armes")
@export_enum("Aucune", "1 main", "2 mains", "1 main + bouclier", "Deux armes 1 main", "Distance") var weapon_loadout: String = "Aucune"
@export_enum("Epee", "Masse", "Hache") var weapon_type: String = "Epee"
@export_enum("Petit rond", "Grand carre") var shield_type: String = "Petit rond"
@export_enum("Arc", "Arbalete") var ranged_type: String = "Arc"
## "Repos" : les armes a une main sont portees a la ceinture, les boucliers/
## armes a 2 mains/armes a distance dans le dos. "Combat" : la main droite
## tient l'arme principale (a deux mains s'il y en a une, voir
## _pose_two_handed_grip), le bouclier (s'il y en a un) dans l'autre main,
## devant le nain (pas dans le dos - uniquement en Combat, le Repos reste
## dans le dos).
@export_enum("Repos", "Combat") var weapon_pose: String = "Repos"
## Sprint 28duotrigesies : remplace l'ancien selecteur de couleur libre par un
## choix de materiau (voir MATERIAL_COLORS) - determine la couleur de la
## tete/lame (weapon_color, recalcule a chaque _build_weapons, voir
## _weapon_material_color).
@export_enum("Bois", "Cuivre", "Fer", "Acier") var weapon_material: String = "Acier"
@export var weapon_handle_color: Color = Color(0.35, 0.24, 0.14)  # manche/poignee (bois)
var weapon_color: Color = Color(0.62, 0.62, 0.65)  # lame/tete d'arme (metal) - recalculee depuis weapon_material, pas exportee directement

@export_group("Animation")
## Sprint 28unvicies : preview d'animation jouee en continu (fonctionne aussi
## DANS L'EDITEUR grace a @tool + _process) - pensee pour anticiper le futur
## portage dans Dwarf.gd, qui anime deja marche/travail/repos/repas mais en
## position/echelle (limitation du sprite billboard, voir Dwarf.gd Sprint 15).
## Ce modele etant un vrai objet 3D (pas un billboard), on peut animer par
## rotation de vraies articulations (pivots), comme l'ancienne silhouette
## articulee du Sprint 14 avant le passage au sprite.
@export_enum("Aucune", "Marche", "Travail", "Combat", "Manger", "Dormir") var preview_animation: String = "Aucune"
@export_range(0.1, 3.0, 0.1) var animation_speed: float = 1.0

@export_group("Debug")
## Coche cette case (elle se decoche toute seule) pour regenerer le modele
## dans l'editeur apres avoir change une couleur/proportion ci-dessus.
@export var rebuild_in_editor: bool = false:
	set(value):
		rebuild_in_editor = false
		_rebuild()

## Coche cette case (elle se decoche toute seule) pour tirer une combinaison
## aleatoire (cheveux, barbe, largeur d'epaules, corpulence) et regenerer le
## modele avec - pour parcourir rapidement plusieurs nains differents.
@export var randomize_variation: bool = false:
	set(value):
		randomize_variation = false
		_randomize_variation()
		_rebuild()

# Sprint 28unvicies : references directes aux pivots bras/jambes (remplies a
# chaque _build_legs()/_build_arms()), utilisees par _process() pour animer
# sans avoir a rechercher les noeuds par nom a chaque frame.
var _leg_pivot_l: Node3D
var _leg_pivot_r: Node3D
var _arm_pivot_l: Node3D
var _arm_pivot_r: Node3D
var _anim_time: float = 0.0

# Sprint 28quinvicies : references directes aux noeuds "Main" (remplies dans
# _build_arms), utilisees par _build_weapons pour attacher une arme/bouclier
# directement dans une main en position "Combat".
var _hand_l: Node3D
var _hand_r: Node3D


func _ready() -> void:
	_rebuild()


## Sprint 28unvicies/28trevicies : joue la preview d'animation choisie
## (preview_animation) en continu, y compris DANS L'EDITEUR (le script est
## @tool) - pratique pour juger le mouvement sans lancer la scene. Mouvement
## simple (sinus), pense comme un premier jet a affiner, pas comme la version
## finale. "rotation.z" (inclinaison du corps entier) est explicitement remis
## a 0 dans chaque etat DEBOUT (toutes sauf "Dormir") pour ne pas rester
## couche si on change d'animation apres avoir teste "Dormir".
func _process(delta: float) -> void:
	if preview_animation == "Aucune":
		rotation.z = 0.0
		return
	if not (_leg_pivot_l and _leg_pivot_r and _arm_pivot_l and _arm_pivot_r):
		return
	_anim_time += delta * animation_speed

	match preview_animation:
		"Marche":
			rotation.z = 0.0
			_arm_pivot_l.rotation.z = 0.0
			_arm_pivot_r.rotation.z = 0.0
			var swing: float = sin(_anim_time * 6.0) * 0.5
			_leg_pivot_l.rotation.x = swing
			_leg_pivot_r.rotation.x = -swing
			_arm_pivot_l.rotation.x = -swing
			_arm_pivot_r.rotation.x = swing
		"Travail":
			rotation.z = 0.0
			_arm_pivot_l.rotation.z = 0.0
			_arm_pivot_r.rotation.z = 0.0
			var shake: float = sin(_anim_time * 10.0) * 0.15
			_arm_pivot_r.rotation.x = -0.9 + shake  # bras leve (outil), petit tremblement
			_arm_pivot_l.rotation.x = -0.1
			_leg_pivot_l.rotation.x = 0.0
			_leg_pivot_r.rotation.x = 0.0
		"Combat":
			rotation.z = 0.0
			var punch: float = sin(_anim_time * 8.0)
			_arm_pivot_r.rotation.x = -1.2 + punch * 0.6  # grand mouvement de coup
			_arm_pivot_r.rotation.z = 0.0
			if weapon_loadout == "2 mains":
				# Sprint 28duosexagesies : arme 2 mains - le bras gauche
				# suivait avant une pose fixe (0.2, immobile), donc l'arme
				# (tenue par la main droite, voir _attach_to_hand) semblait
				# brandie a une seule main pendant le coup - signale par
				# l'utilisateur (n°22). Le bras gauche suit maintenant EXACTEMENT
				# le meme mouvement que le droit (meme rotation.x), avec le
				# meme angle de rapprochement que la pose statique
				# (_pose_two_handed_grip), pour que les deux mains restent sur
				# le manche tout au long du coup.
				_arm_pivot_l.rotation.x = _arm_pivot_r.rotation.x
				_arm_pivot_l.rotation.z = deg_to_rad(55.0)
			elif weapon_loadout == "1 main + bouclier":
				# Sprint 28tresexagesies : meme probleme que la 2 mains - le
				# bras gauche retombait a la pose fixe (0.2, immobile), donc
				# le bouclier (tenu par la main gauche) restait fondu dans le
				# corps pendant l'animation Combat, la pose statique
				# _pose_shield_arm() etant ecrasee ici a chaque frame -
				# signale par l'utilisateur. On applique la MEME pose que
				# _pose_shield_arm() ici, avec une legere oscillation pour ne
				# pas rester parfaitement statique pendant le combat.
				_arm_pivot_l.rotation.x = deg_to_rad(-72.0) + punch * 0.08
				_arm_pivot_l.rotation.z = deg_to_rad(-12.0)
			else:
				_arm_pivot_l.rotation.x = 0.2
				_arm_pivot_l.rotation.z = 0.0
			_leg_pivot_l.rotation.x = 0.0
			_leg_pivot_r.rotation.x = 0.0
		"Manger":
			# Sprint 28quattervicies : la 1ere version ne levait qu'UN bras
			# vers l'avant (rotation X seule) - le bras restait sur le cote,
			# n'atteignait jamais vraiment la bouche (au centre du corps),
			# signale pas convaincant par l'utilisateur. Corrige en combinant
			# DEUX rotations par bras : X (leve vers le haut, comme avant) ET
			# Z (ramene le bras vers le centre du corps, signe oppose pour
			# gauche/droite) - les DEUX mains convergent maintenant vers la
			# bouche au sommet du mouvement, comme si le nain portait un
			# aliment a deux mains.
			rotation.z = 0.0
			var bite: float = (sin(_anim_time * 5.0) + 1.0) * 0.5  # 0..1
			var lift: float = lerp(-0.3, -2.1, bite)
			var inward: float = lerp(0.05, 0.55, bite)
			_arm_pivot_r.rotation.x = lift
			_arm_pivot_r.rotation.z = -inward
			_arm_pivot_l.rotation.x = lift
			_arm_pivot_l.rotation.z = inward
			_leg_pivot_l.rotation.x = 0.0
			_leg_pivot_r.rotation.x = 0.0
		"Dormir":
			# Contrairement au sprite de Dwarf.gd, qui ne pouvait que
			# "s'aplatir" en scale (limitation du billboard, voir Dwarf.gd
			# Sprint 15), ce modele est un vrai objet 3D : on peut litteralement
			# l'incliner a l'horizontale, comme l'ancienne silhouette
			# articulee du Sprint 14 avant le passage au sprite. Legere
			# oscillation des bras pour simuler la respiration.
			rotation.z = deg_to_rad(80.0)
			_arm_pivot_l.rotation.z = 0.0
			_arm_pivot_r.rotation.z = 0.0
			var breathe: float = sin(_anim_time * 2.0) * 0.05
			_arm_pivot_l.rotation.x = breathe
			_arm_pivot_r.rotation.x = breathe
			_leg_pivot_l.rotation.x = 0.0
			_leg_pivot_r.rotation.x = 0.0


## Tire une combinaison aleatoire de variations (cheveux, barbe + largeur,
## corpulence, tenue, couleurs cheveux/barbe) - n'appelle pas _rebuild()
## elle-meme (fait par l'appelant, voir le setter de "randomize_variation"
## ci-dessus).
func _randomize_variation() -> void:
	var hair_styles := ["Chauve", "Court", "Attache", "Iroquois", "Touffu", "Frange basse", "Longs", "Tresse"]
	var beard_styles := ["Sans barbe", "Courte", "Longue", "Tressee", "Fournie", "Bouc", "Moustache", "Fourchue"]
	var outfit_styles := ["Tunique simple", "Tunique + cape", "Armure legere", "Armure lourde"]
	hair_style = hair_styles[randi() % hair_styles.size()]
	beard_style = beard_styles[randi() % beard_styles.size()]
	outfit_style = outfit_styles[randi() % outfit_styles.size()]
	torso_shoulder_width = randf_range(0.46, 0.68)
	corpulence = randf_range(0.8, 1.3)
	beard_width = randf_range(0.75, 1.15)  # etait (0.7, 1.4) - plage resserree, combinee aux top_radius de base reduits (voir _build_beard) pour eviter le "gros triangle" encore signale
	# Sprint 28duovicies : couleurs naturelles piochees independamment pour
	## cheveux et barbe (les sourcils suivent automatiquement, voir
	## _build_eyebrows qui derive brow_color de hair_color).
	hair_color = NATURAL_HAIR_COLORS[randi() % NATURAL_HAIR_COLORS.size()]
	beard_color = NATURAL_HAIR_COLORS[randi() % NATURAL_HAIR_COLORS.size()]

	# Sprint 28quinseptuagesies : theme d'habits aleatoire (gris/noir/vert/
	# rouge/bleu/marron, voir CLOTHING_THEMES) - chemise (clothing_color) et
	# pantalon (pants_color) sont derives independamment du MEME theme, avec
	# une petite variation chacun (voir _color_variant), pour rester
	# coordonnes sans etre identiques. Demande par l'utilisateur.
	var theme: Color = CLOTHING_THEMES[randi() % CLOTHING_THEMES.size()]
	clothing_color = _color_variant(theme, 0.10)
	pants_color = _color_variant(theme, 0.10)
	coat_color = _color_variant(theme, 0.10)

	# Sprint 28sixseptuagesies : gants/manteau tires au hasard (probabilite
	# modeste, pas systematique - accessoires, pas la norme) pour que la
	# grille de verification (voir DwarfVariationGrid.gd) montre de la
	# variete sans que tous les nains en portent.
	wear_gloves = randf() < 0.4
	wear_coat = randf() < 0.35

	# Sprint 28triquatragesies : materiau d'arme aleatoire, demande par
	# l'utilisateur. Pioche uniquement parmi les 3 metaux (pas "Bois") : ca
	# garantit du meme coup que l'arc reste toujours en bois (il n'utilise
	# jamais weapon_color, voir _make_ranged_model - seulement
	# weapon_handle_color) et que l'arbalete reste toujours en metal (son
	# "Limb" utilise weapon_color, qui ne peut plus tomber sur "Bois"). "Bois"
	# reste choisissable a la main dans l'Inspecteur pour qui veut une arme de
	# corps-a-corps en bois (ex. arme d'entrainement), juste pas tire au sort.
	var weapon_materials := ["Cuivre", "Fer", "Acier"]
	weapon_material = weapon_materials[randi() % weapon_materials.size()]

	# Sprint 28quinquagesies : configuration d'armes aleatoire (avant, seul le
	# materiau l'etait) - demande par l'utilisateur pour la grille de
	# verification unifiee (voir DwarfVariationGrid.gd). Pioche independamment
	# loadout/type d'arme/bouclier/arme a distance/pose - les valeurs non
	# utilisees par le loadout tire (ex. shield_type si pas de bouclier) sont
	# tirees quand meme, sans effet (voir _build_weapons qui ignore les
	# champs non pertinents pour le loadout choisi).
	var weapon_loadouts := ["Aucune", "1 main", "2 mains", "1 main + bouclier", "Deux armes 1 main", "Distance"]
	var weapon_types := ["Epee", "Masse", "Hache"]
	var shield_types := ["Petit rond", "Grand carre"]
	var ranged_types := ["Arc", "Arbalete"]
	var weapon_poses := ["Repos", "Combat"]
	weapon_loadout = weapon_loadouts[randi() % weapon_loadouts.size()]
	weapon_type = weapon_types[randi() % weapon_types.size()]
	shield_type = shield_types[randi() % shield_types.size()]
	ranged_type = ranged_types[randi() % ranged_types.size()]
	weapon_pose = weapon_poses[randi() % weapon_poses.size()]


## Supprime l'ancien modele (s'il existe) et en reconstruit un nouveau a
## partir des valeurs actuelles des champs exportes ci-dessus.
## Sprint 28quinquies : suppression IMMEDIATE (remove_child + free) plutot
## que queue_free() - queue_free() ne detruit les noeuds qu'a la fin de la
## frame, donc les anciens et les nouveaux noeuds coexistaient brievement
## avec des noms auto-generes similaires (aucun des noeuds n'avait de nom
## explicite), ce qui perdait le panneau "Scene" de l'editeur ("Node not
## found" en boucle a chaque reconstruction). Corrige aussi en donnant un
## nom explicite et stable a chaque noeud genere (voir _build_*).
func _rebuild() -> void:
	# Sprint 34undecies : instrumentation temporaire - _build_model() est deja
	# instrumente en detail et ne montre rien de lent, alors que l'appel a
	# _rebuild() complet (mesure depuis Dwarf.gd) prend ~5-6s pour le premier
	# nain. Il ne reste que cette boucle de nettoyage des enfants precedents
	# (issus du 1er build automatique, avec les valeurs par defaut, declenche
	# par add_child avant que Dwarf.gd n'appelle explicitement _rebuild()) -
	# separee ici du reste pour confirmer si c'est bien elle.
	var _t0: int = Time.get_ticks_msec()
	var _child_count: int = get_children().size()
	for child in get_children():
		remove_child(child)
		child.free()
	var _t1: int = Time.get_ticks_msec()
	print("[Perf][DwarfModel3D] nettoyage de %d enfant(s) precedent(s) : %.3f s" % [_child_count, (_t1 - _t0) / 1000.0])
	_build_model()
	var _t2: int = Time.get_ticks_msec()
	print("[Perf][DwarfModel3D] _build_model() (nouvelle construction) : %.3f s" % [(_t2 - _t1) / 1000.0])


## Sprint 34octies (2026-07-03) : instrumentation temporaire pour localiser
## precisement la sous-etape responsable du cout de ~6s observe sur le tout
## premier DwarfModel3D construit dans une partie (voir memoire perf "lancement
## lent" - 2 tentatives de prechauffage sans effet, la cause exacte reste
## inconnue). N'affiche que les etapes prenant plus de 5ms (voir _log_step),
## pour ne pas polluer la console sur les rebuilds normaux (~quelques ms).
func _build_model() -> void:
	var head_y: float = leg_height + torso_height + head_radius * 0.85
	var _tperf := Time.get_ticks_msec()
	_build_legs()
	_tperf = _log_step("legs", _tperf)
	_build_torso()
	_tperf = _log_step("torso", _tperf)
	_build_belt()
	_tperf = _log_step("belt", _tperf)
	_build_arms(head_y)
	_tperf = _log_step("arms", _tperf)
	_build_shoulder_caps()
	_tperf = _log_step("shoulder_caps", _tperf)
	_build_head(head_y)
	_tperf = _log_step("head", _tperf)
	_build_hair(head_y)
	_tperf = _log_step("hair(%s)" % hair_style, _tperf)
	_build_beard(head_y)
	_tperf = _log_step("beard(%s)" % beard_style, _tperf)
	_build_face(head_y)
	_tperf = _log_step("face", _tperf)
	_build_outfit(head_y)
	_tperf = _log_step("outfit(%s)" % outfit_style, _tperf)
	_build_coat()
	_tperf = _log_step("coat", _tperf)
	_build_gloves()
	_tperf = _log_step("gloves", _tperf)
	_build_weapons(head_y)
	_tperf = _log_step("weapons", _tperf)


## Sprint 34octies : affiche la duree ecoulee depuis "t_prev" si superieure a
## 5ms (seuil purement pour filtrer le bruit des etapes triviales), et renvoie
## l'horodatage courant pour chainer l'appel suivant.
func _log_step(label: String, t_prev: int) -> int:
	var now: int = Time.get_ticks_msec()
	var dt: int = now - t_prev
	if dt > 5:
		print("[Perf][DwarfModel3D] %s : %.3f s" % [label, dt / 1000.0])
	return now


## Jambes courtes et epaisses (silhouette trapue de nain) + petites bottes
## sombres pour un peu de detail sans ajouter de couleur personnalisable.
## Ecartement proportionnel a la largeur de la taille (bas du torse, plutot
## qu'une valeur fixe) pour que les jambes restent bien sous le torse.
## Sprint 28quindecies : ecartement et epaisseur suivent aussi "corpulence"
## (limb_factor, version adoucie - voir _build_arms pour la meme logique).
## Sprint 28unvicies : chaque jambe est maintenant suspendue sous un PIVOT
## (Node3D vide place au niveau de la hanche), au lieu d'etre positionnee en
## absolu - meme principe que l'ancienne silhouette articulee (Sprint 14 de
## Dwarf.gd, pivots epaule/hanche) : faire tourner le pivot fait balancer
## toute la jambe naturellement, necessaire pour animer la marche (voir
## _process()). Le pivot est garde dans _leg_pivot_l/_leg_pivot_r.
func _build_legs() -> void:
	var waist_w: float = torso_waist_width * corpulence
	var leg_offset: float = waist_w * 0.29
	var limb_factor: float = 1.0 + (corpulence - 1.0) * 0.5
	for side in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"

		var pivot := Node3D.new()
		pivot.name = "LegPivot_%s" % side_name
		pivot.position = Vector3(side * leg_offset, leg_height, 0)  # niveau de la hanche
		add_child(pivot)
		pivot.owner = _edited_owner()
		if side < 0.0:
			_leg_pivot_l = pivot
		else:
			_leg_pivot_r = pivot

		var leg := MeshInstance3D.new()
		var leg_mesh := CylinderMesh.new()
		leg_mesh.top_radius = 0.09 * limb_factor
		leg_mesh.bottom_radius = 0.08 * limb_factor
		leg_mesh.height = leg_height
		leg.mesh = leg_mesh
		leg.position = Vector3(0, -leg_height * 0.5, 0)  # pend sous le pivot
		leg.name = "Leg_%s" % side_name
		leg.set_surface_override_material(0, _flat_material(pants_color))
		pivot.add_child(leg)
		leg.owner = _edited_owner()

		var boot := MeshInstance3D.new()
		var boot_mesh := BoxMesh.new()
		boot_mesh.size = Vector3(0.13, 0.08, 0.18)
		boot.mesh = boot_mesh
		boot.position = Vector3(0, -leg_height + 0.04, 0.03)
		boot.name = "Boot_%s" % side_name
		boot.set_surface_override_material(0, _flat_material(boot_color))
		pivot.add_child(boot)
		boot.owner = _edited_owner()


## Sprint 28quinquies : torse en tronc de piramide (plus large aux epaules
## qu'a la taille) au lieu d'une simple boite, pour un vrai effet "trapeze".
## Sprint 28quindecies : "corpulence" agrandit la taille/profondeur (effet
## "ventre"/costaud) SANS toucher a torso_shoulder_width (largeur d'epaules,
## deja reglable/randomisable independamment).
func _build_torso() -> void:
	var torso := MeshInstance3D.new()
	var waist_w: float = torso_waist_width * corpulence
	var depth: float = torso_depth * corpulence
	torso.mesh = _make_trapezoid_mesh(
		Vector2(torso_shoulder_width, depth),
		Vector2(waist_w, depth * 0.9),
		torso_height
	)
	torso.position = Vector3(0, leg_height + torso_height * 0.5, 0)
	torso.name = "Torso"
	torso.set_surface_override_material(0, _flat_material(clothing_color, true))
	add_child(torso)
	torso.owner = _edited_owner()


## Fine bande a la taille (bas du torse, donc largeur torso_waist_width) :
## utilise armor_color pour que les 4 couleurs personnalisables de Dwarf.gd
## (Sprint 16) restent toutes representees. Suit "corpulence" comme le torse,
## pour rester ajustee a la taille reelle du bas du torse.
func _build_belt() -> void:
	var waist_w: float = torso_waist_width * corpulence
	var depth: float = torso_depth * corpulence
	var belt := MeshInstance3D.new()
	var belt_mesh := BoxMesh.new()
	belt_mesh.size = Vector3(waist_w + 0.02, 0.06, depth + 0.02)
	belt.mesh = belt_mesh
	belt.position = Vector3(0, leg_height + 0.05, 0)
	belt.name = "Belt"
	belt.set_surface_override_material(0, _flat_material(armor_color))
	add_child(belt)
	belt.owner = _edited_owner()


## Sprint 28quinquies : bras "muscles" - plus epais qu'avant, avec un vrai
## renflement au biceps (petite sphere superposee en haut du bras) plutot
## qu'un simple cylindre fin de bout en bout.
## Sprint 28quindecies : epaisseur suit "corpulence" (limb_factor, version
## adoucie - x0.5 par rapport a corpulence brute, pour eviter des bras
## disproportionnes meme a corpulence elevee).
## Sprint 28unvicies : meme principe de pivot que les jambes (voir
## _build_legs) - pivot place au niveau de l'epaule, bras/biceps/main
## suspendus dessous, garde dans _arm_pivot_l/_arm_pivot_r pour l'animation.
func _build_arms(_head_y: float) -> void:
	var shoulder_y: float = leg_height + torso_height - 0.06
	var arm_x_offset: float = torso_shoulder_width * 0.5 + 0.04
	var limb_factor: float = 1.0 + (corpulence - 1.0) * 0.5
	for side in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"
		var arm_x: float = side * arm_x_offset

		var pivot := Node3D.new()
		pivot.name = "ArmPivot_%s" % side_name
		pivot.position = Vector3(arm_x, shoulder_y, 0)
		add_child(pivot)
		pivot.owner = _edited_owner()
		if side < 0.0:
			_arm_pivot_l = pivot
		else:
			_arm_pivot_r = pivot

		var arm := MeshInstance3D.new()
		var arm_mesh := CylinderMesh.new()
		arm_mesh.top_radius = 0.085 * limb_factor   # epaule/biceps large
		arm_mesh.bottom_radius = 0.055 * limb_factor  # avant-bras plus fin
		arm_mesh.height = arm_length
		arm.mesh = arm_mesh
		arm.position = Vector3(0, -arm_length * 0.5, 0)  # pend sous le pivot
		arm.name = "Arm_%s" % side_name
		arm.set_surface_override_material(0, _flat_material(clothing_color * 0.9))
		pivot.add_child(arm)
		arm.owner = _edited_owner()

		# Renflement du biceps : petite sphere superposee pres du haut du bras
		var bicep := MeshInstance3D.new()
		var bicep_mesh := SphereMesh.new()
		bicep_mesh.radius = 0.09 * limb_factor
		bicep_mesh.height = 0.16 * limb_factor
		bicep.mesh = bicep_mesh
		bicep.position = Vector3(0, -arm_length * 0.22, 0)
		bicep.name = "Bicep_%s" % side_name
		bicep.set_surface_override_material(0, _flat_material(clothing_color * 0.9))
		pivot.add_child(bicep)
		bicep.owner = _edited_owner()

		var hand := MeshInstance3D.new()
		var hand_mesh := SphereMesh.new()
		hand_mesh.radius = 0.06
		hand_mesh.height = 0.12
		hand.mesh = hand_mesh
		hand.position = Vector3(0, -arm_length, 0)
		hand.name = "Hand_%s" % side_name
		hand.set_surface_override_material(0, _flat_material(skin_color))
		pivot.add_child(hand)
		hand.owner = _edited_owner()
		if side < 0.0:
			_hand_l = hand
		else:
			_hand_r = hand


## Sprint 28octoseptuagesies : arrondit la jonction epaule/bras - le haut
## plat du torse trapeze (voir _build_torso) rencontrait le cylindre du bras
## en angle droit visible, signale par l'utilisateur. Une petite sphere
## (clothing_color, meme couleur que le torse) posee exactement a la position
## du pivot de bras (voir _build_arms) adoucit cette jonction.
func _build_shoulder_caps() -> void:
	var shoulder_y: float = leg_height + torso_height - 0.06
	var arm_x_offset: float = torso_shoulder_width * 0.5 + 0.04
	var limb_factor: float = 1.0 + (corpulence - 1.0) * 0.5
	for side in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"
		var cap := MeshInstance3D.new()
		var cap_mesh := SphereMesh.new()
		cap_mesh.radius = 0.10 * limb_factor
		cap_mesh.height = cap_mesh.radius * 2.0
		cap.mesh = cap_mesh
		cap.position = Vector3(side * arm_x_offset, shoulder_y, 0)
		cap.name = "ShoulderCap_%s" % side_name
		cap.set_surface_override_material(0, _flat_material(clothing_color))
		add_child(cap)
		cap.owner = _edited_owner()


## Grosse tete (proportion "nain" : tete large par rapport au corps), posee
## juste au-dessus du torse. Sprint 28quinquies : ovale plutot que ronde -
## head_height_factor etire verticalement la SphereMesh (sa largeur/profondeur
## reste head_radius, seule sa hauteur change), sans toucher aux formules de
## placement des cheveux/visage ci-dessous (toutes basees sur head_radius,
## pas sur la hauteur du mesh).
func _build_head(head_y: float) -> void:
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = head_radius
	head_mesh.height = head_radius * 2.0 * head_height_factor
	head.mesh = head_mesh
	head.position = Vector3(0, head_y, 0)
	head.name = "Head"
	head.set_surface_override_material(0, _flat_material(skin_color))
	add_child(head)
	head.owner = _edited_owner()


## Sprint 28unseptuagesies : leger jitter aleatoire de couleur (+/-8% par
## canal, clampe 0-1) - utilise pour les "meches" de cheveux (voir
## _build_hair_short) afin d'eviter un aplat de couleur parfaitement uniforme,
## sans avoir besoin d'une vraie texture d'image (incompatible avec le style
## plat/non-eclaire du jeu, voir _flat_material).
func _hair_color_variant(base: Color) -> Color:
	return _color_variant(base, 0.08)


## Sprint 28quinseptuagesies : jitter generique (facteur ajustable) - extrait
## de _hair_color_variant pour etre reutilise par les themes d'habits (voir
## _randomize_variation, "variations mineures" demandees par l'utilisateur
## entre chemise et pantalon d'un meme theme).
func _color_variant(base: Color, jitter: float) -> Color:
	return Color(
		clampf(base.r * randf_range(1.0 - jitter, 1.0 + jitter), 0.0, 1.0),
		clampf(base.g * randf_range(1.0 - jitter, 1.0 + jitter), 0.0, 1.0),
		clampf(base.b * randf_range(1.0 - jitter, 1.0 + jitter), 0.0, 1.0)
	)


## Sprint 28quindecies/28octodecies : aiguille vers l'une des formes de
## cheveux selon "hair_style" (voir @export_enum plus haut). "Chauve" ne
## construit rien.
func _build_hair(head_y: float) -> void:
	# Sprint 28sexvicies : "bug de couleur de cheveux" signale par l'utilisateur
	# (frange grise visible alors que les cheveux sont noirs/blonds) - en fait
	# pas un bug de couleur : le casque (Armure lourde, gris par defaut, voir
	# _build_helmet) et des cheveux plus grands que lui (ex. "Touffu", qui
	# depasse largement le rayon du casque) se chevauchent, laissant le casque
	# visible en avant du crane pendant que les cheveux colores debordent
	# autour/derriere - lu a tort comme "une frange grise". Corrige logiquement :
	# un casque complet cache les cheveux dessous, donc on ne les construit pas.
	if outfit_style == "Armure lourde":
		return
	match hair_style:
		"Chauve":
			return
		"Attache":
			_build_hair_short(head_y)
			_build_hair_ponytail(head_y)
		"Iroquois":
			_build_hair_mohawk(head_y)
		"Touffu":
			_build_hair_bushy(head_y)
		"Frange basse":
			_build_hair_low_fringe(head_y)
		"Longs":
			_build_hair_short(head_y)
			_build_hair_long(head_y)
		"Tresse":
			_build_hair_short(head_y)
			_build_hair_braid(head_y)
		_:  # "Court" (defaut)
			_build_hair_short(head_y)


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
func _build_hair_short(head_y: float) -> void:
	var hair := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	var hair_radius: float = head_radius * hair_size
	hair_mesh.radius = hair_radius
	hair_mesh.height = hair_radius * 2.0  # sphere pleine, pas aplatie
	hair.mesh = hair_mesh
	var base_pos := Vector3(
		0,
		head_y + head_radius * hair_lift,
		-head_radius * hair_back_offset
	)
	hair.position = base_pos
	hair.name = "Hair"
	hair.set_surface_override_material(0, _flat_material(hair_color))
	add_child(hair)
	hair.owner = _edited_owner()

	# Sprint 28unseptuagesies : silhouette jugee "trop circulaire", demande
	# de texture/variation - une vraie texture d'image serait incoherente
	# avec le style plat/non-eclaire du jeu (voir _flat_material), donc
	# option la plus simple retenue : quelques petites "meches" (spheres)
	# superposees sur la sphere principale, legerement decalees et teintees
	# (voir _hair_color_variant) - casse la silhouette parfaitement ronde et
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
			tuft.set_surface_override_material(0, _flat_material(_hair_color_variant(hair_color)))
			add_child(tuft)
			tuft.owner = _edited_owner()
			tuft_index += 1


## Sprint 28septdecies : "Touffu" recouvrait tout le visage - le recul precedent
## (hair_back_offset * 0.6, donc REDUIT par rapport aux cheveux courts) etait
## pense pour une sphere a peine plus grande, pas pour une sphere 1.35x plus
## grosse : son avant (centre + rayon) depassait tres largement devant les
## yeux/le nez (jusqu'a ~1.33x head_radius, alors que le nez est a ~0.95x).
## Corrige en calculant le recul a partir d'une limite avant explicite
## (front_target, nettement derriere les yeux a 0.90x head_radius) plutot que
## de partir d'un facteur de recul pense pour une sphere plus petite.
func _build_hair_bushy(head_y: float) -> void:
	var hair := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	# Sprint 28septuagesies : "boule" de cheveux "Touffu" jugee trop grosse
	# (1.35x le rayon de la tete, tres proeminente) - reduite a 1.15x. Le
	# calcul de front_target ci-dessous reste inchange et continue de garantir
	# que la sphere (quelle que soit sa taille) ne deborde jamais sur le
	# visage (voir Sprint 28septdecies).
	var hair_radius: float = head_radius * hair_size * 1.15
	hair_mesh.radius = hair_radius
	hair_mesh.height = hair_radius * 2.0
	hair.mesh = hair_mesh
	var front_target: float = head_radius * 0.62  # limite avant voulue, nettement derriere les yeux (0.90x) et le nez (0.95x)
	var offset_z: float = front_target - hair_radius  # recul necessaire pour que centre+rayon = front_target
	hair.position = Vector3(
		0,
		head_y + head_radius * (hair_lift + 0.05),
		offset_z
	)
	hair.name = "Hair"
	hair.set_surface_override_material(0, _flat_material(hair_color))
	add_child(hair)
	hair.owner = _edited_owner()


## Sprint 28vicies : correction complete de "Frange basse" - la 1ere version
## (Sprint 28octodecies) ajoutait un 2e morceau de cheveux (une sphere aplatie
## separee, collee au-dessus des sourcils) EN PLUS du casque court existant,
## ce qui laissait un anneau de peau visible entre les deux (bug signale par
## l'utilisateur sur le modele "7" de la grille) - et ce n'etait de toute
## facon pas ce qui etait demande : il fallait avancer/abaisser la ligne de
## cheveux EXISTANTE, pas en ajouter une nouvelle. Corrige en repensant la
## coupe courte comme UNE SEULE sphere (comme _build_hair_short), mais avec
## son centre remonte (dy=0.46 au lieu de hair_lift=0.15, donc le "ventre" le
## plus large de la sphere se retrouve au niveau du front/des sourcils au lieu
## du niveau des yeux) et moins reculee vers l'arriere (0.16 au lieu de 0.22) -
## la sphere avance donc plus loin PRECISEMENT devant le front, tout en
## restant en retrait au niveau des yeux/du nez (plus bas, donc plus loin de
## l'equateur de la sphere, qui recule naturellement a mesure qu'on s'eloigne
## du centre).
func _build_hair_low_fringe(head_y: float) -> void:
	var hair := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	var hair_radius: float = head_radius * hair_size * 1.02  # a peine plus grande que "Court"
	hair_mesh.radius = hair_radius
	hair_mesh.height = hair_radius * 2.0
	hair.mesh = hair_mesh
	var dy: float = head_radius * 0.46
	var z_offset: float = -head_radius * 0.16
	hair.position = Vector3(0, head_y + dy, z_offset)
	hair.name = "Hair"
	hair.set_surface_override_material(0, _flat_material(hair_color))
	add_child(hair)
	hair.owner = _edited_owner()


## Sprint 28novodecies : cheveux "Longs" - en plus de la base courte, une masse
## de cheveux (cylindre effile) qui descend le long de l'arriere du crane
## jusqu'a la nuque/le haut des epaules (contrairement a "Attache", pas de
## veritable queue fine qui se detache : c'est une masse continue, large,
## posee contre l'arriere de la tete).
func _build_hair_long(head_y: float) -> void:
	var shoulder_y: float = leg_height + torso_height - 0.06
	var top_y: float = head_y + head_radius * 0.3
	var bottom_y: float = shoulder_y + 0.05
	var mane := MeshInstance3D.new()
	var mane_mesh := CylinderMesh.new()
	mane_mesh.top_radius = head_radius * 0.55
	mane_mesh.bottom_radius = head_radius * 0.35
	mane_mesh.height = top_y - bottom_y
	mane.mesh = mane_mesh
	mane.position = Vector3(0, (top_y + bottom_y) * 0.5, -head_radius * (hair_back_offset + 0.55))
	mane.name = "HairLong"
	mane.set_surface_override_material(0, _flat_material(hair_color))
	add_child(mane)
	mane.owner = _edited_owner()


## Sprint 28novodecies : cheveux "Tresse" - en plus de la base courte, une
## petite "attache" (sphere) a la base du crane puis une longue tresse fine
## (cylindre effile) qui descend loin dans le dos, terminee par une petite
## perle (meme principe que la barbe "Tressee", voir _build_beard_braid_tip).
func _build_hair_braid(head_y: float) -> void:
	var attach_y: float = head_y - head_radius * 0.15
	var braid_length: float = head_radius * 2.6
	var z_offset: float = -head_radius * (hair_back_offset + 0.5)

	var tie := MeshInstance3D.new()
	var tie_mesh := SphereMesh.new()
	tie_mesh.radius = head_radius * 0.11
	tie_mesh.height = tie_mesh.radius * 2.0
	tie.mesh = tie_mesh
	tie.position = Vector3(0, attach_y, z_offset)
	tie.name = "HairBraidTie"
	tie.set_surface_override_material(0, _flat_material(hair_color))
	add_child(tie)
	tie.owner = _edited_owner()

	var braid := MeshInstance3D.new()
	var braid_mesh := CylinderMesh.new()
	braid_mesh.top_radius = head_radius * 0.13
	braid_mesh.bottom_radius = head_radius * 0.07
	braid_mesh.height = braid_length
	braid.mesh = braid_mesh
	braid.position = Vector3(0, attach_y - braid_length * 0.5, z_offset)
	braid.name = "HairBraid"
	braid.set_surface_override_material(0, _flat_material(hair_color))
	add_child(braid)
	braid.owner = _edited_owner()

	var end_bead := MeshInstance3D.new()
	var end_mesh := SphereMesh.new()
	end_mesh.radius = head_radius * 0.09
	end_mesh.height = end_mesh.radius * 2.0
	end_bead.mesh = end_mesh
	end_bead.position = Vector3(0, attach_y - braid_length, z_offset)
	end_bead.name = "HairBraidEnd"
	end_bead.set_surface_override_material(0, _flat_material(hair_color * 0.85))
	add_child(end_bead)
	end_bead.owner = _edited_owner()


## Sprint 28quindecies : cheveux "Attache" - la base courte (_build_hair_short)
## plus une "queue" attachee : cylindre effile partant de l'arriere du crane
## et retombant en biais vers le bas/l'arriere.
func _build_hair_ponytail(head_y: float) -> void:
	var tail := MeshInstance3D.new()
	var tail_mesh := CylinderMesh.new()
	tail_mesh.top_radius = head_radius * 0.12
	tail_mesh.bottom_radius = head_radius * 0.05
	tail_mesh.height = head_radius * 1.1
	tail.mesh = tail_mesh
	tail.position = Vector3(0, head_y - head_radius * 0.25, -head_radius * (hair_back_offset + 0.55))
	tail.rotation.x = deg_to_rad(75)  # incline vers l'arriere-bas
	tail.name = "HairTail"
	tail.set_surface_override_material(0, _flat_material(hair_color))
	add_child(tail)
	tail.owner = _edited_owner()


## Sprint 28quindecies : cheveux "Iroquois" - simple crete fine (boite) posee
## sur le sommet de la tete, centree sur l'axe avant-arriere.
func _build_hair_mohawk(head_y: float) -> void:
	var mohawk := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(head_radius * 0.18, head_radius * 0.55, head_radius * 1.3)
	mohawk.mesh = mesh
	var head_top: float = head_y + head_radius * head_height_factor
	mohawk.position = Vector3(0, head_top + head_radius * 0.12, 0)
	mohawk.name = "Hair"
	mohawk.set_surface_override_material(0, _flat_material(hair_color))
	add_child(mohawk)
	mohawk.owner = _edited_owner()


## Sprint 28quindecies/28unvicies : aiguille vers l'une des formes de barbe
## selon "beard_style" (voir @export_enum plus haut). "Sans barbe" ne
## construit rien. Plupart reutilisent _build_beard_shape (meme cone que
## l'original, juste parametrise en largeur/longueur/position) ; "Tressee"
## ajoute une petite "perle" au bout ; "Moustache"/"Fourchue" ont leur propre
## forme (pas un simple cone).
func _build_beard(head_y: float) -> void:
	match beard_style:
		"Sans barbe":
			return
		"Longue":
			_build_beard_shape(head_y, head_radius * 0.38, 0.60, -head_radius * 0.62)
		"Tressee":
			_build_beard_shape(head_y, head_radius * 0.32, 0.62, -head_radius * 0.65)
			_build_beard_braid_tip(head_y)
		"Fournie":
			# Sprint 28duoseptuagesies : etait 0.72 - base deja tres large
			# avant meme beard_width, principale cause du "gros triangle"
			# encore visible malgre le premier plafonnement (n°19, toujours
			# signale). Reduite a 0.48 et hauteur augmentee (0.32->0.42) pour
			# un cone plus effile, moins large/plat.
			_build_beard_shape(head_y, head_radius * 0.48, 0.42, -head_radius * 0.55)
		"Bouc":
			_build_beard_shape(head_y, head_radius * 0.24, 0.20, -head_radius * 0.60)
		"Moustache":
			_build_beard_moustache(head_y)
		"Fourchue":
			_build_beard_forked(head_y)
		_:  # "Courte" (defaut)
			# Sprint 28duoseptuagesies : etait 0.55 - trop large pour une
			# barbe "courte", contribuait aussi au bug signale. Reduite a
			# 0.40.
			_build_beard_shape(head_y, head_radius * 0.40, 0.30, -head_radius * 0.55)


## Forme conique sous le menton : trait caracteristique du nain. Parametree
## (top_radius/height/dy) pour etre reutilisee par les differents styles de
## barbe (voir _build_beard) - avec les valeurs d'origine, "Courte" reproduit
## exactement la forme du Sprint 28bis.
func _build_beard_shape(head_y: float, top_radius: float, height: float, dy: float) -> void:
	var beard := MeshInstance3D.new()
	var beard_mesh := CylinderMesh.new()
	# Sprint 28neufsexagesies/28duoseptuagesies : "beard_width" (tire au
	# hasard, voir _randomize_variation) multipliait un top_radius deja large
	# pour certains styles sans limite suffisante - un 1er plafond a 0.85x
	# head_radius restait encore trop genereux (bug encore visible, n°19,
	# signale a nouveau). Resserre a 0.58x, combine a des top_radius de base
	# reduits (voir _build_beard) et une plage beard_width plus etroite (voir
	# _randomize_variation).
	beard_mesh.top_radius = min(top_radius * beard_width, head_radius * 0.58)
	beard_mesh.bottom_radius = 0.02
	beard_mesh.height = height
	beard.mesh = beard_mesh
	beard.position = Vector3(0, head_y + dy, head_radius * 0.55)
	beard.rotation.x = deg_to_rad(-20)
	beard.name = "Beard"
	beard.set_surface_override_material(0, _flat_material(beard_color))
	add_child(beard)
	beard.owner = _edited_owner()


## Sprint 28quindecies : petite "perle" au bout de la barbe "Tressee" -
## position approximative (pas suivie point par point le long du cone
## incline), a ajuster a l'oeil si besoin une fois vu dans Godot.
func _build_beard_braid_tip(head_y: float) -> void:
	var tip := MeshInstance3D.new()
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = head_radius * 0.10
	tip_mesh.height = tip_mesh.radius * 2.0
	tip.mesh = tip_mesh
	tip.position = Vector3(0, head_y - head_radius * 1.05, head_radius * 0.75)
	tip.name = "BeardTip"
	tip.set_surface_override_material(0, _flat_material(beard_color * 0.8))
	add_child(tip)
	tip.owner = _edited_owner()


## Sprint 28unvicies : "Moustache" - pas de barbe au menton, juste une fine
## moustache sous le nez (au-dessus de la bouche, qui est placee a dy=-0.31 -
## voir _build_mouth).
func _build_beard_moustache(head_y: float) -> void:
	# Sprint 28septseptuagesies : refonte en "fer a cheval" (horseshoe) -
	# l'utilisateur n'aimait pas la simple barre horizontale d'origine.
	# Desormais : la meme barre au-dessus de la levre, PLUS deux meches qui
	# tombent de chaque cote de la bouche jusque vers le bas du menton (meme
	# technique de cone effile que _build_beard_forked).
	var dy: float = -head_radius * 0.22
	var z: float = _head_surface_radius(dy) * 1.05
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
	stache.set_surface_override_material(0, _flat_material(beard_color))
	add_child(stache)
	stache.owner = _edited_owner()

	for side in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"
		var strand_dy: float = dy - head_radius * 0.19
		var strand_z: float = _head_surface_radius(strand_dy) * 1.05
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
		strand.set_surface_override_material(0, _flat_material(beard_color))
		add_child(strand)
		strand.owner = _edited_owner()


## Sprint 28unvicies : "Fourchue" - deux meches distinctes qui divergent
## depuis le menton (au lieu d'un cone unique centre), chacune terminee par
## une petite perle (meme principe que _build_beard_braid_tip).
func _build_beard_forked(head_y: float) -> void:
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
		strand.set_surface_override_material(0, _flat_material(beard_color))
		add_child(strand)
		strand.owner = _edited_owner()

		var tip := MeshInstance3D.new()
		var tip_mesh := SphereMesh.new()
		tip_mesh.radius = head_radius * 0.07
		tip_mesh.height = tip_mesh.radius * 2.0
		tip.mesh = tip_mesh
		tip.position = Vector3(side * head_radius * 0.28 * beard_width, head_y - head_radius * 1.0, head_radius * 0.62)
		tip.name = "BeardTip_%s" % side_name
		tip.set_surface_override_material(0, _flat_material(beard_color * 0.85))
		add_child(tip)
		tip.owner = _edited_owner()


## Yeux, nez et bouche sur l'avant de la tete (+Z, meme cote que la barbe).
## La bouche est volontairement basse - une bonne partie disparait derriere
## la barbe, comme sur un vrai nain barbu.
func _build_face(head_y: float) -> void:
	for side in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"
		var eye_x: float = side * head_radius * 0.38
		var eye_y: float = head_y + head_radius * 0.12
		var eye_z: float = head_radius * 0.90

		# Sprint 28terdecies : la rotation Y tentee au sprint precedent (pour
		# suivre la courbure de la tete) a en fait CAUSE le strabisme divergent
		# (elle a fait deriver la pupille vers la tempe, via out_dir qui a une
		# composante X). Retour a une version simple sans rotation : le blanc
		# et la pupille partagent exactement le meme eye_x/eye_y (aucun autre
		# decalage lateral), donc centree par construction ; seul un leger
		# decalage vers l'avant en Z (pas de composante X) fait ressortir la
		# pupille devant le blanc aplati.
		var eye_white := MeshInstance3D.new()
		var eye_white_mesh := SphereMesh.new()
		eye_white_mesh.radius = head_radius * 0.12
		eye_white_mesh.height = eye_white_mesh.radius * 2.0
		eye_white.mesh = eye_white_mesh
		eye_white.position = Vector3(eye_x, eye_y, eye_z)
		eye_white.scale = Vector3(1.35, 0.85, 0.55)
		eye_white.name = "EyeWhite_%s" % side_name
		eye_white.set_surface_override_material(0, _flat_material(EYE_WHITE_COLOR))
		add_child(eye_white)
		eye_white.owner = _edited_owner()

		# Pupille : plus petite et foncee, meme eye_x/eye_y que le blanc (donc
		# centree), juste plus en avant en Z pour ressortir devant.
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = head_radius * 0.07
		eye_mesh.height = eye_mesh.radius * 2.0
		eye.mesh = eye_mesh
		eye.position = Vector3(eye_x, eye_y, eye_z + head_radius * 0.05)
		eye.scale = Vector3(1.35, 0.85, 1.0)
		eye.name = "Eye_%s" % side_name
		eye.set_surface_override_material(0, _flat_material(EYE_COLOR))
		add_child(eye)
		eye.owner = _edited_owner()

	var nose := MeshInstance3D.new()
	var nose_mesh := SphereMesh.new()
	nose_mesh.radius = head_radius * 0.16
	nose_mesh.height = nose_mesh.radius * 2.0
	nose.mesh = nose_mesh
	nose.position = Vector3(0, head_y - head_radius * 0.02, head_radius * 0.95)
	nose.name = "Nose"
	nose.set_surface_override_material(0, _flat_material(skin_color * 0.95))
	add_child(nose)
	nose.owner = _edited_owner()

	_build_mouth(head_y)
	_build_eyebrows(head_y)


## Sprint 28octies : bouche corrigee une 2e fois -
## (1) vraie courbe : au lieu de perles isolees (qui lisaient comme des
## points, pas une ligne), on relie une serie de points le long de l'arc par
## de petits segments (boites fines tournees pour suivre la tangente locale,
## bout a bout) - ca se lit vraiment comme un trait courbe continu ;
## (2) plus enfoncee dans le visage : le calcul precedent (z = 0.93 *
## head_radius) supposait une tete parfaitement spherique, or elle est
## desormais ovale (head_height_factor) - a la hauteur de la bouche, la
## vraie surface de l'ovale est plus proche de 0.98x head_radius, pas 0.93x.
## _head_surface_radius() calcule la bonne valeur pour n'importe quelle
## hauteur/head_height_factor, au lieu de deviner un facteur fixe.
func _build_mouth(head_y: float) -> void:
	var mouth_color := skin_color * 0.75
	var half_width: float = head_radius * 0.22
	var curve_height: float = head_radius * 0.06  # amplitude de la courbe (leger sourire)
	var dy: float = -head_radius * 0.31  # decalage vertical par rapport au centre de la tete (un peu plus bas que le nez)
	var base_y: float = head_y + dy
	var z: float = _head_surface_radius(dy) * 1.05  # legerement proeminent, pas enfonce

	var pts: Array = []
	var points := 9
	for i in range(points):
		var t: float = float(i) / float(points - 1)
		var x: float = lerp(-half_width, half_width, t)
		var arc: float = 1.0 - pow(2.0 * t - 1.0, 2.0)  # 0 aux extremites, 1 au centre
		var y: float = base_y + arc * curve_height
		pts.append(Vector3(x, y, z))

	_build_curve_segments(pts, head_radius * 0.035, mouth_color, "Mouth")


## Sprint 28quattuordecies : sourcils, un par oeil, meme technique de courbe
## que la bouche (voir _build_curve_segments) - une petite arche au-dessus de
## chaque oeil (eye_y = head_y + 0.12*head_radius, donc les sourcils sont
## places un peu au-dessus a 0.28). Couleur des cheveux (assortis), un peu
## fonces pour rester lisibles sur la peau.
func _build_eyebrows(head_y: float) -> void:
	var brow_color := hair_color * 0.85
	var half_width: float = head_radius * 0.17
	var curve_height: float = head_radius * 0.05
	var dy: float = head_radius * 0.28  # au-dessus des yeux (eye_y = head_y + 0.12*head_radius)
	var base_y: float = head_y + dy
	var z: float = _head_surface_radius(dy) * 1.05

	for side in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"
		var center_x: float = side * head_radius * 0.38  # meme ecart que les yeux

		var pts: Array = []
		var points := 5
		for i in range(points):
			var t: float = float(i) / float(points - 1)
			var x: float = center_x + lerp(-half_width, half_width, t)
			var arc: float = 1.0 - pow(2.0 * t - 1.0, 2.0)
			var y: float = base_y + arc * curve_height
			pts.append(Vector3(x, y, z))

		_build_curve_segments(pts, head_radius * 0.03, brow_color, "Eyebrow_%s" % side_name)


## Sprint 28quattuordecies : trace une courbe continue a travers une liste de
## points en reliant chaque paire consecutive par un petit segment (boite
## fine tournee pour suivre la tangente locale, bout a bout, avec un leger
## chevauchement pour eviter les trous). Extrait de l'ancienne _build_mouth
## pour etre reutilise par les sourcils (meme principe visuel).
func _build_curve_segments(pts: Array, thickness: float, color: Color, name_prefix: String) -> void:
	for i in range(pts.size() - 1):
		var p_a: Vector3 = pts[i]
		var p_b: Vector3 = pts[i + 1]
		var mid: Vector3 = (p_a + p_b) * 0.5
		var seg_length: float = p_a.distance_to(p_b) * 1.2  # leger chevauchement, evite les trous
		var angle: float = atan2(p_b.y - p_a.y, p_b.x - p_a.x)

		var seg := MeshInstance3D.new()
		var seg_mesh := BoxMesh.new()
		seg_mesh.size = Vector3(seg_length, thickness, thickness)
		seg.mesh = seg_mesh
		seg.position = mid
		seg.rotation.z = angle
		seg.name = "%s_%d" % [name_prefix, i]
		seg.set_surface_override_material(0, _flat_material(color))
		add_child(seg)
		seg.owner = _edited_owner()


## Sprint 28unvicies : aiguille vers les pieces a ajouter par-dessus le corps
## selon "outfit_style" (voir @export_enum plus haut). "Tunique simple" ne
## rajoute rien (le torse deja construit, voir _build_torso, fait deja office
## de tunique de base dans tous les cas).
func _build_outfit(head_y: float) -> void:
	match outfit_style:
		"Tunique + cape":
			_build_cape()
		"Armure legere":
			_build_chestplate()
		"Armure lourde":
			_build_chestplate()
			_build_shoulder_pads()
			_build_helmet(head_y)
		_:  # "Tunique simple" (defaut)
			pass


## Sprint 28sixseptuagesies : manteau - accessoire independant de
## outfit_style (voir wear_coat, groupe "Accessoires"), peut se porter
## par-dessus n'importe quelle tenue. Reutilise _make_trapezoid_mesh (comme
## le torse/la cape/le plastron) mais legerement plus large que le torse
## (pour bien le recouvrir) et surtout plus LONG, descendant sous la taille
## jusqu'aux cuisses.
func _build_coat() -> void:
	if not wear_coat:
		return
	var waist_w: float = torso_waist_width * corpulence
	var depth: float = torso_depth * corpulence
	var coat_height: float = torso_height + 0.22
	var torso_top_y: float = leg_height + torso_height
	var top_size := Vector2(torso_shoulder_width * 1.08, depth * 1.2)
	var bottom_size := Vector2(waist_w * 1.35, depth * 1.2)
	var coat_center_y: float = torso_top_y - coat_height * 0.5

	var coat := MeshInstance3D.new()
	coat.mesh = _make_trapezoid_mesh(top_size, bottom_size, coat_height)
	coat.position = Vector3(0, coat_center_y, 0)
	coat.name = "Coat"
	coat.set_surface_override_material(0, _flat_material(coat_color, true))
	add_child(coat)
	coat.owner = _edited_owner()

	# Sprint 28octoseptuagesies : "juste une grosse boite" signale par
	# l'utilisateur - une petite sphere a chaque coin superieur (epaule) pour
	# arrondir l'angle vif entre le haut plat du manteau et le bras.
	for side in [-1.0, 1.0]:
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
		cap.set_surface_override_material(0, _flat_material(coat_color))
		add_child(cap)
		cap.owner = _edited_owner()

	# Sprint 28octoseptuagesies : rangee de boutons devant, demande par
	# l'utilisateur pour casser l'aspect "grosse boite plate".
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
		button.set_surface_override_material(0, _flat_material(Color(0.14, 0.12, 0.10)))
		add_child(button)
		button.owner = _edited_owner()


## Sprint 28sixseptuagesies : gants - accessoire independant de outfit_style
## (voir wear_gloves, groupe "Accessoires"). Une petite sphere legerement
## plus grosse que la main (voir _build_arms), attachee directement en enfant
## du noeud Main (_hand_l/_hand_r) pour suivre automatiquement bras/pivot -
## meme reference que _attach_to_hand pour les armes. Couleur cuir
## (boot_color, meme logique que les bottes) plutot qu'une nouvelle couleur
## dediee.
func _build_gloves() -> void:
	if not wear_gloves:
		return
	for hand in [_hand_l, _hand_r]:
		if not hand:
			continue
		var glove := MeshInstance3D.new()
		var glove_mesh := SphereMesh.new()
		glove_mesh.radius = 0.075
		glove_mesh.height = glove_mesh.radius * 2.0
		glove.mesh = glove_mesh
		glove.name = "Glove_%s" % hand.name
		glove.set_surface_override_material(0, _flat_material(boot_color))
		hand.add_child(glove)
		glove.owner = _edited_owner()


## Sprint 28unvicies : cape plate accrochee aux epaules, tombant le long du
## dos (armor_color, comme la ceinture - voir _build_belt - pour rester
## coherent avec les 4 couleurs personnalisables existantes).
func _build_cape() -> void:
	var shoulder_y: float = leg_height + torso_height - 0.04
	var depth: float = torso_depth * corpulence
	var cape_height: float = torso_height * 0.9
	var cape := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(torso_shoulder_width * 0.85, cape_height, 0.03)
	cape.mesh = mesh
	cape.position = Vector3(0, shoulder_y - cape_height * 0.5, -depth * 0.5 - 0.02)
	cape.name = "Cape"
	cape.set_surface_override_material(0, _flat_material(armor_color, true))
	add_child(cape)
	cape.owner = _edited_owner()


## Sprint 28unvicies : plastron - reutilise _make_trapezoid_mesh (meme forme
## que le torse, voir _build_torso) en plus petit/plus plat, plaque devant le
## torse existant (armor_color) plutot que de remplacer le torse.
func _build_chestplate() -> void:
	var depth: float = torso_depth * corpulence
	var plate := MeshInstance3D.new()
	plate.mesh = _make_trapezoid_mesh(
		Vector2(torso_shoulder_width * 1.04, depth * 0.5),
		Vector2(torso_waist_width * corpulence * 1.02, depth * 0.5),
		torso_height * 0.65
	)
	plate.position = Vector3(0, leg_height + torso_height * 0.72, depth * 0.28)
	plate.name = "Chestplate"
	plate.set_surface_override_material(0, _flat_material(armor_color, true))
	add_child(plate)
	plate.owner = _edited_owner()


## Sprint 28unvicies : petites epaulieres (une boite par epaule, armor_color),
## a la meme position X que le pivot du bras (voir _build_arms) pour rester
## bien alignees quelle que soit la largeur d'epaules.
func _build_shoulder_pads() -> void:
	var shoulder_y: float = leg_height + torso_height - 0.04
	var arm_x_offset: float = torso_shoulder_width * 0.5 + 0.04
	for side in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"
		var pad := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.16, 0.08, 0.18)
		pad.mesh = mesh
		pad.position = Vector3(side * arm_x_offset, shoulder_y + 0.04, 0)
		pad.name = "ShoulderPad_%s" % side_name
		pad.set_surface_override_material(0, _flat_material(armor_color))
		add_child(pad)
		pad.owner = _edited_owner()


## Sprint 28unvicies : casque - sphere aplatie (armor_color) couvrant la tete,
## posee par-dessus les cheveux/la coiffe choisie (peut legerement chevaucher
## la coiffe, acceptable pour un prototype - a affiner si ca choque une fois
## vu dans Godot, par exemple en masquant les cheveux quand un casque est
## porte).
func _build_helmet(head_y: float) -> void:
	# Dome principal : couvre le dessus/l'avant du crane. Reprend les memes
	# proportions "surete" que les cheveux courts (_build_hair_short : rayon
	# ~1.08-1.15x head_radius, recul ~0.20-0.22x) plutot que le centre remonte
	# + sphere aplatie d'avant, qui laissait le bas-arriere du crane decouvert
	# (une sphere aplatie et decentree vers le haut retrecit tres vite en Y
	# des qu'on s'eloigne de son pole, donc son bord a l'arriere ne
	# descendait pas assez bas pour couvrir jusqu'a la nuque).
	var dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	var dome_radius: float = head_radius * 1.15
	dome_mesh.radius = dome_radius
	dome_mesh.height = dome_radius * 2.0
	dome.mesh = dome_mesh
	dome.position = Vector3(0, head_y + head_radius * 0.15, -head_radius * 0.20)
	dome.name = "Helmet"
	dome.set_surface_override_material(0, _flat_material(armor_color))
	add_child(dome)
	dome.owner = _edited_owner()

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
	guard.set_surface_override_material(0, _flat_material(armor_color))
	add_child(guard)
	guard.owner = _edited_owner()


## Sprint 28quinvicies : aiguille vers la construction d'armes/bouclier selon
## "weapon_loadout" (voir @export_enum "Armes" en haut du fichier), puis les
## place selon _effective_weapon_pose() : "Repos" -> _attach_to_belt (armes a
## une main) ou _attach_to_back (armes a 2 mains/boucliers/armes a distance) ;
## "Combat" -> _attach_to_hand (main droite = arme principale, main gauche =
## bouclier si applicable, regle explicite demandee par l'utilisateur).
## "Aucune" ne construit rien.
func _build_weapons(head_y: float) -> void:
	weapon_color = _weapon_material_color(weapon_material)
	var pose: String = _effective_weapon_pose()
	match weapon_loadout:
		"Aucune":
			return
		"1 main":
			var w := _make_weapon_model(weapon_type, false)
			if pose == "Combat":
				_attach_to_hand(w, _hand_r, false)
			else:
				_attach_to_belt(w, 1.0)
		"2 mains":
			var w := _make_weapon_model(weapon_type, true)
			if pose == "Combat":
				_attach_to_hand(w, _hand_r, false)
				_pose_two_handed_grip()
			else:
				_attach_to_back(w, head_y)
		"1 main + bouclier":
			var w := _make_weapon_model(weapon_type, false)
			var s := _make_shield_model(shield_type)
			if pose == "Combat":
				_attach_to_hand(w, _hand_r, false)
				_attach_to_hand(s, _hand_l, true)
				_pose_shield_arm()
			else:
				_attach_to_belt(w, 1.0)
				_attach_to_back(s, head_y)
		"Deux armes 1 main":
			var w1 := _make_weapon_model(weapon_type, false)
			var w2 := _make_weapon_model(weapon_type, false)
			if pose == "Combat":
				_attach_to_hand(w1, _hand_r, false)
				_attach_to_hand(w2, _hand_l, false)
			else:
				_attach_to_belt(w1, 1.0)
				_attach_to_belt(w2, -1.0)
		"Distance":
			var r := _make_ranged_model(ranged_type)
			if pose == "Combat":
				_attach_to_hand(r, _hand_r, false)
			else:
				_attach_to_back(r, head_y)


## Sprint 28unsexagesies : pose "effective" utilisee pour placer les armes -
## avant, seule "weapon_pose" (choix manuel/randomise) decidait, ce qui
## faisait apparaitre des armes brandies en pleine main pendant des
## animations non martiales (signale par l'utilisateur : n°23 "utilise ses
## armes" pendant l'animation Manger). Desormais, l'animation en cours a le
## dernier mot : "Combat" force les armes en main ; toute autre animation en
## mouvement (Marche/Travail/Manger/Dormir) force le rangement (ceinture/dos),
## meme si weapon_pose = "Combat" ; "Aucune" (apercu statique, utilise entre
## autres par la grille de demonstration figee) respecte le choix manuel de
## weapon_pose tel quel.
func _effective_weapon_pose() -> String:
	match preview_animation:
		"Combat":
			return "Combat"
		"Aucune":
			return weapon_pose
		_:  # Marche, Travail, Manger, Dormir
			return "Repos"


## Sprint 28quinvicies : construit le modele d'une arme (Epee/Masse/Hache),
## origine au niveau de la poignee (bas du manche), qui pointe vers +Y (le
## haut) au repos "neutre" du groupe - facilite le repositionnement/la
## rotation lors de l'attache (ceinture/dos/main, voir _attach_to_*).
## "two_handed" agrandit l'ensemble (manche plus long, tete/lame plus grosse)
## pour la version a deux mains.
## Sprint 28septvicies : 2 corrections suite au retour utilisateur -
## (1) armes agrandies (notamment la masse, jugee trop petite) ;
## (2) le "grip" (origine du groupe, point attache a la main en Combat - voir
## _attach_to_hand) est maintenant au MILIEU de la poignee au lieu de tout en
## bas. Avant, l'origine correspondait au bout de la poignee : une fois
## attachee a la main (une simple sphere), la poignee semblait "collee sur"
## la main plutot que tenue dedans. Centree, la moitie de la poignee se
## retrouve naturellement a l'interieur de la sphere de la main (cote pommeau)
## et l'autre moitie ressort vers la lame - beaucoup plus lisible comme "tenue
## en main". Tous les decalages de tete/lame/garde ci-dessous sont donc
## exprimes par rapport a "handle_length * 0.5" (le haut de la poignee) au
## lieu de "handle_length".


## Sprint 28duotrigesies : convertit le materiau choisi (weapon_material) en
## couleur concrete (voir MATERIAL_COLORS) - appelee au debut de
## _build_weapons pour recalculer weapon_color a chaque reconstruction (le
## champ n'est plus directement exportable/editable, voir sa declaration plus
## haut).
func _weapon_material_color(material: String) -> Color:
	if MATERIAL_COLORS.has(material):
		return MATERIAL_COLORS[material]
	return MATERIAL_COLORS["Acier"]


func _make_weapon_model(kind: String, two_handed: bool) -> Node3D:
	var group := Node3D.new()
	# Sprint 28trigesies : etait 1.5 - trop proche des armes 1 main, signale
	# par l'utilisateur ("beaucoup plus grosses"). 2.3 donne une difference de
	# taille nettement plus lisible, cohérente avec une arme tenue a 2 mains.
	var scale_factor: float = 2.3 if two_handed else 1.0

	# Sprint 28octovicies : longueur de manche desormais PAR TYPE (avant,
	# une seule valeur pour toutes les armes) - la masse avait l'air "cassee"
	# (manche beaucoup trop court par rapport a la grosse tete), signale par
	# l'utilisateur ; corrige avec un manche nettement plus long, adapte a une
	# arme tenue a deux mains sur le manche.
	var handle_length_base: float = 0.22
	match kind:
		"Masse":
			handle_length_base = 0.42
		"Hache":
			handle_length_base = 0.34  # etait 0.30, legere augmentation (voir aussi la lame ci-dessous)
		_:  # "Epee"
			handle_length_base = 0.22
	var handle_length: float = handle_length_base * scale_factor

	# Sprint 28novovicies : la masse et la hache doivent etre tenues "au bout
	# du manche" (comme un vrai outil/arme d'impact, pour la portee/le levier
	# du coup), pas au milieu pres de la tete - signale par l'utilisateur
	# ("pas au niveau de la boule ou de la tete de hache"). L'origine du
	# groupe (0,0,0) est le point attache a la main (voir _attach_to_hand) :
	# pour Masse/Hache, elle correspond donc maintenant au BOUT BAS du manche
	# (handle_top = handle_length, la tete est tout en haut). L'epee garde le
	# grip au MILIEU du manche (handle_top = handle_length * 0.5, plus proche
	# d'une prise d'epee classique, entre garde et pommeau) - non concernee
	# par ce retour.
	var grip_at_bottom: bool = (kind == "Masse" or kind == "Hache")
	var handle_top: float = handle_length if grip_at_bottom else handle_length * 0.5
	var handle_center_y: float = handle_length * 0.5 if grip_at_bottom else 0.0

	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.02 * scale_factor
	handle_mesh.bottom_radius = 0.02 * scale_factor
	handle_mesh.height = handle_length
	handle.mesh = handle_mesh
	handle.position = Vector3(0, handle_center_y, 0)  # centre du manche - au-dessus du grip pour Masse/Hache, sur le grip pour Epee
	handle.name = "Handle"
	handle.set_surface_override_material(0, _flat_material(weapon_handle_color))
	group.add_child(handle)
	handle.owner = _edited_owner()

	match kind:
		"Masse":
			var head := MeshInstance3D.new()
			var head_mesh := SphereMesh.new()
			head_mesh.radius = 0.11 * scale_factor  # etait 0.06 - trop petite, signale par l'utilisateur
			head_mesh.height = head_mesh.radius * 2.0
			head.mesh = head_mesh
			head.position = Vector3(0, handle_top, 0)
			head.name = "Head"
			head.set_surface_override_material(0, _flat_material(weapon_color))
			group.add_child(head)
			head.owner = _edited_owner()
			# Petites "flanges" (fines boites autour de la tete) pour lire
			# clairement comme une masse d'armes plutot qu'une simple boule.
			for i in range(4):
				var flange := MeshInstance3D.new()
				var flange_mesh := BoxMesh.new()
				flange_mesh.size = Vector3(0.022 * scale_factor, 0.15 * scale_factor, 0.08 * scale_factor)
				flange.mesh = flange_mesh
				flange.position = Vector3(0, handle_top, 0)
				flange.rotation.y = deg_to_rad(i * 90.0)
				flange.name = "Flange_%d" % i
				flange.set_surface_override_material(0, _flat_material(weapon_color))
				group.add_child(flange)
				flange.owner = _edited_owner()
		"Hache":
			var blade := MeshInstance3D.new()
			var blade_mesh := BoxMesh.new()
			# Sprint 28quinsexagesies : la hache 1 main etait trop petite,
			# signale par l'utilisateur - lame nettement agrandie (etait 0.14,
			# 0.17, 0.02) et decalee un peu plus loin du manche pour rester
			# lisible a la nouvelle taille.
			blade_mesh.size = Vector3(0.20 * scale_factor, 0.25 * scale_factor, 0.03 * scale_factor)
			blade.mesh = blade_mesh
			blade.position = Vector3(0.09 * scale_factor, handle_top - 0.03, 0)
			blade.name = "Blade"
			blade.set_surface_override_material(0, _flat_material(weapon_color))
			group.add_child(blade)
			blade.owner = _edited_owner()
		_:  # "Epee"
			# Sprint 28sepsexagesies : epee 1 main jugee trop fine/courte -
			# lame allongee (0.52 -> 0.64) et epaissie (largeur 0.035 -> 0.05,
			# epaisseur 0.01 -> 0.018).
			var blade_length: float = 0.64 * scale_factor
			var blade := MeshInstance3D.new()
			var blade_mesh := BoxMesh.new()
			blade_mesh.size = Vector3(0.05 * scale_factor, blade_length, 0.018 * scale_factor)
			blade.mesh = blade_mesh
			blade.position = Vector3(0, handle_top + blade_length * 0.5, 0)
			blade.name = "Blade"
			blade.set_surface_override_material(0, _flat_material(weapon_color))
			group.add_child(blade)
			blade.owner = _edited_owner()

			var guard := MeshInstance3D.new()
			var guard_mesh := BoxMesh.new()
			guard_mesh.size = Vector3(0.13 * scale_factor, 0.025 * scale_factor, 0.03 * scale_factor)
			guard.mesh = guard_mesh
			guard.position = Vector3(0, handle_top, 0)
			guard.name = "Guard"
			guard.set_surface_override_material(0, _flat_material(weapon_color))
			group.add_child(guard)
			guard.owner = _edited_owner()

	return group


## Sprint 28quinvicies : construit un bouclier (Petit rond/Grand carre),
## origine au centre du bouclier, face avant tournee vers +Z par defaut
## (correspond a l'orientation "tenu devant soi" en position Combat).
func _make_shield_model(kind: String) -> Node3D:
	var group := Node3D.new()
	match kind:
		"Grand carre":
			var panel := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.42, 0.57, 0.04)  # +30% (etait 0.32, 0.44, 0.03), encore trop petit signale par l'utilisateur
			panel.mesh = mesh
			panel.name = "ShieldPanel"
			panel.set_surface_override_material(0, _flat_material(armor_color, true))
			group.add_child(panel)
			panel.owner = _edited_owner()
		_:  # "Petit rond"
			var panel := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.26  # +30% (etait 0.20)
			mesh.bottom_radius = 0.26
			mesh.height = 0.045
			panel.mesh = mesh
			panel.rotation.x = deg_to_rad(90.0)  # cylindre couche a plat -> disque face a +Z
			panel.name = "ShieldPanel"
			panel.set_surface_override_material(0, _flat_material(armor_color, true))
			group.add_child(panel)
			panel.owner = _edited_owner()

			var boss := MeshInstance3D.new()
			var boss_mesh := SphereMesh.new()
			boss_mesh.radius = 0.065
			boss_mesh.height = boss_mesh.radius * 2.0
			boss.mesh = boss_mesh
			boss.position = Vector3(0, 0, 0.033)
			boss.name = "ShieldBoss"
			boss.set_surface_override_material(0, _flat_material(weapon_color))
			group.add_child(boss)
			boss.owner = _edited_owner()

	return group


## Sprint 28quinvicies : construit une arme a distance (Arc/Arbalete), origine
## au centre de l'arme. "Arc" reutilise le meme principe de courbe que la
## bouche/les sourcils (_build_curve_segments), mais construit ici directement
## dans le groupe local (pas sur "self") pour que la courbe reste attachee/
## bouge avec l'arme lors du positionnement.
func _make_ranged_model(kind: String) -> Node3D:
	var group := Node3D.new()
	match kind:
		"Arbalete":
			var stock := MeshInstance3D.new()
			var stock_mesh := BoxMesh.new()
			stock_mesh.size = Vector3(0.025, 0.03, 0.32)
			stock.mesh = stock_mesh
			stock.position = Vector3(0, 0, 0.16)
			stock.name = "Stock"
			stock.set_surface_override_material(0, _flat_material(weapon_handle_color))
			group.add_child(stock)
			stock.owner = _edited_owner()

			var limb := MeshInstance3D.new()
			var limb_mesh := BoxMesh.new()
			limb_mesh.size = Vector3(0.34, 0.02, 0.02)
			limb.mesh = limb_mesh
			limb.position = Vector3(0, 0, 0.30)
			limb.name = "Limb"
			limb.set_surface_override_material(0, _flat_material(weapon_color))
			group.add_child(limb)
			limb.owner = _edited_owner()
		_:  # "Arc"
			# Sprint 28sepsexagesies : arc juge trop petit/fin, signale par
			# l'utilisateur - hauteur/courbure agrandies (0.34/0.06 -> 0.48/0.09)
			# et segments nettement plus epais (0.012 -> 0.022).
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
				seg.set_surface_override_material(0, _flat_material(weapon_handle_color))
				group.add_child(seg)
				seg.owner = _edited_owner()

	return group


## Sprint 28quinvicies : attache une arme/bouclier a la ceinture (position
## "Repos" pour une arme a une main) - couche a l'horizontale contre la
## hanche, cote determine par "side" (-1.0 = gauche, 1.0 = droite).
func _attach_to_belt(item: Node3D, side: float) -> void:
	var waist_w: float = torso_waist_width * corpulence
	item.position = Vector3(side * (waist_w * 0.5 + 0.05), leg_height + 0.05, 0.02)
	item.rotation.z = deg_to_rad(side * 100.0)  # couche contre la hanche, poignee vers le haut/l'avant
	item.name = "Weapon_Belt_%s" % ("L" if side < 0.0 else "R")
	add_child(item)
	item.owner = _edited_owner()


## Sprint 28quinvicies : attache une arme a 2 mains/bouclier/arme a distance
## dans le dos (position "Repos") - a la verticale, centree derriere le
## torse, legerement inclinee pour coller au dos.
func _attach_to_back(item: Node3D, _head_y: float) -> void:
	var depth: float = torso_depth * corpulence
	# Sprint 28quatersexagesies : attache remontee pres de l'epaule (etait
	# torso_height * 0.55, plus bas) - necessaire maintenant que la tete/lame
	# pointe vers le BAS (voir rotation.x plus bas) : la poignee doit rester
	# haute, pres de l'epaule, pour que la tete/lame ne traverse pas le sol en
	# pendant vers le bas du dos.
	item.position = Vector3(0, leg_height + torso_height * 0.85, -depth * 0.6 - 0.03)
	# Sprint 28quatersexagesies : "trop inclinee" + "inversee haut/bas"
	# demande par l'utilisateur (n°20 et grille suivante) - avant (Sprint
	# 28unsexagesies), rotation.x = -38 deg pointait la tete/lame vers le HAUT
	# et l'arriere (inclinaison prononcee, poignee vers le bas). -155 deg
	# inverse le sens (tete/lame vers le BAS, poignee vers le haut pres de
	# l'epaule - comme une arme glissee dans le dos, poignee accessible
	# par-dessus l'epaule) tout en restant surtout vertical (inclinaison
	# arriere plus discrete qu'avant).
	item.rotation.x = deg_to_rad(-155.0)
	item.name = "Weapon_Back"
	add_child(item)
	item.owner = _edited_owner()


## Sprint 28quinvicies : attache une arme/bouclier dans une main (position
## "Combat") - enfant direct du noeud Main (Hand_L/Hand_R, deja positionne au
## bout du pivot de bras, voir _build_arms), avec une legere orientation pour
## paraitre "empoignee" plutot que de pendre droit vers le bas. Un bouclier
## garde sa rotation neutre (deja face a +Z par construction, voir
## _make_shield_model).
func _attach_to_hand(item: Node3D, hand: Node3D, is_shield: bool) -> void:
	if not hand:
		return
	if not is_shield:
		# Sprint 28septvicies : le signe etait invers - le personnage fait face
		# a +Z (voir eye_z/nose/bouche dans _build_face, tous positifs), or
		# rotation.x = -70 deg envoie la lame vers -Z (l'arriere), signale par
		# l'utilisateur ("les armes pointent en arriere"). +70 deg envoie la
		# lame vers +Z (l'avant, cote visage) avec une legere inclinaison vers
		# le haut - corrige.
		item.rotation.x = deg_to_rad(70.0)
	else:
		# Sprint 28novovicies : leger decalage vers l'avant (+Z, cote visage)
		# pour que le bouclier se lise clairement comme "tenu devant soi" en
		# Combat, plutot que colle exactement au centre de la main (cote du
		# corps).
		item.position = Vector3(0, 0, 0.08)
	item.name = "Weapon_Hand_%s" % hand.name
	hand.add_child(item)
	item.owner = _edited_owner()


## Sprint 28trigesies : pose statique "tenue a deux mains" pour les armes 2
## mains en Combat - signale par l'utilisateur (une arme 2 mains doit etre
## tenue par les deux mains, pas juste posee dans la main droite). La main
## droite tient deja le grip (voir _attach_to_hand) ; on fait aussi pivoter
## le bras gauche pour l'amener pres du manche (desormais bien plus long,
## voir _make_weapon_model), comme si les deux mains le portaient ensemble.
## Premier jet approximatif (pas de cinematique inverse, valeurs ajustees a
## l'oeil) - a affiner apres verification visuelle dans Godot. Sans effet si
## preview_animation != "Aucune" : _process() recalcule alors les pivots de
## bras a chaque frame et prend le dessus (voir l'etat "Combat" de _process).
func _pose_two_handed_grip() -> void:
	if not (_arm_pivot_l and _arm_pivot_r):
		return
	_arm_pivot_r.rotation.x = deg_to_rad(-50.0)
	_arm_pivot_r.rotation.z = deg_to_rad(-8.0)
	_arm_pivot_l.rotation.x = deg_to_rad(-45.0)
	_arm_pivot_l.rotation.z = deg_to_rad(55.0)  # ramene la main gauche vers le manche, cote droit du corps


## Sprint 28untrigesies : pose statique "bras du bouclier" en Combat -
## signale par l'utilisateur : le bras gauche pendait droit le long du corps,
## donc le bouclier (attache a Hand_L, voir _attach_to_hand) se retrouvait
## fondu/enfonce dans le torse au lieu de ressortir devant. On leve le bras
## gauche vers l'avant (meme principe que _pose_two_handed_grip), pour que le
## bouclier se degage nettement du corps. Sans effet si preview_animation !=
## "Aucune" (voir _process, qui reprend la main sur les pivots de bras).
func _pose_shield_arm() -> void:
	if not _arm_pivot_l:
		return
	_arm_pivot_l.rotation.x = deg_to_rad(-72.0)  # etait -55, encore fondu dans le corps signale par l'utilisateur
	_arm_pivot_l.rotation.z = deg_to_rad(-12.0)  # legerement ecarte du corps


## Sprint 28octies : rayon (dans le plan XZ) de la surface ovale de la tete a
## un decalage vertical "dy" donne (relatif au centre de la tete) - permet de
## placer un element du visage exactement sur la surface (ou legerement
## au-dessus) sans deviner un facteur au hasard, meme si head_height_factor
## change la forme de la tete (sphere -> ovale plus ou moins prononce).
## Geometrie d'ellipsoide : a une hauteur donnee, le rayon horizontal restant
## est head_radius*sin(phi), ou phi est l'angle polaire correspondant.
func _head_surface_radius(dy: float) -> float:
	var half_height: float = head_radius * head_height_factor
	var cos_phi: float = clampf(dy / half_height, -1.0, 1.0)
	var sin_phi: float = sqrt(max(1.0 - cos_phi * cos_phi, 0.0))
	return head_radius * sin_phi


## Sprint 28quinquies : construit un tronc de piramide (base rectangulaire en
## haut, base rectangulaire differente en bas) - aucun mesh primitif de Godot
## ne fait ca directement (CylinderMesh permet bien un rayon different en
## haut/bas, mais uniquement pour une base ronde). Utilise pour le torse en
## "trapeze" (plus large aux epaules qu'a la taille).
func _make_trapezoid_mesh(size_top: Vector2, size_bottom: Vector2, height: float) -> ArrayMesh:
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

	_add_quad(st, bot_fl, bot_fr, top_fr, top_fl)  # face avant (+Z)
	_add_quad(st, bot_br, bot_bl, top_bl, top_br)  # face arriere (-Z)
	_add_quad(st, bot_bl, bot_fl, top_fl, top_bl)  # face gauche (-X)
	_add_quad(st, bot_fr, bot_br, top_br, top_fr)  # face droite (+X)
	_add_quad(st, top_fl, top_fr, top_br, top_bl)  # dessus (+Y)
	_add_quad(st, bot_fr, bot_fl, bot_bl, bot_br)  # dessous (-Y)

	st.generate_normals()
	return st.commit()


## Ajoute un quadrilatere (2 triangles) a un SurfaceTool en cours, a partir
## de 4 coins donnes dans l'ordre (peu importe le sens exact : le materiau
## du torse desactive le "cull_mode" pour rester visible des deux cotes,
## voir _build_torso, donc pas besoin de soigner le sens de rotation ici).
func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


## Materiau plat non eclaire, coherent avec le style du reste du jeu
## (terrain, arbres, decorations, outils - voir Forest.gd/_flat_material).
## "double_sided" desactive le retrait des faces arriere - utilise pour le
## torse (_make_trapezoid_mesh), dont le sens des triangles n'est pas
## garanti face par face.
func _flat_material(color: Color, double_sided: bool = false) -> StandardMaterial3D:
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
## a l'execution normale).
func _edited_owner() -> Node:
	if Engine.is_editor_hint():
		return get_tree().edited_scene_root
	return null
