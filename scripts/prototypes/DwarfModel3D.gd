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

## 2026-07-06 (revue de code, paquet E, M58 - etape 1/3) : les fonctions de
## construction/pose des armes ont ete extraites vers DwarfWeaponBuilder.gd
## (fichier source trop volumineux, ~2060 lignes) - voir _build_weapons()
## plus bas, desormais un simple relais. Aucun changement de comportement.
const DwarfWeaponBuilderScript := preload("res://scripts/prototypes/DwarfWeaponBuilder.gd")
## 2026-07-06 (revue de code, paquet E, M58 - etape 2/3) : meme demarche pour
## la tenue/armure (voir _build_outfit() plus bas, desormais un relais).
const DwarfOutfitBuilderScript := preload("res://scripts/prototypes/DwarfOutfitBuilder.gd")
## 2026-07-06 (revue de code, paquet E, M58 - etape 3/3, DERNIERE etape) :
## meme demarche pour les cheveux/la barbe (voir _build_hair()/_build_beard()
## plus bas, desormais des relais).
const DwarfHairBuilderScript := preload("res://scripts/prototypes/DwarfHairBuilder.gd")

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
	Color(0.60, 0.55, 0.47),  # gris - etait (0.55, 0.55, 0.57), un gris neutre trop proche des materiaux d'armes (voir DwarfWeaponBuilder.MATERIAL_COLORS, Fer/Acier), signale par l'utilisateur. Undertone chaud/brun ajoute pour se distinguer clairement du metal.
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
## choix de materiau (voir DwarfWeaponBuilder.MATERIAL_COLORS) - determine la
## couleur de la tete/lame (weapon_color, recalcule a chaque _build_weapons,
## voir DwarfWeaponBuilder.weapon_material_color()).
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
## 2026-07-06 (revue de code, paquet A) : flux GameRandom dedie
## "nains_apparence" au lieu de randi()/randf()/randf_range() globaux (idem
## dans _color_variant plus bas, meme flux) - voir GameRandom.gd.
func _randomize_variation() -> void:
	var rng: RandomNumberGenerator = GameRandom.get_rng("nains_apparence")
	var hair_styles := ["Chauve", "Court", "Attache", "Iroquois", "Touffu", "Frange basse", "Longs", "Tresse"]
	var beard_styles := ["Sans barbe", "Courte", "Longue", "Tressee", "Fournie", "Bouc", "Moustache", "Fourchue"]
	var outfit_styles := ["Tunique simple", "Tunique + cape", "Armure legere", "Armure lourde"]
	hair_style = hair_styles[rng.randi() % hair_styles.size()]
	beard_style = beard_styles[rng.randi() % beard_styles.size()]
	outfit_style = outfit_styles[rng.randi() % outfit_styles.size()]
	torso_shoulder_width = rng.randf_range(0.46, 0.68)
	corpulence = rng.randf_range(0.8, 1.3)
	beard_width = rng.randf_range(0.75, 1.15)  # etait (0.7, 1.4) - plage resserree, combinee aux top_radius de base reduits (voir _build_beard) pour eviter le "gros triangle" encore signale
	# Sprint 28duovicies : couleurs naturelles piochees independamment pour
	## cheveux et barbe (les sourcils suivent automatiquement, voir
	## _build_eyebrows qui derive brow_color de hair_color).
	hair_color = NATURAL_HAIR_COLORS[rng.randi() % NATURAL_HAIR_COLORS.size()]
	beard_color = NATURAL_HAIR_COLORS[rng.randi() % NATURAL_HAIR_COLORS.size()]

	# Sprint 28quinseptuagesies : theme d'habits aleatoire (gris/noir/vert/
	# rouge/bleu/marron, voir CLOTHING_THEMES) - chemise (clothing_color) et
	# pantalon (pants_color) sont derives independamment du MEME theme, avec
	# une petite variation chacun (voir _color_variant), pour rester
	# coordonnes sans etre identiques. Demande par l'utilisateur.
	var theme: Color = CLOTHING_THEMES[rng.randi() % CLOTHING_THEMES.size()]
	clothing_color = _color_variant(theme, 0.10)
	pants_color = _color_variant(theme, 0.10)
	coat_color = _color_variant(theme, 0.10)

	# Sprint 28sixseptuagesies : gants/manteau tires au hasard (probabilite
	# modeste, pas systematique - accessoires, pas la norme) pour que la
	# grille de verification (voir DwarfVariationGrid.gd) montre de la
	# variete sans que tous les nains en portent.
	wear_gloves = rng.randf() < 0.4
	wear_coat = rng.randf() < 0.35

	# Sprint 28triquatragesies : materiau d'arme aleatoire, demande par
	# l'utilisateur. Pioche uniquement parmi les 3 metaux (pas "Bois") : ca
	# garantit du meme coup que l'arc reste toujours en bois (il n'utilise
	# jamais weapon_color, voir _make_ranged_model - seulement
	# weapon_handle_color) et que l'arbalete reste toujours en metal (son
	# "Limb" utilise weapon_color, qui ne peut plus tomber sur "Bois"). "Bois"
	# reste choisissable a la main dans l'Inspecteur pour qui veut une arme de
	# corps-a-corps en bois (ex. arme d'entrainement), juste pas tire au sort.
	var weapon_materials := ["Cuivre", "Fer", "Acier"]
	weapon_material = weapon_materials[rng.randi() % weapon_materials.size()]

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
	weapon_loadout = weapon_loadouts[rng.randi() % weapon_loadouts.size()]
	weapon_type = weapon_types[rng.randi() % weapon_types.size()]
	shield_type = shield_types[rng.randi() % shield_types.size()]
	ranged_type = ranged_types[rng.randi() % ranged_types.size()]
	weapon_pose = weapon_poses[rng.randi() % weapon_poses.size()]


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
	# 2026-07-06 (revue de code, paquet D, M59) : instrumentation de perf
	# conditionnee a OS.is_debug_build() - diagnostic abandonne (cause exacte
	# jamais trouvee, voir commentaire de _build_model() plus bas) mais garde
	# au cas ou, sans polluer un export final.
	if OS.is_debug_build():
		print("[Perf][DwarfModel3D] nettoyage de %d enfant(s) precedent(s) : %.3f s" % [_child_count, (_t1 - _t0) / 1000.0])
	_build_model()
	var _t2: int = Time.get_ticks_msec()
	if OS.is_debug_build():
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
	if dt > 5 and OS.is_debug_build():
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
		_build_one_arm(side, shoulder_y, arm_x_offset, limb_factor)


## 2026-07-06 (revue de code, paquet E, I63) : extrait de _build_arms() - un
## seul cote (gauche ou droit, "side" -1.0/1.0), aucun changement de
## comportement. Assigne directement _arm_pivot_l/_arm_pivot_r/_hand_l/
## _hand_r (variables du script), comme le faisait le corps de boucle avant.
func _build_one_arm(side: float, shoulder_y: float, arm_x_offset: float, limb_factor: float) -> void:
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


## 2026-07-06 (revue de code, paquet E, M58 - etape 3/3) : "_hair_color_variant"
## a demenage vers DwarfHairBuilder.gd (n'avait aucun autre appelant). Cette
## fonction-ci reste ici : encore utilisee par _randomize_variation()
## ci-dessous pour les themes d'habits (pas concernee par l'extraction
## cheveux/barbe) - copie identique disponible en tant que
## Model3DUtils.color_variant() pour DwarfHairBuilder.gd.
## Sprint 28quinseptuagesies : jitter generique (facteur ajustable) de
## couleur (+/-jitter par canal, clampe 0-1).
func _color_variant(base: Color, jitter: float) -> Color:
	var rng: RandomNumberGenerator = GameRandom.get_rng("nains_apparence")
	return Color(
		clampf(base.r * rng.randf_range(1.0 - jitter, 1.0 + jitter), 0.0, 1.0),
		clampf(base.g * rng.randf_range(1.0 - jitter, 1.0 + jitter), 0.0, 1.0),
		clampf(base.b * rng.randf_range(1.0 - jitter, 1.0 + jitter), 0.0, 1.0)
	)


## 2026-07-06 (revue de code, paquet E, M58 - etape 3/3, DERNIERE etape) :
## cheveux/barbe extraits vers DwarfHairBuilder.gd (15 fonctions - voir ce
## fichier pour le detail complet, y compris tous les commentaires Sprint
## d'origine). Simples relais, aucun changement de comportement.
func _build_hair(head_y: float) -> void:
	DwarfHairBuilderScript.build_hair(self, self, head_y)


func _build_beard(head_y: float) -> void:
	DwarfHairBuilderScript.build_beard(self, self, head_y)


## Yeux, nez et bouche sur l'avant de la tete (+Z, meme cote que la barbe).
## La bouche est volontairement basse - une bonne partie disparait derriere
## la barbe, comme sur un vrai nain barbu.
func _build_face(head_y: float) -> void:
	for side in [-1.0, 1.0]:
		_build_one_eye(side, head_y)
	_build_nose(head_y)
	_build_mouth(head_y)
	_build_eyebrows(head_y)


## 2026-07-06 (revue de code, paquet E, I63) : extrait de _build_face() - un
## seul oeil (blanc + pupille), aucun changement de comportement.
## Sprint 28terdecies : la rotation Y tentee au sprint precedent (pour
## suivre la courbure de la tete) a en fait CAUSE le strabisme divergent
## (elle a fait deriver la pupille vers la tempe, via out_dir qui a une
## composante X). Retour a une version simple sans rotation : le blanc
## et la pupille partagent exactement le meme eye_x/eye_y (aucun autre
## decalage lateral), donc centree par construction ; seul un leger
## decalage vers l'avant en Z (pas de composante X) fait ressortir la
## pupille devant le blanc aplati.
func _build_one_eye(side: float, head_y: float) -> void:
	var side_name: String = "L" if side < 0.0 else "R"
	var eye_x: float = side * head_radius * 0.38
	var eye_y: float = head_y + head_radius * 0.12
	var eye_z: float = head_radius * 0.90

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


## 2026-07-06 (revue de code, paquet E, I63) : extrait de _build_face(),
## aucun changement de comportement.
func _build_nose(head_y: float) -> void:
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
## 2026-07-06 (revue de code, paquet E, M58 - etape 2/3) : tenue/armure
## extraite vers DwarfOutfitBuilder.gd (9 fonctions - voir ce fichier pour le
## detail complet, y compris tous les commentaires Sprint d'origine). Simples
## relais, aucun changement de comportement.
func _build_outfit(head_y: float) -> void:
	DwarfOutfitBuilderScript.build_outfit(self, self, head_y)


func _build_coat() -> void:
	DwarfOutfitBuilderScript.build_coat(self, self)


func _build_gloves() -> void:
	DwarfOutfitBuilderScript.build_gloves(self, _hand_l, _hand_r)


## 2026-07-06 (revue de code, paquet E, M58 - etape 1/3) : construction/pose
## des armes extraite vers DwarfWeaponBuilder.gd (23 fonctions - voir ce
## fichier pour le detail complet, y compris tous les commentaires Sprint
## d'origine). Simple relais, aucun changement de comportement : "self" est
## passe a la fois comme "model" (source des champs d'apparence/armes) et
## comme "parent" (noeud auquel accrocher les armes en position Repos).
func _build_weapons(head_y: float) -> void:
	DwarfWeaponBuilderScript.build_weapons(self, self, _hand_l, _hand_r, _arm_pivot_l, _arm_pivot_r, head_y)


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
