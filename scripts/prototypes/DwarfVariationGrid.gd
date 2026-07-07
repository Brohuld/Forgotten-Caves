@tool
extends Node3D
## Grille de demonstration - genere plusieurs DwarfModel3D
## (scripts/prototypes/DwarfModel3D.gd) avec des variations aleatoires
## INDEPENDANTES chacune, cote a cote dans une grille, pour comparer d'un
## coup plusieurs nains sans avoir a cliquer "Randomiser" un par un dans
## l'Inspecteur.
##
## Outil de verification UNIFIE : mode par defaut "Verification complete" :
## grille 6x6 (36 nains), chacun entierement randomise (apparence + armes +
## materiau, voir DwarfModel3D._randomize_variation), et chaque COLONNE joue
## une animation differente parmi les 6 disponibles (voir ANIM_STATES) - vue
## d'ensemble en un seul chargement de scene.
##
## Ne duplique aucune logique de forme : chaque case de la grille est une
## vraie instance de DwarfModel3D (meme script), a qui on appelle directement
## _randomize_variation() puis _rebuild() (GDScript n'a pas de vraie
## visibilite privee malgre le prefixe "_", donc c'est autorise depuis un
## autre script).
##
## Scene associee : scenes/prototypes/DwarfVariationGridPrototype.tscn -
## aucun fichier du jeu principal ni du prototype DwarfModel3D existant n'est
## modifie par ce fichier.

const DwarfModel3DScript := preload("res://scripts/prototypes/DwarfModel3D.gd")

## Les 6 valeurs possibles de preview_animation (voir DwarfModel3D.gd) -
## utilisees en mode "Verification complete" pour assigner une animation
## differente a chaque COLONNE de la grille (voir _regenerate), afin de voir
## toutes les actions jouer en meme temps sur des nains varies.
const ANIM_STATES := ["Aucune", "Marche", "Travail", "Combat", "Manger", "Dormir"]

## 9 configurations d'armes fixes (pas aleatoires) - couvrent les 5
## categories (1 main / 2 mains / 1 main + bouclier / deux armes 1 main /
## distance), en Repos ET en Combat quand la categorie le permet (8 cases),
## plus l'arme a distance en Repos pour la 9e case. Utilisee par
## _apply_weapon_demo() quand grid_mode = "Demonstration armes".
const WEAPON_DEMO_CONFIGS := [
	{"desc": "1 main - Repos", "weapon_loadout": "1 main", "weapon_type": "Epee", "weapon_pose": "Repos"},
	{"desc": "1 main - Combat", "weapon_loadout": "1 main", "weapon_type": "Epee", "weapon_pose": "Combat"},
	{"desc": "2 mains - Repos", "weapon_loadout": "2 mains", "weapon_type": "Hache", "weapon_pose": "Repos"},
	{"desc": "2 mains - Combat", "weapon_loadout": "2 mains", "weapon_type": "Hache", "weapon_pose": "Combat"},
	{"desc": "1 main + bouclier - Repos", "weapon_loadout": "1 main + bouclier", "weapon_type": "Epee", "shield_type": "Petit rond", "weapon_pose": "Repos"},
	{"desc": "1 main + bouclier - Combat", "weapon_loadout": "1 main + bouclier", "weapon_type": "Epee", "shield_type": "Grand carre", "weapon_pose": "Combat"},
	{"desc": "Deux armes 1 main - Repos", "weapon_loadout": "Deux armes 1 main", "weapon_type": "Masse", "weapon_pose": "Repos"},
	{"desc": "Deux armes 1 main - Combat", "weapon_loadout": "Deux armes 1 main", "weapon_type": "Masse", "weapon_pose": "Combat"},
	{"desc": "Distance (Arc) - Repos", "weapon_loadout": "Distance", "ranged_type": "Arc", "weapon_pose": "Repos"},
]

@export_group("Grille")
## "Variations aleatoires" : un nain randomise par case (apparence + armes,
## voir DwarfModel3D._randomize_variation). "Demonstration armes" : les 9
## premieres cases affichent les 9 configurations d'armes fixes de
## WEAPON_DEMO_CONFIGS ci-dessous. "Verification complete" (defaut) : unifie
## les deux modes precedents en un seul outil de verification - CHAQUE case
## est entierement randomisee (apparence + armes + materiau) ET chaque
## COLONNE joue une animation differente parmi les 6 de ANIM_STATES (Aucune/
## Marche/Travail/Combat/Manger/Dormir), pour voir a la fois la variete des
## tirages et toutes les actions d'animation en meme temps. Pensee pour une
## grille 6x6 (36 = 6 variations x 6 animations par colonne), voir
## grid_columns/grid_rows par defaut plus bas.
@export_enum("Variations aleatoires", "Demonstration armes", "Verification complete") var grid_mode: String = "Verification complete"
@export var grid_columns: int = 6
@export var grid_rows: int = 6
@export var spacing: float = 2.0  # les armes 2 mains/boucliers sont assez grosses pour necessiter cet espacement
@export var label_height: float = 1.3  # hauteur du numero flottant au-dessus de chaque nain

@export_group("Debug")
## Coche cette case (elle se decoche toute seule) pour regenerer toute la
## grille avec de nouvelles variations aleatoires.
@export var regenerate_in_editor: bool = false:
	set(value):
		regenerate_in_editor = false
		_regenerate()


func _ready() -> void:
	_regenerate()


## Supprime l'ancienne grille (s'il y en a une) et en reconstruit une
## nouvelle : une instance de DwarfModel3D par case, chacune randomisee
## independamment des autres, avec un numero flottant au-dessus (pour
## pouvoir dire "le numero 5 a tel probleme" sans ambiguite).
func _regenerate() -> void:
	# child.free() (liberation IMMEDIATE) est un choix volontaire ici, pas un
	# oubli de queue_free() - necessaire pour repeupler la grille tout de
	# suite dans la meme fonction sans doublons visibles a la frame suivante
	# (contrairement a Forest.gd/BerryBushes.gd, qui utilisent queue_free()
	# car rien ne repeuple leur zone dans la meme frame). Aucune reference
	# externe n'est conservee vers ces enfants. Ne pas "corriger" vers
	# queue_free() sans revoir cette raison - ca reintroduirait un flash de
	# doublons.
	for child in get_children():
		remove_child(child)
		child.free()

	var index := 0
	for row in range(grid_rows):
		for col in range(grid_columns):
			index += 1
			var x: float = (float(col) - (float(grid_columns) - 1.0) * 0.5) * spacing
			var z: float = (float(row) - (float(grid_rows) - 1.0) * 0.5) * spacing

			var dwarf := Node3D.new()
			dwarf.set_script(DwarfModel3DScript)
			dwarf.name = "Dwarf_%d" % index
			dwarf.position = Vector3(x, 0, z)
			add_child(dwarf)
			dwarf.owner = _edited_owner()
			# La randomisation/reconstruction finale se fait explicitement ici
			# (le _ready() interne de DwarfModel3D, declenche par add_child,
			# construit deja un modele "par defaut" au passage - sans
			# consequence, juste un petit calcul en plus, aussitot remplace).
			var label_text: String = str(index)
			var font_size := 96
			match grid_mode:
				"Demonstration armes":
					label_text = _apply_weapon_demo(dwarf, index)
					font_size = 48
				"Verification complete":
					# Tirage complet (apparence + armes, voir
					# DwarfModel3D._randomize_variation) PUIS l'animation est
					# forcee selon la colonne (pas laissee au hasard), pour
					# garantir que chaque colonne montre bien une action
					# differente plutot que de dependre du tirage.
					dwarf._randomize_variation()
					var anim: String = ANIM_STATES[col % ANIM_STATES.size()]
					dwarf.preview_animation = anim
					label_text = "%d - %s" % [index, anim]
					font_size = 40
				_:  # "Variations aleatoires"
					dwarf._randomize_variation()
			dwarf._rebuild()

			var label := Label3D.new()
			label.text = label_text
			label.font_size = font_size
			label.outline_size = 10
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.position = Vector3(x, label_height, z)
			label.name = "Label_%d" % index
			add_child(label)
			label.owner = _edited_owner()


## Applique la configuration d'armes n°"index" (voir WEAPON_DEMO_CONFIGS plus
## haut) sur l'instance "dwarf" donnee. Les champs d'armes de DwarfModel3D
## (weapon_loadout/weapon_type/shield_type/ranged_type/weapon_pose) sont des
## variables @export publiques (le prefixe "_" de ce script n'existe que sur
## ses propres methodes), donc modifiables directement depuis ici avant
## d'appeler _rebuild(). Retourne le texte a afficher sous le modele (numero
## + description courte de la config).
func _apply_weapon_demo(dwarf: Node3D, index: int) -> String:
	if index > WEAPON_DEMO_CONFIGS.size():
		# La grille peut etre configuree avec plus de cases que
		# WEAPON_DEMO_CONFIGS n'a d'entrees en mode "Demonstration armes" -
		# avertit plutot que de renvoyer silencieusement un simple numero
		# sans description.
		push_warning("DwarfVariationGrid._apply_weapon_demo : index %d depasse WEAPON_DEMO_CONFIGS (%d configs) - grille configuree trop grande pour ce mode." % [index, WEAPON_DEMO_CONFIGS.size()])
		return str(index)
	var cfg: Dictionary = WEAPON_DEMO_CONFIGS[index - 1]
	dwarf.weapon_loadout = cfg.get("weapon_loadout", "Aucune")
	dwarf.weapon_type = cfg.get("weapon_type", "Epee")
	dwarf.shield_type = cfg.get("shield_type", "Petit rond")
	dwarf.ranged_type = cfg.get("ranged_type", "Arc")
	dwarf.weapon_pose = cfg.get("weapon_pose", "Repos")
	return "%d - %s" % [index, cfg.get("desc", "")]


## Meme technique que DwarfModel3D._edited_owner() : necessaire pour que les
## noeuds generes en @tool apparaissent/persistent dans le panneau Scene.
func _edited_owner() -> Node:
	if Engine.is_editor_hint():
		return get_tree().edited_scene_root
	return null
